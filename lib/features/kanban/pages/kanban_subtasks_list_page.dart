import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../../../shared/services/module_access_service.dart';
import '../models/kanban_subtask_models.dart';
import '../services/kanban_subtask_service.dart';
import '../widgets/subtask_flush_row.dart';

/// Tela global "Lista de tarefas" — paridade com `MySubTasksPage.tsx`.
///
/// Identidade visual **flush**, alinhada ao DNA da Fila de Aprovação:
/// hero editorial (eyebrow com dot + número grande + faixa de KPIs por
/// categoria), busca animada, **abas flush fixas com sublinhado**, cabeçalho
/// de painel com ícone tonal e itens em **linhas flush** (sem card/sombra).
/// O acento violet/indigo e o check de conclusão são a característica própria
/// da tela; o vermelho fica reservado para atraso real.
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

  // ─── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_bootLoading) {
      return AppScaffold(
        title: 'Tarefas',
        showBottomNavigation: false,
        body: _buildPageSkeleton(context),
      );
    }
    return AppScaffold(
      title: 'Tarefas',
      showBottomNavigation: false,
      body: RefreshIndicator(
        color: _accentColor(context),
        onRefresh: _refresh,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
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
                        const SizedBox(height: _kSectionGap),
                        _buildSearchField(context),
                        const SizedBox(height: _kSectionGap),
                      ],
                    ),
                  ),
                  _buildTabsRail(context),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _kPagePadH,
                      _kSectionGap,
                      _kPagePadH,
                      _kPagePadBottom,
                    ),
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

  /// Painel da aba ativa — cabeçalho (ícone tonal + eyebrow + título + dica)
  /// seguido do corpo (lista flush / estados de vazio/erro/carregando).
  Widget _buildActivePanel(BuildContext context) {
    return Column(
      key: ValueKey('panel-${_activeBucket.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPanelHeader(context),
        const SizedBox(height: 14),
        _buildBody(context),
      ],
    ).animate(key: ValueKey('panel-${_activeBucket.name}')).fadeIn(
          duration: 220.ms,
        );
  }

  ({IconData icon, String eyebrow, String title, String hint, Color tone})
      _panelMeta(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accentColor(context);
    final ok =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final warn =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    switch (_activeBucket) {
      case _Bucket.pending:
        return (
          icon: LucideIcons.inbox,
          eyebrow: 'A FAZER',
          title: 'Tarefas pendentes',
          hint: 'Tudo que ainda aguarda conclusão.',
          tone: warn,
        );
      case _Bucket.today:
        return (
          icon: LucideIcons.calendar,
          eyebrow: 'AGENDA DE HOJE',
          title: 'Para hoje',
          hint: 'Pendências com prazo para hoje.',
          tone: accent,
        );
      case _Bucket.overdue:
        return (
          icon: LucideIcons.alertTriangle,
          eyebrow: 'ATENÇÃO',
          title: 'Tarefas atrasadas',
          hint: 'Passaram do prazo e precisam de ação.',
          tone: danger,
        );
      case _Bucket.completed:
        return (
          icon: LucideIcons.checkCircle2,
          eyebrow: 'HISTÓRICO',
          title: 'Concluídas',
          hint: 'O que você já finalizou.',
          tone: ok,
        );
      case _Bucket.all:
        return (
          icon: LucideIcons.list,
          eyebrow: 'VISÃO GERAL',
          title: 'Todas as tarefas',
          hint: 'Pendentes e concluídas, sem filtro.',
          tone: accent,
        );
    }
  }

  Widget _buildPanelHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final meta = _panelMeta(context);
    final tone = meta.tone;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: tone.withValues(alpha: isDark ? 0.20 : 0.12),
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

  // ─── Hero editorial (mesmo DNA da Fila de Aprovação) ──────────────────

  Widget _buildGreeting(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accentColor(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final emerald =
        isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
    final stats = _heroStats;

    final pending = _baselinePending > 0 ? _baselinePending : stats.pending;
    final overdue = _baselineOverdue > 0 ? _baselineOverdue : stats.overdue;
    final hasSearch = _appliedSearch.trim().isNotEmpty;
    final hasOverdue = overdue > 0;

    final dotColor =
        hasOverdue ? danger : (pending > 0 ? accent : emerald);
    final subtitle = hasSearch
        ? 'Filtrando por "${_appliedSearch.trim()}".'
        : hasOverdue
            ? '$overdue ${overdue == 1 ? 'tarefa atrasada' : 'tarefas atrasadas'} · priorize o que passou do prazo.'
            : (pending == 0
                ? 'Tudo em dia — nenhuma tarefa pendente agora.'
                : 'Organize o que aguarda você e seu time.');

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Eyebrow editorial — dot semântico + label uppercase.
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColor,
                  boxShadow: [
                    BoxShadow(
                      color: dotColor.withValues(alpha: 0.55),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              Text(
                'MINHAS TAREFAS',
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
          // Headline com número grande + rótulo na base (editorial).
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$pending',
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
                  pending == 1 ? 'pendente' : 'pendentes',
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
          _buildHeroKpiStrip(context),
        ],
      ),
    );
  }

  /// Faixa editorial de KPIs por categoria — 4 colunas separadas por filete.
  Widget _buildHeroKpiStrip(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accentColor(context);
    final ok =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final warn =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final stats = _heroStats;
    final divider = ThemeHelpers.borderColor(context).withValues(alpha: 0.45);

    final blocks = <Widget>[
      _heroKpiBlock(context, LucideIcons.inbox, 'PENDENTES',
          _baselinePending > 0 ? _baselinePending : stats.pending, 'a fazer', warn),
      _heroKpiBlock(context, LucideIcons.calendar, 'HOJE',
          _baselineToday > 0 ? _baselineToday : _todayCount(), 'no prazo', accent),
      _heroKpiBlock(context, LucideIcons.alertTriangle, 'ATRASADAS',
          _baselineOverdue > 0 ? _baselineOverdue : stats.overdue, 'agir', danger),
      _heroKpiBlock(context, LucideIcons.checkCircle2, 'CONCLUÍDAS',
          _baselineCompleted > 0 ? _baselineCompleted : stats.completed, 'feito', ok),
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

  Widget _heroKpiBlock(
    BuildContext context,
    IconData icon,
    String label,
    int value,
    String sub,
    Color tone,
  ) {
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
                    letterSpacing: 1.0,
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
              '$value',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: tone,
                letterSpacing: -0.6,
                height: 1.0,
                fontSize: 22,
                fontFeatures: const [FontFeature.tabularFigures()],
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

  // ─── Abas flush fixas (sublinhado, sem scroll) ────────────────────────

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

    final stats = _heroStats;

    final tabs = <_BucketSpec>[
      _BucketSpec(
        bucket: _Bucket.pending,
        icon: LucideIcons.inbox,
        label: 'Pendentes',
        // Contagem REAL do bucket (vinda do baseline desfiltrado), com
        // fallback pro `_heroStats` enquanto o baseline ainda não chegou.
        count: _baselinePending > 0 ? _baselinePending : stats.pending,
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
        count: _baselineOverdue > 0 ? _baselineOverdue : stats.overdue,
        color: danger,
      ),
      _BucketSpec(
        bucket: _Bucket.completed,
        icon: LucideIcons.checkCircle2,
        label: 'Concluídas',
        count: _baselineCompleted > 0 ? _baselineCompleted : stats.completed,
        color: ok,
      ),
      _BucketSpec(
        bucket: _Bucket.all,
        icon: LucideIcons.list,
        label: 'Todas',
        count: _baselineTotal > 0 ? _baselineTotal : stats.total,
        color: accent,
      ),
    ];

    // Barra de abas **flush** com sublinhado — fixa (sem scroll): cada bucket
    // ocupa fração igual da largura, contagem em badge sobre o ícone e
    // indicador inferior na cor do bucket ativo. Mesmo DNA de Aprovações.
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: _kPagePadH - 8),
      child: Row(
        children: [
          for (final t in tabs)
            Expanded(
              child: _FlushTab(
                spec: t,
                selected: _activeBucket == t.bucket,
                onTap: () => _selectBucket(t.bucket),
              ),
            ),
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
        for (var i = 0; i < _response.data.length; i++)
          SubTaskFlushRow(
            subtask: _response.data[i],
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(4, (i) => const _TaskRowSkeleton()),
    );
  }

  /// Skeleton de **tela inteira** — exibido enquanto a primeira carga não
  /// chega. Cobre hero editorial, KPIs, busca, abas e lista flush — sem
  /// layout shift quando o conteúdo de fato aparece.
  Widget _buildPageSkeleton(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          _kPagePadH,
          _kPagePadTop,
          _kPagePadH,
          _kPagePadBottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero editorial: eyebrow + número grande + subtítulo
            const SizedBox(height: 4),
            SkeletonBox(width: 150, height: 11, borderRadius: 999),
            const SizedBox(height: 12),
            SkeletonBox(width: 110, height: 34, borderRadius: 8),
            const SizedBox(height: 10),
            SkeletonBox(width: 230, height: 12, borderRadius: 4),
            const SizedBox(height: 20),
            // KPI strip
            Row(
              children: List.generate(
                4,
                (i) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 50, height: 9, borderRadius: 999),
                        const SizedBox(height: 8),
                        SkeletonBox(width: 28, height: 20, borderRadius: 4),
                        const SizedBox(height: 6),
                        SkeletonBox(width: 36, height: 9, borderRadius: 999),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            // Search
            SkeletonBox(width: double.infinity, height: 50, borderRadius: 14),
            const SizedBox(height: _kSectionGap + 4),
            // Abas flush
            Row(
              children: List.generate(
                5,
                (i) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 12),
                    child: Column(
                      children: [
                        SkeletonBox(width: 19, height: 19, borderRadius: 6),
                        const SizedBox(height: 6),
                        SkeletonBox(width: 44, height: 10, borderRadius: 999),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: _kSectionGap + 6),
            // Lista flush
            ...List.generate(4, (i) => const _TaskRowSkeleton()),
          ],
        ),
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

/// Aba **flush** vertical (ícone com badge de contagem + rótulo curto), num
/// layout fixo de largura igual (sem scroll). Indicador (sublinhado) na cor do
/// bucket quando ativa. Mesmo DNA de navegação da Fila de Aprovação.
class _FlushTab extends StatelessWidget {
  final _BucketSpec spec;
  final bool selected;
  final VoidCallback onTap;

  const _FlushTab({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = spec.color;
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
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 22,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        Icon(spec.icon, size: 19, color: fg),
                        if (spec.count > 0)
                          Positioned(
                            top: -7,
                            right: -12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              constraints: const BoxConstraints(minWidth: 16),
                              decoration: BoxDecoration(
                                color: tone,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: ThemeHelpers.cardBackgroundColor(
                                      context),
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                spec.count > 99 ? '99+' : '${spec.count}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 9.5,
                                  height: 1.25,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      spec.label,
                      maxLines: 1,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: fg,
                        fontWeight:
                            selected ? FontWeight.w900 : FontWeight.w600,
                        letterSpacing: 0.1,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
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

/// Placeholder de carregamento que reproduz a linha flush real
/// (`SubTaskFlushRow`): check à esquerda, chips, título e meta com filete.
class _TaskRowSkeleton extends StatelessWidget {
  const _TaskRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 26, height: 26, borderRadius: 999),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SkeletonText(width: 70, height: 18, borderRadius: 999),
                    const SizedBox(width: 6),
                    SkeletonText(width: 54, height: 18, borderRadius: 999),
                  ],
                ),
                const SizedBox(height: 9),
                SkeletonText(width: double.infinity, height: 14),
                const SizedBox(height: 8),
                SkeletonText(width: 150, height: 12),
                const SizedBox(height: 10),
                SkeletonText(width: 110, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

