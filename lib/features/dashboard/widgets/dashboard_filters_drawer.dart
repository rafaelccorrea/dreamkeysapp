import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';

/// Modelo de filtros do dashboard (mantido — backend espelha exatamente
/// estes campos).
class DashboardFilters {
  /// Período: 'today' | '7d' | '30d' | '90d' | '1y' | 'custom'
  final String? dateRange;

  /// Comparação com período anterior. **Não é mais editável pela UI** —
  /// o dashboard mobile não exibe deltas/comparativos visualmente, então
  /// ter esse filtro só confundia o usuário. Mantemos um default fixo
  /// (`previous_period`) pra manter a chamada da API válida.
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

  /// O recorte é o padrão da visão executiva (mês corrente, sem corretor,
  /// sem comparação, empresa atual)?
  bool get isExecutiveDefault {
    final d = executiveDefaults();
    return dateRange == d.dateRange &&
        startDate == d.startDate &&
        endDate == d.endDate &&
        !isComparing &&
        teamMember == null &&
        companyIds.isEmpty;
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

// ────────────────────────────────────────────────────────────────────
// DRAWER
// ────────────────────────────────────────────────────────────────────

/// Filtros do Dashboard — reescritos no padrão editorial premium.
///
/// Mudanças em relação à versão anterior:
/// - **Removidos filtros que não funcionavam**: "Tipo de Métrica" tinha
///   valores inválidos pro backend (`properties/clients/...` em vez de
///   `all/sales/revenue/leads/conversions`); "Comparação" não era
///   exibida em lugar nenhum no app; "Atividades Recentes" também não.
/// - **Período em chips horizontais** (não mais dropdown) — mais visível
///   e tátil. O ativo ganha gradiente accent + sombra leve.
/// - **Date pickers**: o `showDatePicker` agora funciona porque o app
///   recebeu `flutter_localizations` no `MaterialApp`. Aplicamos um
///   `Theme` override pra ele usar o accent da marca em vez do default
///   azul Material.
/// - **Stepper visual** pro limite de agendamentos (em vez de TextField
///   de número, que era frágil e sem feedback).
/// - **Header editorial**: eyebrow `FILTROS · DASHBOARD` + título grande
///   "Personalizar visão" + linha contextual com período ativo.
class DashboardFiltersDrawer extends StatefulWidget {
  final DashboardFilters initialFilters;
  final Function(DashboardFilters) onFiltersChanged;

  /// 29/09/2026 (dash-01): visão executiva (admin/master). Troca o limite de
  /// agendamentos (só do painel pessoal) pelos recortes do `HomeFilterBar`
  /// do web: comparação, empresa (só com mais de uma) e corretor.
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

  @override
  void initState() {
    super.initState();
    _filters = widget.initialFilters;
    _parseInitialDates();
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
  /// picker abre com tema azul Material padrão, que destoa da marca.
  Future<DateTime?> _showThemedDatePicker({
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
    required String helpText,
  }) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;

    return showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      locale: const Locale('pt', 'BR'),
      helpText: helpText,
      cancelText: 'CANCELAR',
      confirmText: 'OK',
      builder: (context, child) {
        return Theme(
          data: theme.copyWith(
            colorScheme: theme.colorScheme.copyWith(
              primary: accent,
              onPrimary: Colors.white,
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
              headerBackgroundColor: accent,
              headerForegroundColor: Colors.white,
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
                if (states.contains(WidgetState.selected)) return Colors.white;
                return accent;
              }),
              dayForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return Colors.white;
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
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: accent,
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
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
      helpText: 'DATA INICIAL',
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
      helpText: 'DATA FINAL',
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

  void _resetFilters() {
    setState(() {
      _filters = widget.executive
          ? DashboardFilters.executiveDefaults()
          : DashboardFilters.defaultFilters();
      _selectedStartDate = null;
      _selectedEndDate = null;
      _parseInitialDates();
    });
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
    final v = _filters.dateRange ?? 'custom';
    return _kPeriods
        .firstWhere(
          (p) => p.value == v,
          orElse: () => _kPeriods.last,
        )
        .label;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Drag handle ─────────────────────────────────
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(top: 6, bottom: 16),
                  decoration: BoxDecoration(
                    color: ThemeHelpers.borderLightColor(context),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),

              // ── Header editorial ────────────────────────────
              _buildHeader(theme, isDark, accent),
              const SizedBox(height: 22),

              // ── Período ─────────────────────────────────────
              _SectionTitle(
                eyebrow: 'PERÍODO',
                title: 'Janela de tempo',
                accent: accent,
              ),
              const SizedBox(height: 12),
              _PeriodChips(
                value: _filters.dateRange ?? 'custom',
                accent: accent,
                onChanged: (value) {
                  setState(() {
                    _filters = _filters.copyWith(dateRange: value);
                    if (value != 'custom') {
                      _filters = _filters.copyWith(clearDates: true);
                      _selectedStartDate = null;
                      _selectedEndDate = null;
                    }
                  });
                },
              ),

              // ── Datas customizadas (se Personalizado) ──────
              if (_filters.dateRange == 'custom') ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _DateField(
                        label: 'Início',
                        date: _selectedStartDate,
                        accent: accent,
                        onTap: _selectStartDate,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DateField(
                        label: 'Fim',
                        date: _selectedEndDate,
                        accent: accent,
                        onTap: _selectEndDate,
                      ),
                    ),
                  ],
                ),
                if (_selectedStartDate != null &&
                    _selectedEndDate != null) ...[
                  const SizedBox(height: 8),
                  _DateRangeHint(
                    start: _selectedStartDate!,
                    end: _selectedEndDate!,
                    accent: accent,
                  ),
                ],
              ],

              const SizedBox(height: 28),

              if (widget.executive) ...[
                // ── Comparação (visão executiva) ─────────────────
                _SectionTitle(
                  eyebrow: 'COMPARAÇÃO',
                  title: 'Comparar com',
                  accent: accent,
                ),
                const SizedBox(height: 12),
                _ChoiceWrap(
                  accent: accent,
                  value: _filters.compareWith ?? 'none',
                  options: const [
                    DashboardScopeOption(id: 'none', name: 'Sem comparação'),
                    DashboardScopeOption(
                      id: 'previous_period',
                      name: 'Período anterior',
                    ),
                    DashboardScopeOption(
                      id: 'previous_year',
                      name: 'Ano anterior',
                    ),
                  ],
                  onChanged: (v) => setState(() {
                    _filters = _filters.copyWith(compareWith: v);
                  }),
                ),

                // ── Empresa (só com mais de uma) ─────────────────
                if (widget.companies.length > 1) ...[
                  const SizedBox(height: 28),
                  _SectionTitle(
                    eyebrow: 'EMPRESA',
                    title: 'Dados de qual empresa',
                    accent: accent,
                  ),
                  const SizedBox(height: 12),
                  _ChoiceWrap(
                    accent: accent,
                    value: _filters.companyIds.isEmpty
                        ? ''
                        : _filters.companyIds.first,
                    options: [
                      const DashboardScopeOption(id: '', name: 'Empresa atual'),
                      ...widget.companies,
                    ],
                    onChanged: (v) => setState(() {
                      _filters = _filters.copyWith(
                        companyIds: v.isEmpty ? const <String>[] : [v],
                      );
                    }),
                  ),
                ],

                // ── Corretor ─────────────────────────────────────
                const SizedBox(height: 28),
                _SectionTitle(
                  eyebrow: 'EQUIPE',
                  title: 'Corretor',
                  accent: accent,
                ),
                const SizedBox(height: 12),
                _PickerField(
                  icon: Icons.person_search_rounded,
                  label: _memberLabel,
                  active: _filters.teamMember != null,
                  accent: accent,
                  onTap: widget.members.isEmpty
                      ? null
                      : () => _pickMember(accent),
                  onClear: _filters.teamMember == null
                      ? null
                      : () => setState(() {
                            _filters =
                                _filters.copyWith(clearTeamMember: true);
                          }),
                ),
              ] else ...[
                // ── Limite de agendamentos ──────────────────────
                _SectionTitle(
                  eyebrow: 'TIMELINE',
                  title: 'Próximos agendamentos',
                  accent: accent,
                  trailing:
                      '${_filters.appointmentsLimit} ${_filters.appointmentsLimit == 1 ? 'item' : 'itens'}',
                ),
                const SizedBox(height: 12),
                _AppointmentsLimitStepper(
                  value: _filters.appointmentsLimit,
                  accent: accent,
                  onChanged: (v) {
                    setState(() {
                      _filters = _filters.copyWith(appointmentsLimit: v);
                    });
                  },
                ),
              ],

              const SizedBox(height: 28),

              // ── Ações ───────────────────────────────────────
              _buildActions(theme, isDark, accent),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  Widget _buildHeader(ThemeData theme, bool isDark, Color accent) {
    final periodNote = _filters.dateRange == 'custom' &&
            _selectedStartDate != null &&
            _selectedEndDate != null
        ? '${DateFormat('d MMM', 'pt_BR').format(_selectedStartDate!)} → '
            '${DateFormat('d MMM', 'pt_BR').format(_selectedEndDate!)}'
        : _activePeriodLabel;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FILTROS · DASHBOARD',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Personalizar visão',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  height: 1.05,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent,
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.5),
                          blurRadius: 5,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      periodNote,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Botão fechar circular discreto
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.04),
                border: Border.all(
                  color: ThemeHelpers.borderLightColor(context),
                ),
              ),
              child: Icon(
                Icons.close_rounded,
                size: 18,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────
  Widget _buildActions(ThemeData theme, bool isDark, Color accent) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed: _applyFilters,
            icon: const Icon(Icons.check_rounded, size: 20),
            label: const Text(
              'Aplicar filtros',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.1,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton.icon(
            onPressed: _resetFilters,
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text(
              'Restaurar padrão',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: ThemeHelpers.textSecondaryColor(context),
              side: BorderSide(color: ThemeHelpers.borderLightColor(context)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// COMPONENTES INTERNOS
// ────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.eyebrow,
    required this.title,
    required this.accent,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final Color accent;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(width: 4, height: 14, color: accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                eyebrow,
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                  color: accent,
                  fontSize: 10,
                  height: 1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                  height: 1.1,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: ThemeHelpers.textSecondaryColor(context),
              letterSpacing: 0.4,
            ),
          ),
      ],
    );
  }
}

/// Chips horizontais de período. Substitui o dropdown — mais visível e
/// tátil, mostra todas as opções sem precisar abrir nada.
class _PeriodChips extends StatelessWidget {
  const _PeriodChips({
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  final String value;
  final Color accent;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _kPeriods.map((p) {
        final selected = p.value == value;
        return _PeriodChip(
          option: p,
          selected: selected,
          accent: accent,
          onTap: () => onChanged(p.value),
        );
      }).toList(),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.option,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final _PeriodOption option;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent,
                      Color.lerp(accent, Colors.black, 0.18) ?? accent,
                    ],
                  )
                : null,
            color: selected
                ? null
                : (isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.03)),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.6)
                  : ThemeHelpers.borderLightColor(context),
              width: 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.32),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                option.icon,
                size: 14,
                color: selected
                    ? Colors.white
                    : ThemeHelpers.textSecondaryColor(context),
              ),
              const SizedBox(width: 6),
              Text(
                option.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.1,
                  color: selected
                      ? Colors.white
                      : ThemeHelpers.textColor(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.date,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final DateTime? date;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasDate = date != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: hasDate
                ? accent.withValues(alpha: isDark ? 0.10 : 0.06)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.black.withValues(alpha: 0.03)),
            border: Border.all(
              color: hasDate
                  ? accent.withValues(alpha: isDark ? 0.45 : 0.32)
                  : ThemeHelpers.borderLightColor(context),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: accent.withValues(alpha: hasDate ? 0.18 : 0.10),
                ),
                child: Icon(
                  Icons.event_rounded,
                  size: 16,
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textSecondaryColor(context),
                        fontSize: 9.5,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasDate
                          ? DateFormat("d MMM, y", 'pt_BR').format(date!)
                          : 'Selecionar',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: hasDate
                            ? ThemeHelpers.textColor(context)
                            : ThemeHelpers.textSecondaryColor(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateRangeHint extends StatelessWidget {
  const _DateRangeHint({
    required this.start,
    required this.end,
    required this.accent,
  });

  final DateTime start;
  final DateTime end;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = end.difference(start).inDays + 1;
    final label = days == 1
        ? 'Apenas 1 dia selecionado'
        : '$days dias no intervalo';
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 4),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 12,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: ThemeHelpers.textSecondaryColor(context),
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Stepper de "limite de agendamentos" (1 a 20).
///
/// Substitui o TextField numérico — visualmente óbvio o que é, sem
/// precisar abrir teclado, e ainda inclui um dot/track simples.
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
          _StepperButton(
            icon: Icons.remove_rounded,
            enabled: canDec,
            accent: accent,
            onTap: canDec ? () => onChanged(value - 1) : null,
          ),
          Expanded(
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: anim,
                  child: child,
                ),
                child: Text(
                  '$value',
                  key: ValueKey<int>(value),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    letterSpacing: -0.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
          _StepperButton(
            icon: Icons.add_rounded,
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
    required this.enabled,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: enabled
                ? accent.withValues(alpha: 0.14)
                : Colors.transparent,
            border: Border.all(
              color: enabled
                  ? accent.withValues(alpha: 0.36)
                  : ThemeHelpers.borderLightColor(context),
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: enabled
                ? accent
                : ThemeHelpers.textSecondaryColor(context)
                    .withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
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

/// Escolha única em fichas — mesma gramática das fichas de período acima.
class _ChoiceWrap extends StatelessWidget {
  const _ChoiceWrap({
    required this.accent,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final Color accent;
  final String value;
  final List<DashboardScopeOption> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((o) {
        final selected = o.id == value;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onChanged(o.id),
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              constraints: const BoxConstraints(maxWidth: 280),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: selected
                    ? accent
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.03)),
                border: Border.all(
                  color: selected
                      ? accent.withValues(alpha: 0.6)
                      : ThemeHelpers.borderLightColor(context),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected) ...[
                    const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      o.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.1,
                        color: selected
                            ? Colors.white
                            : ThemeHelpers.textColor(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Campo que abre um seletor (corretor), com "x" para limpar quando ativo.
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.icon,
    required this.label,
    required this.active,
    required this.accent,
    required this.onTap,
    required this.onClear,
  });

  final IconData icon;
  final String label;
  final bool active;
  final Color accent;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final enabled = onTap != null;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: active
                ? accent.withValues(alpha: isDark ? 0.10 : 0.06)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.black.withValues(alpha: 0.03)),
            border: Border.all(
              color: active
                  ? accent.withValues(alpha: isDark ? 0.45 : 0.32)
                  : ThemeHelpers.borderLightColor(context),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: accent.withValues(alpha: active ? 0.18 : 0.10),
                ),
                child: Icon(icon, size: 16, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  enabled ? label : 'Nenhum corretor neste recorte',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: active ? ThemeHelpers.textColor(context) : secondary,
                  ),
                ),
              ),
              if (onClear != null)
                IconButton(
                  onPressed: onClear,
                  tooltip: 'Voltar para toda a equipe',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded, size: 18, color: secondary),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: secondary.withValues(alpha: enabled ? 1 : 0.4),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

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
    IconData icon = Icons.person_outline_rounded,
  }) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final selected = widget.selectedId == id;
    return InkWell(
      onTap: () => Navigator.of(context).pop(_MemberPick(id)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: ThemeHelpers.borderLightColor(
                context,
              ).withValues(alpha: 0.7),
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle_rounded : icon,
              size: 18,
              color: selected ? widget.accent : secondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final visible = _visible;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Filtrar por corretor',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Fechar',
                    icon: Icon(Icons.close_rounded, color: secondary),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onChanged: (v) =>
                    setState(() => _term = _foldForSearch(v.trim())),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Buscar pelo nome',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  filled: true,
                  fillColor: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : const Color(0xFFEEF0F3),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: visible.length + 1,
                itemBuilder: (ctx, i) {
                  if (i == 0) {
                    return _row(
                      id: null,
                      label: 'Toda a equipe',
                      icon: Icons.groups_2_outlined,
                    );
                  }
                  final m = visible[i - 1];
                  return _row(id: m.id, label: m.name);
                },
              ),
            ),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Text(
                  'Ninguém com esse nome.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: secondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
