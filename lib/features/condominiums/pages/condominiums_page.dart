import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/shell_visual_tokens.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/shimmer_image.dart';
import '../condominium_routes.dart';
import '../models/condominium_models.dart';
import '../services/condominium_service.dart';
import '../widgets/estate_card.dart';
import '../widgets/estate_filters_sheet.dart';
import '../widgets/estate_shared.dart';

final _estateIntFormatter = NumberFormat.decimalPattern('pt_BR');

/// Aba de status da listagem (paridade com `filterStatus` do web,
/// default "Ativos").
enum _CondoTab { active, inactive, all }

class _TabState {
  List<Condominium> items = const [];
  bool loading = false;
  bool loadingMore = false;
  bool loaded = false;
  String? error;
  int page = 1;
  int totalPages = 1;
  int total = 0;
  bool get hasMore => page < totalPages;

  void reset() {
    items = const [];
    loaded = false;
    error = null;
    page = 1;
    totalPages = 1;
  }
}

/// Tela **Condomínios** — apresentação na linguagem do portfólio de Imóveis:
/// hero editorial (ícone gradient + eyebrow + título + subtítulo), busca com
/// botão de filtros acoplado, CTA primário, métricas clicáveis
/// (Total/Ativos/Inativos) que comandam as abas com sublinhado, cards row
/// densos com ações no próprio item e paginação por "Carregar mais".
class CondominiumsPage extends StatefulWidget {
  const CondominiumsPage({super.key});

  @override
  State<CondominiumsPage> createState() => _CondominiumsPageState();
}

class _CondominiumsPageState extends State<CondominiumsPage> {
  static const double _kHeaderPadH = 20;
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const int _pageSize = 20;

  static const _tabs = [_CondoTab.active, _CondoTab.inactive, _CondoTab.all];

  _CondoTab _activeTab = _CondoTab.active;
  final Map<_CondoTab, _TabState> _state = {
    _CondoTab.active: _TabState(),
    _CondoTab.inactive: _TabState(),
    _CondoTab.all: _TabState(),
  };

  /// Contagens globais (probe de 1 item por status) para hero + abas.
  int? _activeCount;
  int? _inactiveCount;

  /// Filtros do modal (cidade/UF/bairro/ordenação) — compartilhados pelas abas.
  EstateListFilters _filters = const EstateListFilters(limit: _pageSize);

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _appliedSearch = '';
  bool _searchFocused = false;

  bool get _canView =>
      ModuleAccessService.instance.hasCompanyModule('property_management') &&
      ModuleAccessService.instance.hasPermission('condominium:view');
  bool get _canCreate =>
      ModuleAccessService.instance.hasPermission('condominium:create');
  bool get _canEdit =>
      ModuleAccessService.instance.hasPermission('condominium:update');
  bool get _canDelete =>
      ModuleAccessService.instance.hasPermission('condominium:delete');

  Color _accent(BuildContext context) => EstateTones.blue(context);

  @override
  void initState() {
    super.initState();
    if (_canView) {
      _loadCounts();
      _loadTab(_CondoTab.active);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ─── Dados ───────────────────────────────────────────────────────────────

  EstateListFilters _filtersFor(_CondoTab tab, int page) {
    final search = _appliedSearch.trim().isEmpty ? null : _appliedSearch.trim();
    return _filters.copyWith(
      search: search,
      page: page,
      limit: _pageSize,
      isActive: switch (tab) {
        _CondoTab.active => true,
        _CondoTab.inactive => false,
        _CondoTab.all => null,
      },
      clearIsActive: tab == _CondoTab.all,
    );
  }

  Future<void> _loadCounts() async {
    final base = _filters.copyWith(
      search: _appliedSearch.trim().isEmpty ? null : _appliedSearch.trim(),
      page: 1,
      limit: 1,
    );
    final results = await Future.wait([
      CondominiumService.instance
          .getCondominiums(filters: base.copyWith(isActive: true)),
      CondominiumService.instance
          .getCondominiums(filters: base.copyWith(isActive: false)),
    ]);
    if (!mounted) return;
    setState(() {
      if (results[0].success && results[0].data != null) {
        _activeCount = results[0].data!.total;
      }
      if (results[1].success && results[1].data != null) {
        _inactiveCount = results[1].data!.total;
      }
    });
  }

  Future<void> _loadTab(_CondoTab tab, {bool refresh = false}) async {
    final st = _state[tab]!;
    setState(() {
      st.loading = true;
      if (refresh) st.error = null;
    });
    final res = await CondominiumService.instance
        .getCondominiums(filters: _filtersFor(tab, 1));
    if (!mounted) return;
    setState(() {
      st.loading = false;
      st.loaded = true;
      if (res.success && res.data != null) {
        st.items = res.data!.items;
        st.page = res.data!.page;
        st.totalPages = res.data!.totalPages;
        st.total = res.data!.total;
        st.error = null;
      } else {
        st.error = res.message ?? 'Erro ao carregar condomínios';
      }
    });
  }

  Future<void> _loadMore(_CondoTab tab) async {
    final st = _state[tab]!;
    if (st.loadingMore || !st.hasMore) return;
    setState(() => st.loadingMore = true);
    final res = await CondominiumService.instance
        .getCondominiums(filters: _filtersFor(tab, st.page + 1));
    if (!mounted) return;
    setState(() {
      st.loadingMore = false;
      if (res.success && res.data != null) {
        st.items = [...st.items, ...res.data!.items];
        st.page = res.data!.page;
        st.totalPages = res.data!.totalPages;
      }
    });
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _loadCounts(),
      _loadTab(_activeTab, refresh: true),
    ]);
  }

  void _reloadEverything() {
    setState(() {
      for (final s in _state.values) {
        s.reset();
      }
    });
    _loadCounts();
    _loadTab(_activeTab, refresh: true);
  }

  void _selectTab(_CondoTab tab) {
    if (tab == _activeTab) return;
    setState(() => _activeTab = tab);
    final st = _state[tab]!;
    if (!st.loaded && !st.loading) _loadTab(tab);
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final v = value.trim();
      if (v == _appliedSearch) return;
      _appliedSearch = v;
      _reloadEverything();
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    if (_appliedSearch.isEmpty) {
      setState(() {});
      return;
    }
    _appliedSearch = '';
    _reloadEverything();
  }

  void _clearFilters() {
    _filters = const EstateListFilters(limit: _pageSize);
    _reloadEverything();
  }

  void _openFilters() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => EstateFiltersSheet(
        initialFilters: _filters,
        accent: _accent(context),
        onApply: (f) {
          _filters = f;
          _reloadEverything();
        },
      ),
    );
  }

  Future<void> _goToCreate() async {
    final result = await Navigator.of(context)
        .pushNamed(CondominiumRoutes.condominiumCreate);
    if (result == true) _reloadEverything();
  }

  Future<void> _goToEdit(Condominium c) async {
    final result = await Navigator.of(context)
        .pushNamed(CondominiumRoutes.condominiumEdit(c.id));
    if (result == true) _reloadEverything();
  }

  Future<void> _confirmDelete(Condominium c) async {
    final danger = EstateTones.danger(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Excluir condomínio?',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.3),
        ),
        content: Text(
          '"${c.name}" será excluído. Se houver imóveis vinculados, a exclusão '
          'é bloqueada pelo sistema (use o painel web para migrar os imóveis).',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final res = await CondominiumService.instance.deleteCondominium(c.id);
    if (!mounted) return;
    if (res.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Condomínio excluído'),
          backgroundColor: AppColors.status.success,
        ),
      );
      _reloadEverything();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message ?? 'Erro ao excluir condomínio'),
          backgroundColor: AppColors.status.error,
        ),
      );
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canView) {
      return const AppScaffold(
        title: 'Condomínios',
        showBottomNavigation: false,
        body: _DeniedView(),
      );
    }
    return AppScaffold(
      title: 'Condomínios',
      showBottomNavigation: false,
      body: RefreshIndicator(
        color: _accent(context),
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
                        _kHeaderPadH, _kPagePadTop, _kHeaderPadH, 14),
                    child: _buildPortfolioHeader(context),
                  ),
                  _buildTabsRail(context),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        _kPagePadH, 14, _kPagePadH, _kPagePadBottom),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildListHeader(context),
                        const SizedBox(height: 10),
                        _buildActivePanel(context),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Hero (gramática do portfólio de Imóveis) ────────────────────────────

  Widget _buildPortfolioHeader(BuildContext context) {
    final hasSearch = _appliedSearch.trim().isNotEmpty;
    final hasFilters = _filters.activeCount > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _heroLeadingIcon(context),
            const SizedBox(width: 12),
            Expanded(child: _heroTitleBlock(context, hasSearch)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildSearchField(context)),
            const SizedBox(width: 10),
            _buildHeroFilterButton(context, hasFilters),
          ],
        ),
        if (_canCreate) ...[
          const SizedBox(height: 12),
          _buildPrimaryCta(
            context,
            icon: LucideIcons.plus,
            label: 'Novo condomínio',
            onTap: _goToCreate,
          ),
        ],
        const SizedBox(height: 14),
        _buildMetricsRow(context),
        if (hasSearch || hasFilters) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (hasSearch)
                _buildActiveContextChip(
                  context,
                  LucideIcons.search,
                  _appliedSearch,
                  onClear: _clearSearch,
                ),
              if (hasFilters)
                _buildActiveContextChip(
                  context,
                  LucideIcons.slidersHorizontal,
                  'Filtros aplicados',
                  onClear: _clearFilters,
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _heroLeadingIcon(BuildContext context) {
    final accent = _accent(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final deep = HSLColor.fromColor(accent)
        .withLightness(
            (HSLColor.fromColor(accent).lightness * 0.72).clamp(0.0, 1.0))
        .toColor();
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, deep],
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? accent.withValues(alpha: 0.30)
                : Colors.black.withValues(alpha: 0.12),
            blurRadius: isDark ? 14 : 10,
            offset: Offset(0, isDark ? 8 : 5),
          ),
        ],
      ),
      child: const Icon(LucideIcons.building2, color: Colors.white, size: 20),
    );
  }

  Widget _heroTitleBlock(BuildContext context, bool hasSearch) {
    final theme = Theme.of(context);
    final accent = _accent(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Text(
              hasSearch ? 'CONDOMÍNIOS · BUSCA' : 'CONDOMÍNIOS · PORTFÓLIO',
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w900,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          hasSearch ? 'Resultados da busca' : 'Portfólio de condomínios',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
            height: 1.05,
            color: ThemeHelpers.textColor(context),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Gerencie e vincule condomínios aos imóveis.',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ─── Busca (peso visual da tela de Imóveis) ──────────────────────────────

  Widget _buildSearchField(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accent(context);
    final hasText = _searchController.text.trim().isNotEmpty;
    final showAccent = _searchFocused || hasText;
    final fieldFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;

    return Focus(
      onFocusChange: (f) => setState(() => _searchFocused = f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: hasText
              ? Color.alphaBlend(
                  accent.withValues(alpha: isDark ? 0.08 : 0.04),
                  fieldFill,
                )
              : fieldFill,
          border: Border.all(
            color: showAccent
                ? accent.withValues(alpha: isDark ? 0.50 : 0.38)
                : ThemeHelpers.borderLightColor(context),
            width: showAccent ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(
              Icons.search_rounded,
              size: 21,
              color: showAccent
                  ? accent
                  : ThemeHelpers.textSecondaryColor(context),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                cursorColor: accent,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
                decoration: InputDecoration(
                  hintText: 'Buscar por nome, endereço, cidade…',
                  hintStyle: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w500,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 13),
                ),
                onChanged: (v) {
                  _onSearchChanged(v);
                  setState(() {});
                },
              ),
            ),
            if (hasText)
              IconButton(
                icon: Icon(
                  Icons.clear_rounded,
                  size: 18,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
                visualDensity: VisualDensity.compact,
                tooltip: 'Limpar busca',
                onPressed: _clearSearch,
              )
            else
              const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  /// Botão de filtros colado na busca — quadrado, com dot quando há filtro.
  Widget _buildHeroFilterButton(BuildContext context, bool active) {
    final accent = _accent(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor =
        active ? accent : ThemeHelpers.textSecondaryColor(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openFilters,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: active
                ? accent.withValues(alpha: isDark ? 0.16 : 0.09)
                : ShellVisualTokens.dashboardGlassFill(context),
            border: Border.all(
              color: active
                  ? accent.withValues(alpha: 0.5)
                  : ShellVisualTokens.dashboardGlassBorder(context),
              width: active ? 1.4 : 1,
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Icon(Icons.tune_rounded, size: 21, color: iconColor),
              ),
              if (active)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration:
                        BoxDecoration(color: accent, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// CTA primário full-width — mesma pegada do "Novo imóvel".
  Widget _buildPrimaryCta(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final accent = _accent(context);
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: accent,
          border: Border.all(color: accent),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 6),
              spreadRadius: -4,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 13.25,
                height: 1.15,
                letterSpacing: -0.1,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Métricas clicáveis (Total/Ativos/Inativos) ──────────────────────────

  Widget _buildMetricsRow(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accent(context);
    final total = (_activeCount == null && _inactiveCount == null)
        ? null
        : (_activeCount ?? 0) + (_inactiveCount ?? 0);

    String fmt(int? v) => v == null ? '—' : _estateIntFormatter.format(v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(LucideIcons.chartNoAxesColumn, size: 14, color: accent),
            const SizedBox(width: 6),
            Text(
              'VISÃO DA CARTEIRA',
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent,
                letterSpacing: 1.65,
                fontWeight: FontWeight.w900,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: EstateStatTile(
                label: 'Total',
                value: fmt(total),
                icon: LucideIcons.building2,
                accent: accent,
                selected: _activeTab == _CondoTab.all,
                onTap: () => _selectTab(_CondoTab.all),
              ),
            ),
            Expanded(
              child: EstateStatTile(
                label: 'Ativos',
                value: fmt(_activeCount),
                icon: LucideIcons.circleCheckBig,
                accent: EstateTones.green(context),
                selected: _activeTab == _CondoTab.active,
                onTap: () => _selectTab(_CondoTab.active),
              ),
            ),
            Expanded(
              child: EstateStatTile(
                label: 'Inativos',
                value: fmt(_inactiveCount),
                icon: LucideIcons.circleOff,
                accent: EstateTones.amber(context),
                selected: _activeTab == _CondoTab.inactive,
                onTap: () => _selectTab(_CondoTab.inactive),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActiveContextChip(
    BuildContext context,
    IconData icon,
    String label, {
    VoidCallback? onClear,
  }) {
    final theme = Theme.of(context);
    final accent = _accent(context);
    final chipMaxW =
        (MediaQuery.sizeOf(context).width * 0.52).clamp(96.0, 220.0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: accent),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: chipMaxW),
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onClear != null) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: onClear,
              borderRadius: BorderRadius.circular(10),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.close_rounded, size: 14),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Abas (sublinhado — escopo da carteira) ──────────────────────────────

  int? _tabCount(_CondoTab tab) {
    switch (tab) {
      case _CondoTab.active:
        return _activeCount;
      case _CondoTab.inactive:
        return _inactiveCount;
      case _CondoTab.all:
        if (_activeCount == null && _inactiveCount == null) return null;
        return (_activeCount ?? 0) + (_inactiveCount ?? 0);
    }
  }

  Color _tabColor(BuildContext context, _CondoTab tab) {
    switch (tab) {
      case _CondoTab.active:
        return EstateTones.green(context);
      case _CondoTab.inactive:
        return EstateTones.amber(context);
      case _CondoTab.all:
        return _accent(context);
    }
  }

  IconData _tabIcon(_CondoTab tab) {
    switch (tab) {
      case _CondoTab.active:
        return LucideIcons.circleCheckBig;
      case _CondoTab.inactive:
        return LucideIcons.circleOff;
      case _CondoTab.all:
        return LucideIcons.building2;
    }
  }

  String _tabLabel(_CondoTab tab) {
    switch (tab) {
      case _CondoTab.active:
        return 'Ativos';
      case _CondoTab.inactive:
        return 'Inativos';
      case _CondoTab.all:
        return 'Todos';
    }
  }

  Widget _buildTabsRail(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: _kPagePadH - 8),
      child: Row(
        children: [
          for (final tab in _tabs)
            Expanded(
              child: EstateFlushTab(
                icon: _tabIcon(tab),
                label: _tabLabel(tab),
                count: _tabCount(tab),
                tone: _tabColor(context, tab),
                selected: _activeTab == tab,
                onTap: () => _selectTab(tab),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Listagem ────────────────────────────────────────────────────────────

  /// Eyebrow "LISTAGEM · N carregados · pg X/Y" — contexto entre as abas
  /// e a lista, igual à tela de Imóveis.
  Widget _buildListHeader(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accent(context);
    final st = _state[_activeTab]!;
    final n = st.items.length;
    return Row(
      children: [
        Icon(Icons.view_list_rounded, size: 14, color: accent),
        const SizedBox(width: 6),
        Text(
          'LISTAGEM',
          style: theme.textTheme.labelSmall?.copyWith(
            color: accent,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.65,
            fontSize: 10.5,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '· $n condomínio${n == 1 ? "" : "s"} carregado${n == 1 ? "" : "s"}'
            '${st.totalPages > 1 ? " · pg ${st.page}/${st.totalPages}" : ""}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActivePanel(BuildContext context) {
    final st = _state[_activeTab]!;
    Widget child;
    if (st.loading && st.items.isEmpty) {
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(5, (_) => const EstateCardSkeleton()),
      );
    } else if (st.error != null && st.items.isEmpty) {
      child = EstateErrorState(
        message: st.error!,
        onRetry: () => _loadTab(_activeTab, refresh: true),
      );
    } else if (st.items.isEmpty) {
      child = _buildEmpty(context, _activeTab);
    } else {
      child = _buildList(context, _activeTab, st);
    }

    return Column(
      key: ValueKey('panel-${_activeTab.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [child],
    ).animate(key: ValueKey('panel-${_activeTab.name}')).fadeIn(
          duration: 240.ms,
        );
  }

  Widget _buildList(BuildContext context, _CondoTab tab, _TabState st) {
    final nodes = <Widget>[];
    var animIndex = 0;
    for (final c in st.items) {
      nodes.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: EstateCard(
            name: c.name,
            imageUrl: c.mainImageUrl,
            photoCount: c.activeImages.length,
            isActive: c.isActive,
            typeIcon: LucideIcons.building2,
            typeLabel: 'Condomínio',
            hasCnpj: (c.cnpj ?? '').trim().isNotEmpty,
            addressLine: c.fullAddressLine,
            cityLine: c.cityState,
            specs: _specsFor(c),
            footerPill: _completenessPill(c),
            fallbackIcon: LucideIcons.building2,
            accent: _accent(context),
            onTap: () => _showDetail(c),
            onMenu: () => _showQuickActions(c),
          ).animate(key: ValueKey('condo-${c.id}')).fadeIn(
                delay: Duration(milliseconds: 30 * (animIndex++).clamp(0, 12)),
                duration: 220.ms,
              ),
        ),
      );
    }

    if (st.hasMore) {
      final accent = _accent(context);
      nodes.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Center(
            child: st.loadingMore
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: accent),
                  )
                : OutlinedButton.icon(
                    onPressed: () => _loadMore(tab),
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
        ),
      );
    }

    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: nodes);
  }

  /// Bits informativos do row — CEP, site e última atualização.
  List<EstateSpecBit> _specsFor(Condominium c) {
    final bits = <EstateSpecBit>[];
    if (c.zipCode.trim().isNotEmpty) {
      bits.add(EstateSpecBit(
        icon: LucideIcons.mapPinned,
        label: 'CEP ${c.zipCode.trim()}',
      ));
    }
    final host = websiteHost(c.website);
    if (host.isNotEmpty) {
      bits.add(EstateSpecBit(icon: LucideIcons.globe, label: host));
    }
    if (c.updatedAt != null) {
      bits.add(EstateSpecBit(
        icon: LucideIcons.history,
        label: DateFormat('dd/MM/yyyy', 'pt_BR').format(c.updatedAt!.toLocal()),
      ));
    }
    return bits;
  }

  /// Pill de completude do cadastro — cor por significado (verde ≥75,
  /// âmbar ≥45, neutro abaixo).
  EstateCardChip _completenessPill(Condominium c) {
    final pct = c.completenessPct;
    return EstateCardChip(
      icon: LucideIcons.chartNoAxesColumn,
      label: '$pct%',
      tone: pct >= 75
          ? EstateTones.green
          : pct >= 45
              ? EstateTones.amber
              : (ctx) => ThemeHelpers.textSecondaryColor(ctx),
    );
  }

  /// Ações no próprio item — kebab/long-press abre o sheet de ações rápidas
  /// (mesma gramática do menu contextual do card de imóvel).
  void _showQuickActions(Condominium c) {
    EstateQuickActionsSheet.show(
      context,
      accent: _accent(context),
      title: c.name,
      meta: [c.fullAddressLine, c.cityState]
          .where((s) => s.trim().isNotEmpty)
          .join(' · '),
      actions: [
        EstateQuickAction(
          icon: LucideIcons.layoutGrid,
          label: 'Ver ficha completa',
          subtitle: 'Endereço, contato, fotos e auditoria',
          color: const Color(0xFF0891B2),
          onTap: () => _showDetail(c),
        ),
        if (_canEdit)
          EstateQuickAction(
            icon: LucideIcons.pencil,
            label: 'Editar condomínio',
            subtitle: 'Dados, endereço e galeria',
            color: const Color(0xFF6366F1),
            onTap: () => _goToEdit(c),
          ),
        if (_canDelete)
          EstateQuickAction(
            icon: LucideIcons.trash2,
            label: 'Excluir permanentemente',
            subtitle: 'Remove o condomínio da base da empresa',
            color: EstateTones.danger(context),
            destructive: true,
            onTap: () => _confirmDelete(c),
          ),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context, _CondoTab tab) {
    final hasSearch = _appliedSearch.trim().isNotEmpty;
    if (hasSearch || _filters.activeCount > 0) {
      return EstateEmptyState(
        icon: LucideIcons.searchX,
        title: 'Nada encontrado',
        body: hasSearch
            ? 'Nenhum condomínio corresponde a "${_appliedSearch.trim()}".'
            : 'Nenhum condomínio corresponde aos filtros aplicados.',
        tone: _accent(context),
      );
    }
    final (icon, title, body) = switch (tab) {
      _CondoTab.active => (
          LucideIcons.building2,
          'Nenhum condomínio ativo',
          'Cadastre um condomínio para vincular aos imóveis da carteira.',
        ),
      _CondoTab.inactive => (
          LucideIcons.circleOff,
          'Nenhum inativo',
          'Condomínios desativados aparecem aqui.',
        ),
      _CondoTab.all => (
          LucideIcons.building2,
          'Nenhum condomínio',
          'Cadastre o primeiro condomínio da empresa.',
        ),
    };
    return EstateEmptyState(
      icon: icon,
      title: title,
      body: body,
      tone: _tabColor(context, tab),
      action: _canCreate && tab != _CondoTab.inactive
          ? FilledButton.icon(
              onPressed: _goToCreate,
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('Novo condomínio'),
              style: FilledButton.styleFrom(
                backgroundColor: _accent(context),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            )
          : null,
    );
  }

  // ─── Detalhe (bottom sheet) ──────────────────────────────────────────────

  void _showDetail(Condominium c) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => _CondominiumDetailSheet(
        condominium: c,
        accent: _accent(context),
        onEdit: _canEdit
            ? () {
                Navigator.of(ctx).pop();
                _goToEdit(c);
              }
            : null,
      ),
    );
  }
}

// ─── Sheet de detalhe ────────────────────────────────────────────────────────

class _CondominiumDetailSheet extends StatelessWidget {
  const _CondominiumDetailSheet({
    required this.condominium,
    required this.accent,
    this.onEdit,
  });

  final Condominium condominium;
  final Color accent;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final c = condominium;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final statusTone =
        c.isActive ? EstateTones.green(context) : EstateTones.amber(context);
    final fmt = DateFormat('dd/MM/yyyy', 'pt_BR');
    final photos = c.activeImages;

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.22 : 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.16),
            blurRadius: 28,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: secondary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        color: accent.withValues(alpha: isDark ? 0.18 : 0.1),
                        border:
                            Border.all(color: accent.withValues(alpha: 0.3)),
                      ),
                      child:
                          Icon(LucideIcons.building2, color: accent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: ThemeHelpers.textColor(context),
                              letterSpacing: -0.3,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              EstateMiniPill(
                                label: c.isActive ? 'Ativo' : 'Inativo',
                                icon: c.isActive
                                    ? LucideIcons.circleCheckBig
                                    : LucideIcons.circleOff,
                                tone: statusTone,
                              ),
                              EstateMiniPill(
                                label: '${c.completenessPct}% completo',
                                icon: LucideIcons.chartNoAxesColumn,
                                tone: secondary,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (photos.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 84,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: photos.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 8),
                      itemBuilder: (_, i) => ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ShimmerImage(
                          imageUrl: photos[i].fileUrl,
                          width: 112,
                          height: 84,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ],
                if ((c.description ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    c.description!.trim(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      height: 1.45,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _divider(context),
                EstateInfoRow(
                  label: 'Endereço',
                  value: c.fullAddressLine,
                  icon: LucideIcons.mapPin,
                ),
                EstateInfoRow(
                  label: 'Cidade/UF',
                  value: c.cityState.isEmpty ? '—' : c.cityState,
                ),
                EstateInfoRow(
                  label: 'CEP',
                  value: c.zipCode.trim().isEmpty ? '—' : c.zipCode,
                ),
                _divider(context),
                EstateInfoRow(
                  label: 'Telefone',
                  value: (c.phone ?? '').trim().isEmpty ? '—' : c.phone!.trim(),
                  icon: LucideIcons.phone,
                ),
                EstateInfoRow(
                  label: 'E-mail',
                  value: (c.email ?? '').trim().isEmpty ? '—' : c.email!.trim(),
                  icon: LucideIcons.mail,
                ),
                EstateInfoRow(
                  label: 'CNPJ',
                  value: formatCnpjPretty(c.cnpj).isEmpty
                      ? '—'
                      : formatCnpjPretty(c.cnpj),
                  icon: LucideIcons.landmark,
                ),
                EstateInfoRow(
                  label: 'Site',
                  value: websiteHost(c.website).isEmpty
                      ? '—'
                      : websiteHost(c.website),
                  icon: LucideIcons.globe,
                ),
                _divider(context),
                if (c.createdAt != null)
                  EstateInfoRow(
                    label: 'Criado em',
                    value: fmt.format(c.createdAt!.toLocal()),
                    icon: LucideIcons.calendarPlus,
                  ),
                if (c.updatedAt != null)
                  EstateInfoRow(
                    label: 'Atualizado em',
                    value: fmt.format(c.updatedAt!.toLocal()),
                    icon: LucideIcons.history,
                  ),
                if (onEdit != null) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(LucideIcons.pencil, size: 16),
                      label: const Text('Editar condomínio'),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(fontWeight: FontWeight.w800),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
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

  Widget _divider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        height: 1,
        color: ThemeHelpers.borderLightColor(context),
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
              'Você não tem acesso aos condomínios.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Solicite ao administrador a permissão de visualizar condomínios.',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
