import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/minimal_body_chrome.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/multichannel_models.dart';
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

enum _McTab { overview, channels, engagement, recent }

/// Análise Multicanal — KPIs e gráficos por canal de origem do site público.
/// Paridade com `PublicSiteAnalyticsPage` do imobx-front
/// (módulo `public_site_analytics`, permissão `public_analytics:view`).
class MultichannelAnalyticsPage extends StatefulWidget {
  const MultichannelAnalyticsPage({super.key});

  @override
  State<MultichannelAnalyticsPage> createState() =>
      _MultichannelAnalyticsPageState();
}

class _MultichannelAnalyticsPageState extends State<MultichannelAnalyticsPage> {
  static const double _kPadH = 16;
  static const double _kPadTop = 10;
  static const double _kPadBottom = 88;
  static const double _kGap = 12;

  _McTab _activeTab = _McTab.overview;

  String _period = 'monthly';
  Set<String> _selectedCityKeys = <String>{};

  List<CityOption> _cities = const [];
  SourcesSummary? _sources;
  EngagementSummaryData? _engagement;
  String? _engagementCityLabel;

  RecentAttributionsData? _recent;
  final List<RecentLead> _recentItems = [];
  String? _recentChannel;
  bool _recentLoading = false;

  bool _loading = true;
  String? _error;

  bool get _canView => ModuleAccessService.instance
      .hasPermission('public_analytics:view');

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  // ─── Dados ────────────────────────────────────────────────────────────────

  List<String> get _effectiveCityKeys => _selectedCityKeys.isNotEmpty
      ? _selectedCityKeys.toList()
      : _cities.map((c) => c.key).toList();

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    if (_cities.isEmpty) {
      final citiesRes = await AnalyticsService.instance.getFilterCities();
      if (!mounted) return;
      if (citiesRes.success && citiesRes.data != null) {
        _cities = citiesRes.data!;
      }
    }

    final effective = _effectiveCityKeys;
    if (effective.isEmpty) {
      setState(() {
        _loading = false;
        _error =
            'Sua empresa ainda não possui imóveis cadastrados. Cadastre ao menos um imóvel para ver os analytics.';
      });
      return;
    }

    // Engajamento é por cidade — usa a primeira cidade efetiva.
    final firstCity = _parseCityKey(effective.first);

    final results = await Future.wait([
      AnalyticsService.instance.getSourcesSummary(
        period: _period,
        cities: effective,
      ),
      if (firstCity != null)
        AnalyticsService.instance.getEngagementSummary(
          city: firstCity.$1,
          state: firstCity.$2,
          period: _period,
        ),
    ]);

    if (!mounted) return;

    final sourcesRes = results[0];
    setState(() {
      _loading = false;
      if (sourcesRes.success && sourcesRes.data != null) {
        _sources = sourcesRes.data as SourcesSummary;
        _error = null;
      } else if (_sources == null) {
        _error = sourcesRes.message ?? 'Erro ao carregar análise multicanal';
      }
      if (results.length > 1) {
        final engRes = results[1];
        if (engRes.success && engRes.data != null) {
          _engagement = engRes.data as EngagementSummaryData;
          final c = firstCity;
          _engagementCityLabel =
              c == null ? null : '${c.$1} – ${c.$2}';
        }
      }
    });

    // Leads recentes (não bloqueia o painel).
    _loadRecent(reset: true);
  }

  (String, String)? _parseCityKey(String key) {
    final parts = key.split(',');
    if (parts.length < 2) return null;
    final city = parts[0].trim();
    final state = parts[1].trim().toUpperCase();
    if (city.isEmpty || state.length != 2) return null;
    return (city, state);
  }

  Future<void> _loadRecent({bool reset = false, String? channel}) async {
    if (_recentLoading) return;
    final effective = _effectiveCityKeys;
    if (effective.isEmpty) return;
    setState(() {
      _recentLoading = true;
      if (reset) {
        _recentItems.clear();
        _recent = null;
      }
      if (channel != null || reset) _recentChannel = channel;
    });
    final res = await AnalyticsService.instance.getRecentAttributions(
      period: _period,
      cities: effective,
      channel: _recentChannel,
      offset: reset ? 0 : _recentItems.length,
    );
    if (!mounted) return;
    setState(() {
      _recentLoading = false;
      if (res.success && res.data != null) {
        _recent = res.data;
        _recentItems.addAll(res.data!.items);
      }
    });
  }

  void _openFilters() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (ctx) => MultichannelFiltersSheet(
        period: _period,
        selectedCityKeys: _selectedCityKeys,
        availableCities: _cities,
        onApply: (period, cities) {
          setState(() {
            _period = period;
            _selectedCityKeys = cities;
            _sources = null;
            _engagement = null;
          });
          _loadAll();
        },
      ),
    );
  }

  int get _activeFilterCount =>
      (_period != 'monthly' ? 1 : 0) + (_selectedCityKeys.isNotEmpty ? 1 : 0);

  String get _periodLabel {
    switch (_period) {
      case 'daily':
        return 'diário';
      case 'weekly':
        return 'semanal';
      default:
        return 'mensal';
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canView) {
      return const AppScaffold(
        title: 'Análise Multicanal',
        showBottomNavigation: false,
        body: AnalyticsDeniedView(
          message: 'Você não tem acesso à análise multicanal.',
          permission: 'public_analytics:view',
        ),
      );
    }
    return AppScaffold(
      title: 'Análise Multicanal',
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
              child: _loading && _sources == null
                  ? _buildSkeleton(context)
                  : _error != null && _sources == null
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(
                              _kPadH, 48, _kPadH, _kPadBottom),
                          child: AnalyticsErrorState(
                            message: _error!,
                            onRetry: _loadAll,
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
    final s = _sources;
    final green = AnalyticsTones.green(context);
    final amber = AnalyticsTones.amber(context);
    final blue = AnalyticsTones.blue(context);
    final red = AnalyticsTones.red(context);

    final totalLeads = s?.totalLeads ?? 0;
    final quality = s?.dataQuality;
    final subtitleParts = <String>[
      '${_int.format(s?.totalViews ?? 0)} visualizações',
      '${_int.format(s?.totalContacts ?? 0)} contatos',
      'período $_periodLabel',
    ];
    if (quality != null && quality.unattributedLeadsPct > 0) {
      subtitleParts.add(
          '${quality.unattributedLeadsPct.toStringAsFixed(0)}% sem origem');
    }

    final roi = s?.paidRoi;
    final cpl = s?.paidCpl;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HeroEyebrow(
            label: 'ANÁLISE MULTICANAL',
            dotColor: totalLeads > 0 ? green : amber,
          ),
          const SizedBox(height: 10),
          HeroHeadline(
            value: _int.format(totalLeads),
            suffix: totalLeads == 1 ? 'lead no período' : 'leads no período',
            subtitle: subtitleParts.join(' · '),
          ),
          const SizedBox(height: 18),
          HeroKpiStrip(
            loading: _loading && s == null,
            blocks: [
              HeroKpiData(
                icon: LucideIcons.coins,
                label: 'INVESTIDO',
                value: _compactMoney.format(s?.totalSpend ?? 0),
                sub: 'mídia paga',
                tone: amber,
              ),
              HeroKpiData(
                icon: LucideIcons.crosshair,
                label: 'CPL',
                value: cpl == null ? '—' : _money.format(cpl),
                sub: 'custo por lead',
                tone: blue,
              ),
              HeroKpiData(
                icon: LucideIcons.trendingUp,
                label: 'ROI',
                value: roi == null
                    ? '—'
                    : '${roi >= 0 ? '+' : ''}${roi.toStringAsFixed(0)}%',
                sub: 'sobre o gasto',
                tone: roi != null && roi < 0 ? red : green,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Abas ─────────────────────────────────────────────────────────────────

  Color _tabTone(BuildContext context, _McTab tab) {
    switch (tab) {
      case _McTab.overview:
        return AnalyticsTones.accent(context);
      case _McTab.channels:
        return AnalyticsTones.purple(context);
      case _McTab.engagement:
        return AnalyticsTones.green(context);
      case _McTab.recent:
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
          for (final tab in _McTab.values)
            Expanded(
              child: AnalyticsFlushTab(
                icon: switch (tab) {
                  _McTab.overview => LucideIcons.radar,
                  _McTab.channels => LucideIcons.megaphone,
                  _McTab.engagement => LucideIcons.messageCircle,
                  _McTab.recent => LucideIcons.clock3,
                },
                label: switch (tab) {
                  _McTab.overview => 'Visão geral',
                  _McTab.channels => 'Canais',
                  _McTab.engagement => 'Engajamento',
                  _McTab.recent => 'Recentes',
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
      _McTab.overview => _buildOverviewPanel(context),
      _McTab.channels => _buildChannelsPanel(context),
      _McTab.engagement => _buildEngagementPanel(context),
      _McTab.recent => _buildRecentPanel(context),
    };
    return child
        .animate(key: ValueKey('mc-${_activeTab.name}'))
        .fadeIn(duration: 240.ms);
  }

  // ─── Painel: visão geral ─────────────────────────────────────────────────

  Widget _buildOverviewPanel(BuildContext context) {
    final s = _sources;
    final tone = _tabTone(context, _McTab.overview);
    final green = AnalyticsTones.green(context);
    final blue = AnalyticsTones.blue(context);
    final purple = AnalyticsTones.purple(context);
    final amber = AnalyticsTones.amber(context);

    if (s == null || s.channels.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnalyticsPanelHeader(
            icon: LucideIcons.radar,
            eyebrow: 'VISÃO GERAL',
            title: 'Resumo do período',
            hint: 'KPIs consolidados de todos os canais de origem.',
            tone: tone,
          ),
          AnalyticsEmptyState(
            icon: LucideIcons.radar,
            title: 'Sem dados no período',
            body:
                'Nenhum evento de origem foi registrado. Ajuste o período nos filtros ou aguarde novos acessos ao site.',
            tone: tone,
          ),
        ],
      );
    }

    final leadsPerDay = s.leadsPerDay;
    final channelsByLeads = [...s.channels]
      ..sort((a, b) => b.leads.compareTo(a.leads));
    final quality = s.dataQuality;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnalyticsPanelHeader(
          icon: LucideIcons.radar,
          eyebrow: 'VISÃO GERAL',
          title: 'Resumo do período',
          hint: _periodRangeHint(s),
          tone: tone,
        ),
        const SizedBox(height: 14),
        MetricGrid(cards: [
          MetricCard(
            icon: LucideIcons.eye,
            label: 'Visualizações',
            value: _int.format(s.totalViews),
            tone: blue,
          ),
          MetricCard(
            icon: LucideIcons.messageCircle,
            label: 'Contatos',
            value: _int.format(s.totalContacts),
            tone: green,
          ),
          MetricCard(
            icon: LucideIcons.users,
            label: 'Leads',
            value: _int.format(s.totalLeads),
            tone: tone,
          ),
          MetricCard(
            icon: LucideIcons.banknote,
            label: 'Receita atribuída',
            value: _compactMoney.format(s.totalRevenue),
            tone: purple,
          ),
        ]),
        const SizedBox(height: 18),
        const AnalyticsSubsectionHeader(
          label: 'Leads por canal',
          icon: LucideIcons.megaphone,
        ),
        const SizedBox(height: 12),
        HBarChart(
          tone: tone,
          items: [
            for (final c in channelsByLeads.take(8))
              BarItem(
                label: c.label,
                value: c.leads.toDouble(),
                valueLabel: _int.format(c.leads),
                sub: c.spend > 0
                    ? '${_compactMoney.format(c.spend)} investidos'
                    : null,
              ),
          ],
        ),
        if (leadsPerDay.length >= 2) ...[
          const SizedBox(height: 18),
          const AnalyticsSubsectionHeader(
            label: 'Leads por dia',
            icon: LucideIcons.chartColumn,
          ),
          const SizedBox(height: 12),
          MiniBarsChart(
            values: [for (final p in leadsPerDay) p.leads.toDouble()],
            tone: tone,
            startLabel: _shortDate(leadsPerDay.first.date),
            endLabel: _shortDate(leadsPerDay.last.date),
          ),
        ],
        if (quality != null) ...[
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.info,
                  size: 14,
                  color: quality.confidence == 'low'
                      ? amber
                      : ThemeHelpers.textSecondaryColor(context)),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '${quality.unattributedLeads} de ${quality.totalLeads} leads sem origem rastreável '
                  '(${quality.unattributedLeadsPct.toStringAsFixed(0)}%) · confiança da atribuição: ${quality.confidenceLabel.toLowerCase()}.',
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
        ],
      ],
    );
  }

  String _periodRangeHint(SourcesSummary s) {
    final start = DateTime.tryParse(s.startDate);
    final end = DateTime.tryParse(s.endDate);
    if (start == null || end == null) {
      return 'KPIs consolidados de todos os canais de origem.';
    }
    final fmt = DateFormat('dd/MM/yyyy', 'pt_BR');
    return 'De ${fmt.format(start)} a ${fmt.format(end)}'
        '${_activeFilterCount > 0 ? ' · $_activeFilterCount filtro${_activeFilterCount == 1 ? '' : 's'}' : ''}.';
  }

  String _shortDate(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return DateFormat('dd/MM', 'pt_BR').format(d);
  }

  // ─── Painel: canais ──────────────────────────────────────────────────────

  Widget _buildChannelsPanel(BuildContext context) {
    final s = _sources;
    final tone = _tabTone(context, _McTab.channels);
    final green = AnalyticsTones.green(context);
    final red = AnalyticsTones.red(context);
    final blue = AnalyticsTones.blue(context);

    if (s == null || s.channels.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnalyticsPanelHeader(
            icon: LucideIcons.megaphone,
            eyebrow: 'CANAIS',
            title: 'Origem dos leads',
            hint: 'Performance de cada canal — orgânico e mídia paga.',
            tone: tone,
          ),
          AnalyticsEmptyState(
            icon: LucideIcons.megaphone,
            title: 'Nenhum canal com dados',
            body: 'Sem eventos de origem no período selecionado.',
            tone: tone,
          ),
        ],
      );
    }

    final channels = [...s.channels]..sort((a, b) => b.leads.compareTo(a.leads));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnalyticsPanelHeader(
          icon: LucideIcons.megaphone,
          eyebrow: 'CANAIS',
          title: 'Origem dos leads',
          hint:
              'Leads, engajamento e retorno de cada canal no mesmo recorte.',
          tone: tone,
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < channels.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _channelCard(context, channels[i], tone, green, red, blue)
              .animate(key: ValueKey('ch-${channels[i].channel}'))
              .fadeIn(
                delay: Duration(milliseconds: 30 * i.clamp(0, 10)),
                duration: 220.ms,
              ),
        ],
        if (s.topCampaigns.isNotEmpty) ...[
          const SizedBox(height: 18),
          AnalyticsSubsectionHeader(
            label: 'Top campanhas',
            icon: LucideIcons.target,
            count: s.topCampaigns.length,
          ),
          const SizedBox(height: 6),
          for (final camp in s.topCampaigns.take(8))
            _campaignRow(context, camp, tone, green, red, blue),
        ],
      ],
    );
  }

  Widget _channelCard(
    BuildContext context,
    SourceChannel c,
    Color tone,
    Color green,
    Color red,
    Color blue,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final roi = c.roi;

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
                alignment: Alignment.center,
                child: Text(
                  c.label.isNotEmpty ? c.label[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: tone,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_int.format(c.views)} views · ${_int.format(c.contactIntents)} contatos',
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
                    _int.format(c.leads),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: tone,
                      letterSpacing: -0.4,
                      height: 1.0,
                    ),
                  ),
                  Text(
                    c.leads == 1 ? 'lead' : 'leads',
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
          if (c.spend > 0) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                MiniPill(
                  icon: LucideIcons.coins,
                  label: _compactMoney.format(c.spend),
                  tone: AnalyticsTones.amber(context),
                ),
                if (c.cpl != null)
                  MiniPill(
                    icon: LucideIcons.crosshair,
                    label: 'CPL ${_money.format(c.cpl)}',
                    tone: blue,
                  ),
                if (roi != null)
                  MiniPill(
                    icon: roi >= 0
                        ? LucideIcons.trendingUp
                        : LucideIcons.trendingDown,
                    label:
                        'ROI ${roi >= 0 ? '+' : ''}${roi.toStringAsFixed(0)}%',
                    tone: roi >= 0 ? green : red,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _campaignRow(
    BuildContext context,
    TopCampaign camp,
    Color tone,
    Color green,
    Color red,
    Color blue,
  ) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final action = camp.recommendedAction;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.target, size: 15, color: tone),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  camp.campaign,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    camp.channel,
                    if (camp.spend > 0) _compactMoney.format(camp.spend),
                    if (camp.cpl != null) 'CPL ${_money.format(camp.cpl)}',
                  ].join(' · '),
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
                '${_int.format(camp.leads)} ${camp.leads == 1 ? 'lead' : 'leads'}',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              if (action != null) ...[
                const SizedBox(height: 4),
                MiniPill(
                  label: switch (action) {
                    'increase' => 'Aumentar',
                    'decrease' => 'Reduzir',
                    _ => 'Manter',
                  },
                  tone: switch (action) {
                    'increase' => green,
                    'decrease' => red,
                    _ => blue,
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ─── Painel: engajamento ─────────────────────────────────────────────────

  Widget _buildEngagementPanel(BuildContext context) {
    final e = _engagement;
    final tone = _tabTone(context, _McTab.engagement);
    final blue = AnalyticsTones.blue(context);
    final purple = AnalyticsTones.purple(context);
    final amber = AnalyticsTones.amber(context);

    if (e == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnalyticsPanelHeader(
            icon: LucideIcons.messageCircle,
            eyebrow: 'ENGAJAMENTO',
            title: 'Interações no site',
            hint: 'Eventos reais do site público por cidade.',
            tone: tone,
          ),
          AnalyticsEmptyState(
            icon: LucideIcons.messageCircle,
            title: 'Sem dados de engajamento',
            body:
                'Nenhum evento registrado para a cidade no período selecionado.',
            tone: tone,
          ),
        ],
      );
    }

    final t = e.totals;
    final devices = e.deviceBreakdown;
    final deviceColors = <Color>[blue, purple, amber, tone];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnalyticsPanelHeader(
          icon: LucideIcons.messageCircle,
          eyebrow: 'ENGAJAMENTO',
          title: 'Interações no site',
          hint: _engagementCityLabel == null
              ? 'Eventos reais do site público.'
              : 'Eventos do site em $_engagementCityLabel'
                  '${_effectiveCityKeys.length > 1 ? ' (engajamento é por cidade)' : ''}.',
          tone: tone,
        ),
        const SizedBox(height: 14),
        MetricGrid(cards: [
          MetricCard(
            icon: LucideIcons.eye,
            label: 'Visualizações',
            value: _int.format(t.views),
            tone: blue,
          ),
          MetricCard(
            icon: LucideIcons.messageCircle,
            label: 'WhatsApp',
            value: _int.format(t.whatsappClicks),
            tone: tone,
          ),
          MetricCard(
            icon: LucideIcons.phone,
            label: 'Telefone',
            value: _int.format(t.phoneClicks),
            tone: purple,
          ),
          MetricCard(
            icon: LucideIcons.mail,
            label: 'E-mail',
            value: _int.format(t.emailClicks),
            tone: amber,
          ),
          MetricCard(
            icon: LucideIcons.heart,
            label: 'Favoritos',
            value: _int.format(t.favorites),
            tone: AnalyticsTones.red(context),
          ),
          MetricCard(
            icon: LucideIcons.share2,
            label: 'Compartilhamentos',
            value: _int.format(t.shares),
            tone: blue,
          ),
        ]),
        const SizedBox(height: 18),
        const AnalyticsSubsectionHeader(
          label: 'Conversão',
          icon: LucideIcons.trendingUp,
        ),
        const SizedBox(height: 12),
        HBarChart(
          tone: tone,
          items: [
            BarItem(
              label: 'Visualização → contato',
              value: e.conversion.viewToContactRate.clamp(0, 100).toDouble(),
              valueLabel:
                  '${e.conversion.viewToContactRate.toStringAsFixed(1).replaceAll('.', ',')}%',
            ),
            BarItem(
              label: 'Visualização → WhatsApp',
              value: e.conversion.viewToWhatsappRate.clamp(0, 100).toDouble(),
              valueLabel:
                  '${e.conversion.viewToWhatsappRate.toStringAsFixed(1).replaceAll('.', ',')}%',
              color: blue,
            ),
          ],
        ),
        if (devices.isNotEmpty) ...[
          const SizedBox(height: 18),
          const AnalyticsSubsectionHeader(
            label: 'Dispositivos',
            icon: LucideIcons.smartphone,
          ),
          const SizedBox(height: 12),
          DonutChart(
            centerLabel: 'EVENTOS',
            segments: [
              for (var i = 0; i < devices.length && i < 4; i++)
                DonutSegment(
                  label: devices[i].label,
                  value: devices[i].count.toDouble(),
                  color: deviceColors[i % deviceColors.length],
                ),
            ],
          ),
        ],
        if (e.topEngagedProperties.isNotEmpty) ...[
          const SizedBox(height: 18),
          AnalyticsSubsectionHeader(
            label: 'Imóveis mais engajados',
            icon: LucideIcons.house,
            count: e.topEngagedProperties.length,
          ),
          const SizedBox(height: 6),
          for (final p in e.topEngagedProperties.take(8))
            _engagedPropertyRow(context, p, tone),
        ],
      ],
    );
  }

  Widget _engagedPropertyRow(
      BuildContext context, TopEngagedProperty p, Color tone) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.house, size: 15, color: tone),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_int.format(p.views)} views · ${_int.format(p.whatsappClicks)} WhatsApp · ${_int.format(p.contactIntents)} contatos',
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
          MiniPill(
            label:
                '${p.conversionRate.toStringAsFixed(1).replaceAll('.', ',')}%',
            tone: AnalyticsTones.byScore(context, p.conversionRate * 10),
          ),
        ],
      ),
    );
  }

  // ─── Painel: recentes ────────────────────────────────────────────────────

  Widget _buildRecentPanel(BuildContext context) {
    final tone = _tabTone(context, _McTab.recent);
    final channels = _sources?.channels ?? const <SourceChannel>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnalyticsPanelHeader(
          icon: LucideIcons.clock3,
          eyebrow: 'RECENTES',
          title: 'Últimos leads atribuídos',
          hint: 'Cada lead com o canal e o método de captura da origem.',
          tone: tone,
        ),
        if (channels.isNotEmpty) ...[
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                AnalyticsChip(
                  label: 'Todos',
                  selected: _recentChannel == null,
                  accent: tone,
                  onTap: () => _loadRecent(reset: true),
                ),
                for (final c in channels) ...[
                  const SizedBox(width: 8),
                  AnalyticsChip(
                    label: c.label,
                    selected: _recentChannel == c.channel,
                    accent: tone,
                    onTap: () => _loadRecent(reset: true, channel: c.channel),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        if (_recentLoading && _recentItems.isEmpty)
          _recentSkeleton()
        else if (_recentItems.isEmpty)
          AnalyticsEmptyState(
            icon: LucideIcons.searchX,
            title: 'Nenhum lead recente',
            body: _recentChannel != null
                ? 'Nenhum lead deste canal no período.'
                : 'Nenhum lead atribuído no período selecionado.',
            tone: tone,
          )
        else ...[
          for (var i = 0; i < _recentItems.length; i++)
            _recentLeadRow(context, _recentItems[i], tone)
                .animate(key: ValueKey('rl-${_recentItems[i].id}-$i'))
                .fadeIn(
                  delay: Duration(milliseconds: 25 * (i % 12)),
                  duration: 200.ms,
                ),
          if (_recent?.hasMore == true)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Center(
                child: _recentLoading
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: tone,
                        ),
                      )
                    : OutlinedButton.icon(
                        onPressed: () => _loadRecent(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: tone,
                          side:
                              BorderSide(color: tone.withValues(alpha: 0.45)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(LucideIcons.chevronDown, size: 16),
                        label: const Text('Carregar mais'),
                      ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _recentLeadRow(BuildContext context, RecentLead lead, Color tone) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final fmt = DateFormat('dd/MM · HH:mm', 'pt_BR');
    final metaParts = <String>[
      if (lead.createdAt != null) fmt.format(lead.createdAt!.toLocal()),
      if (lead.assignedToName != null) lead.assignedToName!,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: tone.withValues(alpha: 0.12),
            ),
            child: Icon(LucideIcons.userPlus, size: 17, color: tone),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lead.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    MiniPill(label: lead.channelLabel, tone: tone),
                    MiniPill(
                      label: lead.captureMethodLabel,
                      tone: ThemeHelpers.textSecondaryColor(context),
                    ),
                  ],
                ),
                if (metaParts.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    metaParts.join(' · '),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: secondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (lead.dealValue != null && lead.dealValue! > 0) ...[
            const SizedBox(width: 8),
            Text(
              _compactMoney.format(lead.dealValue),
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: AnalyticsTones.green(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _recentSkeleton() {
    return Column(
      children: List.generate(
        5,
        (_) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              SkeletonBox(width: 38, height: 38, borderRadius: 12),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonText(width: 170, height: 14),
                    SizedBox(height: 7),
                    SkeletonText(width: 110, height: 11),
                  ],
                ),
              ),
            ],
          ),
        ),
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
          const SkeletonText(width: 150, height: 11, borderRadius: 4),
          const SizedBox(height: 12),
          const SkeletonText(width: 120, height: 32, borderRadius: 8),
          const SizedBox(height: 8),
          const SkeletonText(width: 250, height: 13, borderRadius: 4),
          const SizedBox(height: 20),
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      SkeletonText(width: 60, height: 9),
                      SizedBox(height: 9),
                      SkeletonText(width: 74, height: 20),
                      SizedBox(height: 7),
                      SkeletonText(width: 52, height: 9),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
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
                  4,
                  (_) =>
                      SkeletonBox(width: w, height: 92, borderRadius: 16),
                ),
              );
            },
          ),
          const SizedBox(height: 18),
          SkeletonBox(
              width: double.infinity, height: 160, borderRadius: 16),
        ],
      ),
    );
  }
}
