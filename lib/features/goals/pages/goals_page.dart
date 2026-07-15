import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/goal_model.dart';
import '../services/goal_service.dart';
import '../widgets/goal_card.dart';
import '../widgets/goals_filters_sheet.dart';

/// Aba ativa da tela de metas — recorte client-side sobre a mesma resposta.
enum GoalsTab { active, completed, all }

/// Tela **Metas** — gestão de metas configuráveis (paridade com a GoalsPage
/// do imobx-front, rota AdminRoute). Hero editorial com KPIs, busca flush,
/// abas flush com contagem e cards ricos com barra de progresso. Acesso
/// restrito a admin/master.
class GoalsPage extends StatefulWidget {
  const GoalsPage({super.key});

  @override
  State<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends State<GoalsPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 110;
  static const double _kSectionGap = 12;

  static const _tabs = [GoalsTab.active, GoalsTab.completed, GoalsTab.all];

  GoalsTab _activeTab = GoalsTab.active;

  GoalsListResult _result = GoalsListResult.empty;
  bool _loading = true;
  String? _error;

  GoalFilters _filters = GoalFilters.none;
  GoalFormOptions _filterOptions = GoalFormOptions.empty;
  bool _filterOptionsLoaded = false;

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _appliedSearch = '';
  bool _searchFocused = false;

  /// Gate por papel — a rota é AdminRoute no web (sem permissão granular).
  bool get _isAdmin {
    final role = ModuleAccessService.instance.userRole?.toLowerCase().trim();
    return role == 'admin' || role == 'master';
  }

  @override
  void initState() {
    super.initState();
    if (_isAdmin) _load();
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

  Color _tabColor(BuildContext context, GoalsTab tab) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (tab) {
      case GoalsTab.active:
        return isDark
            ? AppColors.status.greenDarkMode
            : AppColors.status.green;
      case GoalsTab.completed:
        return isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
      case GoalsTab.all:
        return _accentColor(context);
    }
  }

  int _tabCount(GoalsTab tab) {
    switch (tab) {
      case GoalsTab.active:
        return _result.active;
      case GoalsTab.completed:
        return _result.completed;
      case GoalsTab.all:
        return _result.total;
    }
  }

  // ─── Dados ───────────────────────────────────────────────────────────────

  GoalFilters get _requestFilters => GoalFilters(
        type: _filters.type,
        period: _filters.period,
        scope: _filters.scope,
        userId: _filters.userId,
        teamId: _filters.teamId,
        onlyActive: _filters.onlyActive,
        search: _appliedSearch.trim().isEmpty ? null : _appliedSearch.trim(),
      );

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final res = await GoalService.instance.listGoals(filters: _requestFilters);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _result = res.data!;
        _error = null;
      } else {
        _error = res.message ?? 'Erro ao carregar metas';
      }
    });
  }

  List<Goal> _tabItems(GoalsTab tab) {
    switch (tab) {
      case GoalsTab.active:
        return _result.goals
            .where((g) => g.status == GoalStatus.active)
            .toList();
      case GoalsTab.completed:
        return _result.goals
            .where((g) => g.status == GoalStatus.completed)
            .toList();
      case GoalsTab.all:
        return _result.goals;
    }
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

  Future<void> _openFilters() async {
    if (!_filterOptionsLoaded) {
      final res = await GoalService.instance.getFilterOptions();
      if (res.success && res.data != null) {
        _filterOptions = res.data!;
        _filterOptionsLoaded = true;
      }
    }
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => GoalsFiltersSheet(
        initialFilters: _filters,
        options: _filterOptions,
        onApply: (f) {
          setState(() => _filters = f);
          _load();
        },
        onClear: () {
          setState(() => _filters = GoalFilters.none);
          _load();
        },
      ),
    );
  }

  // ─── Ações do card ───────────────────────────────────────────────────────

  Future<void> _handleAction(Goal goal, GoalCardAction action) async {
    switch (action) {
      case GoalCardAction.analytics:
        await Navigator.of(context).pushNamed('/goals/${goal.id}/analytics');
        break;
      case GoalCardAction.edit:
        final changed =
            await Navigator.of(context).pushNamed('/goals/${goal.id}/edit');
        if (changed == true) _load(silent: true);
        break;
      case GoalCardAction.duplicate:
        final res = await GoalService.instance.duplicateGoal(goal.id);
        if (!mounted) return;
        _showSnack(
          res.success
              ? 'Meta duplicada para o próximo período.'
              : res.message ?? 'Erro ao duplicar meta',
          success: res.success,
        );
        if (res.success) _load(silent: true);
        break;
      case GoalCardAction.refresh:
        final res = await GoalService.instance.refreshGoalProgress(goal.id);
        if (!mounted) return;
        _showSnack(
          res.success
              ? 'Progresso atualizado.'
              : res.message ?? 'Erro ao atualizar progresso',
          success: res.success,
        );
        if (res.success) _load(silent: true);
        break;
      case GoalCardAction.delete:
        _confirmDelete(goal);
        break;
    }
  }

  void _confirmDelete(Goal goal) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ThemeHelpers.cardBackgroundColor(ctx),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Excluir meta',
          style: TextStyle(
            color: ThemeHelpers.textColor(ctx),
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
          ),
        ),
        content: Text(
          'Tem certeza que deseja excluir a meta "${goal.title}"? '
          'Essa ação não pode ser desfeita.',
          style: TextStyle(
            color: ThemeHelpers.textSecondaryColor(ctx),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancelar',
              style: TextStyle(
                color: ThemeHelpers.textSecondaryColor(ctx),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(LucideIcons.trash2, size: 16),
            label: const Text('Excluir'),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final res = await GoalService.instance.deleteGoal(goal.id);
              if (!mounted) return;
              _showSnack(
                res.success
                    ? 'Meta excluída com sucesso.'
                    : res.message ?? 'Erro ao excluir meta',
                success: res.success,
              );
              if (res.success) _load(silent: true);
            },
          ),
        ],
      ),
    );
  }

  void _showSnack(String message, {required bool success}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone = success
        ? (isDark ? AppColors.status.greenDarkMode : AppColors.status.green)
        : (isDark ? AppColors.status.errorDarkMode : AppColors.status.error);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: tone,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Future<void> _createGoal() async {
    final created = await Navigator.of(context).pushNamed('/goals/create');
    if (created == true) _load(silent: true);
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return const AppScaffold(
        title: 'Metas',
        showBottomNavigation: false,
        body: _DeniedView(),
      );
    }
    return AppScaffold(
      title: 'Metas',
      showBottomNavigation: false,
      body: Stack(
        children: [
          RefreshIndicator(
            color: _accentColor(context),
            onRefresh: _load,
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
          _buildFab(context),
        ],
      ),
    );
  }

  // ─── FAB criar (admin) ───────────────────────────────────────────────────

  Widget _buildFab(BuildContext context) {
    final accent = _accentColor(context);
    return Positioned(
      right: 16,
      bottom: 24,
      child: FloatingActionButton.extended(
        heroTag: 'goals-fab',
        onPressed: _createGoal,
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 3,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(LucideIcons.plus, size: 19),
        label: const Text(
          'Nova meta',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.1),
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
    final blue = isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    final red = isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;

    final total = _result.total;
    final offTrack = _result.goals
        .where((g) => g.status == GoalStatus.active && !g.isOnTrack)
        .length;
    final dot = total == 0
        ? secondary
        : offTrack > 0
            ? amber
            : emerald;
    final subtitle = total == 0
        ? 'Crie metas para acompanhar vendas, aluguéis, leads e conversões.'
        : offTrack > 0
            ? '$offTrack meta${offTrack == 1 ? '' : 's'} ativa${offTrack == 1 ? '' : 's'} '
                'precisa${offTrack == 1 ? '' : 'm'} de atenção no ritmo.'
            : 'Todas as metas ativas estão no ritmo esperado.';

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
                'METAS E OBJETIVOS',
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
                '$total',
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
                  total == 1 ? 'meta' : 'metas',
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
          _buildKpiStrip(context, emerald, blue, red),
        ],
      ),
    );
  }

  Widget _buildKpiStrip(
      BuildContext context, Color emerald, Color blue, Color red) {
    final divider = ThemeHelpers.borderColor(context).withValues(alpha: 0.45);
    final blocks = <Widget>[
      _heroKpiBlock(context, LucideIcons.goal, 'ATIVAS', '${_result.active}',
          'em andamento', emerald),
      _heroKpiBlock(context, LucideIcons.award, 'COMPLETADAS',
          '${_result.completed}', 'objetivo batido', blue),
      _heroKpiBlock(context, LucideIcons.circleAlert, 'FALHARAM',
          '${_result.failed}', 'não atingidas', red),
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
              _loading && _result.total == 0 ? '—' : value,
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: _buildSearchField(context)),
        const SizedBox(width: 10),
        _buildFilterButton(context),
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
                  hintText: 'Buscar metas…',
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

  Widget _buildFilterButton(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accentColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final active = _filters.activeCount > 0;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    return InkWell(
      onTap: _openFilters,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: active
              ? accent.withValues(alpha: isDark ? 0.16 : 0.09)
              : ThemeHelpers.cardBackgroundColor(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? accent.withValues(alpha: 0.5) : borderColor,
            width: active ? 1.4 : 1,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Icon(
                Icons.tune_rounded,
                size: 21,
                color: active ? accent : secondary,
              ),
            ),
            if (active)
              Positioned(
                right: 9,
                top: 9,
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
                selected: _activeTab == tab,
                onTap: () => setState(() => _activeTab = tab),
              ),
            ),
        ],
      ),
    );
  }

  IconData _tabIcon(GoalsTab tab) {
    switch (tab) {
      case GoalsTab.active:
        return LucideIcons.goal;
      case GoalsTab.completed:
        return LucideIcons.award;
      case GoalsTab.all:
        return LucideIcons.target;
    }
  }

  String _tabLabel(GoalsTab tab) {
    switch (tab) {
      case GoalsTab.active:
        return 'Ativas';
      case GoalsTab.completed:
        return 'Completadas';
      case GoalsTab.all:
        return 'Todas';
    }
  }

  // ─── Painel ativo ────────────────────────────────────────────────────────

  ({IconData icon, String eyebrow, String title, String hint}) _panelMeta(
      GoalsTab tab) {
    switch (tab) {
      case GoalsTab.active:
        return (
          icon: LucideIcons.goal,
          eyebrow: 'EM ANDAMENTO',
          title: 'Metas ativas',
          hint: 'O que a equipe está perseguindo agora — ritmo e progresso.',
        );
      case GoalsTab.completed:
        return (
          icon: LucideIcons.award,
          eyebrow: 'COMPLETADAS',
          title: 'Objetivos batidos',
          hint: 'Metas que chegaram a 100% dentro do período.',
        );
      case GoalsTab.all:
        return (
          icon: LucideIcons.target,
          eyebrow: 'TODAS',
          title: 'Histórico de metas',
          hint: 'Todas as metas da empresa, incluindo falhas e canceladas.',
        );
    }
  }

  Widget _buildActivePanel(BuildContext context) {
    final items = _tabItems(_activeTab);
    Widget child;
    if (_loading && _result.goals.isEmpty) {
      child = _buildSkeleton();
    } else if (_error != null && _result.goals.isEmpty) {
      child = _buildError(context, _error!);
    } else if (items.isEmpty) {
      child = _buildEmpty(context, _activeTab);
    } else {
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
              child: GoalCard(
                goal: items[i],
                onAction: (a) => _handleAction(items[i], a),
              ).animate(key: ValueKey('g-${items[i].id}')).fadeIn(
                    delay: Duration(milliseconds: 30 * i.clamp(0, 12)),
                    duration: 220.ms,
                  ),
            ),
        ],
      );
    }

    return Column(
      key: ValueKey('panel-${_activeTab.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPanelHeader(context, _activeTab),
        const SizedBox(height: 14),
        child,
      ],
    ).animate(key: ValueKey('panel-${_activeTab.name}')).fadeIn(
          duration: 240.ms,
        );
  }

  Widget _buildPanelHeader(BuildContext context, GoalsTab tab) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = _tabColor(context, tab);
    final meta = _panelMeta(tab);

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

  // ─── Estados ─────────────────────────────────────────────────────────────

  /// Skeleton fiel ao GoalCard: glyph + título + chips + barra + rodapé.
  Widget _buildSkeleton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(
        3,
        (i) => Container(
          margin: EdgeInsets.only(top: i == 0 ? 0 : 12),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: ThemeHelpers.borderColor(context)
                  .withValues(alpha: isDark ? 0.6 : 1),
            ),
            boxShadow: ThemeHelpers.cardShadow(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonBox(width: 44, height: 44, borderRadius: 13),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SkeletonText(width: double.infinity, height: 15),
                        SizedBox(height: 7),
                        SkeletonText(width: 120, height: 12),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  const SkeletonBox(width: 62, height: 20, borderRadius: 999),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: const [
                  SkeletonText(width: 90, height: 11, borderRadius: 999),
                  SizedBox(width: 10),
                  SkeletonText(width: 90, height: 11, borderRadius: 999),
                ],
              ),
              const SizedBox(height: 14),
              const SkeletonText(width: 170, height: 17),
              const SizedBox(height: 8),
              const SkeletonBox(
                  width: double.infinity, height: 8, borderRadius: 999),
              const SizedBox(height: 12),
              Row(
                children: const [
                  SkeletonText(width: 100, height: 11),
                  Spacer(),
                  SkeletonBox(width: 70, height: 26, borderRadius: 999),
                  SizedBox(width: 6),
                  SkeletonBox(width: 70, height: 26, borderRadius: 999),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, GoalsTab tab) {
    final theme = Theme.of(context);
    final tone = _tabColor(context, tab);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hasSearch = _appliedSearch.trim().isNotEmpty;
    final hasFilters = _filters.activeCount > 0;
    final (icon, title, body) = hasSearch || hasFilters
        ? (
            LucideIcons.searchX,
            'Nada encontrado',
            hasSearch
                ? 'Nenhuma meta corresponde a "${_appliedSearch.trim()}".'
                : 'Nenhuma meta corresponde aos filtros aplicados.',
          )
        : switch (tab) {
            GoalsTab.active => (
                LucideIcons.goal,
                'Nenhuma meta ativa',
                'Crie uma meta para acompanhar o desempenho da equipe.',
              ),
            GoalsTab.completed => (
                LucideIcons.award,
                'Nenhuma completada ainda',
                'Quando uma meta atingir 100%, ela aparece aqui.',
              ),
            GoalsTab.all => (
                LucideIcons.target,
                'Nenhuma meta cadastrada',
                'Comece criando sua primeira meta de vendas, aluguéis ou leads.',
              ),
          };
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
          if (!hasSearch && !hasFilters && tab != GoalsTab.completed) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _createGoal,
              style: OutlinedButton.styleFrom(
                foregroundColor: _accentColor(context),
                side: BorderSide(
                  color: _accentColor(context).withValues(alpha: 0.45),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('Criar primeira meta'),
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
            onPressed: _load,
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

// ─── Acesso negado ───────────────────────────────────────────────────────────

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
              'Você não tem acesso às metas.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'A gestão de metas é restrita a administradores da empresa.',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
