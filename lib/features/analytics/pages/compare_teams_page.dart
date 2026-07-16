import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/utils/input_formatters.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/compare_models.dart';
import '../services/analytics_service.dart';
import '../widgets/analytics_filter_sheets.dart';
import '../widgets/analytics_ui.dart';
import '../widgets/compare_widgets.dart';

final NumberFormat _compactMoney = NumberFormat.compactCurrency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 1,
);
final NumberFormat _int = NumberFormat.decimalPattern('pt_BR');

String _pct(double v) => '${v.toStringAsFixed(1).replaceAll('.', ',')}%';

/// Comparar Equipes — seleção de 2 a 4 equipes e comparação lado a lado.
/// Paridade com `CompareTeamsPage` do imobx-front
/// (`POST /matches/performance/compare/teams`, permissão
/// `performance:compare`).
class CompareTeamsPage extends StatefulWidget {
  const CompareTeamsPage({super.key});

  @override
  State<CompareTeamsPage> createState() => _CompareTeamsPageState();
}

class _CompareTeamsPageState extends State<CompareTeamsPage> {
  static const double _kPadH = 16;
  static const double _kPadTop = 10;
  static const double _kPadBottom = 88;
  static const int _maxSelection = 4;

  List<TeamOption> _teams = const [];
  bool _teamsLoading = true;
  String? _teamsError;
  final Set<String> _selectedIds = <String>{};

  DateTime? _startDate;
  DateTime? _endDate;
  String _propertyType = 'all';
  final TextEditingController _regionController = TextEditingController();
  final TextEditingController _minPriceController = TextEditingController();
  final TextEditingController _maxPriceController = TextEditingController();

  TeamsComparison? _result;
  bool _comparing = false;
  String? _compareError;

  bool get _canCompare =>
      ModuleAccessService.instance.hasPermission('performance:compare');

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  @override
  void dispose() {
    _regionController.dispose();
    _minPriceController.dispose();
    _maxPriceController.dispose();
    super.dispose();
  }

  Future<void> _loadTeams() async {
    setState(() {
      _teamsLoading = true;
      _teamsError = null;
    });
    final res = await AnalyticsService.instance.getTeams();
    if (!mounted) return;
    setState(() {
      _teamsLoading = false;
      if (res.success && res.data != null) {
        _teams = res.data!;
      } else {
        _teamsError = res.message ?? 'Erro ao carregar equipes';
      }
    });
  }

  void _toggleTeam(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        return;
      }
      if (_selectedIds.length >= _maxSelection) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Máximo de 4 equipes na comparação.')),
        );
        return;
      }
      _selectedIds.add(id);
    });
  }

  CompareFilters get _filters => CompareFilters(
        startDate: _startDate,
        endDate: _endDate,
        propertyType: _propertyType,
        region: _regionController.text,
        minPrice: parseCurrencyText(_minPriceController.text),
        maxPrice: parseCurrencyText(_maxPriceController.text),
      );

  String? _validate() {
    if (_selectedIds.length < 2) {
      return 'Selecione pelo menos 2 equipes para comparar.';
    }
    if ((_startDate != null) != (_endDate != null)) {
      return 'Preencha as duas datas do período (ou nenhuma).';
    }
    if (_startDate != null &&
        _endDate != null &&
        _startDate!.isAfter(_endDate!)) {
      return 'A data inicial não pode ser maior que a final.';
    }
    final region = _regionController.text.trim();
    if (region.isNotEmpty && !RegExp(r'^[A-Za-z]{2}$').hasMatch(region)) {
      return 'A UF deve ter exatamente 2 letras (ex.: SP, RJ).';
    }
    final min = parseCurrencyText(_minPriceController.text);
    final max = parseCurrencyText(_maxPriceController.text);
    if (min != null && max != null && min > max) {
      return 'O preço mínimo não pode ser maior que o máximo.';
    }
    return null;
  }

  Future<void> _compare() async {
    final error = _validate();
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() {
      _comparing = true;
      _compareError = null;
    });
    final res = await AnalyticsService.instance.compareTeams(
      teamIds: _selectedIds.toList(),
      filters: _filters,
    );
    if (!mounted) return;
    setState(() {
      _comparing = false;
      if (res.success && res.data != null) {
        _result = res.data;
      } else {
        _compareError = res.message ?? 'Erro ao comparar equipes';
      }
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = (isStart ? _startDate : _endDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('pt', 'BR'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canCompare) {
      return const AppScaffold(
        title: 'Comparar Equipes',
        showBottomNavigation: false,
        body: AnalyticsDeniedView(
          message: 'Você não tem acesso à comparação de equipes.',
          permission: 'performance:compare',
        ),
      );
    }
    return AppScaffold(
      title: 'Comparar Equipes',
      showBottomNavigation: false,
      body: RefreshIndicator(
        color: AnalyticsTones.accent(context),
        onRefresh: _loadTeams,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    _kPadH, _kPadTop, _kPadH, _kPadBottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHero(context),
                    const SizedBox(height: 18),
                    _buildSelectionSection(context),
                    const SizedBox(height: 18),
                    _buildFiltersSection(context),
                    const SizedBox(height: 18),
                    _buildCompareButton(context),
                    if (_comparing) ...[
                      const SizedBox(height: 18),
                      _buildComparingSkeleton(),
                    ] else if (_compareError != null) ...[
                      const SizedBox(height: 10),
                      AnalyticsErrorState(
                        message: _compareError!,
                        onRetry: _compare,
                      ),
                    ] else if (_result != null) ...[
                      const SizedBox(height: 22),
                      ..._buildResults(context, _result!),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Hero ─────────────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context) {
    final green = AnalyticsTones.green(context);
    final amber = AnalyticsTones.amber(context);
    final blue = AnalyticsTones.blue(context);
    final fmt = DateFormat('dd/MM', 'pt_BR');
    final extraFilters = _filters.activeCount;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HeroEyebrow(
            label: 'COMPARAR EQUIPES',
            dotColor: _selectedIds.length >= 2 ? green : amber,
          ),
          const SizedBox(height: 10),
          HeroHeadline(
            value: '${_selectedIds.length}/$_maxSelection',
            suffix: 'selecionadas',
            subtitle:
                'Matches, vendas, receitas e comissões por equipe — escolha de 2 a 4 equipes.',
          ),
          const SizedBox(height: 18),
          HeroKpiStrip(
            blocks: [
              HeroKpiData(
                icon: LucideIcons.network,
                label: 'EQUIPES',
                value: '${_selectedIds.length}',
                sub: 'de $_maxSelection possíveis',
                tone: AnalyticsTones.purple(context),
              ),
              HeroKpiData(
                icon: LucideIcons.calendarDays,
                label: 'PERÍODO',
                value: _startDate != null && _endDate != null
                    ? '${fmt.format(_startDate!)}–${fmt.format(_endDate!)}'
                    : 'Livre',
                sub: 'datas da análise',
                tone: green,
              ),
              HeroKpiData(
                icon: LucideIcons.listFilter,
                label: 'FILTROS',
                value: '$extraFilters',
                sub: extraFilters == 1 ? 'extra ativo' : 'extras ativos',
                tone: blue,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Seleção de equipes ──────────────────────────────────────────────────

  Widget _buildSelectionSection(BuildContext context) {
    final tone = AnalyticsTones.purple(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnalyticsPanelHeader(
          icon: LucideIcons.network,
          eyebrow: 'SELEÇÃO',
          title: 'Equipes (${_selectedIds.length} de $_maxSelection)',
          hint: 'Toque para incluir ou remover da comparação.',
          tone: tone,
        ),
        const SizedBox(height: 12),
        if (_teamsLoading)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(
              4,
              (_) => SkeletonBox(width: 110, height: 34, borderRadius: 999),
            ),
          )
        else if (_teamsError != null)
          AnalyticsErrorState(message: _teamsError!, onRetry: _loadTeams)
        else if (_teams.isEmpty)
          AnalyticsEmptyState(
            icon: LucideIcons.network,
            title: 'Nenhuma equipe cadastrada',
            body:
                'Crie equipes na área de colaboradores para poder compará-las aqui.',
            tone: tone,
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in _teams)
                AnalyticsChip(
                  label: t.memberCount != null
                      ? '${t.name} (${t.memberCount})'
                      : t.name,
                  icon: _selectedIds.contains(t.id)
                      ? LucideIcons.check
                      : LucideIcons.plus,
                  selected: _selectedIds.contains(t.id),
                  accent: tone,
                  onTap: () => _toggleTeam(t.id),
                ),
            ],
          ),
      ],
    );
  }

  // ─── Filtros ─────────────────────────────────────────────────────────────

  Widget _buildFiltersSection(BuildContext context) {
    final tone = AnalyticsTones.blue(context);
    final amber = AnalyticsTones.amber(context);
    final fmt = DateFormat('dd/MM/yyyy', 'pt_BR');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnalyticsPanelHeader(
          icon: LucideIcons.listFilter,
          eyebrow: 'CRITÉRIOS',
          title: 'Filtros da comparação',
          hint:
              'Período, tipo de negócio, UF e faixa de preço — todos opcionais.',
          tone: tone,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: CompareDateField(
                label: 'Data inicial',
                value: _startDate == null ? null : fmt.format(_startDate!),
                accent: tone,
                onTap: () => _pickDate(isStart: true),
                onClear: () => setState(() => _startDate = null),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: CompareDateField(
                label: 'Data final',
                value: _endDate == null ? null : fmt.format(_endDate!),
                accent: tone,
                onTap: () => _pickDate(isStart: false),
                onClear: () => setState(() => _endDate = null),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (value, label) in const [
              ('all', 'Todos'),
              ('sale', 'Apenas vendas'),
              ('rental', 'Apenas aluguéis'),
            ])
              AnalyticsChip(
                label: label,
                selected: _propertyType == value,
                accent: amber,
                onTap: () => setState(() => _propertyType = value),
              ),
          ],
        ),
        const SizedBox(height: 12),
        CompareTextField(
          controller: _regionController,
          hint: 'UF (ex.: SP)',
          icon: LucideIcons.mapPin,
          accent: tone,
          maxLength: 2,
          textCapitalization: TextCapitalization.characters,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: CompareTextField(
                controller: _minPriceController,
                hint: 'Preço mínimo',
                icon: LucideIcons.banknote,
                accent: AnalyticsTones.green(context),
                prefixText: 'R\$ ',
                keyboardType: TextInputType.number,
                inputFormatters: [CurrencyInputFormatter()],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: CompareTextField(
                controller: _maxPriceController,
                hint: 'Preço máximo',
                icon: LucideIcons.banknote,
                accent: AnalyticsTones.green(context),
                prefixText: 'R\$ ',
                keyboardType: TextInputType.number,
                inputFormatters: [CurrencyInputFormatter()],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCompareButton(BuildContext context) {
    final accent = AnalyticsTones.accent(context);
    final enabled = _selectedIds.length >= 2 && !_comparing;
    return FilledButton.icon(
      onPressed: enabled ? _compare : null,
      icon: _comparing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(LucideIcons.gitCompareArrows, size: 18),
      label: Text(
        _comparing
            ? 'Comparando…'
            : _selectedIds.length < 2
                ? 'Selecione pelo menos 2 equipes'
                : 'Comparar ${_selectedIds.length} equipes',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        elevation: 0,
      ),
    );
  }

  Widget _buildComparingSkeleton() {
    return Column(
      children: [
        SkeletonBox(width: double.infinity, height: 90, borderRadius: 16),
        const SizedBox(height: 10),
        SkeletonBox(width: double.infinity, height: 220, borderRadius: 16),
      ],
    );
  }

  // ─── Resultados ──────────────────────────────────────────────────────────

  List<Widget> _buildResults(BuildContext context, TeamsComparison result) {
    final green = AnalyticsTones.green(context);
    final amber = AnalyticsTones.amber(context);
    final blue = AnalyticsTones.blue(context);
    final purple = AnalyticsTones.purple(context);
    final teams = result.teams;
    if (teams.isEmpty) {
      return [
        AnalyticsEmptyState(
          icon: LucideIcons.searchX,
          title: 'Sem resultados',
          body: 'A comparação não retornou dados para os filtros atuais.',
          tone: amber,
        ),
      ];
    }

    final totalSales = teams.fold(0, (acc, t) => acc + t.totalSales);
    final totalRentals = teams.fold(0, (acc, t) => acc + t.totalRentals);
    final totalRevenue = teams.fold(0.0, (acc, t) => acc + t.totalRevenue);
    final totalCommissions =
        teams.fold(0.0, (acc, t) => acc + t.totalCommissions);

    final bestCards = <Widget>[
      if (result.bestAcceptanceRate != null)
        BestInCard(
          icon: LucideIcons.circleCheckBig,
          category: 'Taxa de aceitação',
          name: result.bestAcceptanceRate!.name,
          valueLabel: _pct(result.bestAcceptanceRate!.value),
          tone: green,
        ),
      if (result.bestAvgScore != null)
        BestInCard(
          icon: LucideIcons.gauge,
          category: 'Score médio',
          name: result.bestAvgScore!.name,
          valueLabel: result.bestAvgScore!.value.toStringAsFixed(1),
          tone: purple,
        ),
      if (result.bestTotalMatches != null)
        BestInCard(
          icon: LucideIcons.gitCompareArrows,
          category: 'Mais matches',
          name: result.bestTotalMatches!.name,
          valueLabel: _int.format(result.bestTotalMatches!.value.round()),
          tone: blue,
        ),
    ];

    return [
      AnalyticsPanelHeader(
        icon: LucideIcons.trophy,
        eyebrow: 'RESULTADO',
        title: 'Comparação de ${teams.length} equipes',
        hint: _resultPeriodHint(result),
        tone: AnalyticsTones.accent(context),
      ),
      const SizedBox(height: 14),
      MetricGrid(cards: [
        MetricCard(
          icon: LucideIcons.handshake,
          label: 'Vendas somadas',
          value: _int.format(totalSales),
          tone: AnalyticsTones.accent(context),
        ),
        MetricCard(
          icon: LucideIcons.keyRound,
          label: 'Aluguéis somados',
          value: _int.format(totalRentals),
          tone: amber,
        ),
        MetricCard(
          icon: LucideIcons.banknote,
          label: 'Receita total',
          value: _compactMoney.format(totalRevenue),
          tone: green,
        ),
        MetricCard(
          icon: LucideIcons.percent,
          label: 'Comissões',
          value: _compactMoney.format(totalCommissions),
          tone: purple,
        ),
      ]),
      if (bestCards.isNotEmpty) ...[
        const SizedBox(height: 18),
        const AnalyticsSubsectionHeader(
          label: 'Melhores em',
          icon: LucideIcons.trophy,
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 560 ? 2 : 1;
            final w = (c.maxWidth - 10 * (cols - 1)) / cols;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final card in bestCards) SizedBox(width: w, child: card),
              ],
            );
          },
        ),
      ],
      const SizedBox(height: 18),
      const AnalyticsSubsectionHeader(
        label: 'Lado a lado',
        icon: LucideIcons.gitCompareArrows,
      ),
      const SizedBox(height: 10),
      ComparisonTable(
        entityNames: [for (final t in teams) t.teamName],
        rows: [
          ComparisonRow.fromValues(
            label: 'Membros',
            values: [for (final t in teams) t.memberCount.toDouble()],
            format: (v) => _int.format(v.round()),
          ),
          ComparisonRow.fromValues(
            label: 'Matches',
            values: [for (final t in teams) t.totalMatches.toDouble()],
            format: (v) => _int.format(v.round()),
          ),
          ComparisonRow.fromValues(
            label: 'Matches aceitos',
            values: [for (final t in teams) t.acceptedMatches.toDouble()],
            format: (v) => _int.format(v.round()),
          ),
          ComparisonRow.fromValues(
            label: 'Taxa de aceitação',
            values: [for (final t in teams) t.acceptanceRate],
            format: _pct,
          ),
          ComparisonRow.fromValues(
            label: 'Score médio',
            values: [for (final t in teams) t.avgMatchScore],
            format: (v) => v.toStringAsFixed(1),
          ),
          ComparisonRow.fromValues(
            label: 'Vendas',
            values: [for (final t in teams) t.totalSales.toDouble()],
            format: (v) => _int.format(v.round()),
          ),
          ComparisonRow.fromValues(
            label: 'Aluguéis',
            values: [for (final t in teams) t.totalRentals.toDouble()],
            format: (v) => _int.format(v.round()),
          ),
          ComparisonRow.fromValues(
            label: 'Receita total',
            values: [for (final t in teams) t.totalRevenue],
            format: _compactMoney.format,
          ),
          ComparisonRow.fromValues(
            label: 'Comissões',
            values: [for (final t in teams) t.totalCommissions],
            format: _compactMoney.format,
          ),
          ComparisonRow.fromValues(
            label: 'Conversão',
            values: [for (final t in teams) t.conversionRate],
            format: _pct,
          ),
        ],
      ).animate().fadeIn(duration: 260.ms),
      if (teams.any((t) => t.topPerformerName != null)) ...[
        const SizedBox(height: 14),
        const AnalyticsSubsectionHeader(
          label: 'Destaques por equipe',
          icon: LucideIcons.medal,
        ),
        const SizedBox(height: 8),
        for (final t in teams.where((t) => t.topPerformerName != null))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Icon(LucideIcons.medal, size: 14, color: green),
                const SizedBox(width: 7),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${t.teamName}: ',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: ThemeHelpers.textColor(context),
                          ),
                        ),
                        TextSpan(
                          text: t.topPerformerName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
      if (result.sharedUsers.isNotEmpty) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: amber.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: amber.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.triangleAlert, size: 14, color: amber),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Corretores em mais de uma equipe',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: amber,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              for (final u in result.sharedUsers.take(6))
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '${u.userName} — ${u.teams.join(', ')} '
                    '(${u.totalSales} venda${u.totalSales == 1 ? '' : 's'}, ${u.totalRentals} aluguel${u.totalRentals == 1 ? '' : 's'})',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                  ),
                ),
              const SizedBox(height: 2),
              Text(
                'Os números desses corretores contam nas duas equipes — considere isso ao ler a comparação.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
            ],
          ),
        ),
      ],
    ];
  }

  String _resultPeriodHint(TeamsComparison result) {
    if (result.periodStart == null || result.periodEnd == null) {
      return 'Métricas no mesmo recorte de filtros para todas.';
    }
    final fmt = DateFormat('dd/MM/yyyy', 'pt_BR');
    return 'Período: ${fmt.format(result.periodStart!)} a ${fmt.format(result.periodEnd!)}.';
  }
}
