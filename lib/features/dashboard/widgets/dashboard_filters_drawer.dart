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

  DashboardFilters({
    this.dateRange,
    this.compareWith,
    this.metric,
    this.startDate,
    this.endDate,
    this.activitiesLimit = 10,
    this.appointmentsLimit = 5,
  });

  DashboardFilters copyWith({
    String? dateRange,
    String? compareWith,
    String? metric,
    String? startDate,
    String? endDate,
    int? activitiesLimit,
    int? appointmentsLimit,
    bool clearDates = false,
  }) {
    return DashboardFilters(
      dateRange: dateRange ?? this.dateRange,
      compareWith: compareWith ?? this.compareWith,
      metric: metric ?? this.metric,
      startDate: clearDates ? null : (startDate ?? this.startDate),
      endDate: clearDates ? null : (endDate ?? this.endDate),
      activitiesLimit: activitiesLimit ?? this.activitiesLimit,
      appointmentsLimit: appointmentsLimit ?? this.appointmentsLimit,
    );
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

  const DashboardFiltersDrawer({
    super.key,
    required this.initialFilters,
    required this.onFiltersChanged,
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
      _filters = DashboardFilters.defaultFilters();
      _selectedStartDate = null;
      _selectedEndDate = null;
      _parseInitialDates();
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
