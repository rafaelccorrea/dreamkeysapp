import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../condominium_routes.dart';
import '../models/condominium_models.dart';
import '../models/development_models.dart';
import '../services/development_service.dart';
import '../widgets/estate_card.dart';
import '../widgets/estate_filters_sheet.dart';
import '../widgets/estate_shared.dart';

enum _DevTab { active, inactive, all }

class _TabState {
  List<Development> items = const [];
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

/// Tela **Empreendimentos** — porta a `EmpreendimentosPage` do imobx-front.
/// Mesma gramática flush de Condomínios (hero + pills + busca + abas com
/// sublinhado), com personalidade própria (tom violeta e chip de material
/// da equipe). O toque no card abre a página de detalhe.
class DevelopmentsPage extends StatefulWidget {
  const DevelopmentsPage({super.key});

  @override
  State<DevelopmentsPage> createState() => _DevelopmentsPageState();
}

class _DevelopmentsPageState extends State<DevelopmentsPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const double _kSectionGap = 12;
  static const int _pageSize = 20;

  static const _tabs = [_DevTab.active, _DevTab.inactive, _DevTab.all];

  _DevTab _activeTab = _DevTab.active;
  final Map<_DevTab, _TabState> _state = {
    _DevTab.active: _TabState(),
    _DevTab.inactive: _TabState(),
    _DevTab.all: _TabState(),
  };

  int? _activeCount;
  int? _inactiveCount;

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

  Color _accent(BuildContext context) => EstateTones.purple(context);

  @override
  void initState() {
    super.initState();
    if (_canView) {
      _loadCounts();
      _loadTab(_DevTab.active);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ─── Dados ───────────────────────────────────────────────────────────────

  EstateListFilters _filtersFor(_DevTab tab, int page) {
    final search = _appliedSearch.trim().isEmpty ? null : _appliedSearch.trim();
    return _filters.copyWith(
      search: search,
      page: page,
      limit: _pageSize,
      isActive: switch (tab) {
        _DevTab.active => true,
        _DevTab.inactive => false,
        _DevTab.all => null,
      },
      clearIsActive: tab == _DevTab.all,
    );
  }

  /// Paridade com o web: o status é reforçado no cliente mesmo que a API
  /// ignore o parâmetro `isActive`.
  List<Development> _refine(_DevTab tab, List<Development> list) {
    switch (tab) {
      case _DevTab.active:
        return list.where((d) => d.isActive).toList();
      case _DevTab.inactive:
        return list.where((d) => !d.isActive).toList();
      case _DevTab.all:
        return list;
    }
  }

  Future<void> _loadCounts() async {
    final base = _filters.copyWith(
      search: _appliedSearch.trim().isEmpty ? null : _appliedSearch.trim(),
      page: 1,
      limit: 1,
    );
    final results = await Future.wait([
      DevelopmentService.instance
          .getDevelopments(filters: base.copyWith(isActive: true)),
      DevelopmentService.instance
          .getDevelopments(filters: base.copyWith(isActive: false)),
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

  Future<void> _loadTab(_DevTab tab, {bool refresh = false}) async {
    final st = _state[tab]!;
    setState(() {
      st.loading = true;
      if (refresh) st.error = null;
    });
    final res = await DevelopmentService.instance
        .getDevelopments(filters: _filtersFor(tab, 1));
    if (!mounted) return;
    setState(() {
      st.loading = false;
      st.loaded = true;
      if (res.success && res.data != null) {
        st.items = _refine(tab, res.data!.items);
        st.page = res.data!.page;
        st.totalPages = res.data!.totalPages;
        st.total = res.data!.total;
        st.error = null;
      } else {
        st.error = res.message ?? 'Erro ao carregar empreendimentos';
      }
    });
  }

  Future<void> _loadMore(_DevTab tab) async {
    final st = _state[tab]!;
    if (st.loadingMore || !st.hasMore) return;
    setState(() => st.loadingMore = true);
    final res = await DevelopmentService.instance
        .getDevelopments(filters: _filtersFor(tab, st.page + 1));
    if (!mounted) return;
    setState(() {
      st.loadingMore = false;
      if (res.success && res.data != null) {
        st.items = [...st.items, ..._refine(tab, res.data!.items)];
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

  void _selectTab(_DevTab tab) {
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
        .pushNamed(CondominiumRoutes.developmentCreate);
    if (result == true) _reloadEverything();
  }

  Future<void> _goToEdit(Development d) async {
    final result = await Navigator.of(context)
        .pushNamed(CondominiumRoutes.developmentEdit(d.id));
    if (result == true) _reloadEverything();
  }

  Future<void> _goToDetail(Development d) async {
    final result = await Navigator.of(context)
        .pushNamed(CondominiumRoutes.developmentDetails(d.id));
    if (result == true) _reloadEverything();
  }

  Future<void> _confirmDelete(Development d) async {
    final danger = EstateTones.danger(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Excluir empreendimento?',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.3),
        ),
        content: Text(
          '"${d.name}" será excluído. Essa ação não pode ser desfeita.',
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

    final res = await DevelopmentService.instance.deleteDevelopment(d.id);
    if (!mounted) return;
    if (res.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Empreendimento excluído'),
          backgroundColor: AppColors.status.success,
        ),
      );
      _reloadEverything();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message ?? 'Erro ao excluir empreendimento'),
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
        title: 'Empreendimentos',
        showBottomNavigation: false,
        body: _DeniedView(),
      );
    }
    return AppScaffold(
      title: 'Empreendimentos',
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
                        _kPagePadH, _kPagePadTop, _kPagePadH, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHero(context),
                        const SizedBox(height: 14),
                        _buildActionsRow(context),
                        const SizedBox(height: _kSectionGap),
                        _buildSearchField(context),
                        const SizedBox(height: _kSectionGap),
                      ],
                    ),
                  ),
                  _buildTabsRail(context),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        _kPagePadH, _kSectionGap, _kPagePadH, _kPagePadBottom),
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

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accent(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final green = EstateTones.green(context);
    final amber = EstateTones.amber(context);

    final total = (_activeCount ?? 0) + (_inactiveCount ?? 0);
    final loadedCounts = _activeCount != null || _inactiveCount != null;
    final dot = (_inactiveCount ?? 0) > 0 ? amber : green;
    final subtitle = !loadedCounts
        ? 'Carregando os empreendimentos da empresa…'
        : total == 0
            ? 'Cadastre empreendimentos e o material de vendas da equipe.'
            : '${_activeCount ?? 0} ativo${(_activeCount ?? 0) == 1 ? '' : 's'}'
                ' · ${_inactiveCount ?? 0} inativo${(_inactiveCount ?? 0) == 1 ? '' : 's'}';

    return Padding(
      padding: const EdgeInsets.only(top: 4),
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
                'EMPREENDIMENTOS',
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
                loadedCounts ? '$total' : '—',
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
                  total == 1 ? 'empreendimento' : 'empreendimentos',
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
        ],
      ),
    );
  }

  Widget _buildActionsRow(BuildContext context) {
    final accent = _accent(context);
    final filtersActive = _filters.activeCount;
    return Row(
      children: [
        if (_canCreate) ...[
          FilledButton.icon(
            onPressed: _goToCreate,
            icon: const Icon(LucideIcons.plus, size: 16),
            label: const Text('Novo empreendimento'),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              textStyle:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        OutlinedButton.icon(
          onPressed: _openFilters,
          icon: const Icon(LucideIcons.slidersHorizontal, size: 15),
          label:
              Text(filtersActive == 0 ? 'Filtros' : 'Filtros ($filtersActive)'),
          style: OutlinedButton.styleFrom(
            foregroundColor: filtersActive > 0
                ? accent
                : ThemeHelpers.textSecondaryColor(context),
            side: BorderSide(
              color: filtersActive > 0
                  ? accent.withValues(alpha: 0.55)
                  : ThemeHelpers.borderColor(context),
              width: filtersActive > 0 ? 1.3 : 1,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            textStyle:
                const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accent(context);
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
                  hintText: 'Buscar por nome, endereço, cidade…',
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

  int? _tabCount(_DevTab tab) {
    switch (tab) {
      case _DevTab.active:
        return _activeCount;
      case _DevTab.inactive:
        return _inactiveCount;
      case _DevTab.all:
        if (_activeCount == null && _inactiveCount == null) return null;
        return (_activeCount ?? 0) + (_inactiveCount ?? 0);
    }
  }

  Color _tabColor(BuildContext context, _DevTab tab) {
    switch (tab) {
      case _DevTab.active:
        return EstateTones.green(context);
      case _DevTab.inactive:
        return EstateTones.amber(context);
      case _DevTab.all:
        return _accent(context);
    }
  }

  IconData _tabIcon(_DevTab tab) {
    switch (tab) {
      case _DevTab.active:
        return LucideIcons.circleCheckBig;
      case _DevTab.inactive:
        return LucideIcons.circleOff;
      case _DevTab.all:
        return LucideIcons.blocks;
    }
  }

  String _tabLabel(_DevTab tab) {
    switch (tab) {
      case _DevTab.active:
        return 'Ativos';
      case _DevTab.inactive:
        return 'Inativos';
      case _DevTab.all:
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

  Widget _buildActivePanel(BuildContext context) {
    final st = _state[_activeTab]!;
    Widget child;
    if (st.loading && st.items.isEmpty) {
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(4, (_) => const EstateCardSkeleton()),
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

  Widget _buildList(BuildContext context, _DevTab tab, _TabState st) {
    final nodes = <Widget>[];
    var animIndex = 0;
    for (final d in st.items) {
      nodes.add(
        EstateCard(
          name: d.name,
          imageUrl: d.mainImageUrl,
          photoCount: d.activeImages.length,
          isActive: d.isActive,
          locationLine: d.cityState,
          zipCode: d.zipCode,
          description: d.description,
          updatedAt: d.updatedAt,
          fallbackIcon: LucideIcons.blocks,
          accent: _accent(context),
          chips: _chipsFor(d),
          onTap: () => _goToDetail(d),
          onEdit: _canEdit ? () => _goToEdit(d) : null,
          onDelete: _canDelete ? () => _confirmDelete(d) : null,
        ).animate(key: ValueKey('dev-${d.id}')).fadeIn(
              delay: Duration(milliseconds: 30 * (animIndex++).clamp(0, 12)),
              duration: 220.ms,
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

  List<EstateCardChip> _chipsFor(Development d) {
    return [
      if (d.hasMaterial)
        EstateCardChip(
          icon: LucideIcons.folderOpen,
          label: 'Material da equipe',
          tone: EstateTones.purple,
        ),
      if ((d.cnpj ?? '').trim().isNotEmpty)
        EstateCardChip(
          icon: LucideIcons.landmark,
          label: 'CNPJ',
          tone: (ctx) => ThemeHelpers.textSecondaryColor(ctx),
        ),
      if ((d.website ?? '').trim().isNotEmpty)
        EstateCardChip(
          icon: LucideIcons.globe,
          label: 'Site',
          tone: EstateTones.amber,
        ),
    ];
  }

  Widget _buildEmpty(BuildContext context, _DevTab tab) {
    final hasSearch = _appliedSearch.trim().isNotEmpty;
    if (hasSearch || _filters.activeCount > 0) {
      return EstateEmptyState(
        icon: LucideIcons.searchX,
        title: 'Nada encontrado',
        body: hasSearch
            ? 'Nenhum empreendimento corresponde a "${_appliedSearch.trim()}".'
            : 'Nenhum empreendimento corresponde aos filtros aplicados.',
        tone: _accent(context),
      );
    }
    final (icon, title, body) = switch (tab) {
      _DevTab.active => (
          LucideIcons.blocks,
          'Nenhum empreendimento ativo',
          'Cadastre um empreendimento com o material de vendas da equipe.',
        ),
      _DevTab.inactive => (
          LucideIcons.circleOff,
          'Nenhum inativo',
          'Empreendimentos desativados aparecem aqui.',
        ),
      _DevTab.all => (
          LucideIcons.blocks,
          'Nenhum empreendimento',
          'Cadastre o primeiro empreendimento da empresa.',
        ),
    };
    return EstateEmptyState(
      icon: icon,
      title: title,
      body: body,
      tone: _tabColor(context, tab),
      action: _canCreate && tab != _DevTab.inactive
          ? FilledButton.icon(
              onPressed: _goToCreate,
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('Novo empreendimento'),
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
              'Você não tem acesso aos empreendimentos.',
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
