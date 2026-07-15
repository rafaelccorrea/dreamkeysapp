import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/goal_model.dart';
import '../services/goal_service.dart';
import '../widgets/goal_card.dart';

/// Análise detalhada da meta — paridade com a GoalAnalyticsPage do
/// imobx-front: KPIs (média diária, projeção, melhor/pior dia), insights e
/// evolução temporal. O gauge e o gráfico de barras seguem o approach de
/// charts do dashboard do app (CustomPainter próprio, cores semânticas).
class GoalAnalyticsPage extends StatefulWidget {
  final String goalId;

  const GoalAnalyticsPage({super.key, required this.goalId});

  @override
  State<GoalAnalyticsPage> createState() => _GoalAnalyticsPageState();
}

class _GoalAnalyticsPageState extends State<GoalAnalyticsPage> {
  static const double _kPagePadH = 16;

  Goal? _goal;
  GoalAnalytics? _analytics;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final results = await Future.wait([
      GoalService.instance.getGoalById(widget.goalId),
      GoalService.instance.getGoalAnalytics(widget.goalId),
    ]);
    if (!mounted) return;
    final goalRes = results[0];
    final analyticsRes = results[1];
    setState(() {
      _loading = false;
      if (analyticsRes.success && analyticsRes.data != null) {
        _analytics = analyticsRes.data as GoalAnalytics;
        _goal = goalRes.success ? goalRes.data as Goal? : null;
        _error = null;
      } else {
        _error =
            analyticsRes.message ?? 'Erro ao carregar análise da meta';
      }
    });
  }

  Color _accent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.primary.primaryDarkMode
          : AppColors.primary.primary;

  Color _green(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.status.greenDarkMode
          : AppColors.status.green;

  Color _red(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.status.errorDarkMode
          : AppColors.status.error;

  Color _blue(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.status.infoDarkMode
          : AppColors.status.info;

  Color _amber(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;

  GoalType get _valueType => _goal?.type ?? GoalType.salesValue;

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loading) {
      body = _buildSkeleton(context);
    } else if (_error != null) {
      body = _buildError(context);
    } else {
      body = _buildContent(context);
    }

    return AppScaffold(
      title: 'Análise da meta',
      showBottomNavigation: false,
      showDrawer: false,
      body: body,
    );
  }

  Widget _buildContent(BuildContext context) {
    final a = _analytics!;
    return RefreshIndicator(
      color: _accent(context),
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(_kPagePadH, 12, _kPagePadH, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHero(context, a),
            const SizedBox(height: 20),
            _buildGaugePanel(context, a),
            const SizedBox(height: 20),
            _buildKpiGrid(context, a),
            if (a.insights.isNotEmpty) ...[
              const SizedBox(height: 20),
              _buildInsights(context, a),
            ],
            const SizedBox(height: 20),
            _buildEvolution(context, a),
          ],
        ).animate().fadeIn(duration: 240.ms),
      ),
    );
  }

  // ─── Hero ────────────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context, GoalAnalytics a) {
    final theme = Theme.of(context);
    final accent = _accent(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final goal = _goal;
    final onTrackTone =
        goal == null ? secondary : goalProgressColor(context, goal);

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
                color: onTrackTone,
                boxShadow: [
                  BoxShadow(
                    color: onTrackTone.withValues(alpha: 0.55),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Text(
              'ANÁLISE DETALHADA',
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((goal?.icon ?? '').isNotEmpty) ...[
              Text(goal!.icon!, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                a.title.isNotEmpty ? a.title : (goal?.title ?? 'Meta'),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: -0.6,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
        if (goal != null) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _heroPill(context, goalTypeIcon(goal.type), goal.type.label,
                  secondary),
              _heroPill(context, LucideIcons.calendarSync, goal.period.label,
                  secondary),
              _heroPill(
                context,
                goal.scope == GoalScope.user
                    ? LucideIcons.user
                    : goal.scope == GoalScope.team
                        ? LucideIcons.users2
                        : LucideIcons.building2,
                goal.ownerLabel ?? goal.scope.label,
                secondary,
              ),
              _heroPill(context, LucideIcons.activity, goal.status.label,
                  goalStatusColor(context, goal.status)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _heroPill(
      BuildContext context, IconData icon, String label, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Gauge de progresso ──────────────────────────────────────────────────

  Widget _buildGaugePanel(BuildContext context, GoalAnalytics a) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final goal = _goal;
    final tone =
        goal == null ? _green(context) : goalProgressColor(context, goal);
    final progress = (a.currentProgress / 100).clamp(0.0, 1.0);
    final pctLabel =
        '${NumberFormat('#,##0.0', 'pt_BR').format(a.currentProgress)}%';

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
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
        children: [
          SizedBox(
            height: 118,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _GoalGaugePainter(
                      progress: progress,
                      color: tone,
                      trackColor: tone.withValues(alpha: isDark ? 0.16 : 0.12),
                      tickColor: secondary,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        pctLabel,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: tone,
                          letterSpacing: -1,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'DO OBJETIVO',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: secondary,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (goal != null) ...[
            const SizedBox(height: 14),
            Container(
              height: 1,
              color:
                  ThemeHelpers.borderLightColor(context).withValues(alpha: 0.7),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _gaugeStat(
                    context,
                    'REALIZADO',
                    formatGoalValueCompact(goal.currentValue, goal.type),
                    tone,
                  ),
                ),
                Expanded(
                  child: _gaugeStat(
                    context,
                    'ALVO',
                    formatGoalValueCompact(goal.targetValue, goal.type),
                    ThemeHelpers.textColor(context),
                  ),
                ),
                Expanded(
                  child: _gaugeStat(
                    context,
                    'RESTANTE',
                    formatGoalValueCompact(goal.remaining, goal.type),
                    _amber(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(LucideIcons.hourglass, size: 12,
                    color: ThemeHelpers.textSecondaryColor(context)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    goal.daysRemaining <= 0
                        ? 'Período encerrado · ${goal.daysTotal} dias no total'
                        : '${goal.daysElapsed} de ${goal.daysTotal} dias decorridos · '
                            '${goal.daysRemaining} restante${goal.daysRemaining == 1 ? '' : 's'}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  goal.projectedValue >= goal.targetValue
                      ? LucideIcons.trendingUp
                      : LucideIcons.trendingDown,
                  size: 12,
                  color: goal.projectedValue >= goal.targetValue
                      ? _green(context)
                      : _red(context),
                ),
                const SizedBox(width: 4),
                Text(
                  'Projeção ${formatGoalValueCompact(goal.projectedValue, goal.type)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: goal.projectedValue >= goal.targetValue
                        ? _green(context)
                        : _red(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _gaugeStat(
      BuildContext context, String label, String value, Color tone) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
            fontSize: 9,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: tone,
              letterSpacing: -0.3,
            ),
          ),
        ),
      ],
    );
  }

  // ─── KPIs ────────────────────────────────────────────────────────────────

  Widget _buildKpiGrid(BuildContext context, GoalAnalytics a) {
    final dateFmt = DateFormat('dd MMM yyyy', 'pt_BR');
    final tiles = <Widget>[
      _kpiTile(
        context,
        icon: LucideIcons.sigma,
        label: 'MÉDIA DIÁRIA',
        value: formatGoalValueCompact(a.averageDailyProgress, _valueType),
        sub: 'progresso por dia',
        tone: _blue(context),
      ),
      if (a.projectedCompletion != null)
        _kpiTile(
          context,
          icon: LucideIcons.calendarCheck,
          label: 'PROJEÇÃO',
          value: dateFmt.format(a.projectedCompletion!.toLocal()),
          sub: 'conclusão estimada',
          tone: _green(context),
        ),
      if (a.bestDay != null)
        _kpiTile(
          context,
          icon: LucideIcons.trendingUp,
          label: 'MELHOR DIA',
          value: formatGoalValueCompact(a.bestDay!.value, _valueType),
          sub: a.bestDay!.date == null
              ? '—'
              : dateFmt.format(a.bestDay!.date!.toLocal()),
          tone: _green(context),
        ),
      if (a.worstDay != null)
        _kpiTile(
          context,
          icon: LucideIcons.trendingDown,
          label: 'PIOR DIA',
          value: formatGoalValueCompact(a.worstDay!.value, _valueType),
          sub: a.worstDay!.date == null
              ? '—'
              : dateFmt.format(a.worstDay!.date!.toLocal()),
          tone: _red(context),
        ),
      if (_goal != null)
        _kpiTile(
          context,
          icon: LucideIcons.crosshair,
          label: 'META DIÁRIA',
          value: formatGoalValueCompact(_goal!.dailyTarget, _valueType),
          sub: 'necessário por dia',
          tone: _amber(context),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final t in tiles) SizedBox(width: width, child: t),
          ],
        );
      },
    );
  }

  Widget _kpiTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required String sub,
    required Color tone,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ThemeHelpers.borderColor(context)
              .withValues(alpha: isDark ? 0.6 : 1),
        ),
        boxShadow: ThemeHelpers.cardShadow(context, strength: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: tone),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: tone,
                    letterSpacing: 1.1,
                  ),
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
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: ThemeHelpers.textColor(context),
                letterSpacing: -0.4,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Insights ────────────────────────────────────────────────────────────

  Widget _buildInsights(BuildContext context, GoalAnalytics a) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = _blue(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.1 : 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.lightbulb, size: 15, color: tone),
              const SizedBox(width: 7),
              Text(
                'INSIGHTS',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < a.insights.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Container(
                  height: 1,
                  color: tone.withValues(alpha: 0.16),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration:
                        BoxDecoration(color: tone, shape: BoxShape.circle),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    a.insights[i],
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ─── Evolução ────────────────────────────────────────────────────────────

  Widget _buildEvolution(BuildContext context, GoalAnalytics a) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final tone = _goal == null
        ? _green(context)
        : goalIdentityColor(context, _goal!);

    // Últimos 30 dias com pelo menos um dia útil de dados.
    final points = a.history.length > 30
        ? a.history.sublist(a.history.length - 30)
        : a.history;
    final hasData = points.any((p) => p.value > 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.chartColumn, size: 14, color: secondary),
            const SizedBox(width: 6),
            Text(
              'EVOLUÇÃO',
              style: theme.textTheme.labelSmall?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Container(
                  height: 1,
                  color: ThemeHelpers.borderLightColor(context)
                      .withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Valor realizado por dia dentro do período da meta.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: secondary,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 14),
        if (points.isEmpty || !hasData)
          _buildEvolutionEmpty(context)
        else ...[
          SizedBox(
            height: 130,
            child: CustomPaint(
              size: Size.infinite,
              painter: _GoalBarsPainter(
                points: points,
                color: tone,
                gridColor: ThemeHelpers.borderLightColor(context)
                    .withValues(alpha: 0.7),
              ),
            ),
          ),
          const SizedBox(height: 6),
          _buildChartAxis(context, points),
          const SizedBox(height: 16),
          _buildHistoryList(context, a),
        ],
      ],
    );
  }

  Widget _buildChartAxis(
      BuildContext context, List<GoalHistoryPoint> points) {
    final fmt = DateFormat('dd/MM', 'pt_BR');
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final first = points.first.date;
    final last = points.last.date;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          first == null ? '' : fmt.format(first.toLocal()),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: secondary,
          ),
        ),
        Text(
          last == null ? '' : fmt.format(last.toLocal()),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: secondary,
          ),
        ),
      ],
    );
  }

  /// Últimos registros com valor — data, valor do dia e % acumulado.
  Widget _buildHistoryList(BuildContext context, GoalAnalytics a) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final fmt = DateFormat('dd MMM yyyy', 'pt_BR');
    final entries =
        a.history.where((p) => p.value != 0).toList().reversed.take(8).toList();
    if (entries.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'ÚLTIMAS MOVIMENTAÇÕES',
          style: theme.textTheme.labelSmall?.copyWith(
            color: secondary,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
            fontSize: 9.5,
          ),
        ),
        const SizedBox(height: 4),
        for (final p in entries)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              border: Border(
                bottom:
                    BorderSide(color: ThemeHelpers.borderLightColor(context)),
              ),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.calendarDays, size: 13, color: secondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    p.date == null ? 'Sem data' : fmt.format(p.date!.toLocal()),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  formatGoalValue(p.value, _valueType),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 52,
                  child: Text(
                    '${NumberFormat('#,##0.0', 'pt_BR').format(p.progress)}%',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _accent(context),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildEvolutionEmpty(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          children: [
            Icon(LucideIcons.chartColumn, size: 30, color: secondary),
            const SizedBox(height: 10),
            Text(
              'Nenhum histórico de evolução disponível',
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Estados ─────────────────────────────────────────────────────────────

  /// Skeleton fiel ao layout: hero + gauge + KPIs + gráfico.
  Widget _buildSkeleton(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Widget card(double height) => Container(
          height: height,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: ThemeHelpers.borderColor(context)
                  .withValues(alpha: isDark ? 0.6 : 1),
            ),
            boxShadow: ThemeHelpers.cardShadow(context),
          ),
          child: const Center(
            child: SkeletonBox(
                width: double.infinity, height: 60, borderRadius: 12),
          ),
        );
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(_kPagePadH, 12, _kPagePadH, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonText(width: 130, height: 12, borderRadius: 999),
          const SizedBox(height: 12),
          const SkeletonText(width: 220, height: 24),
          const SizedBox(height: 10),
          Row(
            children: const [
              SkeletonBox(width: 80, height: 22, borderRadius: 999),
              SizedBox(width: 8),
              SkeletonBox(width: 80, height: 22, borderRadius: 999),
              SizedBox(width: 8),
              SkeletonBox(width: 80, height: 22, borderRadius: 999),
            ],
          ),
          const SizedBox(height: 20),
          card(210),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: card(96)),
              const SizedBox(width: 12),
              Expanded(child: card(96)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: card(96)),
              const SizedBox(width: 12),
              Expanded(child: card(96)),
            ],
          ),
          const SizedBox(height: 20),
          const SkeletonBox(
              width: double.infinity, height: 130, borderRadius: 12),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final theme = Theme.of(context);
    final danger = _red(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
              _error ?? 'Erro ao carregar análise',
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
      ),
    );
  }
}

// ─── Painters ────────────────────────────────────────────────────────────────

/// Gauge semicircular de progresso — mesmo DNA do gauge de conversão do
/// dashboard: track sutil, arco com gradiente sweep e "led" na extremidade.
class _GoalGaugePainter extends CustomPainter {
  final double progress; // 0..1
  final Color color;
  final Color trackColor;
  final Color tickColor;

  _GoalGaugePainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.tickColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 11.0;
    final cx = size.width / 2;
    final cy = size.height - 6;
    final radius =
        math.min(size.width / 2, size.height) - strokeWidth / 2 - 2;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, trackPaint);

    if (progress > 0.001) {
      final progressPaint = Paint()
        ..shader = SweepGradient(
          startAngle: math.pi,
          endAngle: math.pi * 2,
          colors: [color.withValues(alpha: 0.55), color],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, math.pi, math.pi * progress, false, progressPaint);

      final endAngle = math.pi + math.pi * progress;
      final endX = cx + radius * math.cos(endAngle);
      final endY = cy + radius * math.sin(endAngle);
      canvas.drawCircle(Offset(endX, endY), strokeWidth * 0.95,
          Paint()..color = color.withValues(alpha: 0.18));
      canvas.drawCircle(
          Offset(endX, endY), strokeWidth * 0.32, Paint()..color = color);
    }

    final tickPaint = Paint()
      ..color = tickColor.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx - radius, cy), 1.6, tickPaint);
    canvas.drawCircle(Offset(cx + radius, cy), 1.6, tickPaint);
  }

  @override
  bool shouldRepaint(covariant _GoalGaugePainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.tickColor != tickColor;
}

/// Barras diárias da evolução — grid horizontal sutil + barras arredondadas
/// com gradiente da cor da meta (informativo e estilizado, sem espaço morto).
class _GoalBarsPainter extends CustomPainter {
  final List<GoalHistoryPoint> points;
  final Color color;
  final Color gridColor;

  _GoalBarsPainter({
    required this.points,
    required this.color,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final maxValue =
        points.map((p) => p.value).fold<double>(0, math.max);
    if (maxValue <= 0) return;

    // Grid horizontal (3 linhas).
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 1; i <= 3; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height),
        gridPaint..color = gridColor.withValues(alpha: 0.9));

    final n = points.length;
    final slot = size.width / n;
    final barWidth = math.max(2.0, math.min(slot * 0.62, 14.0));

    for (var i = 0; i < n; i++) {
      final p = points[i];
      final ratio = (p.value / maxValue).clamp(0.0, 1.0);
      final barHeight = math.max(ratio * (size.height - 6), 0.0);
      final cx = slot * i + slot / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          cx - barWidth / 2,
          size.height - barHeight,
          barWidth,
          barHeight,
        ),
        const Radius.circular(3),
      );
      if (barHeight <= 0.5) {
        // Dia sem movimento: tick discreto na base.
        canvas.drawCircle(
          Offset(cx, size.height - 1.5),
          1.2,
          Paint()..color = color.withValues(alpha: 0.22),
        );
        continue;
      }
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [color.withValues(alpha: 0.55), color],
        ).createShader(rect.outerRect);
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GoalBarsPainter old) =>
      old.points != points || old.color != color || old.gridColor != gridColor;
}
