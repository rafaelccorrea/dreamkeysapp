import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_permissions.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/shell_visual_tokens.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/property_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../services/property_approval_service.dart';
import '../widgets/approval_action_sheets.dart';
import '../widgets/approval_property_card.dart';

/// Tela de **Fila de Aprovação de Imóveis**.
///
/// Identidade visual alinhada ao DNA do app:
/// - Padding página `_kPagePadH=20 / top=10 / bottom=88` + ambient glows.
/// - Greeting com ícone gradiente + eyebrow `letterSpacing 2.2` + título grande.
/// - **KPI strip horizontal slim** (sem cards quadrados) com `dashboardGlass*`.
/// - **Navegação horizontal em pills** (segmented) com gradiente accent quando
///   selecionado e glass fill quando inativo.
/// - Painel principal com `ShellVisualTokens.elevatedPanelDecoration`.
/// - Cards usam `inlineTileDecoration` com **lazy thumbnail** (resolve foto
///   via `getPropertyById` por id quando o backend não devolve `images`).
class PropertyApprovalsPage extends StatefulWidget {
  const PropertyApprovalsPage({super.key});

  @override
  State<PropertyApprovalsPage> createState() => _PropertyApprovalsPageState();
}

enum _Tab { mine, ownerAuth, availability, publication, rejected }

class _PropertyApprovalsPageState extends State<PropertyApprovalsPage> {
  static const double _kSectionGap = 11;
  static const double _kPagePadH = 20;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const int _kRejectedPageSize = 10;

  late final ModuleAccessService _moduleAccess = ModuleAccessService.instance;
  late final bool _hasView;
  late final bool _canApproveAvailability;
  late final bool _canRejectAvailability;
  late final bool _canApprovePublication;
  late final bool _canRejectPublication;

  PropertyApprovalSettingsActive? _settings;

  // Estado por aba.
  bool _loadingMine = false;
  String? _errorMine;
  MyPendingResponse _myPending = MyPendingResponse.empty;

  bool _loadingAvailability = false;
  String? _errorAvailability;
  List<Property> _pendingAvailability = const [];

  bool _loadingPublication = false;
  String? _errorPublication;
  List<Property> _pendingPublication = const [];

  bool _loadingOwner = false;
  String? _errorOwner;
  List<Property> _pendingOwner = const [];

  bool _loadingRejectedAvail = false;
  bool _loadingRejectedPub = false;
  String? _errorRejected;
  RejectedListResponse _rejectedAvail = RejectedListResponse.empty;
  RejectedListResponse _rejectedPub = RejectedListResponse.empty;
  RejectedCounts _rejectedCounts = RejectedCounts.zero;

  _Tab _activeTab = _Tab.mine;

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _appliedSearch = '';

  final Set<String> _actionIds = <String>{};

  @override
  void initState() {
    super.initState();
    _hasView = _moduleAccess.hasPermission(AppPermissions.propertyView);
    _canApproveAvailability =
        _moduleAccess.hasPermission(AppPermissions.propertyApproveAvailability);
    _canRejectAvailability =
        _moduleAccess.hasPermission(AppPermissions.propertyRejectAvailability);
    _canApprovePublication =
        _moduleAccess.hasPermission(AppPermissions.propertyApprovePublication);
    _canRejectPublication =
        _moduleAccess.hasPermission(AppPermissions.propertyRejectPublication);

    _bootstrap();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final settingsRes =
        await PropertyService.instance.getPropertyApprovalSettingsActive();
    if (!mounted) return;
    setState(() => _settings = settingsRes.data);
    await _refreshAll();
  }

  Future<void> _refreshAll() {
    return Future.wait([
      _loadMine(),
      if (_hasView) ...[
        _loadAvailability(),
        _loadPublication(),
        _loadOwnerAuth(),
        _loadRejected(),
      ],
    ]);
  }

  ApprovalListFilters _filters() => ApprovalListFilters(search: _appliedSearch);

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
    });
    final res = await PropertyApprovalService.instance.getMyPending(
      filters: _filters(),
    );
    if (!mounted) return;
    setState(() {
      _loadingMine = false;
      if (res.success && res.data != null) {
        _myPending = res.data!;
      } else {
        _errorMine = res.message ?? 'Erro ao carregar suas pendências';
      }
    });
  }

  Future<void> _loadAvailability() async {
    setState(() {
      _loadingAvailability = true;
      _errorAvailability = null;
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
      } else {
        _errorAvailability =
            res.message ?? 'Erro ao carregar fila de disponibilidade';
      }
    });
  }

  Future<void> _loadPublication() async {
    setState(() {
      _loadingPublication = true;
      _errorPublication = null;
    });
    final res = await PropertyApprovalService.instance.getPendingPublication(
      filters: _filters(),
    );
    if (!mounted) return;
    setState(() {
      _loadingPublication = false;
      if (res.success && res.data != null) {
        _pendingPublication = res.data!;
      } else {
        _errorPublication =
            res.message ?? 'Erro ao carregar fila de publicação';
      }
    });
  }

  Future<void> _loadOwnerAuth() async {
    setState(() {
      _loadingOwner = true;
      _errorOwner = null;
    });
    final res = await PropertyApprovalService.instance
        .getPendingOwnerAuthorization(filters: _filters());
    if (!mounted) return;
    setState(() {
      _loadingOwner = false;
      if (res.success && res.data != null) {
        _pendingOwner = res.data!;
      } else {
        _errorOwner = res.message ?? 'Erro ao carregar autorizações';
      }
    });
  }

  Future<void> _loadRejected({int page = 1}) async {
    setState(() {
      _loadingRejectedAvail = true;
      _loadingRejectedPub = true;
      _errorRejected = null;
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
      }
      if (r1.success && r1.data != null) {
        _rejectedPub = r1.data! as RejectedListResponse;
      } else if (r1.message != null) {
        _errorRejected ??= r1.message;
      }
      if (r2.success && r2.data != null) {
        _rejectedCounts = r2.data! as RejectedCounts;
      }
    });
  }

  // ─── Ações ────────────────────────────────────────────────────────────

  bool _isResponsible(Property p) {
    final uid = _moduleAccess.userId;
    if (uid == null) return false;
    if (p.responsibleUserId == uid) return true;
    if (p.responsibleUserIds != null && p.responsibleUserIds!.contains(uid)) {
      return true;
    }
    if (p.capturedById == uid) return true;
    if (p.capturedByIds != null && p.capturedByIds!.contains(uid)) return true;
    return false;
  }

  void _setActionLoading(String id, bool value) {
    if (!mounted) return;
    setState(() {
      if (value) {
        _actionIds.add(id);
      } else {
        _actionIds.remove(id);
      }
    });
  }

  void _showSnack(String message, {bool success = false}) {
    if (!mounted) return;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = success
        ? (isDark
            ? AppColors.status.greenDarkMode
            : AppColors.status.green)
        : (isDark
            ? AppColors.status.errorDarkMode
            : AppColors.status.error);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        content: Row(
          children: [
            Icon(
              success ? LucideIcons.checkCircle2 : LucideIcons.alertCircle,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _approveAvailability(Property p) async {
    _setActionLoading(p.id, true);
    final res = await PropertyApprovalService.instance.approveAvailability(
      p.id,
      applyWatermark: false,
    );
    _setActionLoading(p.id, false);
    if (!mounted) return;
    if (res.success) {
      _showSnack('Disponibilidade aprovada', success: true);
      await _refreshAll();
    } else {
      _showSnack(res.message ?? 'Falha ao aprovar disponibilidade');
    }
  }

  Future<void> _rejectAvailability(Property p) async {
    final reason = await showRejectReasonSheet(
      context: context,
      title: 'Recusar disponibilidade',
      propertySubtitle: p.title.isEmpty ? p.code : p.title,
    );
    if (reason == null) return;
    _setActionLoading(p.id, true);
    final res = await PropertyApprovalService.instance.rejectAvailability(
      p.id,
      reason: reason,
    );
    _setActionLoading(p.id, false);
    if (!mounted) return;
    if (res.success) {
      _showSnack('Imóvel recusado. Motivo enviado ao responsável.',
          success: true);
      await _refreshAll();
    } else {
      _showSnack(res.message ?? 'Falha ao recusar disponibilidade');
    }
  }

  Future<void> _approvePublication(Property p) async {
    final watermarkConfigured = _settings?.applyWatermarkToImages ?? false;
    bool? applyWatermark;
    if (watermarkConfigured) {
      final result = await showApprovePublicationSheet(
        context: context,
        propertyTitle: p.title.isEmpty ? (p.code ?? '') : p.title,
        watermarkConfigured: true,
      );
      if (result == null) return;
      applyWatermark = result.applyWatermark;
    }
    _setActionLoading(p.id, true);
    final res = await PropertyApprovalService.instance.approvePublication(
      p.id,
      applyWatermark: applyWatermark,
    );
    _setActionLoading(p.id, false);
    if (!mounted) return;
    if (res.success) {
      _showSnack('Publicação aprovada — imóvel já está no site.',
          success: true);
      await _refreshAll();
    } else {
      _showSnack(res.message ?? 'Falha ao aprovar publicação');
    }
  }

  Future<void> _rejectPublication(Property p) async {
    final reason = await showRejectReasonSheet(
      context: context,
      title: 'Recusar publicação no site',
      propertySubtitle: p.title.isEmpty ? p.code : p.title,
    );
    if (reason == null) return;
    _setActionLoading(p.id, true);
    final res = await PropertyApprovalService.instance.rejectPublication(
      p.id,
      reason: reason,
    );
    _setActionLoading(p.id, false);
    if (!mounted) return;
    if (res.success) {
      _showSnack('Publicação recusada. Responsável foi notificado.',
          success: true);
      await _refreshAll();
    } else {
      _showSnack(res.message ?? 'Falha ao recusar publicação');
    }
  }

  Future<void> _resendAvailability(Property p) async {
    _setActionLoading(p.id, true);
    final svc = PropertyApprovalService.instance;
    final res = _canApproveAvailability
        ? await svc.requestAvailabilityReview(p.id)
        : await svc.requestAvailabilityReviewAsResponsible(p.id);
    _setActionLoading(p.id, false);
    if (!mounted) return;
    if (res.success) {
      _showSnack('Imóvel reenviado para análise.', success: true);
      await _refreshAll();
    } else {
      _showSnack(res.message ?? 'Falha ao reabrir análise');
    }
  }

  Future<void> _resendPublication(Property p) async {
    _setActionLoading(p.id, true);
    final svc = PropertyApprovalService.instance;
    final res = _canApprovePublication
        ? await svc.requestSitePublicationReview(p.id)
        : await svc.requestSitePublicationReviewAsResponsible(p.id);
    _setActionLoading(p.id, false);
    if (!mounted) return;
    if (res.success) {
      _showSnack('Publicação reenviada para análise.', success: true);
      await _refreshAll();
    } else {
      _showSnack(res.message ?? 'Falha ao reabrir análise');
    }
  }

  void _openDetails(Property p) {
    Navigator.of(context).pushNamed(AppRoutes.propertyDetails(p.id));
  }

  // ─── Helpers visuais ──────────────────────────────────────────────────

  Color _accentColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFFF4D67)
        : AppColors.primary.primary;
  }

  List<Widget> _ambientHighlights(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accentColor(context);
    final cool = isDark ? const Color(0xFF4F46E5) : const Color(0xFF818CF8);
    return [
      Positioned(
        top: -72,
        right: -48,
        child: IgnorePointer(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  cool.withValues(alpha: isDark ? 0.14 : 0.065),
                  cool.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ),
      Positioned(
        top: 120,
        left: -80,
        child: IgnorePointer(
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  accent.withValues(alpha: isDark ? 0.16 : 0.07),
                  accent.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
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
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ..._ambientHighlights(context),
                  Column(
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
                            const SizedBox(height: _kSectionGap + 1),
                            _buildKpiStrip(context),
                            const SizedBox(height: _kSectionGap),
                            _buildSearchField(context),
                            const SizedBox(height: _kSectionGap + 1),
                          ],
                        ),
                      ),
                      _buildTabsRail(context),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          _kPagePadH,
                          _kSectionGap + 1,
                          _kPagePadH,
                          _kPagePadBottom,
                        ),
                        child: _buildActivePanel(context),
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
  }

  // ─── Greeting (estilo `_buildGreeting` do dashboard) ───────────────────

  Widget _buildGreeting(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accentColor(context);
    final isDark = theme.brightness == Brightness.dark;
    final pendingTotal = _pendingTotal();
    final danger = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [accent, const Color(0xFF7C3AED)],
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? accent.withValues(alpha: 0.35)
                      : accent.withValues(alpha: 0.22),
                  blurRadius: isDark ? 14 : 11,
                  offset: Offset(0, isDark ? 8 : 4),
                  spreadRadius: isDark ? 0 : -1,
                ),
              ],
            ),
            child: const Icon(
              LucideIcons.shieldCheck,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FILA DE APROVAÇÃO',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _hasView
                      ? (pendingTotal == 0
                          ? 'Tudo em dia por aqui'
                          : '$pendingTotal ${pendingTotal == 1 ? 'imóvel aguarda' : 'imóveis aguardam'} aprovação')
                      : 'Acompanhe seus imóveis na fila',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    height: 1.05,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                if (_rejectedCounts.total > 0)
                  Row(
                    children: [
                      _PulseDot(color: danger),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '${_rejectedCounts.total} recusado${_rejectedCounts.total == 1 ? '' : 's'} aguardando reenvio',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: danger,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    'Liberação para a operação e para o site',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      height: 1.3,
                    ),
                  ),
              ],
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

  // ─── KPI strip horizontal slim (sem cards quadrados) ──────────────────

  Widget _buildKpiStrip(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
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

    final items = <_KpiItem>[
      _KpiItem(
        label: 'Pendentes',
        value: _pendingTotal(),
        color: accent,
      ),
      _KpiItem(
        label: 'Disponibilidade',
        value: _pendingAvailability.length,
        color: ok,
      ),
      _KpiItem(
        label: 'Publicação',
        value: _pendingPublication.length,
        color: warn,
      ),
      _KpiItem(
        label: 'Proprietário',
        value: _pendingOwner.length,
        color: purple,
      ),
      _KpiItem(
        label: 'Recusados',
        value: _rejectedCounts.total,
        color: danger,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: ShellVisualTokens.dashboardGlassFill(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ShellVisualTokens.dashboardGlassBorder(context),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.025),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                  spreadRadius: -3,
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                _KpiTile(item: items[i], theme: theme),
                if (i < items.length - 1)
                  Container(
                    width: 1,
                    height: 32,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    color: ThemeHelpers.borderColor(context)
                        .withValues(alpha: 0.4),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─── Search field ─────────────────────────────────────────────────────

  Widget _buildSearchField(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accentColor(context);
    return TextField(
      controller: _searchController,
      onChanged: (v) {
        _onSearchChanged(v);
        setState(() {});
      },
      textInputAction: TextInputAction.search,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: ThemeHelpers.textColor(context),
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        hintText: 'Buscar por código, título, proprietário…',
        hintStyle: theme.textTheme.bodyMedium?.copyWith(
          color: ThemeHelpers.textSecondaryColor(context),
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 14, right: 8),
          child: Icon(LucideIcons.search, size: 18, color: accent),
        ),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 38, minHeight: 38),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(LucideIcons.x, size: 16),
                splashRadius: 18,
                onPressed: () {
                  _searchController.clear();
                  _onSearchChanged('');
                  setState(() {});
                },
              ),
      ),
    );
  }

  // ─── Tabs horizontais (pills com gradiente) ───────────────────────────

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

    final tabs = <_TabSpec>[
      _TabSpec(
        tab: _Tab.mine,
        icon: LucideIcons.user,
        label: 'Meus',
        count: _myPending.total,
        accentColor: accent,
      ),
      if (_hasView)
        _TabSpec(
          tab: _Tab.availability,
          icon: LucideIcons.checkCircle2,
          label: 'Disponibilidade',
          count: _pendingAvailability.length,
          accentColor: ok,
        ),
      if (_hasView)
        _TabSpec(
          tab: _Tab.publication,
          icon: LucideIcons.globe,
          label: 'Publicação',
          count: _pendingPublication.length,
          accentColor: warn,
        ),
      if (_hasView)
        _TabSpec(
          tab: _Tab.ownerAuth,
          icon: LucideIcons.fileSignature,
          label: 'Proprietário',
          count: _pendingOwner.length,
          accentColor: purple,
        ),
      if (_hasView)
        _TabSpec(
          tab: _Tab.rejected,
          icon: LucideIcons.alertTriangle,
          label: 'Recusados',
          count: _rejectedCounts.total,
          accentColor: danger,
        ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(_kPagePadH, 0, _kPagePadH, 0),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++) ...[
            _TabPill(
              spec: tabs[i],
              selected: _activeTab == tabs[i].tab,
              onTap: () => _selectTab(tabs[i].tab),
            ),
            if (i < tabs.length - 1) const SizedBox(width: 8),
          ],
        ],
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
    }
  }

  Widget _buildPanelHeader(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accentColor(context);
    final isDark = theme.brightness == Brightness.dark;
    final meta = _panelMeta();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: [accent, const Color(0xFF7C3AED)],
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: isDark ? 0.32 : 0.22),
                blurRadius: 12,
                offset: const Offset(0, 6),
                spreadRadius: -2,
              ),
            ],
          ),
          child: Icon(meta.icon, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                meta.eyebrow,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 2),
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
    }
  }

  Widget _buildTabBody() {
    final List<Widget> nodes = [];

    void addList(List<Property> list, ApprovalQueueKind kind) {
      for (var i = 0; i < list.length; i++) {
        nodes.add(
          ApprovalPropertyCard(
            property: list[i],
            kind: kind,
            canApproveAvailability: _canApproveAvailability,
            canRejectAvailability: _canRejectAvailability,
            canApprovePublication: _canApprovePublication,
            canRejectPublication: _canRejectPublication,
            isResponsibleForProperty: _isResponsible(list[i]),
            actionInProgress: _actionIds.contains(list[i].id),
            onOpenDetails: () => _openDetails(list[i]),
            onApproveAvailability: () => _approveAvailability(list[i]),
            onRejectAvailability: () => _rejectAvailability(list[i]),
            onApprovePublication: () => _approvePublication(list[i]),
            onRejectPublication: () => _rejectPublication(list[i]),
            onResendAvailability: () => _resendAvailability(list[i]),
            onResendPublication: () => _resendPublication(list[i]),
          )
              .animate(key: ValueKey('card-${list[i].id}-$kind'))
              .fadeIn(
                delay: Duration(milliseconds: 50 * i),
                duration: 240.ms,
              )
              .slideY(
                begin: 0.05,
                end: 0,
                delay: Duration(milliseconds: 50 * i),
                duration: 260.ms,
                curve: Curves.easeOutCubic,
              ),
        );
        if (i < list.length - 1) {
          nodes.add(const SizedBox(height: 10));
        }
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
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: nodes,
    );
  }

  Widget _buildSkeletonList() {
    return Column(
      children: List.generate(
        3,
        (i) => Padding(
          padding: EdgeInsets.only(bottom: i < 2 ? 10 : 0),
          child: SkeletonBox(
            height: 156,
            borderRadius: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildPanelError() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: danger.withValues(alpha: 0.12),
              border: Border.all(color: danger.withValues(alpha: 0.32)),
            ),
            child: Icon(LucideIcons.cloudOff, color: danger, size: 26),
          ),
          const SizedBox(height: 14),
          Text(
            _currentTabError() ?? 'Erro ao carregar',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _refreshAll,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Tentar novamente'),
          ),
        ],
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
    }
  }
}

// ─── Subwidgets internos ────────────────────────────────────────────────

class _KpiItem {
  final String label;
  final int value;
  final Color color;
  _KpiItem({required this.label, required this.value, required this.color});
}

class _KpiTile extends StatelessWidget {
  final _KpiItem item;
  final ThemeData theme;

  const _KpiTile({required this.item, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(top: 9),
                decoration: BoxDecoration(
                  color: item.color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: item.color.withValues(alpha: 0.45),
                      blurRadius: 6,
                      spreadRadius: 0,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.2),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: Text(
                  '${item.value}',
                  key: ValueKey(item.value),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    letterSpacing: -0.6,
                    height: 1.05,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            item.label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              fontSize: 10,
            ),
          ),
        ],
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

class _TabPill extends StatelessWidget {
  final _TabSpec spec;
  final bool selected;
  final VoidCallback onTap;

  const _TabPill({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fg = selected ? Colors.white : ThemeHelpers.textColor(context);
    final fgSecondary = selected
        ? Colors.white.withValues(alpha: 0.85)
        : ThemeHelpers.textSecondaryColor(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: selected
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  spec.accentColor,
                  spec.accentColor.withValues(alpha: 0.78),
                ],
              )
            : null,
        color: selected ? null : ShellVisualTokens.dashboardGlassFill(context),
        border: Border.all(
          color: selected
              ? spec.accentColor.withValues(alpha: 0.3)
              : ShellVisualTokens.dashboardGlassBorder(context),
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: spec.accentColor
                      .withValues(alpha: isDark ? 0.4 : 0.32),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                  spreadRadius: -3,
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          splashColor: spec.accentColor.withValues(alpha: 0.18),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 9,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(spec.icon, size: 16, color: fg),
                const SizedBox(width: 7),
                Text(
                  spec.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.1,
                  ),
                ),
                if (spec.count > 0) ...[
                  const SizedBox(width: 8),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white.withValues(alpha: 0.22)
                          : spec.accentColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      spec.count > 99 ? '99+' : '${spec.count}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: selected ? Colors.white : spec.accentColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
                if (spec.count == 0) const SizedBox(width: 0),
                if (spec.count == 0 && !selected) ...[
                  const SizedBox(width: 6),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: fgSecondary.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ],
            ),
          ),
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

class _PulseDot extends StatelessWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(
          begin: 1,
          end: 1.5,
          duration: 700.ms,
          curve: Curves.easeInOut,
        )
        .fadeIn(begin: 0.55, duration: 700.ms);
  }
}
