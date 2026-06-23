import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../shared/services/property_service.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/skeleton_box.dart';
import '../../../../shared/widgets/shimmer_image.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../models/property_activity_models.dart';
import '../services/property_activity_service.dart';
import '../../matches/widgets/matches_badge.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../shared/utils/broker_contact_actions.dart';
import '../../../../shared/utils/broker_message_templates.dart';
import '../../appointments/pages/create_appointment_page.dart';
import '../../appointments/models/appointment_model.dart';
import '../../documents/services/document_service.dart';
import '../../documents/models/document_model.dart';
import '../../clients/services/client_service.dart';
import '../../documents/widgets/entity_selector.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../shared/services/api_service.dart';
import '../../keys/services/key_service.dart';
import '../../keys/models/key_model.dart' as key_models;
import '../../../../shared/services/gallery_service.dart';
import '../../../../shared/services/module_access_service.dart';
import '../../../../core/constants/app_permissions.dart';
import '../services/property_approval_service.dart';
import '../widgets/approval_action_sheets.dart';
import '../utils/property_edit_permissions.dart';
import '../utils/property_status_visual.dart';
import '../utils/compute_property_score.dart';
import '../widgets/property_score_panel.dart';

// Formatter de moeda
final _currencyFormatter = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 2,
);

/// Aba interna da ficha de imóvel.
enum _DetailsTab { details, activity, performance }

extension on _DetailsTab {
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

  const PropertyDetailsPage({
    super.key,
    required this.propertyId,
    this.initialProperty,
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
  final PageController _imagePageController = PageController();
  int _currentImageIndex = 0;

  // Documentos
  List<Document> _documents = [];
  bool _isLoadingDocuments = false;

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

  bool get _canEditProperty => _editPermission.canEdit;

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
    final access = ModuleAccessService.instance;
    final role = access.userRole?.toLowerCase() ?? '';
    if (role != 'master' && role != 'admin') return false;
    return _property?.status == PropertyStatus.sold;
  }

  /// Perfis elevados (master/admin/manager) podem republicar no site — mesma
  /// regra do web (`canChangePropertyStatusElevated`).
  bool get _canChangePropertyStatusElevated {
    final role = ModuleAccessService.instance.userRole?.toLowerCase() ?? '';
    return role == 'master' || role == 'admin' || role == 'manager';
  }

  /// Mostra o botão "Republicar no site" — espelha o web:
  /// `canChangePropertyStatusElevated && !canUndoSold`.
  bool get _canRepublishOnSite =>
      _canChangePropertyStatusElevated && !_canUndoSold;

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
      _loadProperty();
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
      _loadProperty();
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
      _loadProperty();
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
      _loadProperty();
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
    // Sempre inicia em loading para evitar "tela vazia" com `initialProperty`
    // parcial e garantir feedback visual consistente.
    _isLoading = true;
    _loadProperty();
    _loadSiteBaseUrl();
    _detailsScrollController.addListener(_handleDetailsScroll);
  }

  /// Base pública do site da empresa (custom domain ou subdomínio), do endpoint
  /// `/public-site-config` — espelha o web (`publicUrl || subdomainUrl`). Usada
  /// para montar o link compartilhável correto do imóvel. Fica null quando a
  /// empresa não tem site/permite ver a config; nesse caso a seção de
  /// "Compartilhar" nem aparece.
  Future<void> _loadSiteBaseUrl() async {
    try {
      final response =
          await _apiService.get<Map<String, dynamic>>('/public-site-config');
      if (!mounted || !response.success || response.data == null) return;
      final data = response.data!;
      final pub = (data['publicUrl'] as String?)?.trim();
      final sub = (data['subdomainUrl'] as String?)?.trim();
      final base = (pub != null && pub.isNotEmpty)
          ? pub
          : ((sub != null && sub.isNotEmpty) ? sub : null);
      if (base == null) return;
      setState(() => _siteBaseUrl = base.replaceAll(RegExp(r'/+$'), ''));
    } catch (_) {
      // Sem base → seção de compartilhar permanece oculta. Silencioso.
    }
  }

  /// URL pública completa do imóvel no site (ex.: `https://site/imovel/31020`).
  /// `null` quando não há base do site.
  String? _publicPropertyUrl(Property property) {
    final base = _siteBaseUrl;
    if (base == null || base.isEmpty) return null;
    final id = (property.code != null && property.code!.trim().isNotEmpty)
        ? property.code!.trim()
        : property.id;
    return '$base/imovel/${Uri.encodeComponent(id)}';
  }

  void _handleDetailsScroll() {
    if (!_detailsScrollController.hasClients) return;
    final offset = _detailsScrollController.offset;
    final shouldShow = offset > 480;
    if (shouldShow != _showScrollTopFab) {
      setState(() => _showScrollTopFab = shouldShow);
    }
  }

  Future<void> _loadDocuments() async {
    if (widget.propertyId.isEmpty) return;

    setState(() {
      _isLoadingDocuments = true;
    });

    try {
      final response = await _documentService.getDocuments(
        filters: DocumentFilters(propertyId: widget.propertyId),
        page: 1,
        limit: 10,
      );

      if (mounted) {
        setState(() {
          _isLoadingDocuments = false;
          if (response.success && response.data != null) {
            _documents = response.data!.data;
          }
        });
      }
    } catch (e) {
      debugPrint('âŒ [PROPERTY_DETAILS] Erro ao carregar documentos: $e');
      if (mounted) {
        setState(() {
          _isLoadingDocuments = false;
        });
      }
    }
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
    _detailsScrollController
      ..removeListener(_handleDetailsScroll)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadProperty() async {
    if (widget.propertyId.trim().isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'ID do imóvel inválido.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

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
          setState(() {
            _property = property;
            _isLoading = false;
            _linkedCondominium = null;
          });
          _debugLogPropertyImageDiagnostics(
            property,
            source: 'loadProperty.success',
          );
          // Carregar dados relacionados após carregar propriedade
          _loadDocuments();
          _loadChecklists();
          _loadExpenses();
          _loadKeys();
          final condoId = property.condominiumId?.trim();
          if (condoId != null && condoId.isNotEmpty) {
            _loadLinkedCondominium(condoId);
          }
        } else {
          setState(() {
            // Se já existe algum snapshot local da propriedade, mantém a tela
            // renderizada em vez de trocar para estado de erro cheio.
            if (_property == null) {
              _errorMessage =
                  response.message ?? 'Erro ao carregar propriedade';
            }
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('âŒ [PROPERTY_DETAILS] Erro: $e');
      if (mounted) {
        setState(() {
          if (_property == null) {
            _errorMessage = 'Erro ao conectar com o servidor';
          }
          _isLoading = false;
        });
      }
    }
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
        setState(() => _property = response.data);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Imóvel disponível novamente.'),
            backgroundColor: AppColors.status.success,
          ),
        );
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
        setState(() => _property = response.data);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Imóvel republicado no site.'),
            backgroundColor: AppColors.status.success,
          ),
        );
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
      final h = await _activityService.getHistory(id);
      if (mounted) {
        setState(() {
          _history = h;
          _loadingHistory = false;
          _historyLoaded = true;
        });
      }
    }
    if (!_updatesLoaded && !_loadingUpdates) {
      setState(() => _loadingUpdates = true);
      final u = await _activityService.getUpdates(id);
      if (mounted) {
        setState(() {
          _updates = u;
          _loadingUpdates = false;
          _updatesLoaded = true;
        });
      }
    }
  }

  Future<void> _ensurePerformanceLoaded() async {
    if (_engagementLoaded || _loadingEngagement) return;
    final id = _property?.id ?? widget.propertyId;
    if (id.trim().isEmpty) return;
    setState(() => _loadingEngagement = true);
    final stats = await _activityService.getEngagement(id);
    final byChannel = await _activityService.getEngagementByChannel(id);
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
      title: 'Detalhes do Imóvel',
      currentBottomNavIndex: 1,
      showBottomNavigation: true,
      actions: [
        if (_property != null && _property!.hasPendingOffers == true)
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.request_quote),
                onPressed: () {
                  Navigator.of(context).pushNamed(
                    '/properties/offers',
                    arguments: {'propertyId': widget.propertyId},
                  );
                },
                tooltip: 'Ver Ofertas',
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
            // Esconde o menu por completo se o usuário não tem nenhuma ação
            // disponível (visualização-pura para imóvel de outro corretor).
            final canEdit = _canEditProperty;
            final canDelete = _canDeleteProperty;
            final hasOffersShortcut =
                _property != null && _property!.hasPendingOffers == true;
            if (!canEdit && !canDelete && !hasOffersShortcut) {
              return const SizedBox.shrink();
            }
            return PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    if (!canEdit) return;
                    Navigator.of(
                      context,
                    ).pushNamed('/properties/${widget.propertyId}/edit');
                    break;
                  case 'delete':
                    if (!canDelete) return;
                    _deleteProperty();
                    break;
                  case 'offers':
                    Navigator.of(context).pushNamed(
                      '/properties/offers',
                      arguments: {'propertyId': widget.propertyId},
                    );
                    break;
                }
              },
              itemBuilder: (context) => [
                if (canEdit)
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 20),
                        SizedBox(width: 8),
                        Text('Editar'),
                      ],
                    ),
                  ),
                if (hasOffersShortcut)
                  const PopupMenuItem(
                    value: 'offers',
                    child: Row(
                      children: [
                        Icon(Icons.request_quote, size: 20),
                        SizedBox(width: 8),
                        Text('Ver Ofertas'),
                      ],
                    ),
                  ),
                if (canDelete)
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 20, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Excluir', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
      body: _isLoading
          ? _buildSkeleton(context)
          : _errorMessage != null
          ? _buildErrorState(context, theme)
          : () {
              final property = _property;
              if (property == null) {
                return _buildErrorState(
                  context,
                  theme,
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

  Widget _buildErrorState(
    BuildContext context,
    ThemeData theme, {
    String? message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: AppColors.status.error),
            const SizedBox(height: 16),
            Text(
              message ?? _errorMessage ?? 'Erro ao carregar propriedade',
              style: theme.textTheme.titleMedium?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadProperty,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
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
            padding: const EdgeInsets.only(top: 14),
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
        _loadProperty();
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
        (role == 'master' || role == 'admin') &&
        property.status == PropertyStatus.sold;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1) Título do imóvel — primeira informação (paridade web).
        Text(
          property.title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.025,
            height: 1.2,
            color: ThemeHelpers.textColor(context),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.location_on_outlined,
              size: 16,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _formatPropertyHeroAddress(property),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
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
                child: MatchesBadge(
                  propertyId: widget.propertyId,
                  onClick: () => Navigator.pushNamed(
                    context,
                    AppRoutes.matchesByProperty(widget.propertyId),
                  ),
                  child: const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ),

        // 3) Valores + botão "Republicar no site" (como no web).
        const SizedBox(height: 12),
        _buildPriceShowcase(context, theme, property, isDark),
        if (_canRepublishOnSite) ...[
          const SizedBox(height: 12),
          _buildRepublishButton(context, theme),
        ],

        // 3) Eyebrow: inativo, site, destaque, atualizado
        const SizedBox(height: 10),
        _buildHeroEyebrowChips(context, theme, property, isDark),

        // 4) Specs principais — faixa horizontal refinada (números-chave) +
        //    meta secundária (tipo, bairro, fotos) em chips discretos.
        const SizedBox(height: 14),
        _buildSpecsStrip(context, property, isDark),
        const SizedBox(height: 12),
        _buildHeroMetaPillsRow(context, property, isDark),

        // 6) STATUS DO IMÓVEL + SITUAÇÃO
        // precisa ver. Acompanha a paridade com a versão web (badge roxa
        // "Aguardando autorização do proprietário" + badge verde "Ativo").
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            PropertyStatusPill(status: property.status),
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
                      color: const Color(0xFF10B981).withValues(
                        alpha: isDark ? 0.14 : 0.1,
                      ),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: const Color(0xFF10B981).withValues(
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
                          color: const Color(0xFF10B981),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _undoSoldLoading
                              ? 'Tornando disponível...'
                              : 'Tornar disponível',
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            letterSpacing: 0.15,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            PropertySituationPill(
              isActive: property.isActive,
              isAvailableForSite: property.isAvailableForSite ?? false,
            ),
          ],
        ),

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

        // 4) Captação — agora FLAT (sem moldura externa), só conteúdo
        // direto no fundo da página.
        if (_hasCaptorsContent(property)) ...[
          const SizedBox(height: 16),
          _buildCaptorsBlock(context, theme, property, isDark, muted),
        ],

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

  /// Bloco refinado de captação:
  ///   - eyebrow "CAPTAÇÃO" + contador de captadores
  ///   - lista de cards com avatar (foto ou iniciais coloridas), nome,
  ///     e linha de contato (telefone) abaixo
  ///   - botão de "Ligar" e botão de "WhatsApp" quando há telefone
  Widget _buildCaptorsBlock(
    BuildContext context,
    ThemeData theme,
    Property property,
    bool isDark,
    Color muted,
  ) {
    final captors = _resolveCaptors(property);
    final accent = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;

    // Bloco flat (sem moldura externa) — segue a identidade do hero da
    // PropertiesPage: eyebrow accent + contador + lista de captadores.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.flag_outlined, size: 13, color: accent),
            const SizedBox(width: 6),
            Text(
              'CAPTAÇÃO',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.6,
                color: accent,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: accent.withValues(alpha: 0.32),
                ),
              ),
              child: Text(
                captors.length == 1
                    ? '1 captador'
                    : '${captors.length} captadores',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  color: accent,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Column(
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
        ),
      ],
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
    if (pending > 0) {
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

  IconData _typeIcon(PropertyType type) {
    switch (type) {
      case PropertyType.house:
        return Icons.cottage_outlined;
      case PropertyType.apartment:
        return Icons.apartment;
      case PropertyType.commercial:
        return Icons.storefront_outlined;
      case PropertyType.land:
        return Icons.terrain_outlined;
      case PropertyType.rural:
        return Icons.agriculture_outlined;
    }
  }

  String _formatPropertyHeroAddress(Property property) {
    final streetLine = [
      property.street.trim(),
      if (property.number.trim().isNotEmpty) property.number.trim(),
    ].where((s) => s.isNotEmpty).join(', ');
    final cityLine = '${property.city.trim()}/${property.state.trim()}';
    if (streetLine.isEmpty) return cityLine;
    return '$streetLine, $cityLine';
  }

  /// Pills discretas do hero — paridade `PropertyHeroMetaChip` (web).
  Widget _buildHeroMetaPillsRow(
    BuildContext context,
    Property property,
    bool isDark,
  ) {
    final chips = <Widget>[];
    final typeLabel = property.type.label;
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
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: muted,
              height: 1.2,
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
    final hasSale = property.salePrice != null;
    final hasRent = property.rentPrice != null;
    if (!hasSale && !hasRent) {
      return _buildPriceUnavailableCard(context, theme, isDark);
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
    if (extras == null) return priceBlock;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        priceBlock,
        extras,
      ],
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

  Widget _buildSectionTabs(BuildContext context, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark
        ? AppColors.background.cardBackgroundDarkMode
        : AppColors.background.cardBackground;
    final borderColor = isDark
        ? AppColors.border.borderDarkMode
        : AppColors.border.border;
    final muted = ThemeHelpers.textSecondaryColor(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor.withValues(alpha: isDark ? 0.55 : 0.7)),
        ),
        child: Row(
          children: _DetailsTab.values.map((tab) {
            final active = tab == _activeTab;
            final tabAccent = tab.tone;
            return Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _onTabSelected(tab),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: active ? tabAccent : null,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: active
                          ? [
                              BoxShadow(
                                color: tabAccent.withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          tab.icon,
                          size: 16,
                          color: active ? Colors.white : muted,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            tab.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: active ? Colors.white : muted,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
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
    final hasOffers = property.hasPendingOffers == true ||
        (property.totalOffersCount != null && property.totalOffersCount! > 0);
    final hasClients = (property.clients ?? []).isNotEmpty;
    final hasDocuments = !_isLoadingDocuments && _documents.isNotEmpty;
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
        title: 'Localização',
        icon: Icons.map_outlined,
        tone: const Color(0xFFEF4444),
        child: _buildMapSection(context, theme, property),
      ),
      _buildFlushSection(
        theme: theme,
        title: 'Status da chave',
        icon: Icons.vpn_key_outlined,
        tone: const Color(0xFFF59E0B),
        child: _buildKeyStatusSection(context, theme, property),
      ),
      if (hasClients)
        _buildFlushSection(
          theme: theme,
          title: 'Clientes vinculados',
          icon: Icons.people_alt_outlined,
          tone: const Color(0xFF0EA5E9),
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
      if (hasDocuments)
        _buildFlushSection(
          theme: theme,
          title: 'Documentos',
          icon: Icons.folder_open_outlined,
          tone: const Color(0xFF0284C7),
          child: _buildDocumentsSection(context, theme, property),
        ),
      _buildFlushSection(
        theme: theme,
        title: 'Ações rápidas',
        icon: Icons.bolt_rounded,
        // Vira a última seção quando "Compartilhar" não aparece.
        isLast: !(property.isAvailableForSite == true && _siteBaseUrl != null),
        // Tom coerente (azul info) — não vermelho.
        tone: theme.brightness == Brightness.dark
            ? AppColors.status.blueDarkMode
            : AppColors.status.blue,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // Agendar visita — azul (ação de agenda), não vermelho.
            FilledButton.icon(
              onPressed: () => _openScheduleVisit(property),
              style: FilledButton.styleFrom(
                backgroundColor: theme.brightness == Brightness.dark
                    ? AppColors.status.blueDarkMode
                    : AppColors.status.blue,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.event_rounded, size: 18),
              label: const Text('Agendar visita'),
            ),
            // Nova vistoria — neutro.
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pushNamed(
                AppRoutes.inspectionCreate,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: ThemeHelpers.textColor(context),
                side: BorderSide(color: ThemeHelpers.borderColor(context)),
              ),
              icon: const Icon(Icons.camera_alt_outlined, size: 18),
              label: const Text('Nova vistoria'),
            ),
          ],
        ),
      ),
      // Compartilhar — só quando o imóvel está no site E temos a base pública
      // (senão o link sairia errado). Copia a URL real do site.
      if (property.isAvailableForSite == true && _siteBaseUrl != null)
        _buildFlushSection(
          theme: theme,
          title: 'Compartilhar',
          icon: Icons.link_rounded,
          tone: const Color(0xFF64748B),
          isLast: true,
          child: _buildShareLinkFooter(context, theme, property),
        ),
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
  Widget _buildRepublishButton(BuildContext context, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final accent =
        isDark ? AppColors.status.successDarkMode : AppColors.status.success;

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _republishLoading ? null : _republishOnSite,
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: accent.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: _republishLoading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
              )
            : const Icon(Icons.published_with_changes_rounded, size: 20),
        label: Text(
          _republishLoading ? 'Republicando...' : 'Republicar no site',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFlushSection(
          theme: theme,
          title: 'Atualizações',
          icon: Icons.campaign_outlined,
          tone: accent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildUpdateComposer(context, theme, accent),
              const SizedBox(height: 14),
              if (_loadingUpdates && !_updatesLoaded)
                _buildInlineLoader(context, accent)
              else if (_updates.data.isEmpty)
                _buildActivityEmpty(
                    context, theme, 'Nenhuma atualização ainda.')
              else
                ..._updates.data
                    .map((u) => _buildUpdateTile(context, theme, u)),
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
                _buildInlineLoader(context, accent)
              else if (_history.isEmpty)
                _buildActivityEmpty(
                    context, theme, 'Sem histórico registrado.')
              else
                ..._history.map((h) => _buildHistoryTile(context, theme, h)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInlineLoader(BuildContext context, Color accent) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            valueColor: AlwaysStoppedAnimation<Color>(accent),
          ),
        ),
      ),
    );
  }

  Widget _buildActivityEmpty(
    BuildContext context,
    ThemeData theme,
    String message,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: ThemeHelpers.textSecondaryColor(context),
        ),
      ),
    );
  }

  Widget _buildUpdateComposer(
    BuildContext context,
    ThemeData theme,
    Color accent,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ThemeHelpers.borderColor(context)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          TextField(
            controller: _updateComposer,
            maxLines: 3,
            minLines: 1,
            maxLength: 2000,
            decoration: InputDecoration(
              hintText: 'Escreva uma atualização sobre o imóvel…',
              border: InputBorder.none,
              counterText: '',
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          FilledButton.icon(
            onPressed: _submittingUpdate ? null : _submitPropertyUpdate,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            icon: _submittingUpdate
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.send_rounded, size: 16),
            label: const Text('Publicar'),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateTile(
    BuildContext context,
    ThemeData theme,
    PropertyUpdateEntry update,
  ) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ThemeHelpers.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${update.user?.name ?? 'Sistema'} · ${_formatActivityDateTime(update.createdAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
          Text(update.content, style: theme.textTheme.bodyMedium),
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
    final published = property.isAvailableForSite == true;
    final engagementChild = !published
        ? _buildActivityEmpty(
            context,
            theme,
            'Imóvel fora do site — sem métricas de engajamento.',
          )
        : (_loadingEngagement && !_engagementLoaded)
            ? _buildInlineLoader(context, accent)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildEngagementMetrics(context, theme),
                  if (_engagementByChannel.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildEngagementByChannel(context, theme),
                  ],
                ],
              );
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

  Widget _buildEngagementMetrics(BuildContext context, ThemeData theme) {
    final stats = _engagement;
    final items = <(String, int, IconData)>[
      ('Visualizações', stats?.views ?? 0, Icons.visibility_outlined),
      ('WhatsApp', stats?.whatsappClicks ?? 0, Icons.chat_outlined),
      ('Telefone', stats?.phoneClicks ?? 0, Icons.call_outlined),
      ('Impressões', stats?.prints ?? 0, Icons.bar_chart_rounded),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.4,
      children: items.map((it) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ThemeHelpers.borderColor(context)),
          ),
          child: Row(
            children: [
              Icon(it.$3, size: 20, color: const Color(0xFF10B981)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${it.$2}',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      it.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEngagementByChannel(BuildContext context, ThemeData theme) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Por origem — últimos 30 dias',
          style: theme.textTheme.labelMedium?.copyWith(
            color: muted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        ..._engagementByChannel.map((ch) {
          final parts = <String>[
            '${ch.views} visualizações',
            if (ch.whatsappClicks > 0) '${ch.whatsappClicks} WA',
            if (ch.phoneClicks > 0) '${ch.phoneClicks} tel',
            if (ch.emailClicks > 0) '${ch.emailClicks} e-mail',
            if (ch.favorites > 0) '${ch.favorites} fav',
          ];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.public, size: 16, color: Color(0xFF10B981)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ch.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        parts.join(' · '),
                        style:
                            theme.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
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
          _buildSectionHeader(theme, title, icon, accentOverride: tone),
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

  Widget _buildShareLinkFooter(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    // URL real do imóvel no site (a seção só aparece quando ela existe).
    final url = _publicPropertyUrl(property) ??
        (property.code != null && property.code!.isNotEmpty
            ? 'imovel/${property.code}'
            : 'imovel/${property.id}');
    final blue =
        isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final fieldFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Copie o link público deste imóvel para enviar ao cliente.',
          style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.45),
        ),
        const SizedBox(height: 12),
        // Link em pill — selecionável.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: fieldFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ThemeHelpers.borderLightColor(context)),
          ),
          child: SelectableText(
            url,
            maxLines: 2,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
              color: ThemeHelpers.textColor(context),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            // Copiar — neutro.
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: url));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Link copiado'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: ThemeHelpers.textColor(context),
                  side: BorderSide(color: ThemeHelpers.borderColor(context)),
                ),
                icon: const Icon(Icons.content_copy_rounded, size: 18),
                label: const Text('Copiar link'),
              ),
            ),
            const SizedBox(width: 8),
            // Compartilhar — azul (comunicação), com o link real na mensagem.
            Expanded(
              child: FilledButton.icon(
                onPressed: () {
                  final base = BrokerMessageTemplates.propertyShare(
                    propertyTitle: property.title,
                    address: [
                      property.address,
                      property.city,
                    ].where((s) => s.trim().isNotEmpty).join(', '),
                    code: property.code,
                  );
                  BrokerContactActions.shareText(context, '$base\n$url');
                },
                style: FilledButton.styleFrom(
                  backgroundColor: blue,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.share_rounded, size: 18),
                label: const Text('Compartilhar'),
              ),
            ),
          ],
        ),
      ],
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

  Widget _buildKeyStatusSection(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final hasKeys = _keys.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isLoadingKeys)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: (hasKeys
                      ? AppColors.status.success
                      : ThemeHelpers.textSecondaryColor(context))
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: (hasKeys
                        ? AppColors.status.success
                        : ThemeHelpers.textSecondaryColor(context))
                    .withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              hasKeys ? 'Chave disponível' : 'Sem chave',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: hasKeys
                    ? AppColors.status.success
                    : ThemeHelpers.textSecondaryColor(context),
              ),
            ),
          ),
          if (hasKeys) ...[
            const SizedBox(height: 10),
            Text(
              _keys.first.name,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () {
                if (hasKeys) {
                  Navigator.of(context).pushNamed(
                    '/keys',
                    arguments: {'propertyId': property.id},
                  );
                } else {
                  _showCreateKeyModal(context, property);
                }
              },
              icon: Icon(
                hasKeys ? Icons.vpn_key_rounded : Icons.add_rounded,
                size: 18,
              ),
              label: Text(hasKeys ? 'Gerenciar chaves' : 'Cadastrar chave'),
              // Ação aditiva/neutra — nada de vermelho. Cor coerente: neutra.
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
      ],
    );
  }

  Widget _buildClientsSection(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final clients = property.clients ?? [];
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                clients.isEmpty
                    ? 'Vincule clientes interessados a este imóvel.'
                    : '${clients.length} cliente(s) vinculado(s)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () {
                _showLinkClientModal(context, property);
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Adicionar'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (clients.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 44,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Nenhum cliente vinculado',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...clients.map((client) {
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
                  child: InkWell(
                    onTap: () {
                      Navigator.of(
                        context,
                      ).pushNamed(AppRoutes.clientDetails(client.id));
                    },
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          child: Text(
                            client.name[0].toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                client.name,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (client.email.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  client.email,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: ThemeHelpers.textSecondaryColor(
                                      context,
                                    ),
                                  ),
                                ),
                              ],
                              if (client.phone.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  client.phone,
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
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.primary.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                client.interestType,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.primary.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                              color: ThemeHelpers.textSecondaryColor(context),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
      ],
    );
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
                    // TODO: Navegar para detalhes do checklist quando a página existir
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Visualizar checklist: $checklistId'),
                        backgroundColor: AppColors.status.info,
                      ),
                    );
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
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(
                    Icons.description,
                    color: AppColors.primary.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Documentos',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(
                      context,
                    ).pushNamed(AppRoutes.documentCreate).then((_) {
                      _loadDocuments();
                    });
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Adicionar'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _isLoadingDocuments
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : _documents.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(
                            Icons.description_outlined,
                            size: 48,
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Nenhum documento vinculado',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: ThemeHelpers.textSecondaryColor(context),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Adicione contratos, IPTU, matrícula e outros documentos relacionados a esta propriedade',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: ThemeHelpers.textSecondaryColor(context),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(
                                context,
                              ).pushNamed(AppRoutes.documentCreate).then((_) {
                                _loadDocuments();
                              });
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('Adicionar Documento'),
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    children: [
                      ..._documents.take(5).map((document) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors
                                      .background
                                      .backgroundSecondaryDarkMode
                                : AppColors.background.backgroundSecondary,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: ThemeHelpers.borderLightColor(context),
                            ),
                          ),
                          child: InkWell(
                            onTap: () {
                              Navigator.of(context).pushNamed(
                                AppRoutes.documentDetails(document.id),
                              );
                            },
                            child: Row(
                              children: [
                                Icon(
                                  Icons.description,
                                  color: AppColors.primary.primary,
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        document.title ?? document.originalName,
                                        style: theme.textTheme.bodyLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (document.description != null &&
                                          document.description!.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          document.description!,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color:
                                                    ThemeHelpers.textSecondaryColor(
                                                      context,
                                                    ),
                                              ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.arrow_forward_ios,
                                  size: 16,
                                  color: ThemeHelpers.textSecondaryColor(
                                    context,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      if (_documents.length > 5) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(
                              context,
                            ).pushNamed(AppRoutes.documents);
                          },
                          icon: const Icon(Icons.visibility),
                          label: Text('Ver Todos (${_documents.length})'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 40),
                          ),
                        ),
                      ],
                    ],
                  ),
      ],
    );
  }

  Widget _buildMapSection(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final address = property.address.isNotEmpty
        ? property.address
        : '${property.street}, ${property.number} - ${property.neighborhood}, ${property.city} - ${property.state}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 180,
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.background.backgroundSecondaryDarkMode
                : AppColors.background.backgroundSecondary,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.map_outlined,
                size: 44,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
              const SizedBox(height: 8),
              Text(
                'Mapa de Localização',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(
              Icons.location_on,
              size: 18,
              color: AppColors.primary.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                address,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ThemeHelpers.textColor(context),
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Abrir no mapa será implementado'),
                  ),
                );
              },
              child: const Text('Abrir no Mapa'),
            ),
          ],
        ),
      ],
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
    final selectedInterestTypeRef = <String?>[null];
    final notesController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final interestTypes = ['buy', 'rent', 'both'];

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
                          'Vincular Cliente',
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
                  // Interest Type
                  Text(
                    'Tipo de Interesse *',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: interestTypes.map((type) {
                      final labels = {
                        'buy': 'Compra',
                        'rent': 'Aluguel',
                        'both': 'Ambos',
                      };
                      final isSelected = selectedInterestTypeRef[0] == type;
                      return ChoiceChip(
                        label: Text(labels[type] ?? type),
                        selected: isSelected,
                        onSelected: (selected) {
                          setModalState(() {
                            selectedInterestTypeRef[0] = selected ? type : null;
                          });
                        },
                      );
                    }).toList(),
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
                              if (selectedInterestTypeRef[0] == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                      'Por favor, selecione o tipo de interesse',
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
                          label: const Text('Vincular Cliente'),
                          style: ElevatedButton.styleFrom(
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
      if (result != true ||
          selectedClientIdRef[0] == null ||
          selectedInterestTypeRef[0] == null) {
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
        interestType: selectedInterestTypeRef[0]!,
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
          _loadProperty();
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
    final isDark = theme.brightness == Brightness.dark;
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
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

    final textStyle = theme.textTheme.bodyLarge?.copyWith(
      height: 1.6,
      fontSize: 14.5,
      letterSpacing: -0.05,
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
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                expanded ? 'Ver menos' : 'Ver mais',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 220),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
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
              tint: accent,
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
