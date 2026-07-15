import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
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

/// Tela **Condomínios** — porta a `CondominiumsPage` do imobx-front com a
/// gramática flush do app: hero editorial + ações em pill, busca flush, abas
/// com sublinhado (Ativos/Inativos/Todos), cards ricos com ações no item e
/// paginação por "Carregar mais".
class CondominiumsPage extends StatefulWidget {
  const CondominiumsPage({super.key});

  @override
  State<CondominiumsPage> createState() => _CondominiumsPageState();
}

class _CondominiumsPageState extends State<CondominiumsPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const double _kSectionGap = 12;
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

  // ─── Hero ────────────────────────────────────────────────────────────────

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
        ? 'Carregando o portfólio de condomínios…'
        : total == 0
            ? 'Cadastre condomínios para vincular aos imóveis da carteira.'
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
                'CONDOMÍNIOS',
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
                  total == 1 ? 'condomínio' : 'condomínios',
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

  /// Pills de ação — Novo condomínio (gated por create) + Filtros com badge.
  Widget _buildActionsRow(BuildContext context) {
    final accent = _accent(context);
    final filtersActive = _filters.activeCount;
    return Row(
      children: [
        if (_canCreate) ...[
          FilledButton.icon(
            onPressed: _goToCreate,
            icon: const Icon(LucideIcons.plus, size: 16),
            label: const Text('Novo condomínio'),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
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
          label: Text(filtersActive == 0 ? 'Filtros' : 'Filtros ($filtersActive)'),
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

  // ─── Busca flush ─────────────────────────────────────────────────────────

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

  // ─── Abas ────────────────────────────────────────────────────────────────

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

  // ─── Painel ──────────────────────────────────────────────────────────────

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

  Widget _buildList(BuildContext context, _CondoTab tab, _TabState st) {
    final nodes = <Widget>[];
    var animIndex = 0;
    for (final c in st.items) {
      nodes.add(
        EstateCard(
          name: c.name,
          imageUrl: c.mainImageUrl,
          photoCount: c.activeImages.length,
          isActive: c.isActive,
          locationLine: c.cityState,
          zipCode: c.zipCode,
          description: c.description,
          updatedAt: c.updatedAt,
          fallbackIcon: LucideIcons.building2,
          accent: _accent(context),
          chips: _chipsFor(c),
          onTap: () => _showDetail(c),
          onEdit: _canEdit ? () => _goToEdit(c) : null,
          onDelete: _canDelete ? () => _confirmDelete(c) : null,
        ).animate(key: ValueKey('condo-${c.id}')).fadeIn(
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

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: nodes);
  }

  List<EstateCardChip> _chipsFor(Condominium c) {
    final pct = c.completenessPct;
    return [
      if ((c.cnpj ?? '').trim().isNotEmpty)
        EstateCardChip(
          icon: LucideIcons.landmark,
          label: 'CNPJ',
          tone: (ctx) => ThemeHelpers.textSecondaryColor(ctx),
        ),
      if ((c.website ?? '').trim().isNotEmpty)
        EstateCardChip(
          icon: LucideIcons.globe,
          label: 'Site',
          tone: EstateTones.amber,
        ),
      EstateCardChip(
        icon: LucideIcons.chartNoAxesColumn,
        label: '$pct% completo',
        tone: pct >= 75
            ? EstateTones.green
            : pct >= 45
                ? EstateTones.amber
                : (ctx) => ThemeHelpers.textSecondaryColor(ctx),
      ),
    ];
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
