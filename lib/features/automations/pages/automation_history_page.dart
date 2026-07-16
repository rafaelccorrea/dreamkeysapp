import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/automation_models.dart';
import '../services/automation_service.dart';
import '../widgets/automation_card.dart';
import '../widgets/execution_filters_sheet.dart';

/// Tela **Histórico de Execuções** (`/automations/:id/history`) — paridade com
/// AutomationHistoryPage.tsx: lista paginada dos disparos da automação com
/// filtros (status + período) no modal padrão do app. Tocar numa execução abre
/// o detalhe com os logs (`GET /:id/executions/:executionId`).
class AutomationHistoryPage extends StatefulWidget {
  final String automationId;

  /// Nome já conhecido (passado pela tela de detalhe) — evita flash sem título.
  final String? automationName;

  const AutomationHistoryPage({
    super.key,
    required this.automationId,
    this.automationName,
  });

  @override
  State<AutomationHistoryPage> createState() => _AutomationHistoryPageState();
}

class _AutomationHistoryPageState extends State<AutomationHistoryPage> {
  static const double _kPagePadH = 16;
  static const int _pageSize = 20;

  final DateFormat _dateTime = DateFormat('dd/MM/yyyy · HH:mm', 'pt_BR');

  String? _automationName;
  List<AutomationExecution> _executions = const [];
  ExecutionFilters _filters = const ExecutionFilters(limit: _pageSize);
  int _total = 0;
  int _page = 1;
  int _totalPages = 1;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _automationName = widget.automationName;
    _load();
    if (_automationName == null) _loadName();
  }

  Color _accent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.primary.primaryDarkMode
          : AppColors.primary.primary;

  // ─── Dados ──────────────────────────────────────────────────────────────

  Future<void> _loadName() async {
    final res = await AutomationService.instance.getById(widget.automationId);
    if (!mounted || !res.success || res.data == null) return;
    setState(() => _automationName = res.data!.name);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await AutomationService.instance.getExecutions(
      widget.automationId,
      filters: _filters.copyWith(page: 1),
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _executions = res.data!.executions;
        _page = res.data!.page;
        _totalPages = res.data!.totalPages;
        _total = res.data!.total;
      } else {
        _error = res.message ?? 'Erro ao carregar histórico';
      }
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _page >= _totalPages) return;
    setState(() => _loadingMore = true);
    final res = await AutomationService.instance.getExecutions(
      widget.automationId,
      filters: _filters.copyWith(page: _page + 1),
    );
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (res.success && res.data != null) {
        _executions = [..._executions, ...res.data!.executions];
        _page = res.data!.page;
        _totalPages = res.data!.totalPages;
        _total = res.data!.total;
      }
    });
  }

  void _openFilters() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => ExecutionFiltersSheet(
        initialFilters: _filters,
        onApply: (f) {
          setState(() => _filters = f);
          _load();
        },
        onClear: () {
          setState(() => _filters = const ExecutionFilters(limit: _pageSize));
          _load();
        },
      ),
    );
  }

  void _openExecutionDetail(AutomationExecution execution) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => _ExecutionDetailSheet(
        automationId: widget.automationId,
        execution: execution,
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final accent = _accent(context);
    final activeFilters = _filters.activeCount;

    return AppScaffold(
      title: 'Histórico de Execuções',
      showBottomNavigation: false,
      showDrawer: false,
      actions: [
        IconButton(
          onPressed: _openFilters,
          tooltip: 'Filtros',
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(LucideIcons.listFilter,
                  size: 21, color: ThemeHelpers.textColor(context)),
              if (activeFilters > 0)
                Positioned(
                  right: -5,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.all(3.5),
                    decoration:
                        BoxDecoration(color: accent, shape: BoxShape.circle),
                    child: Text(
                      '$activeFilters',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
      body: RefreshIndicator(
        color: accent,
        onRefresh: _load,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding:
                    const EdgeInsets.fromLTRB(_kPagePadH, 10, _kPagePadH, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHero(context),
                    const SizedBox(height: 16),
                    _buildBody(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Hero flush ─────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accent(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    final subtitle = _loading
        ? 'Carregando execuções…'
        : _total == 0
            ? 'Os disparos desta automação aparecem aqui.'
            : '$_total execuç${_total == 1 ? 'ão registrada' : 'ões registradas'}'
                '${_filters.activeCount > 0 ? ' com os filtros aplicados' : ''}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.55),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Text(
              'HISTÓRICO DE EXECUÇÕES',
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.2,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _automationName ?? 'Automação',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            color: textColor,
            letterSpacing: -0.4,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: secondary,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  // ─── Corpo ──────────────────────────────────────────────────────────────

  Widget _buildBody(BuildContext context) {
    if (_loading) return _buildSkeleton();
    if (_error != null) return _buildError(context, _error!);
    if (_executions.isEmpty) return _buildEmpty(context);

    final children = <Widget>[];
    var animIndex = 0;
    for (final group in _groupByDay(_executions)) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 14));
      children.add(_subsectionHeader(context, group.label, group.items.length));
      children.add(const SizedBox(height: 4));
      for (final exec in group.items) {
        children.add(
          _ExecutionRow(
            execution: exec,
            dateTime: _dateTime,
            onTap: () => _openExecutionDetail(exec),
          ).animate(key: ValueKey('e-${exec.id}')).fadeIn(
                delay: Duration(milliseconds: 25 * (animIndex++).clamp(0, 12)),
                duration: 200.ms,
              ),
        );
      }
    }

    if (_page < _totalPages) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Center(
            child: _loadingMore
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: _accent(context),
                    ),
                  )
                : OutlinedButton.icon(
                    onPressed: _loadMore,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _accent(context),
                      side: BorderSide(
                        color: _accent(context).withValues(alpha: 0.45),
                      ),
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  /// Agrupa por dia preservando a ordem (lista já vem desc por data).
  List<({String label, List<AutomationExecution> items})> _groupByDay(
      List<AutomationExecution> list) {
    final fmt = DateFormat("d 'de' MMMM 'de' yyyy", 'pt_BR');
    final map = <String, List<AutomationExecution>>{};
    for (final e in list) {
      final d = e.createdAt?.toLocal();
      final key = d == null ? 'Sem data' : fmt.format(d);
      map.putIfAbsent(key, () => []).add(e);
    }
    return map.entries
        .map((e) => (label: e.key, items: e.value))
        .toList(growable: false);
  }

  Widget _subsectionHeader(BuildContext context, String label, int count) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Row(
      children: [
        Icon(LucideIcons.calendarDays, size: 14, color: secondary),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: secondary,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color:
                ThemeHelpers.borderLightColor(context).withValues(alpha: 0.7),
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
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Container(
              height: 1,
              color:
                  ThemeHelpers.borderLightColor(context).withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Estados ────────────────────────────────────────────────────────────

  /// Skeleton fiel à linha de execução: glyph + status + bits + data.
  Widget _buildSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(
        6,
        (_) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 40, height: 40, borderRadius: 12),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonText(width: 140, height: 14),
                    SizedBox(height: 7),
                    SkeletonText(width: double.infinity, height: 12),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const SkeletonText(width: 56, height: 18, borderRadius: 999),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accent(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hasFilters = _filters.activeCount > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 4),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [
                accent.withValues(alpha: 0.18),
                accent.withValues(alpha: 0.06),
              ]),
              border: Border.all(color: accent.withValues(alpha: 0.32)),
            ),
            child: Icon(
              hasFilters ? LucideIcons.searchX : LucideIcons.history,
              color: accent,
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            hasFilters
                ? 'Nada com esses filtros'
                : 'Nenhuma execução registrada',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hasFilters
                ? 'Ajuste ou limpe os filtros para ver outras execuções.'
                : 'Quando a automação disparar, os registros aparecem aqui.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondary,
              height: 1.4,
            ),
          ),
          if (hasFilters) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () {
                setState(
                    () => _filters = const ExecutionFilters(limit: _pageSize));
                _load();
              },
              icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
              label: const Text('Limpar filtros'),
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

// ─── Linha de execução ───────────────────────────────────────────────────────

class _ExecutionRow extends StatelessWidget {
  final AutomationExecution execution;
  final DateFormat dateTime;
  final VoidCallback onTap;

  const _ExecutionRow({
    required this.execution,
    required this.dateTime,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final tone = executionStatusColor(context, execution.status);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: tone.withValues(alpha: isDark ? 0.16 : 0.1),
                  border: Border.all(color: tone.withValues(alpha: 0.28)),
                ),
                child: Icon(executionStatusIcon(execution.status),
                    color: tone, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      execution.createdAt != null
                          ? dateTime.format(execution.createdAt!.toLocal())
                          : 'Sem data',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.2,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        AutomationSpecBit(
                          icon: LucideIcons.send,
                          text: '${execution.notificationsSent} '
                              'notificaç${execution.notificationsSent == 1 ? 'ão' : 'ões'}',
                          color: neutral,
                        ),
                        AutomationSpecBit(
                          icon: LucideIcons.layers,
                          text: '${execution.itemsProcessed} '
                              'ite${execution.itemsProcessed == 1 ? 'm' : 'ns'}',
                          color: neutral,
                        ),
                        AutomationSpecBit(
                          icon: LucideIcons.timer,
                          text: '${execution.executionTimeMs} ms',
                          color: neutral,
                        ),
                      ],
                    ),
                    if (execution.status != AutomationExecutionStatus.success &&
                        (execution.errorMessage ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        execution.errorMessage!.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: tone,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AutomationPill(label: execution.status.label, color: tone),
                  const SizedBox(height: 8),
                  Icon(LucideIcons.chevronRight, size: 15, color: neutral),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Bottom sheet de detalhe da execução (com logs) ──────────────────────────

class _ExecutionDetailSheet extends StatefulWidget {
  final String automationId;
  final AutomationExecution execution;

  const _ExecutionDetailSheet({
    required this.automationId,
    required this.execution,
  });

  @override
  State<_ExecutionDetailSheet> createState() => _ExecutionDetailSheetState();
}

class _ExecutionDetailSheetState extends State<_ExecutionDetailSheet> {
  AutomationExecution? _detailed;
  bool _loadingLogs = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final res = await AutomationService.instance
        .getExecution(widget.automationId, widget.execution.id);
    if (!mounted) return;
    setState(() {
      _loadingLogs = false;
      if (res.success && res.data != null) _detailed = res.data;
    });
  }

  Color _logColor(BuildContext context, AutomationLogLevel level) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (level) {
      case AutomationLogLevel.error:
        return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
      case AutomationLogLevel.warn:
        return isDark
            ? AppColors.status.warningDarkMode
            : AppColors.status.warning;
      case AutomationLogLevel.info:
        return isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
      case AutomationLogLevel.debug:
      case AutomationLogLevel.unknown:
        return ThemeHelpers.textSecondaryColor(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final execution = _detailed ?? widget.execution;
    final tone = executionStatusColor(context, execution.status);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final fmt = DateFormat('dd/MM/yyyy HH:mm:ss', 'pt_BR');
    final logs = execution.logs;

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: tone.withValues(alpha: isDark ? 0.22 : 0.14),
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
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.82,
          ),
          child: SingleChildScrollView(
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
                        color: tone.withValues(alpha: isDark ? 0.18 : 0.1),
                        border: Border.all(color: tone.withValues(alpha: 0.3)),
                      ),
                      child: Icon(executionStatusIcon(execution.status),
                          color: tone, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Execução · ${execution.status.label}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: ThemeHelpers.textColor(context),
                              letterSpacing: -0.3,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            execution.createdAt != null
                                ? fmt.format(execution.createdAt!.toLocal())
                                : 'Sem data',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: secondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _row(context, 'Notificações enviadas',
                    '${execution.notificationsSent}'),
                _row(context, 'Itens processados',
                    '${execution.itemsProcessed}'),
                _row(context, 'Erros', '${execution.errorsCount}'),
                _row(context, 'Tempo de execução',
                    '${execution.executionTimeMs} ms'),
                if ((execution.errorMessage ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: isDark ? 0.12 : 0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: tone.withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      execution.errorMessage!.trim(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textColor(context),
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Text(
                  'LOGS DA EXECUÇÃO',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 10),
                if (_loadingLogs)
                  Column(
                    children: List.generate(
                      3,
                      (_) => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: SkeletonText(
                            width: double.infinity, height: 13),
                      ),
                    ),
                  )
                else if (logs.isEmpty)
                  Text(
                    'Nenhum log registrado para esta execução.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  for (final log in logs)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: _logColor(context, log.level),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      log.level.label,
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.8,
                                        color: _logColor(context, log.level),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (log.createdAt != null)
                                      Text(
                                        DateFormat('HH:mm:ss', 'pt_BR').format(
                                            log.createdAt!.toLocal()),
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w600,
                                          color: secondary,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  log.message,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: ThemeHelpers.textColor(context),
                                    fontWeight: FontWeight.w600,
                                    height: 1.35,
                                    fontSize: 12,
                                  ),
                                ),
                                if ((log.details ?? '').trim().isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    log.details!.trim(),
                                    style:
                                        theme.textTheme.bodySmall?.copyWith(
                                      color: secondary,
                                      height: 1.3,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
