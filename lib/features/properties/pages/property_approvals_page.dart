import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_permissions.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/property_service.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/property_change_request.dart';
import '../services/property_approval_service.dart';
import '../widgets/approval_action_sheets.dart';
import '../widgets/approval_actions_sheet.dart';
import '../widgets/approval_filters_sheet.dart';
import '../widgets/approval_info_sheets.dart';
import '../widgets/approval_owner_auth_sheet.dart';
import '../widgets/approval_property_card.dart';
import '../widgets/change_request_card.dart';

/// Tela de **Fila de Aprovação de Imóveis**.
///
/// Identidade visual **flush** alinhada ao DNA do app:
/// - Padding página `_kPagePadH=16 / top=10 / bottom=88`, conteúdo encostado nas
///   margens, sem glows/painéis.
/// - Greeting com ícone gradiente + eyebrow `letterSpacing 2.2` + título grande;
///   alerta de recusados como chip estático (sem animação).
/// - **Navegação em abas flush fixas com sublinhado** (sem scroll horizontal;
///   mesmo DNA de Documentos/Chaves) — cada fila ocupa fração igual da largura,
///   indicador na cor da fila ativa e filete inferior de largura total.
/// - Filas da empresa (disponibilidade/publicação/proprietário/recusados)
///   aparecem para quem tem qualquer permissão de aprovação ou bypass de
///   master/admin/manager (`approvalQueueMenu`).
/// - Cabeçalho de painel com ícone tonal achatado + eyebrow com bolinha.
/// - Itens são **linhas flush** (`ApprovalPropertyCard`) — thumbnail grande com
///   código abaixo, sem faixa lateral; aprovar/recusar no próprio card para quem
///   tem permissão nas filas de disponibilidade/publicação.
class PropertyApprovalsPage extends StatefulWidget {
  const PropertyApprovalsPage({super.key});

  @override
  State<PropertyApprovalsPage> createState() => _PropertyApprovalsPageState();
}

enum _Tab { mine, ownerAuth, availability, publication, rejected, editRequests }

class _PropertyApprovalsPageState extends State<PropertyApprovalsPage> {
  static const double _kSectionGap = 12;
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const int _kRejectedPageSize = 10;

  /// Piso de largura por aba: abaixo disso o rótulo ficaria ilegível, então a
  /// barra rola em vez de espremer.
  static const double _kMinTabWidth = 58;

  late final ModuleAccessService _moduleAccess = ModuleAccessService.instance;

  /// Pode ver as filas da empresa (disponibilidade/publicação/proprietário/
  /// recusados). Espelha o gating do web (`approvalQueueMenu`) e respeita o
  /// bypass de master/admin/manager do [ModuleAccessService]. É um getter
  /// (não `late final`) para reavaliar quando as permissões/role chegam depois
  /// do `initState` — antes ficava preso em `false` por uma corrida de timing.
  bool get _canViewQueues =>
      _moduleAccess.hasAnyPermission(AppPermissions.approvalQueueMenu);

  // Estado por aba. Cada erro carrega o código HTTP que o originou: sem ele
  // "sem permissão na fila" e "servidor fora do ar" chegariam na tela com a
  // mesma frase, e o usuário insistiria num botão que nunca vai funcionar.
  bool _loadingMine = false;
  String? _errorMine;
  int _errorStatusMine = 0;
  MyPendingResponse _myPending = MyPendingResponse.empty;

  bool _loadingAvailability = false;
  String? _errorAvailability;
  int _errorStatusAvailability = 0;
  List<Property> _pendingAvailability = const [];

  bool _loadingPublication = false;
  String? _errorPublication;
  int _errorStatusPublication = 0;
  List<Property> _pendingPublication = const [];

  bool _loadingOwner = false;
  String? _errorOwner;
  int _errorStatusOwner = 0;
  List<Property> _pendingOwner = const [];

  bool _loadingRejectedAvail = false;
  bool _loadingRejectedPub = false;
  String? _errorRejected;
  int _errorStatusRejected = 0;
  RejectedListResponse _rejectedAvail = RejectedListResponse.empty;
  RejectedListResponse _rejectedPub = RejectedListResponse.empty;
  RejectedCounts _rejectedCounts = RejectedCounts.zero;

  // Aba "Edições" — solicitações de alteração de campos protegidos.
  bool _loadingEditRequests = false;
  String? _errorEditRequests;
  int _errorStatusEditRequests = 0;
  PropertyChangeRequestList _editRequests = PropertyChangeRequestList.empty;
  PropertyChangeRequestStatus? _editRequestsFilter =
      PropertyChangeRequestStatus.pending;

  /// Configuração de aprovação da empresa — decide marca d'água na publicação,
  /// bifurcação para votação (multi-aprovadores), exigência de assinatura do
  /// proprietário e se a esteira de campos protegidos está ligada.
  PropertyApprovalSettingsActive _settings =
      const PropertyApprovalSettingsActive();

  _Tab _activeTab = _Tab.mine;

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _appliedSearch = '';
  bool _searchFocused = false;

  /// Filtros granulares (responsável, código, título, proprietário). A busca
  /// global do topo tem prioridade sobre eles — quem impõe essa regra é o
  /// [ApprovalListFilters.toQueryParams], em paridade com o web.
  ApprovalListFilters _advanced = ApprovalListFilters.empty;

  /// Exportação em curso (job assíncrono): trava o botão e mostra progresso.
  bool _exporting = false;

  bool _didLoadQueues = false;

  @override
  void initState() {
    super.initState();
    // Reage quando permissões/role chegam depois do login (ChangeNotifier):
    // recarrega as filas e reconstrói as abas.
    _moduleAccess.addListener(_onAccessChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    _moduleAccess.removeListener(_onAccessChanged);
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onAccessChanged() {
    if (!mounted) return;
    // Só dispara recarga das filas quando o acesso passou a existir e ainda
    // não carregamos — evita loops e trabalho redundante.
    if (_canViewQueues && !_didLoadQueues) {
      _refreshAll();
    }
    setState(() {});
  }

  Future<void> _bootstrap() async {
    await _refreshAll();
  }

  Future<void> _refreshAll() {
    final canView = _canViewQueues;
    if (canView) _didLoadQueues = true;
    return Future.wait([
      _loadSettings(),
      _loadMine(),
      // A esteira de edições é escopada no backend (revisores veem tudo, os
      // demais só as próprias), então a aba existe para qualquer usuário.
      _loadEditRequests(),
      if (canView) ...[
        _loadAvailability(),
        _loadPublication(),
        _loadOwnerAuth(),
        _loadRejected(),
      ],
    ]);
  }

  Future<void> _loadSettings() async {
    final res =
        await PropertyService.instance.getPropertyApprovalSettingsActive();
    if (!mounted) return;
    if (res.success && res.data != null) {
      setState(() => _settings = res.data!);
    }
  }

  Future<void> _loadEditRequests() async {
    setState(() {
      _loadingEditRequests = true;
      _errorEditRequests = null;
      _errorStatusEditRequests = 0;
    });
    final res = await PropertyApprovalService.instance.listChangeRequests(
      status: _editRequestsFilter,
    );
    if (!mounted) return;
    setState(() {
      _loadingEditRequests = false;
      if (res.success && res.data != null) {
        _editRequests = res.data!;
        _errorEditRequests = null;
        _errorStatusEditRequests = 0;
      } else {
        _errorEditRequests =
            res.message ?? 'Erro ao carregar solicitações de edição';
        _errorStatusEditRequests = res.statusCode;
      }
    });
  }

  ApprovalListFilters _filters() => ApprovalListFilters(
        search: _appliedSearch,
        responsibleName: _advanced.responsibleName,
        propertyCode: _advanced.propertyCode,
        propertyTitle: _advanced.propertyTitle,
        ownerName: _advanced.ownerName,
        teamId: _advanced.teamId,
        responsibleUserId: _advanced.responsibleUserId,
      );

  /// Quantos filtros granulares estão ativos (alimenta o badge do botão).
  int get _advancedCount => [
        _advanced.responsibleName,
        _advanced.propertyCode,
        _advanced.propertyTitle,
        _advanced.ownerName,
        _advanced.teamId,
        _advanced.responsibleUserId,
      ].where((v) => (v ?? '').trim().isNotEmpty).length;

  void _selectTab(_Tab tab) {
    if (tab == _activeTab) return;
    setState(() => _activeTab = tab);
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final v = value.trim();
      if (v == _appliedSearch) return;
      setState(() => _appliedSearch = v);
      _refreshAll();
    });
  }

  // ─── Loaders ───────────────────────────────────────────────────────────

  Future<void> _loadMine() async {
    setState(() {
      _loadingMine = true;
      _errorMine = null;
      _errorStatusMine = 0;
    });
    final res = await PropertyApprovalService.instance.getMyPending(
      filters: _filters(),
    );
    if (!mounted) return;
    setState(() {
      _loadingMine = false;
      if (res.success && res.data != null) {
        _myPending = res.data!;
        _errorMine = null;
        _errorStatusMine = 0;
      } else {
        _errorMine = res.message ?? 'Erro ao carregar suas pendências';
        _errorStatusMine = res.statusCode;
      }
    });
  }

  Future<void> _loadAvailability() async {
    setState(() {
      _loadingAvailability = true;
      _errorAvailability = null;
      _errorStatusAvailability = 0;
    });
    final res =
        await PropertyApprovalService.instance.getPendingAvailability(
      filters: _filters(),
    );
    if (!mounted) return;
    setState(() {
      _loadingAvailability = false;
      if (res.success && res.data != null) {
        _pendingAvailability = res.data!;
        _errorAvailability = null;
        _errorStatusAvailability = 0;
      } else {
        _errorAvailability =
            res.message ?? 'Erro ao carregar fila de disponibilidade';
        _errorStatusAvailability = res.statusCode;
      }
    });
  }

  Future<void> _loadPublication() async {
    setState(() {
      _loadingPublication = true;
      _errorPublication = null;
      _errorStatusPublication = 0;
    });
    final res = await PropertyApprovalService.instance.getPendingPublication(
      filters: _filters(),
    );
    if (!mounted) return;
    setState(() {
      _loadingPublication = false;
      if (res.success && res.data != null) {
        _pendingPublication = res.data!;
        _errorPublication = null;
        _errorStatusPublication = 0;
      } else {
        _errorPublication =
            res.message ?? 'Erro ao carregar fila de publicação';
        _errorStatusPublication = res.statusCode;
      }
    });
  }

  Future<void> _loadOwnerAuth() async {
    setState(() {
      _loadingOwner = true;
      _errorOwner = null;
      _errorStatusOwner = 0;
    });
    final res = await PropertyApprovalService.instance
        .getPendingOwnerAuthorization(filters: _filters());
    if (!mounted) return;
    setState(() {
      _loadingOwner = false;
      if (res.success && res.data != null) {
        _pendingOwner = res.data!;
        _errorOwner = null;
        _errorStatusOwner = 0;
      } else {
        _errorOwner = res.message ?? 'Erro ao carregar autorizações';
        _errorStatusOwner = res.statusCode;
      }
    });
  }

  Future<void> _loadRejected({int page = 1}) async {
    setState(() {
      _loadingRejectedAvail = true;
      _loadingRejectedPub = true;
      _errorRejected = null;
      _errorStatusRejected = 0;
    });
    final svc = PropertyApprovalService.instance;
    final results = await Future.wait([
      svc.getRejectedAvailability(
        filters: _filters(),
        page: page,
        limit: _kRejectedPageSize,
      ),
      svc.getRejectedPublication(
        filters: _filters(),
        page: page,
        limit: _kRejectedPageSize,
      ),
      svc.getRejectedCounts(filters: _filters()),
    ]);
    if (!mounted) return;
    setState(() {
      _loadingRejectedAvail = false;
      _loadingRejectedPub = false;
      final r0 = results[0];
      final r1 = results[1];
      final r2 = results[2];
      if (r0.success && r0.data != null) {
        _rejectedAvail = r0.data! as RejectedListResponse;
      } else if (r0.message != null) {
        _errorRejected = r0.message;
        _errorStatusRejected = r0.statusCode;
      }
      if (r1.success && r1.data != null) {
        _rejectedPub = r1.data! as RejectedListResponse;
      } else if (r1.message != null) {
        if (_errorRejected == null) {
          _errorRejected = r1.message;
          _errorStatusRejected = r1.statusCode;
        }
      }
      if (r2.success && r2.data != null) {
        _rejectedCounts = r2.data! as RejectedCounts;
      }
    });
  }

  void _openDetails(Property p) {
    Navigator.of(context).pushNamed(AppRoutes.propertyDetails(p.id));
  }

  // ─── Ações de aprovar/recusar direto no card (gated por permissão) ────────

  bool get _canApproveAvailability => _moduleAccess
      .hasPermission(AppPermissions.propertyApproveAvailability);
  bool get _canRejectAvailability =>
      _moduleAccess.hasPermission(AppPermissions.propertyRejectAvailability);
  bool get _canApprovePublication => _moduleAccess
      .hasPermission(AppPermissions.propertyApprovePublication);
  bool get _canRejectPublication =>
      _moduleAccess.hasPermission(AppPermissions.propertyRejectPublication);
  bool get _canManageSettings => _moduleAccess
      .hasPermission(AppPermissions.propertyManageApprovalSettings);

  /// Espelha `canInvalidateOwnerSignature` do web: só faz sentido quando a
  /// empresa exige a autorização, e apenas para quem aprova/configura.
  bool get _canInvalidateOwnerSignature =>
      _settings.requireOwnerAuthorizationToBeAvailable &&
      (_canManageSettings ||
          _canApproveAvailability ||
          _canApprovePublication);

  /// Espelha `showIgnoreOwnerSignatureMenuItem(p)` do web: aprovador/gestão
  /// **ou** responsável/captador do próprio imóvel, e só com assinatura
  /// digital pendente.
  bool _canIgnoreOwnerSignature(Property p) {
    if (!_settings.requireOwnerAuthorizationToBeAvailable) return false;
    if ((p.ownerAuthStatus ?? '') != 'pending') return false;
    final uid = _moduleAccess.userId;
    final isLinked = uid != null &&
        uid.isNotEmpty &&
        (p.responsibleUserId == uid ||
            p.capturedById == uid ||
            (p.responsibleUserIds?.contains(uid) ?? false) ||
            (p.capturedByIds?.contains(uid) ?? false));
    final isApproverOrAdmin = _canApproveAvailability ||
        _canApprovePublication ||
        _canManageSettings;
    return isLinked || isApproverOrAdmin;
  }

  /// Só o responsável pode "cobrar" os aprovadores (mesma regra do web).
  bool _isResponsible(Property p) {
    final uid = _moduleAccess.userId;
    return uid != null && uid.isNotEmpty && p.responsibleUserId == uid;
  }

  void _actionSnack(String msg, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            ok ? AppColors.status.success : AppColors.status.error,
      ),
    );
  }

  /// Aprova o card conforme a fila. Retorna `true` em sucesso (para o card
  /// encerrar o estado de carregamento). Atualiza as listas no fim.
  Future<bool> _approveCard(Property p, ApprovalQueueKind kind) async {
    final svc = PropertyApprovalService.instance;
    final isPub = kind == ApprovalQueueKind.pendingPublication;
    bool? watermark;
    if (isPub && _settings.applyWatermarkToImages) {
      // Mesma bifurcação do web (`openApprovePublicationModal`): a empresa
      // com marca d'água ligada confirma antes de publicar.
      final choice = await showApprovePublicationSheet(
        context: context,
        propertyTitle: p.title.isEmpty ? (p.code ?? 'Imóvel') : p.title,
        watermarkConfigured: true,
      );
      if (choice == null) return false;
      watermark = choice.applyWatermark;
    }
    final res = isPub
        ? await svc.approvePublication(p.id, applyWatermark: watermark)
        : await svc.approveAvailability(p.id, applyWatermark: false);
    if (!mounted) return false;
    if (res.success) {
      _actionSnack(
        isPub
            ? 'Publicação aprovada — imóvel já está no site.'
            : 'Disponibilidade aprovada.',
        ok: true,
      );
      await _refreshAll();
      return true;
    }
    _actionSnack(res.message ?? 'Falha ao aprovar.');
    return false;
  }

  /// Coleta o motivo (obrigatório) e recusa o card conforme a fila.
  Future<bool> _rejectCard(Property p, ApprovalQueueKind kind) async {
    final isPub = kind == ApprovalQueueKind.pendingPublication;
    final reason = await showRejectReasonSheet(
      context: context,
      title: isPub ? 'Recusar publicação no site' : 'Recusar disponibilidade',
      propertySubtitle: p.title.isEmpty ? p.code : p.title,
    );
    if (reason == null) return false;
    final svc = PropertyApprovalService.instance;
    final res = isPub
        ? await svc.rejectPublication(p.id, reason: reason)
        : await svc.rejectAvailability(p.id, reason: reason);
    if (!mounted) return false;
    if (res.success) {
      _actionSnack('Imóvel recusado. Responsável foi notificado.', ok: true);
      await _refreshAll();
      return true;
    }
    _actionSnack(res.message ?? 'Falha ao recusar.');
    return false;
  }

  // ─── Reenvio / votação ────────────────────────────────────────────────

  /// Fila a que o item pertence, para os endpoints que exigem `approvalType`.
  ApprovalType _queueOf(ApprovalQueueKind kind) {
    switch (kind) {
      case ApprovalQueueKind.myPublication:
      case ApprovalQueueKind.pendingPublication:
      case ApprovalQueueKind.rejectedPublication:
        return ApprovalType.publication;
      case ApprovalQueueKind.myAvailability:
      case ApprovalQueueKind.myOwnerAuth:
      case ApprovalQueueKind.pendingAvailability:
      case ApprovalQueueKind.pendingOwnerAuth:
      case ApprovalQueueKind.rejectedAvailability:
        return ApprovalType.availability;
    }
  }

  bool _isPublicationQueue(ApprovalQueueKind kind) =>
      _queueOf(kind) == ApprovalType.publication;

  /// Item recusado aguardando correção — habilita o botão "Reenviar".
  bool _isRejectedWaitingResend(Property p, ApprovalQueueKind kind) {
    if (kind == ApprovalQueueKind.rejectedAvailability ||
        kind == ApprovalQueueKind.rejectedPublication) {
      return true;
    }
    if (_isPublicationQueue(kind)) {
      return (p.publicationRejectedAt ?? '').isNotEmpty;
    }
    return (p.availabilityRejectedAt ?? '').isNotEmpty;
  }

  /// Reenvia para nova análise. Aprovador usa a rota de revisão; responsável
  /// usa a rota `responsible/reopen-*` (não exige permissão de aprovação).
  Future<bool> _resendCard(Property p, ApprovalQueueKind kind) async {
    final svc = PropertyApprovalService.instance;
    final isPub = _isPublicationQueue(kind);
    final canReview = isPub ? _canApprovePublication : _canApproveAvailability;
    final res = isPub
        ? (canReview
            ? await svc.requestSitePublicationReview(p.id)
            : await svc.requestSitePublicationReviewAsResponsible(p.id))
        : (canReview
            ? await svc.requestAvailabilityReview(p.id)
            : await svc.requestAvailabilityReviewAsResponsible(p.id));
    if (!mounted) return false;
    if (res.success) {
      _actionSnack('Reenviado para nova aprovação.', ok: true);
      await _refreshAll();
      return true;
    }
    _actionSnack(res.message ?? 'Falha ao reenviar.');
    return false;
  }

  /// Voto na fila quando o multi-aprovadores está ligado.
  Future<bool> _voteCard(Property p, ApprovalQueueKind kind) async {
    final queue = _queueOf(kind);
    final result = await showApprovalVoteSheet(
      context: context,
      propertyId: p.id,
      propertyTitle: _propertyLabel(p),
      queue: queue,
      tone: _activeTabColor(context),
    );
    if (result == null || !mounted) return false;
    final res = await PropertyApprovalService.instance.castVote(
      p.id,
      type: queue,
      approved: result.approved,
      comment: result.comment,
    );
    if (!mounted) return false;
    if (res.success) {
      _actionSnack('Voto registrado.', ok: true);
      await _refreshAll();
      return true;
    }
    _actionSnack(res.message ?? 'Falha ao registrar o voto.');
    return false;
  }

  // ─── Menu de mais ações (3 pontinhos) ─────────────────────────────────

  String _propertyLabel(Property p) =>
      p.title.isNotEmpty ? p.title : (p.code ?? 'Imóvel sem título');

  /// Rótulo do estado da autorização exibido abaixo do título nas filas de
  /// proprietário — paridade com o `renderBelowTitle` do web.
  String? _ownerAuthNote(Property p) {
    final status = p.ownerAuthStatus ?? '';
    final sentAt = p.ownerAuthSentAt;
    switch (status) {
      case 'not_sent':
        return 'Não enviado';
      case 'physical_rejected':
        return 'Anexo recusado — ajuste e reenvie o documento';
      case 'pending_physical_validation':
        return sentAt == null || sentAt.isEmpty
            ? 'Anexo aguardando validação do aprovador'
            : 'Anexo enviado em ${_fmtDate(sentAt)} — aguardando validação';
      case 'pending':
        return sentAt == null || sentAt.isEmpty
            ? 'Aguardando assinatura do proprietário'
            : 'Enviado em ${_fmtDate(sentAt)} — aguardando assinatura';
      case 'signed':
        return 'Assinado pelo proprietário';
      default:
        return null;
    }
  }

  String _fmtDate(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    final l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/'
        '${l.month.toString().padLeft(2, '0')}/${l.year}';
  }

  /// Menu de "mais ações" do item — reúne, em uma folha só, o que o web
  /// espalha nos menus de 3 pontinhos de cada aba.
  Future<void> _openMoreActions(Property p, ApprovalQueueKind kind) async {
    final tone = _activeTabColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final warn = isDark
        ? AppColors.status.warningDarkMode
        : AppColors.status.warning;
    final purple =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    final queue = _queueOf(kind);
    final ownerStatus = p.ownerAuthStatus ?? '';
    final isOwnerAuthQueue = kind == ApprovalQueueKind.pendingOwnerAuth ||
        kind == ApprovalQueueKind.myOwnerAuth;
    final rejectedWaiting = _isRejectedWaitingResend(p, kind);
    final canActOnQueue = queue == ApprovalType.publication
        ? _canApprovePublication
        : _canApproveAvailability;

    final actions = <ApprovalMenuAction>[];

    // 1) Abrir a ficha — equivalente ao "abrir em nova aba" do desktop, que
    // no telefone vira navegação normal.
    actions.add(
      ApprovalMenuAction(
        icon: LucideIcons.externalLink,
        label: 'Abrir ficha do imóvel',
        hint: 'Ver dados, fotos e histórico completo.',
        onTap: () => _openDetails(p),
      ),
    );

    // 2) Conversa de aprovação (o painel embutido no card do web).
    actions.add(
      ApprovalMenuAction(
        icon: LucideIcons.messagesSquare,
        label: 'Conversa de aprovação',
        hint: 'Falar com o aprovador ou com o responsável.',
        tone: purple,
        onTap: () => showApprovalThreadSheet(
          context: context,
          propertyId: p.id,
          propertyTitle: _propertyLabel(p),
          queue: queue,
          tone: purple,
        ),
      ),
    );

    // 3) Fluxo da autorização do proprietário.
    if (isOwnerAuthQueue) {
      actions.add(
        ApprovalMenuAction(
          icon: LucideIcons.send,
          label: ownerStatus == 'pending_physical_validation'
              ? 'Substituir anexo'
              : ownerStatus == 'pending'
                  ? 'Enviar novamente'
                  : 'Enviar para assinatura',
          hint: 'Autorização de venda / contrato de agenciamento.',
          tone: purple,
          onTap: () => _sendOwnerAuthorization(p, ownerStatus),
        ),
      );
      if (_canApproveAvailability &&
          ownerStatus == 'pending_physical_validation') {
        actions.addAll([
          ApprovalMenuAction(
            icon: LucideIcons.eye,
            label: 'Ver anexo',
            hint: 'Abre o documento assinado em papel.',
            onTap: () => _openOwnerAuthPhysicalPreview(p),
          ),
          ApprovalMenuAction(
            icon: LucideIcons.badgeCheck,
            label: 'Validar assinatura física',
            hint: 'Libera o imóvel para a fila de aprovação.',
            tone: kApprovalGreen,
            onTap: () => _approveOwnerAuthPhysical(p),
          ),
          ApprovalMenuAction(
            icon: LucideIcons.ban,
            label: 'Recusar anexo',
            hint: 'O documento sai e o imóvel volta a aguardar autorização.',
            danger: true,
            onTap: () => _rejectOwnerAuthPhysical(p),
          ),
        ]);
      }
      if (ownerStatus == 'pending' && (p.canResendOwnerAuthEmail ?? false)) {
        actions.add(
          ApprovalMenuAction(
            icon: LucideIcons.mail,
            label: 'Reenviar por e-mail',
            hint: 'Manda o link de assinatura de novo ao proprietário.',
            tone: purple,
            onTap: () => _resendOwnerAuthEmail(p),
          ),
        );
      }
    }

    // 4) Cobrar aprovadores (só o responsável, e não em item recusado).
    if (!rejectedWaiting && _isResponsible(p) && !isOwnerAuthQueue) {
      actions.add(
        ApprovalMenuAction(
          icon: LucideIcons.bellRing,
          label: 'Cobrar aprovadores',
          hint: 'Envia um lembrete — vale uma vez por hora.',
          tone: warn,
          onTap: () => _remindApprovers(p, queue),
        ),
      );
    }

    // 5) Notificar responsáveis sobre contato com o proprietário — no web
    // aparece no item recusado para quem aprova aquela fila.
    if (rejectedWaiting && canActOnQueue) {
      actions.add(
        ApprovalMenuAction(
          icon: LucideIcons.contactRound,
          label: 'Notificar sobre contato do proprietário',
          hint: 'Avisa responsáveis e captadores — uma vez por hora.',
          tone: warn,
          onTap: () => _notifyOwnerContact(p, queue),
        ),
      );
    }

    // 6) Recusar direto pelo menu na fila de aprovação (sem multi-aprovadores).
    if (!_settings.approversEnabled && !rejectedWaiting && !isOwnerAuthQueue) {
      final canReject = queue == ApprovalType.publication
          ? _canRejectPublication
          : _canRejectAvailability;
      if (canReject &&
          (kind == ApprovalQueueKind.pendingAvailability ||
              kind == ApprovalQueueKind.pendingPublication)) {
        actions.add(
          ApprovalMenuAction(
            icon: LucideIcons.xCircle,
            label: 'Recusar',
            hint: 'Exige motivo — o responsável é notificado.',
            danger: true,
            onTap: () => _rejectCard(p, kind),
          ),
        );
      }
    }

    // 7) Dispensar / invalidar assinatura do proprietário.
    if (_canIgnoreOwnerSignature(p)) {
      actions.add(
        ApprovalMenuAction(
          icon: LucideIcons.penOff,
          label: 'Ignorar assinatura',
          hint: 'Avança o fluxo sem esperar a assinatura digital.',
          tone: warn,
          onTap: () => _ignoreOwnerSignature(p),
        ),
      );
    }
    if (_canInvalidateOwnerSignature &&
        (!isOwnerAuthQueue || ownerStatus == 'signed')) {
      actions.add(
        ApprovalMenuAction(
          icon: LucideIcons.unlink,
          label: 'Invalidar assinatura',
          hint: 'Apaga a assinatura e reinicia o fluxo do proprietário.',
          danger: true,
          onTap: () => _invalidateOwnerSignature(p),
        ),
      );
    }

    // 8) Histórico — o do envio na fila do proprietário, o do imóvel no resto.
    actions.add(
      ApprovalMenuAction(
        icon: LucideIcons.history,
        label: isOwnerAuthQueue ? 'Ver histórico de envios' : 'Ver histórico',
        hint: isOwnerAuthQueue
            ? 'Para quem foi enviado, quando e por quem.'
            : 'Linha do tempo do imóvel.',
        onTap: () => isOwnerAuthQueue
            ? showOwnerAuthSendHistorySheet(
                context: context,
                propertyId: p.id,
                propertyTitle: _propertyLabel(p),
                tone: purple,
              )
            : showPropertyHistorySheet(
                context: context,
                propertyId: p.id,
                propertyTitle: _propertyLabel(p),
                tone: tone,
              ),
      ),
    );

    if (!mounted) return;
    await showApprovalActionsSheet(
      context: context,
      eyebrow: _queueEyebrow(kind),
      title: _propertyLabel(p),
      subtitle: p.code == null || p.code!.isEmpty ? null : 'Cód. ${p.code}',
      tone: tone,
      icon: LucideIcons.listChecks,
      actions: actions,
    );
  }

  String _queueEyebrow(ApprovalQueueKind kind) {
    switch (kind) {
      case ApprovalQueueKind.myAvailability:
      case ApprovalQueueKind.pendingAvailability:
        return 'DISPONIBILIDADE';
      case ApprovalQueueKind.myPublication:
      case ApprovalQueueKind.pendingPublication:
        return 'PUBLICAÇÃO';
      case ApprovalQueueKind.myOwnerAuth:
      case ApprovalQueueKind.pendingOwnerAuth:
        return 'PROPRIETÁRIO';
      case ApprovalQueueKind.rejectedAvailability:
        return 'DISPONIBILIDADE RECUSADA';
      case ApprovalQueueKind.rejectedPublication:
        return 'PUBLICAÇÃO RECUSADA';
    }
  }

  // ─── Ações do menu ────────────────────────────────────────────────────

  /// Trata o cooldown de 1h (429) igual ao web: converte `retryAfterSeconds`
  /// em minutos na mensagem.
  void _cooldownSnack(String? message, dynamic errorBody, String verb) {
    int? retry;
    if (errorBody is Map) {
      final raw = errorBody['retryAfterSeconds'];
      if (raw is num) retry = raw.toInt();
      if (raw is String) retry = int.tryParse(raw);
    }
    if (retry != null) {
      final mins = (retry / 60).ceil().clamp(1, 999);
      _actionSnack('Aguarde cerca de $mins min para $verb novamente.');
      return;
    }
    _actionSnack(message ?? 'Aguarde 1 hora entre os envios.');
  }

  Future<void> _remindApprovers(Property p, ApprovalType queue) async {
    final res = await PropertyApprovalService.instance
        .remindApprovalApprovers(p.id, approvalType: queue);
    if (!mounted) return;
    if (res.success) {
      _actionSnack(
        res.data?['message']?.toString() ?? 'Aprovadores notificados.',
        ok: true,
      );
      return;
    }
    if (res.statusCode == 429) {
      _cooldownSnack(res.message, res.data, 'cobrar');
      return;
    }
    _actionSnack(res.message ?? 'Não foi possível enviar a cobrança.');
  }

  Future<void> _notifyOwnerContact(Property p, ApprovalType queue) async {
    final res = await PropertyApprovalService.instance
        .notifyResponsiblesOwnerContact(p.id, approvalType: queue);
    if (!mounted) return;
    if (res.success) {
      _actionSnack(
        res.data?['message']?.toString() ?? 'Responsáveis notificados.',
        ok: true,
      );
      return;
    }
    if (res.statusCode == 429) {
      _cooldownSnack(res.message, res.data, 'notificar');
      return;
    }
    _actionSnack(res.message ?? 'Não foi possível enviar a notificação.');
  }

  Future<void> _ignoreOwnerSignature(Property p) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final result = await showApprovalConfirmSheet(
      context: context,
      eyebrow: 'PROPRIETÁRIO',
      title: 'Ignorar assinatura digital',
      subtitle: _propertyLabel(p),
      message:
          'O imóvel segue no fluxo sem esperar a assinatura no Autentique. '
          'O motivo fica registrado no histórico.',
      icon: LucideIcons.penOff,
      tone: isDark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning,
      confirmLabel: 'Ignorar assinatura',
      confirmIcon: LucideIcons.penOff,
      withReason: true,
      reasonRequired: true,
      reasonLabel: 'Motivo',
      reasonHint: 'Ex.: proprietário em viagem, liberação aprovada pela gestão.',
    );
    if (result == null || !mounted) return;
    final res = await PropertyApprovalService.instance
        .ignoreOwnerAuthorizationSignature(p.id, reason: result.reason);
    if (!mounted) return;
    if (res.success) {
      _actionSnack('Assinatura dispensada — fluxo liberado.', ok: true);
      await _refreshAll();
      return;
    }
    _actionSnack(res.message ?? 'Não foi possível dispensar a assinatura.');
  }

  Future<void> _invalidateOwnerSignature(Property p) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final result = await showApprovalConfirmSheet(
      context: context,
      eyebrow: 'PROPRIETÁRIO',
      title: 'Invalidar assinatura',
      subtitle: _propertyLabel(p),
      message:
          'A assinatura é apagada, os votos em andamento são descartados e o '
          'imóvel volta a aguardar a autorização do proprietário. Não dá para '
          'desfazer.',
      icon: LucideIcons.unlink,
      tone: isDark ? AppColors.status.errorDarkMode : AppColors.status.error,
      confirmLabel: 'Invalidar',
      confirmIcon: LucideIcons.unlink,
      danger: true,
    );
    if (result == null || !mounted) return;
    final res = await PropertyApprovalService.instance
        .invalidateOwnerAuthorization(p.id);
    if (!mounted) return;
    if (res.success) {
      _actionSnack('Assinatura invalidada.', ok: true);
      await _refreshAll();
      return;
    }
    _actionSnack(res.message ?? 'Não foi possível invalidar a assinatura.');
  }

  Future<void> _resendOwnerAuthEmail(Property p) async {
    final res = await PropertyApprovalService.instance
        .resendOwnerAuthorizationEmail(p.id);
    if (!mounted) return;
    if (res.success) {
      _actionSnack('E-mail reenviado ao proprietário.', ok: true);
      return;
    }
    _actionSnack(res.message ?? 'Não foi possível reenviar o e-mail.');
  }

  Future<void> _approveOwnerAuthPhysical(Property p) async {
    final result = await showApprovalConfirmSheet(
      context: context,
      eyebrow: 'PROPRIETÁRIO',
      title: 'Validar assinatura física',
      subtitle: _propertyLabel(p),
      message:
          'Confirma que o documento anexo está correto? O imóvel segue para a '
          'fila de aprovação, com o mesmo efeito da assinatura digital.',
      icon: LucideIcons.badgeCheck,
      tone: kApprovalGreen,
      confirmLabel: 'Validar',
      confirmIcon: LucideIcons.badgeCheck,
    );
    if (result == null || !mounted) return;
    final res = await PropertyApprovalService.instance
        .approveOwnerAuthorizationPhysical(p.id);
    if (!mounted) return;
    if (res.success) {
      _actionSnack('Anexo validado — imóvel liberado.', ok: true);
      await _refreshAll();
      return;
    }
    _actionSnack(res.message ?? 'Não foi possível validar o anexo.');
  }

  Future<void> _rejectOwnerAuthPhysical(Property p) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final result = await showApprovalConfirmSheet(
      context: context,
      eyebrow: 'PROPRIETÁRIO',
      title: 'Recusar anexo',
      subtitle: _propertyLabel(p),
      message:
          'O anexo é removido e o imóvel continua aguardando a autorização. '
          'Explique o que precisa ser corrigido.',
      icon: LucideIcons.ban,
      tone: isDark ? AppColors.status.errorDarkMode : AppColors.status.error,
      confirmLabel: 'Recusar anexo',
      confirmIcon: LucideIcons.ban,
      danger: true,
      withReason: true,
      reasonLabel: 'Motivo (opcional)',
      reasonHint: 'Ex.: documento ilegível, faltou a assinatura do cônjuge.',
    );
    if (result == null || !mounted) return;
    final res = await PropertyApprovalService.instance
        .rejectOwnerAuthorizationPhysical(
      p.id,
      reason: result.reason.isEmpty ? null : result.reason,
    );
    if (!mounted) return;
    if (res.success) {
      _actionSnack('Anexo recusado.', ok: true);
      await _refreshAll();
      return;
    }
    _actionSnack(res.message ?? 'Não foi possível recusar o anexo.');
  }

  Future<void> _openOwnerAuthPhysicalPreview(Property p) async {
    final res = await PropertyApprovalService.instance
        .getOwnerAuthorizationPhysicalPreviewUrl(p.id);
    if (!mounted) return;
    if (!res.success || res.data == null) {
      _actionSnack(res.message ?? 'Não foi possível abrir o anexo.');
      return;
    }
    final uri = Uri.tryParse(res.data!);
    if (uri == null) {
      _actionSnack('Link do anexo inválido.');
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      _actionSnack('Nenhum aplicativo disponível para abrir o anexo.');
    }
  }

  Future<void> _sendOwnerAuthorization(Property p, String ownerStatus) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final purple =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    final request = await showOwnerAuthSendSheet(
      context: context,
      propertyTitle: _propertyLabel(p),
      tone: purple,
      ownerName: p.owner?.name,
      ownerEmail: p.owner?.email,
      initialMode: ownerStatus == 'pending_physical_validation'
          ? OwnerAuthSendMode.physical
          : OwnerAuthSendMode.digital,
      isResend: ownerStatus == 'pending',
    );
    if (request == null || !mounted) return;

    final svc = PropertyApprovalService.instance;
    switch (request.mode) {
      case OwnerAuthSendMode.physical:
        final res =
            await svc.uploadOwnerAuthorizationPhysical(p.id, request.file!);
        if (!mounted) return;
        if (res.success) {
          _actionSnack(
            'Anexo enviado — aguardando validação do aprovador.',
            ok: true,
          );
          await _refreshAll();
        } else {
          _actionSnack(res.message ?? 'Não foi possível enviar o anexo.');
        }
        return;
      case OwnerAuthSendMode.ownDocument:
        final res = await svc.sendOwnerAuthorizationWithDocument(
          p.id,
          request.file!,
          signerEmail: request.signerEmail,
          signerName: request.signerName,
          sendByEmail: request.sendByEmail,
        );
        if (!mounted) return;
        if (res.success) {
          _actionSnack('Documento enviado para assinatura.', ok: true);
          await _refreshAll();
          _maybeShowSignatureLink(res.data?['signatureUrl']?.toString());
        } else {
          _actionSnack(res.message ?? 'Não foi possível enviar o documento.');
        }
        return;
      case OwnerAuthSendMode.digital:
        final res = await svc.sendOwnerAuthorization(
          p.id,
          signerName: request.signerName,
          signerEmail: request.signerEmail,
          sendByEmail: request.sendByEmail,
          hasExclusivity: request.hasExclusivity,
          exclusivityDays: request.exclusivityDays,
          exclusivityIndeterminate: request.exclusivityIndeterminate,
          acceptsPlaca: request.acceptsPlaca,
          operationType: request.operationType,
          logoSource: request.logoSource,
        );
        if (!mounted) return;
        if (res.success) {
          _actionSnack(
            res.data?.message ?? 'Autorização enviada para assinatura.',
            ok: true,
          );
          await _refreshAll();
          _maybeShowSignatureLink(res.data?.signatureUrl);
        } else {
          _actionSnack(res.message ?? 'Não foi possível enviar a autorização.');
        }
        return;
    }
  }

  /// Quando o envio foi "apenas link", mostramos o link para o corretor
  /// repassar ao proprietário (no web ele vai para a área de transferência).
  void _maybeShowSignatureLink(String? url) {
    if (url == null || url.isEmpty || !mounted) return;
    showApprovalConfirmSheet(
      context: context,
      eyebrow: 'LINK DE ASSINATURA',
      title: 'Repasse este link ao proprietário',
      message: url,
      icon: LucideIcons.externalLink,
      tone: _accentColor(context),
      confirmLabel: 'Abrir link',
      confirmIcon: LucideIcons.externalLink,
    ).then((r) {
      if (r == null) return;
      final uri = Uri.tryParse(url);
      if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
    });
  }

  // ─── Ações da aba de edições ──────────────────────────────────────────

  Future<bool> _approveChangeRequest(PropertyChangeRequest req) async {
    final result = await showApprovalConfirmSheet(
      context: context,
      eyebrow: 'EDIÇÃO',
      title: 'Aprovar alteração',
      subtitle: req.property?.title,
      message: req.hasConflict
          ? 'Atenção: o imóvel mudou depois desta solicitação. Aprovar aplica '
              'os valores propostos por cima do que está lá hoje.'
          : 'Os valores propostos são aplicados ao imóvel e o solicitante é '
              'notificado.',
      icon: LucideIcons.checkCircle2,
      tone: kApprovalGreen,
      confirmLabel: 'Aprovar',
      confirmIcon: LucideIcons.checkCircle2,
    );
    if (result == null || !mounted) return false;
    final res =
        await PropertyApprovalService.instance.approveChangeRequest(req.id);
    if (!mounted) return false;
    if (res.success) {
      _actionSnack('Alteração aplicada ao imóvel.', ok: true);
      await _loadEditRequests();
      return true;
    }
    _actionSnack(res.message ?? 'Não foi possível aprovar a solicitação.');
    return false;
  }

  Future<bool> _rejectChangeRequest(PropertyChangeRequest req) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final result = await showApprovalConfirmSheet(
      context: context,
      eyebrow: 'EDIÇÃO',
      title: 'Recusar alteração',
      subtitle: req.property?.title,
      message: 'O imóvel fica intacto e o solicitante recebe o motivo.',
      icon: LucideIcons.xCircle,
      tone: isDark ? AppColors.status.errorDarkMode : AppColors.status.error,
      confirmLabel: 'Recusar',
      confirmIcon: LucideIcons.xCircle,
      danger: true,
      withReason: true,
      reasonRequired: true,
      reasonLabel: 'Motivo da recusa',
      reasonHint: 'Explique o que impede a alteração.',
    );
    if (result == null || !mounted) return false;
    final res = await PropertyApprovalService.instance
        .rejectChangeRequest(req.id, reason: result.reason);
    if (!mounted) return false;
    if (res.success) {
      _actionSnack('Solicitação recusada. Solicitante notificado.', ok: true);
      await _loadEditRequests();
      return true;
    }
    _actionSnack(res.message ?? 'Não foi possível recusar a solicitação.');
    return false;
  }

  // ─── Helpers visuais ──────────────────────────────────────────────────

  Color _accentColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
  }

  /// Cor coerente da aba ativa — usada no ícone/eyebrow do cabeçalho do painel
  /// pra cada fila ter sua identidade (não "tudo vermelho").
  Color _activeTabColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (_activeTab) {
      case _Tab.availability:
        return isDark
            ? AppColors.status.greenDarkMode
            : AppColors.status.green;
      case _Tab.publication:
        return isDark
            ? AppColors.status.warningDarkMode
            : AppColors.status.warning;
      case _Tab.ownerAuth:
        return isDark
            ? AppColors.status.purpleDarkMode
            : AppColors.status.purple;
      case _Tab.rejected:
        return isDark
            ? AppColors.status.errorDarkMode
            : AppColors.status.error;
      case _Tab.editRequests:
        return isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
      case _Tab.mine:
        return _accentColor(context);
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Aprovações',
      currentBottomNavIndex: 1,
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        color: _accentColor(context),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _kPagePadH,
                      _kPagePadTop,
                      _kPagePadH,
                      0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildGreeting(context),
                        const SizedBox(height: _kSectionGap),
                        _buildSearchField(context),
                        const SizedBox(height: 10),
                        _buildToolbarActions(context),
                        const SizedBox(height: _kSectionGap),
                      ],
                    ),
                  ),
                  _buildTabsRail(context),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _kPagePadH,
                      _kSectionGap,
                      _kPagePadH,
                      _kPagePadBottom,
                    ),
                    child: _buildActivePanel(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Hero editorial (mesmo DNA da tela de Usuários — sem ícone/banner) ──

  Widget _buildGreeting(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accentColor(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final ok =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final warn =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final purple =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final emerald =
        isDark ? const Color(0xFF34D399) : const Color(0xFF059669);

    final pendingTotal = _pendingTotal();
    final hasRejected = _rejectedCounts.total > 0;
    final dotColor =
        hasRejected ? danger : (pendingTotal > 0 ? accent : emerald);

    final subtitle = !_canViewQueues
        ? 'Acompanhe seus imóveis na fila de aprovação.'
        : hasRejected
            ? '${_rejectedCounts.total} recusado${_rejectedCounts.total == 1 ? '' : 's'} aguardando reenvio · libere operação e site.'
            : (pendingTotal == 0
                ? 'Tudo em dia — nada aguardando aprovação agora.'
                : 'Liberação para a operação e para o site.');

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Eyebrow editorial — dot semântico + label uppercase.
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColor,
                  boxShadow: [
                    BoxShadow(
                      color: dotColor.withValues(alpha: 0.55),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              Text(
                'FILA DE APROVAÇÃO',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.2,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Headline com número grande + rótulo na base (editorial).
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$pendingTotal',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: textColor,
                  height: 1.0,
                  letterSpacing: -1.0,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  pendingTotal == 1 ? 'pendência' : 'pendências',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: secondary,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          if (_canViewQueues) ...[
            const SizedBox(height: 18),
            _buildHeroKpiStrip(context, ok, warn, purple, danger),
          ],
        ],
      ),
    );
  }

  /// Strip editorial de KPIs por fila — 4 colunas separadas por filete fino.
  Widget _buildHeroKpiStrip(
    BuildContext context,
    Color ok,
    Color warn,
    Color purple,
    Color danger,
  ) {
    final divider = ThemeHelpers.borderColor(context).withValues(alpha: 0.45);
    final blocks = <Widget>[
      _heroKpiBlock(context, LucideIcons.checkCircle2, 'DISPONIB.',
          _pendingAvailability.length, 'p/ operar', ok),
      _heroKpiBlock(context, LucideIcons.globe, 'PUBLIC.',
          _pendingPublication.length, 'p/ o site', warn),
      _heroKpiBlock(context, LucideIcons.fileSignature, 'PROPRIET.',
          _pendingOwner.length, 'assinatura', purple),
      _heroKpiBlock(context, LucideIcons.alertTriangle, 'RECUSADOS',
          _rejectedCounts.total, 'ajustar', danger),
    ];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < blocks.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: divider,
              ),
            Expanded(child: blocks[i]),
          ],
        ],
      ),
    );
  }

  Widget _heroKpiBlock(
    BuildContext context,
    IconData icon,
    String label,
    int value,
    String sub,
    Color tone,
  ) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: tone),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: tone,
                    letterSpacing: 1.2,
                    height: 1.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '$value',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: tone,
                letterSpacing: -0.6,
                height: 1.0,
                fontSize: 22,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            sub,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: secondary,
              height: 1.0,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 7),
          Container(
            height: 2,
            width: 18,
            decoration: BoxDecoration(
              color: tone,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  int _pendingTotal() {
    return _myPending.total +
        _pendingAvailability.length +
        _pendingPublication.length +
        _pendingOwner.length;
  }

  // ─── Search field ─────────────────────────────────────────────────────

  Widget _buildSearchField(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accentColor(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final cardColor = ThemeHelpers.cardBackgroundColor(context);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final hasText = _searchController.text.isNotEmpty;
    final showAccent = _searchFocused || hasText;

    // Controle único no estilo da tela de Usuários: container animado que
    // tinge em accent quando há foco/texto, com filete e sombra sutis.
    return Focus(
      onFocusChange: (f) => setState(() => _searchFocused = f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        height: 50,
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: showAccent
                ? accent.withValues(alpha: isDark ? 0.5 : 0.42)
                : borderColor,
            width: showAccent ? 1.4 : 1,
          ),
          boxShadow: showAccent
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: isDark ? 0.18 : 0.12),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                    spreadRadius: -4,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(
              LucideIcons.search,
              size: 18,
              color: showAccent ? accent : secondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                cursorColor: accent,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
                decoration: InputDecoration(
                  hintText: 'Buscar por código, título, proprietário…',
                  hintStyle: TextStyle(
                    color: secondary.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w500,
                    fontSize: 13.5,
                  ),
                  filled: false,
                  fillColor: Colors.transparent,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
                onChanged: (v) {
                  _onSearchChanged(v);
                  setState(() {});
                },
              ),
            ),
            if (hasText)
              InkResponse(
                radius: 18,
                onTap: () {
                  _searchController.clear();
                  _onSearchChanged('');
                  setState(() {});
                },
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(LucideIcons.x, size: 15, color: secondary),
                ),
              ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  // ─── Barra de ações: filtros + exportação ─────────────────────────────

  /// Chave da aba para o job de exportação. A aba "Edições" não é exportável
  /// no backend (o job só conhece as filas de aprovação), então devolve
  /// `null` e o botão some — melhor sumir do que falhar ao tocar.
  String? get _exportTabKey {
    switch (_activeTab) {
      case _Tab.mine:
        return 'mine';
      case _Tab.ownerAuth:
        return 'owner_authorization';
      case _Tab.availability:
        return 'availability';
      case _Tab.publication:
        return 'publication';
      case _Tab.rejected:
        return 'rejected';
      case _Tab.editRequests:
        return null;
    }
  }

  Widget _buildToolbarActions(BuildContext context) {
    final count = _advancedCount;
    final canExport = _exportTabKey != null;

    return Row(
      children: [
        Expanded(
          child: _ToolbarPill(
            icon: LucideIcons.slidersHorizontal,
            label: count > 0 ? 'Filtros · $count' : 'Filtros',
            tone: const Color(0xFF4F46E5),
            active: count > 0,
            onTap: _openFiltersSheet,
          ),
        ),
        if (canExport) ...[
          const SizedBox(width: 10),
          Expanded(
            child: _ToolbarPill(
              icon: LucideIcons.download,
              label: _exporting ? 'Exportando…' : 'Exportar',
              tone: const Color(0xFF0891B2),
              active: false,
              busy: _exporting,
              onTap: _exporting ? null : _exportCurrentTab,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _openFiltersSheet() async {
    final result = await showApprovalFiltersSheet(
      context: context,
      current: _advanced,
      globalSearchActive: _appliedSearch.trim().isNotEmpty,
    );
    if (result == null || !mounted) return;
    setState(() => _advanced = result);
    await _refreshAll();
  }

  /// Exporta a aba atual em CSV.
  ///
  /// É um job assíncrono no backend (mesmo fluxo do web): cria → consulta o
  /// status até sair de `pending`/`processing` → baixa os bytes. O arquivo vai
  /// para o diretório temporário e sobe na folha de compartilhamento, que é o
  /// equivalente mobile do "download" do navegador.
  Future<void> _exportCurrentTab() async {
    final tab = _exportTabKey;
    if (tab == null) return;

    setState(() => _exporting = true);
    final svc = PropertyApprovalService.instance;
    try {
      final created = await svc.createApprovalExportJob(
        tab: tab,
        filters: _filters(),
      );
      if (!created.success || (created.data ?? '').isEmpty) {
        _actionSnack(created.message ?? 'Não foi possível iniciar a exportação');
        return;
      }
      final jobId = created.data!;

      // Polling com teto: ~60s. Sem teto, um job travado deixaria o botão
      // girando para sempre.
      ApprovalExportJob? job;
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        if (!mounted) return;
        final status = await svc.getApprovalExportJobStatus(jobId);
        if (!status.success || status.data == null) {
          _actionSnack(status.message ?? 'Erro ao consultar a exportação');
          return;
        }
        job = status.data;
        if (!job!.isRunning) break;
      }

      if (job == null || job.isRunning) {
        _actionSnack('A exportação demorou mais que o esperado. Tente de novo.');
        return;
      }
      if (job.isFailed) {
        _actionSnack(job.error ?? 'A exportação falhou no servidor');
        return;
      }

      final bytes = await svc.downloadApprovalExportJob(jobId);
      if (!bytes.success || bytes.data == null) {
        _actionSnack(bytes.message ?? 'Erro ao baixar o arquivo');
        return;
      }

      final dir = await getTemporaryDirectory();
      final name = (job.fileName ?? '').trim().isNotEmpty
          ? job.fileName!.trim()
          : 'aprovacoes-$tab.csv';
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes.data!, flush: true);

      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Exportação da fila de aprovação',
        ),
      );
      if (!mounted) return;
      _actionSnack(
        job.totalRows > 0
            ? 'Exportação pronta — ${job.totalRows} registro(s).'
            : 'Exportação pronta.',
        ok: true,
      );
    } catch (e) {
      _actionSnack('Erro ao exportar: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ─── Abas flush fixas (sublinhado, sem scroll) ────────────────────────

  Widget _buildTabsRail(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accentColor(context);
    final ok = isDark
        ? AppColors.status.greenDarkMode
        : AppColors.status.green;
    final warn = isDark
        ? AppColors.status.warningDarkMode
        : AppColors.status.warning;
    final danger = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;
    final purple = isDark
        ? AppColors.status.purpleDarkMode
        : AppColors.status.purple;
    final blue =
        isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;

    final tabs = <_TabSpec>[
      _TabSpec(
        tab: _Tab.mine,
        icon: LucideIcons.user,
        label: 'Meus',
        count: _myPending.total,
        accentColor: accent,
      ),
      if (_canViewQueues)
        _TabSpec(
          tab: _Tab.availability,
          icon: LucideIcons.checkCircle2,
          label: 'Disponib.',
          count: _pendingAvailability.length,
          accentColor: ok,
        ),
      if (_canViewQueues)
        _TabSpec(
          tab: _Tab.publication,
          icon: LucideIcons.globe,
          label: 'Publicação',
          count: _pendingPublication.length,
          accentColor: warn,
        ),
      if (_canViewQueues)
        _TabSpec(
          tab: _Tab.ownerAuth,
          icon: LucideIcons.fileSignature,
          label: 'Propriet.',
          count: _pendingOwner.length,
          accentColor: purple,
        ),
      if (_canViewQueues)
        _TabSpec(
          tab: _Tab.rejected,
          icon: LucideIcons.alertTriangle,
          label: 'Recusados',
          count: _rejectedCounts.total,
          accentColor: danger,
        ),
      // Aba "Edições" (campos protegidos). O backend escopa a lista, então
      // ela vale tanto para quem revisa quanto para quem só acompanha as
      // próprias solicitações.
      _TabSpec(
        tab: _Tab.editRequests,
        icon: LucideIcons.squarePen,
        label: 'Edições',
        count: _editRequests.items.where((r) => r.isPending).length,
        accentColor: blue,
      ),
    ];

    // Barra de abas **flush** com sublinhado — fixa (sem scroll horizontal):
    // cada fila ocupa uma fração igual da largura (ícone + rótulo curto +
    // contagem), com filete inferior de largura total e indicador na cor da
    // fila ativa. Mesmo DNA de navegação do app (Documentos/Chaves).
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: _kPagePadH - 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Com 6 filas o layout fixo só cabe em telas normais. Abaixo do piso
          // legível (`_kMinTabWidth`) a barra passa a rolar em vez de espremer
          // o rótulo — nada de texto ilegível nem overflow.
          final available = constraints.maxWidth;
          final each = available / tabs.length;
          final items = [
            for (final t in tabs)
              _FlushTab(
                spec: t,
                selected: _activeTab == t.tab,
                onTap: () => _selectTab(t.tab),
              ),
          ];
          if (each >= _kMinTabWidth) {
            return Row(
              children: [for (final w in items) Expanded(child: w)],
            );
          }
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: Row(
              children: [
                for (final w in items)
                  SizedBox(width: _kMinTabWidth, child: w),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── Seção ativa (sem painel encapsulando) ────────────────────────────

  Widget _buildActivePanel(BuildContext context) {
    final isLoading = _isCurrentTabLoading();
    final hasError = _currentTabError() != null;
    final hasContent = _currentTabHasContent();

    Widget child;
    if (isLoading && !hasContent) {
      child = _buildSkeletonList();
    } else if (hasError && !hasContent) {
      child = _buildPanelError();
    } else if (!hasContent) {
      child = _buildEmptyState();
    } else {
      child = _buildTabBody();
    }

    return Column(
      key: ValueKey('panel-${_activeTab.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPanelHeader(context),
        const SizedBox(height: 14),
        child,
      ],
    ).animate(key: ValueKey('panel-${_activeTab.name}')).fadeIn(
          duration: 240.ms,
        );
  }

  ({IconData icon, String eyebrow, String title, String hint}) _panelMeta() {
    switch (_activeTab) {
      case _Tab.mine:
        return (
          icon: LucideIcons.user,
          eyebrow: 'SUAS PENDÊNCIAS',
          title: 'Meus imóveis',
          hint: 'O que está aguardando você ou seu cliente.',
        );
      case _Tab.ownerAuth:
        return (
          icon: LucideIcons.fileSignature,
          eyebrow: 'PROPRIETÁRIO',
          title: 'Aguardando autorização',
          hint: 'Imóveis pendentes da assinatura do proprietário.',
        );
      case _Tab.availability:
        return (
          icon: LucideIcons.checkCircle2,
          eyebrow: 'DISPONIBILIDADE',
          title: 'Liberação para a operação',
          hint: 'Imóveis aguardando aprovação para ficar disponíveis.',
        );
      case _Tab.publication:
        return (
          icon: LucideIcons.globe,
          eyebrow: 'PUBLICAÇÃO',
          title: 'Liberação para o site',
          hint: 'Aguardando aprovação para o portal público.',
        );
      case _Tab.rejected:
        return (
          icon: LucideIcons.alertTriangle,
          eyebrow: 'RECUSADOS',
          title: 'Aguardando ajustes',
          hint: 'Imóveis recusados que precisam de correção.',
        );
      case _Tab.editRequests:
        return (
          icon: LucideIcons.squarePen,
          eyebrow: 'CAMPOS PROTEGIDOS',
          title: 'Solicitações de edição',
          hint: _editRequests.canReview
              ? 'Aprovar aplica a alteração ao imóvel; recusar exige motivo.'
              : 'Suas alterações aguardando revisão de um aprovador.',
        );
    }
  }

  Widget _buildPanelHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tabColor = _activeTabColor(context);
    final meta = _panelMeta();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: tabColor.withValues(alpha: isDark ? 0.20 : 0.12),
          ),
          child: Icon(meta.icon, color: tabColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: tabColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: tabColor.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    meta.eyebrow,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tabColor,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                meta.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                meta.hint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  height: 1.32,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool _isCurrentTabLoading() {
    switch (_activeTab) {
      case _Tab.mine:
        return _loadingMine;
      case _Tab.ownerAuth:
        return _loadingOwner;
      case _Tab.availability:
        return _loadingAvailability;
      case _Tab.publication:
        return _loadingPublication;
      case _Tab.rejected:
        return _loadingRejectedAvail || _loadingRejectedPub;
      case _Tab.editRequests:
        return _loadingEditRequests;
    }
  }

  String? _currentTabError() {
    switch (_activeTab) {
      case _Tab.mine:
        return _errorMine;
      case _Tab.ownerAuth:
        return _errorOwner;
      case _Tab.availability:
        return _errorAvailability;
      case _Tab.publication:
        return _errorPublication;
      case _Tab.rejected:
        return _errorRejected;
      case _Tab.editRequests:
        return _errorEditRequests;
    }
  }

  /// Código HTTP do erro da aba ativa — 0 quando não houve resposta do
  /// servidor. É o que separa "sem permissão" de "servidor fora do ar".
  int _currentTabErrorStatus() {
    switch (_activeTab) {
      case _Tab.mine:
        return _errorStatusMine;
      case _Tab.ownerAuth:
        return _errorStatusOwner;
      case _Tab.availability:
        return _errorStatusAvailability;
      case _Tab.publication:
        return _errorStatusPublication;
      case _Tab.rejected:
        return _errorStatusRejected;
      case _Tab.editRequests:
        return _errorStatusEditRequests;
    }
  }

  bool _currentTabHasContent() {
    switch (_activeTab) {
      case _Tab.mine:
        return _myPending.total > 0;
      case _Tab.ownerAuth:
        return _pendingOwner.isNotEmpty;
      case _Tab.availability:
        return _pendingAvailability.isNotEmpty;
      case _Tab.publication:
        return _pendingPublication.isNotEmpty;
      case _Tab.rejected:
        return _rejectedAvail.data.isNotEmpty ||
            _rejectedPub.data.isNotEmpty;
      case _Tab.editRequests:
        // O cabeçalho da esteira (ligada/desligada) + os filtros valem por si,
        // então a aba nunca cai no estado vazio "cru".
        return true;
    }
  }

  Widget _buildTabBody() {
    final List<Widget> nodes = [];

    void addList(List<Property> list, ApprovalQueueKind kind) {
      // Ações só nas filas de aprovação (disponibilidade/publicação) e somente
      // para quem tem a permissão correspondente.
      final isQueue = kind == ApprovalQueueKind.pendingAvailability ||
          kind == ApprovalQueueKind.pendingPublication;
      final canApprove = kind == ApprovalQueueKind.pendingAvailability
          ? _canApproveAvailability
          : kind == ApprovalQueueKind.pendingPublication
              ? _canApprovePublication
              : false;
      final canReject = kind == ApprovalQueueKind.pendingAvailability
          ? _canRejectAvailability
          : kind == ApprovalQueueKind.pendingPublication
              ? _canRejectPublication
              : false;
      // Com multi-aprovadores ligado, a fila vota em vez de aprovar direto —
      // mesma bifurcação do web (`settings.approversEnabled`).
      final votingMode = isQueue && _settings.approversEnabled;
      for (var i = 0; i < list.length; i++) {
        final p = list[i];
        final rejectedWaiting = _isRejectedWaitingResend(p, kind);
        final showApprove = canApprove && !votingMode && !rejectedWaiting;
        final showReject = canReject && !votingMode && !rejectedWaiting;
        nodes.add(
          ApprovalPropertyCard(
            property: p,
            kind: kind,
            onOpenDetails: () => _openDetails(p),
            canApprove: showApprove,
            canReject: showReject,
            onApprove: showApprove ? () => _approveCard(p, kind) : null,
            onReject: showReject ? () => _rejectCard(p, kind) : null,
            onResend: rejectedWaiting ? () => _resendCard(p, kind) : null,
            onVote: votingMode && !rejectedWaiting && canApprove
                ? () => _voteCard(p, kind)
                : null,
            onMore: () => _openMoreActions(p, kind),
            ownerAuthNote: kind == ApprovalQueueKind.pendingOwnerAuth ||
                    kind == ApprovalQueueKind.myOwnerAuth
                ? _ownerAuthNote(p)
                : null,
          )
              .animate(key: ValueKey('card-${p.id}-$kind'))
              .fadeIn(
                delay: Duration(milliseconds: 40 * i),
                duration: 220.ms,
              ),
        );
      }
    }

    void addSubsection(String label, IconData icon, int count) {
      if (nodes.isNotEmpty) nodes.add(const SizedBox(height: 14));
      nodes.add(_PanelSubsectionHeader(label: label, icon: icon, count: count));
      nodes.add(const SizedBox(height: 8));
    }

    switch (_activeTab) {
      case _Tab.mine:
        if (_myPending.pendingAvailability.isNotEmpty) {
          addSubsection('Aguardando disponibilidade',
              LucideIcons.checkCircle2, _myPending.pendingAvailability.length);
          addList(_myPending.pendingAvailability,
              ApprovalQueueKind.myAvailability);
        }
        if (_myPending.pendingOwnerAuthorization.isNotEmpty) {
          addSubsection('Aguardando proprietário', LucideIcons.fileSignature,
              _myPending.pendingOwnerAuthorization.length);
          addList(_myPending.pendingOwnerAuthorization,
              ApprovalQueueKind.myOwnerAuth);
        }
        if (_myPending.pendingPublication.isNotEmpty) {
          addSubsection('Aguardando publicação', LucideIcons.globe,
              _myPending.pendingPublication.length);
          addList(_myPending.pendingPublication,
              ApprovalQueueKind.myPublication);
        }
        break;
      case _Tab.ownerAuth:
        addList(_pendingOwner, ApprovalQueueKind.pendingOwnerAuth);
        break;
      case _Tab.availability:
        addList(_pendingAvailability, ApprovalQueueKind.pendingAvailability);
        break;
      case _Tab.publication:
        addList(_pendingPublication, ApprovalQueueKind.pendingPublication);
        break;
      case _Tab.rejected:
        if (_rejectedAvail.data.isNotEmpty) {
          addSubsection('Disponibilidade recusada',
              LucideIcons.alertTriangle, _rejectedAvail.total);
          addList(
              _rejectedAvail.data, ApprovalQueueKind.rejectedAvailability);
        }
        if (_rejectedPub.data.isNotEmpty) {
          addSubsection('Publicação recusada', LucideIcons.alertTriangle,
              _rejectedPub.total);
          addList(_rejectedPub.data, ApprovalQueueKind.rejectedPublication);
        }
        break;
      case _Tab.editRequests:
        return _buildEditRequestsBody();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: nodes,
    );
  }

  // ─── Aba "Edições" (campos protegidos) ────────────────────────────────

  Widget _buildEditRequestsBody() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final blue =
        isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final on = _settings.protectedFieldsEnabled;
    final items = _editRequests.items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Estado da esteira — linha flush com filete, sem card encapsulando.
        Container(
          padding: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                on ? LucideIcons.lock : LucideIcons.lockOpen,
                size: 16,
                color: on ? kApprovalGreen : secondary,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  on
                      ? 'Esteira ligada: edições em campos protegidos de quem não é aprovador viram solicitação.'
                      : 'Esteira desligada: qualquer edição é aplicada direto ao imóvel, sem passar por aprovação.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondary,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: (on ? kApprovalGreen : secondary)
                      .withValues(alpha: isDark ? 0.16 : 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: (on ? kApprovalGreen : secondary)
                        .withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  on ? 'ATIVADA' : 'DESATIVADA',
                  style: TextStyle(
                    color: on ? kApprovalGreen : secondary,
                    fontWeight: FontWeight.w900,
                    fontSize: 9.5,
                    letterSpacing: 0.9,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Filtro por status — mesmos quatro do web.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: Row(
            children: [
              for (final f in <({
                PropertyChangeRequestStatus? status,
                String label
              })>[
                (status: PropertyChangeRequestStatus.pending, label: 'Pendentes'),
                (
                  status: PropertyChangeRequestStatus.approved,
                  label: 'Aprovadas'
                ),
                (
                  status: PropertyChangeRequestStatus.rejected,
                  label: 'Recusadas'
                ),
                (status: null, label: 'Todas'),
              ]) ...[
                _EditRequestFilterChip(
                  label: f.label,
                  tone: blue,
                  selected: _editRequestsFilter == f.status,
                  onTap: () {
                    if (_editRequestsFilter == f.status) return;
                    setState(() => _editRequestsFilter = f.status);
                    _loadEditRequests();
                  },
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_loadingEditRequests)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 34),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 4),
            child: Column(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: blue.withValues(alpha: 0.10),
                    border: Border.all(color: blue.withValues(alpha: 0.28)),
                  ),
                  child: Icon(LucideIcons.squarePen, color: blue, size: 26),
                ),
                const SizedBox(height: 13),
                Text(
                  _editRequestsFilter == PropertyChangeRequestStatus.pending
                      ? 'Nenhuma solicitação pendente'
                      : 'Nenhuma solicitação encontrada',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Edições em campos protegidos aparecem aqui para revisão.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          )
        else
          for (var i = 0; i < items.length; i++)
            ChangeRequestCard(
              request: items[i],
              canReview: _editRequests.canReview,
              onOpenProperty: items[i].property == null
                  ? null
                  : () => Navigator.of(context).pushNamed(
                        AppRoutes.propertyDetails(items[i].property!.id),
                      ),
              onApprove: () => _approveChangeRequest(items[i]),
              onReject: () => _rejectChangeRequest(items[i]),
            ).animate(key: ValueKey('cr-${items[i].id}')).fadeIn(
                  delay: Duration(milliseconds: 40 * i),
                  duration: 220.ms,
                ),
      ],
    );
  }

  Widget _buildSkeletonList() {
    // Espelha a linha flush real (faixa + thumbnail + texto + filete),
    // não um card arredondado — coerência no estado de carregamento.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(4, (i) => const _ApprovalRowSkeleton()),
    );
  }

  Widget _buildPanelError() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 4),
      child: AppErrorState.fromApi(
        message: _currentTabError(),
        statusCode: _currentTabErrorStatus(),
        dense: true,
        onRetry: () => _refreshAll(),
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final accent = _accentColor(context);
    final meta = _emptyMeta();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  accent.withValues(alpha: 0.18),
                  accent.withValues(alpha: 0.06),
                ],
              ),
              border: Border.all(color: accent.withValues(alpha: 0.32)),
            ),
            child: Icon(meta.icon, color: accent, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            meta.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            meta.body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  ({IconData icon, String title, String body}) _emptyMeta() {
    switch (_activeTab) {
      case _Tab.mine:
        return (
          icon: LucideIcons.partyPopper,
          title: 'Tudo em dia por aqui',
          body:
              'Nenhum dos seus imóveis está aguardando aprovação no momento.',
        );
      case _Tab.ownerAuth:
        return (
          icon: LucideIcons.fileSignature,
          title: 'Sem autorizações pendentes',
          body:
              'Quando o proprietário ainda não tiver assinado, o imóvel aparece aqui.',
        );
      case _Tab.availability:
        return (
          icon: LucideIcons.partyPopper,
          title: 'Nada na fila de disponibilidade',
          body:
              'Imóveis aguardando aprovação para a operação aparecem aqui.',
        );
      case _Tab.publication:
        return (
          icon: LucideIcons.globe,
          title: 'Nada na fila de publicação',
          body:
              'Imóveis aguardando entrar no site público aparecem aqui.',
        );
      case _Tab.rejected:
        return (
          icon: LucideIcons.shieldCheck,
          title: 'Nenhum imóvel recusado',
          body:
              'Quando algum imóvel for recusado, ele fica listado aqui para revisão.',
        );
      case _Tab.editRequests:
        return (
          icon: LucideIcons.squarePen,
          title: 'Nenhuma solicitação',
          body:
              'Edições em campos protegidos aparecem aqui para aprovação.',
        );
    }
  }
}

// ─── Subwidgets internos ────────────────────────────────────────────────

/// Placeholder de carregamento que reproduz a linha flush real
/// (`ApprovalPropertyCard`): thumbnail 72 com código abaixo, texto e filete.
class _ApprovalRowSkeleton extends StatelessWidget {
  const _ApprovalRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                SkeletonBox(width: 72, height: 72, borderRadius: 14),
                const SizedBox(height: 7),
                SkeletonText(width: 60, height: 12, borderRadius: 999),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonText(width: 96, height: 18, borderRadius: 999),
                  const SizedBox(height: 9),
                  SkeletonText(width: double.infinity, height: 14),
                  const SizedBox(height: 6),
                  SkeletonText(width: 140, height: 12),
                  const SizedBox(height: 10),
                  SkeletonText(width: 120, height: 14),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip de filtro por status da aba "Edições" (pendentes/aprovadas/…).
/// Pílula da barra de ações (Filtros / Exportar). Tinge em [tone] quando
/// [active] — assim o usuário vê de relance que há filtro ligado.
class _ToolbarPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color tone;
  final bool active;
  final bool busy;
  final VoidCallback? onTap;

  const _ToolbarPill({
    required this.icon,
    required this.label,
    required this.tone,
    required this.active,
    required this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final enabled = onTap != null;
    final fg = active ? tone : (enabled ? secondary : secondary.withValues(alpha: 0.5));

    return Material(
      color: active
          ? tone.withValues(alpha: isDark ? 0.16 : 0.09)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active
                  ? tone.withValues(alpha: 0.42)
                  : ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
              width: active ? 1.3 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(tone),
                  ),
                )
              else
                Icon(icon, size: 15, color: fg),
              const SizedBox(width: 8),
              // FittedBox: "Filtros · 3" e "Exportando…" não podem estourar
              // a metade da largura em aparelho de 320dp.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.1,
                      color: fg,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditRequestFilterChip extends StatelessWidget {
  final String label;
  final Color tone;
  final bool selected;
  final VoidCallback onTap;

  const _EditRequestFilterChip({
    required this.label,
    required this.tone,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: selected
                ? tone.withValues(alpha: isDark ? 0.18 : 0.10)
                : Colors.transparent,
            border: Border.all(
              color: selected
                  ? tone.withValues(alpha: 0.55)
                  : ThemeHelpers.borderColor(context),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              fontSize: 12.5,
              color:
                  selected ? tone : ThemeHelpers.textSecondaryColor(context),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabSpec {
  final _Tab tab;
  final IconData icon;
  final String label;
  final int count;
  final Color accentColor;

  _TabSpec({
    required this.tab,
    required this.icon,
    required this.label,
    required this.count,
    required this.accentColor,
  });
}

/// Aba **flush** vertical (ícone + rótulo curto + contagem), pensada para um
/// layout fixo de largura igual (sem scroll). Indicador (sublinhado) na cor da
/// fila quando ativa. O rótulo usa `FittedBox` para nunca estourar em telas
/// estreitas.
class _FlushTab extends StatelessWidget {
  final _TabSpec spec;
  final bool selected;
  final VoidCallback onTap;

  const _FlushTab({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = spec.accentColor;
    final fg = selected ? tone : ThemeHelpers.textSecondaryColor(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: tone.withValues(alpha: 0.12),
        highlightColor: tone.withValues(alpha: 0.06),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Ícone com a contagem sobreposta (badge) no canto superior.
                  SizedBox(
                    height: 22,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        Icon(spec.icon, size: 19, color: fg),
                        if (spec.count > 0)
                          Positioned(
                            top: -7,
                            right: -12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              constraints: const BoxConstraints(minWidth: 16),
                              decoration: BoxDecoration(
                                color: tone,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: ThemeHelpers.cardBackgroundColor(
                                      context),
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                spec.count > 99 ? '99+' : '${spec.count}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 9.5,
                                  height: 1.25,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      spec.label,
                      maxLines: 1,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: fg,
                        fontWeight:
                            selected ? FontWeight.w900 : FontWeight.w600,
                        letterSpacing: 0.1,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Indicador (sublinhado) — anima a cor, altura estável p/ não pular.
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              height: 2.5,
              decoration: BoxDecoration(
                color: selected ? tone : Colors.transparent,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelSubsectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  final int count;

  const _PanelSubsectionHeader({
    required this.label,
    required this.icon,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon,
            size: 14,
            color: ThemeHelpers.textSecondaryColor(context)),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
        if (count > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: ThemeHelpers.borderLightColor(context)
                  .withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w900,
                fontSize: 10,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Container(
              height: 1,
              color: ThemeHelpers.borderLightColor(context)
                  .withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }
}

