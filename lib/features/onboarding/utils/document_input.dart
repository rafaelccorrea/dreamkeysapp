import 'package:flutter/services.dart';

import '../../../shared/utils/validators.dart';

/// Utilidades de documento do onboarding — CPF e CNPJ (inclusive o CNPJ
/// ALFANUMÉRICO vigente desde 2026), com paridade com `masks.ts` do
/// `imobx-front` (`formatCPF`, `formatCNPJ`, `validateCNPJ`).
class OnboardingDocumentUtils {
  OnboardingDocumentUtils._();

  /// Remove tudo que não é letra/número e põe letras em maiúsculas.
  static String cleanAlnum(String value) {
    return value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  /// Máscara de CPF: `000.000.000-00`.
  static String maskCpf(String value) {
    final d = value.replaceAll(RegExp(r'[^0-9]'), '');
    final digits = d.length > 11 ? d.substring(0, 11) : d;
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 3 || i == 6) b.write('.');
      if (i == 9) b.write('-');
      b.write(digits[i]);
    }
    return b.toString();
  }

  /// Máscara de CNPJ: `XX.XXX.XXX/XXXX-XX` — aceita letras (alfanumérico).
  static String maskCnpj(String value) {
    final c = cleanAlnum(value);
    final chars = c.length > 14 ? c.substring(0, 14) : c;
    final b = StringBuffer();
    for (var i = 0; i < chars.length; i++) {
      if (i == 2 || i == 5) b.write('.');
      if (i == 8) b.write('/');
      if (i == 12) b.write('-');
      b.write(chars[i]);
    }
    return b.toString();
  }

  /// Máscara dinâmica CPF ↔ CNPJ — paridade com `formatDocument` do
  /// `RegisterForm.tsx`: com letras vira CNPJ; até 11 dígitos, CPF;
  /// acima disso, CNPJ.
  static String maskDocument(String value) {
    final cleaned = cleanAlnum(value);
    final hasLetters = RegExp(r'[A-Z]').hasMatch(cleaned);
    if (hasLetters) return maskCnpj(value);
    if (cleaned.length <= 11) return maskCpf(value);
    return maskCnpj(value);
  }

  /// Validação do CNPJ alfanumérico (dígitos verificadores) — porta fiel do
  /// `validateCNPJ` de `masks.ts`: letras valem `ASCII - 48`, os 2 últimos
  /// caracteres são SEMPRE numéricos.
  static bool isValidCnpj(String value) {
    final clean = cleanAlnum(value);
    if (clean.length != 14) return false;
    if (!RegExp(r'^[A-Z0-9]{12}[0-9]{2}$').hasMatch(clean)) return false;

    int charValue(String char) => char.codeUnitAt(0) - 48;

    int calculateDv(String base) {
      const weights = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
      final startIndex = 13 - base.length;
      var sum = 0;
      for (var i = 0; i < base.length; i++) {
        sum += charValue(base[i]) * weights[startIndex + i];
      }
      final remainder = sum % 11;
      return (remainder == 0 || remainder == 1) ? 0 : 11 - remainder;
    }

    if (calculateDv(clean.substring(0, 12)) != int.parse(clean[12])) {
      return false;
    }
    if (calculateDv(clean.substring(0, 13)) != int.parse(clean[13])) {
      return false;
    }
    return true;
  }

  /// Valida CPF (11 dígitos) OU CNPJ (14 caracteres alfanuméricos).
  /// Retorna a mensagem de erro ou `null` quando válido.
  static String? validateDocument(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'CPF/CNPJ é obrigatório';
    }
    final clean = cleanAlnum(value);
    final hasLetters = RegExp(r'[A-Z]').hasMatch(clean);

    if (!hasLetters && clean.length == 11) {
      return Validators.cpf(value);
    }
    if (clean.length == 14) {
      return isValidCnpj(value) ? null : 'CNPJ inválido';
    }
    return 'Informe um CPF (11 dígitos) ou CNPJ (14 caracteres)';
  }

  /// Valida apenas CNPJ (alfanumérico). Retorna mensagem ou `null`.
  static String? validateCnpjField(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'CNPJ é obrigatório';
    }
    if (cleanAlnum(value).length != 14) {
      return 'CNPJ deve ter 14 caracteres';
    }
    return isValidCnpj(value)
        ? null
        : 'CNPJ inválido (dígitos verificadores incorretos)';
  }
}

/// Formatter dinâmico CPF ↔ CNPJ (aceita CNPJ alfanumérico).
class DocumentInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    final masked = OnboardingDocumentUtils.maskDocument(newValue.text);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

/// Formatter de CNPJ alfanumérico: `XX.XXX.XXX/XXXX-XX`.
class AlnumCnpjInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    final masked = OnboardingDocumentUtils.maskCnpj(newValue.text);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

/// Formatter que força minúsculas (o web faz `toLowerCase` no nome).
class LowercaseInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toLowerCase());
  }
}

/// Formatter que força maiúsculas (UF do endereço).
class UppercaseInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
