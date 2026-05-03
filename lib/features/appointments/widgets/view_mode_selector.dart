import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';

enum CalendarViewMode { month, week, agenda }

extension CalendarViewModeX on CalendarViewMode {
  String get label {
    switch (this) {
      case CalendarViewMode.month:
        return 'Mês';
      case CalendarViewMode.week:
        return 'Semana';
      case CalendarViewMode.agenda:
        return 'Agenda';
    }
  }

  IconData get icon {
    switch (this) {
      case CalendarViewMode.month:
        return Icons.calendar_month_rounded;
      case CalendarViewMode.week:
        return Icons.view_week_rounded;
      case CalendarViewMode.agenda:
        return Icons.view_agenda_rounded;
    }
  }
}

/// Seletor segmentado premium para alternar visualização do calendário.
class ViewModeSelector extends StatelessWidget {
  final CalendarViewMode value;
  final ValueChanged<CalendarViewMode> onChanged;

  const ViewModeSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = AppColors.primary.primary;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ThemeHelpers.borderColor(context),
        ),
      ),
      child: Row(
        children: CalendarViewMode.values.map((m) {
          final selected = value == m;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(m),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: selected
                      ? LinearGradient(
                          colors: [
                            primary,
                            primary.withOpacity(0.85),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: primary.withOpacity(0.30),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      m.icon,
                      size: 16,
                      color: selected
                          ? Colors.white
                          : ThemeHelpers.textSecondaryColor(context),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      m.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: selected
                            ? Colors.white
                            : ThemeHelpers.textSecondaryColor(context),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
