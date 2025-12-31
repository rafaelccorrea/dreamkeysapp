import 'package:flutter/services.dart';
import 'masks.dart';

/// Formatters customizados para TextFields

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










