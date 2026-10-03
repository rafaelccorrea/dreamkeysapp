import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/theme_helpers.dart';
import '../../meu_financeiro/widgets/meu_financeiro_widgets.dart';

InputDecoration financeInputDecoration(
  BuildContext context, {
  required String label,
  String? hint,
  String? error,
  String? helper,
  Widget? prefix,
  Widget? suffix,
}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: ThemeHelpers.borderLightColor(context)),
  );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    errorText: error,
    helperText: helper,
    helperMaxLines: 3,
    errorMaxLines: 3,
    prefixIcon: prefix,
    suffixIcon: suffix,
    filled: true,
    fillColor: ThemeHelpers.cardBackgroundColor(context),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: BorderSide(color: financeAccent(context), width: 1.6),
    ),
  );
}

/// Campo de texto com rótulo e erro.
class FinanceTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? error;
  final String? helper;
  final int maxLines;
  final int? maxLength;
  final bool enabled;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final Widget? prefix;

  const FinanceTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.error,
    this.helper,
    this.maxLines = 1,
    this.maxLength,
    this.enabled = true,
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
    this.prefix,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        enabled: enabled,
        minLines: maxLines > 1 ? 2 : 1,
        maxLines: maxLines,
        maxLength: maxLength,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        decoration: financeInputDecoration(
          context,
          label: label,
          hint: hint,
          error: error,
          helper: helper,
          prefix: prefix,
        ),
      ),
    );
  }
}

/// Seletor (lista curta) com rótulo e erro.
class FinanceDropdown<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<(T, String)> items;
  final ValueChanged<T?>? onChanged;
  final String? error;
  final String? helper;
  final bool allowClear;

  const FinanceDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.error,
    this.helper,
    this.allowClear = false,
  });

  @override
  Widget build(BuildContext context) {
    final has = items.any((i) => i.$1 == value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<T>(
        // `initialValue` só vale no 1º build: a chave recria o campo quando
        // o valor/opções mudam por fora (rascunho, troca de empresa…).
        key: ValueKey('$label|$value|${items.length}'),
        initialValue: has ? value : null,
        isExpanded: true,
        icon: const Icon(LucideIcons.chevronDown, size: 18),
        decoration: financeInputDecoration(
          context,
          label: label,
          error: error,
          helper: helper,
        ),
        items: [
          if (allowClear)
            DropdownMenuItem<T>(
              value: null,
              child: Text(
                '—',
                style: TextStyle(
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
            ),
          for (final i in items)
            DropdownMenuItem<T>(
              value: i.$1,
              child: Text(i.$2, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

/// Campo de data (abre o seletor do sistema).
class FinanceDateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String? error;
  final String? helper;
  final DateTime? first;
  final DateTime? last;

  const FinanceDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.error,
    this.helper,
    this.first,
    this.last,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final now = DateTime.now();
          final d = await showDatePicker(
            context: context,
            initialDate: value ?? now,
            firstDate: first ?? DateTime(now.year - 5),
            lastDate: last ?? DateTime(now.year + 5),
            locale: const Locale('pt', 'BR'),
          );
          if (d != null) onChanged(d);
        },
        child: InputDecorator(
          decoration: financeInputDecoration(
            context,
            label: label,
            error: error,
            helper: helper,
            suffix: const Icon(LucideIcons.calendar, size: 18),
          ),
          child: Text(
            value == null
                ? 'Selecionar'
                : DateFormat('dd/MM/yyyy', 'pt_BR').format(value!),
          ),
        ),
      ),
    );
  }
}

/// Converte "1.234,56" / "1234.56" para número.
double? parseBrlInput(String raw) {
  var s = raw.trim().replaceAll('R\$', '').replaceAll(' ', '');
  if (s.isEmpty) return null;
  if (s.contains(',')) {
    s = s.replaceAll('.', '').replaceAll(',', '.');
  }
  return double.tryParse(s);
}

/// Número → "1234,56" para o campo de valor.
String brlInputText(double? v) =>
    v == null ? '' : v.toStringAsFixed(2).replaceAll('.', ',');

/// Só dígitos, vírgula e ponto.
final List<TextInputFormatter> kMoneyInputFormatters = [
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
];

/// Botão principal do Financeiro (largura cheia, com carregando).
class FinancePrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool loading;
  final VoidCallback? onPressed;
  final Color? color;

  const FinancePrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: color ?? financeAccent(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
            : Icon(icon ?? LucideIcons.check, size: 18),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ),
    );
  }
}

/// SnackBar padrão.
void financeSnack(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? FinanceTones.rose : null,
        duration: Duration(seconds: error ? 6 : 4),
      ),
    );
}
