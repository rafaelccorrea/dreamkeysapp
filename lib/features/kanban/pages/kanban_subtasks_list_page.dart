import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/shell_visual_tokens.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../../../shared/services/module_access_service.dart';
import '../models/kanban_subtask_models.dart';
import '../services/kanban_subtask_service.dart';
import '../widgets/subtask_card.dart';

/// Tela global "Lista de tarefas" — paridade com `MySubTasksPage.tsx`.
///
/// Identidade visual da casa: shell gradient + ambient orbes, hero
/// greeting com ícone gradiente, KPI strip slim, navegação horizontal em
/// pills e cards fluidos.
class KanbanSubtasksListPage extends StatefulWidget {
  const KanbanSubtasksListPage({super.key});

  @override
  State<KanbanSubtasksListPage> createState() =>
      _KanbanSubtasksListPageState();
}

enum _Bucket { all, pending, today, overdue, completed }

class _KanbanSubtasksListPageState extends State<KanbanSubtasksListPage> {
  static const double _kSectionGap = 11;
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;

  /// `true` enquanto a primeira carga não chegou — a tela inteira mostra
  /// skeleton coerente (hero + métricas + lista). Depois disso, trocas de
  /// bucket/busca usam `_quietRefresh` (refetch silencioso, sem cobrir o
  /// hero) pra não dar a sensação de "tela inteira piscando" cada vez.
  bool _bootLoading = true;
  bool _silentLoading = false;
  bool _loadingMore = false;
  String? _error;
  SubTasksListResponse _response = SubTasksListResponse.empty;
  SubTasksListStats _heroStats = SubTasksListStats.zero;

  _Bucket _activeBucket = _Bucket.pending;
  int _pagingGeneration = 0;
  final ScrollController _scrollController = ScrollController();

  // IDs em ação (toggle / delete) para mostrar loader inline.
  final Set<String> _busyIds = <String>{};

  // Busca global por título do card pai (cardSearch) — debounced.
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _appliedSearch = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _bootstrap();
  }

  /// Carrega tudo de uma vez antes de exibir conteúdo. A tela só "aparece"
  /// quando a primeira resposta chega — evita layout shift e dá uma
  /// sensação mais fluida que "skeleton no meio do hero pronto".
  Future<void> _bootstrap() async {
    final generation = ++_pagingGeneration;
    final res = await KanbanSubtaskService.instance.getMySubTasks(
      filters: _filtersFor(_activeBucket),
      useCache: false,
    );
    if (!mounted) return;
    setState(() {
      _bootLoading = false;
      _loadingMore = false;
      if (res.success && res.data != null) {
        _heroStats = res.data!.stats;
      }
      if (res.success && res.data != null) {
        _response = res.data!;
      } else {
        _error = res.message ?? 'Erro ao carregar tarefas';
      }
    });
    if (generation != _pagingGeneration) return;
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ─── Filters por bucket ──────────────────────────────────────────────

  bool get _isMasterOrAdmin {
    final role = ModuleAccessService.instance.userRole?.toLowerCase().trim() ?? '';
    return role == 'master' || role == 'admin';
  }

  bool get _isManager {
    final role = ModuleAccessService.instance.userRole?.toLowerCase().trim() ?? '';
    return role == 'manager';
  }

  /// Escopo por role:
  /// - master/admin: empresa inteira
  /// - manager: equipe(s) acessíveis no backend (não força `onlyMine`)
  /// - demais: somente minhas
  SubTasksListFilters _baseScopeFilters({
    required int page,
    required int limit,
    String? cardSearch,
  }) {
    final isPrivileged = _isMasterOrAdmin || _isManager;
    return SubTasksListFilters(
      onlyMine: !isPrivileged,
      cardSearch: cardSearch,
      page: page,
      limit: limit,
    );
  }

  bool get _hasMorePages => _response.page < _response.totalPages;

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 280) {
      unawaited(_loadNextPage());
    }
  }

  SubTasksListFilters _filtersFor(_Bucket bucket) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    switch (bucket) {
      case _Bucket.all:
        return _baseScopeFilters(
          cardSearch: _appliedSearch,
          page: 1,
          limit: 30,
        );
      case _Bucket.pending:
        return _baseScopeFilters(
          cardSearch: _appliedSearch,
          page: 1,
          limit: 30,
        ).copyWith(
          isCompleted: false,
        );
      case _Bucket.today:
        return _baseScopeFilters(
          cardSearch: _appliedSearch,
          page: 1,
          limit: 30,
        ).copyWith(
          isCompleted: false,
          dueDateFrom: today,
          dueDateTo: today,
        );
      case _Bucket.overdue:
        return _baseScopeFilters(
          cardSearch: _appliedSearch,
          page: 1,
          limit: 30,
        ).copyWith(
          isCompleted: false,
          dueDateTo: yesterday,
        );
      case _Bucket.completed:
        return _baseScopeFilters(
          cardSearch: _appliedSearch,
          page: 1,
          limit: 30,
        ).copyWith(
          isCompleted: true,
        );
    }
  }

  // ─── Loaders ─────────────────────────────────────────────────────────

  /// Refetch que cobre a tela inteira com skeleton (uso restrito ao
  /// pull-to-refresh quando o usuário pediu explicitamente "atualizar").
  Future<void> _refresh() async {
    final generation = ++_pagingGeneration;
    setState(() {
      _silentLoading = true;
      _loadingMore = false;
      _error = null;
    });
    final res = await KanbanSubtaskService.instance.getMySubTasks(
      filters: _filtersFor(_activeBucket),
      useCache: false,
    );
    if (!mounted) return;
    setState(() {
      _silentLoading = false;
      _loadingMore = false;
      if (res.success && res.data != null) {
        _heroStats = res.data!.stats;
      }
      if (res.success && res.data != null) {
        _response = res.data!;
      } else {
        _error = res.message ?? 'Erro ao carregar tarefas';
      }
    });
    if (generation != _pagingGeneration) return;
  }

  Future<void> _loadNextPage() async {
    if (!mounted || _bootLoading || _silentLoading || _loadingMore) return;
    if (!_hasMorePages) return;

    final generation = _pagingGeneration;
    final current = _response;
    final nextPage = current.page + 1;
    final limit = current.limit > 0 ? current.limit : 30;

    setState(() => _loadingMore = true);
    final res = await KanbanSubtaskService.instance.getMySubTasks(
      filters: _filtersFor(_activeBucket).copyWith(page: nextPage, limit: limit),
    );
    if (!mounted || generation != _pagingGeneration) return;

    setState(() {
      _loadingMore = false;
      if (!res.success || res.data == null) return;
      _heroStats = res.data!.stats;
      final merged = <KanbanSubTask>[];
      final seen = <String>{};
      for (final item in current.data) {
        if (seen.add(item.id)) merged.add(item);
      }
      for (final item in res.data!.data) {
        if (seen.add(item.id)) merged.add(item);
      }
      _response = SubTasksListResponse(
        data: merged,
        total: res.data!.total,
        page: res.data!.page,
        limit: res.data!.limit,
        totalPages: res.data!.totalPages,
        stats: res.data!.stats,
      );
    });
  }

  void _selectBucket(_Bucket bucket) {
    if (bucket == _activeBucket) return;
    setState(() => _activeBucket = bucket);
    _refresh();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final v = value.trim();
      if (v == _appliedSearch) return;
      setState(() => _appliedSearch = v);
      _refresh();
    });
  }

  // ─── Ações ───────────────────────────────────────────────────────────

  Future<void> _toggle(KanbanSubTask st) async {
    final previous = _response.data;
    setState(() {
      _busyIds.add(st.id);
      _response = SubTasksListResponse(
        data: _response.data
            .map((e) => e.id == st.id
                ? e.copyWith(isCompleted: !e.isCompleted)
                : e)
            .toList(),
        total: _response.total,
        page: _response.page,
        limit: _response.limit,
        totalPages: _response.totalPages,
        stats: _response.stats,
      );
    });
    final res = await KanbanSubtaskService.instance.toggleSubTask(st.id);
    if (!mounted) return;
    setState(() => _busyIds.remove(st.id));
    if (!res.success) {
      // Rollback
      setState(() {
        _response = SubTasksListResponse(
          data: previous,
          total: _response.total,
          page: _response.page,
          limit: _response.limit,
          totalPages: _response.totalPages,
          stats: _response.stats,
        );
      });
      _showSnack(res.message ?? 'Erro ao atualizar tarefa');
    } else {
      // Refetch silencioso pra alinhar com servidor.
      unawaited(_refresh());
    }
  }

  Future<void> _delete(KanbanSubTask st) async {
    final danger = Theme.of(context).brightness == Brightness.dark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir tarefa'),
        content: Text('Excluir «${st.title}»?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: danger),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _busyIds.add(st.id);
      _response = SubTasksListResponse(
        data: _response.data.where((e) => e.id != st.id).toList(),
        total: _response.total,
        page: _response.page,
        limit: _response.limit,
        totalPages: _response.totalPages,
        stats: _response.stats,
      );
    });
    final res = await KanbanSubtaskService.instance.deleteSubTask(st.id);
    if (!mounted) return;
    setState(() => _busyIds.remove(st.id));
    if (!res.success) {
      _showSnack(res.message ?? 'Erro ao excluir tarefa');
      _refresh();
    } else {
      _showSnack('Tarefa excluída.', success: true);
      unawaited(_refresh());
    }
  }

  void _openParentCard(KanbanSubTask st) {
    final cardId = st.taskId;
    if (cardId.isEmpty) return;
    // Deep-link direto pra negociação: a página dedicada carrega a
    // `KanbanTask` por id e abre o `TaskDetailsModal` automaticamente.
    Navigator.of(context).pushNamed(AppRoutes.kanbanTaskDetails(cardId));
  }

  void _showSnack(String message, {bool success = false}) {
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ─── Visual helpers ──────────────────────────────────────────────────

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

  // ─── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    return AppScaffold(
      title: 'Tarefas',
      showBottomNavigation: false,
      body: _bootLoading
          ? _buildPageSkeleton(context)
          : RefreshIndicator(
              color: _accentColor(context),
              onRefresh: _refresh,
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: viewportHeight),
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
                                const SizedBox(height: 14),
                                _buildKpiInline(context),
                                const SizedBox(height: _kSectionGap),
                                _buildSearchField(context),
                                const SizedBox(height: _kSectionGap + 1),
                              ],
                            ),
                          ),
                          _buildBucketsRail(context),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              8,
                              _kSectionGap + 1,
                              8,
                              _kPagePadBottom,
                            ),
                            child: _buildBody(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  // ─── Greeting ────────────────────────────────────────────────────────

  Widget _buildGreeting(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accentColor(context);
    final isDark = theme.brightness == Brightness.dark;
    final stats = _heroStats;
    final pending = stats.pending;
    final overdue = stats.overdue;
    final completed = stats.completed;
    final total = stats.total;
    final completionPct = total > 0 ? ((completed * 100) / total).round() : 0;
    final danger = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;
    final subtitleColor = ThemeHelpers.textSecondaryColor(context);
    final updatedAtLabel = _formatHeroTimestamp(DateTime.now());
    final activeBucketLabel = _bucketLabel(_activeBucket);
    final hasSearch = _appliedSearch.trim().isNotEmpty;
    final progressTone = completionPct >= 70
        ? (isDark ? AppColors.status.greenDarkMode : AppColors.status.green)
        : accent;
    final pendingTone = pending > 0
        ? (isDark ? AppColors.status.warningDarkMode : AppColors.status.warning)
        : (isDark ? AppColors.status.greenDarkMode : AppColors.status.green);

    final headline = pending == 0
        ? 'Tudo em dia por aqui'
        : (pending == 1
            ? '1 tarefa aguarda você'
            : '$pending tarefas aguardam você');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    colors: [accent, const Color(0xFF7C3AED)],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: isDark ? 0.16 : 0.34),
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
                  LucideIcons.checkSquare,
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
                      'TAREFAS DO CRM',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.2,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      headline,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        height: 1.08,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Atualizado $updatedAtLabel · Visão ${activeBucketLabel[0].toUpperCase()}${activeBucketLabel.substring(1)} · Progresso $completionPct%',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: subtitleColor,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    if (hasSearch) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? accent.withValues(alpha: 0.11)
                              : accent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: isDark
                                ? accent.withValues(alpha: 0.24)
                                : accent.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.search, size: 13, color: accent),
                            const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 230),
                              child: Text(
                                'Filtro "${_appliedSearch.trim()}"',
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: ThemeHelpers.textColor(context),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.15,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        _buildHeroMiniStatChip(
                          context,
                          icon: LucideIcons.inbox,
                          label: 'Pendentes',
                          value: pending,
                          tone: pendingTone,
                        ),
                        _buildHeroMiniStatChip(
                          context,
                          icon: LucideIcons.alertTriangle,
                          label: 'Atrasadas',
                          value: overdue,
                          tone: danger,
                        ),
                        _buildHeroMiniStatChip(
                          context,
                          icon: LucideIcons.checkCircle2,
                          label: 'Concluídas',
                          value: completed,
                          tone: progressTone,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.03)
                  : Colors.white.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 3,
                  height: 30,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    color: overdue > 0 ? danger : pendingTone,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: overdue > 0
                        ? danger.withValues(alpha: 0.16)
                        : pendingTone.withValues(alpha: 0.16),
                  ),
                  child: Icon(
                    overdue > 0 ? LucideIcons.alertTriangle : LucideIcons.sparkles,
                    size: 14,
                    color: overdue > 0 ? danger : pendingTone,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    overdue > 0
                        ? '$overdue ${overdue == 1 ? 'tarefa atrasada precisa de atenção agora.' : 'tarefas atrasadas pedem ação imediata.'}'
                        : (pending > 0
                            ? '$pending ${pending == 1 ? 'pendência ativa no seu fluxo.' : 'pendências ativas no seu fluxo.'}'
                            : 'Nenhuma pendência ativa. Continue mantendo esse ritmo.'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      fontWeight: FontWeight.w700,
                      height: 1.32,
                    ),
                  ),
                ),
                if (overdue > 0) ...[
                  const SizedBox(width: 8),
                  _PulseDot(color: danger),
                ],
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Lembretes do que fazer com cada lead.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: subtitleColor,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroMiniStatChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required int value,
    required Color tone,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? tone.withValues(alpha: 0.11) : tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? tone.withValues(alpha: 0.28) : tone.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: tone),
          const SizedBox(width: 6),
          Text(
            '$value',
            style: theme.textTheme.labelLarge?.copyWith(
              color: tone,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w800,
              letterSpacing: 0.15,
            ),
          ),
        ],
      ),
    );
  }

  String _bucketLabel(_Bucket bucket) {
    switch (bucket) {
      case _Bucket.all:
        return 'todas';
      case _Bucket.pending:
        return 'pendentes';
      case _Bucket.today:
        return 'hoje';
      case _Bucket.overdue:
        return 'atrasadas';
      case _Bucket.completed:
        return 'concluídas';
    }
  }

  String _formatHeroTimestamp(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}';
  }

  // ─── KPI inline (sem card) ───────────────────────────────────────────

  /// Stats expandidas horizontalmente direto abaixo do hero — cada KPI é
  /// só **número grande + label**, separados por divisor vertical sutil.
  /// Sem card glass, sem caixa: respiro total e leitura imediata.
  Widget _buildKpiInline(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
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

    final stats = _heroStats;
    final items = [
      _KpiItem(label: 'Total', value: stats.total, color: accent),
      _KpiItem(label: 'Pendentes', value: stats.pending, color: warn),
      _KpiItem(label: 'Atrasadas', value: stats.overdue, color: danger),
      _KpiItem(label: 'Concluídas', value: stats.completed, color: ok),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Builder(
        builder: (context) {
          // Em telas largas distribuímos no espaço total; em telas
          // estreitas mantemos scroll horizontal pra não estourar.
          final dividerColor = ThemeHelpers.borderColor(context)
              .withValues(alpha: 0.32);
          if (screenWidth < 360) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    _KpiInlineTile(item: items[i], theme: theme),
                    if (i < items.length - 1)
                      Container(
                        width: 1,
                        height: 28,
                        margin: const EdgeInsets.symmetric(horizontal: 14),
                        color: dividerColor,
                      ),
                  ],
                ],
              ),
            );
          }
          return Row(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                Expanded(
                  child: _KpiInlineTile(item: items[i], theme: theme),
                ),
                if (i < items.length - 1)
                  Container(
                    width: 1,
                    height: 28,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    color: dividerColor,
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  // ─── Search ──────────────────────────────────────────────────────────

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
        hintText: 'Buscar pelo card pai…',
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

  // ─── Bucket pills ────────────────────────────────────────────────────

  Widget _buildBucketsRail(BuildContext context) {
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

    final stats = _heroStats;

    final tabs = <_BucketSpec>[
      _BucketSpec(
        bucket: _Bucket.pending,
        icon: LucideIcons.inbox,
        label: 'Pendentes',
        count: stats.pending,
        color: warn,
      ),
      _BucketSpec(
        bucket: _Bucket.today,
        icon: LucideIcons.calendar,
        label: 'Hoje',
        count: _todayCount(),
        color: accent,
      ),
      _BucketSpec(
        bucket: _Bucket.overdue,
        icon: LucideIcons.alertTriangle,
        label: 'Atrasadas',
        count: stats.overdue,
        color: danger,
      ),
      _BucketSpec(
        bucket: _Bucket.completed,
        icon: LucideIcons.checkCircle2,
        label: 'Concluídas',
        count: stats.completed,
        color: ok,
      ),
      _BucketSpec(
        bucket: _Bucket.all,
        icon: LucideIcons.list,
        label: 'Todas',
        count: stats.total,
        color: const Color(0xFF7C3AED),
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++) ...[
            _BucketPill(
              spec: tabs[i],
              selected: _activeBucket == tabs[i].bucket,
              onTap: () => _selectBucket(tabs[i].bucket),
            ),
            if (i < tabs.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  /// Conta itens com prazo "hoje" entre os carregados — métrica leve
  /// usada apenas pra preview no pill (a métrica rigorosa vem da API
  /// quando o bucket é selecionado).
  int _todayCount() {
    if (_activeBucket == _Bucket.today) return _response.data.length;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _response.data
        .where((e) =>
            !e.isCompleted &&
            e.dueDate != null &&
            DateTime(
                  e.dueDate!.year,
                  e.dueDate!.month,
                  e.dueDate!.day,
                ).isAtSameMomentAs(today))
        .length;
  }

  // ─── Body ────────────────────────────────────────────────────────────

  Widget _buildBody(BuildContext context) {
    if (_silentLoading && _response.data.isEmpty) return _buildListSkeleton();
    if (_error != null && _response.data.isEmpty) return _buildError();
    if (_response.data.isEmpty) return _buildEmpty();
    final theme = Theme.of(context);
    final accent = _accentColor(context);
    final hintColor = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _response.data.length; i++) ...[
          SubTaskCard(
            subtask: _response.data[i],
            showParentCard: true,
            busy: _busyIds.contains(_response.data[i].id),
            onTap: () => _openParentCard(_response.data[i]),
            onToggle: () => _toggle(_response.data[i]),
            onDelete: () => _delete(_response.data[i]),
          )
              .animate(key: ValueKey('subtask-${_response.data[i].id}'))
              .fadeIn(
                delay: Duration(milliseconds: 40 * i),
                duration: 220.ms,
              )
              .slideY(
                begin: 0.04,
                end: 0,
                delay: Duration(milliseconds: 40 * i),
                duration: 240.ms,
                curve: Curves.easeOutCubic,
              ),
          if (i < _response.data.length - 1) const SubTaskDivider(),
        ],
        if (_hasMorePages || _loadingMore) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.18)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_loadingMore)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: accent,
                    ),
                  )
                else
                  Icon(
                    LucideIcons.chevronsDown,
                    size: 16,
                    color: hintColor,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _loadingMore
                        ? 'Carregando mais tarefas...'
                        : 'Role para carregar mais tarefas',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _loadingMore ? accent : hintColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Página ${_response.page} de ${_response.totalPages}',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: hintColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }

  Widget _buildListSkeleton() {
    return Column(
      children: List.generate(
        4,
        (i) => Padding(
          padding: EdgeInsets.only(bottom: i < 3 ? 12 : 0),
          child: SkeletonBox(height: 96, borderRadius: 18),
        ),
      ),
    );
  }

  /// Skeleton de **tela inteira** — exibido enquanto a primeira carga
  /// não chega. Cobre hero, KPIs, busca, pills e lista — sem layout shift
  /// quando o conteúdo de fato aparece.
  Widget _buildPageSkeleton(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ..._ambientHighlights(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              _kPagePadH,
              _kPagePadTop,
              _kPagePadH,
              _kPagePadBottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero: ícone + textos
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 40, height: 40, borderRadius: 14),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(
                              width: 130,
                              height: 9,
                              borderRadius: 999,
                            ),
                            const SizedBox(height: 8),
                            SkeletonBox(
                              width: double.infinity,
                              height: 22,
                              borderRadius: 6,
                            ),
                            const SizedBox(height: 8),
                            SkeletonBox(
                              width: 200,
                              height: 11,
                              borderRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // KPI inline (4 mini blocos)
                Row(
                  children: [
                    for (var i = 0; i < 4; i++) ...[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(
                              width: 32,
                              height: 22,
                              borderRadius: 6,
                            ),
                            const SizedBox(height: 6),
                            SkeletonBox(
                              width: 64,
                              height: 9,
                              borderRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      if (i < 3) const SizedBox(width: 12),
                    ],
                  ],
                ),
                const SizedBox(height: _kSectionGap + 4),
                // Search
                SkeletonBox(
                  width: double.infinity,
                  height: 48,
                  borderRadius: 14,
                ),
                const SizedBox(height: _kSectionGap + 4),
                // Pills
                Row(
                  children: [
                    SkeletonBox(width: 110, height: 36, borderRadius: 999),
                    const SizedBox(width: 8),
                    SkeletonBox(width: 90, height: 36, borderRadius: 999),
                    const SizedBox(width: 8),
                    SkeletonBox(width: 110, height: 36, borderRadius: 999),
                  ],
                ),
                const SizedBox(height: _kSectionGap + 4),
                // Lista de tarefas
                ...List.generate(
                  4,
                  (i) => Padding(
                    padding: EdgeInsets.only(bottom: i < 3 ? 12 : 0),
                    child: SkeletonBox(height: 96, borderRadius: 18),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: danger.withValues(alpha: 0.10),
              border: Border.all(color: danger.withValues(alpha: 0.32)),
            ),
            child: Icon(LucideIcons.cloudOff, color: danger, size: 26),
          ),
          const SizedBox(height: 14),
          Text(
            _error ?? 'Erro ao carregar',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _refresh,
            icon: const Icon(LucideIcons.refreshCw, size: 14),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    final theme = Theme.of(context);
    final accent = _accentColor(context);
    final meta = _emptyMeta();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 4),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
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
            child: Icon(meta.icon, color: accent, size: 30),
          ),
          const SizedBox(height: 14),
          Text(
            meta.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            meta.body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  ({IconData icon, String title, String body}) _emptyMeta() {
    switch (_activeBucket) {
      case _Bucket.all:
        return (
          icon: LucideIcons.list,
          title: 'Nenhuma tarefa por aqui',
          body:
              'Abra um card no funil e crie tarefas para organizar suas próximas ações.',
        );
      case _Bucket.pending:
        return (
          icon: LucideIcons.partyPopper,
          title: 'Tudo em dia',
          body: 'Você não tem tarefas pendentes. Bom trabalho!',
        );
      case _Bucket.today:
        return (
          icon: LucideIcons.calendar,
          title: 'Sem tarefas para hoje',
          body: 'Aproveite para adiantar pendências de outros dias.',
        );
      case _Bucket.overdue:
        return (
          icon: LucideIcons.shieldCheck,
          title: 'Sem atrasos',
          body: 'Nenhuma tarefa pendente passou do prazo.',
        );
      case _Bucket.completed:
        return (
          icon: LucideIcons.checkCircle2,
          title: 'Nada concluído ainda',
          body: 'Tarefas concluídas aparecerão aqui.',
        );
    }
  }
}

// ─── Subwidgets ────────────────────────────────────────────────────────

class _KpiItem {
  final String label;
  final int value;
  final Color color;
  _KpiItem({required this.label, required this.value, required this.color});
}

/// KPI inline (sem caixa) — número grande colorido + label uppercase
/// pequena. Usado direto sob o hero, distribuído na horizontal.
class _KpiInlineTile extends StatelessWidget {
  final _KpiItem item;
  final ThemeData theme;
  const _KpiInlineTile({required this.item, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
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
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: item.color,
              letterSpacing: -0.85,
              height: 1.0,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          item.label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _BucketSpec {
  final _Bucket bucket;
  final IconData icon;
  final String label;
  final int count;
  final Color color;

  _BucketSpec({
    required this.bucket,
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
  });
}

class _BucketPill extends StatelessWidget {
  final _BucketSpec spec;
  final bool selected;
  final VoidCallback onTap;

  const _BucketPill({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fg = selected ? Colors.white : ThemeHelpers.textColor(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: selected
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  spec.color,
                  spec.color.withValues(alpha: 0.78),
                ],
              )
            : null,
        color:
            selected ? null : ShellVisualTokens.dashboardGlassFill(context),
        border: Border.all(
          color: selected
              ? spec.color.withValues(alpha: 0.3)
              : ShellVisualTokens.dashboardGlassBorder(context),
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color:
                      spec.color.withValues(alpha: isDark ? 0.4 : 0.32),
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
          splashColor: spec.color.withValues(alpha: 0.18),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white.withValues(alpha: 0.22)
                          : spec.color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      spec.count > 99 ? '99+' : '${spec.count}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: selected ? Colors.white : spec.color,
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
      ),
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
