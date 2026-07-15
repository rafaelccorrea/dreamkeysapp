import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/rental_models.dart';
import '../services/rental_service.dart';
import '../widgets/rental_card.dart';
import '../widgets/rental_filters_sheet.dart';
import '../widgets/rental_status_ui.dart';

final NumberFormat _compact = NumberFormat.compactCurrency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 1,
);

/// Tela **Locações** — lista dos contratos de aluguel (paridade com
/// `RentalsPage.tsx`): hero editorial com KPIs, busca flush, chips de status,
/// filtros avançados no modal padrão, paginação e ações no próprio item
/// (aprovar/rejeitar, editar, excluir).
class RentalsPage extends StatefulWidget {
  const RentalsPage({super.key});

  @override
  State<RentalsPage> createState() => _RentalsPageState();
}

class _RentalsPageState extends State<RentalsPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const double _kSectionGap = 12;
  static const int _pageSize = 20;

  List<Rental> _items = const [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _total = 0;
  int _page = 1;
  int _totalPages = 1;

  RentalFilters _filters = const RentalFilters(limit: _pageSize);

  RentalDashboardData? _stats;
  bool _statsLoading = false;

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _appliedSearch = '';
  bool _searchFocused = false;

  ModuleAccessService get _access => ModuleAccessService.instance;
  bool get _canView => _access.hasPermission(RentalPermissions.view);
  bool get _canCreate => _access.hasPermission(RentalPermissions.create);
  bool get _canUpdate => _access.hasPermission(RentalPermissions.update);
  bool get _canDelete => _access.hasPermission(RentalPermissions.delete);
  bool get _canManageWorkflows =>
      _access.hasPermission(RentalPermissions.manageWorkflows);
  bool get _canManagePayments =>
      _access.hasPermission(RentalPermissions.managePayments);
  bool get _canViewDashboard =>
      _access.hasPermission(RentalPermissions.viewDashboard);

  bool get _hasMore => _page < _totalPages;

  @override
  void initState() {
    super.initState();
    _load();
    if (_canViewDashboard) _loadStats();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Color _accentColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
  }

  // ─── Dados ───────────────────────────────────────────────────────────────

  RentalFilters _effectiveFilters(int page) {
    final search = _appliedSearch.trim();
    return _filters.copyWith(
      search: search.isEmpty ? '' : search,
      page: page,
      limit: _pageSize,
    );
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      if (refresh) _error = null;
    });
    final res = await RentalService.instance
        .getRentals(filters: _effectiveFilters(1));
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _items = res.data!.rentals;
        _total = res.data!.total;
        _page = res.data!.page;
        _totalPages = res.data!.totalPages;
        _error = null;
      } else {
        _error = res.message ?? 'Erro ao carregar locações';
      }
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final res = await RentalService.instance
        .getRentals(filters: _effectiveFilters(_page + 1));
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (res.success && res.data != null) {
        _items = [..._items, ...res.data!.rentals];
        _page = res.data!.page;
        _totalPages = res.data!.totalPages;
        _total = res.data!.total;
      }
    });
  }

  Future<void> _loadStats() async {
    setState(() => _statsLoading = true);
    final res = await RentalService.instance.getDashboard(periodMonths: 12);
    if (!mounted) return;
    setState(() {
      _statsLoading = false;
      if (res.success && res.data != null) _stats = res.data!;
    });
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _load(refresh: true),
      if (_canViewDashboard) _loadStats(),
    ]);
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final v = value.trim();
      if (v == _appliedSearch) return;
      setState(() => _appliedSearch = v);
      _load(refresh: true);
    });
  }

  void _selectStatus(RentalStatus? status) {
    if (_filters.status == status) return;
    setState(() {
      _filters = _filters.copyWith(
        status: status,
        clearStatus: status == null,
        page: 1,
      );
    });
    _load(refresh: true);
  }

  void _openFilters() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => RentalFiltersSheet(
        initialFilters: _filters,
        onApply: (f) {
          setState(() => _filters = f.copyWith(limit: _pageSize, page: 1));
          _load(refresh: true);
        },
        onClear: () {
          setState(() {
            _filters = const RentalFilters(limit: _pageSize);
            _appliedSearch = '';
            _searchController.clear();
          });
          _load(refresh: true);
        },
      ),
    );
  }

  // ─── Ações por item ──────────────────────────────────────────────────────

  void _openDetails(Rental rental, {bool focusPayments = false}) {
    Navigator.of(context)
        .pushNamed(
          '/rentals/${rental.id}',
          arguments: focusPayments ? {'tab': 'payments'} : null,
        )
        .then((_) => _refreshAll());
  }

  void _openEdit(Rental rental) {
    Navigator.of(context)
        .pushNamed('/rentals/${rental.id}/edit')
        .then((_) => _refreshAll());
  }

  void _openCreate() {
    Navigator.of(context)
        .pushNamed('/rentals/create')
        .then((_) => _refreshAll());
  }

  void _openDashboard() {
    Navigator.of(context).pushNamed('/rentals/dashboard');
  }

  Future<void> _handleAction(Rental rental, RentalCardAction action) async {
    switch (action) {
      case RentalCardAction.details:
        _openDetails(rental);
        break;
      case RentalCardAction.payments:
        _openDetails(rental, focusPayments: true);
        break;
      case RentalCardAction.edit:
        _openEdit(rental);
        break;
      case RentalCardAction.approve:
        await _confirmApprove(rental);
        break;
      case RentalCardAction.reject:
        await _confirmReject(rental);
        break;
      case RentalCardAction.delete:
        await _confirmDelete(rental);
        break;
    }
  }

  Future<void> _confirmApprove(Rental rental) async {
    final ok = await _confirmDialog(
      title: 'Aprovar locação',
      message:
          'Deseja aprovar a locação de "${rental.tenantName}"? O aluguel será '
          'ativado e os pagamentos serão gerados conforme a configuração.',
      confirmLabel: 'Aprovar',
      icon: LucideIcons.check,
      destructive: false,
    );
    if (ok != true || !mounted) return;
    final res = await RentalService.instance.approve(rental.id);
    if (!mounted) return;
    _snack(
      res.success
          ? 'Locação aprovada com sucesso.'
          : (res.message ?? 'Erro ao aprovar locação.'),
      error: !res.success,
    );
    if (res.success) _refreshAll();
  }

  Future<void> _confirmReject(Rental rental) async {
    final ok = await _confirmDialog(
      title: 'Rejeitar locação',
      message:
          'Tem certeza que deseja rejeitar a locação de "${rental.tenantName}"?',
      confirmLabel: 'Rejeitar',
      icon: LucideIcons.x,
      destructive: true,
    );
    if (ok != true || !mounted) return;
    final res = await RentalService.instance.reject(rental.id);
    if (!mounted) return;
    _snack(
      res.success
          ? 'Locação rejeitada.'
          : (res.message ?? 'Erro ao rejeitar locação.'),
      error: !res.success,
    );
    if (res.success) _refreshAll();
  }

  Future<void> _confirmDelete(Rental rental) async {
    final ok = await _confirmDialog(
      title: 'Excluir locação',
      message:
          'Tem certeza que deseja excluir a locação de "${rental.tenantName}"? '
          'As cobranças pendentes serão canceladas no gateway de pagamento e '
          'todos os pagamentos associados serão removidos. Esta ação não '
          'poderá ser desfeita.',
      confirmLabel: 'Excluir',
      icon: LucideIcons.trash2,
      destructive: true,
    );
    if (ok != true || !mounted) return;
    final res = await RentalService.instance.delete(rental.id);
    if (!mounted) return;
    _snack(
      res.success
          ? 'Locação excluída.'
          : (res.message ?? 'Erro ao excluir locação.'),
      error: !res.success,
    );
    if (res.success) _refreshAll();
  }

  Future<bool?> _confirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required IconData icon,
    required bool destructive,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone = destructive
        ? (isDark ? AppColors.status.errorDarkMode : AppColors.status.error)
        : (isDark ? AppColors.status.greenDarkMode : AppColors.status.green);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ThemeHelpers.cardBackgroundColor(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: tone, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                  color: ThemeHelpers.textColor(ctx),
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.45,
            color: ThemeHelpers.textSecondaryColor(ctx),
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancelar',
              style: TextStyle(
                color: ThemeHelpers.textSecondaryColor(ctx),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: tone,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              confirmLabel,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  void _snack(String message, {bool error = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error
            ? (isDark ? AppColors.status.errorDarkMode : AppColors.status.error)
            : null,
      ),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canView) {
      return const AppScaffold(
        title: 'Locações',
        showBottomNavigation: false,
        body: _DeniedView(),
      );
    }
    return AppScaffold(
      title: 'Locações',
      showBottomNavigation: false,
      actions: [
        if (_canViewDashboard)
          IconButton(
            tooltip: 'Dashboard de locações',
            onPressed: _openDashboard,
            icon: Icon(
              LucideIcons.chartNoAxesColumn,
              size: 20,
              color: ThemeHelpers.textColor(context),
            ),
          ),
      ],
      body: RefreshIndicator(
        color: _accentColor(context),
        onRefresh: _refreshAll,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        _kPagePadH, _kPagePadTop, _kPagePadH, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHero(context),
                        const SizedBox(height: _kSectionGap),
                        _buildSearchRow(context),
                        const SizedBox(height: _kSectionGap),
                      ],
                    ),
                  ),
                  _buildStatusRail(context),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        _kPagePadH, _kSectionGap, _kPagePadH, _kPagePadBottom),
                    child: _buildBody(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Hero editorial ──────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accentColor(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;

    final stats = _stats;
    final hasAlert =
        stats != null && (stats.overduePayments > 0 || stats.expiringContracts > 0);
    final dot = hasAlert ? amber : emerald;

    final subtitle = stats == null
        ? 'Contratos de aluguel e pagamentos da sua carteira.'
        : hasAlert
            ? [
                if (stats.overduePayments > 0)
                  '${stats.overduePayments} pagamento${stats.overduePayments == 1 ? '' : 's'} atrasado${stats.overduePayments == 1 ? '' : 's'}',
                if (stats.expiringContracts > 0)
                  '${stats.expiringContracts} contrato${stats.expiringContracts == 1 ? '' : 's'} vencendo em 30 dias',
              ].join(' · ')
            : 'Carteira em dia — nenhum alerta no momento.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dot,
                  boxShadow: [
                    BoxShadow(
                      color: dot.withValues(alpha: 0.55),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'GESTÃO DE LOCAÇÕES',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.2,
                    fontSize: 11,
                  ),
                ),
              ),
              if (_canCreate)
                _HeroActionButton(
                  icon: LucideIcons.plus,
                  label: 'Nova',
                  accent: accent,
                  onTap: _openCreate,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$_total',
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
                  _total == 1 ? 'contrato' : 'contratos',
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
          if (_canViewDashboard) ...[
            const SizedBox(height: 18),
            _buildKpiStrip(context),
          ],
        ],
      ),
    );
  }

  Widget _buildKpiStrip(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final divider = ThemeHelpers.borderColor(context).withValues(alpha: 0.45);
    final stats = _stats ?? RentalDashboardData.zero;
    final canSeeMoney = _access.hasPermission(RentalPermissions.viewFinancials);

    final blocks = <Widget>[
      _heroKpiBlock(
        context,
        LucideIcons.circleCheckBig,
        'ATIVAS',
        _statsLoading ? '—' : '${stats.activeRentals}',
        '${stats.occupancyRate.toStringAsFixed(0)}% de ocupação',
        emerald,
      ),
      if (canSeeMoney)
        _heroKpiBlock(
          context,
          LucideIcons.banknote,
          'RECEITA/MÊS',
          _statsLoading ? '—' : _compact.format(stats.totalMonthlyRevenue),
          'média ${_compact.format(stats.averageRentalValue)}',
          amber,
        ),
      _heroKpiBlock(
        context,
        LucideIcons.triangleAlert,
        'ATRASADOS',
        _statsLoading ? '—' : '${stats.overduePayments}',
        '${stats.expiringContracts} vencendo em 30d',
        danger,
      ),
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

  Widget _heroKpiBlock(BuildContext context, IconData icon, String label,
      String value, String sub, Color tone) {
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
              value,
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

  // ─── Busca + filtros ─────────────────────────────────────────────────────

  Widget _buildSearchRow(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accentColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final cardColor = ThemeHelpers.cardBackgroundColor(context);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final advancedCount = _filters.advancedCount;
    final hasAdvanced = advancedCount > 0;

    return Row(
      children: [
        Expanded(child: _buildSearchField(context)),
        const SizedBox(width: 10),
        InkWell(
          onTap: _openFilters,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasAdvanced
                    ? accent.withValues(alpha: isDark ? 0.5 : 0.42)
                    : borderColor,
                width: hasAdvanced ? 1.4 : 1,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  LucideIcons.slidersHorizontal,
                  size: 19,
                  color: hasAdvanced ? accent : secondary,
                ),
                if (hasAdvanced)
                  Positioned(
                    top: 9,
                    right: 9,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration:
                          BoxDecoration(color: accent, shape: BoxShape.circle),
                      child: Text(
                        '$advancedCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accentColor(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final cardColor = ThemeHelpers.cardBackgroundColor(context);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final hasText = _searchController.text.isNotEmpty;
    final showAccent = _searchFocused || hasText;

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
            Icon(LucideIcons.search,
                size: 18, color: showAccent ? accent : secondary),
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
                  hintText: 'Inquilino, documento, endereço…',
                  hintStyle: TextStyle(
                    color: secondary.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w500,
                    fontSize: 13.5,
                  ),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
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

  // ─── Chips de status ─────────────────────────────────────────────────────

  Widget _buildStatusRail(BuildContext context) {
    final options = <(RentalStatus?, String)>[
      (null, 'Todos'),
      for (final s in RentalStatus.selectable) (s, s.label),
    ];
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(_kPagePadH, 0, _kPagePadH, 10),
        child: Row(
          children: [
            for (final (status, label) in options) ...[
              _StatusChip(
                label: label,
                tone: status == null
                    ? _accentColor(context)
                    : rentalStatusColor(context, status),
                selected: _filters.status == status,
                onTap: () => _selectStatus(status),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Corpo ───────────────────────────────────────────────────────────────

  Widget _buildBody(BuildContext context) {
    Widget child;
    if (_loading && _items.isEmpty) {
      child = _buildSkeleton();
    } else if (_error != null && _items.isEmpty) {
      child = _buildError(context, _error!);
    } else if (_items.isEmpty) {
      child = _buildEmpty(context);
    } else {
      child = _buildList(context);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPanelHeader(context),
        const SizedBox(height: 14),
        child,
      ],
    ).animate(key: ValueKey('panel-${_filters.status?.name ?? 'all'}')).fadeIn(
          duration: 240.ms,
        );
  }

  Widget _buildPanelHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final status = _filters.status;
    final tone = status == null
        ? _accentColor(context)
        : rentalStatusColor(context, status);
    final icon =
        status == null ? LucideIcons.keyRound : rentalStatusIcon(status);
    final eyebrow = status == null ? 'CARTEIRA' : status.label.toUpperCase();
    final title = status == null
        ? 'Todos os contratos'
        : switch (status) {
            RentalStatus.active => 'Contratos ativos',
            RentalStatus.pending => 'Contratos pendentes',
            RentalStatus.pendingApproval => 'Aguardando sua aprovação',
            RentalStatus.expired => 'Contratos expirados',
            RentalStatus.cancelled => 'Contratos cancelados',
            RentalStatus.unknown => 'Contratos',
          };
    final hint = status == RentalStatus.pendingApproval
        ? 'Locações criadas que dependem de aprovação para ativar.'
        : 'Gerencie contratos de aluguel e pagamentos.';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: tone.withValues(alpha: isDark ? 0.2 : 0.12),
          ),
          child: Icon(icon, color: tone, size: 20),
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
                      color: tone,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: tone.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    eyebrow,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
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

  Widget _buildList(BuildContext context) {
    final nodes = <Widget>[];
    var animIndex = 0;
    for (final rental in _items) {
      nodes.add(
        RentalCard(
          rental: rental,
          onTap: () => _openDetails(rental),
          onAction: (a) => _handleAction(rental, a),
          canManageWorkflows: _canManageWorkflows,
          canManagePayments: _canManagePayments,
          canUpdate: _canUpdate,
          canDelete: _canDelete,
        ).animate(key: ValueKey('r-${rental.id}')).fadeIn(
              delay: Duration(milliseconds: 30 * (animIndex++).clamp(0, 12)),
              duration: 220.ms,
            ),
      );
    }
    if (_hasMore) nodes.add(_buildLoadMore(context));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: nodes,
    );
  }

  Widget _buildLoadMore(BuildContext context) {
    final accent = _accentColor(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Center(
        child: _loadingMore
            ? SizedBox(
                width: 22,
                height: 22,
                child:
                    CircularProgressIndicator(strokeWidth: 2.2, color: accent),
              )
            : OutlinedButton.icon(
                onPressed: _loadMore,
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  side: BorderSide(color: accent.withValues(alpha: 0.45)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(LucideIcons.chevronDown, size: 16),
                label: const Text('Carregar mais'),
              ),
      ),
    );
  }

  // ─── Estados ─────────────────────────────────────────────────────────────

  Widget _buildSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(
        5,
        (_) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 48, height: 48, borderRadius: 13),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonText(width: 110, height: 16, borderRadius: 999),
                    SizedBox(height: 9),
                    SkeletonText(width: double.infinity, height: 14),
                    SizedBox(height: 6),
                    SkeletonText(width: 170, height: 12),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const SkeletonText(width: 74, height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    final status = _filters.status;
    final tone = status == null
        ? _accentColor(context)
        : rentalStatusColor(context, status);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hasSearch = _appliedSearch.trim().isNotEmpty;
    final hasAnyFilter = hasSearch || status != null || _filters.advancedCount > 0;
    final (icon, title, body) = hasSearch
        ? (
            LucideIcons.searchX,
            'Nada encontrado',
            'Nenhuma locação corresponde a "${_appliedSearch.trim()}".',
          )
        : status == RentalStatus.pendingApproval
            ? (
                LucideIcons.hourglass,
                'Nenhuma locação pendente de aprovação',
                'Quando houver aluguéis aguardando aprovação, eles aparecerão aqui.',
              )
            : hasAnyFilter
                ? (
                    LucideIcons.filterX,
                    'Nenhuma locação com esses filtros',
                    'Ajuste os filtros ou limpe para ver todos os contratos.',
                  )
                : (
                    LucideIcons.keyRound,
                    'Nenhum aluguel encontrado',
                    'Comece criando uma locação para gerenciar seus contratos e pagamentos.',
                  );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 4),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [
                tone.withValues(alpha: 0.18),
                tone.withValues(alpha: 0.06),
              ]),
              border: Border.all(color: tone.withValues(alpha: 0.32)),
            ),
            child: Icon(icon, color: tone, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondary,
              height: 1.4,
            ),
          ),
          if (!hasAnyFilter && _canCreate) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _openCreate,
              style: FilledButton.styleFrom(
                backgroundColor: _accentColor(context),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text(
                'Criar primeira locação',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, String message) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 4),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: danger.withValues(alpha: 0.12),
              border: Border.all(color: danger.withValues(alpha: 0.32)),
            ),
            child: Icon(LucideIcons.cloudOff, color: danger, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _load(refresh: true),
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}

// ─── Botão de ação do hero ───────────────────────────────────────────────────

class _HeroActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  const _HeroActionButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: isDark ? 0.18 : 0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Chip de status (rail horizontal) ────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String label;
  final Color tone;
  final bool selected;
  final VoidCallback onTap;

  const _StatusChip({
    required this.label,
    required this.tone,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final fg = selected
        ? tone
        : ThemeHelpers.textColor(context).withValues(alpha: 0.75);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? tone.withValues(alpha: isDark ? 0.18 : 0.1)
              : fieldFill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color:
                selected ? tone : ThemeHelpers.borderLightColor(context),
            width: selected ? 1.2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: fg,
            fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
            fontSize: 12.5,
            letterSpacing: -0.1,
          ),
        ),
      ),
    );
  }
}

class _DeniedView extends StatelessWidget {
  const _DeniedView();
  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.lock, size: 38, color: secondary),
            const SizedBox(height: 12),
            Text(
              'Você não tem acesso às locações.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Solicite ao administrador a permissão de visualizar locações.',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
