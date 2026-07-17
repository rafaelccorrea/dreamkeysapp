import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/shell_visual_tokens.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
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

/// Análise Multicanal — PAINEL da mesma família do Dashboard geral:
/// hero com placa de ícone + manchete editorial, spotlight do canal destaque,
/// faixa de KPIs com régua accent, chips de período, seções flush com filete
/// gradiente, faixa de composição por canal, gauges de conversão e insight
/// contextual. Paridade de dados com `PublicSiteAnalyticsPage` do imobx-front
/// (módulo `public_site_analytics`, permissão `public_analytics:view`).
class MultichannelAnalyticsPage extends StatefulWidget {
  const MultichannelAnalyticsPage({super.key});

  @override
  State<MultichannelAnalyticsPage> createState() =>
      _MultichannelAnalyticsPageState();
}

class _MultichannelAnalyticsPageState extends State<MultichannelAnalyticsPage> {
  static const double _kPadH = 20;
  static const double _kPadTop = 10;
  static const double _kPadBottom = 88;
  static const double _kPanelGap = 18;

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

  /// Índice onde começa o lote mais novo — só os itens recém-chegados entram
  /// com stagger de fade/slide (os anteriores ficam parados).
  int _recentBatchStart = 0;

  /// Se o usuário já paginou ao menos uma vez — habilita a linha de fecho
  /// "tudo carregado" quando a lista termina.
  bool _recentPaged = false;

  bool _loading = true;
  String? _error;

  bool get _canView =>
      ModuleAccessService.instance.hasPermission('public_analytics:view');

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
          _engagementCityLabel = c == null ? null : '${c.$1} – ${c.$2}';
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
        _recentBatchStart = 0;
        _recentPaged = false;
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
        _recentBatchStart = _recentItems.length;
        if (!reset && res.data!.items.isNotEmpty) _recentPaged = true;
        _recentItems.addAll(res.data!.items);
      }
    });
  }

  void _changePeriod(String period) {
    if (period == _period) return;
    setState(() {
      _period = period;
      _sources = null;
      _engagement = null;
    });
    _loadAll();
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

  /// Dimensões de filtro fora do padrão — alimenta o contador do gatilho de
  /// filtros (período ≠ mensal e recorte de cidades).
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

  /// Paleta cíclica dos canais — cor por posição, sempre da família semântica.
  List<Color> _channelPalette(BuildContext context) => [
        AnalyticsTones.accent(context),
        AnalyticsTones.blue(context),
        AnalyticsTones.purple(context),
        AnalyticsTones.amber(context),
        AnalyticsTones.green(context),
        const Color(0xFF64748B),
      ];

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
        _FilterTriggerButton(
          activeCount: _activeFilterCount,
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
    final s = _sources;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ..._ambientHighlights(context),
        Padding(
          padding:
              const EdgeInsets.fromLTRB(_kPadH, _kPadTop, _kPadH, _kPadBottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHero(context),
              const SizedBox(height: 12),
              _buildPeriodRow(context),
              const SizedBox(height: _kPanelGap),
              if (s == null || s.channels.isEmpty)
                AnalyticsEmptyState(
                  icon: LucideIcons.radar,
                  title: 'Sem sinais no período',
                  body:
                      'Nenhum evento de origem foi registrado. Ajuste o período nos chips acima ou aguarde novos acessos ao site.',
                  tone: AnalyticsTones.accent(context),
                )
              else ...[
                _buildPaidMediaPanel(context, s)
                    .animate(key: ValueKey('mc-paid-$_period'))
                    .fadeIn(duration: 240.ms),
                const SizedBox(height: _kPanelGap),
                _buildChannelsPanel(context, s)
                    .animate(key: ValueKey('mc-channels-$_period'))
                    .fadeIn(duration: 240.ms, delay: 40.ms),
                const SizedBox(height: _kPanelGap),
                _buildRhythmPanel(context, s)
                    .animate(key: ValueKey('mc-rhythm-$_period'))
                    .fadeIn(duration: 240.ms, delay: 80.ms),
              ],
              const SizedBox(height: _kPanelGap),
              _buildEngagementPanel(context)
                  .animate(key: ValueKey('mc-eng-$_period'))
                  .fadeIn(duration: 240.ms, delay: 120.ms),
              const SizedBox(height: _kPanelGap),
              _buildRecentPanel(context),
            ],
          ),
        ),
      ],
    );
  }

  /// Orbes desfocados por trás do conteúdo — leitura em camadas, DNA do
  /// dashboard geral.
  List<Widget> _ambientHighlights(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
        top: 300,
        left: -110,
        child: IgnorePointer(
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  cool.withValues(alpha: isDark ? 0.18 : 0.065),
                  cool.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  // ─── Hero (gramática do greeting do dashboard) ───────────────────────────

  SourceChannel? get _topChannel {
    final s = _sources;
    if (s == null || s.channels.isEmpty) return null;
    final sorted = [...s.channels]..sort((a, b) => b.leads.compareTo(a.leads));
    return sorted.first.leads > 0 ? sorted.first : null;
  }

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AnalyticsTones.accent(context);
    final isDark = theme.brightness == Brightness.dark;
    final s = _sources;
    final top = _topChannel;

    final headline =
        top != null ? '${top.label} lidera a captação' : 'Radar de aquisição';
    final subtitle = s == null
        ? 'Origem dos leads do site público, canal a canal.'
        : '${_int.format(s.totalLeads)} ${s.totalLeads == 1 ? 'lead' : 'leads'} no recorte $_periodLabel · '
            '${_int.format(s.totalViews)} visualizações';

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── TOP ROW: placa de ícone + eyebrow/manchete ────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent,
                      accent.withValues(alpha: 0.62),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: isDark ? 0.30 : 0.20),
                      blurRadius: isDark ? 16 : 11,
                      offset: Offset(0, isDark ? 8 : 4),
                      spreadRadius: isDark ? 0 : -1,
                    ),
                  ],
                ),
                child: const Icon(
                  LucideIcons.radar,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          'MULTICANAL',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.2,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _periodRangeLabel(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: ThemeHelpers.textSecondaryColor(context),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      headline,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        height: 1.05,
                        letterSpacing: -0.4,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ── SPOTLIGHT do canal destaque (ou empty-state) ──────
          _buildChannelSpotlight(context),

          const SizedBox(height: 14),

          // ── QUICK KPI strip ───────────────────────────────────
          _buildQuickKpiStrip(context),
        ],
      ),
    );
  }

  String _periodRangeLabel() {
    final s = _sources;
    if (s == null) return 'período $_periodLabel';
    final start = DateTime.tryParse(s.startDate);
    final end = DateTime.tryParse(s.endDate);
    if (start == null || end == null) return 'período $_periodLabel';
    final fmt = DateFormat('dd/MM', 'pt_BR');
    return '${fmt.format(start)} — ${fmt.format(end)}';
  }

  /// Bloco de atenção do hero: canal que mais capta no período — mesma
  /// anatomia do spotlight de próximo compromisso do dashboard.
  Widget _buildChannelSpotlight(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = AnalyticsTones.accent(context);
    final top = _topChannel;
    final s = _sources;

    if (top == null || s == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.black.withValues(alpha: 0.03),
          border: Border.all(color: ThemeHelpers.borderLightColor(context)),
        ),
        child: Row(
          children: [
            Icon(
              LucideIcons.antenna,
              size: 18,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Nenhum canal com leads no período · os sinais aparecem aqui',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    final share =
        s.totalLeads > 0 ? top.leads / s.totalLeads * 100 : 0.0;
    final roi = top.roi;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: accent.withValues(alpha: isDark ? 0.10 : 0.06),
        border: Border.all(color: accent.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Contagem grande à esquerda (coluna de tempo do dashboard)
          SizedBox(
            width: 64,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _int.format(top.leads),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: accent,
                      letterSpacing: -0.6,
                      height: 1,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  top.leads == 1 ? 'LEAD' : 'LEADS',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 36,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: accent.withValues(alpha: 0.25),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.sparkles, size: 13, color: accent),
                    const SizedBox(width: 5),
                    Text(
                      'CANAL DESTAQUE',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  top.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                    letterSpacing: -0.2,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${share.toStringAsFixed(0)}% dos leads · ${_int.format(top.views)} views',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (roi != null) ...[
            const SizedBox(width: 8),
            MiniPill(
              icon: roi >= 0
                  ? LucideIcons.trendingUp
                  : LucideIcons.trendingDown,
              label: 'ROI ${roi >= 0 ? '+' : ''}${roi.toStringAsFixed(0)}%',
              tone: roi >= 0
                  ? AnalyticsTones.green(context)
                  : AnalyticsTones.red(context),
            ),
          ],
        ],
      ),
    );
  }

  /// Manchete de KPIs — valor grande na cor semântica, rótulo fino e régua
  /// accent embaixo, colunas divididas por filete (composição do dashboard).
  Widget _buildQuickKpiStrip(BuildContext context) {
    final s = _sources;
    final items = <({Color tone, String label, String value})>[
      (
        tone: AnalyticsTones.accent(context),
        label: 'Leads',
        value: _int.format(s?.totalLeads ?? 0),
      ),
      (
        tone: AnalyticsTones.blue(context),
        label: 'Views',
        value: _int.format(s?.totalViews ?? 0),
      ),
      (
        tone: AnalyticsTones.green(context),
        label: 'Contatos',
        value: _int.format(s?.totalContacts ?? 0),
      ),
      (
        tone: AnalyticsTones.purple(context),
        label: 'Receita',
        value: (s?.totalRevenue ?? 0) > 0
            ? _compactMoney.format(s!.totalRevenue)
            : '—',
      ),
    ];

    final divColor =
        ThemeHelpers.borderLightColor(context).withValues(alpha: 0.6);
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) Container(width: 1, height: 38, color: divColor),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      items[i].value,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: items[i].tone,
                        letterSpacing: -0.6,
                        height: 1,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    items[i].label.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: ThemeHelpers.textSecondaryColor(context),
                      letterSpacing: 1.4,
                      fontSize: 9.5,
                      height: 1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 2,
                    width: 18,
                    decoration: BoxDecoration(
                      color: items[i].tone,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ─── Chips de período + escopo de cidades ─────────────────────────────────

  Widget _buildPeriodRow(BuildContext context) {
    final accent = AnalyticsTones.accent(context);
    final theme = Theme.of(context);
    final citiesLabel = _selectedCityKeys.isEmpty
        ? 'Todas as cidades'
        : _selectedCityKeys.length == 1
            ? (_parseCityKey(_selectedCityKeys.first)?.$1 ?? '1 cidade')
            : '${_selectedCityKeys.length} cidades';

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          AnalyticsChip(
            label: 'Diário',
            selected: _period == 'daily',
            accent: accent,
            onTap: () => _changePeriod('daily'),
          ),
          const SizedBox(width: 8),
          AnalyticsChip(
            label: 'Semanal',
            selected: _period == 'weekly',
            accent: accent,
            onTap: () => _changePeriod('weekly'),
          ),
          const SizedBox(width: 8),
          AnalyticsChip(
            label: 'Mensal',
            selected: _period == 'monthly',
            accent: accent,
            onTap: () => _changePeriod('monthly'),
          ),
          const SizedBox(width: 12),
          // Tag informativa do escopo — quem troca é o botão de Filtros.
          InkWell(
            onTap: _openFilters,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: ShellVisualTokens.dashboardGlassFill(context),
                border: Border.all(
                  color: ShellVisualTokens.dashboardGlassBorder(context),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.mapPin, size: 13, color: accent),
                  const SizedBox(width: 6),
                  Text(
                    citiesLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: ThemeHelpers.textColor(context),
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Cabeçalho flush de seção (gramática dos painéis do dashboard) ───────

  Widget _flushPanel({
    required BuildContext context,
    required String eyebrow,
    required String title,
    required IconData icon,
    required Color tone,
    required Widget child,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: isDark
                    ? tone.withValues(alpha: 0.14)
                    : ThemeHelpers.borderLightColor(context)
                        .withValues(alpha: 0.88),
                border: isDark
                    ? null
                    : Border.all(
                        color: ThemeHelpers.borderColor(context)
                            .withValues(alpha: 0.42),
                      ),
              ),
              child: Icon(icon, color: tone, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eyebrow,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
        const SizedBox(height: 10),
        Container(
          height: 3,
          width: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            gradient: LinearGradient(
              colors: isDark
                  ? [tone, tone.withValues(alpha: 0.15)]
                  : [
                      ThemeHelpers.borderColor(context)
                          .withValues(alpha: 0.35),
                      tone.withValues(alpha: 0.7),
                    ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        child,
      ],
    );
  }

  /// Divisor de sub-seção: rótulo maiúsculo + linha em gradiente (dashboard).
  Widget _sectionDivider(BuildContext context, String label,
      {Widget? trailing}) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
            fontSize: 10,
            height: 1,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  ShellVisualTokens.dashboardGlassBorder(context),
                  ShellVisualTokens.dashboardGlassBorder(context)
                      .withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing],
      ],
    );
  }

  /// Pill de tag do cabeçalho (gramática da pill de crescimento do dashboard).
  Widget _headerTagPill(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color tone,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          colors: [
            tone.withValues(alpha: isDark ? 0.34 : 0.2),
            tone.withValues(alpha: isDark ? 0.18 : 0.1),
          ],
        ),
        border: Border.all(color: tone.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: tone.withValues(alpha: isDark ? 0.22 : 0.11),
            blurRadius: isDark ? 10 : 7,
            offset: Offset(0, isDark ? 3 : 2),
            spreadRadius: -2,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: tone, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: tone,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.1,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Painel: mídia paga ───────────────────────────────────────────────────

  Widget _buildPaidMediaPanel(BuildContext context, SourcesSummary s) {
    final theme = Theme.of(context);
    final amber = AnalyticsTones.amber(context);
    final green = AnalyticsTones.green(context);
    final red = AnalyticsTones.red(context);
    final blue = AnalyticsTones.blue(context);
    final purple = AnalyticsTones.purple(context);
    final isDark = theme.brightness == Brightness.dark;

    final paidChannels = s.channels.where((c) => c.spend > 0).toList();
    final roi = s.paidRoi;
    final cpl = s.paidCpl;
    final spend = s.totalSpend;
    final revenue = s.totalRevenue;

    if (paidChannels.isEmpty) {
      return _flushPanel(
        context: context,
        eyebrow: 'INVESTIMENTO · RETORNO',
        title: 'Mídia paga',
        icon: LucideIcons.coins,
        tone: amber,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: ShellVisualTokens.inlineTileDecoration(
            context,
            amber,
            radius: 16,
          ),
          child: Row(
            children: [
              Icon(LucideIcons.coins, size: 18, color: amber),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Nenhum investimento importado no período — os KPIs de CPL e ROI aparecem quando houver gasto atribuído aos canais.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final maxVol = math.max(math.max(spend, revenue), 1.0);
    final fSpend = (spend / maxVol).clamp(0.0, 1.0).toDouble();
    final fRevenue = (revenue / maxVol).clamp(0.0, 1.0).toDouble();
    final delta = revenue - spend;

    return _flushPanel(
      context: context,
      eyebrow: 'INVESTIMENTO · RETORNO',
      title: 'Mídia paga',
      icon: LucideIcons.coins,
      tone: amber,
      trailing: roi != null
          ? _headerTagPill(
              context,
              icon: roi >= 0
                  ? Icons.trending_up_rounded
                  : Icons.trending_down_rounded,
              label: '${roi >= 0 ? '+' : ''}${roi.toStringAsFixed(0)}%',
              tone: roi >= 0 ? green : red,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hero financeiro inline — hierarquia tipográfica, sem card.
          Row(
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: amber,
                  boxShadow: [
                    BoxShadow(
                      color: amber.withValues(alpha: isDark ? 0.6 : 0.32),
                      blurRadius: isDark ? 6 : 5,
                      spreadRadius: isDark ? 0 : -1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              Text(
                'INVESTIDO NO PERÍODO',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: amber,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.6,
                  fontSize: 10,
                  height: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _money.format(spend),
                    style: theme.textTheme.headlineLarge?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.4,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
              if (delta.abs() > 0.5) ...[
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${delta >= 0 ? '+' : '−'}${_compactMoney.format(delta.abs())}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: delta >= 0 ? green : red,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          _compareRow(
            context,
            label: 'Investido',
            valueLabel: _compactMoney.format(spend),
            fraction: fSpend,
            color: amber,
            highlighted: true,
          ),
          const SizedBox(height: 8),
          _compareRow(
            context,
            label: 'Receita',
            valueLabel: _compactMoney.format(revenue),
            fraction: fRevenue,
            color: green,
            highlighted: revenue >= spend,
          ),
          const SizedBox(height: 18),
          _sectionDivider(context, 'KPIs de aquisição'),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final dense = c.maxWidth < 360;
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _kpiTile(
                        context,
                        label: 'CPL',
                        value: cpl == null ? '—' : _money.format(cpl),
                        sub: 'custo por lead',
                        icon: LucideIcons.crosshair,
                        color: blue,
                        dense: dense,
                      ),
                    ),
                    SizedBox(width: dense ? 8 : 10),
                    Expanded(
                      child: _kpiTile(
                        context,
                        label: 'ROI',
                        value: roi == null
                            ? '—'
                            : '${roi >= 0 ? '+' : ''}${roi.toStringAsFixed(0)}%',
                        sub: 'sobre o gasto',
                        icon: roi != null && roi < 0
                            ? LucideIcons.trendingDown
                            : LucideIcons.trendingUp,
                        color: roi != null && roi < 0 ? red : green,
                        dense: dense,
                      ),
                    ),
                    SizedBox(width: dense ? 8 : 10),
                    Expanded(
                      child: _kpiTile(
                        context,
                        label: 'Canais',
                        value: '${paidChannels.length}',
                        sub: 'com tráfego pago',
                        icon: LucideIcons.megaphone,
                        color: purple,
                        dense: dense,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Linha comparativa: label · barra horizontal animada · valor (dashboard).
  Widget _compareRow(
    BuildContext context, {
    required String label,
    required String valueLabel,
    required double fraction,
    required Color color,
    required bool highlighted,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: highlighted
                  ? ThemeHelpers.textColor(context)
                  : ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 10,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      color: color.withValues(alpha: isDark ? 0.1 : 0.07),
                    ),
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: fraction),
                      duration: const Duration(milliseconds: 720),
                      curve: Curves.easeOutCubic,
                      builder: (context, anim, _) => FractionallySizedBox(
                        widthFactor: anim,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(99),
                            gradient: LinearGradient(
                              colors: [
                                color.withValues(
                                  alpha: highlighted ? 0.95 : 0.7,
                                ),
                                color.withValues(
                                  alpha: highlighted ? 0.65 : 0.45,
                                ),
                              ],
                            ),
                            boxShadow: highlighted
                                ? [
                                    BoxShadow(
                                      color: color.withValues(
                                        alpha: isDark ? 0.34 : 0.2,
                                      ),
                                      blurRadius: isDark ? 8 : 6,
                                      offset: Offset(0, isDark ? 2 : 1),
                                      spreadRadius: -2,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 78),
          child: Text(
            valueLabel,
            textAlign: TextAlign.right,
            style: theme.textTheme.labelMedium?.copyWith(
              color: highlighted
                  ? ThemeHelpers.textColor(context)
                  : ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ],
    );
  }

  /// Tile de KPI com gradiente tonal + orbe decorativo (rail do dashboard).
  Widget _kpiTile(
    BuildContext context, {
    required String label,
    required String value,
    required String sub,
    required IconData icon,
    required Color color,
    required bool dense,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.all(dense ? 11 : 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: isDark ? 0.2 : 0.12),
            color.withValues(alpha: isDark ? 0.06 : 0.04),
          ],
        ),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.36 : 0.34),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF1A2340).withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                  spreadRadius: -4,
                ),
              ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -12,
            top: -16,
            child: IgnorePointer(
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: isDark ? 0.1 : 0.07),
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(dense ? 6 : 7),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: LinearGradient(
                        colors: [
                          color.withValues(alpha: isDark ? 0.5 : 0.42),
                          color.withValues(alpha: isDark ? 0.24 : 0.22),
                        ],
                      ),
                    ),
                    child: Icon(
                      icon,
                      size: dense ? 13 : 15,
                      color: Colors.white.withValues(alpha: 0.96),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    label.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color.withValues(alpha: isDark ? 0.95 : 0.9),
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.95,
                      fontSize: 9.5,
                      height: 1,
                    ),
                  ),
                ],
              ),
              SizedBox(height: dense ? 10 : 12),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                sub,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.05,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Painel: canais (faixa de composição + legenda quantitativa) ─────────

  Widget _buildChannelsPanel(BuildContext context, SourcesSummary s) {
    final purple = AnalyticsTones.purple(context);
    final green = AnalyticsTones.green(context);
    final red = AnalyticsTones.red(context);
    final blue = AnalyticsTones.blue(context);

    final channels = [...s.channels]..sort((a, b) => b.leads.compareTo(a.leads));
    final withLeads = channels.where((c) => c.leads > 0).toList();
    final palette = _channelPalette(context);
    final totalLeads = s.totalLeads;

    // Top 5 + agregado "Outros" — a faixa fica legível e a legenda enxuta.
    final top = withLeads.take(5).toList();
    final restLeads =
        withLeads.skip(5).fold<int>(0, (acc, c) => acc + c.leads);
    final entries = <({String label, int leads, Color color})>[
      for (var i = 0; i < top.length; i++)
        (label: top[i].label, leads: top[i].leads, color: palette[i]),
      if (restLeads > 0)
        (label: 'Outros', leads: restLeads, color: palette.last),
    ];

    return _flushPanel(
      context: context,
      eyebrow: 'ORIGEM DOS LEADS',
      title: 'Composição por canal',
      icon: LucideIcons.megaphone,
      tone: purple,
      trailing: _headerTagPill(
        context,
        icon: LucideIcons.megaphone,
        label:
            '${withLeads.length} ${withLeads.length == 1 ? 'canal' : 'canais'}',
        tone: purple,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Nenhum lead atribuído no período.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      fontWeight: FontWeight.w600,
                    ),
              ),
            )
          else ...[
            _compositionRibbon(context, entries),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, c) => _compositionLegend(
                context,
                entries,
                totalLeads,
                c.maxWidth,
              ),
            ),
          ],
          if (s.topCampaigns.isNotEmpty) ...[
            const SizedBox(height: 18),
            _sectionDivider(
              context,
              'Top campanhas',
              trailing: Text(
                '${s.topCampaigns.length}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: purple,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
            const SizedBox(height: 4),
            for (final camp in s.topCampaigns.take(8))
              _campaignRow(context, camp, purple, green, red, blue),
          ],
        ],
      ),
    );
  }

  /// Barra única em camadas — track + segmentos com gradiente (composição de
  /// pontos do dashboard).
  Widget _compositionRibbon(
    BuildContext context,
    List<({String label, int leads, Color color})> entries,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.04),
        border: Border.all(
          color: ShellVisualTokens.dashboardGlassBorder(context),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: SizedBox(
          height: 14,
          child: Row(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                Expanded(
                  flex: entries[i].leads,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: Duration(milliseconds: 600 + i * 80),
                    curve: Curves.easeOutCubic,
                    builder: (context, anim, _) => Opacity(
                      opacity: anim,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              entries[i].color.withValues(alpha: 0.95),
                              entries[i].color.withValues(alpha: 0.7),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Legenda quantitativa em tiles com borda — 2 colunas quando há espaço.
  Widget _compositionLegend(
    BuildContext context,
    List<({String label, int leads, Color color})> entries,
    int total,
    double maxW,
  ) {
    Widget row(({String label, int leads, Color color}) e) {
      final theme = Theme.of(context);
      final pct = total > 0 ? e.leads / total * 100 : 0.0;
      return Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: e.color,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                e.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              _int.format(e.leads),
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w900,
                fontSize: 12,
                color: e.color,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '· ${pct.toStringAsFixed(0)}%',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 10.5,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
          ],
        ),
      );
    }

    final rows = entries.map(row).toList();
    final twoCols = maxW >= 360 && rows.length > 1;
    if (!twoCols) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            rows[i],
          ],
        ],
      );
    }
    final left = <Widget>[];
    final right = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      (i.isEven ? left : right).add(rows[i]);
    }
    Widget col(List<Widget> items) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              items[i],
            ],
          ],
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: col(left)),
        const SizedBox(width: 10),
        Expanded(child: col(right)),
      ],
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

  // ─── Painel: ritmo do período (série diária + insight) ───────────────────

  Widget _buildRhythmPanel(BuildContext context, SourcesSummary s) {
    final blue = AnalyticsTones.blue(context);
    final leadsPerDay = s.leadsPerDay;
    final theme = Theme.of(context);

    final peak = leadsPerDay.isEmpty
        ? null
        : leadsPerDay.reduce((a, b) => b.leads >= a.leads ? b : a);

    return _flushPanel(
      context: context,
      eyebrow: 'RITMO DO PERÍODO',
      title: 'Leads por dia',
      icon: LucideIcons.chartColumn,
      tone: blue,
      trailing: peak != null && peak.leads > 0
          ? _headerTagPill(
              context,
              icon: LucideIcons.flame,
              label: 'pico ${_int.format(peak.leads)}',
              tone: blue,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (leadsPerDay.length >= 2)
            MiniBarsChart(
              values: [for (final p in leadsPerDay) p.leads.toDouble()],
              tone: blue,
              height: 110,
              startLabel: _shortDate(leadsPerDay.first.date),
              endLabel: _shortDate(leadsPerDay.last.date),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Série diária insuficiente para desenhar o ritmo — amplie o período.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ..._insightPill(context, s),
        ],
      ),
    );
  }

  /// Insight contextual — um único destaque calculado dos dados, em tile
  /// tingido (gramática do spotlight do dashboard).
  List<Widget> _insightPill(BuildContext context, SourcesSummary s) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    ({IconData icon, Color tone, String text})? insight;

    final q = s.dataQuality;
    if (q != null && q.totalLeads > 0 && q.unattributedLeadsPct >= 30) {
      insight = (
        icon: LucideIcons.info,
        tone: AnalyticsTones.amber(context),
        text:
            '${q.unattributedLeadsPct.toStringAsFixed(0)}% dos leads estão sem origem rastreável (confiança ${q.confidenceLabel.toLowerCase()}) — os números por canal podem estar subestimados.',
      );
    } else {
      final paid = s.channels
          .where((c) => c.spend > 0 && (c.roi ?? double.negativeInfinity) > 0)
          .toList()
        ..sort((a, b) => (b.roi ?? 0).compareTo(a.roi ?? 0));
      if (paid.isNotEmpty) {
        final best = paid.first;
        insight = (
          icon: LucideIcons.lightbulb,
          tone: AnalyticsTones.green(context),
          text:
              '${best.label} devolve +${best.roi!.toStringAsFixed(0)}% sobre o investimento — é o canal pago mais eficiente do período.',
        );
      } else {
        final days = s.leadsPerDay;
        if (days.isNotEmpty) {
          final peak = days.reduce((a, b) => b.leads >= a.leads ? b : a);
          if (peak.leads > 0) {
            insight = (
              icon: LucideIcons.lightbulb,
              tone: AnalyticsTones.blue(context),
              text:
                  'Pico de captação em ${_shortDate(peak.date)}: ${_int.format(peak.leads)} ${peak.leads == 1 ? 'lead' : 'leads'} num único dia.',
            );
          }
        }
      }
    }

    if (insight == null) return const [];
    final tone = insight.tone;
    return [
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: tone.withValues(alpha: isDark ? 0.10 : 0.06),
          border: Border.all(color: tone.withValues(alpha: 0.32)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(insight.icon, size: 16, color: tone),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                insight.text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  String _shortDate(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return DateFormat('dd/MM', 'pt_BR').format(d);
  }

  // ─── Painel: engajamento no site (gauges + donut) ─────────────────────────

  Widget _buildEngagementPanel(BuildContext context) {
    final e = _engagement;
    final green = AnalyticsTones.green(context);
    final blue = AnalyticsTones.blue(context);
    final purple = AnalyticsTones.purple(context);
    final amber = AnalyticsTones.amber(context);
    final red = AnalyticsTones.red(context);
    final theme = Theme.of(context);

    if (e == null) {
      return _flushPanel(
        context: context,
        eyebrow: 'SITE PÚBLICO',
        title: 'Engajamento',
        icon: LucideIcons.messageCircle,
        tone: green,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: ShellVisualTokens.inlineTileDecoration(
            context,
            green,
            radius: 16,
          ),
          child: Row(
            children: [
              Icon(LucideIcons.messageCircle, size: 18, color: green),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Sem eventos de engajamento para a cidade no período selecionado.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final t = e.totals;
    final devices = e.deviceBreakdown;
    final deviceColors = <Color>[blue, purple, amber, green];

    final meterContact = _conversionStatTile(
      context,
      label: 'Visualização → Contato',
      rate: e.conversion.viewToContactRate,
      base: const Color(0xFF6366F1),
      icon: LucideIcons.messageSquare,
    );
    final meterWhats = _conversionStatTile(
      context,
      label: 'Visualização → WhatsApp',
      rate: e.conversion.viewToWhatsappRate,
      base: const Color(0xFFEC4899),
      icon: LucideIcons.messageCircle,
    );
    final whatsTile = _bigCountTile(
      context,
      label: 'CLIQUES NO WHATSAPP',
      count: t.whatsappClicks,
      base: green,
    );

    return _flushPanel(
      context: context,
      eyebrow: _engagementCityLabel == null
          ? 'SITE PÚBLICO'
          : 'SITE PÚBLICO · ${_engagementCityLabel!.toUpperCase()}',
      title: 'Engajamento e conversão',
      icon: LucideIcons.messageCircle,
      tone: green,
      trailing: _headerTagPill(
        context,
        icon: LucideIcons.eye,
        label: _int.format(t.views),
        tone: blue,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Medidores de conversão — título SEMPRE em largura total (sem
          // truncar): lado a lado só quando há espaço de sobra.
          LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 500;
              if (wide) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: meterContact),
                      const SizedBox(width: 10),
                      Expanded(child: meterWhats),
                    ],
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  meterContact,
                  const SizedBox(height: 10),
                  meterWhats,
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          whatsTile,
          const SizedBox(height: 10),
          // Mini chips de interação — telefone, e-mail, favoritos, shares.
          Row(
            children: [
              Expanded(
                child: _miniChip(
                  context,
                  icon: LucideIcons.phone,
                  value: _int.format(t.phoneClicks),
                  label: 'Telefone',
                  tone: purple,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniChip(
                  context,
                  icon: LucideIcons.mail,
                  value: _int.format(t.emailClicks),
                  label: 'E-mail',
                  tone: amber,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniChip(
                  context,
                  icon: LucideIcons.heart,
                  value: _int.format(t.favorites),
                  label: 'Favoritos',
                  tone: red,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniChip(
                  context,
                  icon: LucideIcons.share2,
                  value: _int.format(t.shares),
                  label: 'Compart.',
                  tone: blue,
                ),
              ),
            ],
          ),
          if (devices.isNotEmpty) ...[
            const SizedBox(height: 18),
            _sectionDivider(context, 'Dispositivos'),
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
            _sectionDivider(
              context,
              'Imóveis mais engajados',
              trailing: Text(
                '${e.topEngagedProperties.length}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: green,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 4),
            for (final p in e.topEngagedProperties.take(8))
              _engagedPropertyRow(context, p, green),
          ],
        ],
      ),
    );
  }

  /// Tom por taxa de conversão do site (benchmarks próprios do funil web).
  Color _rateTone(BuildContext context, double rate) {
    if (rate >= 6) return AnalyticsTones.green(context);
    if (rate >= 2.5) return AnalyticsTones.amber(context);
    return AnalyticsTones.red(context);
  }

  String _rateStatusLabel(double rate) {
    if (rate >= 6) return 'FORTE';
    if (rate >= 2.5) return 'EM RITMO';
    if (rate > 0) return 'PRECISA ATENÇÃO';
    return 'SEM REGISTRO';
  }

  /// Medidor de conversão "stat tile" — substitui o gauge semicircular que
  /// truncava o título: anel fino ao redor da placa de ícone (progresso sobre
  /// o benchmark de 10%), título em LARGURA TOTAL com quebra em até 2 linhas
  /// (nunca reticências), número contado em animação e pill meter segmentado
  /// que acende da esquerda pra direita.
  Widget _conversionStatTile(
    BuildContext context, {
    required String label,
    required double rate,
    required Color base,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = _rateTone(context, rate);
    final progress = (rate / 10).clamp(0.0, 1.0).toDouble();
    const segments = 10;

    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            base.withValues(alpha: isDark ? 0.18 : 0.1),
            base.withValues(alpha: isDark ? 0.05 : 0.04),
          ],
        ),
        border: Border.all(color: base.withValues(alpha: isDark ? 0.32 : 0.3)),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF1A2340).withValues(alpha: 0.055),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                  spreadRadius: -4,
                ),
              ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -16,
            top: -22,
            child: IgnorePointer(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: base.withValues(alpha: isDark ? 0.1 : 0.065),
                ),
              ),
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 950),
            curve: Curves.easeOutCubic,
            builder: (context, anim, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Anel fino no canto — progresso sobre o benchmark,
                    // com a placa de ícone no centro.
                    SizedBox(
                      width: 46,
                      height: 46,
                      child: CustomPaint(
                        painter: _RingMeterPainter(
                          progress: anim * progress,
                          color: tone,
                          trackColor: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : base.withValues(alpha: 0.12),
                        ),
                        child: Center(
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  base.withValues(alpha: isDark ? 0.5 : 0.42),
                                  base.withValues(
                                      alpha: isDark ? 0.24 : 0.22),
                                ],
                              ),
                            ),
                            child: Icon(
                              icon,
                              size: 13,
                              color: Colors.white.withValues(alpha: 0.96),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Título em largura total — quebra, NUNCA trunca.
                          Text(
                            label.toUpperCase(),
                            softWrap: true,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: base.withValues(
                                  alpha: isDark ? 0.95 : 0.88),
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.05,
                              fontSize: 10,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: tone,
                                  boxShadow: [
                                    BoxShadow(
                                      color: tone.withValues(
                                          alpha: isDark ? 0.55 : 0.32),
                                      blurRadius: isDark ? 5 : 4,
                                      spreadRadius: isDark ? 0 : -0.5,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  _rateStatusLabel(rate),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: tone,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                    fontSize: 9.5,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      // O meter satura no benchmark de 10%, mas o número é
                      // sempre a taxa real (contada na entrada).
                      '${(rate * anim).toStringAsFixed(1).replaceAll('.', ',')}%',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: ThemeHelpers.textColor(context),
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.9,
                        height: 1,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        'benchmark 10%',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                          fontWeight: FontWeight.w700,
                          fontSize: 9.5,
                          letterSpacing: 0.3,
                          height: 1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                // Pill meter segmentado — cada gomo vale 1 p.p. até 10%.
                Row(
                  children: [
                    for (var i = 0; i < segments; i++) ...[
                      if (i > 0) const SizedBox(width: 3),
                      Expanded(
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(99),
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : base.withValues(alpha: 0.09),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor:
                                    ((anim * progress * segments) - i)
                                        .clamp(0.0, 1.0),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(99),
                                    gradient: LinearGradient(
                                      colors: [
                                        tone.withValues(alpha: 0.95),
                                        tone.withValues(alpha: 0.6),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Tile de contagem grande com barra de intensidade (tile de matches do
  /// dashboard).
  Widget _bigCountTile(
    BuildContext context, {
    required String label,
    required int count,
    required Color base,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const segments = 5;
    final lit = count <= 0
        ? 0
        : count >= 500
            ? segments
            : count >= 200
                ? 4
                : count >= 75
                    ? 3
                    : count >= 25
                        ? 2
                        : 1;

    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            base.withValues(alpha: isDark ? 0.2 : 0.12),
            base.withValues(alpha: isDark ? 0.06 : 0.04),
          ],
        ),
        border: Border.all(color: base.withValues(alpha: isDark ? 0.36 : 0.3)),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF1A2340).withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                  spreadRadius: -4,
                ),
              ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -10,
            bottom: -14,
            child: IgnorePointer(
              child: Icon(
                LucideIcons.messageCircle,
                size: 96,
                color: base.withValues(alpha: isDark ? 0.06 : 0.045),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      gradient: LinearGradient(
                        colors: [
                          base.withValues(alpha: isDark ? 0.5 : 0.42),
                          base.withValues(alpha: isDark ? 0.24 : 0.22),
                        ],
                      ),
                    ),
                    child: const Icon(
                      LucideIcons.messageCircle,
                      size: 13,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      // Título informativo — quebra em largura total, nunca
                      // trunca (regra da tela).
                      softWrap: true,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: base.withValues(alpha: isDark ? 0.95 : 0.88),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.85,
                        fontSize: 9.5,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 70,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: count.toDouble()),
                          duration: const Duration(milliseconds: 750),
                          curve: Curves.easeOutCubic,
                          builder: (context, anim, _) => Text(
                            _int.format(anim.round()),
                            style: theme.textTheme.displaySmall?.copyWith(
                              color: ThemeHelpers.textColor(context),
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1.6,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        count == 1
                            ? '1 conversa iniciada'
                            : '${_int.format(count)} conversas iniciadas',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.05,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (var i = 0; i < segments; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: i < lit ? 1.0 : 0.0),
                        duration: Duration(milliseconds: 350 + i * 90),
                        curve: Curves.easeOutCubic,
                        builder: (context, anim, _) => Container(
                          height: 5,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(99),
                            color:
                                base.withValues(alpha: isDark ? 0.08 : 0.07),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: anim,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(99),
                                    gradient: LinearGradient(
                                      colors: [
                                        base.withValues(alpha: 0.95),
                                        base.withValues(alpha: 0.6),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Mini chip de interação — valor + rótulo com placa de ícone tintada.
  Widget _miniChip(
    BuildContext context, {
    required IconData icon,
    required String value,
    required String label,
    required Color tone,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 9, 9, 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              color: tone.withValues(alpha: isDark ? 0.18 : 0.10),
            ),
            child: Icon(icon, size: 14, color: tone),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: ThemeHelpers.textColor(context),
                letterSpacing: -0.3,
                height: 1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
              fontSize: 8.5,
              height: 1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
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

  // ─── Painel: últimos leads atribuídos ─────────────────────────────────────

  Widget _buildRecentPanel(BuildContext context) {
    final amber = AnalyticsTones.amber(context);
    final channels = _sources?.channels ?? const <SourceChannel>[];
    final total = _recent?.total;

    return _flushPanel(
      context: context,
      eyebrow: 'ATRIBUIÇÃO',
      title: 'Últimos leads captados',
      icon: LucideIcons.clock3,
      tone: amber,
      trailing: total != null && total > 0
          ? _headerTagPill(
              context,
              icon: LucideIcons.userPlus,
              label: _int.format(total),
              tone: amber,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (channels.isNotEmpty) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  AnalyticsChip(
                    label: 'Todos',
                    selected: _recentChannel == null,
                    accent: amber,
                    onTap: () => _loadRecent(reset: true),
                  ),
                  for (final c in channels) ...[
                    const SizedBox(width: 8),
                    AnalyticsChip(
                      label: c.label,
                      selected: _recentChannel == c.channel,
                      accent: amber,
                      onTap: () =>
                          _loadRecent(reset: true, channel: c.channel),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (_recentLoading && _recentItems.isEmpty)
            _recentSkeleton()
          else if (_recentItems.isEmpty)
            AnalyticsEmptyState(
              icon: LucideIcons.searchX,
              title: 'Nenhum lead recente',
              body: _recentChannel != null
                  ? 'Nenhum lead deste canal no período.'
                  : 'Nenhum lead atribuído no período selecionado.',
              tone: amber,
            )
          else ...[
            for (var i = 0; i < _recentItems.length; i++)
              _recentLeadRow(context, _recentItems[i], amber)
                  .animate(key: ValueKey('rl-${_recentItems[i].id}-$i'))
                  .fadeIn(
                    delay: Duration(
                      milliseconds:
                          30 * ((i - _recentBatchStart).clamp(0, 11)),
                    ),
                    duration: 240.ms,
                    curve: Curves.easeOut,
                  )
                  .slideY(
                    begin: 0.10,
                    end: 0,
                    delay: Duration(
                      milliseconds:
                          30 * ((i - _recentBatchStart).clamp(0, 11)),
                    ),
                    duration: 300.ms,
                    curve: Curves.easeOutCubic,
                  ),
            _recentListFooter(context, amber),
          ],
        ],
      ),
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

  /// Fecho da lista de leads — nada de botão avulso: uma linha integrada à
  /// lista com contagem "mostrando X de Y", régua de progresso da paginação,
  /// spinner inline discreto durante o carregamento e, quando tudo já foi
  /// paginado, um filete de encerramento silencioso.
  Widget _recentListFooter(BuildContext context, Color tone) {
    final theme = Theme.of(context);
    final data = _recent;
    if (data == null) return const SizedBox.shrink();

    final total = data.total;
    final shown = _recentItems.length;
    final secondary = ThemeHelpers.textSecondaryColor(context);

    // ── Tudo carregado após paginar: filete de encerramento ────────────────
    if (!data.hasMore) {
      if (!_recentPaged || shown == 0) return const SizedBox.shrink();
      Widget hairline({required bool fadeLeft}) => Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: fadeLeft
                      ? [
                          ShellVisualTokens.dashboardGlassBorder(context)
                              .withValues(alpha: 0.0),
                          ShellVisualTokens.dashboardGlassBorder(context),
                        ]
                      : [
                          ShellVisualTokens.dashboardGlassBorder(context),
                          ShellVisualTokens.dashboardGlassBorder(context)
                              .withValues(alpha: 0.0),
                        ],
                ),
              ),
            ),
          );
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Row(
          children: [
            hairline(fadeLeft: true),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.check, size: 12, color: tone),
                  const SizedBox(width: 6),
                  Text(
                    '${_int.format(total)} ${total == 1 ? 'LEAD EXIBIDO' : 'LEADS EXIBIDOS'}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      fontSize: 9.5,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
            hairline(fadeLeft: false),
          ],
        ),
      ).animate().fadeIn(duration: 260.ms);
    }

    // ── Há mais leads: linha de carregamento integrada ─────────────────────
    final isDark = theme.brightness == Brightness.dark;
    final remaining = math.max(total - shown, 0);
    final fraction =
        total > 0 ? (shown / total).clamp(0.0, 1.0).toDouble() : 0.0;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: ShellVisualTokens.dashboardGlassFill(context),
          border: Border.all(
            color: ShellVisualTokens.dashboardGlassBorder(context),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _recentLoading
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    _loadRecent();
                  },
            splashColor: tone.withValues(alpha: 0.10),
            highlightColor: tone.withValues(alpha: 0.05),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
              child: Row(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: _recentLoading
                        ? SizedBox(
                            key: const ValueKey('rlf-spin'),
                            width: 30,
                            height: 30,
                            child: Padding(
                              padding: const EdgeInsets.all(7),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: tone,
                              ),
                            ),
                          )
                        : Container(
                            key: const ValueKey('rlf-icon'),
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color: tone.withValues(
                                alpha: isDark ? 0.16 : 0.10,
                              ),
                            ),
                            child: Icon(
                              LucideIcons.chevronsDown,
                              size: 16,
                              color: tone,
                            ),
                          ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Text(
                            _recentLoading
                                ? 'Carregando mais leads…'
                                : 'Carregar mais leads',
                            key: ValueKey('rlf-title-$_recentLoading'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: ThemeHelpers.textColor(context),
                              fontSize: 13,
                              height: 1.1,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Text(
                              'mostrando ${_int.format(shown)} de ${_int.format(total)}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: secondary,
                                fontWeight: FontWeight.w700,
                                fontSize: 10.5,
                                height: 1,
                                letterSpacing: 0.1,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Régua fina do quanto da lista já chegou.
                            Expanded(
                              child: SizedBox(
                                height: 3,
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(99),
                                          color: tone.withValues(
                                            alpha: isDark ? 0.12 : 0.10,
                                          ),
                                        ),
                                      ),
                                    ),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(99),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: TweenAnimationBuilder<double>(
                                          tween: Tween(begin: 0, end: fraction),
                                          duration: const Duration(
                                              milliseconds: 500),
                                          curve: Curves.easeOutCubic,
                                          builder: (context, anim, _) =>
                                              FractionallySizedBox(
                                            widthFactor: anim,
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(99),
                                                gradient: LinearGradient(
                                                  colors: [
                                                    tone.withValues(
                                                        alpha: 0.9),
                                                    tone.withValues(
                                                        alpha: 0.55),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (remaining > 0) ...[
                    const SizedBox(width: 10),
                    MiniPill(label: '+${_int.format(remaining)}', tone: tone),
                  ],
                ],
              ),
            ),
          ),
        ),
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

  // ─── Skeleton (fiel ao layout do painel) ──────────────────────────────────

  Widget _buildSkeleton(BuildContext context) {
    Widget panelHeader({double titleW = 170, bool trailing = true}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 44, height: 44, borderRadius: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SkeletonText(width: 110, height: 10),
                      const SizedBox(height: 4),
                      SkeletonText(width: titleW, height: 16),
                    ],
                  ),
                ),
                if (trailing)
                  SkeletonBox(width: 84, height: 30, borderRadius: 999),
              ],
            ),
            const SizedBox(height: 10),
            SkeletonBox(width: 44, height: 3, borderRadius: 3),
          ],
        );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ..._ambientHighlights(context),
        Padding(
          padding:
              const EdgeInsets.fromLTRB(_kPadH, _kPadTop, _kPadH, _kPadBottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Hero: placa + eyebrow/título/sub
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 52, height: 52, borderRadius: 16),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SkeletonText(width: 150, height: 10, borderRadius: 4),
                        SizedBox(height: 8),
                        SkeletonText(width: 220, height: 20, borderRadius: 6),
                        SizedBox(height: 7),
                        SkeletonText(width: 250, height: 12, borderRadius: 4),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Spotlight
              SkeletonBox(width: double.infinity, height: 66, borderRadius: 16),
              const SizedBox(height: 14),
              // Quick KPI strip — 4 colunas centradas
              Row(
                children: [
                  for (var i = 0; i < 4; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        children: const [
                          SkeletonText(width: 46, height: 20, borderRadius: 6),
                          SizedBox(height: 7),
                          SkeletonText(width: 52, height: 9),
                          SizedBox(height: 8),
                          SkeletonBox(width: 18, height: 2, borderRadius: 2),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              // Chips de período + tag de cidades
              Row(
                children: [
                  SkeletonBox(width: 66, height: 33, borderRadius: 999),
                  const SizedBox(width: 8),
                  SkeletonBox(width: 80, height: 33, borderRadius: 999),
                  const SizedBox(width: 8),
                  SkeletonBox(width: 74, height: 33, borderRadius: 999),
                  const Spacer(),
                  SkeletonBox(width: 96, height: 33, borderRadius: 999),
                ],
              ),
              const SizedBox(height: _kPanelGap),
              // Painel mídia paga: hero financeiro + compare rows + rail
              panelHeader(titleW: 120),
              const SizedBox(height: 14),
              const SkeletonText(width: 148, height: 10),
              const SizedBox(height: 10),
              const SkeletonText(width: 210, height: 30, borderRadius: 8),
              const SizedBox(height: 14),
              Row(
                children: [
                  const SkeletonText(width: 56, height: 11),
                  const SizedBox(width: 10),
                  Expanded(child: SkeletonBox(height: 10, borderRadius: 99)),
                  const SizedBox(width: 10),
                  const SkeletonText(width: 70, height: 12),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const SkeletonText(width: 56, height: 11),
                  const SizedBox(width: 10),
                  Expanded(child: SkeletonBox(height: 10, borderRadius: 99)),
                  const SizedBox(width: 10),
                  const SkeletonText(width: 70, height: 12),
                ],
              ),
              const SizedBox(height: 16),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: SkeletonBox(height: 96, borderRadius: 16)),
                    const SizedBox(width: 10),
                    Expanded(child: SkeletonBox(height: 96, borderRadius: 16)),
                    const SizedBox(width: 10),
                    Expanded(child: SkeletonBox(height: 96, borderRadius: 16)),
                  ],
                ),
              ),
              const SizedBox(height: _kPanelGap),
              // Painel canais: faixa + legenda em 2 colunas
              panelHeader(titleW: 190),
              const SizedBox(height: 14),
              SkeletonBox(width: double.infinity, height: 18, borderRadius: 99),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: const [
                        SkeletonBox(
                            width: double.infinity,
                            height: 36,
                            borderRadius: 12),
                        SizedBox(height: 8),
                        SkeletonBox(
                            width: double.infinity,
                            height: 36,
                            borderRadius: 12),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      children: const [
                        SkeletonBox(
                            width: double.infinity,
                            height: 36,
                            borderRadius: 12),
                        SizedBox(height: 8),
                        SkeletonBox(
                            width: double.infinity,
                            height: 36,
                            borderRadius: 12),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: _kPanelGap),
              // Painel ritmo: gráfico de barras
              panelHeader(titleW: 130, trailing: false),
              const SizedBox(height: 14),
              SkeletonBox(
                  width: double.infinity, height: 110, borderRadius: 12),
            ],
          ),
        ),
      ],
    );
  }
}

/// Pintor do anel fino dos medidores de conversão — círculo completo com
/// track sutil, arco em sweep gradient a partir do topo e "led" com halo na
/// ponta (progresso relativo ao benchmark de 10%).
class _RingMeterPainter extends CustomPainter {
  final double progress; // 0..1
  final Color color;
  final Color trackColor;

  _RingMeterPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 3.4;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - strokeWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    final p = progress.clamp(0.0, 1.0);
    if (p > 0.004) {
      const start = -math.pi / 2;
      final sweep = math.pi * 2 * p;
      final progressPaint = Paint()
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: math.max(sweep, 0.12),
          transform: const GradientRotation(start),
          colors: [color.withValues(alpha: 0.45), color],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, start, sweep, false, progressPaint);

      final endAngle = start + sweep;
      final tip = Offset(
        center.dx + radius * math.cos(endAngle),
        center.dy + radius * math.sin(endAngle),
      );
      canvas.drawCircle(
        tip,
        strokeWidth * 1.5,
        Paint()..color = color.withValues(alpha: 0.18),
      );
      canvas.drawCircle(tip, strokeWidth * 0.62, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _RingMeterPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor;
}

/// Gatilho de filtros da toolbar — pill com rótulo, contador de dimensões
/// ativas e feedback de toque (escala + haptic + tint), vivendo dentro da
/// cápsula de ações do chrome.
class _FilterTriggerButton extends StatefulWidget {
  const _FilterTriggerButton({
    required this.activeCount,
    required this.onPressed,
  });

  final int activeCount;
  final VoidCallback onPressed;

  @override
  State<_FilterTriggerButton> createState() => _FilterTriggerButtonState();
}

class _FilterTriggerButtonState extends State<_FilterTriggerButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = AnalyticsTones.accent(context);
    final active = widget.activeCount > 0;
    final fg = active
        ? accent
        : ThemeHelpers.textColor(context).withValues(alpha: 0.88);

    return Tooltip(
      message: active
          ? 'Filtros · ${widget.activeCount} ativo${widget.activeCount == 1 ? '' : 's'}'
          : 'Filtros',
      child: AnimatedScale(
        scale: _pressed ? 0.93 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onPressed();
            },
            onTapDown: (_) => setState(() => _pressed = true),
            onTapCancel: () => setState(() => _pressed = false),
            onTapUp: (_) => setState(() => _pressed = false),
            customBorder: const StadiumBorder(),
            splashColor: accent.withValues(alpha: 0.14),
            highlightColor: accent.withValues(alpha: 0.07),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: active
                    ? accent.withValues(alpha: isDark ? 0.18 : 0.10)
                    : Colors.transparent,
                border: Border.all(
                  color: active
                      ? accent.withValues(alpha: isDark ? 0.55 : 0.45)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.slidersHorizontal, size: 16, color: fg),
                  const SizedBox(width: 7),
                  Text(
                    'Filtros',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                      letterSpacing: -0.1,
                      height: 1,
                    ),
                  ),
                  if (active) ...[
                    const SizedBox(width: 7),
                    Container(
                      constraints: const BoxConstraints(minWidth: 17),
                      height: 17,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        gradient: LinearGradient(
                          colors: [
                            accent,
                            accent.withValues(alpha: 0.78),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(
                                alpha: isDark ? 0.45 : 0.28),
                            blurRadius: 7,
                            offset: const Offset(0, 2),
                            spreadRadius: -1,
                          ),
                        ],
                      ),
                      child: Text(
                        '${widget.activeCount}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                          height: 1,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ).animate().scale(
                          begin: const Offset(0.6, 0.6),
                          end: const Offset(1, 1),
                          duration: 220.ms,
                          curve: Curves.easeOutBack,
                        ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
