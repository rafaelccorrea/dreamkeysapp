import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/sale_form_overview_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';

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

/// Períodos rápidos do painel (paridade com os chips do web).
enum _Period { today, d7, d30, d90, year, custom }

extension _PeriodX on _Period {
  String get label {
    switch (this) {
      case _Period.today:
        return 'Hoje';
      case _Period.d7:
        return '7d';
      case _Period.d30:
        return '30d';
      case _Period.d90:
        return '90d';
      case _Period.year:
        return '1 ano';
      case _Period.custom:
        return 'Personalizado';
    }
  }
}

/// Dashboard de Fichas de Venda — porta o "Painel enxuto" do web
/// (`/fichas-venda/painel`): KPIs com deltas, VGV/VGC, distribuição por
/// status, evolução no período e rankings por corretor/equipe/unidade
/// (o backend decide o escopo visível via `scopeUi`).
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

  _Period _period = _Period.d30;
  DateTimeRange? _customRange;

  int _rankingTab = 0; // 0=corretores 1=equipes 2=unidades

  @override
  void initState() {
    super.initState();
    _load();
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

  // ─── Dados ─────────────────────────────────────────────────────────────

  ({String from, String to, String granularity}) _rangeFor(_Period p) {
    final now = DateTime.now();
    final fmt = DateFormat('yyyy-MM-dd');
    DateTime from;
    String granularity = 'day';
    switch (p) {
      case _Period.today:
        from = DateTime(now.year, now.month, now.day);
        break;
      case _Period.d7:
        from = now.subtract(const Duration(days: 7));
        break;
      case _Period.d30:
        from = now.subtract(const Duration(days: 30));
        break;
      case _Period.d90:
        from = now.subtract(const Duration(days: 90));
        granularity = 'week';
        break;
      case _Period.year:
        from = now.subtract(const Duration(days: 365));
        granularity = 'month';
        break;
      case _Period.custom:
        final r = _customRange;
        if (r == null) {
          from = now.subtract(const Duration(days: 30));
        } else {
          final days = r.duration.inDays;
          granularity = days > 180
              ? 'month'
              : days > 60
                  ? 'week'
                  : 'day';
          return (
            from: fmt.format(r.start),
            to: fmt.format(r.end),
            granularity: granularity,
          );
        }
        break;
    }
    return (from: fmt.format(from), to: fmt.format(now), granularity: granularity);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final range = _rangeFor(_period);
    final res = await SaleFormOverviewService.instance.getOverview(
      dateFrom: range.from,
      dateTo: range.to,
      granularity: range.granularity,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _overview = res.data;
        // Se o escopo esconder o ranking ativo, volta para o primeiro visível.
        final ui = res.data!.scopeUi;
        final visible = _visibleRankingTabs(ui);
        if (visible.isNotEmpty && !visible.any((t) => t.$1 == _rankingTab)) {
          _rankingTab = visible.first.$1;
        }
      } else {
        _error = res.message ?? 'Erro ao carregar o painel';
      }
    });
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: _customRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 30)),
            end: now,
          ),
      locale: const Locale('pt', 'BR'),
    );
    if (picked == null) return;
    setState(() {
      _customRange = picked;
      _period = _Period.custom;
    });
    _load();
  }

  List<(int, String)> _visibleRankingTabs(SaleFormsOverviewScopeUi ui) => [
        if (ui.showBrokerRanking) (0, 'Corretores'),
        if (ui.showTeamRanking) (1, 'Equipes'),
        if (ui.showUnitSection) (2, 'Unidades'),
      ];

  // ─── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
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
        child: _loading
            ? _buildSkeleton()
            : _error != null
                ? _buildError()
                : _buildContent(),
      ),
    );
  }

  Widget _buildError() {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(_padH, 80, _padH, 40),
      children: [
        Icon(LucideIcons.cloudOff, size: 40, color: secondary),
        const SizedBox(height: 14),
        Text(
          _error ?? 'Erro ao carregar o painel',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: secondary,
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: FilledButton.tonalIcon(
            onPressed: _load,
            icon: const Icon(LucideIcons.rotateCcw, size: 16),
            label: const Text('Tentar novamente'),
          ),
        ),
      ],
    );
  }

  Widget _buildSkeleton() {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(_padH, 14, _padH, 40),
      children: [
        const SkeletonBox(height: 34, borderRadius: 17),
        const SizedBox(height: 16),
        Row(
          children: const [
            Expanded(child: SkeletonBox(height: 108, borderRadius: 16)),
            SizedBox(width: 10),
            Expanded(child: SkeletonBox(height: 108, borderRadius: 16)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: const [
            Expanded(child: SkeletonBox(height: 84, borderRadius: 16)),
            SizedBox(width: 10),
            Expanded(child: SkeletonBox(height: 84, borderRadius: 16)),
          ],
        ),
        const SizedBox(height: 16),
        const SkeletonBox(height: 160, borderRadius: 16),
        const SizedBox(height: 16),
        const SkeletonBox(height: 220, borderRadius: 16),
      ],
    );
  }

  Widget _buildContent() {
    final o = _overview!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(_padH, 14, _padH, 40),
      children: [
        _buildPeriodChips(),
        const SizedBox(height: 16),
        _buildHeadlineKpis(o),
        const SizedBox(height: 10),
        _buildCountsRow(o),
        const SizedBox(height: 18),
        _sectionHeader(
          icon: LucideIcons.chartPie,
          title: 'Distribuição por status',
          hint: '${_intFmt.format(o.kpis.totalGeradas)} fichas no período',
        ),
        const SizedBox(height: 10),
        _buildStatusDistribution(o),
        const SizedBox(height: 18),
        if (o.timeseries.isNotEmpty) ...[
          _sectionHeader(
            icon: LucideIcons.chartColumn,
            title: 'Evolução no período',
            hint: 'VGV por ${_granularityLabel()}',
          ),
          const SizedBox(height: 10),
          _buildTimeseries(o),
          const SizedBox(height: 18),
        ],
        if (o.kpisCompartilhadas.total > 0) ...[
          _buildSharedCard(o.kpisCompartilhadas),
          const SizedBox(height: 18),
        ],
        if (_visibleRankingTabs(o.scopeUi).isNotEmpty) ...[
          _sectionHeader(
            icon: LucideIcons.trophy,
            title: 'Rankings',
            hint: 'por VGV no período',
          ),
          const SizedBox(height: 4),
          _buildRankingTabs(o),
          const SizedBox(height: 10),
          _buildRankingList(o),
        ],
      ],
    );
  }

  String _granularityLabel() {
    switch (_rangeFor(_period).granularity) {
      case 'month':
        return 'mês';
      case 'week':
        return 'semana';
      default:
        return 'dia';
    }
  }

  // ─── Período ───────────────────────────────────────────────────────────

  Widget _buildPeriodChips() {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _Period.values.map((p) {
          final active = _period == p;
          String label = p.label;
          if (p == _Period.custom && _customRange != null) {
            final f = DateFormat('dd/MM');
            label =
                '${f.format(_customRange!.start)} – ${f.format(_customRange!.end)}';
          }
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                if (p == _Period.custom) {
                  _pickCustomRange();
                  return;
                }
                if (_period == p) return;
                setState(() => _period = p);
                _load();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: active ? _accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: active
                        ? _accent
                        : ThemeHelpers.borderColor(context)
                            .withValues(alpha: 0.6),
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : secondary,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── KPIs ──────────────────────────────────────────────────────────────

  Widget _delta(double? value) {
    if (value == null) return const SizedBox.shrink();
    final up = value >= 0;
    final color = up ? _green : _accent;
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
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
            maxLines: 1,
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
    );
  }

  Widget _buildHeadlineKpis(SaleFormsOverview o) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _kpiCard(
                icon: LucideIcons.landmark,
                tone: _accent,
                label: 'VGV',
                sub: 'valor geral de vendas',
                value: _compactBrl.format(o.kpis.vgv),
                trailing: _delta(o.deltas.vgv),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _kpiCard(
                icon: LucideIcons.wallet,
                tone: _green,
                label: 'VGC',
                sub: 'comissões',
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
        ),
      ],
    );
  }

  Widget _countPill({
    required String label,
    required int value,
    required Color tone,
    double? delta,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: BorderRadius.circular(14),
          boxShadow: ThemeHelpers.cardShadow(context),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
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
            const SizedBox(height: 2),
            Text(
              label,
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
    );
  }

  Widget _buildCountsRow(SaleFormsOverview o) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Row(
      children: [
        _countPill(
          label: 'Geradas',
          value: o.kpis.totalGeradas,
          tone: ThemeHelpers.textColor(context),
          delta: o.deltas.totalGeradas,
        ),
        const SizedBox(width: 8),
        _countPill(
          label: 'Finalizadas',
          value: o.kpis.finalizadas,
          tone: _green,
          delta: o.deltas.finalizadas,
        ),
        const SizedBox(width: 8),
        _countPill(
          label: 'Aguardando',
          value: o.kpis.aguardandoAssinatura,
          tone: _amber,
        ),
        const SizedBox(width: 8),
        _countPill(
          label: 'Canceladas',
          value: o.kpis.canceladas,
          tone: secondary,
        ),
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
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
            color: ThemeHelpers.textColor(context),
          ),
        ),
        const Spacer(),
        if (hint != null)
          Text(
            hint,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
      ],
    );
  }

  Color _statusTone(String key) {
    final k = key.toLowerCase();
    if (k.contains('final')) return _green;
    if (k.contains('waiting') || k.contains('aguard')) return _amber;
    if (k.contains('cancel')) {
      return ThemeHelpers.textSecondaryColor(context);
    }
    return _accent;
  }

  Widget _buildStatusDistribution(SaleFormsOverview o) {
    final slices =
        o.porStatus.where((s) => s.total > 0).toList(growable: false);
    final total = slices.fold<int>(0, (s, e) => s + e.total);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: total == 0
          ? Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Sem fichas no período selecionado.',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
            )
          : Column(
              children: [
                // Barra 100% empilhada
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    height: 10,
                    child: Row(
                      children: [
                        for (final s in slices)
                          Expanded(
                            flex: s.total,
                            child: Container(color: _statusTone(s.key)),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 14,
                  runSpacing: 8,
                  children: [
                    for (final s in slices)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _statusTone(s.key),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${s.label} · ${_intFmt.format(s.total)}'
                              ' (${(s.total / total * 100).toStringAsFixed(0)}%)',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: ThemeHelpers.textSecondaryColor(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildTimeseries(SaleFormsOverview o) {
    final points = o.timeseries;
    final maxVgv = points.fold<double>(0, (m, p) => p.vgv > m ? p.vgv : m);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: SizedBox(
        height: 148,
        child: points.every((p) => p.vgv == 0 && p.total == 0)
            ? Center(
                child: Text(
                  'Sem movimentação no período.',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: secondary,
                  ),
                ),
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final p in points)
                    Expanded(
                      child: Tooltip(
                        message:
                            '${p.periodo}\nVGV ${_compactBrl.format(p.vgv)} · '
                            '${p.finalizadas}/${p.total} finalizadas',
                        triggerMode: TooltipTriggerMode.tap,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2.5),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (p.vgv > 0 && p.vgv == maxVgv)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    _compactBrl.format(p.vgv),
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: _accent,
                                    ),
                                  ),
                                ),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                height: maxVgv == 0
                                    ? 3
                                    : 6 + 92 * (p.vgv / maxVgv),
                                decoration: BoxDecoration(
                                  color: p.vgv == 0
                                      ? ThemeHelpers.borderColor(context)
                                          .withValues(alpha: 0.4)
                                      : _accent.withValues(
                                          alpha:
                                              p.vgv == maxVgv ? 1 : 0.55),
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(4),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _shortPeriod(p.periodo),
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                style: TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w700,
                                  color: secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  String _shortPeriod(String raw) {
    // '2026-07-01' → '01/07' · '2026-07' → 'jul' · semanas ficam como vierem.
    final day = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
    if (day != null) return '${day.group(3)}/${day.group(2)}';
    final month = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(raw);
    if (month != null) {
      final m = int.tryParse(month.group(2)!) ?? 1;
      return DateFormat.MMM('pt_BR').format(DateTime(2000, m));
    }
    return raw.length > 6 ? raw.substring(raw.length - 5) : raw;
  }

  Widget _buildSharedCard(SaleFormsOverviewSharedKpis s) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    Widget cell(String label, String value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: secondary,
                ),
              ),
            ],
          ),
        );
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
              Icon(LucideIcons.users, size: 14, color: _amber),
              const SizedBox(width: 6),
              Text(
                'FICHAS COMPARTILHADAS',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              cell('Fichas', _intFmt.format(s.total)),
              cell('Finalizadas', _intFmt.format(s.finalizadas)),
              cell('VGV', _compactBrl.format(s.vgv)),
              cell('VGC', _compactBrl.format(s.vgc)),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Rankings ──────────────────────────────────────────────────────────

  Widget _buildRankingTabs(SaleFormsOverview o) {
    final tabs = _visibleRankingTabs(o.scopeUi);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Row(
      children: [
        for (final (index, label) in tabs) ...[
          GestureDetector(
            onTap: () => setState(() => _rankingTab = index),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              margin: const EdgeInsets.only(right: 18),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    width: 2.5,
                    color:
                        _rankingTab == index ? _accent : Colors.transparent,
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
      ],
    );
  }

  List<SaleFormsOverviewRankingItem> _activeRanking(SaleFormsOverview o) {
    switch (_rankingTab) {
      case 1:
        return o.rankingEquipes;
      case 2:
        return o.rankingUnidades;
      default:
        return o.rankingCorretores;
    }
  }

  Widget _buildRankingList(SaleFormsOverview o) {
    final items = _activeRanking(o);
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
            'Sem dados de ranking no período.',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: secondary,
            ),
          ),
        ),
      );
    }
    final maxVgv =
        items.fold<double>(0, (m, i) => i.vgv > m ? i.vgv : m);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
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
                color: ThemeHelpers.borderLightColor(context)
                    .withValues(alpha: 0.4),
              ),
            _rankingRow(i + 1, items[i], maxVgv),
          ],
        ],
      ),
    );
  }

  Widget _rankingRow(
    int position,
    SaleFormsOverviewRankingItem item,
    double maxVgv,
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
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
                // Barra proporcional ao VGV do líder
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    height: 5,
                    child: Stack(
                      children: [
                        Container(
                          color: ThemeHelpers.borderColor(context)
                              .withValues(alpha: 0.25),
                        ),
                        FractionallySizedBox(
                          widthFactor:
                              maxVgv == 0 ? 0 : (item.vgv / maxVgv),
                          child: Container(
                            color:
                                isTop ? _accent : _accent.withValues(alpha: 0.5),
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
        ],
      ),
    );
  }
}
