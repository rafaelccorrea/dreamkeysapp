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
import '../models/asset_models.dart';
import '../services/asset_service.dart';
import '../widgets/asset_card.dart';
import '../widgets/asset_filters_drawer.dart';

final NumberFormat _compact = NumberFormat.compactCurrency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 1,
);

/// Aba ativa (atalho de status). O filtro de situação do modal, quando
/// definido, tem precedência e devolve a aba para "Todos".
enum _AssetTab { all, available, inUse }

/// Tela **Patrimônio** — inventário de bens da empresa. Mesmo DNA refinado de
/// Comissões: hero editorial com KPIs (stats do backend), busca flush
/// server-side, abas flush com contagem e paginação por "Carregar mais".
/// Módulo `asset_management`; permissão `asset:view`.
class AssetsPage extends StatefulWidget {
  const AssetsPage({super.key});

  @override
  State<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends State<AssetsPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 104;
  static const double _kSectionGap = 12;
  static const int _pageSize = 20;

  static const _tabs = [_AssetTab.all, _AssetTab.available, _AssetTab.inUse];

  _AssetTab _activeTab = _AssetTab.all;

  List<Asset> _items = const [];
  int _total = 0;
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  AssetStats _stats = AssetStats.zero;
  bool _statsLoading = true;

  AssetDrawerFilters _drawerFilters = const AssetDrawerFilters();

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _appliedSearch = '';
  bool _searchFocused = false;

  bool get _canView =>
      ModuleAccessService.instance.hasCompanyModule('asset_management') &&
      ModuleAccessService.instance.hasPermission('asset:view');

  bool get _canCreate =>
      ModuleAccessService.instance.hasPermission('asset:create');

  @override
  void initState() {
    super.initState();
    if (_canView) {
      _loadStats();
      _load();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ─── Cores ───────────────────────────────────────────────────────────────

  Color _accentColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
  }

  Color _tabColor(BuildContext context, _AssetTab tab) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (tab) {
      case _AssetTab.all:
        return _accentColor(context);
      case _AssetTab.available:
        return isDark
            ? AppColors.status.greenDarkMode
            : AppColors.status.green;
      case _AssetTab.inUse:
        return isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    }
  }

  // ─── Dados ───────────────────────────────────────────────────────────────

  AssetStatus? get _appliedStatus {
    if (_drawerFilters.status != null) return _drawerFilters.status;
    switch (_activeTab) {
      case _AssetTab.all:
        return null;
      case _AssetTab.available:
        return AssetStatus.available;
      case _AssetTab.inUse:
        return AssetStatus.inUse;
    }
  }

  AssetFilters _filtersFor(int page) {
    final search = _appliedSearch.trim();
    return AssetFilters(
      status: _appliedStatus,
      category: _drawerFilters.category,
      onlyMyData: _drawerFilters.onlyMyData,
      search: search.isEmpty ? null : search,
      page: page,
      limit: _pageSize,
    );
  }

  bool get _hasMore => _items.length < _total;

  Future<void> _loadStats() async {
    setState(() => _statsLoading = true);
    final res = await AssetService.instance.getStats();
    if (!mounted) return;
    setState(() {
      _statsLoading = false;
      if (res.success && res.data != null) _stats = res.data!;
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final res =
        await AssetService.instance.getAssets(filters: _filtersFor(1));
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _items = res.data!.assets;
        _total = res.data!.total;
        _page = 1;
        _error = null;
      } else {
        _error = res.message ?? 'Erro ao carregar patrimônio';
      }
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final res = await AssetService.instance
        .getAssets(filters: _filtersFor(_page + 1));
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (res.success && res.data != null) {
        _items = [..._items, ...res.data!.assets];
        _total = res.data!.total;
        _page += 1;
      }
    });
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadStats(), _load(silent: true)]);
  }

  void _selectTab(_AssetTab tab) {
    if (tab == _activeTab) return;
    setState(() {
      _activeTab = tab;
      // Atalho de status na aba limpa a situação escolhida no modal.
      if (_drawerFilters.status != null) {
        _drawerFilters = AssetDrawerFilters(
          category: _drawerFilters.category,
          onlyMyData: _drawerFilters.onlyMyData,
        );
      }
    });
    _load();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final v = value.trim();
      if (v == _appliedSearch) return;
      setState(() => _appliedSearch = v);
      _load();
    });
  }

  void _openFilters() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => AssetFiltersDrawer(
        initialFilters: _drawerFilters,
        onApply: (filters) {
          setState(() {
            _drawerFilters = filters;
            // Situação do modal manda — devolve a aba para "Todos".
            if (filters.status != null) _activeTab = _AssetTab.all;
          });
          _load();
        },
        onClear: () {
          setState(() => _drawerFilters = const AssetDrawerFilters());
          _load();
        },
      ),
    );
  }

  Future<void> _openCreate() async {
    await Navigator.of(context).pushNamed('/assets/create');
    if (mounted) _refreshAll();
  }

  Future<void> _openDetails(Asset asset) async {
    await Navigator.of(context).pushNamed('/assets/${asset.id}');
    if (mounted) _refreshAll();
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canView) {
      return const AppScaffold(
        title: 'Patrimônio',
        showBottomNavigation: false,
        body: _DeniedView(),
      );
    }
    final accent = _accentColor(context);
    return AppScaffold(
      title: 'Patrimônio',
      showBottomNavigation: false,
      body: Stack(
        children: [
          RefreshIndicator(
            color: accent,
            onRefresh: _refreshAll,
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
                      _buildTabsRail(context),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(_kPagePadH,
                            _kSectionGap, _kPagePadH, _kPagePadBottom),
                        child: _buildActivePanel(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_canCreate)
            Positioned(
              right: 16,
              bottom: 24,
              child: FloatingActionButton.extended(
                heroTag: 'assets-fab',
                onPressed: _openCreate,
                backgroundColor: accent,
                foregroundColor: Colors.white,
                elevation: 3,
                icon: const Icon(LucideIcons.plus, size: 19),
                label: const Text(
                  'Novo item',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
        ],
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
    final blue = isDark ? AppColors.status.infoDarkMode : AppColors.status.info;

    final total = _stats.total;
    final maintenance = _stats.countFor(AssetStatus.maintenance);
    final lost = _stats.countFor(AssetStatus.lost);
    final attention = maintenance + lost;
    final dot = attention > 0 ? amber : emerald;
    final subtitle = total == 0
        ? 'Cadastre os bens da empresa para controlar o inventário.'
        : attention > 0
            ? '${_compact.format(_stats.totalValue)} em bens · '
                '$attention ite${attention == 1 ? 'm exige' : 'ns exigem'} atenção'
            : '${_compact.format(_stats.totalValue)} em bens — tudo em ordem.';

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
              Text(
                'PATRIMÔNIO',
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _statsLoading ? '—' : '$total',
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
                  total == 1 ? 'item no acervo' : 'itens no acervo',
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
          const SizedBox(height: 18),
          _buildKpiStrip(context, emerald, blue, amber),
        ],
      ),
    );
  }

  Widget _buildKpiStrip(
      BuildContext context, Color emerald, Color blue, Color amber) {
    final divider = ThemeHelpers.borderColor(context).withValues(alpha: 0.45);
    final available = _stats.countFor(AssetStatus.available);
    final inUse = _stats.countFor(AssetStatus.inUse);
    final maintenance = _stats.countFor(AssetStatus.maintenance);
    final blocks = <Widget>[
      _heroKpiBlock(context, LucideIcons.circleCheckBig, 'DISPONÍVEIS',
          '$available', 'prontos para uso', emerald),
      _heroKpiBlock(context, LucideIcons.userCheck, 'EM USO', '$inUse',
          'com colaboradores', blue),
      _heroKpiBlock(context, LucideIcons.wrench, 'MANUTENÇÃO', '$maintenance',
          'em reparo', amber),
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
              _statsLoading ? '—' : value,
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

  // ─── Busca flush + botão de filtros ──────────────────────────────────────

  Widget _buildSearchRow(BuildContext context) {
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
    final filterCount = _drawerFilters.activeCount;
    final filterActive = filterCount > 0;

    return Row(
      children: [
        Expanded(
          child: Focus(
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
                          color:
                              accent.withValues(alpha: isDark ? 0.18 : 0.12),
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
                        hintText: 'Buscar por nome, série…',
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
          ),
        ),
        const SizedBox(width: 10),
        InkWell(
          onTap: _openFilters,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: filterActive
                  ? accent.withValues(alpha: isDark ? 0.18 : 0.1)
                  : cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: filterActive
                    ? accent.withValues(alpha: 0.5)
                    : borderColor,
                width: filterActive ? 1.4 : 1,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  LucideIcons.slidersHorizontal,
                  size: 19,
                  color: filterActive ? accent : secondary,
                ),
                if (filterActive)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(3.5),
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$filterCount',
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

  // ─── Abas flush ──────────────────────────────────────────────────────────

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
              child: _FlushTab(
                icon: _tabIcon(tab),
                label: _tabLabel(tab),
                count: _tabCount(tab),
                tone: _tabColor(context, tab),
                selected:
                    _activeTab == tab && _drawerFilters.status == null,
                onTap: () => _selectTab(tab),
              ),
            ),
        ],
      ),
    );
  }

  IconData _tabIcon(_AssetTab tab) {
    switch (tab) {
      case _AssetTab.all:
        return LucideIcons.package;
      case _AssetTab.available:
        return LucideIcons.circleCheckBig;
      case _AssetTab.inUse:
        return LucideIcons.userCheck;
    }
  }

  String _tabLabel(_AssetTab tab) {
    switch (tab) {
      case _AssetTab.all:
        return 'Todos';
      case _AssetTab.available:
        return 'Disponíveis';
      case _AssetTab.inUse:
        return 'Em uso';
    }
  }

  int _tabCount(_AssetTab tab) {
    switch (tab) {
      case _AssetTab.all:
        return _stats.total;
      case _AssetTab.available:
        return _stats.countFor(AssetStatus.available);
      case _AssetTab.inUse:
        return _stats.countFor(AssetStatus.inUse);
    }
  }

  // ─── Painel ativo ────────────────────────────────────────────────────────

  ({IconData icon, String eyebrow, String title, String hint}) _panelMeta() {
    if (_drawerFilters.status != null) {
      final s = _drawerFilters.status!;
      return (
        icon: LucideIcons.listFilter,
        eyebrow: s.label.toUpperCase(),
        title: 'Itens com situação "${s.label}"',
        hint: 'Filtro de situação aplicado pelo modal de filtros.',
      );
    }
    switch (_activeTab) {
      case _AssetTab.all:
        return (
          icon: LucideIcons.package,
          eyebrow: 'INVENTÁRIO',
          title: 'Todos os itens',
          hint: 'O acervo completo da empresa, do mais recente ao mais antigo.',
        );
      case _AssetTab.available:
        return (
          icon: LucideIcons.circleCheckBig,
          eyebrow: 'DISPONÍVEIS',
          title: 'Prontos para uso',
          hint: 'Itens livres, sem vínculo com colaboradores.',
        );
      case _AssetTab.inUse:
        return (
          icon: LucideIcons.userCheck,
          eyebrow: 'EM USO',
          title: 'Com colaboradores',
          hint: 'Itens atualmente vinculados a alguém da equipe.',
        );
    }
  }

  Widget _buildActivePanel(BuildContext context) {
    final tone = _drawerFilters.status != null
        ? _accentColor(context)
        : _tabColor(context, _activeTab);
    Widget child;
    if (_loading && _items.isEmpty) {
      child = _buildSkeleton();
    } else if (_error != null && _items.isEmpty) {
      child = _buildError(context, _error!);
    } else if (_items.isEmpty) {
      child = _buildEmpty(context, tone);
    } else {
      var animIndex = 0;
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final a in _items)
            AssetCard(
              asset: a,
              onTap: () => _openDetails(a),
            ).animate(key: ValueKey('a-${a.id}')).fadeIn(
                  delay:
                      Duration(milliseconds: 30 * (animIndex++).clamp(0, 12)),
                  duration: 220.ms,
                ),
          if (_hasMore) _buildLoadMore(context),
        ],
      );
    }

    final meta = _panelMeta();
    final key = 'panel-${_activeTab.name}-${_drawerFilters.status?.name}';
    return Column(
      key: ValueKey(key),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPanelHeader(context, meta, tone),
        const SizedBox(height: 14),
        child,
      ],
    ).animate(key: ValueKey(key)).fadeIn(duration: 240.ms);
  }

  Widget _buildPanelHeader(
      BuildContext context,
      ({IconData icon, String eyebrow, String title, String hint}) meta,
      Color tone) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
          child: Icon(meta.icon, color: tone, size: 20),
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
                    meta.eyebrow,
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
              SkeletonBox(width: 44, height: 44, borderRadius: 13),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonText(width: 96, height: 16, borderRadius: 999),
                    SizedBox(height: 9),
                    SkeletonText(width: double.infinity, height: 14),
                    SizedBox(height: 6),
                    SkeletonText(width: 150, height: 12),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const SkeletonText(width: 72, height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, Color tone) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hasQuery = _appliedSearch.trim().isNotEmpty ||
        _drawerFilters.activeCount > 0 ||
        _activeTab != _AssetTab.all;
    final (icon, title, body) = hasQuery
        ? (
            LucideIcons.searchX,
            'Nada encontrado',
            'Nenhum item corresponde à busca ou aos filtros aplicados.',
          )
        : (
            LucideIcons.packageOpen,
            'Acervo vazio',
            _canCreate
                ? 'Toque em "Novo item" para cadastrar o primeiro bem da empresa.'
                : 'Nenhum bem patrimonial cadastrado até o momento.',
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
            onPressed: () => _load(),
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}

// ─── Aba flush (ícone + rótulo + contagem + sublinhado) ──────────────────────

class _FlushTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color tone;
  final bool selected;
  final VoidCallback onTap;

  const _FlushTab({
    required this.icon,
    required this.label,
    required this.count,
    required this.tone,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: fg),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      maxLines: 1,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: fg,
                        fontWeight:
                            selected ? FontWeight.w900 : FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: tone.withValues(alpha: selected ? 0.18 : 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: selected
                                ? tone
                                : ThemeHelpers.textSecondaryColor(context),
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
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
              'Você não tem acesso ao patrimônio.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Solicite ao administrador a permissão de visualizar o patrimônio.',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
