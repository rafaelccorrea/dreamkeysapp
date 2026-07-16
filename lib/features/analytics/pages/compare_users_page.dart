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

/// Comparar Corretores — seleção de 2 a 4 corretores e comparação lado a
/// lado. Paridade com `CompareUsersPage` do imobx-front
/// (`POST /matches/performance/compare/users`, permissão
/// `performance:compare`).
class CompareUsersPage extends StatefulWidget {
  const CompareUsersPage({super.key});

  @override
  State<CompareUsersPage> createState() => _CompareUsersPageState();
}

class _CompareUsersPageState extends State<CompareUsersPage> {
  static const double _kPadH = 16;
  static const double _kPadTop = 10;
  static const double _kPadBottom = 88;
  static const int _maxSelection = 4;

  List<MemberOption> _members = const [];
  bool _membersLoading = true;
  String? _membersError;
  final Set<String> _selectedIds = <String>{};
  final TextEditingController _searchController = TextEditingController();
  String _search = '';

  DateTime? _startDate;
  DateTime? _endDate;
  String _propertyType = 'all';
  final TextEditingController _regionController = TextEditingController();
  final TextEditingController _minPriceController = TextEditingController();
  final TextEditingController _maxPriceController = TextEditingController();

  UsersComparison? _result;
  bool _comparing = false;
  String? _compareError;

  bool get _canCompare =>
      ModuleAccessService.instance.hasPermission('performance:compare');

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _regionController.dispose();
    _minPriceController.dispose();
    _maxPriceController.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    setState(() {
      _membersLoading = true;
      _membersError = null;
    });
    final res = await AnalyticsService.instance.getCompanyMembers();
    if (!mounted) return;
    setState(() {
      _membersLoading = false;
      if (res.success && res.data != null) {
        _members = res.data!;
      } else {
        _membersError = res.message ?? 'Erro ao carregar corretores';
      }
    });
  }

  void _toggleMember(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        return;
      }
      if (_selectedIds.length >= _maxSelection) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Máximo de 4 corretores na comparação.'),
          ),
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
      return 'Selecione pelo menos 2 corretores para comparar.';
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
    final res = await AnalyticsService.instance.compareUsers(
      userIds: _selectedIds.toList(),
      filters: _filters,
    );
    if (!mounted) return;
    setState(() {
      _comparing = false;
      if (res.success && res.data != null) {
        _result = res.data;
      } else {
        _compareError = res.message ?? 'Erro ao comparar corretores';
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
        title: 'Comparar Corretores',
        showBottomNavigation: false,
        body: AnalyticsDeniedView(
          message: 'Você não tem acesso à comparação de corretores.',
          permission: 'performance:compare',
        ),
      );
    }
    return AppScaffold(
      title: 'Comparar Corretores',
      showBottomNavigation: false,
      body: RefreshIndicator(
        color: AnalyticsTones.accent(context),
        onRefresh: _loadMembers,
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
    final purple = AnalyticsTones.purple(context);
    final fmt = DateFormat('dd/MM', 'pt_BR');
    final extraFilters = _filters.activeCount;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HeroEyebrow(
            label: 'COMPARAR CORRETORES',
            dotColor: _selectedIds.length >= 2 ? green : amber,
          ),
          const SizedBox(height: 10),
          HeroHeadline(
            value: '${_selectedIds.length}/$_maxSelection',
            suffix: 'selecionados',
            subtitle:
                'Vendas, aluguéis, receitas, comissões e taxas lado a lado — escolha de 2 a 4 corretores.',
          ),
          const SizedBox(height: 18),
          HeroKpiStrip(
            blocks: [
              HeroKpiData(
                icon: LucideIcons.usersRound,
                label: 'CORRETORES',
                value: '${_selectedIds.length}',
                sub: 'de $_maxSelection possíveis',
                tone: purple,
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

  // ─── Seleção de corretores ───────────────────────────────────────────────

  Widget _buildSelectionSection(BuildContext context) {
    final tone = AnalyticsTones.purple(context);
    final filtered = _search.isEmpty
        ? _members
        : _members
            .where((m) =>
                m.name.toLowerCase().contains(_search) ||
                m.email.toLowerCase().contains(_search))
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnalyticsPanelHeader(
          icon: LucideIcons.usersRound,
          eyebrow: 'SELEÇÃO',
          title: 'Corretores (${_selectedIds.length} de $_maxSelection)',
          hint: 'Toque para incluir ou remover da comparação.',
          tone: tone,
        ),
        const SizedBox(height: 12),
        if (_membersLoading)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(
              6,
              (_) => SkeletonBox(width: 96, height: 34, borderRadius: 999),
            ),
          )
        else if (_membersError != null)
          AnalyticsErrorState(message: _membersError!, onRetry: _loadMembers)
        else ...[
          TextField(
            controller: _searchController,
            onChanged: (v) =>
                setState(() => _search = v.trim().toLowerCase()),
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: ThemeHelpers.textColor(context),
            ),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: Icon(LucideIcons.search,
                  size: 17, color: ThemeHelpers.textSecondaryColor(context)),
              hintText: 'Buscar corretor…',
              hintStyle: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: ThemeHelpers.textSecondaryColor(context)
                    .withValues(alpha: 0.8),
              ),
              filled: true,
              fillColor: ThemeHelpers.cardBackgroundColor(context),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: ThemeHelpers.borderLightColor(context),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: ThemeHelpers.borderLightColor(context),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: tone.withValues(alpha: 0.5)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (filtered.isEmpty)
            Text(
              'Nenhum corretor encontrado para "$_search".',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in filtered.take(40))
                  AnalyticsChip(
                    label: m.name,
                    icon: _selectedIds.contains(m.id)
                        ? LucideIcons.check
                        : LucideIcons.plus,
                    selected: _selectedIds.contains(m.id),
                    accent: tone,
                    onTap: () => _toggleMember(m.id),
                  ),
              ],
            ),
        ],
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
        Row(
          children: [
            Expanded(
              child: CompareTextField(
                controller: _regionController,
                hint: 'UF (ex.: SP)',
                icon: LucideIcons.mapPin,
                accent: tone,
                maxLength: 2,
                textCapitalization: TextCapitalization.characters,
              ),
            ),
          ],
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
                ? 'Selecione pelo menos 2 corretores'
                : 'Comparar ${_selectedIds.length} corretores',
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

  List<Widget> _buildResults(BuildContext context, UsersComparison result) {
    final green = AnalyticsTones.green(context);
    final amber = AnalyticsTones.amber(context);
    final blue = AnalyticsTones.blue(context);
    final purple = AnalyticsTones.purple(context);
    final users = result.users;
    if (users.isEmpty) {
      return [
        AnalyticsEmptyState(
          icon: LucideIcons.searchX,
          title: 'Sem resultados',
          body: 'A comparação não retornou dados para os filtros atuais.',
          tone: amber,
        ),
      ];
    }

    final totalSales = users.fold(0, (acc, u) => acc + u.totalSales);
    final totalRentals = users.fold(0, (acc, u) => acc + u.totalRentals);
    final totalRevenue = users.fold(0.0, (acc, u) => acc + u.totalRevenue);
    final totalCommissions =
        users.fold(0.0, (acc, u) => acc + u.totalCommissions);

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
      if (result.bestTasksCompleted != null)
        BestInCard(
          icon: LucideIcons.listChecks,
          category: 'Tarefas concluídas',
          name: result.bestTasksCompleted!.name,
          valueLabel: _int.format(result.bestTasksCompleted!.value.round()),
          tone: blue,
        ),
      if (result.bestResponseTime != null)
        BestInCard(
          icon: LucideIcons.timer,
          category: 'Resposta mais rápida',
          name: result.bestResponseTime!.name,
          valueLabel:
              '${result.bestResponseTime!.value.toStringAsFixed(1).replaceAll('.', ',')} h',
          tone: amber,
        ),
    ];

    return [
      AnalyticsPanelHeader(
        icon: LucideIcons.trophy,
        eyebrow: 'RESULTADO',
        title: 'Comparação de ${users.length} corretores',
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
        entityNames: [for (final u in users) u.userName],
        rows: [
          ComparisonRow.fromValues(
            label: 'Vendas',
            values: [for (final u in users) u.totalSales.toDouble()],
            format: (v) => _int.format(v.round()),
          ),
          ComparisonRow.fromValues(
            label: 'Aluguéis',
            values: [for (final u in users) u.totalRentals.toDouble()],
            format: (v) => _int.format(v.round()),
          ),
          ComparisonRow.fromValues(
            label: 'Receita de vendas',
            values: [for (final u in users) u.salesRevenue],
            format: _compactMoney.format,
          ),
          ComparisonRow.fromValues(
            label: 'Receita de aluguéis',
            values: [for (final u in users) u.rentalsRevenue],
            format: _compactMoney.format,
          ),
          ComparisonRow.fromValues(
            label: 'Comissões',
            values: [for (final u in users) u.totalCommissions],
            format: _compactMoney.format,
          ),
          ComparisonRow.fromValues(
            label: 'Matches',
            values: [for (final u in users) u.totalMatches.toDouble()],
            format: (v) => _int.format(v.round()),
          ),
          ComparisonRow.fromValues(
            label: 'Matches aceitos',
            values: [for (final u in users) u.acceptedMatches.toDouble()],
            format: (v) => _int.format(v.round()),
          ),
          ComparisonRow.fromValues(
            label: 'Taxa de aceitação',
            values: [for (final u in users) u.acceptanceRate],
            format: _pct,
          ),
          ComparisonRow.fromValues(
            label: 'Score médio aceito',
            values: [for (final u in users) u.avgAcceptedScore],
            format: (v) => v.toStringAsFixed(1),
          ),
          ComparisonRow.fromValues(
            label: 'Tarefas concluídas',
            values: [
              for (final u in users) u.tasksCompletedFromMatches.toDouble()
            ],
            format: (v) => _int.format(v.round()),
          ),
          ComparisonRow.fromValues(
            label: 'Conclusão de tarefas',
            values: [for (final u in users) u.taskCompletionRate],
            format: _pct,
          ),
          ComparisonRow.fromValues(
            label: 'Tempo de resposta',
            values: [for (final u in users) u.avgResponseTime],
            format: (v) => '${v.toStringAsFixed(1).replaceAll('.', ',')} h',
            lowerIsBetter: true,
          ),
        ],
      ).animate().fadeIn(duration: 260.ms),
      const SizedBox(height: 10),
      Text(
        'Valores monetários somam vendas e aluguéis no recorte de filtros aplicado. '
        'A medalha marca o melhor corretor em cada métrica.',
        style: TextStyle(
          fontSize: 11,
          height: 1.4,
          fontWeight: FontWeight.w600,
          color: ThemeHelpers.textSecondaryColor(context),
        ),
      ),
    ];
  }

  String _resultPeriodHint(UsersComparison result) {
    if (result.periodStart == null || result.periodEnd == null) {
      return 'Métricas no mesmo recorte de filtros para todos.';
    }
    final fmt = DateFormat('dd/MM/yyyy', 'pt_BR');
    return 'Período: ${fmt.format(result.periodStart!)} a ${fmt.format(result.periodEnd!)}.';
  }
}
