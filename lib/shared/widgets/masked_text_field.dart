import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/input_formatters.dart';
import '../utils/validators.dart';

/// Tipos de máscara disponíveis
enum MaskType {
  cpf,
  cnpj,
  phone,
  cep,
  money,
  percentage,
  date,
  time,
  numeric,
  lettersOnly,
  none,
}

/// Campo de texto com máscara integrada
class MaskedTextField extends StatelessWidget {
  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final MaskType maskType;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final bool enabled;
  final int? maxLength;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final FocusNode? focusNode;
  final bool readOnly;
  final String? errorText;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final bool required;
  final List<TextInputFormatter>? additionalFormatters;

  const MaskedTextField({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.maskType = MaskType.none,
    this.keyboardType,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.maxLength,
    this.suffixIcon,
    this.prefixIcon,
    this.focusNode,
    this.readOnly = false,
    this.errorText,
    this.textInputAction,
    this.obscureText = false,
    this.required = false,
    this.additionalFormatters,
  });

  TextInputFormatter? _getFormatter() {
    switch (maskType) {
      case MaskType.cpf:
        return CpfInputFormatter();
      case MaskType.cnpj:
        return CnpjInputFormatter();
      case MaskType.phone:
        return PhoneInputFormatter();
      case MaskType.cep:
        return CepInputFormatter();
      case MaskType.money:
        return MoneyInputFormatter();
      case MaskType.percentage:
        return PercentageInputFormatter();
      case MaskType.date:
        return DateInputFormatter();
      case MaskType.time:
        return TimeInputFormatter();
      case MaskType.numeric:
        return NumericInputFormatter();
      case MaskType.lettersOnly:
        return LettersOnlyInputFormatter();
      case MaskType.none:
        return null;
    }
  }

  TextInputType _getKeyboardType() {
    if (keyboardType != null) return keyboardType!;
    
    switch (maskType) {
      case MaskType.cpf:
      case MaskType.cnpj:
      case MaskType.phone:
      case MaskType.cep:
      case MaskType.numeric:
        return TextInputType.number;
      case MaskType.money:
      case MaskType.percentage:
        return const TextInputType.numberWithOptions(decimal: true);
      case MaskType.date:
      case MaskType.time:
        return TextInputType.number;
      default:
        return TextInputType.text;
    }
  }

  String? Function(String?)? _buildValidator() {
    if (validator != null) {
      return validator;
    }

    if (!required && maskType == MaskType.none) {
      return null;
    }

    return (String? value) {
      // Validação de obrigatório
      if (required) {
        final requiredError = Validators.required(value);
        if (requiredError != null) return requiredError;
      }

      // Validações específicas por tipo de máscara
      switch (maskType) {
        case MaskType.cpf:
          return Validators.cpf(value);
        case MaskType.cnpj:
          return Validators.cnpj(value);
        case MaskType.phone:
          return Validators.phone(value, required: required);
        case MaskType.cep:
          return Validators.cep(value);
        case MaskType.money:
          return Validators.money(value);
        case MaskType.none:
          return null;
        default:
          return null;
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatters = <TextInputFormatter>[];

    // Adiciona formatter da máscara
    final maskFormatter = _getFormatter();
    if (maskFormatter != null) {
      formatters.add(maskFormatter);
    }

    // Adiciona formatter de limite de caracteres se especificado
    if (maxLength != null) {
      formatters.add(LengthLimitingFormatter(maxLength!));
    }

    // Adiciona formatters adicionais
    if (additionalFormatters != null) {
      formatters.addAll(additionalFormatters!);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
        ],
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: _getKeyboardType(),
          validator: _buildValidator(),
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
          enabled: enabled,
          focusNode: focusNode,
          readOnly: readOnly,
          textInputAction: textInputAction,
          inputFormatters: formatters.isNotEmpty ? formatters : null,
          style: theme.textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
            errorText: errorText,
          ),
        ),
      ],
    );
  }
}
