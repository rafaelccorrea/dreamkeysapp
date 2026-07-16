import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/minimal_body_chrome.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/advanced_models.dart';
import '../services/analytics_service.dart';
import '../widgets/analytics_charts.dart';
import '../widgets/analytics_filter_sheets.dart';
import '../widgets/analytics_ui.dart';

final NumberFormat _money = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 2,
);
final NumberFormat _compactMoney = NumberFormat.compactCurrency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 1,
);
final NumberFormat _int = NumberFormat.decimalPattern('pt_BR');

String _pct(double v) => '${v.toStringAsFixed(1).replaceAll('.', ',')}%';

enum _AdvTab { company, brokers, funnel, churn }

/// Analytics Avançado — performance da empresa, corretores (IA), funil de
/// conversão e churn. Paridade com `AdvancedAnalyticsPage` do imobx-front
/// (permissão `performance:view_company`).
class AdvancedAnalyticsPage extends StatefulWidget {
  const AdvancedAnalyticsPage({super.key});

  @override
  State<AdvancedAnalyticsPage> createState() => _AdvancedAnalyticsPageState();
}

class _AdvancedAnalyticsPageState extends State<AdvancedAnalyticsPage> {
  static const double _kPadH = 16;
  static const double _kPadTop = 10;
  static const double _kPadBottom = 88;
  static const double _kGap = 12;

  _AdvTab _activeTab = _AdvTab.company;
  String _period = 'month';

  PerformanceDashboard? _performance;
  bool _performanceLoading = true;
  String? _performanceError;

  PendingMatchesSummary? _pending;
  bool _pendingLoading = true;

  List<BrokerPerformance>? _brokers;
  bool _brokersLoading = true;
  String? _brokersError;
  int _brokersToShow = 3;

  ConversionFunnelData? _funnel;
  bool _funnelLoading = true;
  String? _funnelError;

  ChurnAnalysis? _churn;
  bool _churnLoading = true;
  String? _churnError;
  int _churnToShow = 3;

  CapturesStats? _captures;
  bool _capturesLoading = true;

  bool get _canView => ModuleAccessService.instance
      .hasPermission('performance:view_company');

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  // ─── Dados ────────────────────────────────────────────────────────────────

  ({DateTime start, DateTime end}) get _dateRange {
    final end = DateTime.now();
    final start = switch (_period) {
      'week' => end.subtract(const Duration(days: 7)),
      'quarter' => DateTime(end.year, end.month - 3, end.day),
      'year' => DateTime(end.year - 1, end.month, end.day),
      _ => end.subtract(const Duration(days: 30)),
    };
    return (start: start, end: end);
  }

  Future<void> _loadAll() async {
    setState(() {
      _performanceLoading = true;
      _pendingLoading = true;
      _brokersLoading = true;
      _funnelLoading = true;
      _churnLoading = true;
      _capturesLoading = true;
      _performanceError = null;
      _brokersError = null;
      _funnelError = null;
      _churnError = null;
      _brokersToShow = 3;
      _churnToShow = 3;
    });
    await Future.wait([
      _loadPerformance(),
      _loadPending(),
      _loadBrokers(),
      _loadFunnel(),
      _loadChurn(),
      _loadCaptures(),
    ]);
  }

  Future<void> _loadPerformance() async {
    final range = _dateRange;
    final res = await AnalyticsService.instance.getPerformanceDashboard(
      startDate: range.start,
      endDate: range.end,
    );
    if (!mounted) return;
    setState(() {
      _performanceLoading = false;
      if (res.success && res.data != null) {
        _performance = res.data;
      } else if (_performance == null) {
        _performanceError = res.message;
      }
    });
  }

  Future<void> _loadPending() async {
    final res = await AnalyticsService.instance.getPendingMatches();
    if (!mounted) return;
    setState(() {
      _pendingLoading = false;
      if (res.success && res.data != null) _pending = res.data;
    });
  }

  Future<void> _loadBrokers() async {
    final range = _dateRange;
    final res = await AnalyticsService.instance.getBrokersPerformance(
      period: _period,
      startDate: range.start,
      endDate: range.end,
    );
    if (!mounted) return;
    setState(() {
      _brokersLoading = false;
      if (res.success && res.data != null) {
        _brokers = res.data;
      } else if (_brokers == null) {
        _brokersError = res.message;
      }
    });
  }

  Future<void> _loadFunnel() async {
    final range = _dateRange;
    final res = await AnalyticsService.instance.getConversionFunnel(
      startDate: range.start,
      endDate: range.end,
    );
    if (!mounted) return;
    setState(() {
      _funnelLoading = false;
      if (res.success && res.data != null) {
        _funnel = res.data;
      } else if (_funnel == null) {
        _funnelError = res.message;
      }
    });
  }

  Future<void> _loadChurn() async {
    final res = await AnalyticsService.instance.getChurnAnalysis();
    if (!mounted) return;
    setState(() {
      _churnLoading = false;
      if (res.success && res.data != null) {
        _churn = res.data;
      } else if (_churn == null) {
        _churnError = res.message;
      }
    });
  }

  Future<void> _loadCaptures() async {
    final range = _dateRange;
    final res = await AnalyticsService.instance.getCapturesStatistics(
      startDate: range.start,
      endDate: range.end,
    );
    if (!mounted) return;
    setState(() {
      _capturesLoading = false;
      if (res.success && res.data != null) _captures = res.data;
    });
  }

  void _openFilters() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (ctx) => AdvancedFiltersSheet(
        period: _period,
        onApply: (period) {
          if (period == _period) return;
          setState(() => _period = period);
          _loadAll();
        },
      ),
    );
  }

  String get _periodLabel => switch (_period) {
        'week' => 'última semana',
        'quarter' => 'último trimestre',
        'year' => 'último ano',
        _ => 'último mês',
      };

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canView) {
      return const AppScaffold(
        title: 'Análise Avançada',
        showBottomNavigation: false,
        body: AnalyticsDeniedView(
          message: 'Você não tem acesso à análise avançada.',
          permission: 'performance:view_company',
        ),
      );
    }
    return AppScaffold(
      title: 'Análise Avançada',
      showBottomNavigation: false,
      actions: [
        ChromeToolbarIconButton(
          icon: Icons.tune_rounded,
          tooltip: 'Filtros',
          onPressed: _openFilters,
        ),
      ],
      body: RefreshIndicator(
        color: AnalyticsTones.accent(context),
        onRefresh: _loadAll,
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
                        _kPadH, _kPadTop, _kPadH, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHero(context),
                        const SizedBox(height: _kGap),
                      ],
                    ),
                  ),
                  _buildTabsRail(context),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        _kPadH, _kGap, _kPadH, _kPadBottom),
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

  // ─── Hero ─────────────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context) {
    final stats = _performance?.companyStats ?? CompanyStats.empty;
    final green = AnalyticsTones.green(context);
    final amber = AnalyticsTones.amber(context);
    final blue = AnalyticsTones.blue(context);
    final purple = AnalyticsTones.purple(context);
    final loading = _performanceLoading && _performance == null;

    final subtitle = loading
        ? 'Carregando performance da empresa…'
        : stats.totalMatches == 0
            ? 'Sem matches no período ($_periodLabel).'
            : '${_int.format(stats.acceptedMatches)} aceitos · '
                '${_pct(stats.avgAcceptanceRate)} de aceitação · $_periodLabel';

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HeroEyebrow(
            label: 'ANÁLISE AVANÇADA',
            dotColor: stats.totalMatches > 0 ? green : amber,
          ),
          const SizedBox(height: 10),
          HeroHeadline(
            value: loading ? '—' : _int.format(stats.totalMatches),
            suffix: stats.totalMatches == 1 ? 'match' : 'matches',
            subtitle: subtitle,
          ),
          const SizedBox(height: 18),
          HeroKpiStrip(
            loading: loading,
            blocks: [
              HeroKpiData(
                icon: LucideIcons.circleCheckBig,
                label: 'ACEITOS',
                value: _int.format(stats.acceptedMatches),
                sub: 'no período',
                tone: green,
              ),
              HeroKpiData(
                icon: LucideIcons.gauge,
                label: 'SCORE MÉDIO',
                value: stats.avgMatchScore.toStringAsFixed(1),
                sub: 'dos matches',
                tone: purple,
              ),
              HeroKpiData(
                icon: LucideIcons.listChecks,
                label: 'TAREFAS',
                value:
                    '${_int.format(stats.totalTasksCompleted)}/${_int.format(stats.totalTasksCreated)}',
                sub: 'concluídas/criadas',
                tone: blue,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Abas ─────────────────────────────────────────────────────────────────

  Color _tabTone(BuildContext context, _AdvTab tab) {
    switch (tab) {
      case _AdvTab.company:
        return AnalyticsTones.accent(context);
      case _AdvTab.brokers:
        return AnalyticsTones.purple(context);
      case _AdvTab.funnel:
        return AnalyticsTones.blue(context);
      case _AdvTab.churn:
        return AnalyticsTones.amber(context);
    }
  }

  Widget _buildTabsRail(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: _kPadH - 8),
      child: Row(
        children: [
          for (final tab in _AdvTab.values)
            Expanded(
              child: AnalyticsFlushTab(
                icon: switch (tab) {
                  _AdvTab.company => LucideIcons.building2,
                  _AdvTab.brokers => LucideIcons.usersRound,
                  _AdvTab.funnel => LucideIcons.funnel,
                  _AdvTab.churn => LucideIcons.userX,
                },
                label: switch (tab) {
                  _AdvTab.company => 'Empresa',
                  _AdvTab.brokers => 'Corretores',
                  _AdvTab.funnel => 'Funil',
                  _AdvTab.churn => 'Churn',
                },
                count: switch (tab) {
                  _AdvTab.churn => _churn?.highRisk,
                  _AdvTab.brokers => _brokers?.length,
                  _ => null,
                },
                tone: _tabTone(context, tab),
                selected: _activeTab == tab,
                onTap: () => setState(() => _activeTab = tab),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActivePanel(BuildContext context) {
    final child = switch (_activeTab) {
      _AdvTab.company => _buildCompanyPanel(context),
      _AdvTab.brokers => _buildBrokersPanel(context),
      _AdvTab.funnel => _buildFunnelPanel(context),
      _AdvTab.churn => _buildChurnPanel(context),
    };
    return child
        .animate(key: ValueKey('adv-${_activeTab.name}'))
        .fadeIn(duration: 240.ms);
  }

  Widget _sectionSkeleton() {
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 10) / 2;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonText(width: 180, height: 14),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: List.generate(
                4,
                (_) => SkeletonBox(width: w, height: 92, borderRadius: 16),
              ),
            ),
          ],
        );
      },
    );
  }

  // ─── Painel: empresa ─────────────────────────────────────────────────────

  Widget _buildCompanyPanel(BuildContext context) {
    final tone = _tabTone(context, _AdvTab.company);
    final green = AnalyticsTones.green(context);
    final amber = AnalyticsTones.amber(context);
    final blue = AnalyticsTones.blue(context);
    final purple = AnalyticsTones.purple(context);
    final red = AnalyticsTones.red(context);

    if (_performanceLoading && _performance == null) return _sectionSkeleton();
    if (_performanceError != null && _performance == null) {
      return AnalyticsErrorState(
        message: _performanceError!,
        onRetry: _loadAll,
      );
    }

    final stats = _performance?.companyStats ?? CompanyStats.empty;
    final pending = _pending;
    final captures = _captures;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnalyticsPanelHeader(
          icon: LucideIcons.building2,
          eyebrow: 'EMPRESA',
          title: 'Performance geral',
          hint:
              'Matches, tarefas e captações da empresa no $_periodLabel.',
          tone: tone,
        ),
        const SizedBox(height: 14),
        MetricGrid(cards: [
          MetricCard(
            icon: LucideIcons.gitCompareArrows,
            label: 'Total de matches',
            value: _int.format(stats.totalMatches),
            tone: blue,
          ),
          MetricCard(
            icon: LucideIcons.circleCheckBig,
            label: 'Matches aceitos',
            value: _int.format(stats.acceptedMatches),
            sub: _pct(stats.avgAcceptanceRate),
            tone: green,
          ),
          MetricCard(
            icon: LucideIcons.gauge,
            label: 'Score médio',
            value: stats.avgMatchScore.toStringAsFixed(1),
            tone: purple,
          ),
          MetricCard(
            icon: LucideIcons.listChecks,
            label: 'Tarefas concluídas',
            value: _int.format(stats.totalTasksCompleted),
            sub: '${_int.format(stats.totalTasksCreated)} criadas · ${_pct(stats.taskCompletionRate)}',
            tone: amber,
          ),
        ]),
        const SizedBox(height: 18),
        const AnalyticsSubsectionHeader(
          label: 'Visão geral de métricas',
          icon: LucideIcons.chartColumn,
        ),
        const SizedBox(height: 12),
        HBarChart(
          tone: tone,
          items: [
            BarItem(
              label: 'Total de matches',
              value: stats.totalMatches.toDouble(),
              color: blue,
            ),
            BarItem(
              label: 'Matches aceitos',
              value: stats.acceptedMatches.toDouble(),
              color: green,
            ),
            BarItem(
              label: 'Tarefas criadas',
              value: stats.totalTasksCreated.toDouble(),
              color: amber,
            ),
            BarItem(
              label: 'Tarefas concluídas',
              value: stats.totalTasksCompleted.toDouble(),
              color: purple,
            ),
          ],
        ),
        const SizedBox(height: 18),
        AnalyticsSubsectionHeader(
          label: 'Matches pendentes',
          icon: LucideIcons.hourglass,
          count: pending?.total,
        ),
        const SizedBox(height: 12),
        if (_pendingLoading && pending == null)
          Row(
            children: [
              Expanded(
                  child: SkeletonBox(
                      width: double.infinity, height: 64, borderRadius: 14)),
              const SizedBox(width: 10),
              Expanded(
                  child: SkeletonBox(
                      width: double.infinity, height: 64, borderRadius: 14)),
            ],
          )
        else if (pending == null || pending.total == 0)
          Text(
            'Nenhum match aguardando resposta. Tudo em dia.',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: _pendingStat(context, 'PENDENTES',
                    _int.format(pending.total), blue, LucideIcons.hourglass),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _pendingStat(
                    context,
                    'ATENÇÃO (>3D)',
                    _int.format(pending.warning),
                    amber,
                    LucideIcons.triangleAlert),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _pendingStat(context, 'ATRASO (>7D)',
                    _int.format(pending.overdue), red, LucideIcons.siren),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final m in _sortedPending(pending).take(5))
            _pendingMatchRow(context, m),
        ],
        if (_capturesLoading || (captures?.hasData ?? false)) ...[
          const SizedBox(height: 18),
          const AnalyticsSubsectionHeader(
            label: 'Captações',
            icon: LucideIcons.userPlus,
          ),
          const SizedBox(height: 12),
          if (_capturesLoading && captures == null)
            SkeletonBox(width: double.infinity, height: 90, borderRadius: 16)
          else if (captures != null) ...[
            MetricGrid(cards: [
              MetricCard(
                icon: LucideIcons.house,
                label: 'Imóveis captados',
                value: _int.format(captures.totalProperties),
                sub: '${_pct(captures.propertiesSoldRate)} vendidos',
                tone: tone,
              ),
              MetricCard(
                icon: LucideIcons.users,
                label: 'Clientes captados',
                value: _int.format(captures.totalClients),
                sub: '${_pct(captures.clientsClosedRate)} fechados',
                tone: green,
              ),
            ]),
            if (captures.byCapturer.isNotEmpty) ...[
              const SizedBox(height: 12),
              HBarChart(
                tone: tone,
                items: [
                  for (final c in captures.byCapturer.take(5))
                    BarItem(
                      label: c.capturerName,
                      value: c.totalCaptures.toDouble(),
                      valueLabel: _int.format(c.totalCaptures),
                      sub:
                          '${c.propertiesCount} imóveis · ${c.clientsCount} clientes',
                    ),
                ],
              ),
            ],
          ],
        ],
      ],
    );
  }

  List<PendingMatch> _sortedPending(PendingMatchesSummary pending) {
    final list = [...pending.items]
      ..sort((a, b) => b.daysPending.compareTo(a.daysPending));
    return list;
  }

  Widget _pendingStat(BuildContext context, String label, String value,
      Color tone, IconData icon) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(14),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 11, color: tone),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    color: tone,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: tone,
              height: 1.0,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pendingMatchRow(BuildContext context, PendingMatch m) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final days = m.daysPending;
    final tone = days > 7
        ? AnalyticsTones.red(context)
        : days > 3
            ? AnalyticsTones.amber(context)
            : AnalyticsTones.blue(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.gitCompareArrows, size: 15, color: tone),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.clientName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  m.propertyTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: secondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MiniPill(
                label: 'score ${m.matchScore.toStringAsFixed(0)}',
                tone: AnalyticsTones.byScore(context, m.matchScore),
              ),
              const SizedBox(height: 4),
              Text(
                days == 0 ? 'hoje' : '$days dia${days == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: tone,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Painel: corretores ──────────────────────────────────────────────────

  Widget _buildBrokersPanel(BuildContext context) {
    final tone = _tabTone(context, _AdvTab.brokers);
    final green = AnalyticsTones.green(context);
    final amber = AnalyticsTones.amber(context);
    final red = AnalyticsTones.red(context);

    if (_brokersLoading && _brokers == null) return _sectionSkeleton();
    if (_brokersError != null && (_brokers?.isEmpty ?? true)) {
      return AnalyticsErrorState(message: _brokersError!, onRetry: _loadAll);
    }
    final brokers = _brokers ?? const <BrokerPerformance>[];
    if (brokers.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnalyticsPanelHeader(
            icon: LucideIcons.usersRound,
            eyebrow: 'CORRETORES',
            title: 'Ranking de performance',
            hint: 'Score, vendas, conversão e tendência por corretor.',
            tone: tone,
          ),
          AnalyticsEmptyState(
            icon: LucideIcons.usersRound,
            title: 'Nenhum corretor analisado',
            body:
                'Não há dados de performance de corretores para o período selecionado.',
            tone: tone,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnalyticsPanelHeader(
          icon: LucideIcons.usersRound,
          eyebrow: 'CORRETORES',
          title: 'Ranking de performance',
          hint:
              'Análise da IA — score geral, vendas, conversão e tendência.',
          tone: tone,
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < brokers.length && i < _brokersToShow; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _brokerCard(context, brokers[i], i, tone, green, amber, red)
              .animate(key: ValueKey('bk-${brokers[i].brokerId}'))
              .fadeIn(
                delay: Duration(milliseconds: 30 * i.clamp(0, 10)),
                duration: 220.ms,
              ),
        ],
        if (brokers.length > _brokersToShow)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Center(
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _brokersToShow =
                    (_brokersToShow + 5).clamp(0, brokers.length)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: tone,
                  side: BorderSide(color: tone.withValues(alpha: 0.45)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(LucideIcons.chevronDown, size: 16),
                label: Text(
                    'Ver mais (${brokers.length - _brokersToShow} restantes)'),
              ),
            ),
          ),
        if (brokers.length > 1) ...[
          const SizedBox(height: 18),
          const AnalyticsSubsectionHeader(
            label: 'Top 5 · vendas',
            icon: LucideIcons.chartColumn,
          ),
          const SizedBox(height: 12),
          HBarChart(
            tone: tone,
            items: [
              for (final b in brokers.take(5))
                BarItem(
                  label: b.brokerName,
                  value: b.salesCount.toDouble(),
                  valueLabel: _int.format(b.salesCount),
                  sub: _compactMoney.format(b.totalSalesValue),
                ),
            ],
          ),
          const SizedBox(height: 18),
          const AnalyticsSubsectionHeader(
            label: 'Top 5 · taxa de conversão',
            icon: LucideIcons.trendingUp,
          ),
          const SizedBox(height: 12),
          HBarChart(
            tone: green,
            items: [
              for (final b in brokers.take(5))
                BarItem(
                  label: b.brokerName,
                  value: b.conversionRate,
                  valueLabel: _pct(b.conversionRate),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _brokerCard(BuildContext context, BrokerPerformance b, int index,
      Color tone, Color green, Color amber, Color red) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final scoreTone = AnalyticsTones.byScore(context, b.overallScore);
    final medal = switch (index) {
      0 => amber,
      1 => secondary,
      2 => const Color(0xFF92400E),
      _ => tone,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: medal.withValues(alpha: isDark ? 0.2 : 0.12),
                ),
                alignment: Alignment.center,
                child: index < 3
                    ? Icon(LucideIcons.medal, size: 18, color: medal)
                    : Text(
                        '${index + 1}º',
                        style: TextStyle(
                          color: medal,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.brokerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${index + 1}º lugar · ${b.leadsGenerated} leads · ${b.visitsCompleted} visitas',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    b.overallScore.toStringAsFixed(1),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: scoreTone,
                      height: 1.0,
                      letterSpacing: -0.4,
                    ),
                  ),
                  Text(
                    'score',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: secondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              MiniPill(
                icon: LucideIcons.handshake,
                label:
                    '${b.salesCount} venda${b.salesCount == 1 ? '' : 's'}',
                tone: tone,
              ),
              MiniPill(
                icon: LucideIcons.banknote,
                label: _compactMoney.format(b.totalSalesValue),
                tone: green,
              ),
              MiniPill(
                icon: LucideIcons.trendingUp,
                label: _pct(b.conversionRate),
                tone: AnalyticsTones.blue(context),
              ),
              if (b.averageSaleTime > 0)
                MiniPill(
                  icon: LucideIcons.timer,
                  label: '${b.averageSaleTime.toStringAsFixed(0)} dias',
                  tone: amber,
                ),
              MiniPill(
                icon: b.trend == 'improving'
                    ? LucideIcons.trendingUp
                    : b.trend == 'declining'
                        ? LucideIcons.trendingDown
                        : LucideIcons.arrowLeftRight,
                label: b.trendLabel,
                tone: b.trend == 'improving'
                    ? green
                    : b.trend == 'declining'
                        ? red
                        : AnalyticsTones.blue(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Painel: funil ───────────────────────────────────────────────────────

  Widget _buildFunnelPanel(BuildContext context) {
    final tone = _tabTone(context, _AdvTab.funnel);
    final green = AnalyticsTones.green(context);
    final amber = AnalyticsTones.amber(context);

    if (_funnelLoading && _funnel == null) return _sectionSkeleton();
    if (_funnelError != null && _funnel == null) {
      return AnalyticsErrorState(message: _funnelError!, onRetry: _loadAll);
    }
    final funnel = _funnel;
    if (funnel == null || funnel.stages.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnalyticsPanelHeader(
            icon: LucideIcons.funnel,
            eyebrow: 'FUNIL',
            title: 'Conversão de leads',
            hint: 'Do lead à venda, etapa por etapa.',
            tone: tone,
          ),
          AnalyticsEmptyState(
            icon: LucideIcons.funnel,
            title: 'Nenhum dado do funil',
            body:
                'Não há dados de conversão para o período. Ajuste os filtros ou aguarde novos leads.',
            tone: tone,
          ),
        ],
      );
    }

    final analysis = funnel.analysis;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnalyticsPanelHeader(
          icon: LucideIcons.funnel,
          eyebrow: 'FUNIL',
          title: 'Conversão de leads',
          hint: funnel.period.isNotEmpty
              ? 'Período: ${funnel.period}.'
              : 'Do lead à venda, etapa por etapa.',
          tone: tone,
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: MetricCard(
                icon: LucideIcons.users,
                label: 'Total de leads',
                value: _int.format(funnel.totalLeads),
                tone: tone,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MetricCard(
                icon: LucideIcons.trendingUp,
                label: 'Conversão geral',
                value: _pct(funnel.overallConversionRate),
                tone: green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (analysis != null)
          Center(
            child: ScoreGauge(
              score: analysis.overallScore.clamp(0, 100).toDouble(),
              tone: AnalyticsTones.byScore(context, analysis.overallScore),
              label: 'Score do funil',
            ),
          ),
        const SizedBox(height: 16),
        const AnalyticsSubsectionHeader(
          label: 'Etapas do funil',
          icon: LucideIcons.funnel,
        ),
        const SizedBox(height: 12),
        FunnelChart(
          tone: tone,
          stages: [
            for (final s in funnel.stages)
              FunnelStageBar(
                name: s.name,
                count: s.count,
                conversionFromPrevious: s.conversionRate,
                conversionFromTotal: s.conversionRateFromTotal,
              ),
          ],
        ),
        if (analysis != null) ...[
          if (analysis.summary.isNotEmpty) ...[
            const SizedBox(height: 18),
            const AnalyticsSubsectionHeader(
              label: 'Análise do funil',
              icon: LucideIcons.sparkles,
            ),
            const SizedBox(height: 10),
            Text(
              analysis.summary,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: ThemeHelpers.textColor(context),
              ),
            ),
          ],
          if (analysis.strengths.isNotEmpty) ...[
            const SizedBox(height: 14),
            _bulletList(context, 'Pontos fortes', LucideIcons.circleCheckBig,
                green, analysis.strengths),
          ],
          if (analysis.bottlenecks.isNotEmpty) ...[
            const SizedBox(height: 14),
            _bulletList(context, 'Gargalos', LucideIcons.triangleAlert, amber,
                analysis.bottlenecks),
          ],
          if (analysis.opportunities.isNotEmpty) ...[
            const SizedBox(height: 14),
            _bulletList(context, 'Oportunidades', LucideIcons.lightbulb,
                AnalyticsTones.blue(context), analysis.opportunities),
          ],
          if (analysis.insights.isNotEmpty) ...[
            const SizedBox(height: 18),
            const AnalyticsSubsectionHeader(
              label: 'Insights detalhados',
              icon: LucideIcons.lightbulb,
            ),
            const SizedBox(height: 10),
            for (final insight in analysis.insights) ...[
              _insightCard(context, insight),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ],
    );
  }

  Widget _bulletList(BuildContext context, String title, IconData icon,
      Color tone, List<String> items) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: tone),
            const SizedBox(width: 6),
            Text(
              title,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: tone,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration:
                        BoxDecoration(color: tone, shape: BoxShape.circle),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _insightCard(BuildContext context, FunnelInsight insight) {
    final theme = Theme.of(context);
    final tone = switch (insight.type) {
      'success' => AnalyticsTones.green(context),
      'warning' => AnalyticsTones.amber(context),
      'error' => AnalyticsTones.red(context),
      _ => AnalyticsTones.blue(context),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: tone,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: tone.withValues(alpha: 0.5), blurRadius: 6),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  insight.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ),
            ],
          ),
          if (insight.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              insight.description,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
          ],
          if (insight.recommendations.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final rec in insight.recommendations)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(LucideIcons.arrowRight, size: 12, color: tone),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        rec,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ─── Painel: churn ───────────────────────────────────────────────────────

  Widget _buildChurnPanel(BuildContext context) {
    final tone = _tabTone(context, _AdvTab.churn);
    final green = AnalyticsTones.green(context);
    final red = AnalyticsTones.red(context);
    final blue = AnalyticsTones.blue(context);

    if (_churnLoading && _churn == null) return _sectionSkeleton();
    if (_churnError != null && !(_churn?.hasData ?? false)) {
      return AnalyticsErrorState(message: _churnError!, onRetry: _loadAll);
    }
    final churn = _churn ?? ChurnAnalysis.empty;
    if (!churn.hasData) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnalyticsPanelHeader(
            icon: LucideIcons.userX,
            eyebrow: 'CHURN',
            title: 'Risco de perda de clientes',
            hint: 'Análise preditiva de churn com ações de recuperação.',
            tone: tone,
          ),
          AnalyticsEmptyState(
            icon: LucideIcons.userCheck,
            title: 'Nenhum cliente em risco',
            body:
                'A análise não identificou clientes em risco de churn no momento.',
            tone: green,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnalyticsPanelHeader(
          icon: LucideIcons.userX,
          eyebrow: 'CHURN',
          title: 'Risco de perda de clientes',
          hint:
              '${_int.format(churn.totalClients)} clientes analisados pela IA · taxa estimada ${_pct(churn.churnRate)}.',
          tone: tone,
        ),
        const SizedBox(height: 14),
        MetricGrid(cards: [
          MetricCard(
            icon: LucideIcons.users,
            label: 'Analisados',
            value: _int.format(churn.totalClients),
            tone: blue,
          ),
          MetricCard(
            icon: LucideIcons.siren,
            label: 'Risco alto',
            value: _int.format(churn.highRisk),
            tone: red,
          ),
          MetricCard(
            icon: LucideIcons.triangleAlert,
            label: 'Risco médio',
            value: _int.format(churn.mediumRisk),
            tone: tone,
          ),
          MetricCard(
            icon: LucideIcons.circleCheckBig,
            label: 'Risco baixo',
            value: _int.format(churn.lowRisk),
            tone: green,
          ),
        ]),
        const SizedBox(height: 18),
        AnalyticsSubsectionHeader(
          label: 'Clientes em risco',
          icon: LucideIcons.userX,
          count: churn.atRiskClients.length,
        ),
        const SizedBox(height: 10),
        for (var i = 0;
            i < churn.atRiskClients.length && i < _churnToShow;
            i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _churnCard(context, churn.atRiskClients[i])
              .animate(key: ValueKey('churn-${churn.atRiskClients[i].clientId}'))
              .fadeIn(
                delay: Duration(milliseconds: 30 * i.clamp(0, 10)),
                duration: 220.ms,
              ),
        ],
        if (churn.atRiskClients.length > _churnToShow)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Center(
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _churnToShow =
                    (_churnToShow + 5).clamp(0, churn.atRiskClients.length)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: tone,
                  side: BorderSide(color: tone.withValues(alpha: 0.45)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(LucideIcons.chevronDown, size: 16),
                label: Text(
                    'Ver mais (${churn.atRiskClients.length - _churnToShow} restantes)'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _churnCard(BuildContext context, ChurnPrediction c) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final tone = AnalyticsTones.byRisk(context, c.riskLevel);
    final green = AnalyticsTones.green(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: tone.withValues(alpha: isDark ? 0.2 : 0.12),
                ),
                child: Icon(LucideIcons.userX, size: 17, color: tone),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.clientName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Sem contato há ${c.daysSinceLastContact} dia${c.daysSinceLastContact == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    c.churnRiskScore.toStringAsFixed(0),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: tone,
                      height: 1.0,
                      letterSpacing: -0.4,
                    ),
                  ),
                  Text(
                    'risco ${c.riskLabel.toLowerCase()}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: tone,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              MiniPill(
                icon: LucideIcons.heartPulse,
                label:
                    '${c.recoveryProbability.toStringAsFixed(0)}% recuperável',
                tone: green,
              ),
              for (final factor in c.riskFactors.take(3))
                MiniPill(label: factor, tone: secondary),
            ],
          ),
          if (c.recommendedActions.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final action in c.recommendedActions.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(LucideIcons.arrowRight,
                        size: 12, color: AnalyticsTones.blue(context)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        action,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: secondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
