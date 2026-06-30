import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'masks.dart';

/// Formatters customizados para TextFields

/// Máscara monetária pt-BR baseada em **centavos** — os dígitos preenchem da
/// direita para a esquerda e o valor é agrupado: `1.234,56`. NÃO inclui o
/// símbolo "R$" (use `prefixText: 'R\$ '` no campo). É a máscara padrão de TODO
/// input de valor monetário (ficha de venda, proposta, etc.).
class CurrencyInputFormatter extends TextInputFormatter {
  CurrencyInputFormatter({this.maxDigits = 13});

  /// Limite de dígitos (centavos) — 13 ⇒ até 99.999.999.999,99.
  final int maxDigits;
  static final NumberFormat _fmt = NumberFormat('#,##0.00', 'pt_BR');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue(text: '');
    if (digits.length > maxDigits) digits = digits.substring(0, maxDigits);
    final value = int.parse(digits) / 100.0;
    final masked = _fmt.format(value);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }

  /// Formata um número já existente (prefill) no mesmo padrão da máscara.
  static String format(num? v) => v == null ? '' : _fmt.format(v);
}

/// Formatter para CPF
class CpfInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    
    if (text.isEmpty) {
      return newValue;
    }

    // Remove caracteres não numéricos
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    
    // Limita a 11 dígitos
    final limitedDigits = digits.length > 11 ? digits.substring(0, 11) : digits;
    
    // Aplica máscara
    final masked = Masks.cpf(limitedDigits);
    
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

/// Formatter para CNPJ
class CnpjInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    
    if (text.isEmpty) {
      return newValue;
    }

    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    final limitedDigits = digits.length > 14 ? digits.substring(0, 14) : digits;
    final masked = Masks.cnpj(limitedDigits);
    
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

/// Formatter para telefone
class PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    
    if (text.isEmpty) {
      return newValue;
    }

    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    final limitedDigits = digits.length > 11 ? digits.substring(0, 11) : digits;
    final masked = Masks.phone(limitedDigits);
    
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

/// Formatter para CEP
class CepInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    
    if (text.isEmpty) {
      return newValue;
    }

    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    final limitedDigits = digits.length > 8 ? digits.substring(0, 8) : digits;
    final masked = Masks.cep(limitedDigits);
    
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

/// Formatter para valor monetário
class MoneyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    
    if (text.isEmpty) {
      return newValue;
    }

    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    final masked = Masks.money(digits);
    
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

/// Formatter para porcentagem
class PercentageInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    
    if (text.isEmpty) {
      return newValue;
    }

    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    final masked = Masks.percentage(digits);
    
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

/// Formatter para data
class DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    
    if (text.isEmpty) {
      return newValue;
    }

    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    final limitedDigits = digits.length > 8 ? digits.substring(0, 8) : digits;
    final masked = Masks.date(limitedDigits);
    
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

/// Formatter para hora
class TimeInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    
    if (text.isEmpty) {
      return newValue;
    }

    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    final limitedDigits = digits.length > 4 ? digits.substring(0, 4) : digits;
    final masked = Masks.time(limitedDigits);
    
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

/// Formatter para apenas números
class NumericInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    
    if (text.isEmpty) {
      return newValue;
    }

    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}

/// Formatter para apenas letras
class LettersOnlyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    
    if (text.isEmpty) {
      return newValue;
    }

    final letters = text.replaceAll(RegExp(r'[^a-zA-ZáàâãéèêíìîóòôõúùûçñÁÀÂÃÉÈÊÍÌÎÓÒÔÕÚÙÛÇÑ\s]'), '');
    
    return TextEditingValue(
      text: letters,
      selection: TextSelection.collapsed(offset: letters.length),
    );
  }
}

/// Formatter com limite de caracteres
class LengthLimitingFormatter extends TextInputFormatter {
  final int maxLength;

  LengthLimitingFormatter(this.maxLength);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.length <= maxLength) {
      return newValue;
    }

    return TextEditingValue(
      text: newValue.text.substring(0, maxLength),
      selection: TextSelection.collapsed(offset: maxLength),
    );
  }
}

/// Formatter para capitalizar palavras
class CapitalizeInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    
    if (text.isEmpty) {
      return newValue;
    }

    final capitalized = Masks.capitalize(text);
    
    return TextEditingValue(
      text: capitalized,
      selection: newValue.selection,
    );
  }
}











