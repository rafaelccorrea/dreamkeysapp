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

  /// Contagens globais (absolutas) por bucket — populadas por chamadas
  /// dedicadas SEM filtro de bucket aplicado. Usadas pelos pills de
  /// navegação pra mostrar o "tem 30, tem 100, tem 200…" real, e não a
  /// contagem CAPADA pelo filtro atual.
  ///
  /// `total` aqui = total absoluto da query (respeitando só o escopo
  /// onlyMine e a busca por card-pai, se houver).
  int _baselineTotal = 0;
  int _baselinePending = 0;
  int _baselineOverdue = 0;
  int _baselineCompleted = 0;
  int _baselineToday = 0;

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
    // Em paralelo, busca as contagens reais por bucket — sem cobrir
    // o flow de exibir a tela. Fica em segundo plano.
    unawaited(_loadBaselineCounts());
    if (generation != _pagingGeneration) return;
  }

  /// Faz uma série de chamadas LEVES (limit=1) sem filtro de bucket pra
  /// descobrir as contagens absolutas por categoria. A primeira chamada
  /// (sem filtro) já devolve `total / pending / completed / overdue` via
  /// `stats`; a segunda fecha o "hoje".
  ///
  /// Por que: o `getMySubTasks` filtrado por bucket retorna `total` e
  /// `stats` ESCOPADOS àquela query. Sem isso aqui, as pills mostrariam
  /// "30" pra todo bucket — exatamente a queixa do usuário.
  Future<void> _loadBaselineCounts() async {
    final scope = _baseScopeFilters(
      cardSearch: _appliedSearch,
      page: 1,
      limit: 1,
    );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    try {
      final results = await Future.wait([
        // (1) sem filtro de bucket — devolve stats absolutas + total real
        //     respeitando o escopo (onlyMine) e a busca.
        KanbanSubtaskService.instance.getMySubTasks(
          filters: scope,
          useCache: false,
        ),
        // (2) só "hoje" — pra contagem precisa do pill correspondente.
        KanbanSubtaskService.instance.getMySubTasks(
          filters: scope.copyWith(
            isCompleted: false,
            dueDateFrom: today,
            dueDateTo: today,
          ),
          useCache: false,
        ),
      ]);
      if (!mounted) return;
      final r0 = results[0];
      final r1 = results[1];
      setState(() {
        if (r0.success && r0.data != null) {
          _baselineTotal = r0.data!.total > 0
              ? r0.data!.total
              : r0.data!.stats.total;
          _baselinePending = r0.data!.stats.pending;
          _baselineOverdue = r0.data!.stats.overdue;
          _baselineCompleted = r0.data!.stats.completed;
        }
        if (r1.success && r1.data != null) {
          _baselineToday = r1.data!.total > 0
              ? r1.data!.total
              : r1.data!.data.length;
        }
      });
    } catch (_) {
      // Sem fallback — se baseline falhar, pills exibem `_heroStats`
      // que pode estar capado pelo filtro corrente. Não é UX ideal mas
      // não trava a tela.
    }
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
    unawaited(_loadBaselineCounts());
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

  /// Paleta da tela — TIRAMOS o vermelho coral. Agora violet/indigo
  /// como acento neutro, e o vermelho é reservado SOMENTE pra atraso real.
  Color _accentColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF8B5CF6) // violet-500
        : const Color(0xFF7C3AED); // violet-600
  }

  Color _accentSecondary(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF6366F1) // indigo-500
        : const Color(0xFF4F46E5); // indigo-600
  }

  List<Widget> _ambientHighlights(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accentColor(context);
    final secondary = _accentSecondary(context);
    return [
      // Glow superior direito — violet sutil (não mais cool isolado).
      Positioned(
        top: -90,
        right: -60,
        child: IgnorePointer(
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  accent.withValues(alpha: isDark ? 0.12 : 0.055),
                  accent.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ),
      // Glow lateral esquerdo — indigo (par harmônico com violet).
      Positioned(
        top: 180,
        left: -100,
        child: IgnorePointer(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  secondary.withValues(alpha: isDark ? 0.10 : 0.045),
                  secondary.withValues(alpha: 0),
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
                                _buildSearchField(context),
                                const SizedBox(height: _kSectionGap + 2),
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
    final secondary = _accentSecondary(context);
    final isDark = theme.brightness == Brightness.dark;
    final stats = _heroStats;
    final overdue = _baselineOverdue > 0 ? _baselineOverdue : stats.overdue;
    // Total HONESTO do filtro atual: prefere `_response.total` (autoridade
    // do backend pra essa query), e cai pro stats só como fallback até a
    // resposta chegar. Quando o bucket é "Todas" e o baseline já está
    // populado, usa esse pra cobrir o caso de servidores que retornam
    // total escopado pela paginação.
    final filteredTotal = _response.total > 0
        ? _response.total
        : (_activeBucket == _Bucket.all
            ? _baselineTotal
            : stats.total);
    final danger = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;
    final subtitleColor = ThemeHelpers.textSecondaryColor(context);
    final hasSearch = _appliedSearch.trim().isNotEmpty;
    final hasOverdue = overdue > 0;

    // Headline curta — não tenta gritar "X tarefas aguardam você". Só
    // diz o que a tela é. O contexto (filtro, busca) vai no chip ao lado.
    const headline = 'Suas tarefas';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Ícone "marca" — gradiente violet/indigo, calmo,
              // sem nada de vermelho.
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [accent, secondary],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: isDark ? 0.14 : 0.32),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: isDark ? 0.32 : 0.18),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                      spreadRadius: -4,
                    ),
                  ],
                ),
                child: const Icon(
                  LucideIcons.listChecks,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          headline,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: ThemeHelpers.textColor(context),
                            letterSpacing: -0.4,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(width: 9),
                        // Badge com o TOTAL real do filtro corrente.
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: accent.withValues(
                                alpha: isDark ? 0.16 : 0.08),
                            border: Border.all(
                              color: accent.withValues(
                                  alpha: isDark ? 0.34 : 0.22),
                            ),
                          ),
                          child: Text(
                            '$filteredTotal',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.2,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hasSearch
                          ? 'Filtradas por "${_appliedSearch.trim()}"'
                          : 'Visão · ${_bucketLabel(_activeBucket)[0].toUpperCase()}${_bucketLabel(_activeBucket).substring(1)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: subtitleColor,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              // Alerta de atraso (se houver) — chip compacto, vermelho
              // SÓ aqui, onde faz sentido. Sem pulse dot solto.
              if (hasOverdue) ...[
                const SizedBox(width: 8),
                _OverdueAlertButton(
                  count: overdue,
                  danger: danger,
                  onTap: () => _selectBucket(_Bucket.overdue),
                ),
              ],
            ],
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

  // ─── Search ──────────────────────────────────────────────────────────

  Widget _buildSearchField(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accentColor(context);
    final hasFocus = _searchController.text.isNotEmpty;
    final cardBg = isDark
        ? AppColors.background.cardBackgroundDarkMode
        : AppColors.background.cardBackground;
    final borderColor = isDark
        ? AppColors.border.borderDarkMode
        : AppColors.border.border;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasFocus
              ? accent.withValues(alpha: isDark ? 0.55 : 0.42)
              : borderColor,
        ),
        boxShadow: hasFocus
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: isDark ? 0.20 : 0.14),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                  spreadRadius: -4,
                ),
              ]
            : [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.18)
                      : Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                  spreadRadius: -4,
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Row(
          children: [
            // Ícone da busca dentro de um "bullet" sutil tintado.
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: hasFocus
                    ? accent.withValues(alpha: isDark ? 0.18 : 0.10)
                    : Colors.transparent,
              ),
              alignment: Alignment.center,
              child: Icon(
                LucideIcons.search,
                size: 16,
                color: hasFocus
                    ? accent
                    : ThemeHelpers.textSecondaryColor(context),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (v) {
                  _onSearchChanged(v);
                  setState(() {});
                },
                textInputAction: TextInputAction.search,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
                cursorColor: accent,
                decoration: InputDecoration(
                  hintText: 'Buscar tarefas pelo card pai…',
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context)
                        .withValues(alpha: 0.7),
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.1,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 12),
                  isDense: true,
                ),
              ),
            ),
            if (_searchController.text.isNotEmpty) ...[
              const SizedBox(width: 4),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    _searchController.clear();
                    _onSearchChanged('');
                    setState(() {});
                  },
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.04),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      LucideIcons.x,
                      size: 14,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Bucket pills ────────────────────────────────────────────────────

  Widget _buildBucketsRail(BuildContext context) {
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
    final subtitleColor = ThemeHelpers.textSecondaryColor(context);

    final stats = _heroStats;

    final tabs = <_BucketSpec>[
      _BucketSpec(
        bucket: _Bucket.pending,
        icon: LucideIcons.inbox,
        label: 'Pendentes',
        // Contagem REAL do bucket (vinda do baseline desfiltrado), com
        // fallback pro `_heroStats` enquanto o baseline ainda não chegou.
        count:
            _baselinePending > 0 ? _baselinePending : stats.pending,
        color: warn,
      ),
      _BucketSpec(
        bucket: _Bucket.today,
        icon: LucideIcons.calendar,
        label: 'Hoje',
        count: _baselineToday > 0 ? _baselineToday : _todayCount(),
        color: accent,
      ),
      _BucketSpec(
        bucket: _Bucket.overdue,
        icon: LucideIcons.alertTriangle,
        label: 'Atrasadas',
        count:
            _baselineOverdue > 0 ? _baselineOverdue : stats.overdue,
        color: danger,
      ),
      _BucketSpec(
        bucket: _Bucket.completed,
        icon: LucideIcons.checkCircle2,
        label: 'Concluídas',
        count: _baselineCompleted > 0
            ? _baselineCompleted
            : stats.completed,
        color: ok,
      ),
      _BucketSpec(
        bucket: _Bucket.all,
        icon: LucideIcons.list,
        label: 'Todas',
        count: _baselineTotal > 0 ? _baselineTotal : stats.total,
        color: const Color(0xFF7C3AED),
      ),
    ];

    final activeSpec = tabs.firstWhere(
      (t) => t.bucket == _activeBucket,
      orElse: () => tabs.first,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header da seção de navegação — orienta o usuário e mostra
        // claramente qual filtro está ativo no momento (não fica só
        // no destaque visual da pill).
        Padding(
          padding: const EdgeInsets.fromLTRB(_kPagePadH, 0, _kPagePadH, 8),
          child: Row(
            children: [
              Icon(LucideIcons.slidersHorizontal, size: 12, color: subtitleColor),
              const SizedBox(width: 6),
              Text(
                'FILTRAR POR',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: subtitleColor,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  fontSize: 10,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: subtitleColor.withValues(alpha: 0.45),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  '${activeSpec.label} · ${activeSpec.count}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: activeSpec.color,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Row scrollable das pills.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: _kPagePadH - 2),
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
        ),
      ],
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
          if (i > 0) const SizedBox(height: 10),
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

/// Botão compacto de "atenção: tem atraso" — aparece no canto direito do
/// hero somente quando há overdue. Clique pula direto pra esse bucket.
class _OverdueAlertButton extends StatelessWidget {
  final int count;
  final Color danger;
  final VoidCallback onTap;
  const _OverdueAlertButton({
    required this.count,
    required this.danger,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: danger.withValues(alpha: 0.18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: danger.withValues(alpha: isDark ? 0.14 : 0.08),
            border: Border.all(
              color: danger.withValues(alpha: isDark ? 0.34 : 0.24),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.alertTriangle, size: 14, color: danger),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: danger,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

