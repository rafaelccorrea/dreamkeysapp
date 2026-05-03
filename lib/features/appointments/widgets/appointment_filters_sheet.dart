import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/appointment_model.dart';
import 'appointment_helpers.dart';

/// Estado dos filtros aplicáveis na agenda.
class CalendarFiltersState {
  final AppointmentStatus? status;
  final AppointmentType? type;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool onlyMyData;

  const CalendarFiltersState({
    this.status,
    this.type,
    this.startDate,
    this.endDate,
    this.onlyMyData = false,
  });

  bool get hasActiveFilters =>
      status != null ||
      type != null ||
      startDate != null ||
      endDate != null ||
      onlyMyData;

  int get activeFilterCount {
    int n = 0;
    if (status != null) n++;
    if (type != null) n++;
    if (startDate != null || endDate != null) n++;
    if (onlyMyData) n++;
    return n;
  }

  CalendarFiltersState copyWith({
    Object? status = _unset,
    Object? type = _unset,
    Object? startDate = _unset,
    Object? endDate = _unset,
    bool? onlyMyData,
  }) {
    return CalendarFiltersState(
      status: identical(status, _unset)
          ? this.status
          : status as AppointmentStatus?,
      type: identical(type, _unset) ? this.type : type as AppointmentType?,
      startDate: identical(startDate, _unset)
          ? this.startDate
          : startDate as DateTime?,
      endDate:
          identical(endDate, _unset) ? this.endDate : endDate as DateTime?,
      onlyMyData: onlyMyData ?? this.onlyMyData,
    );
  }
}

const _unset = Object();

/// Bottom sheet premium de filtros da agenda.
class AppointmentFiltersSheet extends StatefulWidget {
  final CalendarFiltersState initial;
  final ValueChanged<CalendarFiltersState> onApply;

  const AppointmentFiltersSheet({
    super.key,
    required this.initial,
    required this.onApply,
  });

  @override
  State<AppointmentFiltersSheet> createState() =>
      _AppointmentFiltersSheetState();
}

class _AppointmentFiltersSheetState extends State<AppointmentFiltersSheet> {
  late CalendarFiltersState _state;

  @override
  void initState() {
    super.initState();
    _state = widget.initial;
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      initialDateRange:
          (_state.startDate != null && _state.endDate != null)
              ? DateTimeRange(start: _state.startDate!, end: _state.endDate!)
              : null,
      locale: const Locale('pt', 'BR'),
      saveText: 'Aplicar',
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: Theme.of(ctx).colorScheme.copyWith(
                  primary: AppColors.primary.primary,
                ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _state = _state.copyWith(
          startDate: picked.start,
          endDate: picked.end,
        );
      });
    }
  }

  void _quickRange(int days) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(Duration(days: days - 1));
    setState(() {
      _state = _state.copyWith(startDate: start, endDate: end);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: ThemeHelpers.borderColor(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.primary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.tune_rounded,
                    color: AppColors.primary.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Filtros da agenda',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        'Refine o que você quer ver no calendário',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle(context, 'Período'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _quickChip(
                          context,
                          'Hoje',
                          () => _quickRange(1),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child:
                            _quickChip(context, '7 dias', () => _quickRange(7)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _quickChip(
                          context,
                          '30 dias',
                          () => _quickRange(30),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: _pickRange,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: ThemeHelpers.borderColor(context),
                        ),
                        color: isDark
                            ? Colors.white.withOpacity(0.03)
                            : Colors.white,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.date_range_rounded,
                              color: AppColors.primary.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              (_state.startDate != null &&
                                      _state.endDate != null)
                                  ? '${DateFormat('dd MMM', 'pt_BR').format(_state.startDate!)} → ${DateFormat('dd MMM', 'pt_BR').format(_state.endDate!)}'
                                  : 'Selecionar intervalo personalizado',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (_state.startDate != null)
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () => setState(
                                () => _state = _state.copyWith(
                                  startDate: null,
                                  endDate: null,
                                ),
                              ),
                            )
                          else
                            const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _sectionTitle(context, 'Status'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _filterChip(
                        context,
                        label: 'Todos',
                        selected: _state.status == null,
                        color: ThemeHelpers.textColor(context),
                        icon: Icons.all_inclusive_rounded,
                        onTap: () => setState(
                          () => _state = _state.copyWith(status: null),
                        ),
                      ),
                      ...AppointmentStatus.values.map((s) {
                        return _filterChip(
                          context,
                          label: s.label,
                          icon: AppointmentVisuals.iconForStatus(s),
                          color: AppointmentVisuals.colorForStatus(s),
                          selected: _state.status == s,
                          onTap: () => setState(
                            () => _state = _state.copyWith(
                              status: _state.status == s ? null : s,
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _sectionTitle(context, 'Tipo'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _filterChip(
                        context,
                        label: 'Todos',
                        selected: _state.type == null,
                        color: ThemeHelpers.textColor(context),
                        icon: Icons.apps_rounded,
                        onTap: () => setState(
                          () => _state = _state.copyWith(type: null),
                        ),
                      ),
                      ...AppointmentType.values.map((t) {
                        return _filterChip(
                          context,
                          label: t.label,
                          icon: AppointmentVisuals.iconFor(t),
                          color: AppColors.primary.primary,
                          selected: _state.type == t,
                          onTap: () => setState(
                            () => _state = _state.copyWith(
                              type: _state.type == t ? null : t,
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _sectionTitle(context, 'Visualização'),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: ThemeHelpers.borderColor(context),
                      ),
                      color: isDark
                          ? Colors.white.withOpacity(0.03)
                          : Colors.white,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.person_outline_rounded,
                            color: AppColors.primary.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Apenas meus agendamentos',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Esconde os criados por outros corretores',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color:
                                      ThemeHelpers.textSecondaryColor(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch.adaptive(
                          activeColor: AppColors.primary.primary,
                          value: _state.onlyMyData,
                          onChanged: (v) => setState(
                            () => _state = _state.copyWith(onlyMyData: v),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Limpar'),
                      onPressed: () {
                        setState(() {
                          _state = const CalendarFiltersState();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Aplicar filtros'),
                      onPressed: () {
                        widget.onApply(_state);
                        Navigator.pop(context);
                      },
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

  Widget _sectionTitle(BuildContext context, String text) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            fontSize: 11,
          ),
    );
  }

  Widget _quickChip(BuildContext context, String label, VoidCallback onTap) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.primary.primary.withOpacity(0.18),
          ),
          color: isDark
              ? AppColors.primary.primary.withOpacity(0.10)
              : AppColors.primary.primary.withOpacity(0.06),
        ),
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.primary.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _filterChip(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? color.withOpacity(0.55)
                : ThemeHelpers.borderColor(context),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? color : null),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? color : null,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
