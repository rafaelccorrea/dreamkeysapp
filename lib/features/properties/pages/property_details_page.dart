import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
// Mapa real da seção Localização — OSM/CARTO sem chave (paridade com o
// PropertyMap/Leaflet do web).
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import '../../../../shared/services/property_service.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/minimal_body_chrome.dart';
import '../../../../shared/widgets/skeleton_box.dart';
import '../../../../shared/widgets/shimmer_image.dart';
import '../../../../shared/widgets/app_error_state.dart';
import '../../../../shared/utils/error_cause.dart';
import '../../../../shared/utils/property_finalidade.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../models/property_activity_models.dart';
import '../services/property_activity_service.dart';
import '../../matches/widgets/matches_badge.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../shared/utils/broker_contact_actions.dart';
import '../../appointments/pages/create_appointment_page.dart';
import '../../appointments/models/appointment_model.dart';
import '../../documents/services/document_service.dart';
import '../../documents/models/document_model.dart';
import '../../documents/pages/create_document_page.dart';
import '../../documents/utils/document_file_actions.dart';
import '../../documents/utils/document_permissions.dart';
import '../../clients/services/client_service.dart';
import '../../documents/widgets/entity_selector.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../shared/services/api_service.dart';
import '../../keys/services/key_service.dart';
import '../../keys/models/key_model.dart' as key_models;
import '../../../../shared/services/gallery_service.dart';
import '../../../../shared/services/module_access_service.dart';
import '../../../../core/constants/app_permissions.dart';
import '../../../../core/constants/feature_visibility.dart';
import '../services/property_approval_service.dart';
import '../widgets/approval_action_sheets.dart';
import '../utils/property_edit_permissions.dart';
import '../utils/property_status_visual.dart';
import '../utils/property_type_visual.dart';
import '../utils/compute_property_score.dart';
import '../utils/public_property_link.dart';
import '../widgets/property_score_panel.dart';
import '../widgets/property_share_sheet.dart';
import '../widgets/property_presentation_pdf_sheet.dart';
import '../widgets/details/property_activation_sheet.dart';
import '../widgets/details/property_approval_banner.dart';
import '../widgets/details/property_details_kit.dart'
    show kPropertyDeletedReadOnlyReason;
import '../widgets/details/property_owner_section.dart';
import '../widgets/details/property_responsibles_section.dart';
import '../widgets/details/property_status_change_sheet.dart';

// Formatter de moeda
final _currencyFormatter = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 2,
);

/// Aba interna da ficha de imóvel.
enum _DetailsTab { details, activity, performance }

extension _DetailsTabQuery on _DetailsTab {
  /// Aba pelo id do web (`?tab=`), com o apelido `updates` → Atividades
  /// (o aviso de atualização aponta para `?tab=updates`, como no web).
  static _DetailsTab? fromQuery(String? raw) {
    final v = raw?.trim().toLowerCase() ?? '';
    switch (v) {
      case 'details':
        return _DetailsTab.details;
      case 'activity':
      case 'updates':
        return _DetailsTab.activity;
      case 'performance':
        return _DetailsTab.performance;
    }
    return null;
  }

  String get label {
    switch (this) {
      case _DetailsTab.details:
        return 'Detalhes';
      case _DetailsTab.activity:
        return 'Atividades';
      case _DetailsTab.performance:
        return 'Desempenho';
    }
  }

  IconData get icon {
    switch (this) {
      case _DetailsTab.details:
        return Icons.description_outlined;
      case _DetailsTab.activity:
        return Icons.history_rounded;
      case _DetailsTab.performance:
        return Icons.insights_rounded;
    }
  }

  /// Acento da aba — mesmas cores do web (`propertySplitTabs.ts`).
  Color get tone {
    switch (this) {
      case _DetailsTab.details:
        return const Color(0xFF6366F1);
      case _DetailsTab.activity:
        return const Color(0xFFD97706);
      case _DetailsTab.performance:
        return const Color(0xFF10B981);
    }
  }
}

/// Página de detalhes da propriedade
class PropertyDetailsPage extends StatefulWidget {
  final String propertyId;
  final Property? initialProperty;

  /// Aba inicial pelo id do web (`details`, `activity`, `performance`;
  /// `updates` = Atividades) — vem do `?tab=` do link. Desconhecida ou sem
  /// acesso → Detalhes.
  final String? initialTab;

  const PropertyDetailsPage({
    super.key,
    required this.propertyId,
    this.initialProperty,
    this.initialTab,
  });

  @override
  State<PropertyDetailsPage> createState() => _PropertyDetailsPageState();
}

class _PropertyDetailsPageState extends State<PropertyDetailsPage> {
  final PropertyService _propertyService = PropertyService.instance;
  final DocumentService _documentService = DocumentService.instance;
  final ClientService _clientService = ClientService.instance;
  final ApiService _apiService = ApiService.instance;
  final KeyService _keyService = KeyService.instance;
  bool _isLoading = true;
  Property? _property;
  String? _errorMessage;
  // Sem o código HTTP não há como separar falta de permissão de servidor fora.
  int _errorStatus = 0;
  Object? _errorDetail;
  bool _errorFromException = false;
  final PageController _imagePageController = PageController();
  int _currentImageIndex = 0;

  // Documentos
  List<Document> _documents = [];
  bool _isLoadingDocuments = false;
  ApiResponse<dynamic>? _documentsFailure;

  // Checklists
  List<dynamic> _checklists = [];
  bool _isLoadingChecklists = false;

  // Despesas
  List<dynamic> _expenses = [];
  bool _isLoadingExpenses = false;
  Map<String, dynamic>? _expensesSummary;

  // Chaves
  List<key_models.Key> _keys = [];
  bool _isLoadingKeys = false;

  // Condomínio vinculado (só quando `condominiumId` existe — paridade web).
  NamedEntityWithAddress? _linkedCondominium;
  bool _loadingCondominium = false;

  /// Aba interna ativa: Visão geral, Comercial ou Gestão.
  _DetailsTab _activeTab = _DetailsTab.details;

  /// Controlador da rolagem — controla FAB "voltar ao topo".
  final ScrollController _detailsScrollController = ScrollController();
  bool _showScrollTopFab = false;
  String? _lastImageDiagnosticsSignature;

  Map<String, dynamic>? _asStringKeyedMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map(
        (key, entryValue) => MapEntry(key.toString(), entryValue),
      );
    }
    return null;
  }

  double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.replaceAll(',', '.'));
    }
    return null;
  }

  List<dynamic> _extractChecklists(dynamic payload) {
    if (payload is List) return payload;
    final rootMap = _asStringKeyedMap(payload);
    if (rootMap == null) return const [];

    final directCandidates = [
      rootMap['checklists'],
      rootMap['data'],
      rootMap['items'],
      rootMap['results'],
    ];
    for (final candidate in directCandidates) {
      if (candidate is List) return candidate;
    }

    final nestedData = _asStringKeyedMap(rootMap['data']);
    if (nestedData != null) {
      final nestedCandidates = [
        nestedData['checklists'],
        nestedData['data'],
        nestedData['items'],
        nestedData['results'],
      ];
      for (final candidate in nestedCandidates) {
        if (candidate is List) return candidate;
      }
    }

    return const [];
  }

  double _extractChecklistCompletionPercentage(Map<String, dynamic> checklist) {
    final stats =
        _asStringKeyedMap(checklist['statistics']) ??
        _asStringKeyedMap(checklist['stats']) ??
        _asStringKeyedMap(checklist['metrics']);

    final directPercentage =
        _asDouble(stats?['completionPercentage']) ??
        _asDouble(stats?['completion_percentage']) ??
        _asDouble(stats?['progressPercentage']) ??
        _asDouble(stats?['progress_percentage']) ??
        _asDouble(stats?['completion']) ??
        _asDouble(checklist['completionPercentage']) ??
        _asDouble(checklist['completion_percentage']);

    if (directPercentage != null) {
      return directPercentage.clamp(0, 100).toDouble();
    }

    final totalTasks =
        _asDouble(stats?['totalTasks']) ??
        _asDouble(stats?['total_tasks']) ??
        _asDouble(stats?['total']) ??
        _asDouble(checklist['totalTasks']) ??
        _asDouble(checklist['total_tasks']);
    final completedTasks =
        _asDouble(stats?['completedTasks']) ??
        _asDouble(stats?['completed_tasks']) ??
        _asDouble(stats?['doneTasks']) ??
        _asDouble(stats?['done_tasks']) ??
        _asDouble(stats?['completed']) ??
        _asDouble(checklist['completedTasks']) ??
        _asDouble(checklist['completed_tasks']) ??
        _asDouble(checklist['doneTasks']) ??
        _asDouble(checklist['done_tasks']);

    if (totalTasks != null && totalTasks > 0 && completedTasks != null) {
      return ((completedTasks / totalTasks) * 100).clamp(0, 100).toDouble();
    }

    return 0;
  }

  /// Avaliação alinhada às regras do backend (master/admin/manager, aprovador
  /// na matriz, vínculo como responsável/captador, ou autorização de venda
  /// assinada bloqueando vinculados). Veja
  /// `property_edit_permissions.dart` para a lógica completa.
  PropertyEditPermissionResult get _editPermission {
    final access = ModuleAccessService.instance;
    return evaluatePropertyEditPermission(
      property: _property,
      currentUserId: access.userId,
      userRole: access.userRole,
      hasPermission: access.hasPermission,
    );
  }

  /// Excluído (soft delete) abre só para consulta — nenhuma escrita (web).
  bool get _isDeletedProperty => _property?.isDeleted == true;

  bool get _canEditProperty =>
      _editPermission.canEdit && !_isDeletedProperty;

  bool get _canDeleteProperty {
    final access = ModuleAccessService.instance;
    return canUserDeleteThisPropertyRecord(
      property: _property,
      currentUserId: access.userId,
      userRole: access.userRole,
      hasPermission: access.hasPermission,
    );
  }

  /// Pode deletar imagens individuais do imóvel direto pelo carrossel
  /// fullscreen (paridade com `imobx-front/PropertyGalleryFullscreenPage`).
  ///
  /// Espelha exatamente a regra do web:
  ///   `master/admin OR property:approve_publication OR property:approve_availability`
  ///
  /// Backend: `DELETE /gallery/:id` valida ownership pela company; o front
  /// é quem decide se o botão aparece. Útil pra reprovar fotos individuais
  /// (não-quadradas, categoria errada) sem precisar mandar a publicação
  /// inteira de volta pra fila.
  bool get _canDeletePropertyImages {
    if (_isDeletedProperty) return false;
    final access = ModuleAccessService.instance;
    final role = access.userRole?.toLowerCase() ?? '';
    if (role == 'master' || role == 'admin') return true;
    return access.hasPermission(AppPermissions.propertyApprovePublication) ||
        access.hasPermission(AppPermissions.propertyApproveAvailability);
  }

  /// Define a imagem principal direto pelo carrossel fullscreen. Liberado para:
  ///   - quem pode editar a ficha do imóvel (responsável/captador/gestão)
  ///   - quem tem permissão de aprovação (mesma regra do botão de excluir foto)
  ///
  /// Backend: `PATCH /gallery/:id/set-main`. Em caso de sucesso, o front
  /// atualiza local + sinaliza ao detalhe pra recarregar e mostrar a nova
  /// foto principal no carrossel + cards.
  bool get _canSetMainPropertyImage =>
      _canEditProperty || _canDeletePropertyImages;

  /// Apenas master/admin podem desfazer venda (SOLD â†’ AVAILABLE).
  bool get _canUndoSold {
    if (_isDeletedProperty) return false;
    final access = ModuleAccessService.instance;
    final role = access.userRole?.toLowerCase() ?? '';
    if (role != 'master' && role != 'admin') return false;
    return _property?.status == PropertyStatus.sold;
  }

  /// Perfis elevados (master/admin/manager) podem republicar no site — mesma
  /// regra do web (`canChangePropertyStatusElevated`).
  bool get _canChangePropertyStatusElevated {
    if (_isDeletedProperty) return false;
    final role = ModuleAccessService.instance.userRole?.toLowerCase() ?? '';
    return role == 'master' || role == 'admin' || role == 'manager';
  }

  /// Quem pode republicar no site — espelha o web: perfis elevados
  /// (`skipPermissionCheck`) OU `property:approve_publication`.
  bool get _republishAllowed =>
      _canChangePropertyStatusElevated ||
      ModuleAccessService.instance
          .hasPermission(AppPermissions.propertyApprovePublication);

  /// "Republicar no site" some só quando "Tornar disponível" ocupa o lugar
  /// (vendido + master/admin); quem não pode vê a ação travada.
  bool get _canRepublishOnSite => _republishAllowed && !_canUndoSold;

  /// Motivo do cadeado do Republicar — texto do PermissionButton do web.
  static const String _republishLockedReason =
      'Sem a permissão "Aprovar publicação de imóveis no site". Fale com o '
      'seu gestor ou com o suporte.';

  bool _undoSoldLoading = false;
  bool _republishLoading = false;
  /// Base pública do site da empresa (para o link de compartilhar). Carregada
  /// uma vez via `/public-site-config`.
  String? _siteBaseUrl;

  // ─── Aprovação (na própria tela de detalhes, para quem tem permissão) ───
  bool _approvalBusy = false;

  bool get _canApproveAvailability => ModuleAccessService.instance
      .hasPermission(AppPermissions.propertyApproveAvailability);
  bool get _canRejectAvailability => ModuleAccessService.instance
      .hasPermission(AppPermissions.propertyRejectAvailability);
  bool get _canApprovePublication => ModuleAccessService.instance
      .hasPermission(AppPermissions.propertyApprovePublication);
  bool get _canRejectPublication => ModuleAccessService.instance
      .hasPermission(AppPermissions.propertyRejectPublication);

  bool _availabilityPending(Property p) =>
      p.status == PropertyStatus.pendingApproval;

  bool _publicationPending(Property p) =>
      (p.publicationRequestedAt ?? '').isNotEmpty &&
      p.isAvailableForSite != true &&
      (p.publicationRejectedAt ?? '').isEmpty;

  bool _showApprovalSection(Property p) =>
      (_availabilityPending(p) &&
          (_canApproveAvailability || _canRejectAvailability)) ||
      (_publicationPending(p) &&
          (_canApprovePublication || _canRejectPublication));

  // ─── Conversa de aprovação (chat aprovador ↔ responsável) ──────────────
  // Paridade com `PropertyApprovalCommunicationPanel` do web: o gate é
  // 100% server-side (`canParticipateInApprovalThread` — gestão, aprovadores,
  // responsável/adicionais, captadores). Quem está fora leva 403 no GET e a
  // seção inteira some — mesma condição do web, onde o painel vira `null`.
  // Quem vê, envia: leitura e escrita usam o MESMO gate no backend.
  List<PropertyHistoryEntry> _threadMessages = const [];
  bool _threadLoading = true;
  bool _threadLoadFailed = false;
  bool _threadForbidden = false;
  bool _threadSending = false;
  bool _threadShowAll = false;

  /// Fila selecionada para envio — paridade com o segmented "Enviar na fila"
  /// do web (default `availability`, igual lá).
  ApprovalType _threadQueue = ApprovalType.availability;
  final TextEditingController _threadComposer = TextEditingController();
  final ScrollController _threadScroll = ScrollController();

  Future<void> _loadApprovalThread() async {
    if (widget.propertyId.trim().isEmpty) return;
    setState(() {
      _threadLoading = true;
      _threadLoadFailed = false;
    });
    // Sem `context` → traz as DUAS filas misturadas em ordem cronológica
    // (mesma chamada da ficha web). O GET também marca a conversa como vista.
    final res = await PropertyApprovalService.instance
        .getApprovalThread(widget.propertyId);
    if (!mounted) return;
    if (res.success) {
      setState(() {
        _threadMessages = res.data ?? const [];
        _threadLoading = false;
      });
      _threadScrollToBottom();
    } else if (res.statusCode == 403) {
      setState(() {
        _threadForbidden = true;
        _threadLoading = false;
      });
    } else {
      setState(() {
        _threadLoadFailed = true;
        _threadLoading = false;
      });
    }
  }

  void _threadScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_threadScroll.hasClients) return;
      _threadScroll.jumpTo(_threadScroll.position.maxScrollExtent);
    });
  }

  Future<void> _sendApprovalThreadMessage() async {
    final text = _threadComposer.text.trim();
    if (text.isEmpty || _threadSending) return;
    setState(() => _threadSending = true);
    final res =
        await PropertyApprovalService.instance.postApprovalThreadMessage(
      widget.propertyId,
      message: text,
      queue: _threadQueue,
    );
    if (!mounted) return;
    setState(() => _threadSending = false);
    if (res.success && res.data != null) {
      setState(() {
        _threadMessages = [..._threadMessages, res.data!];
        _threadComposer.clear();
      });
      _threadScrollToBottom();
    } else {
      // Erro → SnackBar com a mensagem real da API (403 do envio incluso).
      _approvalSnack(res.message ?? 'Erro ao enviar mensagem.');
    }
  }

  void _approvalSnack(String msg, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: ok ? AppColors.status.success : AppColors.status.error,
      ),
    );
  }

  Future<void> _doApproveAvailability(Property p) async {
    setState(() => _approvalBusy = true);
    final res = await PropertyApprovalService.instance
        .approveAvailability(p.id, applyWatermark: false);
    if (!mounted) return;
    setState(() => _approvalBusy = false);
    if (res.success) {
      _approvalSnack('Disponibilidade aprovada.', ok: true);
      _refreshAfterChange();
    } else {
      _approvalSnack(res.message ?? 'Falha ao aprovar disponibilidade.');
    }
  }

  Future<void> _doRejectAvailability(Property p) async {
    final reason = await showRejectReasonSheet(
      context: context,
      title: 'Recusar disponibilidade',
      propertySubtitle: p.title.isEmpty ? p.code : p.title,
    );
    if (reason == null) return;
    setState(() => _approvalBusy = true);
    final res = await PropertyApprovalService.instance
        .rejectAvailability(p.id, reason: reason);
    if (!mounted) return;
    setState(() => _approvalBusy = false);
    if (res.success) {
      _approvalSnack('Imóvel recusado. Motivo enviado ao responsável.',
          ok: true);
      _refreshAfterChange();
    } else {
      _approvalSnack(res.message ?? 'Falha ao recusar disponibilidade.');
    }
  }

  Future<void> _doApprovePublication(Property p) async {
    setState(() => _approvalBusy = true);
    final res = await PropertyApprovalService.instance
        .approvePublication(p.id, applyWatermark: null);
    if (!mounted) return;
    setState(() => _approvalBusy = false);
    if (res.success) {
      _approvalSnack('Publicação aprovada — imóvel já está no site.', ok: true);
      _refreshAfterChange();
    } else {
      _approvalSnack(res.message ?? 'Falha ao aprovar publicação.');
    }
  }

  Future<void> _doRejectPublication(Property p) async {
    final reason = await showRejectReasonSheet(
      context: context,
      title: 'Recusar publicação no site',
      propertySubtitle: p.title.isEmpty ? p.code : p.title,
    );
    if (reason == null) return;
    setState(() => _approvalBusy = true);
    final res = await PropertyApprovalService.instance
        .rejectPublication(p.id, reason: reason);
    if (!mounted) return;
    setState(() => _approvalBusy = false);
    if (res.success) {
      _approvalSnack('Publicação recusada. Responsável foi notificado.',
          ok: true);
      _refreshAfterChange();
    } else {
      _approvalSnack(res.message ?? 'Falha ao recusar publicação.');
    }
  }

  // â”€â”€â”€ Aba Atividades (histórico + atualizações) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  final PropertyActivityService _activityService =
      PropertyActivityService.instance;
  List<PropertyHistoryEntry> _history = const [];
  bool _loadingHistory = false;
  bool _historyLoaded = false;
  PropertyUpdatesResponse _updates = PropertyUpdatesResponse.empty;
  bool _loadingUpdates = false;
  bool _updatesLoaded = false;

  /// Falhas das leituras da aba Atividades (a causa vai para o erro padrão).
  ApiResponse<dynamic>? _historyFailure;
  ApiResponse<dynamic>? _updatesFailure;

  /// "Carregar mais atualizações" (páginas de 15, como o web).
  static const int _kUpdatesPageSize = 15;
  bool _loadingMoreUpdates = false;
  bool _moreUpdatesFailed = false;
  final TextEditingController _updateComposer = TextEditingController();
  bool _submittingUpdate = false;

  // â”€â”€â”€ Aba Desempenho (engajamento + observações) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  PropertyEngagementStats? _engagement;
  List<PropertyEngagementByChannel> _engagementByChannel = const [];
  bool _loadingEngagement = false;
  bool _engagementLoaded = false;
  bool _editingNotes = false;
  final TextEditingController _notesController = TextEditingController();
  bool _savingNotes = false;

  @override
  void initState() {
    super.initState();
    _property = widget.initialProperty;
    _activeTab =
        _DetailsTabQuery.fromQuery(widget.initialTab) ?? _DetailsTab.details;
    // Sempre inicia em loading para evitar "tela vazia" com `initialProperty`
    // parcial e garantir feedback visual consistente.
    _isLoading = true;
    _loadProperty();
    if (_activeTab == _DetailsTab.activity) _ensureActivityLoaded();
    _loadSiteBaseUrl();
    _loadApprovalThread();
    _detailsScrollController.addListener(_handleDetailsScroll);
  }

  /// Base pública do site da empresa via [PublicPropertyLink] (cache por
  /// sessão + fallback União para corretor sem `public_site:view`). Null →
  /// seção/botão de compartilhar não aparecem.
  Future<void> _loadSiteBaseUrl() async {
    final base = await PublicPropertyLink.resolveBaseUrl();
    if (!mounted || base == null) return;
    setState(() => _siteBaseUrl = base);
  }

  /// URL pública completa do imóvel no site (ex.: `https://site/imovel/31020`).
  /// `null` quando não há base do site.
  ///
  /// Sem consumidor direto desde que a seção "Compartilhar" saiu do rodapé
  /// (o share da AppBar/sheet resolve o link via [PublicPropertyLink]) —
  /// mantido como builder canônico do link público desta tela.
  // ignore: unused_element
  String? _publicPropertyUrl(Property property) =>
      PublicPropertyLink.buildUrl(property, _siteBaseUrl);

  /// Toque numa ação travada: diz o motivo (a ação fica à vista em vez de
  /// sumir, como o botão com cadeado do web).
  void _showLockedReason(String reason) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 18,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(reason)),
            ],
          ),
          duration: const Duration(seconds: 5),
        ),
      );
  }

  /// Apresentação em PDF para enviar ao cliente — de todos que veem o
  /// imóvel (`property:view`, mesmo gate do botão da ficha web).
  void _openPresentationPdf() {
    final property = _property;
    if (property == null) return;
    showPropertyPresentationPdfSheet(
      context,
      propertyId:
          property.id.trim().isNotEmpty ? property.id : widget.propertyId,
      propertyTitle: property.title,
      propertyCode: property.code,
    );
  }

  /// Sheet de ações do detalhe — substitui o PopupMenu nativo do Material
  /// (fora do padrão da casa). Mesma anatomia do sheet da listagem:
  /// grabber + header editorial + tiles com roundel tinted.
  void _showDetailActionsSheet({
    required bool canEdit,
    required bool canDelete,
    required bool hasOffersShortcut,
  }) {
    final property = _property;
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final isDark = theme.brightness == Brightness.dark;
        final muted = ThemeHelpers.textSecondaryColor(sheetContext);

        // `lockedReason` != null: a ação existe mas não é desta pessoa —
        // fica à vista, apagada, com cadeado e o motivo no lugar da dica
        // (esconder ensinaria que a função não existe).
        Widget tile({
          required IconData icon,
          required String label,
          required String subtitle,
          required Color color,
          required VoidCallback onTap,
          bool destructive = false,
          bool badge = false,
          String? lockedReason,
        }) {
          final locked = lockedReason != null;
          if (locked) color = muted;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: locked ? null : onTap,
              borderRadius: BorderRadius.circular(14),
              splashColor: color.withValues(alpha: 0.16),
              highlightColor: color.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                child: Row(
                  crossAxisAlignment: locked
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color:
                                color.withValues(alpha: isDark ? 0.18 : 0.12),
                            border: Border.all(
                              color: color.withValues(
                                  alpha: isDark ? 0.34 : 0.22),
                            ),
                          ),
                          child: Icon(icon, size: 19, color: color),
                        ),
                        if (badge)
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: AppColors.status.error,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: ThemeHelpers.cardBackgroundColor(
                                      sheetContext),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.15,
                              fontSize: 14.5,
                              color: locked
                                  ? muted
                                  : destructive
                                      ? color
                                      : ThemeHelpers.textColor(sheetContext),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            lockedReason ?? subtitle,
                            maxLines: locked ? 4 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: muted,
                              fontSize: 11.5,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (locked) ...[
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.lock_outline_rounded,
                          size: 16,
                          color: muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }

        final sheet = Container(
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(sheetContext),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(
                color: ThemeHelpers.borderColor(sheetContext)
                    .withValues(alpha: 0.55),
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: muted.withValues(alpha: 0.32),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 12, 14, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'AÇÕES DO IMÓVEL',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.primary.primary,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.6,
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              property?.title.isNotEmpty == true
                                  ? property!.title
                                  : 'Imóvel',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.4,
                                color: ThemeHelpers.textColor(sheetContext),
                                height: 1.15,
                                fontSize: 19,
                              ),
                            ),
                            if (property != null) ...[
                              const SizedBox(height: 7),
                              Row(
                                children: [
                                  if ((property.code ?? '')
                                      .trim()
                                      .isNotEmpty) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(6),
                                        color:
                                            muted.withValues(alpha: 0.10),
                                        border: Border.all(
                                          color: muted.withValues(
                                              alpha: 0.25),
                                        ),
                                      ),
                                      child: Text(
                                        '#${property.code!.trim()}',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 10.5,
                                          color: muted,
                                          height: 1,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Expanded(
                                    child: Text(
                                      [property.address, property.city]
                                          .where((s) => s.trim().isNotEmpty)
                                          .join(' · '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 11.5,
                                        color: muted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 22),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        ThemeHelpers.borderColor(sheetContext),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
                Builder(
                  builder: (context) {
                    // Tiles montados em lista pra intercalar hairlines
                    // (flush: separação por linha, não por espaço morto).
                    final actionTiles = <Widget>[
                      // Ação nº 1 do corretor — só quando o imóvel está
                      // publicado no site (mesmo gate do web).
                      if (property != null &&
                          property.isAvailableForSite == true &&
                          _siteBaseUrl != null)
                        tile(
                          icon: Icons.share_rounded,
                          label: 'Compartilhar link',
                          subtitle: 'WhatsApp, link do site e mensagem pronta',
                          color: const Color(0xFF25D366),
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            Future.microtask(() {
                              if (!mounted) return;
                              showPropertyShareSheet(this.context, property);
                            });
                          },
                        ),
                      // De todos que veem o imóvel — o PDF é o material que
                      // o corretor manda ao cliente (mesmo gate do web).
                      if (property != null)
                        tile(
                          icon: Icons.picture_as_pdf_outlined,
                          label: 'Apresentação em PDF',
                          subtitle:
                              'Fotos, valores e seu contato para o cliente',
                          color: isDark
                              ? AppColors.status.infoDarkMode
                              : AppColors.status.info,
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            Future.microtask(() {
                              if (!mounted) return;
                              _openPresentationPdf();
                            });
                          },
                        ),
                      if (property != null)
                        tile(
                          icon: Icons.edit_rounded,
                          label: 'Editar imóvel',
                          subtitle: 'Dados, valores, proprietário e galeria',
                          color: const Color(0xFF6366F1),
                          lockedReason: _statusChangeLockReason(property),
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            Navigator.of(this.context).pushNamed(
                              '/properties/${widget.propertyId}/edit',
                            );
                          },
                        ),
                      if (property != null)
                        tile(
                          icon: Icons.swap_horiz_rounded,
                          label: 'Alterar status',
                          subtitle: 'Disponível, reservado, vendido, alugado…',
                          color: isDark
                              ? AppColors.status.infoDarkMode
                              : AppColors.status.info,
                          lockedReason: _statusChangeLockReason(property),
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            Future.microtask(() {
                              if (!mounted) return;
                              _openStatusChange();
                            });
                          },
                        ),
                      if (property != null && !_canUndoSold)
                        tile(
                          icon: Icons.published_with_changes_rounded,
                          label: 'Republicar no site',
                          subtitle: 'Volta para Disponível, ativo e no site',
                          color: isDark
                              ? AppColors.status.successDarkMode
                              : AppColors.status.success,
                          lockedReason: property.isDeleted
                              ? kPropertyDeletedReadOnlyReason
                              : _republishAllowed
                                  ? null
                                  : _republishLockedReason,
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            _republishOnSite();
                          },
                        ),
                      if (property != null)
                        tile(
                          icon: Icons.power_settings_new_rounded,
                          label: property.isActive
                              ? 'Desativar imóvel'
                              : 'Ativar imóvel',
                          subtitle: property.isActive
                              ? 'Tira do site e da vitrine, ou só da venda '
                                  'ou da locação'
                              : 'Volta a aparecer na vitrine e no site',
                          color: property.isActive
                              ? ThemeHelpers.textColor(sheetContext)
                              : (isDark
                                  ? AppColors.status.successDarkMode
                                  : AppColors.status.success),
                          lockedReason: property.isDeleted
                              ? kPropertyDeletedReadOnlyReason
                              : _canChangePropertyStatusElevated
                                  ? null
                                  : kPropertyToggleActiveBlockedReason,
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            Future.microtask(() {
                              if (!mounted) return;
                              _openActivation();
                            });
                          },
                        ),
                      if (hasOffersShortcut)
                        tile(
                          icon: Icons.request_quote_rounded,
                          label: 'Ver ofertas',
                          subtitle: 'Há propostas pendentes neste imóvel',
                          color: const Color(0xFF0891B2),
                          badge: true,
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            Navigator.of(this.context).pushNamed(
                              '/properties/offers',
                              arguments: {'propertyId': widget.propertyId},
                            );
                          },
                        ),
                      if (property != null)
                        tile(
                          icon: Icons.delete_outline_rounded,
                          label: 'Excluir permanentemente',
                          subtitle: 'Remove o imóvel do portfólio da empresa',
                          color: theme.colorScheme.error,
                          destructive: true,
                          lockedReason: property.isDeleted
                              ? kPropertyDeletedReadOnlyReason
                              : canDelete
                                  ? null
                                  : !canEdit
                                      ? _editPermission.reasonMessage
                                      : 'Sem a permissão "Excluir imóveis". '
                                          'Fale com o seu gestor ou com o '
                                          'suporte.',
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            _deleteProperty();
                          },
                        ),
                    ];

                    return Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < actionTiles.length; i++) ...[
                              if (i > 0)
                                Padding(
                                  padding: const EdgeInsets.only(left: 62),
                                  child: Container(
                                    height: 1,
                                    color: ThemeHelpers.borderColor(sheetContext)
                                        .withValues(alpha: 0.25),
                                  ),
                                ),
                              actionTiles[i],
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
        return ConstrainedBox(
          // Teto de 0,88 com a lista rolando: deitado ou com fonte grande,
          // as ações não estouram a folha.
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.88,
          ),
          child: sheet,
        );
      },
    );
  }

  void _handleDetailsScroll() {
    if (!_detailsScrollController.hasClients) return;
    final offset = _detailsScrollController.offset;
    final shouldShow = offset > 480;
    if (shouldShow != _showScrollTopFab) {
      setState(() => _showScrollTopFab = shouldShow);
    }
  }

  /// Documentos do imóvel — 20 por vez, como o `useDocumentsByEntity` do
  /// web. Falha fica registrada para a seção mostrar a causa.
  Future<void> _loadDocuments() async {
    if (widget.propertyId.isEmpty) return;
    if (!DocumentPermissions.moduleEnabled) return;

    setState(() {
      _isLoadingDocuments = true;
    });

    final response = await _documentService.getDocuments(
      filters: DocumentFilters(propertyId: widget.propertyId),
      page: 1,
      limit: 20,
    );
    if (!mounted) return;
    setState(() {
      _isLoadingDocuments = false;
      if (response.success && response.data != null) {
        _documents = response.data!.data;
        _documentsFailure = null;
      } else {
        _documentsFailure = response;
      }
    });
  }

  Future<void> _loadChecklists() async {
    if (widget.propertyId.isEmpty) return;

    setState(() {
      _isLoadingChecklists = true;
    });

    try {
      final response = await _apiService.get<dynamic>(
        ApiConstants.saleChecklistsByProperty(widget.propertyId),
      );

      if (mounted) {
        setState(() {
          _isLoadingChecklists = false;
          if (response.success && response.data != null) {
            _checklists = _extractChecklists(response.data);
          }
        });
      }
    } catch (e) {
      debugPrint('âŒ [PROPERTY_DETAILS] Erro ao carregar checklists: $e');
      if (mounted) {
        setState(() {
          _isLoadingChecklists = false;
        });
      }
    }
  }

  Future<void> _loadExpenses() async {
    if (widget.propertyId.isEmpty) return;

    setState(() {
      _isLoadingExpenses = true;
    });

    try {
      // Carregar lista de despesas
      final expensesResponse = await _apiService.get<dynamic>(
        ApiConstants.propertyExpenses(widget.propertyId),
      );

      // Carregar resumo de despesas
      final summaryResponse = await _apiService.get<dynamic>(
        ApiConstants.propertyExpensesSummary(widget.propertyId),
      );

      if (mounted) {
        setState(() {
          _isLoadingExpenses = false;
          if (expensesResponse.success && expensesResponse.data != null) {
            if (expensesResponse.data is List) {
              _expenses = expensesResponse.data as List<dynamic>;
            } else if (expensesResponse.data is Map<String, dynamic>) {
              final data = expensesResponse.data as Map<String, dynamic>;
              _expenses =
                  data['data'] as List<dynamic>? ??
                  data['expenses'] as List<dynamic>? ??
                  [];
            }
          }
          if (summaryResponse.success && summaryResponse.data != null) {
            _expensesSummary = summaryResponse.data as Map<String, dynamic>;
          }
        });
      }
    } catch (e) {
      debugPrint('âŒ [PROPERTY_DETAILS] Erro ao carregar despesas: $e');
      if (mounted) {
        setState(() {
          _isLoadingExpenses = false;
        });
      }
    }
  }

  Future<void> _loadLinkedCondominium(String id) async {
    setState(() => _loadingCondominium = true);
    try {
      final response = await _propertyService.getCondominiumById(id);
      if (mounted) {
        setState(() {
          _loadingCondominium = false;
          _linkedCondominium =
              response.success ? response.data : null;
        });
      }
    } catch (e) {
      debugPrint('âŒ [PROPERTY_DETAILS] condomínio: $e');
      if (mounted) {
        setState(() {
          _loadingCondominium = false;
          _linkedCondominium = null;
        });
      }
    }
  }

  Color _salePriceColor(bool isDark) =>
      isDark ? const Color(0xFF4FC77D) : const Color(0xFF16A34A);

  Color _rentPriceColor(bool isDark) =>
      isDark ? const Color(0xFFE6B84C) : const Color(0xFFD97706);

  Future<void> _loadKeys() async {
    if (widget.propertyId.isEmpty) return;

    setState(() {
      _isLoadingKeys = true;
    });

    try {
      // Carregar lista de chaves usando KeyService
      final keysResponse = await _keyService.getKeys(
        filters: key_models.KeyFilters(propertyId: widget.propertyId),
      );

      if (mounted) {
        setState(() {
          _isLoadingKeys = false;
          if (keysResponse.success && keysResponse.data != null) {
            _keys = keysResponse.data!;
          }
        });
      }
    } catch (e) {
      debugPrint('âŒ [PROPERTY_DETAILS] Erro ao carregar chaves: $e');
      if (mounted) {
        setState(() {
          _isLoadingKeys = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _imagePageController.dispose();
    _updateComposer.dispose();
    _notesController.dispose();
    _threadComposer.dispose();
    _threadScroll.dispose();
    _detailsScrollController
      ..removeListener(_handleDetailsScroll)
      ..dispose();
    super.dispose();
  }

  /// Carrega a ficha. [silent]: depois de uma ação na própria tela — não
  /// troca o conteúdo pelo esqueleto (a rolagem fica onde está) nem recarrega
  /// documentos/checklists/despesas/chaves, que a ação não mexe.
  Future<void> _loadProperty({bool silent = false}) async {
    if (widget.propertyId.trim().isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'ID do imóvel inválido.';
      });
      return;
    }

    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _errorStatus = 0;
        _errorDetail = null;
        _errorFromException = false;
      });
    }

    try {
      final response = await _propertyService.getPropertyById(
        widget.propertyId,
      );

      if (mounted) {
        if (response.success && response.data != null) {
          final property = response.data!;
          if (property.id.trim().isEmpty) {
            setState(() {
              _errorMessage = 'Imóvel retornou sem identificador válido.';
              _isLoading = false;
            });
            return;
          }
          final condoId = property.condominiumId?.trim();
          final condoChanged =
              condoId != _property?.condominiumId?.trim();
          setState(() {
            _property = property;
            _isLoading = false;
            if (!silent || condoChanged) _linkedCondominium = null;
          });
          _debugLogPropertyImageDiagnostics(
            property,
            source: 'loadProperty.success',
          );
          // Carregar dados relacionados após carregar propriedade
          if (!silent) {
            _loadDocuments();
            _loadChecklists();
            _loadExpenses();
            _loadKeys();
          }
          if (condoId != null &&
              condoId.isNotEmpty &&
              (!silent || condoChanged)) {
            _loadLinkedCondominium(condoId);
          }
          if (_activeTab == _DetailsTab.performance) {
            _ensurePerformanceLoaded();
          }
        } else {
          setState(() {
            // Se já existe algum snapshot local da propriedade, mantém a tela
            // renderizada em vez de trocar para estado de erro cheio.
            if (_property == null) {
              _errorMessage =
                  response.message ?? 'Erro ao carregar propriedade';
              _errorStatus = response.statusCode;
              _errorDetail = response.error;
            }
            _isLoading = false;
          });
          if (silent) _warnStaleProperty();
        }
      }
    } catch (e) {
      debugPrint('âŒ [PROPERTY_DETAILS] Erro: $e');
      if (mounted) {
        setState(() {
          if (_property == null) {
            _errorMessage = 'Erro ao conectar com o servidor';
            _errorStatus = 0;
            _errorDetail = e;
            _errorFromException = true;
          }
          _isLoading = false;
        });
        if (silent) _warnStaleProperty();
      }
    }
  }

  /// A ação deu certo, mas a ficha não recarregou: a tela avisa que pode
  /// estar desatualizada e oferece tentar de novo.
  void _warnStaleProperty() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Feito. A ficha não atualizou agora e pode estar desatualizada.',
        ),
        action: SnackBarAction(
          label: 'Atualizar',
          onPressed: () => _loadProperty(silent: true),
        ),
      ),
    );
  }

  /// Depois de uma ação que muda o imóvel (status, ativo, aprovação,
  /// reenvio, fotos, clientes): recarga silenciosa da ficha — nunca troca
  /// `_property` pela resposta do PATCH, que vem sem os campos só do detalhe
  /// (proprietário, responsáveis) — e o histórico é buscado de novo.
  void _refreshAfterChange() {
    if (!mounted) return;
    _historyLoaded = false;
    _updatesLoaded = false;
    _engagementLoaded = false;
    _loadProperty(silent: true).then((_) {
      if (!mounted) return;
      if (_activeTab == _DetailsTab.performance) _ensurePerformanceLoaded();
    });
    if (_activeTab == _DetailsTab.activity) _ensureActivityLoaded();
  }

  /// "Alterar status" — como no hero do web: todos veem; quem não pode
  /// editar a ficha (ou imóvel excluído) abre a folha travada com o motivo.
  Future<void> _openStatusChange() async {
    final property = _property;
    if (property == null) return;
    final changed = await showPropertyStatusChangeSheet(
      context: context,
      property: property,
      canRentOutKeepSale: _canChangePropertyStatusElevated,
      lockedReason: _statusChangeLockReason(property),
    );
    if (changed) _refreshAfterChange();
  }

  String? _statusChangeLockReason(Property property) =>
      propertyStatusChangeLockReason(
        property: property,
        permission: _editPermission,
      );

  /// Ativar/Desativar (escopo + motivo) — master/admin/gestor, como o
  /// `PropertyActiveToggle` do web.
  Future<void> _openActivation() async {
    final property = _property;
    if (property == null) return;
    final changed = await showPropertyActivationSheet(
      context: context,
      property: property,
      canToggle: _canChangePropertyStatusElevated,
      lockedReason: property.isDeleted ? kPropertyDeletedReadOnlyReason : null,
    );
    if (changed) _refreshAfterChange();
  }

  void _openApprovalsQueue() {
    Navigator.of(context).pushNamed(AppRoutes.propertyApprovals);
  }

  Future<void> _confirmAndUndoSold() async {
    if (!_canUndoSold || _undoSoldLoading) return;
    final property = _property;
    if (property == null || property.id.trim().isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tornar imóvel disponível?'),
        content: Text(
          'O status de vendido será removido. O imóvel${property.code != null && property.code!.trim().isNotEmpty ? ' ${property.code!.trim()}' : ''} voltará ao cadastro como disponível e a ficha será reativada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Tornar disponível'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _undoSoldLoading = true);
    try {
      final response = await _propertyService.changePropertyStatus(
        property.id,
        status: PropertyStatus.available,
        notes: 'Venda desfeita — imóvel disponível novamente',
      );

      if (!mounted) return;

      if (response.success && response.data != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Imóvel disponível novamente.'),
            backgroundColor: AppColors.status.success,
          ),
        );
        _refreshAfterChange();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response.message ?? 'Não foi possível desfazer a venda.',
            ),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _undoSoldLoading = false);
      }
    }
  }

  Future<void> _republishOnSite() async {
    if (!_canRepublishOnSite || _republishLoading) return;
    final property = _property;
    if (property == null || property.id.trim().isEmpty) return;

    setState(() => _republishLoading = true);
    try {
      final response = await _propertyService.republishOnSite(property.id);
      if (!mounted) return;

      if (response.success && response.data != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Imóvel republicado no site.'),
            backgroundColor: AppColors.status.success,
          ),
        );
        _refreshAfterChange();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response.message ?? 'Não foi possível republicar o imóvel.',
            ),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _republishLoading = false);
      }
    }
  }

  void _openScheduleVisit(Property property) {
    final location = [
      property.address,
      property.neighborhood,
      property.city,
      property.state,
    ].where((s) => s.trim().isNotEmpty).join(', ');

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CreateAppointmentPage(
          initialTitle: 'Visita — ${property.title}',
          initialLocation: location,
          initialType: AppointmentType.visit,
          propertyId: property.id,
        ),
      ),
    );
  }

  void _onTabSelected(_DetailsTab tab) {
    setState(() => _activeTab = tab);
    if (tab == _DetailsTab.activity) _ensureActivityLoaded();
    if (tab == _DetailsTab.performance) _ensurePerformanceLoaded();
  }

  Future<void> _ensureActivityLoaded() async {
    final id = _property?.id ?? widget.propertyId;
    if (id.trim().isEmpty) return;

    if (!_historyLoaded && !_loadingHistory) {
      setState(() => _loadingHistory = true);
      final h = await _activityService.getHistoryResult(id);
      if (mounted) {
        setState(() {
          if (h.success) {
            _history = h.data ?? const [];
            _historyFailure = null;
          } else {
            _historyFailure = h;
          }
          _loadingHistory = false;
          _historyLoaded = true;
        });
      }
    }
    if (!_updatesLoaded && !_loadingUpdates) {
      setState(() => _loadingUpdates = true);
      final u = await _activityService.getUpdatesPage(
        id,
        limit: _kUpdatesPageSize,
      );
      if (mounted) {
        setState(() {
          if (u.success && u.data != null) {
            _updates = u.data!;
            _updatesFailure = null;
          } else {
            _updatesFailure = u;
          }
          _moreUpdatesFailed = false;
          _loadingUpdates = false;
          _updatesLoaded = true;
        });
      }
    }
  }

  /// Tenta de novo as leituras da aba Atividades que falharam.
  Future<void> _retryActivity() async {
    setState(() {
      if (_historyFailure != null) _historyLoaded = false;
      if (_updatesFailure != null) _updatesLoaded = false;
    });
    await _ensureActivityLoaded();
  }

  /// Próxima página de atualizações — "Carregar mais atualizações".
  Future<void> _loadMoreUpdates() async {
    final id = _property?.id ?? widget.propertyId;
    if (_loadingMoreUpdates || id.trim().isEmpty) return;
    setState(() {
      _loadingMoreUpdates = true;
      _moreUpdatesFailed = false;
    });
    final next = await _activityService.getUpdatesPage(
      id,
      page: _updates.page + 1,
      limit: _kUpdatesPageSize,
    );
    if (!mounted) return;
    setState(() {
      _loadingMoreUpdates = false;
      final data = next.data;
      if (next.success && data != null) {
        // Sem repetir o que já está na tela (uma atualização nova empurra
        // a paginação uma posição).
        final seen = {for (final u in _updates.data) u.id};
        _updates = PropertyUpdatesResponse(
          data: [
            ..._updates.data,
            ...data.data.where((u) => !seen.contains(u.id)),
          ],
          total: data.total,
          page: data.page,
          limit: data.limit,
        );
      } else {
        _moreUpdatesFailed = true;
      }
    });
  }

  Future<void> _ensurePerformanceLoaded() async {
    if (_engagementLoaded || _loadingEngagement) return;
    final id = _property?.id ?? widget.propertyId;
    if (id.trim().isEmpty) return;
    // Como o web: só mede imóvel publicado no site; totais dos últimos 3
    // dias e origem dos últimos 30.
    if (_property?.isAvailableForSite != true) return;
    setState(() => _loadingEngagement = true);
    final results = await Future.wait<Object?>([
      _activityService.getEngagement(id, days: 3),
      _activityService.getEngagementByChannel(id, days: 30),
    ]);
    final stats = results[0] as PropertyEngagementStats?;
    final byChannel = results[1] as List<PropertyEngagementByChannel>;
    if (mounted) {
      setState(() {
        _engagement = stats;
        _engagementByChannel = byChannel;
        _loadingEngagement = false;
        _engagementLoaded = true;
      });
    }
  }

  Future<void> _submitPropertyUpdate() async {
    final content = _updateComposer.text.trim();
    if (content.isEmpty || _submittingUpdate) return;
    final id = _property?.id ?? widget.propertyId;
    if (id.trim().isEmpty) return;

    setState(() => _submittingUpdate = true);
    final created = await _activityService.createUpdate(id, content);
    if (!mounted) return;
    setState(() {
      _submittingUpdate = false;
      if (created != null) {
        _updateComposer.clear();
        _updates = PropertyUpdatesResponse(
          data: [created, ..._updates.data],
          total: _updates.total + 1,
          page: _updates.page,
          limit: _updates.limit,
        );
      }
    });
    if (created == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Não foi possível registrar a atualização.'),
          backgroundColor: AppColors.status.error,
        ),
      );
    }
  }

  Future<void> _saveInternalNotes() async {
    final id = _property?.id ?? widget.propertyId;
    if (id.trim().isEmpty || _savingNotes) return;
    setState(() => _savingNotes = true);
    final text = _notesController.text.trim();
    final response = await _propertyService.updateProperty(
      id,
      {'internalNotes': text.isEmpty ? null : text},
    );
    if (!mounted) return;
    setState(() {
      _savingNotes = false;
      if (response.success) {
        _editingNotes = false;
        if (response.data != null) _property = response.data;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          response.success
              ? 'Observações salvas.'
              : (response.message ?? 'Não foi possível salvar.'),
        ),
        backgroundColor:
            response.success ? AppColors.status.success : AppColors.status.error,
      ),
    );
  }

  void _debugLogPropertyImageDiagnostics(
    Property property, {
    required String source,
  }) {
    if (!kDebugMode) return;
    final allImages = property.images ?? const <PropertyImage>[];
    final validImages =
        allImages.where((img) => img.url.trim().isNotEmpty).toList();
    final mainUrl = property.mainImage?.url.trim() ?? '';
    final signature =
        '${property.id}|${allImages.length}|${validImages.length}|$mainUrl|'
        '${allImages.take(3).map((e) => e.url).join('|')}';
    if (_lastImageDiagnosticsSignature == signature) return;
    _lastImageDiagnosticsSignature = signature;

    debugPrint('ðŸ–¼ï¸ [PROPERTY_DETAILS] Diagnóstico de imagens ($source)');
    debugPrint('   - propertyId: ${property.id}');
    debugPrint('   - imageCount(api): ${property.imageCount}');
    debugPrint('   - images.length(raw): ${allImages.length}');
    debugPrint('   - images.length(valid): ${validImages.length}');
    debugPrint(
      '   - mainImage.id/url: ${property.mainImage?.id ?? '-'} / '
      '${mainUrl.isEmpty ? '(vazio)' : mainUrl}',
    );
    if (allImages.isEmpty) {
      debugPrint('   - image list veio vazia');
      return;
    }
    for (var i = 0; i < allImages.length && i < 5; i++) {
      final img = allImages[i];
      debugPrint(
        '   - image[$i] id=${img.id} | isMain=${img.isMain} | url="${img.url}"',
      );
    }
  }

  Future<void> _deleteProperty() async {
    if (_property == null) return;

    final confirm = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Excluir Propriedade',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context, false),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Tem certeza que deseja excluir "${_property!.title}"? Esta ação não pode ser desfeita.',
                ),
                const SizedBox(height: 24),
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context, true),
                        icon: const Icon(Icons.delete),
                        label: const Text('Excluir Propriedade'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.status.error,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context, false),
                        icon: const Icon(Icons.close),
                        label: const Text('Cancelar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirm == true && mounted) {
      final response = await _propertyService.deleteProperty(widget.propertyId);

      if (mounted) {
        if (response.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Propriedade excluída com sucesso')),
          );
          Navigator.of(context).pop(true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao excluir propriedade'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      // Sem título: o hero da própria página já identifica o imóvel —
      // título na AppBar era conteúdo dobrado.
      title: '',
      currentBottomNavIndex: 1,
      showBottomNavigation: true,
      actions: [
        // Compartilhar sempre à mão (sem rolar até o rodapé) — só quando o
        // imóvel está publicado no site e temos link (mesmo gate do web).
        if (_property != null &&
            _property!.isAvailableForSite == true &&
            _siteBaseUrl != null)
          ChromeToolbarIconButton(
            icon: Icons.share_rounded,
            tooltip: 'Compartilhar imóvel',
            onPressed: () => showPropertyShareSheet(context, _property!),
          ),
        // Ofertas oculta no app: badge da AppBar só volta com o flag.
        if (FeatureVisibility.offersEnabled &&
            _property != null &&
            _property!.hasPendingOffers == true)
          Stack(
            children: [
              ChromeToolbarIconButton(
                icon: Icons.request_quote_rounded,
                tooltip: 'Ver ofertas',
                onPressed: () {
                  Navigator.of(context).pushNamed(
                    '/properties/offers',
                    arguments: {'propertyId': widget.propertyId},
                  );
                },
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        Builder(
          builder: (context) {
            // A Apresentação em PDF é de todos que veem o imóvel (mesmo gate
            // do web): o menu só some enquanto o imóvel não carregou.
            if (_property == null) return const SizedBox.shrink();
            final canEdit = _canEditProperty;
            final canDelete = _canDeleteProperty;
            // Ofertas oculta no app: o atalho do sheet ⋯ fica desligado
            // (o gate original de pendências segue preservado atrás do flag).
            final hasOffersShortcut = FeatureVisibility.offersEnabled &&
                _property!.hasPendingOffers == true;
            // Sheet da casa no lugar do PopupMenu nativo do Material.
            return ChromeToolbarIconButton(
              icon: Icons.more_horiz_rounded,
              tooltip: 'Ações do imóvel',
              onPressed: () => _showDetailActionsSheet(
                canEdit: canEdit,
                canDelete: canDelete,
                hasOffersShortcut: hasOffersShortcut,
              ),
            );
          },
        ),
      ],
      body: _isLoading
          ? _buildSkeleton(context)
          : _errorMessage != null
          ? _buildErrorState(context)
          : () {
              final property = _property;
              if (property == null) {
                return _buildErrorState(
                  context,
                  message: 'Não foi possível carregar os detalhes do imóvel.',
                );
              }
              return Stack(
                children: [
                  Positioned.fill(
                    child: _buildPropertyDetails(context, theme, property),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    right: 16,
                    bottom: _showScrollTopFab ? 20 : -64,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 220),
                      opacity: _showScrollTopFab ? 1 : 0,
                      child: _buildScrollTopButton(context, theme),
                    ),
                  ),
                ],
              );
            }(),
    );
  }

  Widget _buildSkeleton(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Skeleton da imagem
          SkeletonBox(width: double.infinity, height: 300, borderRadius: 0),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonText(
                  width: 250,
                  height: 24,
                  margin: const EdgeInsets.only(bottom: 8),
                ),
                SkeletonText(
                  width: 200,
                  height: 16,
                  margin: const EdgeInsets.only(bottom: 20),
                ),
                SkeletonText(
                  width: double.infinity,
                  height: 16,
                  margin: const EdgeInsets.only(bottom: 8),
                ),
                SkeletonText(
                  width: double.infinity,
                  height: 16,
                  margin: const EdgeInsets.only(bottom: 20),
                ),
                SkeletonText(
                  width: 150,
                  height: 20,
                  margin: const EdgeInsets.only(bottom: 16),
                ),
                SkeletonCard(
                  height: 200,
                  child: Column(
                    children: List.generate(
                      4,
                      (index) => Padding(
                        padding: EdgeInsets.only(bottom: index < 3 ? 16 : 0),
                        child: Row(
                          children: [
                            SkeletonBox(
                              width: 24,
                              height: 24,
                              borderRadius: 12,
                            ),
                            const SizedBox(width: 12),
                            SkeletonText(width: 100, height: 16),
                            const Spacer(),
                            SkeletonText(width: 80, height: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, {String? message}) {
    if (message == null && _errorFromException && _errorDetail != null) {
      return AppErrorState(
        cause: ErrorCause.fromException(_errorDetail!),
        onRetry: _loadProperty,
      );
    }
    return AppErrorState.fromApi(
      message: message ?? _errorMessage,
      statusCode: message != null ? 0 : _errorStatus,
      error: message != null ? null : _errorDetail,
      onRetry: _loadProperty,
    );
  }

  Widget _buildPropertyDetails(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final isDark = theme.brightness == Brightness.dark;

    // Layout reformulado em estilo editorial:
    //
    // 1. Hero edge-to-edge (sem bordas arredondadas, sem padding lateral)
    //    — a foto é o protagonista e ocupa toda a largura da tela.
    // 2. Bloco "headline" (tipo + código + título + endereço) sem caixa.
    // 3. Quick stats em strip horizontal.
    // 4. Preço em destaque tipográfico (sem caixa).
    // 5. Ações rápidas.
    // 6. Tabs + conteúdo da aba.
    //
    // Essa ordem coloca a informação mais importante (foto â†’ título â†’
    // preço) com hierarquia visual real, em vez de "card dentro de card
    // dentro de card" que era o layout antigo.
    return CustomScrollView(
      controller: _detailsScrollController,
      // Rolar a página fecha o teclado — é o primeiro gesto que a pessoa
      // tenta quando o campo é multilinha e não há tecla de "concluir".
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        // 1. HERO sem padding lateral, edge-to-edge
        SliverToBoxAdapter(
          child: _buildDetailsHero(context, theme, property),
        ),
        // 2. Hero textual: código + preço + título + pills (paridade web)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: _buildIdentityCard(context, theme, property, muted, isDark),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 18),
            child: _buildSectionTabs(context, theme),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
            child: _buildActiveTabContent(context, theme, property),
          ),
        ),
      ],
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ HERO â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Hero **edge-to-edge** — a foto é o protagonista da tela.
  ///
  /// Mudanças em relação à versão anterior:
  /// - Sem `borderRadius: 20` — bordas retas, full-width
  /// - Sem `Material elevation` + sombra — fica visualmente "preso" ao topo
  /// - Sem `padding lateral 16` — ocupa 100% da largura da tela
  /// - Altura de **340px** (era 248) pra dar mais peso visual à foto
  /// - **Título do imóvel + endereço sobrepostos** no rodapé da imagem
  ///   (estilo Airbnb/Booking) com gradiente bottom mais forte
  /// - Featured/contador/dots reposicionados pra não brigar com o título
  Widget _buildDetailsHero(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final rawImages = property.images ?? const <PropertyImage>[];
    final validImages =
        rawImages.where((img) => img.url.trim().isNotEmpty).toList();
    final hasValidMainImage =
        property.mainImage?.url.trim().isNotEmpty == true;
    // Alguns payloads chegam com `mainImage` válida e `images` vazia.
    final images = validImages.isNotEmpty
        ? validImages
        : (hasValidMainImage
            ? <PropertyImage>[property.mainImage!]
            : const <PropertyImage>[]);
    final safeCurrentIndex = images.isEmpty
        ? 0
        : _currentImageIndex.clamp(0, images.length - 1);
    if (kDebugMode && rawImages.length != validImages.length) {
      debugPrint(
        'âš ï¸ [PROPERTY_DETAILS] Imagens com URL inválida/vazia: '
        '${rawImages.length - validImages.length} de ${rawImages.length}',
      );
    }
    if (kDebugMode && images.isEmpty) {
      debugPrint(
        'âš ï¸ [PROPERTY_DETAILS] Hero sem imagem renderizável. '
        'mainImage="${property.mainImage?.url ?? '(null)'}" '
        'imagesRaw=${rawImages.length}',
      );
    }
    final mediaCount = property.imageCount ?? images.length;
    const heroH = 340.0;
    final isDark = theme.brightness == Brightness.dark;

    Widget imageLayer() => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: images.isEmpty
              ? null
              : () => _openFullscreenGallery(images, safeCurrentIndex),
          child: images.isEmpty
              ? _buildHeroFallback(context, theme)
              : PageView.builder(
                  controller: _imagePageController,
                  itemCount: images.length,
                  onPageChanged: (i) => setState(() => _currentImageIndex = i),
                  itemBuilder: (_, i) => Hero(
                    tag: 'property-image-${property.id}-$i',
                    child: ShimmerImage(
                      imageUrl: images[i].url,
                      width: double.infinity,
                      height: heroH,
                      fit: BoxFit.cover,
                      errorWidget: _buildHeroFallback(context, theme),
                    ),
                  ),
                ),
        );

    return SizedBox(
      width: double.infinity,
      height: heroH,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: imageLayer()),

          // Gradient bottom mais forte — necessário pro título sobreposto
          // ler bem em fotos claras. Top também tem um leve "veneer" pra
          // contadores/featured chip.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.32, 0.6, 1.0],
                  colors: [
                    Colors.black.withValues(alpha: isDark ? 0.5 : 0.38),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.18),
                    Colors.black.withValues(alpha: 0.78),
                  ],
                ),
              ),
            ),
          ),

          if (mediaCount > 1)
            Positioned(
              right: 16,
              top: 16,
              child: _buildHeroMediaCounter(
                images.isEmpty ? 1 : safeCurrentIndex + 1,
                mediaCount,
              ),
            ),
          if (images.isNotEmpty)
            Positioned(
              left: 16,
              top: 16,
              child: _buildExpandHint(),
            ),

          // Setas laterais para navegação entre fotos
          if (images.length > 1 && safeCurrentIndex > 0)
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _buildHeroNavArrow(
                  Icons.chevron_left_rounded,
                  () => _imagePageController.previousPage(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOut,
                  ),
                ),
              ),
            ),
          if (images.length > 1 && safeCurrentIndex < images.length - 1)
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _buildHeroNavArrow(
                  Icons.chevron_right_rounded,
                  () => _imagePageController.nextPage(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOut,
                  ),
                ),
              ),
            ),

          // Dots no fim (apenas quando há mais de uma imagem)
          if (images.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: Center(
                child: _buildHeroDots(images.length, safeCurrentIndex),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildExpandHint() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.zoom_out_map_rounded, size: 12, color: Colors.white),
          SizedBox(width: 5),
          Text(
            'Toque para ampliar',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              height: 1,
              letterSpacing: -0.05,
            ),
          ),
        ],
      ),
    );
  }

  void _openFullscreenGallery(List<PropertyImage> images, int initial) {
    Navigator.of(context)
        .push<bool>(
      PageRouteBuilder<bool>(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => _FullscreenGallery(
          images: images,
          initialIndex: initial,
          propertyId: _property?.id ?? '',
          canDelete: _canDeletePropertyImages,
          canSetMain: _canSetMainPropertyImage,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    )
        .then((didMutate) {
      // Quando o user deleta uma ou mais fotos pelo fullscreen, recarregamos
      // o property pra refletir nova `mainImage`/`images` (e contadores).
      if (didMutate == true && mounted) {
        _refreshAfterChange();
      }
    });
  }

  Widget _buildHeroFallback(BuildContext context, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  AppColors.background.backgroundDarkMode,
                  AppColors.background.backgroundSecondaryDarkMode,
                ]
              : [
                  AppColors.background.backgroundSecondary,
                  AppColors.background.background,
                ],
        ),
      ),
      child: Center(
        child: Container(
          width: 86,
          height: 86,
          decoration: BoxDecoration(
            color: AppColors.primary.primary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Icon(
            Icons.home_work_outlined,
            size: 44,
            color: AppColors.primary.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildHeroMediaCounter(int current, int total) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.photo_library_outlined, size: 12, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            '$current / $total',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              height: 1,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  /// Indicadores de página da hero.
  ///
  /// Antes usava um `Row` com `total` dots — quebrava em overflow quando
  /// o imóvel tinha 12+ fotos (ex.: 20 dots × ~12px = 240px+ que estoura
  /// telas estreitas). Agora aplicamos uma regra adaptativa:
  ///
  /// - Até **8 fotos**: mostra dots tradicionais (Instagram-like).
  /// - Mais que isso: usa um **indicador compacto "X / Y"** com fundo
  ///   semitransparente — escala bem para qualquer número de fotos.
  Widget _buildHeroDots(int total, int current) {
    if (total > 8) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
          ),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${current + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 0.2,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              TextSpan(
                text: '  /  $total',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  letterSpacing: 0.2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(total, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active
                ? Colors.white
                : Colors.white.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }

  Widget _buildHeroNavArrow(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.42),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ IDENTIDADE â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Bloco de "identidade" reformulado — **sem caixa visual encapsulada**.
  ///
  /// Antes era um DecoratedBox com borderRadius 20, sombra e ClipRRect
  /// envolvendo tudo, criando um "card sobre card". Repetia também o
  /// título + tipo + endereço que agora estão sobrepostos na hero.
  ///
  /// Agora é só conteúdo direto sobre o background da página:
  /// - Linha de código + matches badge + relacionados (compacto)
  /// - Pills de meta-status (público/privado, aceita proposta, MCMV…)
  /// - Footer de identidade (se houver) — separado por linha sutil
  Widget _buildIdentityCard(
    BuildContext context,
    ThemeData theme,
    Property property,
    Color muted,
    bool isDark,
  ) {
    final pills = _buildIdentityMetaPills(property, isDark);
    final hasFooter = _hasIdentityFooterContent(property);
    final hasCode = property.code != null && property.code!.isNotEmpty;
    final access = ModuleAccessService.instance;
    final role = access.userRole?.toLowerCase() ?? '';
    final canUndoSold =
        !property.isDeleted &&
        (role == 'master' || role == 'admin') &&
        property.status == PropertyStatus.sold;
    final disponivelTone =
        PropertyStatusVisual.of(PropertyStatus.available, dark: isDark).color;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1) Título do imóvel — primeira informação (paridade web). Fonte
        // contida (19): o título identifica, não grita.
        Text(
          property.title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.25,
            height: 1.2,
            fontSize: 19,
            color: ThemeHelpers.textColor(context),
          ),
        ),
        const SizedBox(height: 8),
        // 1.5) Pills de status no LUGAR do endereço (a Localização tem seção
        // própria com mapa): estado de negócio + situação — a própria
        // PropertySituationPill já cobre "Ativo · no site" com o globo.
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            PropertyStatusPill(
              status: property.status,
              rawStatus: property.statusRaw,
            ),
            if (canUndoSold)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _undoSoldLoading ? null : _confirmAndUndoSold,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: disponivelTone.withValues(
                        alpha: isDark ? 0.14 : 0.1,
                      ),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: disponivelTone.withValues(
                          alpha: isDark ? 0.45 : 0.35,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _undoSoldLoading
                              ? Icons.hourglass_top_rounded
                              : Icons.check_circle_outline_rounded,
                          size: 14,
                          color: disponivelTone,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            _undoSoldLoading
                                ? 'Tornando disponível...'
                                : 'Tornar disponível',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: disponivelTone,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 0.15,
                              height: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (property.isDeleted)
              _buildDeletedPill(context, property)
            else
              PropertySituationPill(
                isActive: property.isActive,
                isAvailableForSite: property.isAvailableForSite ?? false,
              ),
          ],
        ),
        // Nas 9 etapas do funil de locação, a trilha responde "em que ponto
        // está" sem a pessoa decorar a ordem das etapas.
        if (property.statusIsKnown && property.status.isRentalFunnel) ...[
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: PropertyRentalFunnelTrail(status: property.status),
          ),
        ],
        // Gestão ao lado do status, como a faixa do hero do web.
        ..._buildStatusActionsBlock(context, property, isDark),
        const SizedBox(height: 14),
        // 2) Linha CRM: código (à esquerda) + matches badge (canto direito).
        Row(
          children: [
            if (hasCode) ...[
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: property.code!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Código copiado'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '#',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _salePriceColor(isDark).withValues(alpha: 0.55),
                      ),
                    ),
                    Text(
                      property.code!,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.04,
                        color: _salePriceColor(isDark),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.content_copy_rounded,
                      size: 13,
                      color: _salePriceColor(isDark).withValues(alpha: 0.65),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                // Matches oculto no app: o hero segue sem o badge.
                child: FeatureVisibility.matchesEnabled
                    ? MatchesBadge(
                        propertyId: widget.propertyId,
                        onClick: () => Navigator.pushNamed(
                          context,
                          AppRoutes.matchesByProperty(widget.propertyId),
                        ),
                        child: const SizedBox.shrink(),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),

        // 3) Valores (o "Republicar no site" foi para a faixa de gestão,
        // ao lado do status — onde o web o põe).
        const SizedBox(height: 12),
        _buildPriceShowcase(context, theme, property, isDark),

        // 3) Eyebrow: inativo, site, destaque, atualizado
        const SizedBox(height: 10),
        _buildHeroEyebrowChips(context, theme, property, isDark),

        // 4) Specs principais — faixa horizontal refinada (números-chave) +
        //    meta secundária (tipo, bairro, fotos) em chips discretos.
        const SizedBox(height: 14),
        _buildSpecsStrip(context, property, isDark),
        const SizedBox(height: 12),
        _buildHeroMetaPillsRow(context, property, isDark),

        // 3) Pills de meta secundárias (MCMV, aceita proposta, ofertas
        //    pendentes, sem fotos). Já excluímos "no site"/"privado" do
        //    helper porque agora vem na PropertySituationPill.
        if (pills.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: pills,
          ),
        ],

        // 4) Captação saiu daqui — virou seção própria no fim da aba
        // Detalhes (logo antes de "Status da chave").

        // 5) Footer (responsável, datas)
        if (hasFooter && _formatHeroUpdatedLabel(property.updatedAt) == null) ...[
          const SizedBox(height: 14),
          Container(
            height: 1,
            color: ThemeHelpers.borderLightColor(context)
                .withValues(alpha: 0.55),
          ),
          const SizedBox(height: 12),
          _buildIdentityFooter(theme, property, muted),
        ],
      ],
    );
  }

  /// Selo "Excluído em …" (web) — a ficha fica só para consulta.
  Widget _buildDeletedPill(BuildContext context, Property property) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final when = DateTime.tryParse(property.deletedAt ?? '');
    final label = when == null
        ? 'Excluído · só consulta'
        : 'Excluído em ${DateFormat('dd/MM/yyyy HH:mm').format(when.toLocal())}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: muted.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: muted.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline_rounded, size: 14, color: muted),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w800,
                fontSize: 11,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Lista normalizada de captadores. Prioriza `captors` (multi, vindo da API
  /// de detalhe). Cai para `capturedBy` (single, legacy) se o multi não veio.
  List<PropertyCaptor> _resolveCaptors(Property property) {
    final multi = property.captors ?? const <PropertyCaptor>[];
    if (multi.isNotEmpty) {
      // Deduplica por id pra evitar repetição quando o backend devolve tanto
      // legacy quanto multi (raríssimo, mas mantém UI limpa).
      final seen = <String>{};
      return multi.where((c) => seen.add(c.id)).toList();
    }
    final legacy = property.capturedBy;
    if (legacy != null && legacy.name.isNotEmpty) {
      return [
        PropertyCaptor(
          id: legacy.id,
          name: legacy.name,
          email: legacy.email,
          phone: legacy.phone,
          avatar: legacy.avatar,
        ),
      ];
    }
    return const [];
  }

  bool _hasCaptorsContent(Property property) => _resolveCaptors(property).isNotEmpty;

  /// Conteúdo da seção "Captação" (o header/contador ficam no molde flush):
  /// lista de tiles com avatar (foto ou iniciais), nome e contato, com ações
  /// de Ligar/WhatsApp no próprio item.
  Widget _buildCaptorsBlock(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final captors = _resolveCaptors(property);
    final accent = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;

    return Column(
      children: [
        for (var i = 0; i < captors.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _CaptorTile(
            captor: captors[i],
            accent: accent,
            muted: muted,
          ),
        ],
      ],
    );
  }

  /// Tom das seções de pessoas do imóvel (Proprietário, Responsáveis) — o
  /// índigo da aba Detalhes, o mesmo do web.
  static const Color _kPeopleTone = Color(0xFF6366F1);

  /// Contador compacto para o cabeçalho de uma seção (trailing).
  Widget _buildSectionCountBadge(
    BuildContext context,
    String label,
    Color accent,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.32)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: accent,
        ),
      ),
    );
  }

  /// Contador compacto pro header da seção Captação (trailing).
  Widget _buildCaptorsCountBadge(BuildContext context, Property property) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
    final count = _resolveCaptors(property).length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.32)),
      ),
      child: Text(
        count == 1 ? '1 captador' : '$count captadores',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: accent,
        ),
      ),
    );
  }

  /// Pills com meta-info do imóvel: público, MCMV, aceita proposta, ofertas.
  List<Widget> _buildIdentityMetaPills(Property property, bool isDark) {
    final pills = <Widget>[];

    if (property.acceptsNegotiation == true) {
      pills.add(_metaPill(
        icon: Icons.handshake_outlined,
        label: 'Aceita proposta',
        color: AppColors.status.success,
        isDark: isDark,
      ));
    }
    if (property.mcmvEligible == true) {
      pills.add(_metaPill(
        icon: Icons.home_work_outlined,
        label: 'MCMV',
        color: AppColors.status.info,
        isDark: isDark,
      ));
    }
    final pending = property.pendingOffersCount ?? 0;
    // Ofertas oculta no app: sem pill de pendências apontando pra área morta.
    if (FeatureVisibility.offersEnabled && pending > 0) {
      pills.add(_metaPill(
        icon: Icons.request_quote_outlined,
        label: '$pending oferta${pending > 1 ? 's' : ''} pendente${pending > 1 ? 's' : ''}',
        color: AppColors.status.warning,
        isDark: isDark,
      ));
    }
    if ((property.imageCount ?? property.images?.length ?? 0) == 0) {
      pills.add(_metaPill(
        icon: Icons.image_not_supported_outlined,
        label: 'Sem fotos',
        color: AppColors.status.warning,
        isDark: isDark,
      ));
    }
    return pills;
  }

  Widget _metaPill({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.11),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 10.5,
              letterSpacing: 0.1,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  bool _hasIdentityFooterContent(Property property) {
    return property.updatedAt.isNotEmpty || property.createdAt.isNotEmpty;
  }

  Widget _buildIdentityFooter(ThemeData theme, Property property, Color muted) {
    final updatedAgo = _humanRelativeTime(property.updatedAt);
    final createdAgo = _humanRelativeTime(property.createdAt);

    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        if (updatedAgo != null)
          _identityMicroInfo(
            icon: Icons.history_rounded,
            label: 'Atualizado $updatedAgo',
            muted: muted,
            theme: theme,
          ),
        if (updatedAgo == null && createdAgo != null)
          _identityMicroInfo(
            icon: Icons.event_available_outlined,
            label: 'Criado $createdAgo',
            muted: muted,
            theme: theme,
          ),
      ],
    );
  }

  Widget _identityMicroInfo({
    required IconData icon,
    required String label,
    required Color muted,
    required ThemeData theme,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: muted),
        const SizedBox(width: 5),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: muted,
            fontWeight: FontWeight.w600,
            fontSize: 10.5,
          ),
        ),
      ],
    );
  }

  /// Devolve algo como "há 3d", "há 2h" ou null se a string for inválida.
  String? _humanRelativeTime(String iso) {
    if (iso.trim().isEmpty) return null;
    DateTime? dt;
    try {
      dt = DateTime.parse(iso).toLocal();
    } catch (_) {
      return null;
    }
    final delta = DateTime.now().difference(dt);
    if (delta.isNegative) return null;
    if (delta.inMinutes < 1) return 'agora';
    if (delta.inMinutes < 60) return 'há ${delta.inMinutes} min';
    if (delta.inHours < 24) return 'há ${delta.inHours} h';
    if (delta.inDays < 7) return 'há ${delta.inDays} d';
    if (delta.inDays < 30) return 'há ${(delta.inDays / 7).floor()} sem';
    if (delta.inDays < 365) return 'há ${(delta.inDays / 30).floor()} mes';
    return 'há ${(delta.inDays / 365).floor()} a';
  }

  IconData _typeIcon(PropertyType type) =>
      type == PropertyType.house || type == PropertyType.townhouse
          ? Icons.cottage_outlined
          : PropertyTypeVisual.outlined(type);

  /// Pills discretas do hero — paridade `PropertyHeroMetaChip` (web).
  Widget _buildHeroMetaPillsRow(
    BuildContext context,
    Property property,
    bool isDark,
  ) {
    final chips = <Widget>[];
    // Tipo cru: o que o app não conhece aparece como veio, nunca como "Casa".
    final typeLabel = property.typeLabel;
    if (typeLabel.isNotEmpty) {
      chips.add(_heroMetaChip(
        context,
        isDark: isDark,
        icon: _typeIcon(property.type),
        label: typeLabel,
      ));
    }
    final neighborhood = property.neighborhood.trim();
    if (neighborhood.isNotEmpty) {
      chips.add(_heroMetaChip(
        context,
        isDark: isDark,
        icon: Icons.location_on_outlined,
        label: neighborhood,
      ));
    }
    // Números-chave (quartos/suítes/banheiros/vagas/área) agora vivem na
    // faixa de specs (_buildSpecsStrip); aqui ficam só os meta secundários.
    final photos = property.imageCount ?? property.images?.length ?? 0;
    if (photos > 0) {
      chips.add(_heroMetaChip(
        context,
        isDark: isDark,
        icon: Icons.photo_library_outlined,
        label: '$photos foto${photos == 1 ? '' : 's'}',
      ));
    }

    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: chips,
    );
  }

  /// Faixa de specs principais — ícone + valor + label, distribuídos na
  /// horizontal com divisórias finas e hairlines em cima/embaixo. Substitui a
  /// lista monótona de pills; usa bem a largura e fica colado às margens.
  Widget _buildSpecsStrip(
    BuildContext context,
    Property property,
    bool isDark,
  ) {
    final items = <({IconData icon, String value, String label})>[];
    final bedrooms = property.bedrooms;
    if (bedrooms != null && bedrooms > 0) {
      items.add((
        icon: Icons.bed_outlined,
        value: '$bedrooms',
        label: bedrooms == 1 ? 'Quarto' : 'Quartos',
      ));
    }
    final suites = property.suites;
    if (suites != null && suites > 0) {
      items.add((
        icon: Icons.king_bed_outlined,
        value: '$suites',
        label: suites == 1 ? 'Suíte' : 'Suítes',
      ));
    }
    final bathrooms = property.bathrooms;
    if (bathrooms != null && bathrooms > 0) {
      items.add((
        icon: Icons.bathtub_outlined,
        value: '$bathrooms',
        label: bathrooms == 1 ? 'Banheiro' : 'Banheiros',
      ));
    }
    final parking = property.parkingSpaces;
    if (parking != null && parking > 0) {
      items.add((
        icon: Icons.directions_car_filled_outlined,
        value: '$parking',
        label: parking == 1 ? 'Vaga' : 'Vagas',
      ));
    }
    String? area;
    if (property.builtArea != null && property.builtArea! > 0) {
      area = _formatAreaHero(property.builtArea!);
    } else if (property.totalArea > 0) {
      area = _formatAreaHero(property.totalArea);
    }
    if (area != null) {
      items.add((icon: Icons.straighten_rounded, value: area, label: 'm²'));
    }

    if (items.isEmpty) return const SizedBox.shrink();

    final text = ThemeHelpers.textColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final line = ThemeHelpers.borderColor(context).withValues(alpha: 0.5);

    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      children.add(
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(it.icon, size: 19, color: muted),
              const SizedBox(height: 6),
              Text(
                it.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: -0.2,
                  color: text,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                it.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  height: 1,
                  color: muted,
                ),
              ),
            ],
          ),
        ),
      );
      if (i < items.length - 1) {
        children.add(Container(width: 1, height: 36, color: line));
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: line),
          bottom: BorderSide(color: line),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: children,
      ),
    );
  }

  String _formatAreaHero(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  Widget _heroMetaChip(
    BuildContext context, {
    required bool isDark,
    required IconData icon,
    required String label,
    Color? tint,
  }) {
    final muted = tint ?? ThemeHelpers.textSecondaryColor(context);
    final border = ThemeHelpers.borderColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : const Color(0xFF0F172A).withValues(alpha: 0.035),
        border: Border.all(color: border.withValues(alpha: 0.53)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: muted.withValues(alpha: 0.85)),
          const SizedBox(width: 5),
          // Flexible + ellipsis: bairro longo ou tipo cru desconhecido não
          // estouram a Wrap em 320dp com texto a 130%.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: muted,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroEyebrowChips(
    BuildContext context,
    ThemeData theme,
    Property property,
    bool isDark,
  ) {
    final chips = <Widget>[];
    if (!property.isActive) {
      chips.add(_heroMetaChip(
        context,
        isDark: isDark,
        icon: Icons.block_rounded,
        label: 'Inativo no sistema',
        tint: AppColors.status.error,
      ));
    }
    final onSite = property.isAvailableForSite == true;
    chips.add(_heroMetaChip(
      context,
      isDark: isDark,
      icon: Icons.public_rounded,
      label: onSite ? 'No site' : 'Fora do site',
      tint: onSite ? _salePriceColor(isDark) : mutedFrom(context),
    ));
    if (property.isFeatured) {
      chips.add(_heroMetaChip(
        context,
        isDark: isDark,
        icon: Icons.star_rounded,
        label: 'Destaque',
        tint: const Color(0xFFD97706),
      ));
    }
    final updatedLabel = _formatHeroUpdatedLabel(property.updatedAt);
    if (updatedLabel != null) {
      chips.add(_heroMetaChip(
        context,
        isDark: isDark,
        icon: Icons.schedule_rounded,
        label: updatedLabel,
      ));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: chips,
    );
  }

  Color mutedFrom(BuildContext context) =>
      ThemeHelpers.textSecondaryColor(context);

  String? _formatHeroUpdatedLabel(String iso) {
    final rel = _humanRelativeTime(iso);
    if (rel == null) return null;
    try {
      final dt = DateTime.parse(iso).toLocal();
      final formatted = DateFormat('dd/MM/yyyy, HH:mm').format(dt);
      return 'Atualizado em $formatted';
    } catch (_) {
      return 'Atualizado $rel';
    }
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ PRICE SHOWCASE â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildPriceShowcase(
    BuildContext context,
    ThemeData theme,
    Property property,
    bool isDark,
  ) {
    // O hero segue a FINALIDADE, não a mera presença do valor (regra do
    // web): imóvel só para locação com preço de venda preenchido não está à
    // venda, e anunciar o valor aqui contradizia filtros e site.
    final finalidade = PropertyFinalidade.tryParse(property.finalidade);
    final hasSale = (property.salePrice ?? 0) > 0 &&
        anunciaVenda(
          finalidade: finalidade,
          salePrice: property.salePrice,
          rentPrice: property.rentPrice,
        );
    final hasRent = (property.rentPrice ?? 0) > 0 &&
        anunciaLocacao(
          finalidade: finalidade,
          salePrice: property.salePrice,
          rentPrice: property.rentPrice,
        );
    final outside = valorForaDaFinalidade(
      finalidade: finalidade,
      salePrice: property.salePrice,
      rentPrice: property.rentPrice,
    );
    final outsideNote = _buildPriceOutsideFinalidadeNote(
      theme,
      property,
      finalidade,
      sale: outside.venda,
      rent: outside.locacao,
    );
    if (!hasSale && !hasRent) {
      final card = _buildPriceUnavailableCard(context, theme, isDark);
      if (outsideNote == null) return card;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [card, outsideNote],
      );
    }

    // Bloco de preço editorial — **sem caixa** (cores paridade web).
    //
    // O preço é a informação mais importante depois da foto: ele é a
    // razão de o imóvel existir na vitrine. Antes ficava encapsulado
    // numa caixa secundária, sem destaque tipográfico real.
    //
    // Agora é só um padding inline sobre o background da página, com a
    // hierarquia tipográfica fazendo o trabalho: eyebrow accent fino +
    // valor grande em peso 900 + chips de meta abaixo.
    final priceBlock = hasSale && hasRent
        ? _buildPriceDualLayout(theme, property, isDark)
        : _buildPriceSingleLayout(theme, property, hasSale, isDark);
    final extras = _buildPriceExtrasLine(theme, property, isDark);
    if (extras == null && outsideNote == null) return priceBlock;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        priceBlock,
        if (extras != null) extras,
        if (outsideNote != null) outsideNote,
      ],
    );
  }

  /// Valor preenchido que a finalidade não anuncia: em vez de sumir sem
  /// explicação, a linha diz qual é e por que não aparece.
  Widget? _buildPriceOutsideFinalidadeNote(
    ThemeData theme,
    Property property,
    PropertyFinalidade? finalidade, {
    required bool sale,
    required bool rent,
  }) {
    if (!sale && !rent) return null;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final marcado = switch (finalidade) {
      PropertyFinalidade.venda => 'marcado só para venda',
      PropertyFinalidade.locacao => 'marcado só para locação',
      _ => 'sem essa finalidade',
    };
    final partes = <String>[
      if (sale && property.salePrice != null)
        'venda de ${_currencyFormatter.format(property.salePrice)}',
      if (rent && property.rentPrice != null)
        'aluguel de ${_currencyFormatter.format(property.rentPrice)}',
    ];
    final valor = partes.join(' e ');
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline_rounded, size: 15, color: muted),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'O valor de $valor está preenchido, mas não é anunciado: o '
              'imóvel está $marcado.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: muted,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Condomínio e IPTU abaixo dos preços principais (paridade `PriceExtrasLine`).
  Widget? _buildPriceExtrasLine(
    ThemeData theme,
    Property property,
    bool isDark,
  ) {
    final hasCondo = property.condominiumFee != null &&
        property.condominiumFee! > 0;
    final hasIptu = property.iptu != null && property.iptu! > 0;
    if (!hasCondo && !hasIptu) return null;

    final muted = ThemeHelpers.textSecondaryColor(context);
    final neutral = ThemeHelpers.textColor(context);

    Widget extra(String label, double value) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: muted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              fontSize: 9.5,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _currencyFormatter.format(value),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: neutral,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 16,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (hasCondo) extra('Condomínio', property.condominiumFee!),
          if (hasCondo && hasIptu)
            Text('·', style: TextStyle(color: muted, fontWeight: FontWeight.w700)),
          if (hasIptu) extra('IPTU', property.iptu!),
        ],
      ),
    );
  }

  Widget _buildPriceUnavailableCard(BuildContext context, ThemeData theme, bool isDark) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.background.cardBackgroundDarkMode
            : AppColors.background.cardBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: (isDark
                  ? AppColors.border.borderDarkMode
                  : AppColors.border.border)
              .withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.price_change_outlined, size: 22, color: muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Preço sob consulta',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Preencha os valores na ficha para apresentar nesta tela.',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceSingleLayout(
    ThemeData theme,
    Property property,
    bool isSale,
    bool isDark,
  ) {
    final value = isSale ? property.salePrice! : property.rentPrice!;
    final label = isSale ? 'Venda' : 'Aluguel';
    final valueColor =
        isSale ? _salePriceColor(isDark) : _rentPriceColor(isDark);
    final muted = ThemeHelpers.textSecondaryColor(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: muted,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.1,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _currencyFormatter.format(value),
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: valueColor,
            letterSpacing: -0.02,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (property.acceptsNegotiation == true) ...[
          const SizedBox(height: 12),
          _buildAcceptsNegotiationChip(theme, isDark),
        ],
      ],
    );
  }

  Widget _buildPriceDualLayout(
    ThemeData theme,
    Property property,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 28,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            _buildPriceColumn(
              theme,
              'Venda',
              _currencyFormatter.format(property.salePrice),
              _salePriceColor(isDark),
            ),
            _buildPriceColumn(
              theme,
              'Aluguel',
              _currencyFormatter.format(property.rentPrice),
              _rentPriceColor(isDark),
            ),
          ],
        ),
        if (property.acceptsNegotiation == true) ...[
          const SizedBox(height: 12),
          _buildAcceptsNegotiationChip(theme, isDark),
        ],
      ],
    );
  }

  Widget _buildPriceColumn(
    ThemeData theme,
    String label,
    String formattedValue,
    Color valueColor,
  ) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: muted,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.1,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          formattedValue,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: valueColor,
            letterSpacing: -0.02,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _buildAcceptsNegotiationChip(ThemeData theme, bool isDark) {
    final c = AppColors.status.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: isDark ? 0.18 : 0.13),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.handshake_outlined, size: 13, color: c),
          const SizedBox(width: 5),
          Text(
            'Aceita proposta',
            style: theme.textTheme.labelSmall?.copyWith(
              color: c,
              fontWeight: FontWeight.w800,
              fontSize: 10.5,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ TABS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Abas que esta pessoa vê, na ordem do web.
  List<_DetailsTab> get _visibleTabs => _DetailsTab.values;

  /// Abas com sublinhado na cor de cada uma (a régua proíbe pílulas):
  /// dividem a largura quando cabem; senão rolam na horizontal, com a ativa
  /// sempre à vista.
  Widget _buildSectionTabs(BuildContext context, ThemeData theme) {
    return _DetailsTabBar(
      tabs: _visibleTabs,
      active: _activeTab,
      onSelect: _onTabSelected,
    );
  }

  Widget _buildActiveTabContent(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    switch (_activeTab) {
      case _DetailsTab.details:
        return _buildDetailsTab(context, theme, property);
      case _DetailsTab.activity:
        return _buildActivityTab(context, theme, property);
      case _DetailsTab.performance:
        return _buildPerformanceTab(context, theme, property);
    }
  }

  /// Aba **Detalhes** — reúne cadastro, comercial e gestão (paridade com o web,
  /// onde "Detalhes" concentra tudo do imóvel). Reusa os blocos existentes.
  Widget _buildDetailsTab(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    // Ofertas oculta no app: a seção embutida some junto com os atalhos.
    final hasOffers = FeatureVisibility.offersEnabled &&
        (property.hasPendingOffers == true ||
            (property.totalOffersCount != null &&
                property.totalOffersCount! > 0));
    final hasChecklists = !_isLoadingChecklists && _checklists.isNotEmpty;
    final hasExpenses = !_isLoadingExpenses && _expenses.isNotEmpty;
    final condoId = property.condominiumId?.trim() ?? '';

    final sections = <Widget>[
      // Aprovação pendente — no topo, para quem tem permissão. Integrada ao
      // layout flush (não jogada).
      if (_showApprovalSection(property))
        _buildApprovalSection(context, theme, property),
      if (property.description.trim().isNotEmpty)
        _buildFlushSection(
          theme: theme,
          title: 'Descrição',
          icon: Icons.notes_outlined,
          tone: const Color(0xFF6366F1),
          child: _buildDescriptionCard(context, theme, property),
        ),
      _buildFlushSection(
        theme: theme,
        title: 'Características',
        icon: Icons.view_module_outlined,
        tone: const Color(0xFF6366F1),
        child: _buildCharacteristicsGrid(context, theme, property),
      ),
      if (condoId.isNotEmpty)
        _buildFlushSection(
          theme: theme,
          title: 'Condomínio',
          icon: Icons.apartment_rounded,
          tone: const Color(0xFF10B981),
          child: _buildCondominiumSection(context, theme, property),
        ),
      if (property.features.isNotEmpty)
        _buildFlushSection(
          theme: theme,
          title: 'Recursos e comodidades',
          icon: Icons.auto_awesome_outlined,
          tone: const Color(0xFF8B5CF6),
          child: _buildFeaturesSection(context, theme, property.features),
        ),
      _buildFlushSection(
        theme: theme,
        // Mapa/navegação = AZUL (vermelho é marca/erro/destrutivo).
        title: 'Localização',
        icon: Icons.map_outlined,
        tone: const Color(0xFF3B82F6),
        // Header limpo — as ações (Copiar endereço / Abrir no Maps) vivem
        // no par pareado logo abaixo do mapa, dentro da seção.
        child: _buildMapSection(context, theme, property),
      ),
      // Pessoas do imóvel em sequência: quem é o dono, quem responde e quem
      // captou (Captação segue imediatamente antes do status da chave).
      if (PropertyOwnerSection.isVisible(property))
        _buildFlushSection(
          theme: theme,
          title: 'Proprietário',
          icon: Icons.person_outline_rounded,
          tone: _kPeopleTone,
          child: PropertyOwnerSection(property: property),
        ),
      if (PropertyResponsiblesSection.isVisible(property))
        _buildFlushSection(
          theme: theme,
          title: 'Responsáveis',
          icon: Icons.badge_outlined,
          tone: _kPeopleTone,
          headerTrailing: _buildSectionCountBadge(
            context,
            PropertyResponsiblesSection.resolve(property).length == 1
                ? '1 responsável'
                : '${PropertyResponsiblesSection.resolve(property).length} '
                    'responsáveis',
            _kPeopleTone,
          ),
          child: PropertyResponsiblesSection(
            property: property,
            currentUserId: ModuleAccessService.instance.userId,
            tone: _kPeopleTone,
          ),
        ),
      // Captação — saiu do hero de identidade e virou seção própria,
      // imediatamente ANTES do status da chave (ordem pedida pelo dono).
      if (_hasCaptorsContent(property))
        _buildFlushSection(
          theme: theme,
          title: 'Captação',
          icon: Icons.flag_outlined,
          // Cor da marca — captação é a assinatura do corretor no imóvel.
          tone: theme.brightness == Brightness.dark
              ? AppColors.primary.primaryDarkMode
              : AppColors.primary.primary,
          headerTrailing: _buildCaptorsCountBadge(context, property),
          child: _buildCaptorsBlock(context, theme, property),
        ),
      _buildFlushSection(
        theme: theme,
        title: 'Status da chave',
        icon: Icons.vpn_key_outlined,
        tone: const Color(0xFFF59E0B),
        child: _buildKeyStatusSection(context, theme, property),
      ),
      // Sempre à vista, como no web: o vazio ensina e vincula o primeiro.
      _buildFlushSection(
        theme: theme,
        title: 'Clientes vinculados',
        icon: Icons.people_alt_outlined,
        tone: const Color(0xFF0EA5E9),
        headerTrailing: (property.clients ?? const []).isEmpty
            ? null
            : _buildSectionCountBadge(
                context,
                (property.clients ?? const []).length == 1
                    ? '1 cliente'
                    : '${(property.clients ?? const []).length} clientes',
                const Color(0xFF0EA5E9),
              ),
        child: _buildClientsSection(context, theme, property),
      ),
      if (hasOffers)
        _buildFlushSection(
          theme: theme,
          title: 'Ofertas',
          icon: Icons.request_quote_outlined,
          tone: const Color(0xFF10B981),
          child: _buildOffersSection(context, theme, property),
        ),
      if (hasExpenses)
        _buildFlushSection(
          theme: theme,
          title: 'Despesas',
          icon: Icons.payments_outlined,
          tone: const Color(0xFF64748B),
          child: _buildExpensesSection(context, theme, property),
        ),
      if (hasChecklists)
        _buildFlushSection(
          theme: theme,
          title: 'Checklists',
          icon: Icons.checklist_rtl_rounded,
          tone: const Color(0xFF0891B2),
          child: _buildChecklistsSection(context, theme, property),
        ),
      // Sempre à vista, como no web: vazio ensina e oferece o primeiro.
      _buildFlushSection(
        theme: theme,
        title: 'Documentos',
        icon: Icons.folder_open_outlined,
        tone: const Color(0xFF0284C7),
        headerTrailing: _documents.isEmpty
            ? null
            : _buildSectionCountBadge(
                context,
                _documents.length == 1
                    ? '1 documento'
                    : '${_documents.length} documentos',
                const Color(0xFF0284C7),
              ),
        child: _buildDocumentsSection(context, theme, property),
      ),
      _buildFlushSection(
        theme: theme,
        title: 'Ações rápidas',
        icon: Icons.bolt_rounded,
        // "Compartilhar" saiu do rodapé (já vive na AppBar e no sheet dos 3
        // pontinhos; aqui era conteúdo dobrado).
        // `isLast` saiu daqui: a última agora é a comunicação de aprovações,
        // e quem carrega a flag tem de ser a que fecha a página — senão
        // sobra divisor no fim.
        isLast: _threadForbidden,
        // Âmbar = energia/ação imediata; cada linha tem a cor do próprio
        // significado.
        tone: const Color(0xFFE6B84C),
        child: _buildQuickActionsSection(context, theme, property),
      ),
      // ÚLTIMA seção: a conversa de aprovação é acompanhamento, não a
      // ficha do imóvel. No topo ela empurrava descrição, características e
      // mapa para baixo — o que se abre o imóvel para ver.
      if (!_threadForbidden)
        _buildApprovalThreadSection(context, theme, property),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: sections,
    );
  }

  /// Seção de aprovação — aparece no topo dos detalhes para quem tem permissão,
  /// quando há disponibilidade e/ou publicação pendentes. Integrada ao layout
  /// flush (mesmo molde das outras seções), com Aprovar (verde) / Reprovar
  /// (vermelho — destrutivo, faz sentido aqui).
  Widget _buildApprovalSection(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final tone =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;

    final rows = <Widget>[];
    if (_availabilityPending(property) &&
        (_canApproveAvailability || _canRejectAvailability)) {
      rows.add(_approvalRow(
        context,
        label: 'Disponibilidade na operação',
        hint: 'Liberar este imóvel para a operação interna.',
        onApprove: _canApproveAvailability
            ? () => _doApproveAvailability(property)
            : null,
        onReject:
            _canRejectAvailability ? () => _doRejectAvailability(property) : null,
        green: green,
        danger: danger,
      ));
    }
    if (_publicationPending(property) &&
        (_canApprovePublication || _canRejectPublication)) {
      if (rows.isNotEmpty) {
        rows.add(const SizedBox(height: 16));
        rows.add(Divider(
          height: 1,
          color: ThemeHelpers.borderLightColor(context),
        ));
        rows.add(const SizedBox(height: 16));
      }
      rows.add(_approvalRow(
        context,
        label: 'Publicação no site',
        hint: 'Liberar este imóvel para o portal público.',
        onApprove: _canApprovePublication
            ? () => _doApprovePublication(property)
            : null,
        onReject:
            _canRejectPublication ? () => _doRejectPublication(property) : null,
        green: green,
        danger: danger,
      ));
    }

    return _buildFlushSection(
      theme: theme,
      title: 'Aprovação pendente',
      icon: Icons.verified_user_outlined,
      tone: tone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }

  /// Azul comunicação — mesma voz do chat do CRM (`_kChatTone` do
  /// task_details_modal). Vermelho aqui é só marca/erro/destrutivo.
  static const Color _kThreadTone = Color(0xFF3B82F6);

  /// Quantas mensagens aparecem antes do "Ver anteriores" — a seção não
  /// infla a página: as últimas N + scroll interno com teto de altura.
  static const int _kThreadPreviewCount = 10;

  /// Seção flush "Comunicação de aprovações" — paridade com a seção
  /// "Comunicação sobre aprovações" da ficha web (PropertyDetailsPage +
  /// PropertyApprovalCommunicationPanel variant full/flush).
  ///
  /// Contrato real (imobx):
  ///   GET  /properties/:id/approval-thread            → mensagens (asc)
  ///   POST /properties/:id/approval-thread            → { message, approvalContext }
  /// Filas: `availability` (Disponibilidade) e `publication` (Publicação no
  /// site) — obrigatório escolher antes de enviar; default = disponibilidade,
  /// igual ao web.
  Widget _buildApprovalThreadSection(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    const accent = _kThreadTone;
    final secondary = ThemeHelpers.textSecondaryColor(context);

    final Widget content;
    if (_threadLoading) {
      // Skeleton fiel ao layout final: avatar redondo + bolha.
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final h in const [56.0, 42.0])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonBox(width: 30, height: 30, borderRadius: 15),
                  const SizedBox(width: 10),
                  Expanded(child: SkeletonBox(height: h, borderRadius: 14)),
                ],
              ),
            ),
        ],
      );
    } else if (_threadLoadFailed) {
      content = Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 16, color: secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Não foi possível carregar a conversa.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
          TextButton(
            onPressed: _loadApprovalThread,
            // Tema global pinta TextButton de vermelho — accent forçado.
            style: TextButton.styleFrom(
              foregroundColor: accent,
              minimumSize: Size.zero,
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Tentar de novo',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      );
    } else if (_threadMessages.isEmpty) {
      // Empty state neutro — espelho do "Nenhuma mensagem ainda" do web.
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: isDark ? 0.16 : 0.1),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 20,
                color: accent,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Nenhuma mensagem ainda',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: ThemeHelpers.textColor(context),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Escolha a fila abaixo e envie a primeira mensagem.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    } else {
      final total = _threadMessages.length;
      final visible = (_threadShowAll || total <= _kThreadPreviewCount)
          ? _threadMessages
          : _threadMessages.sublist(total - _kThreadPreviewCount);
      final hiddenCount = total - visible.length;
      final myId = ModuleAccessService.instance.userId;

      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hiddenCount > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _threadShowAll = true),
                style: TextButton.styleFrom(
                  foregroundColor: accent,
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 5),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.history_rounded, size: 15),
                label: Text(
                  'Ver anteriores ($hiddenCount)',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ),
          // Lista com teto de altura + scroll interno — não infla a página.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: SingleChildScrollView(
              controller: _threadScroll,
              physics: const ClampingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final m in visible)
                    _ApprovalThreadBubble(
                      entry: m,
                      isMe: myId != null &&
                          myId.isNotEmpty &&
                          m.user?.id == myId,
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return _buildFlushSection(
      theme: theme,
      title: 'Comunicação de aprovações',
      icon: Icons.forum_outlined,
      tone: accent,
      // Fecha a página: sem isto sobraria um divisor solto no rodapé.
      isLast: true,
      headerTrailing: _threadMessages.isEmpty
          ? null
          : Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: accent.withValues(alpha: isDark ? 0.2 : 0.1),
              ),
              child: Text(
                '${_threadMessages.length}',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: accent,
                  letterSpacing: 0.2,
                ),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Chat interno entre quem aprova e quem responde pelo imóvel.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          content,
          const SizedBox(height: 14),
          // Seletor de fila — paridade com o "Enviar na fila" do web.
          Text(
            'ENVIAR NA FILA',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              fontSize: 10,
              color: secondary.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _threadQueueChip(
                  context,
                  label: 'Disponibilidade',
                  icon: Icons.fact_check_outlined,
                  selected: _threadQueue == ApprovalType.availability,
                  onTap: () => setState(
                      () => _threadQueue = ApprovalType.availability),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _threadQueueChip(
                  context,
                  label: 'Publicação no site',
                  icon: Icons.public_rounded,
                  selected: _threadQueue == ApprovalType.publication,
                  onTap: () => setState(
                      () => _threadQueue = ApprovalType.publication),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _threadComposerBar(context, theme),
        ],
      ),
    );
  }

  /// Chip de fila — estado claro: selecionado = tinted azul + check + w800.
  Widget _threadQueueChip(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const accent = _kThreadTone;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: selected
                ? accent.withValues(alpha: isDark ? 0.18 : 0.09)
                : Colors.transparent,
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.55)
                  : ThemeHelpers.borderColor(context)
                      .withValues(alpha: 0.45),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check_circle_rounded : icon,
                size: 15,
                color: selected ? accent : secondary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    letterSpacing: -0.1,
                    color: selected
                        ? accent
                        : ThemeHelpers.textColor(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Composer — TextField filled + botão enviar azul com loading (gramática
  /// do composer de comentários do CRM).
  Widget _threadComposerBar(BuildContext context, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    const accent = _kThreadTone;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 2, 6, 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: ThemeHelpers.cardBackgroundColor(context)
            .withValues(alpha: isDark ? 0.5 : 0.7),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _threadComposer,
              // Campo MULTILINHA: o teclado mostra "nova linha", nunca
              // "concluir". Sem tratar o toque fora, o único jeito de
              // fechar era sair da tela e voltar.
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              minLines: 1,
              maxLines: 4,
              maxLength: 4000,
              textCapitalization: TextCapitalization.sentences,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
              decoration: InputDecoration(
                hintText: 'Mensagem…',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: secondary,
                  fontWeight: FontWeight.w500,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                counterText: '',
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 5, top: 5),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _threadComposer,
              builder: (context, value, _) {
                final canSend =
                    value.text.trim().isNotEmpty && !_threadSending;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: canSend ? _sendApprovalThreadMessage : null,
                    borderRadius: BorderRadius.circular(12),
                    child: Ink(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: canSend
                            ? accent
                            : ThemeHelpers.borderColor(context)
                                .withValues(alpha: 0.3),
                      ),
                      child: SizedBox(
                        width: 38,
                        height: 38,
                        child: Center(
                          child: _threadSending
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  Icons.send_rounded,
                                  size: 18,
                                  color:
                                      canSend ? Colors.white : secondary,
                                ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _approvalRow(
    BuildContext context, {
    required String label,
    required String hint,
    VoidCallback? onApprove,
    VoidCallback? onReject,
    required Color green,
    required Color danger,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: ThemeHelpers.textColor(context),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          hint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            height: 1.3,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (onReject != null)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _approvalBusy ? null : onReject,
                  icon: _approvalBusy
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(danger),
                          ),
                        )
                      : const Icon(Icons.close_rounded, size: 20),
                  label: const Text(
                    'Reprovar',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: danger,
                    side: BorderSide(color: danger.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            if (onReject != null && onApprove != null)
              const SizedBox(width: 10),
            if (onApprove != null)
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _approvalBusy ? null : onApprove,
                  icon: _approvalBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded, size: 20),
                  label: const Text(
                    'Aprovar',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Botão "Republicar no site" — perfis elevados (master/admin/manager).
  /// Volta o imóvel para Disponível, ativo e visível no site (backend valida).
  /// Faixa de gestão do hero: ações compactas que mexem no estado do
  /// imóvel. Cada uma aparece para todos a quem o web mostra, travada com o
  /// motivo quando a pessoa não pode.
  List<Widget> _buildStatusActionsBlock(
    BuildContext context,
    Property property,
    bool isDark,
  ) {
    final green =
        isDark ? AppColors.status.successDarkMode : AppColors.status.success;
    final neutral = ThemeHelpers.textColor(context);
    final deleted = property.isDeleted;
    final statusLock = _statusChangeLockReason(property);
    final chips = <Widget>[
      // Todos veem; travado abre a folha com o status atual e o motivo.
      _HeroActionChip(
        icon: Icons.swap_horiz_rounded,
        label: 'Alterar status',
        tone: neutral,
        lockedReason: statusLock,
        onLockedTap: (_) => _openStatusChange(),
        onTap: _openStatusChange,
      ),
      if (!_canUndoSold && !deleted)
        _HeroActionChip(
          icon: Icons.published_with_changes_rounded,
          label: _republishLoading ? 'Republicando…' : 'Republicar no site',
          tone: green,
          busy: _republishLoading,
          lockedReason: _republishAllowed ? null : _republishLockedReason,
          onLockedTap: _showLockedReason,
          onTap: _republishOnSite,
        ),
      // Web: o interruptor Ativo/Inativo só existe para a gestão (os demais
      // acham a ação travada, com o motivo, no menu ⋯).
      if (_canChangePropertyStatusElevated && !deleted)
        _HeroActionChip(
          icon: Icons.power_settings_new_rounded,
          label: property.isActive ? 'Desativar' : 'Ativar',
          tone: property.isActive ? neutral : green,
          onTap: _openActivation,
        ),
    ];
    final access = ModuleAccessService.instance;
    final rights = PropertyApprovalBanner.approverRights(
      role: access.userRole,
      explicitPermissions: access.userPermissionNames,
    );
    return [
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: chips),
      // Recusa / em análise logo abaixo do status: o motivo e o "Reenviar"
      // aparecem antes de preço e características.
      if (PropertyApprovalBanner.hasContent(property)) ...[
        const SizedBox(height: 14),
        PropertyApprovalBanner(
          property: property,
          canApproveAvailability: rights.availability,
          canApprovePublication: rights.publication,
          onResent: _refreshAfterChange,
          onOpenQueue: _openApprovalsQueue,
          resendLockedReason: deleted ? kPropertyDeletedReadOnlyReason : null,
        ),
      ],
    ];
  }

  String _formatActivityDateTime(DateTime dt) {
    final d = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  // â”€â”€â”€ Aba ATIVIDADES (histórico + atualizações) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildActivityTab(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    const accent = Color(0xFFD97706);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final total = _updates.total;
    final updatesFailure = _updatesFailure;
    final historyFailure = _historyFailure;
    final updatesLock = property.isDeleted
        ? kPropertyDeletedReadOnlyReason
        : (_canEditProperty ? null : _editPermission.reasonMessage);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFlushSection(
          theme: theme,
          title: 'Atualizações',
          icon: Icons.campaign_outlined,
          tone: accent,
          headerTrailing: total > 0
              ? Text(
                  '$total registro${total > 1 ? 's' : ''}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Web: só quem pode editar a ficha registra atualização.
              if (updatesLock == null)
                _buildUpdateComposer(context, theme, accent)
              else
                _buildLockedLine(context, updatesLock),
              const SizedBox(height: 14),
              if (_loadingUpdates && !_updatesLoaded)
                _buildActivitySkeleton(context)
              else if (updatesFailure != null && _updates.data.isEmpty)
                AppErrorState.fromApi(
                  message: updatesFailure.message,
                  statusCode: updatesFailure.statusCode,
                  error: updatesFailure.error,
                  onRetry: _retryActivity,
                  dense: true,
                )
              else if (_updates.data.isEmpty)
                _buildActivityEmpty(
                  context,
                  theme,
                  'Nenhuma atualização registrada ainda.',
                  hint: updatesLock == null
                      ? 'Registre acima o que mudou: visita, contato com o '
                          'proprietário, ajuste de valor.'
                      : null,
                )
              else ...[
                for (var i = 0; i < _updates.data.length; i++)
                  _buildUpdateTile(
                    context,
                    theme,
                    _updates.data[i],
                    accent: accent,
                    last: i == _updates.data.length - 1,
                  ),
                if (_updates.data.length < total)
                  _buildLoadMoreUpdates(context, theme, total),
              ],
            ],
          ),
        ),
        _buildFlushSection(
          theme: theme,
          title: 'Histórico',
          icon: Icons.history_rounded,
          tone: const Color(0xFF475569),
          isLast: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loadingHistory && !_historyLoaded)
                _buildActivitySkeleton(context)
              else if (historyFailure != null && _history.isEmpty)
                AppErrorState.fromApi(
                  message: historyFailure.message,
                  statusCode: historyFailure.statusCode,
                  error: historyFailure.error,
                  onRetry: _retryActivity,
                  dense: true,
                )
              else if (_history.isEmpty)
                _buildActivityEmpty(
                  context,
                  theme,
                  'Sem histórico registrado.',
                  hint: 'Cada alteração no cadastro, mudança de status e '
                      'aprovação aparece aqui, com quem fez e quando.',
                )
              else
                ..._history.map((h) => _buildHistoryTile(context, theme, h)),
            ],
          ),
        ),
      ],
    );
  }

  /// "Carregar mais atualizações" — com o que falta e a falha no lugar.
  Widget _buildLoadMoreUpdates(
    BuildContext context,
    ThemeData theme,
    int total,
  ) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final remaining = total - _updates.data.length;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_moreUpdatesFailed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Não foi possível carregar mais agora. Confira a conexão e '
                'tente de novo.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: _loadingMoreUpdates ? null : _loadMoreUpdates,
            style: OutlinedButton.styleFrom(
              foregroundColor: ThemeHelpers.textColor(context),
              side: BorderSide(color: ThemeHelpers.borderColor(context)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: _loadingMoreUpdates
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(muted),
                    ),
                  )
                : Icon(
                    _moreUpdatesFailed
                        ? Icons.refresh_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                  ),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _loadingMoreUpdates
                    ? 'Carregando…'
                    : _moreUpdatesFailed
                        ? 'Tentar de novo'
                        : 'Carregar mais atualizações ($remaining)',
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Esqueleto da linha do tempo (ponto + 2 linhas), no lugar do spinner.
  Widget _buildActivitySkeleton(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonBox(width: 22, height: 22, borderRadius: 11),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SkeletonText(width: 150, height: 11),
                      const SizedBox(height: 8),
                      SkeletonText(
                        width: i.isEven ? double.infinity : 200,
                        height: 13,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Ação que a pessoa não pode fazer aqui: à vista, com cadeado e o motivo.
  Widget _buildLockedLine(BuildContext context, String reason) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ThemeHelpers.borderLightColor(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.lock_outline_rounded, size: 16, color: muted),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              reason,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityEmpty(
    BuildContext context,
    ThemeData theme,
    String message, {
    String? hint,
  }) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(
              hint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: muted,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUpdateComposer(
    BuildContext context,
    ThemeData theme,
    Color accent,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final green =
        isDark ? AppColors.status.successDarkMode : AppColors.status.success;
    final nearLimitTone =
        isDark ? AppColors.message.warningTextDarkMode : AppColors.message.warningText;
    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ThemeHelpers.borderColor(context)),
      ),
      padding: const EdgeInsets.all(12),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _updateComposer,
        builder: (context, value, _) {
          final count = value.text.length;
          final canSubmit = value.text.trim().isNotEmpty && !_submittingUpdate;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _updateComposer,
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
                maxLines: 4,
                minLines: 2,
                maxLength: 2000,
                enabled: !_submittingUpdate,
                decoration: const InputDecoration(
                  hintText: 'Registre uma atualização sobre este imóvel…',
                  border: InputBorder.none,
                  counterText: '',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$count/2000',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: count >= 1800 ? nearLimitTone : muted,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: canSubmit ? _submitPropertyUpdate : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: green,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: green.withValues(alpha: 0.4),
                      disabledForegroundColor:
                          Colors.white.withValues(alpha: 0.85),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    icon: _submittingUpdate
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.send_rounded, size: 16),
                    label: Text(_submittingUpdate ? 'Enviando…' : 'Registrar'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  /// Atualização na linha do tempo (flush): ponto (engrenagem =
  /// automática, lápis = manual), data · autor, selo e o texto.
  Widget _buildUpdateTile(
    BuildContext context,
    ThemeData theme,
    PropertyUpdateEntry update, {
    required Color accent,
    bool last = false,
  }) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final isDark = theme.brightness == Brightness.dark;
    final dotTone = update.isSystem ? muted : accent;
    final author = update.user?.name?.trim() ?? '';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(
                bottom: BorderSide(
                  color: ThemeHelpers.borderLightColor(context),
                ),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotTone.withValues(alpha: isDark ? 0.2 : 0.12),
              border: Border.all(color: dotTone.withValues(alpha: 0.35)),
            ),
            child: Icon(
              update.isSystem
                  ? Icons.settings_outlined
                  : Icons.edit_outlined,
              size: 12,
              color: dotTone,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        [
                          _formatActivityDateTime(update.createdAt),
                          if (author.isNotEmpty) author,
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: muted.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        update.isSystem ? 'Automático' : 'Manual',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  update.content,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTile(
    BuildContext context,
    ThemeData theme,
    PropertyHistoryEntry entry,
  ) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    const accent = Color(0xFF475569);
    final title = propertyHistoryEventLabel(entry.event);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 2,
                height: 26,
                color: ThemeHelpers.borderColor(context),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if ((entry.description ?? '').trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      entry.description!.trim(),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    '${entry.user?.name != null ? '${entry.user!.name} · ' : ''}${_formatActivityDateTime(entry.createdAt)}',
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // â”€â”€â”€ Aba DESEMPENHO (engajamento + observações) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildPerformanceTab(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    const accent = Color(0xFF10B981);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final published = property.isAvailableForSite == true;
    final Widget engagementChild;
    if (!published) {
      // Texto do web: fora do site não há o que medir — e diz o que fazer.
      engagementChild = _buildActivityEmpty(
        context,
        theme,
        'Imóvel fora do site público no momento.',
        hint: 'Publique o imóvel no site público para acompanhar '
            'visualizações, cliques e impressões — e liberar os atalhos Ver '
            'no site e Compartilhar no WhatsApp.',
      );
    } else if (_loadingEngagement || !_engagementLoaded) {
      engagementChild = _buildEngagementSkeleton(context);
    } else if (_engagement == null) {
      engagementChild = _buildActivityEmpty(
        context,
        theme,
        'Sem dados disponíveis ainda.',
        hint: 'As visitas e os cliques no anúncio do site aparecem aqui.',
      );
    } else {
      engagementChild = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildEngagementMetrics(context, theme),
          if (_engagementByChannel.isNotEmpty) ...[
            const SizedBox(height: 18),
            _buildEngagementByChannel(context, theme),
          ],
        ],
      );
    }
    final scoreResult = computePropertyScore(property);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Paridade web: `PropertyScoreDetails` flush no step Desempenho (sem
        // `PropertyDetailSection` duplicando o título).
        PropertyScorePanel(result: scoreResult),
        const SizedBox(height: 20),
        _buildFlushSection(
          theme: theme,
          title: 'Engajamento no site',
          icon: Icons.insights_rounded,
          tone: accent,
          headerTrailing: published
              ? Text(
                  'últimos 3 dias',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : null,
          child: engagementChild,
        ),
        _buildFlushSection(
          theme: theme,
          title: 'Observações internas',
          icon: Icons.lock_outline,
          tone: const Color(0xFFA855F7),
          isLast: true,
          child: _buildInternalNotes(context, theme, property),
        ),
      ],
    );
  }

  /// Esqueleto da faixa de números do engajamento.
  Widget _buildEngagementSkeleton(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 30, height: 30, borderRadius: 9),
                SizedBox(height: 8),
                SkeletonText(width: 56, height: 10),
                SizedBox(height: 6),
                SkeletonText(width: 36, height: 18),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Os 4 números do web (Visualizações, WhatsApp, Telefone, Impressões) em
  /// faixa flush: 4 colunas quando cabem, senão 2 × 2 — altura pelo
  /// conteúdo (a grade de proporção fixa estourava a 320dp com fonte grande).
  Widget _buildEngagementMetrics(BuildContext context, ThemeData theme) {
    final stats = _engagement;
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final items = <(String, int, IconData, Color)>[
      (
        'Visualizações',
        stats?.views ?? 0,
        Icons.visibility_outlined,
        isDark ? AppColors.status.infoDarkMode : AppColors.status.info,
      ),
      (
        'WhatsApp',
        stats?.whatsappClicks ?? 0,
        Icons.chat_outlined,
        isDark ? AppColors.status.successDarkMode : AppColors.status.success,
      ),
      (
        'Telefone',
        stats?.phoneClicks ?? 0,
        Icons.call_outlined,
        isDark ? AppColors.status.tealDarkMode : AppColors.status.teal,
      ),
      (
        'Impressões',
        stats?.prints ?? 0,
        Icons.print_outlined,
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple,
      ),
    ];

    Widget cell((String, int, IconData, Color) it) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              color: it.$4.withValues(alpha: isDark ? 0.18 : 0.12),
            ),
            child: Icon(it.$3, size: 16, color: it.$4),
          ),
          const SizedBox(height: 8),
          Text(
            it.$1,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${it.$2}',
              maxLines: 1,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: ThemeHelpers.textColor(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final cols = constraints.maxWidth / scale >= 340 ? 4 : 2;
        final rows = <Widget>[];
        for (var start = 0; start < items.length; start += cols) {
          if (rows.isNotEmpty) rows.add(const SizedBox(height: 14));
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = start; i < start + cols; i++) ...[
                  if (i > start) const SizedBox(width: 10),
                  Expanded(child: cell(items[i])),
                ],
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }

  /// "Por origem — últimos 30 dias" (até 8, como o web), em linhas flush.
  Widget _buildEngagementByChannel(BuildContext context, ThemeData theme) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final channels = _engagementByChannel.take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Por origem — últimos 30 dias',
          style: theme.textTheme.labelMedium?.copyWith(
            color: muted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < channels.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              border: i == channels.length - 1
                  ? null
                  : Border(
                      bottom: BorderSide(
                        color: ThemeHelpers.borderLightColor(context),
                      ),
                    ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  channels[i].label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    '${channels[i].views} visualizações',
                    if (channels[i].whatsappClicks > 0)
                      '${channels[i].whatsappClicks} WA',
                    if (channels[i].phoneClicks > 0)
                      '${channels[i].phoneClicks} tel',
                    if (channels[i].emailClicks > 0)
                      '${channels[i].emailClicks} e-mail',
                    if (channels[i].favorites > 0)
                      '${channels[i].favorites} fav',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildInternalNotes(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final notes = (property.internalNotes ?? '').trim();

    if (_editingNotes) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          TextField(
            controller: _notesController,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            maxLines: 6,
            minLines: 3,
            maxLength: 10000,
            decoration: InputDecoration(
              hintText: 'Anotações internas (não aparecem no site)…',
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _savingNotes
                    ? null
                    : () => setState(() => _editingNotes = false),
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _savingNotes ? null : _saveInternalNotes,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFA855F7),
                ),
                child: Text(_savingNotes ? 'Salvando…' : 'Salvar'),
              ),
            ],
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ThemeHelpers.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            notes.isEmpty ? 'Nenhuma observação interna.' : notes,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: notes.isEmpty ? muted : null,
              height: 1.5,
            ),
          ),
          if (_canEditProperty) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  _notesController.text = notes;
                  setState(() => _editingNotes = true);
                },
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: Text(notes.isEmpty ? 'Adicionar' : 'Editar'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFA855F7),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Header flush (paridade web `PropertyDetailSectionTitle`): apenas uma
  /// régua vertical fina na cor da seção + título bold + ícone discreto à
  /// direita. Sem chip com background, sem moldura — nada que reforce a
  /// ideia de "card dentro de card".
  Widget _buildSectionHeader(
    ThemeData theme,
    String title,
    IconData icon, {
    Color? accentOverride,
    Widget? trailing,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final accent = accentOverride ??
        (isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              height: 1.2,
              color: ThemeHelpers.textColor(context),
            ),
          ),
        ),
        // Trailing útil (botão/contador) no lugar do ícone decorativo —
        // nunca os dois brigando pelo canto direito.
        trailing ??
            Icon(
              icon,
              size: 18,
              color: ThemeHelpers.textSecondaryColor(context)
                  .withValues(alpha: 0.7),
            ),
      ],
    );
  }

  /// Wrapper flush de seção (paridade web `PropertyDetailSection`): padding
  /// vertical, divisor inferior fininho, sem moldura/borda/cartão. Caller
  /// passa o conteúdo direto, sem `Container` decorado por fora.
  Widget _buildFlushSection({
    required ThemeData theme,
    required String title,
    required IconData icon,
    required Color tone,
    required Widget child,
    bool isLast = false,
    Widget? headerTrailing,
  }) {
    final divider = ThemeHelpers.borderColor(context).withValues(alpha: 0.33);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: divider, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader(
            theme,
            title,
            icon,
            accentOverride: tone,
            trailing: headerTrailing,
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  /// Descrição editorial — sem caixa, sem limite duro, com expand/collapse.
  ///
  /// Antes era um Container com border + sombra + stripe accent + texto
  /// sem limite, virando paredão infinito em imóveis com descrição
  /// longa.
  ///
  /// Agora delega ao `_ExpandableDescription`:
  /// - Texto vai DIRETO sobre o background (sem caixa cinza)
  /// - Régua accent fina à esquerda como ânfase editorial
  /// - Mostra ~5 linhas com **gradient fade** no rodapé indicando truncamento
  /// - Botão "Ver mais" / "Ver menos" — não corta o conteúdo, só recolhe
  Widget _buildDescriptionCard(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    return _ExpandableDescription(text: property.description);
  }

  /// Grade flat de características — paridade `PropertyDetailsCharacteristicsSection`.
  Widget _buildCharacteristicsGrid(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    String formatArea(double value) {
      final n = value;
      final text = n == n.roundToDouble()
          ? n.toInt().toString()
          : n.toStringAsFixed(2).replaceAll('.', ',');
      return '$text m²';
    }

    final items = <({IconData icon, String label, String value})>[
      if (property.totalArea > 0)
        (
          icon: Icons.straighten_rounded,
          label: 'Área total',
          value: formatArea(property.totalArea),
        ),
      if (property.builtArea != null && property.builtArea! > 0)
        (
          icon: Icons.home_outlined,
          label: 'Área construída',
          value: formatArea(property.builtArea!),
        ),
      if (property.bedrooms != null && property.bedrooms! > 0)
        (
          icon: Icons.bed_outlined,
          label: 'Quartos',
          value: '${property.bedrooms}',
        ),
      if (property.suites != null && property.suites! > 0)
        (
          icon: Icons.king_bed_outlined,
          label: 'Suítes',
          value: '${property.suites}',
        ),
      if (property.bathrooms != null && property.bathrooms! > 0)
        (
          icon: Icons.bathtub_outlined,
          label: 'Banheiros',
          value: '${property.bathrooms}',
        ),
      if (property.parkingSpaces != null && property.parkingSpaces! > 0)
        (
          icon: Icons.directions_car_filled_outlined,
          label: 'Vagas',
          value: '${property.parkingSpaces}',
        ),
    ];

    if (items.isEmpty) {
      return Text(
        'Nenhuma característica cadastrada.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: ThemeHelpers.textSecondaryColor(context),
        ),
      );
    }

    final muted = ThemeHelpers.textSecondaryColor(context);
    final borderTint = ThemeHelpers.borderColor(context).withValues(alpha: 0.27);
    final cols = MediaQuery.sizeOf(context).width > 520 ? 3 : 2;

    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = (constraints.maxWidth - (cols - 1) * 16) / cols;
        return Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            for (var i = 0; i < items.length; i++)
              SizedBox(
                width: tileWidth,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: i % cols != cols - 1
                      ? BoxDecoration(
                          border: Border(
                            right: BorderSide(color: borderTint, width: 1),
                          ),
                        )
                      : null,
                  child: Row(
                    children: [
                      Icon(
                        items[i].icon,
                        size: 17,
                        color: muted.withValues(alpha: 0.72),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              items[i].value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.02,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              items[i].label.toUpperCase(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: muted,
                                fontWeight: FontWeight.w600,
                                fontSize: 10,
                                letterSpacing: 0.05,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCondominiumSection(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final name = _linkedCondominium?.name.trim().isNotEmpty == true
        ? _linkedCondominium!.name.trim()
        : 'Condomínio vinculado';

    if (_loadingCondominium) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }

    final c = _linkedCondominium;
    final addressParts = <String>[
      if (c != null) ...[
        if ((c.street ?? '').isNotEmpty) c.street!,
        if ((c.number ?? '').isNotEmpty) c.number!,
      ],
      if (c != null && (c.neighborhood ?? '').isNotEmpty) c.neighborhood!,
      if (c != null &&
          (c.city ?? '').isNotEmpty &&
          (c.state ?? '').isNotEmpty)
        '${c.city}/${c.state}',
    ];
    final address = addressParts.where((s) => s.trim().isNotEmpty).join(', ');

    final fee = property.condominiumFee;
    final hasFee = fee != null && fee > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: _salePriceColor(theme.brightness == Brightness.dark),
          ),
        ),
        if (address.isNotEmpty) ...[
          const SizedBox(height: 10),
          _buildCondominiumInfoRow(
            theme,
            Icons.location_on_outlined,
            'Endereço',
            address,
            muted,
          ),
        ],
        if (hasFee)
          _buildCondominiumInfoRow(
            theme,
            Icons.payments_outlined,
            'Taxa informada no imóvel',
            _currencyFormatter.format(fee),
            muted,
          ),
      ],
    );
  }

  Widget _buildCondominiumInfoRow(
    ThemeData theme,
    IconData icon,
    String label,
    String value,
    Color muted,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: muted.withValues(alpha: 0.85)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Ações rápidas como LINHAS ricas — roundel tinted 40 + título w800 +
  /// subtítulo informativo + chevron, com hairline recuada entre elas. Cor
  /// POR SIGNIFICADO (agendar = âmbar, matches = violeta, ofertas = cyan,
  /// vistoria = teal). Substitui o grid de botões soltos sem contexto; zero
  /// caixa em volta da seção.
  Widget _buildQuickActionsSection(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final pendingOffers = property.pendingOffersCount ?? 0;
    final actions = <({
      IconData icon,
      String title,
      String subtitle,
      Color color,
      VoidCallback onTap,
    })>[
      (
        icon: Icons.event_rounded,
        title: 'Agendar visita',
        subtitle: 'Marque um horário com o cliente na agenda',
        color: const Color(0xFFE6B84C),
        onTap: () => _openScheduleVisit(property),
      ),
      (
        icon: Icons.picture_as_pdf_outlined,
        title: 'Apresentação em PDF',
        subtitle: 'Fotos, valores e seu contato para enviar ao cliente',
        color: theme.brightness == Brightness.dark
            ? AppColors.status.infoDarkMode
            : AppColors.status.info,
        onTap: _openPresentationPdf,
      ),
      // Matches e Ofertas ocultas no app: as linhas só voltam com os flags.
      if (FeatureVisibility.matchesEnabled)
        (
          icon: Icons.join_inner_rounded,
          title: 'Ver matches',
          subtitle: 'Clientes com perfil compatível com este imóvel',
          color: const Color(0xFF8B5CF6),
          onTap: () => Navigator.pushNamed(
            context,
            AppRoutes.matchesByProperty(widget.propertyId),
          ),
        ),
      if (FeatureVisibility.offersEnabled)
        (
          icon: Icons.request_quote_outlined,
          title: 'Ver ofertas',
          subtitle: pendingOffers > 0
              ? '$pendingOffers pendente${pendingOffers > 1 ? 's' : ''} '
                  'aguardando resposta'
              : 'Propostas recebidas para este imóvel',
          color: const Color(0xFF0891B2),
          onTap: () => Navigator.of(context).pushNamed(
            '/properties/offers',
            arguments: {'propertyId': widget.propertyId},
          ),
        ),
      (
        icon: Icons.camera_alt_outlined,
        title: 'Nova vistoria',
        subtitle: 'Registre o estado atual do imóvel com fotos',
        color: const Color(0xFF14B8A6),
        onTap: () =>
            Navigator.of(context).pushNamed(AppRoutes.inspectionCreate),
      ),
    ];

    Widget divider() => Container(
          height: 1,
          // Recuada: alinhada ao texto (40 do roundel + 14 do gap).
          margin: const EdgeInsets.only(left: 54),
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.30),
        );

    final children = <Widget>[];
    for (var i = 0; i < actions.length; i++) {
      if (i > 0) children.add(divider());
      final action = actions[i];
      children.add(_buildQuickActionRow(
        context,
        theme,
        icon: action.icon,
        title: action.title,
        subtitle: action.subtitle,
        color: action.color,
        onTap: action.onTap,
      ));
    }

    // Web: "Gerar Proposta" com o módulo de IA e o imóvel disponível. O
    // gerador ainda não existe no app — fica à vista, travado, com o motivo.
    if (ModuleAccessService.instance.isModuleAvailableForCompany(
          'ai_assistant',
        ) &&
        property.status == PropertyStatus.available) {
      children
        ..add(divider())
        ..add(_buildQuickActionRow(
          context,
          theme,
          icon: Icons.description_outlined,
          title: 'Gerar proposta (IA)',
          subtitle: 'Proposta escrita pela IA a partir deste imóvel',
          color: AppColors.status.purple,
          lockedReason: 'Por enquanto só no painel web: o gerador de '
              'proposta com IA ainda não chegou ao app.',
          onTap: () {},
        ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _buildQuickActionRow(
    BuildContext context,
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    String? lockedReason,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final locked = lockedReason != null;
    if (locked) color = muted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        // Travada: o toque explica o motivo em vez de não fazer nada.
        onTap: locked ? () => _showLockedReason(lockedReason) : onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: color.withValues(alpha: 0.16),
        highlightColor: color.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: color.withValues(alpha: isDark ? 0.18 : 0.12),
                  border: Border.all(
                    color: color.withValues(alpha: isDark ? 0.34 : 0.22),
                  ),
                ),
                child: Icon(icon, size: 19, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.15,
                        fontSize: 14.5,
                        color: locked ? muted : ThemeHelpers.textColor(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lockedReason ?? subtitle,
                      maxLines: locked ? 3 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        fontSize: 11.5,
                        height: 1.3,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                locked
                    ? Icons.lock_outline_rounded
                    : Icons.chevron_right_rounded,
                size: locked ? 17 : 20,
                color: muted.withValues(alpha: locked ? 0.85 : 0.55),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOffersSection(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              Navigator.of(context).pushNamed(
                '/properties/offers',
                arguments: {'propertyId': property.id},
              );
            },
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: const Text('Ver todas'),
          ),
        ),
        if (property.totalOffersCount != null) ...[
          _buildInfoRow(theme, 'Total', '${property.totalOffersCount}'),
          if (property.pendingOffersCount != null)
            _buildInfoRow(theme, 'Pendentes', '${property.pendingOffersCount}'),
          if (property.acceptedOffersCount != null)
            _buildInfoRow(theme, 'Aceitas', '${property.acceptedOffersCount}'),
          if (property.rejectedOffersCount != null)
            _buildInfoRow(
                theme, 'Rejeitadas', '${property.rejectedOffersCount}'),
        ],
      ],
    );
  }

  Widget _buildInfoRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Status da chave — flush. Com chave: linhas ricas (roundel tinted na cor
  /// SEMÂNTICA do status + nome + detalhe + chevron, tap abre o controle de
  /// chaves). Sem chave: empty state digno e NEUTRO (slate) — sem vermelho,
  /// sem caixa gritante.
  Widget _buildKeyStatusSection(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);

    if (_isLoadingKeys) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }

    if (_keys.isEmpty) {
      final slate = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  color: slate.withValues(alpha: isDark ? 0.16 : 0.10),
                  border: Border.all(
                    color: slate.withValues(alpha: isDark ? 0.32 : 0.22),
                  ),
                ),
                child: Icon(Icons.key_off_rounded, size: 20, color: slate),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nenhuma chave cadastrada',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Cadastre no painel para controlar retiradas '
                      'e devoluções',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        fontSize: 11.5,
                        height: 1.35,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _showCreateKeyModal(context, property),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Cadastrar chave'),
              // Ação aditiva/neutra — nada de vermelho.
              style: OutlinedButton.styleFrom(
                foregroundColor: ThemeHelpers.textColor(context),
                side: BorderSide(color: ThemeHelpers.borderColor(context)),
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < _keys.length; i++) {
      if (i > 0) {
        rows.add(Container(
          height: 1,
          margin: const EdgeInsets.only(left: 54),
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.30),
        ));
      }
      rows.add(_buildKeyRow(context, theme, property, _keys[i]));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  /// Cor + ícone SEMÂNTICOS do status da chave (verde = disponível, âmbar =
  /// em uso, vermelho = perdida (erro de verdade), laranja = danificada,
  /// slate = manutenção).
  ({Color color, IconData icon}) _keyStatusVisual(key_models.KeyStatus status) {
    switch (status) {
      case key_models.KeyStatus.available:
        return (color: const Color(0xFF10B981), icon: Icons.vpn_key_rounded);
      case key_models.KeyStatus.inUse:
        return (color: const Color(0xFFF59E0B), icon: Icons.schedule_rounded);
      case key_models.KeyStatus.lost:
        return (color: const Color(0xFFEF4444), icon: Icons.key_off_rounded);
      case key_models.KeyStatus.damaged:
        return (
          color: const Color(0xFFF97316),
          icon: Icons.report_problem_outlined,
        );
      case key_models.KeyStatus.maintenance:
        return (color: const Color(0xFF64748B), icon: Icons.build_rounded);
    }
  }

  Widget _buildKeyRow(
    BuildContext context,
    ThemeData theme,
    Property property,
    key_models.Key k,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final visual = _keyStatusVisual(k.status);
    final color = visual.color;
    final location = k.location?.trim() ?? '';
    final detail =
        location.isNotEmpty ? '${k.status.label} · $location' : k.status.label;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pushNamed(
          '/keys',
          arguments: {'propertyId': property.id},
        ),
        borderRadius: BorderRadius.circular(12),
        splashColor: color.withValues(alpha: 0.16),
        highlightColor: color.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: color.withValues(alpha: isDark ? 0.18 : 0.12),
                  border: Border.all(
                    color: color.withValues(alpha: isDark ? 0.34 : 0.22),
                  ),
                ),
                child: Icon(visual.icon, size: 19, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      k.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.15,
                        fontSize: 14.5,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w500,
                              fontSize: 11.5,
                              height: 1.3,
                              color: muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: muted.withValues(alpha: 0.55),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Rótulos do web (`getClientTypeLabel`).
  static String _clientTypeLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'buyer':
        return 'Comprador';
      case 'seller':
        return 'Vendedor';
      case 'renter':
        return 'Locatário';
      case 'lessor':
        return 'Locador';
      case 'investor':
        return 'Investidor';
      case '':
      case 'general':
        return 'Geral';
    }
    return raw;
  }

  /// Rótulos do web (`getInterestTypeLabel`) + os valores que o app
  /// gravava antes (compra/aluguel/ambos), para vínculos antigos lerem bem.
  static String _clientInterestLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case '':
      case 'interested':
        return 'Interessado';
      case 'contacted':
        return 'Contatado';
      case 'viewing':
        return 'Visualizando';
      case 'negotiating':
        return 'Negociando';
      case 'closed':
        return 'Fechado';
      case 'buy':
        return 'Compra';
      case 'rent':
        return 'Aluguel';
      case 'both':
        return 'Compra e aluguel';
    }
    return raw;
  }

  Widget _buildClientsSection(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final clients = property.clients ?? const <PropertyClient>[];
    final readOnly = property.isDeleted;

    Widget linkButton(String label) {
      if (readOnly) {
        return _buildLockedLine(context, kPropertyDeletedReadOnlyReason);
      }
      return OutlinedButton.icon(
        onPressed: () => _showLinkClientModal(context, property),
        style: OutlinedButton.styleFrom(
          foregroundColor: ThemeHelpers.textColor(context),
          side: BorderSide(color: ThemeHelpers.borderColor(context)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    if (clients.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildActivityEmpty(
            context,
            theme,
            'Nenhum cliente vinculado',
            hint: 'Vincule clientes interessados nesta propriedade para '
                'acompanhar negociações.',
          ),
          const SizedBox(height: 4),
          linkButton('Vincular clientes'),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < clients.length; i++)
          _buildLinkedClientRow(
            context,
            theme,
            property,
            clients[i],
            last: i == clients.length - 1,
          ),
        const SizedBox(height: 12),
        linkButton('Vincular clientes'),
      ],
    );
  }

  /// Cliente vinculado em linha flush — quem é, o interesse e como falar
  /// com ele, sem abrir a ficha do cliente.
  Widget _buildLinkedClientRow(
    BuildContext context,
    ThemeData theme,
    Property property,
    PropertyClient client, {
    bool last = false,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    const tone = Color(0xFF0EA5E9);
    final name = client.name.trim().isEmpty
        ? 'Nome não disponível'
        : client.name.trim();
    final initial = client.name.trim().isEmpty
        ? '?'
        : client.name.trim().characters.first.toUpperCase();
    final contact = [
      if (client.email.trim().isNotEmpty) client.email.trim(),
      if (client.phone.trim().isNotEmpty) client.phone.trim(),
    ].join(' · ');
    final contactedAt = DateTime.tryParse(client.contactedAt ?? '');
    final notes = client.notes?.trim() ?? '';

    Widget pill(String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: tone.withValues(alpha: isDark ? 0.18 : 0.10),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w700,
            ),
          ),
        );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context)
            .pushNamed(AppRoutes.clientDetails(client.id)),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: last
                ? null
                : Border(
                    bottom: BorderSide(
                      color: ThemeHelpers.borderLightColor(context),
                    ),
                  ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tone.withValues(alpha: isDark ? 0.2 : 0.12),
                ),
                child: Text(
                  initial,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        pill(_clientTypeLabel(client.type)),
                        pill(_clientInterestLabel(client.interestType)),
                      ],
                    ),
                    if (contact.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        contact,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ],
                    if (client.responsibleUserName.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Responsável: ${client.responsibleUserName.trim()}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ],
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        notes,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    if (contactedAt != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Último contato: '
                        '${DateFormat('dd/MM/yyyy').format(contactedAt.toLocal())}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Ações do cliente',
                onPressed: () =>
                    _showLinkedClientActions(property, client, name),
                icon: Icon(Icons.more_vert_rounded, color: muted, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Menu do cliente vinculado — Visualizar, Editar e Desvincular (o web
  /// esconde o desvincular com o imóvel excluído; aqui fica travado).
  void _showLinkedClientActions(
    Property property,
    PropertyClient client,
    String name,
  ) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final isDark = theme.brightness == Brightness.dark;
        final muted = ThemeHelpers.textSecondaryColor(sheetContext);
        final danger =
            isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

        Widget action({
          required IconData icon,
          required String label,
          required VoidCallback onTap,
          String? lockedReason,
          bool destructive = false,
        }) {
          final locked = lockedReason != null;
          final color = locked
              ? muted
              : destructive
                  ? danger
                  : ThemeHelpers.textColor(sheetContext);
          return InkWell(
            onTap: locked
                ? null
                : () {
                    Navigator.of(sheetContext).pop();
                    onTap();
                  },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 20, color: color),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                        if (locked) ...[
                          const SizedBox(height: 2),
                          Text(
                            lockedReason,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: muted,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (locked)
                    Icon(Icons.lock_outline_rounded, size: 16, color: muted),
                ],
              ),
            ),
          );
        }

        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.88,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: ThemeHelpers.cardBackgroundColor(sheetContext),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Fechar',
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: Icon(Icons.close_rounded, color: muted),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    height: 1,
                    color: ThemeHelpers.borderLightColor(sheetContext),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          action(
                            icon: Icons.visibility_outlined,
                            label: 'Visualizar',
                            onTap: () => Navigator.of(context).pushNamed(
                              AppRoutes.clientDetails(client.id),
                            ),
                          ),
                          action(
                            icon: Icons.edit_outlined,
                            label: 'Editar',
                            onTap: () => Navigator.of(context).pushNamed(
                              AppRoutes.clientEdit(client.id),
                            ),
                          ),
                          action(
                            icon: Icons.link_off_rounded,
                            label: 'Desvincular cliente',
                            destructive: true,
                            lockedReason: property.isDeleted
                                ? kPropertyDeletedReadOnlyReason
                                : null,
                            onTap: () =>
                                _confirmUnlinkClient(property, client, name),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmUnlinkClient(
    Property property,
    PropertyClient client,
    String name,
  ) async {
    final danger = Theme.of(context).brightness == Brightness.dark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ThemeHelpers.cardBackgroundColor(ctx),
        title: const Text('Desvincular cliente?'),
        content: SingleChildScrollView(
          child: Text(
            '$name deixa de aparecer entre os clientes deste imóvel. O '
            'cadastro do cliente não muda e dá para vincular de novo.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: ThemeHelpers.textSecondaryColor(ctx),
            ),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Desvincular'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final res = await _clientService.disassociateClientFromProperty(
      client.id,
      property.id,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res.success
              ? 'Cliente desvinculado com sucesso!'
              : (res.message ?? 'Erro ao desvincular cliente'),
        ),
        backgroundColor:
            res.success ? AppColors.status.success : AppColors.status.error,
      ),
    );
    if (res.success) _refreshAfterChange();
  }

  Widget _buildExpensesSection(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              _showCreateExpenseModal(context, property);
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Adicionar'),
          ),
        ),
        const SizedBox(height: 4),
            if (_isLoadingExpenses)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_expenses.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 48,
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Nenhuma despesa cadastrada',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              // Resumo de Despesas
              if (_expensesSummary != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.background.backgroundSecondaryDarkMode
                        : AppColors.background.backgroundSecondary,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: ThemeHelpers.borderLightColor(context),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Resumo',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Pendentes',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: ThemeHelpers.textSecondaryColor(
                                      context,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_expensesSummary!['totalPending'] ?? 0}',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Vencidas',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: ThemeHelpers.textSecondaryColor(
                                      context,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_expensesSummary!['totalOverdue'] ?? 0}',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.status.error,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Pagas',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: ThemeHelpers.textSecondaryColor(
                                      context,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_expensesSummary!['totalPaid'] ?? 0}',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.status.success,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Total Pendente',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: ThemeHelpers.textSecondaryColor(
                                      context,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _currencyFormatter.format(
                                    ((_expensesSummary!['totalPendingAmount'] ??
                                                0)
                                            as num)
                                        .toDouble(),
                                  ),
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              // Lista de Despesas
              ...(_expenses.take(5).map((expense) {
                final exp = expense as Map<String, dynamic>;
                final expenseId = exp['id']?.toString() ?? '';
                final title = exp['title']?.toString() ?? 'Despesa';
                final amount = exp['amount']?.toString() ?? '0';
                final status = exp['status']?.toString() ?? 'pending';
                final dueDate = exp['dueDate']?.toString();

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.background.backgroundSecondaryDarkMode
                        : AppColors.background.backgroundSecondary,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: ThemeHelpers.borderLightColor(context),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _currencyFormatter.format(
                                double.tryParse(amount) ?? 0,
                              ),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppColors.primary.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (dueDate != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Vence: ${DateFormat('dd/MM/yyyy').format(DateTime.parse(dueDate))}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: ThemeHelpers.textSecondaryColor(
                                    context,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: status == 'paid'
                              ? AppColors.status.success.withValues(alpha: 0.1)
                              : status == 'overdue'
                              ? AppColors.status.error.withValues(alpha: 0.1)
                              : AppColors.status.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          status == 'paid'
                              ? 'Paga'
                              : status == 'overdue'
                              ? 'Vencida'
                              : 'Pendente',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: status == 'paid'
                                ? AppColors.status.success
                                : status == 'overdue'
                                ? AppColors.status.error
                                : AppColors.status.warning,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        onSelected: (value) {
                          if (value == 'mark_paid') {
                            _markExpenseAsPaid(context, property.id, expenseId);
                          } else if (value == 'edit') {
                            _showEditExpenseModal(context, property, expense);
                          } else if (value == 'delete') {
                            _deleteExpense(
                              context,
                              property.id,
                              expenseId,
                              title,
                            );
                          }
                        },
                        itemBuilder: (context) => [
                          if (status != 'paid')
                            const PopupMenuItem(
                              value: 'mark_paid',
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle, size: 18),
                                  SizedBox(width: 8),
                                  Text('Marcar como Paga'),
                                ],
                              ),
                            ),
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit, size: 18),
                                SizedBox(width: 8),
                                Text('Editar'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, size: 18, color: Colors.red),
                                SizedBox(width: 8),
                                Text(
                                  'Excluir',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              })),
        ],
      ],
    );
  }

  Widget _buildChecklistsSection(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              _showCreateChecklistModal(context, property);
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Criar Checklist'),
          ),
        ),
        const SizedBox(height: 4),
            if (_isLoadingChecklists)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_checklists.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.checklist_outlined,
                        size: 48,
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Nenhum checklist cadastrado',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              ...(_checklists.take(5).map((checklist) {
                final chk = _asStringKeyedMap(checklist) ?? const <String, dynamic>{};
                final checklistId = chk['id']?.toString() ?? '';
                final type = chk['type']?.toString() ?? 'sale';
                final status = chk['status']?.toString() ?? 'pending';
                final completionPercentage = _extractChecklistCompletionPercentage(
                  chk,
                );
                final client = chk['client'] as Map<String, dynamic>?;
                final clientName =
                    client?['name']?.toString() ?? 'Cliente não informado';

                return InkWell(
                  onTap: () {
                    if (checklistId.isEmpty) return;
                    Navigator.of(context).pushNamed('/checklists/$checklistId');
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.background.backgroundSecondaryDarkMode
                          : AppColors.background.backgroundSecondary,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: ThemeHelpers.borderLightColor(context),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Checklist de ${type == 'sale' ? 'Venda' : 'Aluguel'}',
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Cliente: $clientName',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: ThemeHelpers.textSecondaryColor(
                                        context,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: status == 'completed'
                                    ? AppColors.status.success.withValues(
                                        alpha: 0.1,
                                      )
                                    : status == 'in_progress'
                                    ? AppColors.status.warning.withValues(
                                        alpha: 0.1,
                                      )
                                    : AppColors.background.backgroundSecondary,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                status == 'completed'
                                    ? 'Concluído'
                                    : status == 'in_progress'
                                    ? 'Em Andamento'
                                    : 'Pendente',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: status == 'completed'
                                      ? AppColors.status.success
                                      : status == 'in_progress'
                                      ? AppColors.status.warning
                                      : ThemeHelpers.textSecondaryColor(
                                          context,
                                        ),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                              color: ThemeHelpers.textSecondaryColor(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: LinearProgressIndicator(
                                value: completionPercentage / 100,
                                backgroundColor: ThemeHelpers.borderLightColor(
                                  context,
                                ),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.primary.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '${completionPercentage.toStringAsFixed(0)}%',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              })),
      ],
    );
  }

  Widget _buildDocumentsSection(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    if (!DocumentPermissions.moduleEnabled) {
      return _buildLockedLine(
        context,
        'Documentos fazem parte de um módulo que não está incluído no plano '
        'atual da empresa. Fale com o administrador.',
      );
    }
    final failure = _documentsFailure;
    final createLock = property.isDeleted
        ? kPropertyDeletedReadOnlyReason
        : DocumentPermissions.canCreate
            ? null
            : 'Sem a permissão para criar documentos. Fale com o seu gestor '
                'ou com o suporte.';

    Widget addButton(String label) {
      if (createLock != null) return _buildLockedLine(context, createLock);
      return OutlinedButton.icon(
        onPressed: () => _openDocumentCreate(property),
        style: OutlinedButton.styleFrom(
          foregroundColor: ThemeHelpers.textColor(context),
          side: BorderSide(color: ThemeHelpers.borderColor(context)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: const Icon(Icons.add_rounded, size: 18),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    if (_isLoadingDocuments && _documents.isEmpty) {
      return _buildActivitySkeleton(context);
    }
    if (failure != null && _documents.isEmpty) {
      return AppErrorState.fromApi(
        message: failure.message,
        statusCode: failure.statusCode,
        error: failure.error,
        onRetry: _loadDocuments,
        dense: true,
      );
    }
    if (_documents.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildActivityEmpty(
            context,
            theme,
            'Nenhum documento encontrado',
            hint: 'Este imóvel ainda não possui documentos. Matrícula, IPTU, '
                'contratos e laudos ficam aqui, à mão de quem atende.',
          ),
          const SizedBox(height: 4),
          addButton('Adicionar primeiro documento'),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _documents.length; i++)
          _buildDocumentRow(
            context,
            theme,
            _documents[i],
            last: i == _documents.length - 1,
          ),
        const SizedBox(height: 12),
        addButton('Adicionar documento'),
        if (_isLoadingDocuments)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(
              minHeight: 2,
              color: muted,
              backgroundColor: muted.withValues(alpha: 0.12),
            ),
          ),
      ],
    );
  }

  /// Documento em linha flush: situação no ícone, nome, "tipo · tamanho ·
  /// situação · vencimento", descrição; toque abre o documento e o ⋯ traz
  /// Visualizar / Baixar / Editar / Excluir.
  Widget _buildDocumentRow(
    BuildContext context,
    ThemeData theme,
    Document document, {
    bool last = false,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final Color tone;
    final IconData icon;
    switch (document.status) {
      case DocumentStatus.approved:
        tone = isDark
            ? AppColors.status.successDarkMode
            : AppColors.status.success;
        icon = Icons.check_circle_outline_rounded;
      case DocumentStatus.rejected:
        tone = isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
        icon = Icons.cancel_outlined;
      case DocumentStatus.pendingReview:
        tone = isDark
            ? AppColors.message.warningTextDarkMode
            : AppColors.message.warningText;
        icon = Icons.schedule_rounded;
      default:
        tone = muted;
        icon = Icons.insert_drive_file_outlined;
    }
    final expiry = document.expiryDate;
    final meta = [
      document.type.label,
      _formatFileSize(document.fileSize),
      document.status.label,
      if (expiry != null)
        'vence ${DateFormat('dd/MM/yyyy').format(expiry.toLocal())}',
    ].join(' · ');
    final name = (document.title ?? '').trim().isNotEmpty
        ? document.title!.trim()
        : document.originalName;
    final description = document.description?.trim() ?? '';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openDocument(document),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: last
                ? null
                : Border(
                    bottom: BorderSide(
                      color: ThemeHelpers.borderLightColor(context),
                    ),
                  ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: tone.withValues(alpha: isDark ? 0.18 : 0.10),
                ),
                child: Icon(icon, size: 18, color: tone),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Ações do documento',
                onPressed: () => _showDocumentActions(document),
                icon: Icon(Icons.more_vert_rounded, color: muted, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 KB';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1).replaceAll('.', ',')} MB';
  }

  void _openDocument(Document document) {
    Navigator.of(context)
        .pushNamed(AppRoutes.documentDetails(document.id))
        .then((_) {
      if (mounted) _loadDocuments();
    });
  }

  void _openDocumentCreate(Property property) {
    Navigator.of(context)
        .push(
      MaterialPageRoute<void>(
        builder: (_) => CreateDocumentPage(
          initialPropertyId: property.id,
          initialPropertyName: property.title,
        ),
      ),
    )
        .then((_) {
      if (mounted) _loadDocuments();
    });
  }

  /// Ações do documento — as do web (Visualizar, Download, Editar, Excluir),
  /// cada uma travada com a frase do web quando falta a permissão.
  void _showDocumentActions(Document document) {
    final name = (document.title ?? '').trim().isNotEmpty
        ? document.title!.trim()
        : document.originalName;
    final deleted = _property?.isDeleted == true;
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final isDark = theme.brightness == Brightness.dark;
        final muted = ThemeHelpers.textSecondaryColor(sheetContext);
        final danger =
            isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

        Widget action({
          required IconData icon,
          required String label,
          required VoidCallback onTap,
          String? lockedReason,
          bool destructive = false,
        }) {
          final locked = lockedReason != null;
          final color = locked
              ? muted
              : destructive
                  ? danger
                  : ThemeHelpers.textColor(sheetContext);
          return InkWell(
            onTap: locked
                ? null
                : () {
                    Navigator.of(sheetContext).pop();
                    onTap();
                  },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 20, color: color),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                        if (locked) ...[
                          const SizedBox(height: 2),
                          Text(
                            lockedReason,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: muted,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (locked)
                    Icon(Icons.lock_outline_rounded, size: 16, color: muted),
                ],
              ),
            ),
          );
        }

        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.88,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: ThemeHelpers.cardBackgroundColor(sheetContext),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Fechar',
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: Icon(Icons.close_rounded, color: muted),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    height: 1,
                    color: ThemeHelpers.borderLightColor(sheetContext),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          action(
                            icon: Icons.visibility_outlined,
                            label: 'Visualizar',
                            onTap: () => _openDocument(document),
                          ),
                          action(
                            icon: Icons.download_rounded,
                            label: 'Baixar',
                            lockedReason: DocumentPermissions.canDownload
                                ? null
                                : 'Você não tem permissão para fazer '
                                    'download de documentos',
                            onTap: () => DocumentFileActions.download(
                              context,
                              document.fileUrl,
                              document.originalName,
                            ),
                          ),
                          action(
                            icon: Icons.edit_outlined,
                            label: 'Editar',
                            lockedReason: deleted
                                ? kPropertyDeletedReadOnlyReason
                                : DocumentPermissions.canUpdate
                                    ? null
                                    : 'Você não tem permissão para editar '
                                        'documentos',
                            onTap: () {
                              Navigator.of(context)
                                  .pushNamed(
                                    AppRoutes.documentEdit(document.id),
                                  )
                                  .then((_) {
                                if (mounted) _loadDocuments();
                              });
                            },
                          ),
                          action(
                            icon: Icons.delete_outline_rounded,
                            label: 'Excluir',
                            destructive: true,
                            lockedReason: deleted
                                ? kPropertyDeletedReadOnlyReason
                                : DocumentPermissions.canDelete
                                    ? null
                                    : 'Você não tem permissão para excluir '
                                        'documentos',
                            onTap: () => _confirmDeleteDocument(document),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// "Excluir documento" — texto do modal do web; Cancelar neutro e
  /// Excluir vermelho de texto branco.
  Future<void> _confirmDeleteDocument(Document document) async {
    final name = (document.title ?? '').trim().isNotEmpty
        ? document.title!.trim()
        : document.originalName;
    final danger = Theme.of(context).brightness == Brightness.dark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ThemeHelpers.cardBackgroundColor(ctx),
        title: const Text('Excluir documento'),
        content: SingleChildScrollView(
          child: Text(
            'Tem certeza que deseja excluir este documento?\n\n"$name"',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: ThemeHelpers.textSecondaryColor(ctx),
            ),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final res = await _documentService.deleteDocuments([document.id]);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res.success
              ? 'Documento excluído com sucesso!'
              : (res.message ?? 'Erro ao excluir documento'),
        ),
        backgroundColor:
            res.success ? AppColors.status.success : AppColors.status.error,
      ),
    );
    if (res.success) _loadDocuments();
  }

  /// Localização com MAPA REAL (paridade `PropertyMap` do web): tiles CARTO
  /// claro/escuro sobre dados OpenStreetMap — grátis, sem chave de API — com
  /// pin da marca e zoom de rua. O mapa aqui é vitrine (interações
  /// desligadas): o tap inteiro abre o Google Maps externo.
  Widget _buildMapSection(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    // Azul de mapa/navegação — mesma família do "Abrir no Maps".
    const mapsBlue = Color(0xFF3B82F6);
    final coords = _propertyCoords(property);

    final street = [property.street, property.number]
        .where((s) => s.trim().isNotEmpty)
        .join(', ');
    final complement = property.complement?.trim() ?? '';
    final addressLine = property.address.trim().isNotEmpty
        ? property.address.trim()
        : (complement.isNotEmpty && street.isNotEmpty
            ? '$street — $complement'
            : street);
    final cityLine = [property.city, property.state]
        .where((s) => s.trim().isNotEmpty)
        .join(' – ');

    final infoRows = <Widget>[
      if (addressLine.isNotEmpty)
        _buildLocationInfoRow(
          theme,
          Icons.place_rounded,
          'ENDEREÇO',
          addressLine,
          mapsBlue,
          // Tap-para-copiar na linha principal — mesmo padrão do telefone
          // do lead no CRM.
          onTap: () => _copyPropertyAddress(property),
        ),
      if (property.neighborhood.trim().isNotEmpty)
        _buildLocationInfoRow(
          theme,
          Icons.holiday_village_outlined,
          'BAIRRO',
          property.neighborhood.trim(),
          mapsBlue,
        ),
      if (cityLine.isNotEmpty)
        _buildLocationInfoRow(
          theme,
          Icons.location_city_rounded,
          'CIDADE',
          cityLine,
          mapsBlue,
        ),
      if (property.zipCode.trim().isNotEmpty)
        _buildLocationInfoRow(
          theme,
          Icons.markunread_mailbox_outlined,
          'CEP',
          property.zipCode.trim(),
          mapsBlue,
        ),
    ];

    Widget mapBlock;
    if (coords != null) {
      mapBlock = Container(
        height: 200,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: coords,
                initialZoom: 16,
                backgroundColor: isDark
                    ? const Color(0xFF11151F)
                    : const Color(0xFFE9ECF3),
                // Vitrine, não navegação — arrastar/zoom desligados.
                interactionOptions:
                    const InteractionOptions(flags: InteractiveFlag.none),
              ),
              children: [
                TileLayer(
                  // Mesmos tiles do web (leafletSetup): CARTO Positron no
                  // claro, Dark Matter no escuro — OSM cru não tem par dark.
                  urlTemplate: isDark
                      ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                      : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  maxZoom: 20,
                  userAgentPackageName: 'com.dreamkeys.corretor',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: coords,
                      width: 44,
                      height: 44,
                      // Ponta do pin exatamente sobre a coordenada.
                      alignment: Alignment.topCenter,
                      child: Icon(
                        Icons.location_on,
                        size: 40,
                        // Pin na cor da MARCA (vermelho aqui é marca, não
                        // erro) — paridade com o ModernPin do web.
                        color: isDark
                            ? AppColors.primary.primaryDarkMode
                            : AppColors.primary.primary,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            // Atribuição OSM/CARTO (obrigatória no uso dos tiles) — discreta.
            Positioned(
              right: 6,
              bottom: 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: (isDark ? Colors.black : Colors.white)
                      .withValues(alpha: 0.55),
                ),
                child: Text(
                  '© OpenStreetMap · CARTO',
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
              ),
            ),
            // Tap em qualquer ponto do mapa → Google Maps externo.
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _openInExternalMaps(property),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      // Sem coordenadas — placeholder digno com saída útil (nunca a seção
      // vazia/só texto).
      mapBlock = Container(
        height: 160,
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.background.backgroundSecondaryDarkMode
              : AppColors.background.backgroundSecondary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.map_outlined,
              size: 30,
              color: muted.withValues(alpha: 0.8),
            ),
            const SizedBox(height: 8),
            Text(
              'Sem coordenadas cadastradas',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: ThemeHelpers.textColor(context),
              ),
            ),
            const SizedBox(height: 3),
            // A ação vive no par de botões logo abaixo — aqui só a dica de
            // que o Maps abre pelo endereço cadastrado (sem duplicar botão).
            Text(
              'O Maps abre pelo endereço cadastrado',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: muted.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      );
    }

    final canCopyAddress = _fullAddressText(property).isNotEmpty;
    final children = <Widget>[mapBlock];
    // Par de ações pareadas sob o mapa — a âncora de ações da seção: mesma
    // largura, mesma altura, mesma voz visual (pill outline azul). O header
    // fica limpo (só barrinha + título).
    if (canCopyAddress || coords != null) {
      children.add(const SizedBox(height: 10));
      children.add(
        Row(
          children: [
            if (canCopyAddress) ...[
              Expanded(
                child: _buildLocationActionButton(
                  Icons.copy_rounded,
                  'Copiar endereço',
                  () => _copyPropertyAddress(property),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: _buildLocationActionButton(
                Icons.map_rounded,
                'Abrir no Maps',
                () => _openInExternalMaps(property),
              ),
            ),
          ],
        ),
      );
    }
    if (infoRows.isNotEmpty) {
      children.add(const SizedBox(height: 14));
      for (var i = 0; i < infoRows.length; i++) {
        if (i > 0) children.add(const SizedBox(height: 10));
        children.add(infoRows[i]);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  /// Coordenadas válidas do imóvel — mesma validação do `parseLatLng` do web
  /// (faixa geográfica), mais o descarte do (0,0) de cadastro sujo.
  LatLng? _propertyCoords(Property property) {
    final lat = property.latitude;
    final lng = property.longitude;
    if (lat == null || lng == null) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    if (lat == 0 && lng == 0) return null;
    return LatLng(lat, lng);
  }

  /// Google Maps externo — coordenadas quando existem, senão o endereço
  /// completo (mesmo `openMaps` que o resto da casa usa).
  Future<void> _openInExternalMaps(Property property) async {
    final coords = _propertyCoords(property);
    if (coords != null) {
      await BrokerContactActions.openMaps(
        context,
        '${coords.latitude},${coords.longitude}',
      );
      return;
    }
    final query = [
      property.address.trim().isNotEmpty
          ? property.address.trim()
          : [property.street, property.number]
              .where((s) => s.trim().isNotEmpty)
              .join(', '),
      property.neighborhood,
      property.city,
      property.state,
      property.zipCode,
    ].where((s) => s.trim().isNotEmpty).join(', ');
    await BrokerContactActions.openMaps(context, query);
  }

  /// Endereço completo legível — os mesmos campos que a seção Localização
  /// exibe, unidos por ', ' pulando vazios. Ex.: "Rua das Acácias, 123,
  /// Palmital, Marília, 17500-000".
  String _fullAddressText(Property property) {
    final street = [property.street, property.number]
        .where((s) => s.trim().isNotEmpty)
        .join(', ');
    final base =
        property.address.trim().isNotEmpty ? property.address.trim() : street;
    return [
      base,
      property.complement?.trim() ?? '',
      property.neighborhood,
      property.city,
      property.state,
      property.zipCode,
    ].map((s) => s.trim()).where((s) => s.isNotEmpty).join(', ');
  }

  /// Copia o endereço completo — clipboard + haptic + snack curto.
  Future<void> _copyPropertyAddress(Property property) async {
    final text = _fullAddressText(property);
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.selectionClick();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Endereço copiado'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Botão do par de ações da Localização — pill outline AZUL (o tema
  /// global pinta botões de vermelho por default), voz visual única pros
  /// dois lados do par. Label em FittedBox: nunca clipa, nem em 320dp.
  Widget _buildLocationActionButton(
    IconData icon,
    String label,
    VoidCallback onPressed,
  ) {
    const mapsBlue = Color(0xFF3B82F6);
    return SizedBox(
      height: 40,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: mapsBlue,
          side: BorderSide(color: mapsBlue.withValues(alpha: 0.45)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        icon: Icon(icon, size: 16),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ),
    );
  }

  /// Linha informativa de endereço — roundel azul pequeno (28) + rótulo
  /// small caps + valor. Flush: o dado direto na página, sem caixa.
  Widget _buildLocationInfoRow(
    ThemeData theme,
    IconData icon,
    String label,
    String value,
    Color tone, {
    VoidCallback? onTap,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            color: tone.withValues(alpha: isDark ? 0.18 : 0.12),
            border: Border.all(
              color: tone.withValues(alpha: isDark ? 0.34 : 0.22),
            ),
          ),
          child: Icon(icon, size: 15, color: tone),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 9.5,
                  letterSpacing: 1.3,
                  fontWeight: FontWeight.w800,
                  color: muted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                  height: 1.3,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
            ],
          ),
        ),
        // Affordance de cópia — o usuário precisa VER que a linha é
        // copiável (padrão do _LeadContactRow do CRM).
        if (onTap != null) ...[
          const SizedBox(width: 8),
          Icon(
            Icons.copy_rounded,
            size: 14,
            color: muted.withValues(alpha: 0.8),
          ),
        ],
      ],
    );
    if (onTap == null) return row;
    // Tap-para-copiar (padrão do telefone do lead no CRM) — splash suave
    // sem tirar a linha do layout flush.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: row,
      ),
    );
  }

  Widget _buildFeaturesSection(
    BuildContext context,
    ThemeData theme,
    List<String> features,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    // Verde da identidade do imóvel (mais vivo) — chip refinado, nada do
    // Chip nativo sem estilo.
    final green = isDark ? const Color(0xFF34D399) : const Color(0xFF10B981);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: features.map((feature) {
        return Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 13, 8),
          decoration: BoxDecoration(
            color: green.withValues(alpha: isDark ? 0.14 : 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: green.withValues(alpha: isDark ? 0.40 : 0.28),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_getFeatureIcon(feature), size: 16, color: green),
              const SizedBox(width: 8),
              Text(
                feature,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  IconData _getFeatureIcon(String feature) {
    // Mapeamento básico de ícones para recursos
    final iconMap = {
      'Ar condicionado': Icons.ac_unit,
      'Aquecimento': Icons.whatshot,
      'Elevador': Icons.elevator,
      'Portaria 24h': Icons.security,
      'Segurança 24h': Icons.shield,
      'Piscina': Icons.pool,
      'Academia': Icons.fitness_center,
      'Playground': Icons.child_care,
      'Churrasqueira': Icons.outdoor_grill,
      'Área gourmet': Icons.restaurant,
      'Jardim': Icons.local_florist,
      'Terraço': Icons.roofing,
      'Varanda': Icons.balcony,
      'Sacada': Icons.balcony,
      'Garagem coberta': Icons.garage,
      'Garagem descoberta': Icons.drive_eta,
      'Depósito': Icons.inventory_2,
      'Lavanderia': Icons.local_laundry_service,
      'Closet': Icons.checkroom,
      'Home office': Icons.work,
      'Lareira': Icons.fireplace,
      'Sistema de alarme': Icons.alarm,
      'Câmeras de segurança': Icons.videocam,
      'Internet': Icons.wifi,
      'Gás encanado': Icons.local_gas_station,
      'Água quente': Icons.water_drop,
      'Energia solar': Icons.solar_power,
      'Mobiliado': Icons.chair,
      'Semi-mobiliado': Icons.chair_outlined,
      'Pronto para morar': Icons.home,
      'Novo': Icons.new_releases,
    };

    return iconMap[feature] ?? Icons.check_circle_outline;
  }

  Future<void> _showLinkClientModal(
    BuildContext context,
    Property property,
  ) async {
    final selectedClientIdRef = <String?>[null];
    final selectedClientNameRef = <String?>[null];
    final notesController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: ThemeHelpers.textSecondaryColor(context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Header
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Vincular cliente',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context, false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Client Selector
                  EntitySelector(
                    type: 'client',
                    selectedId: selectedClientIdRef[0],
                    selectedName: selectedClientNameRef[0],
                    onSelected: (id, name) {
                      setModalState(() {
                        selectedClientIdRef[0] = id;
                        selectedClientNameRef[0] = name;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  // Notes (optional)
                  TextFormField(
                    controller: notesController,
                    decoration: const InputDecoration(
                      labelText: 'Observações (opcional)',
                      hintText:
                          'Adicione observações sobre o interesse do cliente',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                    maxLength: 500,
                  ),
                  const SizedBox(height: 24),
                  // Buttons (full width)
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (formKey.currentState!.validate()) {
                              if (selectedClientIdRef[0] == null ||
                                  selectedClientNameRef[0] == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                      'Por favor, selecione um cliente',
                                    ),
                                    backgroundColor: AppColors.status.error,
                                  ),
                                );
                                return;
                              }
                              Navigator.pop(context, true);
                            }
                          },
                          icon: const Icon(Icons.link),
                          label: const Text('Vincular cliente'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.status.success,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context, false);
                          },
                          icon: const Icon(Icons.close),
                          label: const Text('Cancelar'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor:
                                ThemeHelpers.textSecondaryColor(context),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // Usar try-finally para garantir que o controller seja sempre descartado
    try {
      if (result != true || selectedClientIdRef[0] == null) {
        return;
      }

      // Capturar o texto antes de usar
      final notes = notesController.text.trim().isEmpty
          ? null
          : notesController.text.trim();

      // Associar cliente à propriedade

      final response = await _clientService.associateClientToProperty(
        selectedClientIdRef[0]!,
        property.id,
        // Mesmo padrão do web (`usePropertyClients`): vínculo nasce como
        // "Interessado".
        interestType: 'interested',
        notes: notes,
      );

      if (mounted) {
        if (response.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Cliente vinculado com sucesso'),
              backgroundColor: AppColors.status.success,
            ),
          );
          // Recarregar propriedade para atualizar lista de clientes
          _refreshAfterChange();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao vincular cliente'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    } finally {
      // Sempre descartar o controller no final
      notesController.dispose();
    }
  }

  Future<void> _showCreateKeyModal(
    BuildContext context,
    Property property,
  ) async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final locationController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final keyTypeRef = <String>['main'];
    final keyTypes = [
      {'value': 'main', 'label': 'Principal'},
      {'value': 'backup', 'label': 'Reserva'},
      {'value': 'emergency', 'label': 'Emergência'},
      {'value': 'garage', 'label': 'Garagem'},
      {'value': 'mailbox', 'label': 'Caixa de Correio'},
      {'value': 'other', 'label': 'Outra'},
    ];

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: ThemeHelpers.textSecondaryColor(context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Criar Chave',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context, false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nome da Chave *',
                      hintText: 'Ex: Chave Principal',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Nome é obrigatório';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Tipo *',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: keyTypes.map((type) {
                      final isSelected = keyTypeRef[0] == type['value'];
                      return ChoiceChip(
                        label: Text(type['label']!),
                        selected: isSelected,
                        onSelected: (selected) {
                          setModalState(() {
                            keyTypeRef[0] = type['value']!;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: locationController,
                    decoration: const InputDecoration(
                      labelText: 'Localização',
                      hintText: 'Ex: Escritório',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Descrição',
                      hintText: 'Informações adicionais sobre a chave',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 24),
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (formKey.currentState!.validate()) {
                              Navigator.pop(context, true);
                            }
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Criar Chave'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context, false),
                          icon: const Icon(Icons.close),
                          label: const Text('Cancelar'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      if (result != true) {
        nameController.dispose();
        descriptionController.dispose();
        locationController.dispose();
        return;
      }

      final dto = key_models.CreateKeyDto(
        name: nameController.text.trim(),
        propertyId: property.id,
        type: keyTypeRef[0],
        status: 'available',
        location: locationController.text.trim().isNotEmpty
            ? locationController.text.trim()
            : null,
        description: descriptionController.text.trim().isNotEmpty
            ? descriptionController.text.trim()
            : null,
      );

      final response = await _keyService.createKey(dto);

      if (mounted) {
        if (response.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Chave criada com sucesso'),
              backgroundColor: AppColors.status.success,
            ),
          );
          _loadKeys();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao criar chave'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    } finally {
      nameController.dispose();
      descriptionController.dispose();
      locationController.dispose();
    }
  }

  Future<void> _showCreateExpenseModal(
    BuildContext context,
    Property property,
  ) async {
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    final dueDateController = TextEditingController();
    final descriptionController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final expenseTypeRef = <String>['other'];
    final expenseTypes = [
      {'value': 'iptu', 'label': 'IPTU'},
      {'value': 'condominium', 'label': 'Condomínio'},
      {'value': 'insurance', 'label': 'Seguro'},
      {'value': 'maintenance', 'label': 'Manutenção'},
      {'value': 'utilities', 'label': 'Utilidades'},
      {'value': 'other', 'label': 'Outro'},
    ];

    DateTime? selectedDueDate;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: ThemeHelpers.textSecondaryColor(context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Adicionar Despesa',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context, false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Título *',
                      hintText: 'Ex: IPTU 2024',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Título é obrigatório';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Tipo *',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: expenseTypes.map((type) {
                      final isSelected = expenseTypeRef[0] == type['value'];
                      return ChoiceChip(
                        label: Text(type['label']!),
                        selected: isSelected,
                        onSelected: (selected) {
                          setModalState(() {
                            expenseTypeRef[0] = type['value']!;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: amountController,
                    decoration: const InputDecoration(
                      labelText: 'Valor (R\$) *',
                      hintText: '0,00',
                      border: OutlineInputBorder(),
                      prefixText: 'R\$ ',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Valor é obrigatório';
                      }
                      final amount = double.tryParse(
                        value.replaceAll(',', '.'),
                      );
                      if (amount == null || amount <= 0) {
                        return 'Valor inválido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: dueDateController,
                    decoration: const InputDecoration(
                      labelText: 'Data de Vencimento *',
                      hintText: 'DD/MM/AAAA',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                    readOnly: true,
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(
                          const Duration(days: 3650),
                        ),
                      );
                      if (date != null) {
                        setModalState(() {
                          selectedDueDate = date;
                          dueDateController.text = DateFormat(
                            'dd/MM/yyyy',
                          ).format(date);
                        });
                      }
                    },
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Data de vencimento é obrigatória';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Descrição',
                      hintText: 'Informações adicionais',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 24),
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (formKey.currentState!.validate()) {
                              Navigator.pop(context, true);
                            }
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Adicionar Despesa'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context, false),
                          icon: const Icon(Icons.close),
                          label: const Text('Cancelar'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      if (result != true || selectedDueDate == null) {
        titleController.dispose();
        amountController.dispose();
        dueDateController.dispose();
        descriptionController.dispose();
        return;
      }

      final amount = double.parse(amountController.text.replaceAll(',', '.'));

      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConstants.propertyExpenses(property.id),
        body: {
          'title': titleController.text.trim(),
          'type': expenseTypeRef[0],
          'amount': amount,
          'dueDate': selectedDueDate!.toIso8601String(),
          'status': 'pending',
          if (descriptionController.text.trim().isNotEmpty)
            'description': descriptionController.text.trim(),
        },
      );

      if (mounted) {
        if (response.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Despesa adicionada com sucesso'),
              backgroundColor: AppColors.status.success,
            ),
          );
          _loadExpenses();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao adicionar despesa'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    } finally {
      titleController.dispose();
      amountController.dispose();
      dueDateController.dispose();
      descriptionController.dispose();
    }
  }

  Future<void> _showCreateChecklistModal(
    BuildContext context,
    Property property,
  ) async {
    final clientIdController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final checklistTypeRef = <String>['sale'];
    final checklistTypes = [
      {'value': 'sale', 'label': 'Venda'},
      {'value': 'rental', 'label': 'Aluguel'},
    ];

    final selectedClientIdRef = <String?>[null];
    final selectedClientNameRef = <String?>[null];

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: ThemeHelpers.textSecondaryColor(context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Criar Checklist',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context, false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Tipo *',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: checklistTypes.map((type) {
                      final isSelected = checklistTypeRef[0] == type['value'];
                      return ChoiceChip(
                        label: Text(type['label']!),
                        selected: isSelected,
                        onSelected: (selected) {
                          setModalState(() {
                            checklistTypeRef[0] = type['value']!;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Cliente *',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  EntitySelector(
                    type: 'client',
                    selectedId: selectedClientIdRef[0],
                    selectedName: selectedClientNameRef[0],
                    onSelected: (id, name) {
                      setModalState(() {
                        selectedClientIdRef[0] = id;
                        selectedClientNameRef[0] = name;
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (selectedClientIdRef[0] == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                    'Por favor, selecione um cliente',
                                  ),
                                  backgroundColor: AppColors.status.error,
                                ),
                              );
                              return;
                            }
                            Navigator.pop(context, true);
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Criar Checklist'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context, false),
                          icon: const Icon(Icons.close),
                          label: const Text('Cancelar'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      if (result != true || selectedClientIdRef[0] == null) {
        clientIdController.dispose();
        return;
      }

      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConstants.saleChecklists,
        body: {
          'propertyId': property.id,
          'clientId': selectedClientIdRef[0]!,
          'type': checklistTypeRef[0],
          'status': 'pending',
        },
      );

      if (mounted) {
        if (response.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Checklist criado com sucesso'),
              backgroundColor: AppColors.status.success,
            ),
          );
          _loadChecklists();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao criar checklist'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    } finally {
      clientIdController.dispose();
    }
  }

  Future<void> _markExpenseAsPaid(
    BuildContext context,
    String propertyId,
    String expenseId,
  ) async {
    try {
      final response = await _apiService.put<Map<String, dynamic>>(
        ApiConstants.propertyExpenseMarkAsPaid(propertyId, expenseId),
        body: {'paidDate': DateTime.now().toIso8601String()},
      );

      if (mounted) {
        if (response.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Despesa marcada como paga'),
              backgroundColor: AppColors.status.success,
            ),
          );
          _loadExpenses();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                response.message ?? 'Erro ao marcar despesa como paga',
              ),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    }
  }

  Future<void> _showEditExpenseModal(
    BuildContext context,
    Property property,
    Map<String, dynamic> expense,
  ) async {
    // Por enquanto, apenas mostra mensagem
    // TODO: Implementar modal de edição completo
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Edição de despesa será implementada em breve'),
        backgroundColor: AppColors.status.info,
      ),
    );
  }

  Future<void> _deleteExpense(
    BuildContext context,
    String propertyId,
    String expenseId,
    String expenseTitle,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.status.error),
            const SizedBox(width: 12),
            const Expanded(child: Text('Confirmar Exclusão')),
          ],
        ),
        content: Text(
          'Tem certeza que deseja excluir a despesa "$expenseTitle"? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.status.error,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await _apiService.delete<dynamic>(
        ApiConstants.propertyExpenseById(propertyId, expenseId),
      );

      if (mounted) {
        if (response.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Despesa excluída com sucesso'),
              backgroundColor: AppColors.status.success,
            ),
          );
          _loadExpenses();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao excluir despesa'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    }
  }


  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ FAB â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildScrollTopButton(BuildContext context, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _detailsScrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
        ),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.45),
                blurRadius: 18,
                offset: const Offset(0, 8),
                spreadRadius: -2,
              ),
            ],
          ),
          child: const Icon(
            Icons.keyboard_arrow_up_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }
}

/// Visualizador fullscreen — paridade com `imobx-front/PropertyGalleryFullscreenPage`.
///
/// - **`BoxFit.contain`**: a imagem é mostrada nas suas dimensões reais
///   (com letterbox em volta). Isso permite ao avaliador ver se a foto é
///   quadrada/retangular antes de aprovar — `cover` cortava as bordas e
///   escondia desproporções.
/// - **Pinch + double-tap zoom** via `InteractiveViewer` (até 5x).
/// - **Pill de metadados** (categoria + dimensões + ratio + badge "QUADRADA"
///   ou "NÃO QUADRADA") — ajuda o avaliador a decidir rapidamente.
/// - **Botão de excluir** disponível para usuários com permissão
///   `propertyApprovePublication`/`propertyApproveAvailability` ou roles
///   master/admin. Confirmação obrigatória antes do delete.
/// - Retorna `true` no pop quando alguma imagem foi deletada — a página
///   pai usa isso pra recarregar o property.
class _FullscreenGallery extends StatefulWidget {
  const _FullscreenGallery({
    required this.images,
    required this.initialIndex,
    required this.propertyId,
    this.canDelete = false,
    this.canSetMain = false,
  });

  final List<PropertyImage> images;
  final int initialIndex;
  final String propertyId;
  final bool canDelete;
  final bool canSetMain;

  @override
  State<_FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends State<_FullscreenGallery> {
  late final PageController _controller;
  late List<PropertyImage> _images;
  late int _index;
  bool _didMutate = false;
  bool _deleting = false;
  bool _settingMain = false;

  /// Cache de dimensões reais (decodificadas) por url. Evita resolver de
  /// novo a cada rebuild e permite mostrar o ratio na barra inferior.
  final Map<String, Size> _resolvedSizes = {};

  @override
  void initState() {
    super.initState();
    _images = List.of(widget.images);
    _index = widget.initialIndex.clamp(0, _images.length - 1);
    _controller = PageController(initialPage: _index);
    _resolveSizeFor(_currentImage);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  PropertyImage? get _currentImage =>
      (_images.isEmpty || _index < 0 || _index >= _images.length)
          ? null
          : _images[_index];

  /// Resolve dimensões reais via `Image.image.resolve(...)` — apenas uma
  /// vez por URL. Útil pro badge "QUADRADA"/"NÃO QUADRADA" e pra mostrar
  /// "1920×1080" na pill inferior.
  void _resolveSizeFor(PropertyImage? img) {
    if (img == null) return;
    if (_resolvedSizes.containsKey(img.url)) return;
    final provider = NetworkImage(img.url);
    final stream = provider.resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!mounted) return;
        setState(() {
          _resolvedSizes[img.url] = Size(
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          );
        });
        stream.removeListener(listener);
      },
      onError: (_, __) {
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
  }

  bool _isApproximatelySquare(Size size) {
    if (size.width == 0 || size.height == 0) return false;
    final ratio = size.width / size.height;
    // Toleramos ±2% pra absorver compressões e arredondamentos JPEG.
    return (ratio - 1.0).abs() <= 0.02;
  }

  String _categoryLabel(String? raw) {
    if (raw == null || raw.isEmpty) return 'Geral';
    switch (raw.toLowerCase()) {
      case 'general':
        return 'Geral';
      case 'living_room':
      case 'sala':
        return 'Sala';
      case 'kitchen':
      case 'cozinha':
        return 'Cozinha';
      case 'bedroom':
      case 'quarto':
        return 'Quarto';
      case 'bathroom':
      case 'banheiro':
        return 'Banheiro';
      case 'facade':
      case 'fachada':
        return 'Fachada';
      case 'plant':
      case 'planta':
        return 'Planta';
      case 'leisure':
      case 'lazer':
        return 'Lazer';
      default:
        return raw[0].toUpperCase() + raw.substring(1);
    }
  }

  /// Define a foto atual como principal. Sem confirmação por modal — a ação
  /// é reversível (basta marcar outra) e o feedback fica no snackbar.
  Future<void> _setCurrentAsMain() async {
    if (!widget.canSetMain || _settingMain) return;
    final img = _currentImage;
    if (img == null || img.id.isEmpty) return;
    if (img.isMain) return;

    setState(() => _settingMain = true);

    final res = await GalleryService.instance.setMainImage(img.id);

    if (!mounted) return;

    if (!res.success) {
      setState(() => _settingMain = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.status.error,
          behavior: SnackBarBehavior.floating,
          content: Text(
            res.message ?? 'Não foi possível definir a foto principal.',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
      return;
    }

    // Atualiza local: a nova vira principal e todas as outras saem como
    // principal. Espelha o comportamento do backend (single-main).
    setState(() {
      _images = _images
          .map(
            (e) => PropertyImage(
              id: e.id,
              url: e.url,
              thumbnailUrl: e.thumbnailUrl,
              category: e.category,
              isMain: e.id == img.id,
              createdAt: e.createdAt,
            ),
          )
          .toList();
      _didMutate = true;
      _settingMain = false;
    });

    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFFE0AA3E),
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            Icon(Icons.star_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Foto principal atualizada.',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndDelete() async {
    if (!widget.canDelete || _deleting) return;
    final img = _currentImage;
    if (img == null || img.id.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: const Text(
          'Excluir esta foto?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          img.isMain
              ? 'Esta é a foto principal. Ao excluir, a próxima imagem assume como principal automaticamente. Esta ação não pode ser desfeita.'
              : 'A imagem será removida do imóvel e do armazenamento. Esta ação não pode ser desfeita.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.78),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white.withValues(alpha: 0.7),
            ),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.status.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _deleting = true);

    final res = await GalleryService.instance.deleteImage(img.id);

    if (!mounted) return;

    if (!res.success) {
      setState(() => _deleting = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.status.error,
          behavior: SnackBarBehavior.floating,
          content: Text(
            res.message ?? 'Não foi possível excluir a imagem.',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
      return;
    }

    setState(() {
      _images.removeAt(_index);
      _didMutate = true;
      if (_images.isEmpty) {
        _index = 0;
      } else if (_index >= _images.length) {
        _index = _images.length - 1;
      }
      _deleting = false;
    });

    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF3FA66B),
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Foto excluída com sucesso.',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );

    if (_images.isEmpty) {
      Navigator.of(context).pop(_didMutate);
      return;
    }

    // Garante que o PageController acompanhe o novo índice
    _controller.jumpToPage(_index);
    _resolveSizeFor(_currentImage);
  }

  @override
  Widget build(BuildContext context) {
    final total = _images.length;
    final current = _currentImage;
    final size = current != null ? _resolvedSizes[current.url] : null;
    final isSquare = size != null && _isApproximatelySquare(size);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // â”€â”€â”€â”€â”€â”€â”€â”€â”€ Imagem em dimensões reais (BoxFit.contain) â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(_didMutate),
                child: PageView.builder(
                  controller: _controller,
                  itemCount: total,
                  onPageChanged: (i) {
                    setState(() => _index = i);
                    _resolveSizeFor(_currentImage);
                  },
                  itemBuilder: (_, i) {
                    return Hero(
                      tag: 'property-image-${widget.propertyId}-$i',
                      child: InteractiveViewer(
                        minScale: 1,
                        maxScale: 5,
                        child: Center(
                          child: ShimmerImage(
                            imageUrl: _images[i].url,
                            // `contain` revela letterbox/pillarbox =
                            // o avaliador percebe imagens não-quadradas
                            // só de olhar.
                            fit: BoxFit.contain,
                            width: double.infinity,
                            height: double.infinity,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // â”€â”€â”€â”€â”€â”€â”€â”€â”€ Top bar (fechar + counter + delete) â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  _GalleryRoundIconButton(
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.of(context).pop(_didMutate),
                  ),
                  const Spacer(),
                  if (total > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        '${_index + 1} / $total',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          height: 1,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  if (widget.canSetMain && current != null) ...[
                    const SizedBox(width: 10),
                    _GalleryRoundIconButton(
                      // Amarelo "principal": estrela cheia quando já é a
                      // principal (somente leitura), contorno quando tap.
                      icon: current.isMain
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      onTap: current.isMain ? null : _setCurrentAsMain,
                      tint: const Color(0xFFE0AA3E),
                      busy: _settingMain,
                      filled: current.isMain,
                      tooltip: current.isMain
                          ? 'Já é a foto principal'
                          : 'Definir como foto principal',
                    ),
                  ],
                  if (widget.canDelete && current != null) ...[
                    const SizedBox(width: 10),
                    _GalleryRoundIconButton(
                      icon: Icons.delete_outline_rounded,
                      onTap: _confirmAndDelete,
                      // Vermelho semitransparente — "destrutivo" sem
                      // berrar como vermelho puro num fundo preto.
                      tint: AppColors.status.error,
                      busy: _deleting,
                    ),
                  ],
                ],
              ),
            ),

            // â”€â”€â”€â”€â”€â”€â”€â”€â”€ Badge de proporção (NÃO QUADRADA) â”€â”€â”€â”€â”€â”€â”€â”€â”€
            // Aparece só quando temos as dimensões e a foto NÃO é quadrada.
            // Quadrada não recebe badge — evita ruído visual.
            if (size != null && !isSquare)
              Positioned(
                top: 60,
                right: 16,
                child: _RatioWarningBadge(),
              ),

            // â”€â”€â”€â”€â”€â”€â”€â”€â”€ Pill de metadados (bottom) â”€â”€â”€â”€â”€â”€â”€â”€â”€
            if (current != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: total > 1 ? 60 : 26,
                child: _MetaPill(
                  category: _categoryLabel(current.category),
                  size: size,
                  isSquare: size != null ? isSquare : null,
                  isMain: current.isMain,
                ),
              ),

            // â”€â”€â”€â”€â”€â”€â”€â”€â”€ Dots (paginação) â”€â”€â”€â”€â”€â”€â”€â”€â”€
            if (total > 1)
              Positioned(
                left: 0,
                right: 0,
                bottom: 26,
                child: Center(
                  child: Wrap(
                    spacing: 6,
                    children: List.generate(total, (i) {
                      final active = i == _index;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: active ? 22 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: active
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pill com metadados (categoria + dimensões + ratio + foto principal).
///
/// Renderiza tudo em uma linha só — fluido. Os "chips" internos têm cores
/// distintas por função: categoria neutra, dimensões accent-cinza, ratio
/// verde se quadrada/cinza se desconhecido, "PRINCIPAL" amarelo.
class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.category,
    required this.size,
    required this.isSquare,
    required this.isMain,
  });

  final String category;
  final Size? size;
  final bool? isSquare;
  final bool isMain;

  @override
  Widget build(BuildContext context) {
    final w = size?.width.toInt();
    final h = size?.height.toInt();
    final dimsLabel = (w != null && h != null) ? '$w × $h' : null;
    String? ratioLabel;
    if (size != null && size!.height > 0) {
      final r = size!.width / size!.height;
      ratioLabel = '${r.toStringAsFixed(2)}:1';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _MetaChip(
            icon: Icons.category_outlined,
            label: category,
          ),
          if (dimsLabel != null)
            _MetaChip(
              icon: Icons.aspect_ratio_rounded,
              label: dimsLabel,
            ),
          if (ratioLabel != null)
            _MetaChip(
              icon: isSquare == true
                  ? Icons.crop_square_rounded
                  : Icons.crop_landscape_rounded,
              label: ratioLabel,
              tint: isSquare == true
                  ? const Color(0xFF3FA66B)
                  : const Color(0xFFE0AA3E),
            ),
          if (isMain)
            const _MetaChip(
              icon: Icons.star_rounded,
              label: 'PRINCIPAL',
              tint: Color(0xFFE0AA3E),
              emphasized: true,
            ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    this.tint,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final Color? tint;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final c = tint ?? Colors.white.withValues(alpha: 0.85);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: emphasized
            ? c.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: c,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: emphasized ? 1.2 : 0.2,
              height: 1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge "NÃO QUADRADA" — chama atenção pro avaliador no canto superior
/// direito quando a imagem foge da proporção quadrada (regra prioritária
/// pedida pelo time de aprovação).
class _RatioWarningBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFE0AA3E).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE0AA3E)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 14,
            color: Color(0xFFE0AA3E),
          ),
          SizedBox(width: 6),
          Text(
            'NÃO QUADRADA',
            style: TextStyle(
              color: Color(0xFFE0AA3E),
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _GalleryRoundIconButton extends StatelessWidget {
  const _GalleryRoundIconButton({
    required this.icon,
    required this.onTap,
    this.tint,
    this.busy = false,
    this.filled = false,
    this.tooltip,
  });

  final IconData icon;

  /// `null` desabilita o tap (estado "somente leitura" — usado, por
  /// exemplo, na estrela quando a foto JÁ é a principal).
  final VoidCallback? onTap;

  /// Cor de destaque opcional (usada na ação destrutiva de excluir).
  /// Quando setada, o botão herda essa cor no fundo (com alpha) e na borda.
  final Color? tint;

  /// Quando `true`, mostra spinner em lugar do ícone e desabilita o tap.
  final bool busy;

  /// Quando `true`, pinta o botão sólido na cor `tint` — usado para o
  /// estado "ativo" (ex.: estrela cheia indicando foto principal).
  final bool filled;

  /// Texto opcional do `Tooltip` (long-press).
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final hasTint = tint != null;
    Color fg;
    Color bg;
    Color borderColor;

    if (filled && hasTint) {
      fg = Colors.white;
      bg = tint!;
      borderColor = tint!;
    } else if (hasTint) {
      fg = tint!;
      bg = tint!.withValues(alpha: 0.18);
      borderColor = tint!.withValues(alpha: 0.6);
    } else {
      fg = Colors.white;
      bg = Colors.black.withValues(alpha: 0.55);
      borderColor = Colors.white.withValues(alpha: 0.18);
    }

    final disabled = onTap == null || busy;

    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: Border.all(color: borderColor),
            boxShadow: filled
                ? [
                    BoxShadow(
                      color: (tint ?? Colors.black).withValues(alpha: 0.36),
                      blurRadius: 14,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: busy
              ? Padding(
                  padding: const EdgeInsets.all(11),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: fg,
                  ),
                )
              : Icon(icon, color: fg, size: 22),
        ),
      ),
    );

    if (tooltip != null && tooltip!.isNotEmpty) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

/// Descrição editorial expansível.
///
/// Comportamento:
/// - **Recolhida**: mostra ~5 linhas; quando o texto extrapola, aplica
///   um `ShaderMask` com gradient fade no rodapé indicando que tem mais
///   conteúdo, e exibe o botão "Ver mais".
/// - **Expandida**: texto completo + botão "Ver menos".
/// - **Vazia**: mensagem discreta em itálico, sem qualquer caixa.
///
/// A detecção de "extrapolou as 5 linhas" é feita via `TextPainter.didExceedMaxLines`
/// no `LayoutBuilder` — assim o botão só aparece se realmente o texto
/// for longo o suficiente para ser truncado.
class _ExpandableDescription extends StatefulWidget {
  const _ExpandableDescription({required this.text});

  final String text;

  static const int _kCollapsedMaxLines = 5;

  @override
  State<_ExpandableDescription> createState() => _ExpandableDescriptionState();
}

class _ExpandableDescriptionState extends State<_ExpandableDescription>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Indigo editorial — mesma voz do BRIEFING do modal do CRM
    // (`_EditorialDescription`), e o tom da própria seção Descrição.
    const accent = Color(0xFF6366F1);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    final cleaned = widget.text.trim();
    final empty = cleaned.isEmpty;

    if (empty) {
      return Padding(
        padding: const EdgeInsets.only(left: 14, top: 4),
        child: Row(
          children: [
            Icon(Icons.short_text_rounded, size: 16, color: secondary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Sem descrição cadastrada. Edite o imóvel para adicionar contexto.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: secondary,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Tipografia editorial da casa (ref.: BRIEFING do task_details_modal):
    // 15px, entrelinha generosa, peso médio.
    final textStyle = theme.textTheme.bodyLarge?.copyWith(
      height: 1.55,
      fontSize: 15,
      letterSpacing: -0.1,
      color: ThemeHelpers.textColor(context),
      fontWeight: FontWeight.w500,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Régua accent fina à esquerda — referência editorial discreta
        Container(
          width: 3,
          margin: const EdgeInsets.only(right: 14),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Mede se o texto extrapola N linhas pra decidir se
              // mostra o botão "Ver mais"/"Ver menos".
              final tp = TextPainter(
                text: TextSpan(text: cleaned, style: textStyle),
                maxLines: _ExpandableDescription._kCollapsedMaxLines,
                textDirection: Directionality.of(context),
              )..layout(maxWidth: constraints.maxWidth);

              final overflow = tp.didExceedMaxLines;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    alignment: Alignment.topLeft,
                    curve: Curves.easeOut,
                    child: _expanded || !overflow
                        ? SelectableText(
                            cleaned,
                            style: textStyle,
                          )
                        : ShaderMask(
                            shaderCallback: (rect) {
                              return LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: const [
                                  Colors.white,
                                  Colors.white,
                                  Colors.transparent,
                                ],
                                stops: const [0.0, 0.7, 1.0],
                              ).createShader(rect);
                            },
                            blendMode: BlendMode.dstIn,
                            child: Text(
                              cleaned,
                              maxLines: _ExpandableDescription._kCollapsedMaxLines,
                              overflow: TextOverflow.clip,
                              style: textStyle,
                            ),
                          ),
                  ),
                  if (overflow) ...[
                    const SizedBox(height: 6),
                    _ExpandToggle(
                      expanded: _expanded,
                      accent: accent,
                      onTap: () {
                        setState(() => _expanded = !_expanded);
                      },
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Botão minimalista de toggle "Ver mais â†“ / Ver menos â†‘".
class _ExpandToggle extends StatelessWidget {
  const _ExpandToggle({
    required this.expanded,
    required this.accent,
    required this.onTap,
  });

  final bool expanded;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: onTap,
        // Tema global pinta TextButton de VERMELHO (armadilha conhecida) —
        // aqui o accent editorial (indigo) é FORÇADO.
        style: TextButton.styleFrom(
          foregroundColor: accent,
          minimumSize: Size.zero,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              expanded ? 'Ver menos' : 'Ver mais',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.1,
              ),
            ),
            const SizedBox(width: 4),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 220),
              child: const Icon(Icons.expand_more_rounded, size: 16),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cor estável por pessoa — mesma mecânica e paleta do `_personColor` do
/// chat do CRM (task_details_modal.dart). Sem nome → slate.
Color _approvalPersonColor(String? name) {
  if (name == null || name.trim().isEmpty) return const Color(0xFF64748B);
  const palette = [
    Color(0xFF0EA5E9),
    Color(0xFF14B8A6),
    Color(0xFF6366F1),
    Color(0xFFF97316),
    Color(0xFF22C55E),
    Color(0xFFEC4899),
    Color(0xFFA855F7),
    Color(0xFF0891B2),
  ];
  var h = 0;
  for (final c in name.trim().toLowerCase().codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return palette[h % palette.length];
}

/// Hora relativa curta (mesma régua do chat do CRM): agora / N min / N h /
/// N d, e a partir de 7 dias a data "d MMM" em pt-BR.
String _approvalThreadRelativeTime(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);
  if (diff.inSeconds < 60) return 'agora';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min';
  if (diff.inHours < 24) return '${diff.inHours} h';
  if (diff.inDays < 7) return '${diff.inDays} d';
  return DateFormat('d MMM', 'pt_BR').format(date.toLocal());
}

/// Bolha da conversa de aprovação — gramática do chat do CRM
/// (`_CommentBubble` do task_details_modal): avatar-inicial com cor estável
/// por hash do nome, bolha tinted azul quando é minha, neutra quando é dos
/// outros; nome w800 + fila em small caps + hora relativa.
class _ApprovalThreadBubble extends StatelessWidget {
  final PropertyHistoryEntry entry;
  final bool isMe;

  const _ApprovalThreadBubble({required this.entry, required this.isMe});

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Azul comunicação — mesma voz do chat do CRM.
    const accent = Color(0xFF3B82F6);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    final rawName = entry.user?.name?.trim() ?? '';
    final name = rawName.isNotEmpty
        ? rawName
        : (entry.user?.email?.trim().isNotEmpty == true
            ? entry.user!.email!.trim()
            : 'Usuário');
    final displayName = isMe ? 'Você' : name;

    // Fila da mensagem (metadata.approvalContext) — tag curta, paridade com
    // o `contextShort` do web: Disp. / Site.
    final queue = entry.metadata?['approvalContext']?.toString();
    final queueLabel = queue == 'publication'
        ? 'SITE'
        : (queue == 'availability' ? 'DISP.' : null);
    final wasEdited = (entry.metadata?['editedAt']?.toString() ?? '')
        .isNotEmpty;

    final bubbleColor = isMe
        ? accent.withValues(alpha: isDark ? 0.16 : 0.08)
        : ThemeHelpers.cardBackgroundColor(context)
            .withValues(alpha: isDark ? 0.5 : 0.7);
    final borderColor = isMe
        ? accent.withValues(alpha: 0.34)
        : ThemeHelpers.borderColor(context).withValues(alpha: 0.45);
    final personTone = _approvalPersonColor(name);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: personTone,
            ),
            alignment: Alignment.center,
            child: Text(
              _initials(name),
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 9, 11, 10),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
                color: bubbleColor,
                border: Border.all(color: borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            height: 1.15,
                            color: isMe
                                ? accent
                                : ThemeHelpers.textColor(context),
                          ),
                        ),
                      ),
                      if (queueLabel != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: accent
                                .withValues(alpha: isDark ? 0.2 : 0.1),
                          ),
                          child: Text(
                            queueLabel,
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: accent,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      Text(
                        _approvalThreadRelativeTime(entry.createdAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: secondary,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  SelectableText(
                    (entry.description ?? '').trim(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.45,
                      fontSize: 13.5,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  if (wasEdited) ...[
                    const SizedBox(height: 3),
                    Text(
                      'editada',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: secondary.withValues(alpha: 0.8),
                        fontStyle: FontStyle.italic,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Card refinado para um único captador.
///
/// Layout:
///   [Avatar 36px] [Nome (bold) + linha de contato (telefone/email muted)]
///   [Ações em ícone à direita: Ligar / WhatsApp — só quando há telefone]
///
/// Avatar: foto se houver `avatar`, senão iniciais do nome em fundo gradiente
/// derivado do accent (ou de um palette estável por hash do nome).
/// Barra de abas do detalhe — sublinhado de 2,5 na cor da aba ativa, ícone
/// na cor e rótulo no texto do tema (contraste), filete embaixo. Mede os
/// rótulos na escala real do texto: cabendo, as abas dividem a largura;
/// não cabendo (320dp, fonte grande, 5 abas), rolam na horizontal e a ativa
/// é trazida para a vista — sem mexer na rolagem da página.
class _DetailsTabBar extends StatefulWidget {
  const _DetailsTabBar({
    required this.tabs,
    required this.active,
    required this.onSelect,
  });

  final List<_DetailsTab> tabs;
  final _DetailsTab active;
  final ValueChanged<_DetailsTab> onSelect;

  @override
  State<_DetailsTabBar> createState() => _DetailsTabBarState();
}

class _DetailsTabBarState extends State<_DetailsTabBar> {
  static const double _hPad = 14;
  static const double _iconSize = 17;
  static const double _gap = 6;
  static const TextStyle _labelStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.1,
  );

  final ScrollController _scroll = ScrollController();
  final Map<_DetailsTab, GlobalKey> _keys = {};

  GlobalKey _keyOf(_DetailsTab tab) => _keys.putIfAbsent(tab, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    _revealActive(animate: false);
  }

  @override
  void didUpdateWidget(covariant _DetailsTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _revealActive();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Traz a aba ativa para a vista só na rolagem horizontal da barra
  /// (`ensureVisible` rolaria a página inteira também).
  void _revealActive({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final box =
          _keys[widget.active]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) return;
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport == null) return;
      final target = viewport
          .getOffsetToReveal(box, 0.5)
          .offset
          .clamp(0.0, _scroll.position.maxScrollExtent)
          .toDouble();
      if (animate) {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(target);
      }
    });
  }

  double _naturalWidth(BuildContext context, _DetailsTab tab) {
    final painter = TextPainter(
      text: TextSpan(text: tab.label, style: _labelStyle),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return _hPad * 2 + _iconSize + _gap + width + 1;
  }

  Widget _tab(BuildContext context, _DetailsTab tab, {required bool expand}) {
    final active = tab == widget.active;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final content = Container(
      key: _keyOf(tab),
      padding: const EdgeInsets.fromLTRB(_hPad, 12, _hPad, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: active ? tab.tone : Colors.transparent,
            width: 2.5,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(tab.icon, size: _iconSize, color: active ? tab.tone : muted),
          const SizedBox(width: _gap),
          Flexible(
            child: Text(
              tab.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _labelStyle.copyWith(
                color: active ? ThemeHelpers.textColor(context) : muted,
              ),
            ),
          ),
        ],
      ),
    );
    final button = Semantics(
      selected: active,
      button: true,
      child: InkWell(
        onTap: () => widget.onSelect(tab),
        child: content,
      ),
    );
    return expand ? Expanded(child: button) : button;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 4, 0, 0),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const side = 16.0;
          final available = constraints.maxWidth - side * 2;
          final natural = widget.tabs.fold<double>(
            0,
            (sum, tab) => sum + _naturalWidth(context, tab),
          );
          if (natural <= available) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: side),
              child: Row(
                children: [
                  for (final tab in widget.tabs)
                    _tab(context, tab, expand: true),
                ],
              ),
            );
          }
          return SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: side - 4),
            child: Row(
              children: [
                for (final tab in widget.tabs)
                  _tab(context, tab, expand: false),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Ação compacta da faixa de gestão do hero. Travada: apagada, com cadeado,
/// e o toque explica o motivo em vez de sumir.
class _HeroActionChip extends StatelessWidget {
  const _HeroActionChip({
    required this.icon,
    required this.label,
    required this.tone,
    required this.onTap,
    this.lockedReason,
    this.onLockedTap,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final Color tone;
  final VoidCallback onTap;
  final String? lockedReason;
  final void Function(String reason)? onLockedTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final reason = lockedReason;
    final locked = reason != null;
    final color = locked ? muted : tone;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy
            ? null
            : locked
                ? () => onLockedTap?.call(reason)
                : onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            color: locked ? null : tone.withValues(alpha: isDark ? 0.14 : 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: locked
                  ? ThemeHelpers.borderColor(context)
                  : tone.withValues(alpha: isDark ? 0.45 : 0.35),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                )
              else
                Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    color: color,
                  ),
                ),
              ),
              if (locked) ...[
                const SizedBox(width: 6),
                Icon(Icons.lock_outline_rounded, size: 13, color: muted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CaptorTile extends StatelessWidget {
  const _CaptorTile({
    required this.captor,
    required this.accent,
    required this.muted,
  });

  final PropertyCaptor captor;
  final Color accent;
  final Color muted;

  /// Iniciais para o avatar quando não há foto. Pega a primeira letra do
  /// primeiro e do último nome — em pessoas com nome único, repete a primeira.
  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  /// Telefone formatado pra exibição. Aceita E.164, dígitos puros, "(xx) ...".
  String _displayPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 11) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2, 7)}-${digits.substring(7)}';
    }
    if (digits.length == 10) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2, 6)}-${digits.substring(6)}';
    }
    return phone;
  }

  Future<void> _call(String phone) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: digits);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _whatsapp(String phone) async {
    var digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    // Garante DDI 55 quando vem só DDD + número.
    if (digits.length <= 11 && !digits.startsWith('55')) {
      digits = '55$digits';
    }
    final uri = Uri.parse('https://wa.me/$digits');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (captor.name ?? '').trim();
    final email = (captor.email ?? '').trim();
    final phone = (captor.phone ?? '').trim();
    final displayName = name.isNotEmpty ? name : 'Captador';
    final hasPhone = phone.isNotEmpty;
    final hasAvatar = (captor.avatar ?? '').isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: hasAvatar
                  ? null
                  : LinearGradient(
                      colors: [
                        accent,
                        accent.withValues(alpha: 0.65),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              image: hasAvatar
                  ? DecorationImage(
                      image: NetworkImage(captor.avatar!),
                      fit: BoxFit.cover,
                    )
                  : null,
              border: Border.all(
                color: accent.withValues(alpha: 0.35),
                width: 1.2,
              ),
            ),
            alignment: Alignment.center,
            child: hasAvatar
                ? null
                : Text(
                    _initials(displayName),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                    ),
                  ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      hasPhone
                          ? Icons.phone_rounded
                          : (email.isNotEmpty
                              ? Icons.mail_outline_rounded
                              : Icons.person_outline_rounded),
                      size: 12,
                      color: muted,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        hasPhone
                            ? _displayPhone(phone)
                            : (email.isNotEmpty ? email : 'Sem contato'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: muted,
                          letterSpacing: -0.05,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (hasPhone) ...[
            const SizedBox(width: 4),
            _CaptorActionButton(
              icon: Icons.phone_rounded,
              // Ligar = AZUL (comunicação) — vermelho é marca/erro, não isso.
              tint: const Color(0xFF3B82F6),
              tooltip: 'Ligar',
              onTap: () => _call(phone),
            ),
            const SizedBox(width: 4),
            _CaptorActionButton(
              icon: Icons.chat_rounded,
              tint: const Color(0xFF25D366),
              tooltip: 'WhatsApp',
              onTap: () => _whatsapp(phone),
            ),
          ],
        ],
      ),
    );
  }
}

class _CaptorActionButton extends StatelessWidget {
  const _CaptorActionButton({
    required this.icon,
    required this.tint,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color tint;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: tint.withValues(alpha: 0.32)),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 16, color: tint),
          ),
        ),
      ),
    );
  }
}
