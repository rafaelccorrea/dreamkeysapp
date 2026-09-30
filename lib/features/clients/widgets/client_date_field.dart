import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Campo de data no mesmo desenho do `CustomTextField` (rótulo em cima,
/// campo do tema embaixo), com seletor nativo e botão de limpar.
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

  Future<void> _pick(BuildContext context) async {
    final first = firstDate ?? DateTime(1900);
    final last = lastDate ?? DateTime(2100);
    var initial = value ?? initialPickerDate ?? DateTime.now();
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      locale: const Locale('pt', 'BR'),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text =
        value == null ? '' : DateFormat('dd/MM/yyyy').format(value!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: ValueKey('$label-$text'),
          initialValue: text,
          readOnly: true,
          enabled: enabled,
          onTap: enabled ? () => _pick(context) : null,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            prefixIcon: Icon(icon),
            suffixIcon: value == null || !enabled
                ? const Icon(Icons.calendar_today_outlined, size: 18)
                : IconButton(
                    tooltip: 'Limpar',
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () => onChanged(null),
                  ),
          ),
        ),
      ],
    );
  }
}
