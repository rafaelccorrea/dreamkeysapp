import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_permissions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/sale_form_overview_service.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../sale_forms_overview_filters.dart';
import '../widgets/fichas_filters_kit.dart';
import '../widgets/sale_forms_dashboard_charts.dart';
import '../widgets/sale_forms_drill_down_sheet.dart';
import '../widgets/sale_forms_overview_filters_sheet.dart';

final NumberFormat _compactBrl = NumberFormat.compactCurrency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 1,
);
final NumberFormat _fullBrl = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 0,
);
final NumberFormat _intFmt = NumberFormat.decimalPattern('pt_BR');

/// Cores dos status (`STATUS_COLORS` do web).
const Map<String, Color> _kStatusColors = {
  'finalized': Color(0xFF10B981),
  'waiting_for_signature': Color(0xFFF59E0B),
  'processing': Color(0xFF3B82F6),
  'canceled': Color(0xFFEF4444),
};

/// Dashboard de Fichas de Venda — porta o "Painel enxuto" do web
/// (`SaleFormsDashboardPage.tsx`, `/sistema/fichas-venda/painel`): filtros
/// de período/corretor/equipe/unidade/status guardados no aparelho, KPIs com
/// deltas, donut de status, evolução VGV × VGC × finalizadas, rankings e a
/// seção por unidade. KPIs, fatias, linhas de ranking e "Compartilhadas"
/// abrem a lista de fichas do recorte (`FichasListDrawer` do web).
class SaleFormsDashboardPage extends StatefulWidget {
  const SaleFormsDashboardPage({super.key});

  @override
  State<SaleFormsDashboardPage> createState() => _SaleFormsDashboardPageState();
}

class _SaleFormsDashboardPageState extends State<SaleFormsDashboardPage> {
  static const double _padH = 16;

  SaleFormsOverview? _overview;
  bool _loading = true;
  String? _error;
  int _errorStatus = 0;
  int _loadSeq = 0;

  /// Filtros na tela (D-3: mês corrente por padrão; D-4: guardados).
  SaleFormsOverviewFilters _filters = overviewCurrentMonthDefault(
    DateTime.now(),
  );

  /// Filtros do overview exibido — base do drill-down (`loadedFilters`).
  SaleFormsOverviewFilters? _loadedFilters;

  List<SaleFormsOverviewPickOption> _users = const [];
  List<SaleFormsOverviewPickOption> _teams = const [];
  List<SaleFormsOverviewPickOption> _units = const [];
  SaleFormsOverviewScopeUi _scopeBoot = SaleFormsOverviewScopeUi.defaults;
  bool _optionsLoaded = false;

  int _rankingTab = 0; // 0=corretores 1=equipes

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Color get _accent => Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;

  Color get _green => Theme.of(context).brightness == Brightness.dark
      ? AppColors.status.greenDarkMode
      : AppColors.status.green;

  Color get _amber => Theme.of(context).brightness == Brightness.dark
      ? AppColors.status.warningDarkMode
      : AppColors.status.warning;

  Color get _red => Theme.of(context).brightness == Brightness.dark
      ? AppColors.status.errorDarkMode
      : AppColors.status.error;

  Color get _info => Theme.of(context).brightness == Brightness.dark
      ? AppColors.status.infoDarkMode
      : AppColors.status.info;

  // ─── Dados ─────────────────────────────────────────────────────────────

  Future<void> _bootstrap() async {
    final stored = await SaleFormsOverviewFiltersStore.instance.read();
    if (!mounted) return;
    setState(() => _filters = stored);
    _load();
    _loadOptions();
  }

  /// Escopo efetivo (`resolveEffectiveScopeUi`): papel + nº de opções.
  /// Antes das opções chegarem, vale o escopo cru (não esconde à toa).
  SaleFormsOverviewScopeUi get _scope {
    final raw = _overview?.scopeUi ?? _scopeBoot;
    if (!_optionsLoaded) return raw;
    return resolveOverviewEffectiveScope(
      raw,
      users: _users.length,
      teams: _teams.length,
      units: _units.length,
    );
  }

  Future<void> _loadOptions() async {
    final svc = SaleFormOverviewService.instance;
    final results = await Future.wait([
      svc.getAvailableUsers(),
      svc.getAvailableTeams(),
      svc.getAvailableUnits(),
    ]);
    final scopeRes = await svc.getScopeUi();
    if (!mounted) return;
    // Silencioso como no web: sem opções, os campos ficam vazios.
    if (results.any((r) => !r.success) || !scopeRes.success) return;
    setState(() {
      _users = results[0].data ?? const [];
      _teams = results[1].data ?? const [];
      _units = results[2].data ?? const [];
      _scopeBoot = scopeRes.data ?? SaleFormsOverviewScopeUi.defaults;
      _optionsLoaded = true;
    });
    final effective = resolveOverviewEffectiveScope(
      _scopeBoot,
      users: _users.length,
      teams: _teams.length,
      units: _units.length,
    );
    _setFilters(
      pruneOverviewFiltersToScope(
        _filters,
        users: _users,
        teams: _teams,
        units: _units,
        scope: effective,
      ),
    );
  }

  void _setFilters(SaleFormsOverviewFilters next) {
    if (next == _filters) return;
    setState(() => _filters = next);
    SaleFormsOverviewFiltersStore.instance.save(next);
    _load();
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    final req = _filters;
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await SaleFormOverviewService.instance.getOverview(req);
    if (!mounted || seq != _loadSeq) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _overview = res.data;
        _loadedFilters = req;
        _error = null;
        _errorStatus = 0;
        final visible = _visibleRankingTabs(_scope);
        if (visible.isNotEmpty && !visible.any((t) => t.$1 == _rankingTab)) {
          _rankingTab = visible.first.$1;
        }
      } else {
        _error = res.message ?? 'Erro ao carregar o painel';
        _errorStatus = res.statusCode;
      }
    });
    if (_overview != null && _error != null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Erro ao carregar o painel de fichas de venda'),
        ),
      );
    }
  }

  Future<void> _openFilters() async {
    final next = await showSaleFormsOverviewFiltersSheet(
      context,
      value: _filters,
      users: _users,
      teams: _teams,
      units: _units,
      scope: _scope,
    );
    if (next != null && mounted) _setFilters(next);
  }

  List<(int, String)> _visibleRankingTabs(SaleFormsOverviewScopeUi ui) => [
    if (ui.showBrokerRanking) (0, 'Corretores'),
    if (ui.showTeamRanking) (1, 'Equipes'),
  ];

  // ─── Drill-down (D-2) ──────────────────────────────────────────────────

  /// Só quando o painel exibido corresponde aos filtros atuais.
  bool get _drillReady =>
      !_loading && _loadedFilters != null && _loadedFilters == _filters;

  String? get _rangeLabel => formatOverviewRangeLabel(_filters);

  void _openDrill({
    required String title,
    String? subtitle,
    OverviewDrillDimension dimension = const OverviewDrillDimension(),
  }) {
    if (!_drillReady) return;
    showSaleFormsDrillDownSheet(
      context,
      title: title,
      subtitle: subtitle,
      filters: buildOverviewDrillFilters(_loadedFilters!, dimension),
    );
  }

  void _openStatusDrill(String key, String title) {
    final status = overviewStatusFromKey(key);
    if (status == null) return;
    _openDrill(
      title: title,
      subtitle: _rangeLabel,
      dimension: overviewStatusDrill(
        status,
        canViewAll: ModuleAccessService.instance.hasPermission(
          AppPermissions.saleFormViewAll,
        ),
      ),
    );
  }

  void _openRankingDrill(SaleFormsOverviewRankingItem row, int kind) {
    if (row.key.isEmpty) return;
    final r = _rangeLabel;
    _openDrill(
      title: row.label,
      subtitle: r != null
          ? 'Fichas · $r'
          : switch (kind) {
              0 => 'Fichas do corretor',
              1 => 'Fichas da equipe',
              _ => 'Fichas da unidade',
            },
      dimension: switch (kind) {
        0 => OverviewDrillDimension(userIds: [row.key]),
        1 => OverviewDrillDimension(teamIds: [row.key]),
        _ => OverviewDrillDimension(unitIds: [row.key]),
      },
    );
  }

  void _openSharedDrill() {
    final r = _rangeLabel;
    _openDrill(
      title: 'Fichas compartilhadas',
      subtitle: r != null
          ? 'Compartilhadas entre unidades · $r'
          : 'Compartilhadas entre unidades',
      dimension: const OverviewDrillDimension(sharedOnly: true),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final o = _overview;
    return AppScaffold(
      title: 'Dashboard de Fichas',
      showBottomNavigation: false,
      actions: [
        IconButton(
          tooltip: 'Atualizar',
          onPressed: _loading ? null : _load,
          icon: const Icon(LucideIcons.refreshCw, size: 18),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: _load,
        color: _accent,
        child: o == null
            ? (_loading
                  ? _buildSkeleton()
                  : _error != null
                  ? _buildError()
                  : _buildSkeleton())
            : _buildContent(o),
      ),
    );
  }

  Widget _buildError() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(_padH, 14, _padH, 40),
      children: [
        _buildFilterBar(),
        const SizedBox(height: 40),
        AppErrorState.fromApi(
          message: _error,
          statusCode: _errorStatus,
          onRetry: _load,
          dense: true,
        ),
      ],
    );
  }

  Widget _buildSkeleton() {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(_padH, 14, _padH, 40),
      children: [
        const SkeletonBox(height: 104, borderRadius: 18),
        const SizedBox(height: 16),
        Row(
          children: const [
            Expanded(child: SkeletonBox(height: 108, borderRadius: 16)),
            SizedBox(width: 10),
            Expanded(child: SkeletonBox(height: 108, borderRadius: 16)),
          ],
        ),
        const SizedBox(height: 10),
        const SkeletonBox(height: 64, borderRadius: 14),
        const SizedBox(height: 16),
        const SkeletonBox(height: 260, borderRadius: 18),
        const SizedBox(height: 16),
        const SkeletonBox(height: 220, borderRadius: 18),
      ],
    );
  }

  Widget _buildContent(SaleFormsOverview o) {
    final scope = _scope;
    final labels = resolveOverviewMetricLabels(
      _loadedFilters?.status.isNotEmpty == true
          ? _loadedFilters!.status
          : _filters.status,
    );
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(_padH, 14, _padH, 40),
      children: [
        _buildFilterBar(),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          child: _loading
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      color: _accent,
                      backgroundColor: _accent.withValues(alpha: 0.12),
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: 16),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _loading ? 0.55 : 1,
          child: IgnorePointer(
            ignoring: _loading,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _sections(o, scope, labels),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _sections(
    SaleFormsOverview o,
    SaleFormsOverviewScopeUi scope,
    ({
      String vgvTitle,
      String vgcTitle,
      String rankingVgvSubtitle,
      bool showConversion,
      bool valuesScoped,
    })
    labels,
  ) {
    final rankingTabs = _visibleRankingTabs(scope);
    return [
      _buildHeadlineKpis(o, labels),
      const SizedBox(height: 10),
      _buildCountsRow(o),
      const SizedBox(height: 18),
      _sectionHeader(
        icon: LucideIcons.chartPie,
        title: 'Status das fichas',
        hint: 'toque para ver a lista',
      ),
      const SizedBox(height: 10),
      OverviewDonutCard(
        title: 'Distribuição no período',
        subtitle: _rangeLabel ?? 'Período selecionado',
        slices: [
          for (final s in o.porStatus)
            OverviewDonutSlice(
              key: s.key,
              label: s.label,
              value: s.total.toDouble(),
              color: _kStatusColors[s.key] ?? _accent,
            ),
        ],
        centerLabel: 'geradas',
        centerValue: _intFmt.format(o.kpis.totalGeradas),
        formatValue: (v) => _intFmt.format(v.round()),
        emptyText: 'Sem fichas no período selecionado.',
        onSliceTap: _drillReady
            ? (s) => _openStatusDrill(s.key, s.label)
            : null,
      ),
      const SizedBox(height: 18),
      _sectionHeader(
        icon: LucideIcons.trendingUp,
        title: 'Evolução de VGV e VGC',
        hint: 'por ${_granularityLabel()}',
      ),
      const SizedBox(height: 10),
      OverviewTimeseriesCard(
        points: o.timeseries,
        periodLabel: _granularityLabel(),
      ),
      if (rankingTabs.isNotEmpty) ...[
        const SizedBox(height: 18),
        _sectionHeader(
          icon: LucideIcons.trophy,
          title: 'Ranking por VGV e VGC',
        ),
        const SizedBox(height: 4),
        _buildRankingTabs(rankingTabs),
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 8),
          child: Text(
            _rankingTab == 1
                ? 'Equipe principal do corretor (sem double-count)'
                : labels.rankingVgvSubtitle,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
        ),
        _buildRankingList(
          _rankingTab == 1 ? o.rankingEquipes : o.rankingCorretores,
          kind: _rankingTab,
          emptyText: _rankingTab == 1
              ? 'Nenhuma equipe no recorte.'
              : 'Nenhum corretor no recorte.',
        ),
      ],
      if (scope.showUnitSection) ...[
        const SizedBox(height: 22),
        _sectionHeader(icon: LucideIcons.house, title: 'Por unidade (filial)'),
        const SizedBox(height: 10),
        _buildSharedCards(o.kpisCompartilhadas, labels.valuesScoped),
        const SizedBox(height: 12),
        OverviewDonutCard(
          title: 'VGV por unidade',
          subtitle: labels.valuesScoped
              ? 'Participação de cada unidade no VGV do recorte'
              : 'Participação de cada unidade no VGV finalizado',
          slices: [
            for (var i = 0; i < o.rankingUnidades.length; i++)
              if (o.rankingUnidades[i].vgv > 0)
                OverviewDonutSlice(
                  key: o.rankingUnidades[i].key,
                  label: o.rankingUnidades[i].label,
                  value: o.rankingUnidades[i].vgv,
                  color:
                      kOverviewDonutPalette[i % kOverviewDonutPalette.length],
                ),
          ],
          centerLabel: 'VGV',
          centerValue: _compactBrl.format(o.kpis.vgv),
          formatValue: _compactBrl.format,
          emptyText: 'Sem VGV por unidade no recorte.',
          onSliceTap: _drillReady
              ? (s) => _openRankingDrill(
                  o.rankingUnidades.firstWhere((u) => u.key == s.key),
                  2,
                )
              : null,
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            'Ranking por unidade · ${labels.rankingVgvSubtitle.toLowerCase()}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
        ),
        _buildRankingList(
          o.rankingUnidades,
          kind: 2,
          emptyText: 'Nenhuma unidade no recorte.',
        ),
      ],
    ];
  }

  String _granularityLabel() {
    switch ((_loadedFilters ?? _filters).granularity) {
      case 'month':
        return 'mês';
      case 'week':
        return 'semana';
      default:
        return 'dia';
    }
  }

  // ─── Filtros (D-1 / D-3) ───────────────────────────────────────────────

  Widget _buildFilterBar() {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final now = DateTime.now();
    final presetId = resolveOverviewPresetId(_filters, now);
    final active = <String>[
      if (_filters.userIds.isNotEmpty)
        _filters.userIds.length == 1
            ? (_users
                      .where((u) => u.id == _filters.userIds.first)
                      .map((u) => u.label)
                      .firstOrNull ??
                  '1 corretor')
            : '${_filters.userIds.length} corretores',
      if (_filters.teamIds.isNotEmpty)
        '${_filters.teamIds.length} equipe${_filters.teamIds.length == 1 ? '' : 's'}',
      if (_filters.unitIds.isNotEmpty)
        '${_filters.unitIds.length} unidade${_filters.unitIds.length == 1 ? '' : 's'}',
      for (final s in _filters.status)
        kOverviewStatusOptions
                .where((o) => o.value == s)
                .map((o) => o.label)
                .firstOrNull ??
            s,
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(18),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _openFilters,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: _accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(
                            LucideIcons.calendarRange,
                            size: 18,
                            color: _accent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'PERÍODO',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                  color: secondary,
                                ),
                              ),
                              Text(
                                _rangeLabel ?? 'Selecione o período',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                  color: ThemeHelpers.textColor(context),
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
              const SizedBox(width: 8),
              FichasFiltersButton(
                count: _filters.dimensionCount,
                onTap: _openFilters,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final p in kOverviewPresets)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _presetChip(p, presetId == p.id, now),
                  ),
              ],
            ),
          ),
          if (active.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in active)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: _accent.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      a,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _accent,
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

  Widget _presetChip(OverviewPreset p, bool active, DateTime now) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return GestureDetector(
      onTap: () => _setFilters(applyOverviewPreset(_filters, p, now)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? _accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? _accent
                : ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
          ),
        ),
        child: Text(
          p.label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : secondary,
            letterSpacing: -0.1,
          ),
        ),
      ),
    );
  }

  // ─── KPIs ──────────────────────────────────────────────────────────────

  Widget _delta(double? value) {
    if (value == null) return const SizedBox.shrink();
    final up = value >= 0;
    final color = up ? _green : _red;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          up ? LucideIcons.trendingUp : LucideIcons.trendingDown,
          size: 12,
          color: color,
        ),
        const SizedBox(width: 3),
        Text(
          '${value.abs().toStringAsFixed(0)}%',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _kpiCard({
    required IconData icon,
    required Color tone,
    required String label,
    required String value,
    Widget? trailing,
    String? sub,
    VoidCallback? onTap,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: tone.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(icon, size: 15, color: tone),
                    ),
                    const Spacer(),
                    ?trailing,
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub == null ? label : '$label · $sub',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeadlineKpis(
    SaleFormsOverview o,
    ({
      String vgvTitle,
      String vgcTitle,
      String rankingVgvSubtitle,
      bool showConversion,
      bool valuesScoped,
    })
    labels,
  ) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _kpiCard(
                icon: LucideIcons.landmark,
                tone: _accent,
                label: labels.vgvTitle,
                value: _compactBrl.format(o.kpis.vgv),
                trailing: _delta(o.deltas.vgv),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _kpiCard(
                icon: LucideIcons.wallet,
                tone: _green,
                label: labels.vgcTitle,
                value: _compactBrl.format(o.kpis.vgc),
                trailing: _delta(o.deltas.vgc),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _kpiCard(
                icon: LucideIcons.receipt,
                tone: _amber,
                label: 'Ticket médio',
                value: _fullBrl.format(o.kpis.ticketMedio),
              ),
            ),
            if (labels.showConversion) ...[
              const SizedBox(width: 10),
              Expanded(
                child: _kpiCard(
                  icon: LucideIcons.percent,
                  tone: _green,
                  label: 'Conversão',
                  sub: 'finalizadas ÷ geradas',
                  value:
                      '${o.kpis.taxaConversao.toStringAsFixed(1).replaceAll('.', ',')}%',
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _countPill({
    required String label,
    required int value,
    required Color tone,
    double? delta,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: BorderRadius.circular(14),
          boxShadow: ThemeHelpers.cardShadow(context),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Column(
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _intFmt.format(value),
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                            color: tone,
                          ),
                        ),
                        if (delta != null) ...[
                          const SizedBox(width: 5),
                          _delta(delta),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCountsRow(SaleFormsOverview o) {
    // Com filtro de status, os cards seguem o recorte (igual ao web).
    final st = _filters.status;
    final showAll = st.isEmpty;
    final showWaiting =
        showAll ||
        st.contains('waiting_for_signature') ||
        st.contains('processing');
    return Row(
      children: [
        _countPill(
          label: 'Geradas',
          value: o.kpis.totalGeradas,
          tone: _accent,
          delta: o.deltas.totalGeradas,
          onTap: () =>
              _openDrill(title: 'Fichas geradas', subtitle: _rangeLabel),
        ),
        const SizedBox(width: 8),
        _countPill(
          label: 'Finalizadas',
          value: o.kpis.finalizadas,
          tone: _green,
          delta: o.deltas.finalizadas,
          onTap: () => _openStatusDrill('finalized', 'Fichas finalizadas'),
        ),
        if (showWaiting) ...[
          const SizedBox(width: 8),
          _countPill(
            label: 'Aguardando',
            value: o.kpis.aguardandoAssinatura,
            tone: _amber,
            onTap: () => _openStatusDrill(
              'waiting_for_signature',
              'Aguardando assinatura',
            ),
          ),
        ],
        if (showAll) ...[
          const SizedBox(width: 8),
          _countPill(
            label: 'Canceladas',
            value: o.kpis.canceladas,
            tone: _red,
            onTap: () => _openStatusDrill('canceled', 'Fichas canceladas'),
          ),
        ],
      ],
    );
  }

  // ─── Seções ────────────────────────────────────────────────────────────

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    String? hint,
  }) {
    return Row(
      children: [
        Icon(icon, size: 15, color: _accent),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            title.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: ThemeHelpers.textColor(context),
            ),
          ),
        ),
        if (hint != null) ...[
          const SizedBox(width: 8),
          const Spacer(),
          Text(
            hint,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
        ],
      ],
    );
  }

  /// D-6: sempre visível na seção por unidade, mesmo com 0 (web).
  Widget _buildSharedCards(SaleFormsOverviewSharedKpis s, bool scoped) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _kpiCard(
            icon: LucideIcons.share2,
            tone: _info,
            label: 'Compartilhadas',
            value: _intFmt.format(s.total),
            sub: s.total > 0
                ? '${_intFmt.format(s.finalizadas)} finalizadas'
                : 'nenhuma no recorte',
            onTap: _openSharedDrill,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _kpiCard(
            icon: LucideIcons.trendingUp,
            tone: _info,
            label: 'VGV compartilhadas',
            value: _compactBrl.format(s.vgv),
            sub: s.vgv > 0
                ? 'VGC ${_compactBrl.format(s.vgc)}'
                : scoped
                ? 'sem VGV no recorte filtrado'
                : 'sem VGV finalizado',
            onTap: _openSharedDrill,
          ),
        ),
      ],
    );
  }

  // ─── Rankings ──────────────────────────────────────────────────────────

  Widget _buildRankingTabs(List<(int, String)> tabs) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Row(
      children: [
        for (final (index, label) in tabs)
          GestureDetector(
            onTap: () => setState(() => _rankingTab = index),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              margin: const EdgeInsets.only(right: 18),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    width: 2.5,
                    color: _rankingTab == index ? _accent : Colors.transparent,
                  ),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  color: _rankingTab == index
                      ? ThemeHelpers.textColor(context)
                      : secondary,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRankingList(
    List<SaleFormsOverviewRankingItem> items, {
    required int kind,
    required String emptyText,
  }) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: BorderRadius.circular(16),
          boxShadow: ThemeHelpers.cardShadow(context),
        ),
        child: Center(
          child: Text(
            emptyText,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: secondary,
            ),
          ),
        ),
      );
    }
    final maxVgv = items.fold<double>(0, (m, i) => i.vgv > m ? i.vgv : m);
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: 8,
                endIndent: 8,
                color: ThemeHelpers.borderLightColor(
                  context,
                ).withValues(alpha: 0.4),
              ),
            _rankingRow(i + 1, items[i], maxVgv, kind),
          ],
        ],
      ),
    );
  }

  Widget _rankingRow(
    int position,
    SaleFormsOverviewRankingItem item,
    double maxVgv,
    int kind,
  ) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final isTop = position == 1;
    final medal = position <= 3;
    final medalColor = switch (position) {
      1 => const Color(0xFFD4A017),
      2 => const Color(0xFF9AA4B2),
      3 => const Color(0xFFB0714D),
      _ => secondary,
    };
    final tappable = item.key.isNotEmpty && _drillReady;
    return InkWell(
      onTap: tappable ? () => _openRankingDrill(item, kind) : null,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 6, 10),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: medal
                  ? Icon(LucideIcons.medal, size: 17, color: medalColor)
                  : Text(
                      '$position°',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: secondary,
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: isTop ? FontWeight.w800 : FontWeight.w700,
                      letterSpacing: -0.2,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: SizedBox(
                      height: 5,
                      child: Stack(
                        children: [
                          Container(
                            color: ThemeHelpers.borderColor(
                              context,
                            ).withValues(alpha: 0.25),
                          ),
                          FractionallySizedBox(
                            widthFactor: maxVgv == 0 ? 0 : (item.vgv / maxVgv),
                            child: Container(
                              color: isTop
                                  ? _accent
                                  : _accent.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.finalizadas}/${item.total} finalizadas · '
                    '${item.taxaConversao.toStringAsFixed(0)}% conversão',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: secondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _compactBrl.format(item.vgv),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: isTop ? _accent : ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'VGC ${_compactBrl.format(item.vgc)}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: secondary,
                  ),
                ),
              ],
            ),
            if (tappable) ...[
              const SizedBox(width: 4),
              Icon(LucideIcons.chevronRight, size: 16, color: secondary),
            ],
          ],
        ),
      ),
    );
  }
}
