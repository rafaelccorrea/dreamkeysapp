import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/minimal_body_chrome.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/property_analytics_models.dart';
import '../services/analytics_service.dart';
import '../widgets/analytics_charts.dart';
import '../widgets/analytics_filter_sheets.dart';
import '../widgets/analytics_ui.dart';

final NumberFormat _compactMoney = NumberFormat.compactCurrency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 1,
);
final NumberFormat _int = NumberFormat.decimalPattern('pt_BR');

enum _PropTab { overview, regions, engagement }

/// Analytics de Imóveis — KPIs do portfólio, evolução de preços, ranking por
/// região e engajamento do site. Paridade com `PropertyAnalyticsPage` do
/// imobx-front (permissão `performance:view_company`).
class PropertyAnalyticsPage extends StatefulWidget {
  const PropertyAnalyticsPage({super.key});

  @override
  State<PropertyAnalyticsPage> createState() => _PropertyAnalyticsPageState();
}

class _PropertyAnalyticsPageState extends State<PropertyAnalyticsPage> {
  static const double _kPadH = 16;
  static const double _kPadTop = 10;
  static const double _kPadBottom = 88;
  static const double _kGap = 12;

  static const List<int> _daysOptions = [1, 3, 7, 14, 30];
  static const List<(String, String)> _sortOptions = [
    ('total', 'Total'),
    ('views', 'Views'),
    ('whatsappClicks', 'WhatsApp'),
    ('favorites', 'Favoritos'),
  ];

  _PropTab _activeTab = _PropTab.overview;

  PropertyAnalyticsFilters _filters = const PropertyAnalyticsFilters();
  PropertyAnalyticsData? _data;
  bool _loading = true;
  String? _error;

  List<PropertyEngagement>? _engagement;
  bool _engagementLoading = true;
  int _engagementDays = 3;
  String _engagementSortBy = 'total';

  bool get _canView => ModuleAccessService.instance
      .hasPermission('performance:view_company');

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadEngagement();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await AnalyticsService.instance
        .getPropertyAnalytics(filters: _filters);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _data = res.data;
      } else if (_data == null) {
        _error = res.message ?? 'Erro ao carregar analytics de imóveis';
      }
    });
  }

  Future<void> _loadEngagement() async {
    setState(() => _engagementLoading = true);
    final res = await AnalyticsService.instance.getPropertyEngagement(
      days: _engagementDays,
      sortBy: _engagementSortBy,
    );
    if (!mounted) return;
    setState(() {
      _engagementLoading = false;
      if (res.success && res.data != null) _engagement = res.data;
    });
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadData(), _loadEngagement()]);
  }

  void _openFilters() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (ctx) => PropertyAnalyticsFiltersSheet(
        filters: _filters,
        onApply: (filters) {
          setState(() => _filters = filters);
          _loadData();
        },
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canView) {
      return const AppScaffold(
        title: 'Analytics de Imóveis',
        showBottomNavigation: false,
        body: AnalyticsDeniedView(
          message: 'Você não tem acesso ao analytics de imóveis.',
          permission: 'performance:view_company',
        ),
      );
    }
    return AppScaffold(
      title: 'Analytics de Imóveis',
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
        onRefresh: _refreshAll,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: _loading && _data == null
                  ? _buildSkeleton(context)
                  : _error != null && _data == null
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(
                              _kPadH, 48, _kPadH, _kPadBottom),
                          child: AnalyticsErrorState(
                            message: _error!,
                            onRetry: _refreshAll,
                          ),
                        )
                      : _buildContent(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(_kPadH, _kPadTop, _kPadH, 0),
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
          padding:
              const EdgeInsets.fromLTRB(_kPadH, _kGap, _kPadH, _kPadBottom),
          child: _buildActivePanel(context),
        ),
      ],
    );
  }

  // ─── Hero ─────────────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context) {
    final summary = _data?.summary ?? PropertySummaryStats.empty;
    final green = AnalyticsTones.green(context);
    final amber = AnalyticsTones.amber(context);
    final purple = AnalyticsTones.purple(context);
    final filterCount = _filters.activeCount;

    final subtitle = summary.totalProperties == 0
        ? 'Nenhum imóvel encontrado com os filtros atuais.'
        : '${summary.totalCities} cidade${summary.totalCities == 1 ? '' : 's'} · '
            '${summary.totalNeighborhoods} bairro${summary.totalNeighborhoods == 1 ? '' : 's'}'
            '${filterCount > 0 ? ' · $filterCount filtro${filterCount == 1 ? '' : 's'} ativo${filterCount == 1 ? '' : 's'}' : ''}';

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HeroEyebrow(
            label: 'ANALYTICS DE IMÓVEIS',
            dotColor: summary.totalProperties > 0 ? green : amber,
          ),
          const SizedBox(height: 10),
          HeroHeadline(
            value: _int.format(summary.totalProperties),
            suffix: summary.totalProperties == 1 ? 'imóvel' : 'imóveis',
            subtitle: subtitle,
          ),
          const SizedBox(height: 18),
          HeroKpiStrip(
            loading: _loading && _data == null,
            blocks: [
              HeroKpiData(
                icon: LucideIcons.circleCheckBig,
                label: 'DISPONÍVEIS',
                value: _int.format(summary.totalAvailable),
                sub:
                    '${summary.pctOfTotal(summary.totalAvailable).toStringAsFixed(0)}% do total',
                tone: green,
              ),
              HeroKpiData(
                icon: LucideIcons.handshake,
                label: 'VENDIDOS',
                value: _int.format(summary.totalSold),
                sub:
                    '${summary.pctOfTotal(summary.totalSold).toStringAsFixed(0)}% do total',
                tone: purple,
              ),
              HeroKpiData(
                icon: LucideIcons.keyRound,
                label: 'ALUGADOS',
                value: _int.format(summary.totalRented),
                sub:
                    '${summary.pctOfTotal(summary.totalRented).toStringAsFixed(0)}% do total',
                tone: amber,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Abas ─────────────────────────────────────────────────────────────────

  Color _tabTone(BuildContext context, _PropTab tab) {
    switch (tab) {
      case _PropTab.overview:
        return AnalyticsTones.accent(context);
      case _PropTab.regions:
        return AnalyticsTones.blue(context);
      case _PropTab.engagement:
        return AnalyticsTones.green(context);
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
          for (final tab in _PropTab.values)
            Expanded(
              child: AnalyticsFlushTab(
                icon: switch (tab) {
                  _PropTab.overview => LucideIcons.chartLine,
                  _PropTab.regions => LucideIcons.mapPin,
                  _PropTab.engagement => LucideIcons.messageCircle,
                },
                label: switch (tab) {
                  _PropTab.overview => 'Visão geral',
                  _PropTab.regions => 'Regiões',
                  _PropTab.engagement => 'Engajamento',
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
      _PropTab.overview => _buildOverviewPanel(context),
      _PropTab.regions => _buildRegionsPanel(context),
      _PropTab.engagement => _buildEngagementPanel(context),
    };
    return child
        .animate(key: ValueKey('prop-${_activeTab.name}'))
        .fadeIn(duration: 240.ms);
  }

  // ─── Painel: visão geral ─────────────────────────────────────────────────

  Widget _buildOverviewPanel(BuildContext context) {
    final data = _data;
    final tone = _tabTone(context, _PropTab.overview);
    final green = AnalyticsTones.green(context);
    final amber = AnalyticsTones.amber(context);
    final blue = AnalyticsTones.blue(context);
    final purple = AnalyticsTones.purple(context);

    if (data == null || data.summary.totalProperties == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnalyticsPanelHeader(
            icon: LucideIcons.chartLine,
            eyebrow: 'VISÃO GERAL',
            title: 'Preços e portfólio',
            hint: 'Tickets médios, evolução de preços e valores por tipo.',
            tone: tone,
          ),
          AnalyticsEmptyState(
            icon: LucideIcons.house,
            title: 'Nenhum imóvel encontrado',
            body:
                'Ajuste os filtros ou cadastre imóveis para ver o analytics do portfólio.',
            tone: tone,
          ),
        ],
      );
    }

    final s = data.summary;
    final evolution = data.priceEvolution;
    final byType = [...data.avgValuesByType]
      ..sort((a, b) => b.totalProperties.compareTo(a.totalProperties));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnalyticsPanelHeader(
          icon: LucideIcons.chartLine,
          eyebrow: 'VISÃO GERAL',
          title: 'Preços e portfólio',
          hint: 'Tickets médios, evolução de preços e valores por tipo.',
          tone: tone,
        ),
        const SizedBox(height: 14),
        MetricGrid(cards: [
          MetricCard(
            icon: LucideIcons.banknote,
            label: 'Ticket médio venda',
            value: _compactMoney.format(s.avgSalePrice),
            sub: 'R\$ ${s.avgPricePerSqm.toStringAsFixed(0)}/m²',
            tone: blue,
          ),
          MetricCard(
            icon: LucideIcons.keyRound,
            label: 'Ticket médio aluguel',
            value: _compactMoney.format(s.avgRentPrice),
            sub: 'área média ${s.avgTotalArea.toStringAsFixed(0)} m²',
            tone: amber,
          ),
        ]),
        if (evolution.length >= 2) ...[
          const SizedBox(height: 18),
          const AnalyticsSubsectionHeader(
            label: 'Evolução de preços',
            icon: LucideIcons.chartLine,
          ),
          const SizedBox(height: 12),
          LineChart(
            startLabel: evolution.first.monthLabel,
            endLabel: evolution.last.monthLabel,
            series: [
              LineSeries(
                label: 'Venda',
                color: blue,
                values: [for (final p in evolution) p.avgSalePrice],
              ),
              LineSeries(
                label: 'Aluguel',
                color: amber,
                values: [for (final p in evolution) p.avgRentPrice],
              ),
            ],
          ),
          const SizedBox(height: 16),
          const AnalyticsSubsectionHeader(
            label: 'Vendas e locações por mês',
            icon: LucideIcons.chartColumn,
          ),
          const SizedBox(height: 12),
          MiniBarsChart(
            tone: purple,
            values: [
              for (final p in evolution)
                (p.totalSold + p.totalRented).toDouble(),
            ],
            startLabel: evolution.first.monthLabel,
            endLabel: evolution.last.monthLabel,
          ),
        ],
        if (byType.isNotEmpty) ...[
          const SizedBox(height: 18),
          AnalyticsSubsectionHeader(
            label: 'Valores por tipo',
            icon: LucideIcons.house,
            count: byType.length,
          ),
          const SizedBox(height: 6),
          for (final t in byType.take(8)) _typeRow(context, t, green),
        ],
      ],
    );
  }

  Widget _typeRow(BuildContext context, AvgValuesByType t, Color green) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.house,
              size: 15, color: AnalyticsTones.accent(context)),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.typeLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_int.format(t.totalProperties)} imóve${t.totalProperties == 1 ? 'l' : 'is'} · '
                  'R\$ ${t.avgPricePerSqm.toStringAsFixed(0)}/m²',
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
                _compactMoney.format(t.avgSalePrice),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              if (t.avgRentPrice > 0)
                Text(
                  '${_compactMoney.format(t.avgRentPrice)} aluguel',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: green,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Painel: regiões ─────────────────────────────────────────────────────

  Widget _buildRegionsPanel(BuildContext context) {
    final data = _data;
    final tone = _tabTone(context, _PropTab.regions);
    final green = AnalyticsTones.green(context);
    final amber = AnalyticsTones.amber(context);

    final ranking = data?.regionRanking ?? const <RegionRanking>[];
    if (ranking.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnalyticsPanelHeader(
            icon: LucideIcons.mapPin,
            eyebrow: 'REGIÕES',
            title: 'Ranking por bairro',
            hint: 'Onde o portfólio mais vende e aluga.',
            tone: tone,
          ),
          AnalyticsEmptyState(
            icon: LucideIcons.mapPin,
            title: 'Sem dados por região',
            body:
                'Nenhum bairro com vendas ou locações nos filtros atuais.',
            tone: tone,
          ),
        ],
      );
    }

    final maxSold = ranking
        .map((r) => r.totalSold)
        .fold<int>(1, (acc, v) => v > acc ? v : acc);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnalyticsPanelHeader(
          icon: LucideIcons.mapPin,
          eyebrow: 'REGIÕES',
          title: 'Ranking por bairro',
          hint: 'Vendas, locações, disponibilidade e conversão por região.',
          tone: tone,
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < ranking.length && i < 15; i++)
          _regionRow(context, ranking[i], i, maxSold, tone, green, amber)
              .animate(key: ValueKey('rg-$i-${ranking[i].neighborhood}'))
              .fadeIn(
                delay: Duration(milliseconds: 25 * (i % 12)),
                duration: 200.ms,
              ),
      ],
    );
  }

  Widget _regionRow(BuildContext context, RegionRanking r, int index,
      int maxSold, Color tone, Color green, Color amber) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final ratio = (r.totalSold / maxSold).clamp(0.0, 1.0).toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              color: tone.withValues(alpha: isDark ? 0.2 : 0.12),
            ),
            alignment: Alignment.center,
            child: Text(
              '${r.rank > 0 ? r.rank : index + 1}º',
              style: TextStyle(
                color: tone,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.neighborhood,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    MiniPill(
                      label:
                          '${r.conversionRate.toStringAsFixed(0)}% conv.',
                      tone: AnalyticsTones.byScore(
                          context, r.conversionRate),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${r.city.isNotEmpty ? '${r.city} · ' : ''}'
                  '${r.totalSold} vendido${r.totalSold == 1 ? '' : 's'} · '
                  '${r.totalRented} alugado${r.totalRented == 1 ? '' : 's'} · '
                  '${r.totalAvailable} disponíve${r.totalAvailable == 1 ? 'l' : 'is'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: secondary,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Stack(
                    children: [
                      Container(
                        height: 6,
                        color: ThemeHelpers.borderLightColor(context)
                            .withValues(alpha: 0.55),
                      ),
                      FractionallySizedBox(
                        widthFactor:
                            ratio > 0 ? ratio.clamp(0.02, 1.0).toDouble() : 0.02,
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            gradient: LinearGradient(colors: [
                              tone.withValues(alpha: 0.55),
                              tone,
                            ]),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Painel: engajamento ─────────────────────────────────────────────────

  Widget _buildEngagementPanel(BuildContext context) {
    final tone = _tabTone(context, _PropTab.engagement);
    final blue = AnalyticsTones.blue(context);
    final purple = AnalyticsTones.purple(context);
    final amber = AnalyticsTones.amber(context);
    final red = AnalyticsTones.red(context);

    final stats = _engagement ?? const <PropertyEngagement>[];
    final active = stats.where((e) => e.total > 0).toList();
    final totals = _engagementTotals(stats);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnalyticsPanelHeader(
          icon: LucideIcons.messageCircle,
          eyebrow: 'ENGAJAMENTO',
          title: 'Interações por imóvel',
          hint:
              'Eventos do site público nos últimos $_engagementDays dia${_engagementDays == 1 ? '' : 's'}.',
          tone: tone,
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final d in _daysOptions) ...[
                AnalyticsChip(
                  label: d == 1 ? '24h' : '$d dias',
                  selected: _engagementDays == d,
                  accent: tone,
                  onTap: () {
                    if (_engagementDays == d) return;
                    setState(() => _engagementDays = d);
                    _loadEngagement();
                  },
                ),
                const SizedBox(width: 8),
              ],
              Container(
                width: 1,
                height: 22,
                margin: const EdgeInsets.only(right: 8),
                color: ThemeHelpers.borderLightColor(context),
              ),
              for (final (value, label) in _sortOptions) ...[
                AnalyticsChip(
                  label: label,
                  selected: _engagementSortBy == value,
                  accent: blue,
                  onTap: () {
                    if (_engagementSortBy == value) return;
                    setState(() => _engagementSortBy = value);
                    _loadEngagement();
                  },
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_engagementLoading && _engagement == null)
          LayoutBuilder(
            builder: (context, c) {
              final w = (c.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: List.generate(
                  4,
                  (_) => SkeletonBox(width: w, height: 92, borderRadius: 16),
                ),
              );
            },
          )
        else if (active.isEmpty)
          AnalyticsEmptyState(
            icon: LucideIcons.messageCircle,
            title: 'Sem engajamento no período',
            body:
                'Nenhuma interação registrada nos últimos $_engagementDays dia${_engagementDays == 1 ? '' : 's'}. Experimente ampliar a janela.',
            tone: tone,
          )
        else ...[
          MetricGrid(cards: [
            MetricCard(
              icon: LucideIcons.eye,
              label: 'Visualizações',
              value: _int.format(totals.views),
              tone: blue,
            ),
            MetricCard(
              icon: LucideIcons.messageCircle,
              label: 'WhatsApp',
              value: _int.format(totals.whatsapp),
              tone: tone,
            ),
            MetricCard(
              icon: LucideIcons.phone,
              label: 'Telefone',
              value: _int.format(totals.phone),
              tone: purple,
            ),
            MetricCard(
              icon: LucideIcons.heart,
              label: 'Favoritos',
              value: _int.format(totals.favorites),
              tone: red,
            ),
          ]),
          const SizedBox(height: 18),
          AnalyticsSubsectionHeader(
            label: 'Imóveis em destaque',
            icon: LucideIcons.flame,
            count: active.length,
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < active.length && i < 10; i++)
            _engagementRow(context, active[i], i, tone, blue, amber)
                .animate(key: ValueKey('pe-${active[i].propertyId}'))
                .fadeIn(
                  delay: Duration(milliseconds: 25 * (i % 12)),
                  duration: 200.ms,
                ),
        ],
      ],
    );
  }

  ({int views, int whatsapp, int phone, int favorites}) _engagementTotals(
      List<PropertyEngagement> stats) {
    var views = 0, whatsapp = 0, phone = 0, favorites = 0;
    for (final e in stats) {
      views += e.views;
      whatsapp += e.whatsappClicks;
      phone += e.phoneClicks;
      favorites += e.favorites;
    }
    return (views: views, whatsapp: whatsapp, phone: phone, favorites: favorites);
  }

  Widget _engagementRow(BuildContext context, PropertyEngagement e, int index,
      Color tone, Color blue, Color amber) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final title = (e.title?.trim().isNotEmpty ?? false)
        ? e.title!.trim()
        : 'Imóvel ${e.code ?? e.propertyId}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              color: tone.withValues(alpha: isDark ? 0.2 : 0.12),
            ),
            alignment: Alignment.center,
            child: Text(
              '${index + 1}º',
              style: TextStyle(
                color: tone,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                if (e.code != null && e.code!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Código ${e.code}',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: secondary,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (e.views > 0)
                      MiniPill(
                        icon: LucideIcons.eye,
                        label: _int.format(e.views),
                        tone: blue,
                      ),
                    if (e.whatsappClicks > 0)
                      MiniPill(
                        icon: LucideIcons.messageCircle,
                        label: _int.format(e.whatsappClicks),
                        tone: tone,
                      ),
                    if (e.phoneClicks > 0)
                      MiniPill(
                        icon: LucideIcons.phone,
                        label: _int.format(e.phoneClicks),
                        tone: AnalyticsTones.purple(context),
                      ),
                    if (e.favorites > 0)
                      MiniPill(
                        icon: LucideIcons.heart,
                        label: _int.format(e.favorites),
                        tone: AnalyticsTones.red(context),
                      ),
                    if (e.prints > 0)
                      MiniPill(
                        icon: LucideIcons.printer,
                        label: _int.format(e.prints),
                        tone: amber,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _int.format(e.total),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: tone,
                  height: 1.0,
                  letterSpacing: -0.4,
                ),
              ),
              Text(
                'ações',
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
    );
  }

  // ─── Skeleton (fiel ao layout real) ──────────────────────────────────────

  Widget _buildSkeleton(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(_kPadH, _kPadTop + 4, _kPadH, _kPadBottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonText(width: 170, height: 11, borderRadius: 4),
          const SizedBox(height: 12),
          const SkeletonText(width: 110, height: 32, borderRadius: 8),
          const SizedBox(height: 8),
          const SkeletonText(width: 230, height: 13, borderRadius: 4),
          const SizedBox(height: 20),
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      SkeletonText(width: 64, height: 9),
                      SizedBox(height: 9),
                      SkeletonText(width: 60, height: 20),
                      SizedBox(height: 7),
                      SkeletonText(width: 56, height: 9),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: SkeletonBox(
                      width: double.infinity, height: 38, borderRadius: 10),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, c) {
              final w = (c.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: List.generate(
                  2,
                  (_) => SkeletonBox(width: w, height: 92, borderRadius: 16),
                ),
              );
            },
          ),
          const SizedBox(height: 18),
          SkeletonBox(width: double.infinity, height: 170, borderRadius: 16),
        ],
      ),
    );
  }
}
