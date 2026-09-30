import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/theme_helpers.dart';
import 'client_form_kit.dart';

/// Seletor de data na cor do formulário de cliente: cabeçalho na marca,
/// "Cancelar" neutro e confirmação em destaque (sem tema, o Material abriria
/// com as cores genéricas).
Future<DateTime?> showClientDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String? helpText,
  DatePickerMode initialDatePickerMode = DatePickerMode.day,
}) {
  final base = Theme.of(context);
  final accent = clientFormAccent(context);
  final surface = ThemeHelpers.cardBackgroundColor(context);
  final text = ThemeHelpers.textColor(context);
  final muted = ThemeHelpers.textSecondaryColor(context);
  final border = ThemeHelpers.borderColor(context);

  Color? dayOrYearText(Set<WidgetState> states) {
    if (states.contains(WidgetState.selected)) return Colors.white;
    if (states.contains(WidgetState.disabled)) {
      return muted.withValues(alpha: 0.4);
    }
    return text;
  }

  Color? dayOrYearFill(Set<WidgetState> states) =>
      states.contains(WidgetState.selected) ? accent : Colors.transparent;

  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    helpText: helpText,
    initialDatePickerMode: initialDatePickerMode,
    locale: const Locale('pt', 'BR'),
    builder: (context, child) => Theme(
      data: base.copyWith(
        colorScheme: base.colorScheme.copyWith(
          primary: accent,
          onPrimary: Colors.white,
          surface: surface,
          onSurface: text,
        ),
        datePickerTheme: DatePickerThemeData(
          backgroundColor: surface,
          surfaceTintColor: Colors.transparent,
          headerBackgroundColor: accent,
          headerForegroundColor: Colors.white,
          dividerColor: border,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          weekdayStyle: TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            color: muted,
          ),
          dayStyle: const TextStyle(fontWeight: FontWeight.w600),
          todayBorder: BorderSide(color: accent, width: 1.4),
          todayForegroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? Colors.white : accent,
          ),
          dayForegroundColor: WidgetStateProperty.resolveWith(dayOrYearText),
          dayBackgroundColor: WidgetStateProperty.resolveWith(dayOrYearFill),
          yearForegroundColor: WidgetStateProperty.resolveWith(dayOrYearText),
          yearBackgroundColor: WidgetStateProperty.resolveWith(dayOrYearFill),
          cancelButtonStyle: TextButton.styleFrom(
            foregroundColor: muted,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
          confirmButtonStyle: TextButton.styleFrom(
            foregroundColor: accent,
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
      child: child ?? const SizedBox.shrink(),
    ),
  );
}

/// Campo de data no mesmo desenho dos campos do formulário de cliente
/// (filled, rótulo dentro do campo): abre o seletor com a cor da marca e,
/// preenchido, oferece "limpar". Vazio, o [icon] indica o tipo de data.
class ClientDateField extends StatelessWidget {
  const ClientDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.icon = Icons.event_outlined,
    this.firstDate,
    this.lastDate,
    this.initialPickerDate,
    this.hint = 'Selecione a data',
    this.enabled = true,
    this.pickYearFirst = false,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final IconData icon;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final DateTime? initialPickerDate;
  final String hint;
  final bool enabled;

  /// Datas distantes (nascimento): o seletor abre na grade de anos.
  final bool pickYearFirst;

  Future<void> _pick(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final first = firstDate ?? DateTime(1900);
    final last = lastDate ?? DateTime(2100);
    var initial = value ?? initialPickerDate ?? DateTime.now();
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showClientDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: label,
      initialDatePickerMode: pickYearFirst && value == null
          ? DatePickerMode.year
          : DatePickerMode.day,
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final hasValue = value != null;
    final text = hasValue ? DateFormat('dd/MM/yyyy').format(value!) : '';
    return InkWell(
      onTap: enabled ? () => _pick(context) : null,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        isEmpty: !hasValue,
        decoration: InputDecoration(
          enabled: enabled,
          label: ClientFieldLabel(label),
          hintText: hint,
          suffixIcon: hasValue && enabled
              ? IconButton(
                  tooltip: 'Limpar data',
                  icon: Icon(Icons.close_rounded, size: 18, color: muted),
                  onPressed: () => onChanged(null),
                )
              : Icon(icon, size: 18, color: muted),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: ThemeHelpers.textColor(context),
          ),
        ),
      ),
    );
  }
}
