import 'package:flutter/material.dart';
// `hide TextDirection`: o intl tem o próprio TextDirection (LTR maiúsculo),
// que sombreava o do Flutter e quebrava o `TextDirection.ltr` do layout.
import 'package:intl/intl.dart' hide TextDirection;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';

/// Modelo de filtros do dashboard (mantido — backend espelha exatamente
/// estes campos).
class DashboardFilters {
  /// Período: 'today' | '7d' | '30d' | '90d' | '1y' | 'custom'
  final String? dateRange;

  /// Comparação com período anterior: 'previous_period' | 'previous_year' |
  /// 'none'. No painel pessoal ela não é editável (o painel não exibe
  /// deltas) e fica no default fixo `previous_period`. Na visão executiva
  /// (29/09/2026, dash-01) ela É um filtro, como no `HomeFilterBar` do web:
  /// nasce em 'none' e, ligada, acende as variações da tela.
  final String? compareWith;

  /// Tipo de métrica. **Removido da UI** — os valores que o app mandava
  /// (`properties/clients/inspections/...`) nem existem no backend
  /// (que aceita só `all/sales/revenue/leads/conversions`), então o
  /// filtro era puramente decorativo e não tinha efeito nenhum.
  final String? metric;

  final String? startDate; // YYYY-MM-DD
  final String? endDate;   // YYYY-MM-DD

  /// Limite de "atividades recentes". **Removido da UI** — atividades
  /// recentes nem aparecem na tela do app mobile. Mantemos um default
  /// pra a API.
  final int activitiesLimit;

  /// Limite de próximos agendamentos exibidos no timeline do dashboard.
  /// Esse SIM é exibido visualmente, então fica controlável.
  final int appointmentsLimit;

  /// Corretor do recorte da visão executiva (`teamMember` do
  /// `/dashboard/overview`). Nulo = toda a equipe.
  ///
  /// 29/09/2026 (dash-01): o `HomeFilterBar` do web filtra a Home do
  /// admin/master por corretor — e o ranking "Top corretores" também liga e
  /// desliga este filtro com um toque.
  final String? teamMember;

  /// Empresa(s) do recorte da visão executiva (`companyIds[]`). Vazio =
  /// empresa atual. Só aparece para quem tem mais de uma empresa, como no web.
  final List<String> companyIds;

  DashboardFilters({
    this.dateRange,
    this.compareWith,
    this.metric,
    this.startDate,
    this.endDate,
    this.activitiesLimit = 10,
    this.appointmentsLimit = 5,
    this.teamMember,
    this.companyIds = const [],
  });

  /// Comparação ligada (a visão executiva só mostra variação com ela ligada).
  bool get isComparing =>
      compareWith != null && compareWith!.isNotEmpty && compareWith != 'none';

  DashboardFilters copyWith({
    String? dateRange,
    String? compareWith,
    String? metric,
    String? startDate,
    String? endDate,
    int? activitiesLimit,
    int? appointmentsLimit,
    bool clearDates = false,
    String? teamMember,
    bool clearTeamMember = false,
    List<String>? companyIds,
  }) {
    return DashboardFilters(
      dateRange: dateRange ?? this.dateRange,
      compareWith: compareWith ?? this.compareWith,
      metric: metric ?? this.metric,
      startDate: clearDates ? null : (startDate ?? this.startDate),
      endDate: clearDates ? null : (endDate ?? this.endDate),
      activitiesLimit: activitiesLimit ?? this.activitiesLimit,
      appointmentsLimit: appointmentsLimit ?? this.appointmentsLimit,
      teamMember: clearTeamMember ? null : (teamMember ?? this.teamMember),
      companyIds: companyIds ?? this.companyIds,
    );
  }

  /// Padrão da visão executiva — o mesmo `getInitialFilters` do web para
  /// admin/master: do dia 1º do mês até hoje, SEM comparação.
  static DashboardFilters executiveDefaults() {
    final now = DateTime.now();
    final firstDayOfMonth = DateTime(now.year, now.month, 1);
    return DashboardFilters(
      dateRange: 'custom',
      startDate: _ymd(firstDayOfMonth),
      endDate: _ymd(now),
      compareWith: 'none',
      metric: 'all',
    );
  }

  /// O período é o "Este mês" da visão executiva (do dia 1º até hoje)?
  bool get isCurrentMonthPeriod {
    final d = executiveDefaults();
    return dateRange == 'custom' &&
        startDate == d.startDate &&
        endDate == d.endDate;
  }

  /// Filtros padrão: primeiro dia do mês até hoje.
  static DashboardFilters defaultFilters() {
    final now = DateTime.now();
    final firstDayOfMonth = DateTime(now.year, now.month, 1);
    return DashboardFilters(
      dateRange: 'custom',
      startDate: _ymd(firstDayOfMonth),
      endDate: _ymd(now),
      compareWith: 'previous_period',
      metric: 'all',
      activitiesLimit: 10,
      appointmentsLimit: 5,
    );
  }

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// ────────────────────────────────────────────────────────────────────
// PERÍODOS DISPONÍVEIS
// ────────────────────────────────────────────────────────────────────

class _PeriodOption {
  const _PeriodOption({
    required this.value,
    required this.label,
    required this.icon,
  });
  final String value;
  final String label;
  final IconData icon;
}

const _kPeriods = <_PeriodOption>[
  _PeriodOption(
    value: 'today',
    label: 'Hoje',
    icon: Icons.today_rounded,
  ),
  _PeriodOption(
    value: '7d',
    label: '7 dias',
    icon: Icons.view_week_rounded,
  ),
  _PeriodOption(
    value: '30d',
    label: '30 dias',
    icon: Icons.calendar_view_month_rounded,
  ),
  _PeriodOption(
    value: '90d',
    label: '90 dias',
    icon: Icons.event_repeat_rounded,
  ),
  _PeriodOption(
    value: '1y',
    label: '1 ano',
    icon: Icons.calendar_today_rounded,
  ),
  _PeriodOption(
    value: 'custom',
    label: 'Personalizado',
    icon: Icons.edit_calendar_rounded,
  ),
];

/// "Este mês" não é um `dateRange` do back: é o personalizado do dia 1º até
/// hoje. Só existe na visão executiva.
const String _kMonthPeriod = 'month';

/// Recortes de tempo da visão executiva — os mesmos atalhos do menu
/// "Recorte de tempo" do `HomeFilterBar` do web (29/09/2026, dash-01): lá
/// não existem 90 dias nem 1 ano, e existe "Este mês", que é o padrão.
const _kExecutivePeriods = <_PeriodOption>[
  _PeriodOption(
    value: 'today',
    label: 'Hoje',
    icon: Icons.today_rounded,
  ),
  _PeriodOption(
    value: '7d',
    label: '7 dias',
    icon: Icons.view_week_rounded,
  ),
  _PeriodOption(
    value: '30d',
    label: '30 dias',
    icon: Icons.calendar_view_month_rounded,
  ),
  _PeriodOption(
    value: _kMonthPeriod,
    label: 'Este mês',
    icon: Icons.calendar_month_rounded,
  ),
  _PeriodOption(
    value: 'custom',
    label: 'Personalizado',
    icon: Icons.edit_calendar_rounded,
  ),
];

// ────────────────────────────────────────────────────────────────────
// DRAWER
// ────────────────────────────────────────────────────────────────────

/// Filtros do Dashboard.
///
/// Histórico:
/// - **Removidos filtros que não funcionavam**: "Tipo de Métrica" tinha
///   valores inválidos pro backend (`properties/clients/...` em vez de
///   `all/sales/revenue/leads/conversions`); "Comparação" não era
///   exibida em lugar nenhum no app; "Atividades Recentes" também não.
/// - **Período em fichas** (não mais dropdown) — mais visível e tátil.
/// - **Date pickers**: o `showDatePicker` agora funciona porque o app
///   recebeu `flutter_localizations` no `MaterialApp`; um `Theme` override
///   tira o azul Material padrão.
/// - **Stepper visual** pro limite de agendamentos (em vez de TextField
///   de número, que era frágil e sem feedback).
/// - **Visão executiva** (29/09/2026, dash-01): com `executive`, a gaveta é
///   o `HomeFilterBar` do web — período com "Este mês", empresa, corretor e
///   comparação (que lá existe porque a tela mostra as variações).
/// - **Revisão de design** (30/09/2026): a gaveta espelha o modal de
///   filtros do CRM (`kanban_filters_drawer.dart`, a referência de filtros
///   do app). Saíram o cabeçalho editorial com ponto brilhando, as fichas
///   ativas com gradiente + sombra colorida e o "Aplicar" vermelho; entraram
///   cabeçalho com chapa + contagem, seções com filete tracejado, fichas
///   com véu, campos com fill e rodapé fixo ("Limpar" neutro, "Aplicar"
///   verde).
class DashboardFiltersDrawer extends StatefulWidget {
  final DashboardFilters initialFilters;
  final Function(DashboardFilters) onFiltersChanged;

  /// 29/09/2026 (dash-01): visão executiva (admin/master). Troca o limite de
  /// agendamentos (só do painel pessoal) pelos recortes do `HomeFilterBar`
  /// do web: período com "Este mês", empresa (só com mais de uma), corretor
  /// e comparação.
  final bool executive;

  /// Empresas do usuário (`GET /companies`). O seletor só aparece com 2+.
  final List<DashboardScopeOption> companies;

  /// Corretores do recorte (`filters.availableUsers` do overview).
  final List<DashboardScopeOption> members;

  const DashboardFiltersDrawer({
    super.key,
    required this.initialFilters,
    required this.onFiltersChanged,
    this.executive = false,
    this.companies = const [],
    this.members = const [],
  });

  @override
  State<DashboardFiltersDrawer> createState() => _DashboardFiltersDrawerState();
}

class _DashboardFiltersDrawerState extends State<DashboardFiltersDrawer> {
  late DashboardFilters _filters;
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;

  /// Visão executiva: "Personalizado" foi tocado — mostra as datas mesmo
  /// quando o intervalo ainda coincide com "Este mês" (o `customOpen` do
  /// `HomeFilterBar` do web).
  bool _customOpen = false;

  @override
  void initState() {
    super.initState();
    _filters = widget.initialFilters;
    _parseInitialDates();
  }

  List<_PeriodOption> get _periods =>
      widget.executive ? _kExecutivePeriods : _kPeriods;

  /// Ficha de período acesa. Na visão executiva o personalizado que cobre do
  /// dia 1º até hoje é "Este mês"; 90 dias e 1 ano não existem lá.
  String get _periodValue {
    final v = _filters.dateRange ?? 'custom';
    if (!widget.executive) return v;
    if (v == 'custom') {
      return _filters.isCurrentMonthPeriod && !_customOpen
          ? _kMonthPeriod
          : 'custom';
    }
    if (v == 'today' || v == '7d' || v == '30d') return v;
    return 'custom';
  }

  void _onPeriodChanged(String value) {
    setState(() {
      if (!widget.executive) {
        _filters = _filters.copyWith(dateRange: value);
        if (value != 'custom') {
          _filters = _filters.copyWith(clearDates: true);
          _selectedStartDate = null;
          _selectedEndDate = null;
        }
        return;
      }
      final month = DashboardFilters.executiveDefaults();
      if (value == _kMonthPeriod) {
        _customOpen = false;
        _filters = _filters.copyWith(
          dateRange: 'custom',
          startDate: month.startDate,
          endDate: month.endDate,
        );
      } else if (value == 'custom') {
        // Abre as datas já preenchidas com o mês corrente (o web faz o
        // mesmo): o personalizado nunca vai ao back sem início e fim.
        _customOpen = true;
        if (_filters.dateRange != 'custom') {
          _filters = _filters.copyWith(
            dateRange: 'custom',
            startDate: month.startDate,
            endDate: month.endDate,
          );
        }
      } else {
        _customOpen = false;
        _filters = _filters.copyWith(dateRange: value, clearDates: true);
      }
      _selectedStartDate = null;
      _selectedEndDate = null;
      _parseInitialDates();
    });
  }

  void _parseInitialDates() {
    if (_filters.startDate != null) {
      try {
        _selectedStartDate = DateTime.parse(_filters.startDate!);
      } catch (_) {
        _selectedStartDate = null;
      }
    }
    if (_filters.endDate != null) {
      try {
        _selectedEndDate = DateTime.parse(_filters.endDate!);
      } catch (_) {
        _selectedEndDate = null;
      }
    }
  }

  /// Aplica o `Theme` do app dentro do `showDatePicker` — sem isso, o
  /// picker abre com tema azul Material padrão, que destoa do app.
  ///
  /// 30/09/2026 (revisão de design): o seletor veste a tinta da seção
  /// "Período" (aço), com "Cancelar" NEUTRO e "Confirmar" na tinta — o tema
  /// global pintava os dois de vermelho, e vermelho não confirma nem cancela.
  /// No claro, o azul de TEXTO do tema (o `info` puro não passa contraste
  /// com o número branco do dia escolhido); o texto sobre a tinta é o
  /// `onPrimaryColor` do tema (branco no claro, grafite no escuro).
  Future<DateTime?> _showThemedDatePicker({
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
    required String helpText,
  }) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent =
        isDark ? AppColors.status.infoDarkMode : AppColors.message.infoText;
    final onAccent = ThemeHelpers.onPrimaryColor(context);

    return showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      locale: const Locale('pt', 'BR'),
      helpText: helpText,
      cancelText: 'Cancelar',
      confirmText: 'Confirmar',
      builder: (context, child) {
        return Theme(
          data: theme.copyWith(
            colorScheme: theme.colorScheme.copyWith(
              primary: accent,
              onPrimary: onAccent,
              surface: ThemeHelpers.cardBackgroundColor(context),
              onSurface: ThemeHelpers.textColor(context),
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: ThemeHelpers.cardBackgroundColor(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            datePickerTheme: DatePickerThemeData(
              backgroundColor: ThemeHelpers.cardBackgroundColor(context),
              surfaceTintColor: Colors.transparent,
              headerBackgroundColor: accent,
              headerForegroundColor: onAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              dayStyle: const TextStyle(fontWeight: FontWeight.w600),
              weekdayStyle: TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
              todayBorder: BorderSide(color: accent, width: 1.4),
              todayForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return onAccent;
                return accent;
              }),
              dayForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return onAccent;
                if (states.contains(WidgetState.disabled)) {
                  return ThemeHelpers.textSecondaryColor(context)
                      .withValues(alpha: 0.4);
                }
                return ThemeHelpers.textColor(context);
              }),
              dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return accent;
                return Colors.transparent;
              }),
              cancelButtonStyle: TextButton.styleFrom(
                foregroundColor: ThemeHelpers.textSecondaryColor(context),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              confirmButtonStyle: TextButton.styleFrom(
                foregroundColor: accent,
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }

  Future<void> _selectStartDate() async {
    final picked = await _showThemedDatePicker(
      initialDate: _selectedStartDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: _selectedEndDate ?? DateTime.now(),
      helpText: 'Início do período',
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedStartDate = picked;
        _filters = _filters.copyWith(
          startDate: DashboardFilters._ymd(picked),
        );
      });
    }
  }

  Future<void> _selectEndDate() async {
    final picked = await _showThemedDatePicker(
      initialDate: _selectedEndDate ?? DateTime.now(),
      firstDate: _selectedStartDate ?? DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Fim do período',
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedEndDate = picked;
        _filters = _filters.copyWith(
          endDate: DashboardFilters._ymd(picked),
        );
      });
    }
  }

  void _applyFilters() {
    widget.onFiltersChanged(_filters);
    Navigator.pop(context);
  }

  /// "Limpar filtros" — como no modal do CRM: volta ao padrão, aplica e
  /// fecha. Visão executiva: o "Limpar tudo" do web — "Este mês", toda a
  /// equipe, sem comparação e a empresa atual.
  void _clearFilters() {
    widget.onFiltersChanged(
      widget.executive
          ? DashboardFilters.executiveDefaults()
          : DashboardFilters.defaultFilters(),
    );
    Navigator.pop(context);
  }

  /// Quantos recortes fogem do padrão — o mesmo critério da fita de
  /// filtros da tela ("Este mês" não conta).
  int get _activeCount {
    var n = 0;
    if (!_filters.isCurrentMonthPeriod) n++;
    if (widget.executive) {
      if (_filters.teamMember != null) n++;
      if (_filters.isComparing) n++;
      n += _filters.companyIds.length;
    } else if (_filters.appointmentsLimit !=
        DashboardFilters.defaultFilters().appointmentsLimit) {
      n++;
    }
    return n;
  }

  /// Nome do corretor escolhido (ou "Toda a equipe").
  String get _memberLabel {
    final id = _filters.teamMember;
    if (id == null) return 'Toda a equipe';
    for (final m in widget.members) {
      if (m.id == id) return m.name;
    }
    return 'Corretor selecionado';
  }

  /// Picker de corretor com busca — a União tem 170+ pessoas, então lista
  /// solta dentro do sheet de filtros viraria uma coluna sem fim.
  Future<void> _pickMember(Color accent) async {
    final picked = await showModalBottomSheet<_MemberPick>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black54,
      backgroundColor: ThemeHelpers.cardBackgroundColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (ctx) => _MemberPickerSheet(
        members: widget.members,
        selectedId: _filters.teamMember,
        accent: accent,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _filters = picked.id == null
          ? _filters.copyWith(clearTeamMember: true)
          : _filters.copyWith(teamMember: picked.id);
    });
  }

  String get _activePeriodLabel {
    final v = _periodValue;
    final periods = _periods;
    return periods
        .firstWhere(
          (p) => p.value == v,
          orElse: () => periods.last,
        )
        .label;
  }

  // ─────────────────────────────────────────────────────────────────
  // Visual (30/09/2026, revisão de design): espelha o modal de filtros do
  // CRM (`kanban_filters_drawer.dart`), a referência de filtros do app —
  // cabeçalho com chapa + contagem, seções flush com filete tracejado e
  // ponto de cor, campos com fill de campo, fichas com véu (nunca sólidas,
  // nunca com gradiente ou sombra colorida) e rodapé fixo com "Limpar"
  // neutro e "Aplicar" verde.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mq = MediaQuery.of(context);
    // Marca: chapa do cabeçalho e contagem de filtros.
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    // Tinta por seção — só SINAL (ponto, ícone, ficha ativa), como no CRM.
    final cPeriodo =
        isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final cEmpresa =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    final cEquipe =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    // Âmbar de texto de aviso no claro: o `warning` puro some no branco.
    final cComparacao = isDark
        ? AppColors.status.warningDarkMode
        : AppColors.message.warningText;
    final cAgenda =
        isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    final activeCount = _activeCount;
    final showDates = widget.executive
        ? _periodValue == 'custom'
        : _filters.dateRange == 'custom';
    final companyValue =
        _filters.companyIds.isEmpty ? '' : _filters.companyIds.first;

    // Teto de 88% da tela + corpo rolável + rodapé fixo: em paisagem ou tela
    // baixa o corpo rola e os botões continuam à vista.
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.88),
        child: Material(
          color: ThemeHelpers.backgroundColor(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ThemeHelpers.borderColor(context)
                          .withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
              _buildHeader(theme, isDark, accent, activeCount),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Período ──────────────────────────────────
                      _section(
                        accent: cPeriodo,
                        label: 'Período',
                        hint: widget.executive
                            ? 'Recorte de tempo de todos os números da tela.'
                            : 'Recorte de tempo dos números do painel.',
                        first: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final p in _periods)
                                  _ChipChoice(
                                    label: p.label,
                                    icon: p.icon,
                                    selected: p.value == _periodValue,
                                    accent: cPeriodo,
                                    onTap: () => _onPeriodChanged(p.value),
                                  ),
                              ],
                            ),
                            // ── Datas (Personalizado) ─────────────
                            if (showDates) ...[
                              const SizedBox(height: 12),
                              LayoutBuilder(
                                builder: (context, c) {
                                  final from = _FieldControl(
                                    icon: Icons.event_rounded,
                                    accent: cPeriodo,
                                    onTap: _selectStartDate,
                                    child: _DateValue(
                                      caption: 'De',
                                      date: _selectedStartDate,
                                    ),
                                  );
                                  final to = _FieldControl(
                                    icon: Icons.event_rounded,
                                    accent: cPeriodo,
                                    onTap: _selectEndDate,
                                    child: _DateValue(
                                      caption: 'Até',
                                      date: _selectedEndDate,
                                    ),
                                  );
                                  // Lado a lado só quando a data inteira cabe
                                  // em cada metade (medida no tamanho real);
                                  // senão, uma embaixo da outra — em 320dp com
                                  // fonte grande ela encolhia para ~70%.
                                  final half = (c.maxWidth - 10) / 2;
                                  if (_DateValue.fitsIn(context, half - 60)) {
                                    return Row(
                                      children: [
                                        Expanded(child: from),
                                        const SizedBox(width: 10),
                                        Expanded(child: to),
                                      ],
                                    );
                                  }
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      from,
                                      const SizedBox(height: 8),
                                      to,
                                    ],
                                  );
                                },
                              ),
                              if (_selectedStartDate != null &&
                                  _selectedEndDate != null) ...[
                                const SizedBox(height: 8),
                                _DateRangeHint(
                                  start: _selectedStartDate!,
                                  end: _selectedEndDate!,
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),

                      if (widget.executive) ...[
                        // Mesma ordem da frase "Mostrando …" do web:
                        // empresa, equipe, comparação.

                        // ── Empresa (só com mais de uma) ──────────
                        if (widget.companies.length > 1)
                          _section(
                            accent: cEmpresa,
                            label: 'Empresa',
                            hint: 'De qual empresa são os números da tela.',
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final o in [
                                  const DashboardScopeOption(
                                    id: '',
                                    name: 'Empresa atual',
                                  ),
                                  ...widget.companies,
                                ])
                                  _ChipChoice(
                                    label: o.name,
                                    icon: o.id.isEmpty
                                        ? Icons.home_work_outlined
                                        : null,
                                    selected: o.id == companyValue,
                                    accent: cEmpresa,
                                    onTap: () => setState(() {
                                      _filters = _filters.copyWith(
                                        companyIds: o.id.isEmpty
                                            ? const <String>[]
                                            : [o.id],
                                      );
                                    }),
                                  ),
                              ],
                            ),
                          ),

                        // ── Corretor ──────────────────────────────
                        _section(
                          accent: cEquipe,
                          label: 'Corretor',
                          hint: 'Os números da tela passam a ser só os dele.',
                          child: _memberControl(cEquipe),
                        ),

                        // ── Comparação ────────────────────────────
                        _section(
                          accent: cComparacao,
                          label: 'Comparar com',
                          hint: 'Liga as setas de alta e queda em cada '
                              'número da tela.',
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final o in _kCompareOptions)
                                _ChipChoice(
                                  label: o.name,
                                  selected:
                                      o.id == (_filters.compareWith ?? 'none'),
                                  accent: cComparacao,
                                  onTap: () => setState(() {
                                    _filters =
                                        _filters.copyWith(compareWith: o.id);
                                  }),
                                ),
                            ],
                          ),
                        ),
                      ] else
                        // ── Limite de agendamentos (painel pessoal) ──
                        _section(
                          accent: cAgenda,
                          label: 'Próximos agendamentos',
                          hint: 'Quantos compromissos a agenda do painel '
                              'mostra.',
                          child: _AppointmentsLimitStepper(
                            value: _filters.appointmentsLimit,
                            accent: cAgenda,
                            onChanged: (v) {
                              setState(() {
                                _filters =
                                    _filters.copyWith(appointmentsLimit: v);
                              });
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              _buildFooter(theme, activeCount, mq),
            ],
          ),
        ),
      ),
    );
  }

  /// Seção flush: filete tracejado (menos na primeira) + rótulo com ponto
  /// de cor + dica + conteúdo. Sem card, sem sombra, sem preenchimento.
  Widget _section({
    required Color accent,
    required String label,
    String? hint,
    required Widget child,
    bool first = false,
  }) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: EdgeInsets.only(top: first ? 16 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!first) ...[
            _DashedLine(color: ThemeHelpers.borderLightColor(context)),
            const SizedBox(height: 18),
          ],
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                    color: secondary,
                  ),
                ),
              ),
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(
              hint,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                height: 1.3,
                color: secondary.withValues(alpha: 0.9),
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  /// Campo do corretor — UMA linha, como o "Ordenar por" do CRM: mostra o
  /// escolhido; a lista (com busca, a União tem 170+ pessoas) abre num
  /// sheet à parte.
  Widget _memberControl(Color accent) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final enabled = widget.members.isNotEmpty;
    final active = _filters.teamMember != null;
    final String title;
    final String hint;
    if (active) {
      title = _memberLabel;
      hint = 'Só os números deste corretor';
    } else if (enabled) {
      title = _memberLabel;
      hint = 'Toque para escolher um corretor';
    } else {
      title = 'Nenhum corretor para escolher';
      hint = 'A lista acompanha a empresa e o período';
    }
    return _FieldControl(
      icon: Icons.person_search_rounded,
      accent: accent,
      onTap: enabled ? () => _pickMember(accent) : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                    color: enabled || active
                        ? ThemeHelpers.textColor(context)
                        : secondary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          if (active)
            IconButton(
              onPressed: () => setState(() {
                _filters = _filters.copyWith(clearTeamMember: true);
              }),
              tooltip: 'Voltar para toda a equipe',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded, size: 18, color: secondary),
            )
          else
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: enabled ? accent : secondary.withValues(alpha: 0.4),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  /// Cabeçalho do CRM: chapa da marca + título + o recorte e a contagem de
  /// filtros; fechar à direita.
  Widget _buildHeader(
    ThemeData theme,
    bool isDark,
    Color accent,
    int activeCount,
  ) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    // "1 set → 30 set": sem o ponto da abreviação do mês ("set."), como o
    // carimbo do dia na tela.
    String day(DateTime d) =>
        DateFormat('d MMM', 'pt_BR').format(d).replaceAll('.', '');
    final periodNote = _periodValue == 'custom' &&
            _selectedStartDate != null &&
            _selectedEndDate != null
        ? '${day(_selectedStartDate!)} → ${day(_selectedEndDate!)}'
        : _activePeriodLabel;
    final countNote = activeCount == 0
        ? 'nenhum filtro aplicado'
        : '$activeCount ${activeCount == 1 ? 'filtro ativo' : 'filtros ativos'}';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 4, 10, 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.20 : 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.tune_rounded, color: accent, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.executive
                      ? 'Filtrar a visão da empresa'
                      : 'Filtrar o painel',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    height: 1.2,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '$periodNote · '),
                      TextSpan(
                        text: countNote,
                        style: TextStyle(
                          color: activeCount == 0 ? secondary : accent,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, color: secondary),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Fechar',
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  /// Rodapé fixo do CRM: "Limpar filtros" NEUTRO (só com filtro fora do
  /// padrão) + "Aplicar" VERDE. Os rótulos encolhem em vez de quebrar em
  /// 320dp.
  Widget _buildFooter(ThemeData theme, int activeCount, MediaQueryData mq) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + mq.padding.bottom),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          top: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
          ),
        ),
      ),
      child: Row(
        children: [
          if (activeCount > 0) ...[
            Expanded(
              child: TextButton(
                onPressed: _clearFilters,
                style: TextButton.styleFrom(
                  // "Limpar" NUNCA em vermelho: o tema global pinta
                  // TextButton de vermelho, e limpar não é destrutivo — só
                  // volta ao padrão.
                  foregroundColor: ThemeHelpers.textSecondaryColor(context),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                  textStyle: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Limpar filtros',
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            flex: activeCount > 0 ? 2 : 1,
            child: FilledButton.icon(
              onPressed: _applyFilters,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  activeCount == 0 ? 'Aplicar' : 'Aplicar ($activeCount)',
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
              style: FilledButton.styleFrom(
                // VERDE de confirmação do app (o mesmo do modal do CRM): o
                // vermelho da marca não confirma.
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
                elevation: 0,
                textStyle: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// COMPONENTES INTERNOS
// ────────────────────────────────────────────────────────────────────

/// Campo de filtro — o `_filterControl` do CRM: fill de campo, fio claro,
/// chapa do ícone na tinta da seção e altura MÍNIMA de 48 (cresce com a
/// fonte, nunca corta).
class _FieldControl extends StatelessWidget {
  const _FieldControl({
    required this.icon,
    required this.accent,
    required this.child,
    this.onTap,
  });

  final IconData icon;
  final Color accent;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    return Material(
      color: fill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: ThemeHelpers.borderLightColor(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.20 : 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Data dentro do campo: legenda miúda ("De"/"Até") + a data. A data
/// encolhe em vez de cortar — dois campos lado a lado em 320dp com fonte
/// grande.
class _DateValue extends StatelessWidget {
  const _DateValue({required this.caption, required this.date});

  final String caption;
  final DateTime? date;

  /// Estilo da data — também usado para medir se ela cabe na linha.
  static const TextStyle _valueStyle = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w800,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// A data mais larga ("00/00/0000"), no tamanho real (fonte do sistema
  /// inclusa), cabe em [width] encolhendo no máximo 10%?
  static bool fitsIn(BuildContext context, double width) {
    final tp = TextPainter(
      text: TextSpan(
        text: '00/00/0000',
        style: DefaultTextStyle.of(context).style.merge(_valueStyle),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final natural = tp.width;
    tp.dispose();
    return natural * 0.9 <= width;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final d = date;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: secondary,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            d == null ? 'Escolher' : DateFormat('dd/MM/yyyy', 'pt_BR').format(d),
            maxLines: 1,
            softWrap: false,
            style: _valueStyle.copyWith(
              color: d == null ? secondary : ThemeHelpers.textColor(context),
            ),
          ),
        ),
      ],
    );
  }
}

class _DateRangeHint extends StatelessWidget {
  const _DateRangeHint({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final days = end.difference(start).inDays + 1;
    final label = days == 1
        ? 'Apenas 1 dia selecionado'
        : '$days dias no intervalo';
    return Row(
      children: [
        Icon(Icons.info_outline_rounded, size: 13, color: secondary),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: secondary,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }
}

/// Ficha de escolha — a do modal do CRM: ativa com véu da tinta + borda +
/// ✓ na tinta; o rótulo fica no tom do texto (a tinta como texto miúdo não
/// passa contraste no claro). Nome longo (empresa) termina em reticências
/// em vez de estourar a linha.
class _ChipChoice extends StatelessWidget {
  const _ChipChoice({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.accent,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final fieldFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final glyph = selected ? Icons.check_rounded : icon;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? accent.withValues(alpha: isDark ? 0.18 : 0.10)
            : fieldFill,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? accent : ThemeHelpers.borderLightColor(context),
            width: selected ? 1.2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (glyph != null) ...[
                  Icon(
                    glyph,
                    size: 14,
                    color: selected
                        ? accent
                        : ThemeHelpers.textSecondaryColor(context),
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontSize: 12.5,
                      color: selected
                          ? textColor
                          : textColor.withValues(alpha: 0.82),
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Stepper de "limite de agendamentos" (1 a 20) — no corpo de campo do
/// modal do CRM, com o número grande e o que ele significa embaixo.
class _AppointmentsLimitStepper extends StatelessWidget {
  const _AppointmentsLimitStepper({
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  final int value;
  final Color accent;
  final ValueChanged<int> onChanged;

  static const int _min = 1;
  static const int _max = 20;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final canDec = value > _min;
    final canInc = value < _max;

    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark
            ? AppColors.background.backgroundTertiaryDarkMode
            : AppColors.background.backgroundTertiary,
        border: Border.all(color: ThemeHelpers.borderLightColor(context)),
      ),
      child: Row(
        children: [
          _StepperButton(
            icon: Icons.remove_rounded,
            tooltip: 'Mostrar menos',
            enabled: canDec,
            accent: accent,
            onTap: canDec ? () => onChanged(value - 1) : null,
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, anim) => ScaleTransition(
                    scale: anim,
                    child: child,
                  ),
                  child: Text(
                    '$value',
                    key: ValueKey<int>(value),
                    maxLines: 1,
                    softWrap: false,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: ThemeHelpers.textColor(context),
                      letterSpacing: -0.5,
                      height: 1.1,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                // Duas linhas centradas: em 320dp com fonte grande a legenda
                // saía "compromissos na agen…" entre os dois botões.
                Text(
                  value == 1
                      ? 'compromisso na agenda'
                      : 'compromissos na agenda',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          _StepperButton(
            icon: Icons.add_rounded,
            tooltip: 'Mostrar mais',
            enabled: canInc,
            accent: accent,
            onTap: canInc ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: enabled
            ? accent.withValues(alpha: isDark ? 0.20 : 0.12)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: enabled
                ? accent.withValues(alpha: 0.36)
                : ThemeHelpers.borderLightColor(context),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: 19,
              color: enabled
                  ? accent
                  : ThemeHelpers.textSecondaryColor(context)
                      .withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

/// Filete tracejado fino — separa as seções, como no modal do CRM.
class _DashedLine extends StatelessWidget {
  const _DashedLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      width: double.infinity,
      child: CustomPaint(painter: _DashedPainter(color)),
    );
  }
}

class _DashedPainter extends CustomPainter {
  _DashedPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const dash = 5.0;
    const gap = 4.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dash, 0), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ────────────────────────────────────────────────────────────────────
// VISÃO EXECUTIVA — comparação, empresa e corretor (29/09/2026, dash-01)
// ────────────────────────────────────────────────────────────────────

/// Opção de recorte da visão executiva (empresa, corretor ou comparação).
class DashboardScopeOption {
  const DashboardScopeOption({required this.id, required this.name});

  final String id;
  final String name;
}

/// Comparações do `HomeFilterBar` do web.
const _kCompareOptions = <DashboardScopeOption>[
  DashboardScopeOption(id: 'none', name: 'Sem comparação'),
  DashboardScopeOption(id: 'previous_period', name: 'Período anterior'),
  DashboardScopeOption(id: 'previous_year', name: 'Ano anterior'),
];

/// Resultado do picker: `id` nulo = toda a equipe.
class _MemberPick {
  const _MemberPick(this.id);

  final String? id;
}

/// Tira acento e caixa para a busca por nome ("João" casa com "joao").
String _foldForSearch(String s) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  final buf = StringBuffer();
  for (final rune in s.toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    final i = from.indexOf(ch);
    buf.write(i >= 0 ? to[i] : ch);
  }
  return buf.toString();
}

/// Iniciais (duas) para a pastilha do corretor na lista.
String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  final letters = parts.take(2).map((p) => p[0].toUpperCase()).join();
  return letters.isEmpty ? '?' : letters;
}

/// Lista de corretores com busca — a anatomia dos sheets de escolha do CRM
/// (alça, rótulo com ponto + título, fio, lista flush com ✓ no escolhido).
class _MemberPickerSheet extends StatefulWidget {
  const _MemberPickerSheet({
    required this.members,
    required this.selectedId,
    required this.accent,
  });

  final List<DashboardScopeOption> members;
  final String? selectedId;
  final Color accent;

  @override
  State<_MemberPickerSheet> createState() => _MemberPickerSheetState();
}

class _MemberPickerSheetState extends State<_MemberPickerSheet> {
  final TextEditingController _search = TextEditingController();
  String _term = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<DashboardScopeOption> get _visible {
    if (_term.isEmpty) return widget.members;
    return widget.members
        .where((m) => _foldForSearch(m.name).contains(_term))
        .toList(growable: false);
  }

  Widget _row({
    required String? id,
    required String label,
    bool team = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final selected = widget.selectedId == id;
    final fieldFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    return Material(
      color: selected
          ? widget.accent.withValues(alpha: isDark ? 0.14 : 0.08)
          : Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(_MemberPick(id)),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: team
                      ? widget.accent.withValues(alpha: isDark ? 0.20 : 0.12)
                      : fieldFill,
                  border: team
                      ? null
                      : Border.all(
                          color: ThemeHelpers.borderLightColor(context),
                        ),
                ),
                child: team
                    ? Icon(
                        Icons.groups_2_outlined,
                        size: 17,
                        color: widget.accent,
                      )
                    : Text(
                        _initials(label),
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                          height: 1,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.check_circle_rounded,
                  size: 19,
                  color: widget.accent,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final visible = _visible;
    final total = widget.members.length;

    final grabber = Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
    final closeButton = IconButton(
      onPressed: () => Navigator.of(context).pop(),
      tooltip: 'Fechar',
      visualDensity: VisualDensity.compact,
      icon: Icon(Icons.close_rounded, size: 19, color: secondary),
    );
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: widget.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'EQUIPE',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: secondary,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Filtrar por corretor',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '$total ${total == 1 ? 'corretor' : 'corretores'} '
                  'neste recorte',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          closeButton,
        ],
      ),
    );
    // Busca no corpo de campo do modal de filtros (o `_searchControl` do
    // CRM): fill de campo, fio claro, chapa do ícone na tinta da seção e
    // "x" para limpar. Bordas do tema desligadas de propósito — o contorno
    // é o do próprio campo.
    final search = _FieldControl(
      icon: Icons.search_rounded,
      accent: widget.accent,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              textAlignVertical: TextAlignVertical.center,
              onChanged: (v) =>
                  setState(() => _term = _foldForSearch(v.trim())),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: ThemeHelpers.textColor(context),
              ),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'Buscar pelo nome',
                hintStyle: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: secondary.withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
          if (_search.text.isNotEmpty)
            IconButton(
              onPressed: () => setState(() {
                _search.clear();
                _term = '';
              }),
              tooltip: 'Limpar a busca',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded, size: 18, color: secondary),
            ),
        ],
      ),
    );

    // Teclado aberto: o sheet sobe (viewInsets) e a lista encolhe dentro do
    // teto — a busca nunca fica escondida atrás do teclado.
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.88),
        child: LayoutBuilder(
          builder: (context, c) {
            // Pouca altura (celular deitado com o teclado aberto): some o
            // cabeçalho e ficam a busca (com o "fechar" ao lado) e a lista.
            // Com ele, a parte fixa (~160dp) passava da altura livre e o
            // sheet estourava. A busca tem chave: quando o cabeçalho some,
            // ela é a MESMA na árvore e o teclado não fecha.
            final tight = c.maxHeight < 300;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!tight) ...[grabber, header],
                Padding(
                  key: const ValueKey<String>('member-search'),
                  padding: EdgeInsets.fromLTRB(
                    20,
                    tight ? 10 : 0,
                    tight ? 8 : 20,
                    12,
                  ),
                  child: Row(
                    children: [
                      Expanded(child: search),
                      if (tight) closeButton,
                    ],
                  ),
                ),
                Container(
                  height: 1,
                  color: ThemeHelpers.borderLightColor(context),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.only(
                      bottom: visible.isEmpty ? 0 : 16 + mq.padding.bottom,
                    ),
                    itemCount: visible.length + 1,
                    itemBuilder: (ctx, i) {
                      if (i == 0) {
                        return _row(
                          id: null,
                          label: 'Toda a equipe',
                          team: true,
                        );
                      }
                      final m = visible[i - 1];
                      return _row(id: m.id, label: m.name);
                    },
                  ),
                ),
                if (visible.isEmpty)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      tight ? 10 : 16,
                      20,
                      (tight ? 12 : 24) + mq.padding.bottom,
                    ),
                    child: Text(
                      'Ninguém com esse nome neste recorte. Confira a '
                      'grafia ou limpe a busca para ver todos.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        height: 1.35,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
