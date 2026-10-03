import 'package:flutter/services.dart';

/// Máscaras e validações da ficha de proposta — cópia fiel das funções de
/// `imobx-front/src/utils/masks.ts` usadas pelo `CreatePurchaseProposalPage`
/// (o web é a fonte da verdade). Ficam aqui, e não no
/// `shared/utils/input_formatters.dart`, porque o formatter compartilhado de
/// CPF corta em 11 dígitos e a ficha precisa aceitar CNPJ.
class ProposalRules {
  ProposalRules._();

  static String digits(String v) => v.replaceAll(RegExp(r'\D'), '');

  // ─── Máscaras ───────────────────────────────────────────────────────────

  /// `maskCPF`: 000.000.000-00.
  static String maskCpf(String value) {
    final d = digits(value);
    final s = d.length > 11 ? d.substring(0, 11) : d;
    if (s.length <= 3) return s;
    if (s.length <= 6) return '${s.substring(0, 3)}.${s.substring(3)}';
    if (s.length <= 9) {
      return '${s.substring(0, 3)}.${s.substring(3, 6)}.${s.substring(6)}';
    }
    return '${s.substring(0, 3)}.${s.substring(3, 6)}.${s.substring(6, 9)}'
        '-${s.substring(9)}';
  }

  /// `maskCPFouCNPJ`: até 11 dígitos = CPF; acima, CNPJ 00.000.000/0000-00.
  static String maskCpfOuCnpj(String value) {
    final d = digits(value);
    if (d.length <= 11) return maskCpf(d);
    final s = d.length > 14 ? d.substring(0, 14) : d;
    final b = StringBuffer()
      ..write(s.substring(0, 2))
      ..write('.')
      ..write(s.substring(2, 5))
      ..write('.')
      ..write(s.substring(5, 8))
      ..write('/')
      ..write(s.substring(8, s.length < 12 ? s.length : 12));
    if (s.length > 12) b.write('-${s.substring(12)}');
    return b.toString();
  }

  /// `maskRG`: só dígitos, 00.000.000-0.
  static String maskRg(String value) {
    final d = digits(value);
    final s = d.length > 9 ? d.substring(0, 9) : d;
    if (s.length <= 2) return s;
    if (s.length <= 5) return '${s.substring(0, 2)}.${s.substring(2)}';
    if (s.length <= 8) {
      return '${s.substring(0, 2)}.${s.substring(2, 5)}.${s.substring(5)}';
    }
    return '${s.substring(0, 2)}.${s.substring(2, 5)}.${s.substring(5, 8)}'
        '-${s.substring(8)}';
  }

  /// `maskPhoneAuto`: (00) 0000-0000 ou (00) 00000-0000; 12–13 dígitos com
  /// 55 na frente viram celular com os últimos 11.
  static String maskPhone(String value) {
    var d = digits(value);
    if (d.length >= 12 && d.startsWith('55')) d = d.substring(d.length - 11);
    if (d.length > 11) d = d.substring(0, 11);
    if (d.isEmpty) return '';
    if (d.length <= 2) return '($d';
    final ddd = d.substring(0, 2);
    final rest = d.substring(2);
    if (d.length <= 6) return '($ddd) $rest';
    if (d.length <= 10) {
      return '($ddd) ${rest.substring(0, 4)}-${rest.substring(4)}';
    }
    return '($ddd) ${rest.substring(0, 5)}-${rest.substring(5)}';
  }

  /// `maskCEP`: 00000-000.
  static String maskCep(String value) {
    final d = digits(value);
    final s = d.length > 8 ? d.substring(0, 8) : d;
    if (s.length <= 5) return s;
    return '${s.substring(0, 5)}-${s.substring(5)}';
  }

  /// Valor em pt-BR com 2 casas ("1.234,56") — `fmtNum` do web ao hidratar.
  static String formatDecimal(num? v) {
    if (v == null) return '';
    final neg = v < 0;
    final fixed = v.abs().toStringAsFixed(2);
    final parts = fixed.split('.');
    final intPart = parts[0];
    final b = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) b.write('.');
      b.write(intPart[i]);
    }
    return '${neg ? '-' : ''}$b,${parts[1]}';
  }

  /// `getNumericValue`: "1.234,56" → 1234.56; vazio → null.
  static double? parseDecimal(String v) {
    final clean = v.replaceAll(RegExp(r'[^\d,]'), '');
    if (clean.isEmpty) return null;
    return double.tryParse(clean.replaceAll(',', '.'));
  }

  // ─── Validações ─────────────────────────────────────────────────────────

  /// `validateCPF` (dígitos verificadores; rejeita sequências repetidas).
  static bool isValidCpf(String value) {
    final c = digits(value);
    if (c.length != 11) return false;
    if (RegExp(r'^(\d)\1{10}$').hasMatch(c)) return false;
    int dv(int len) {
      var sum = 0;
      for (var i = 0; i < len; i++) {
        sum += int.parse(c[i]) * (len + 1 - i);
      }
      var r = (sum * 10) % 11;
      if (r == 10) r = 0;
      return r;
    }

    return dv(9) == int.parse(c[9]) && dv(10) == int.parse(c[10]);
  }

  /// `validateCNPJ` (pesos oficiais 5..2/9..2). Só dígitos: a máscara do
  /// web (`maskCPFouCNPJ`) remove letras antes de validar.
  static bool isValidCnpj(String value) {
    final c = digits(value);
    if (c.length != 14) return false;
    if (RegExp(r'^(\d)\1{13}$').hasMatch(c)) return false;
    int dv(String base) {
      const weights = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
      final start = 13 - base.length;
      var sum = 0;
      for (var i = 0; i < base.length; i++) {
        sum += int.parse(base[i]) * weights[start + i];
      }
      final r = sum % 11;
      return r < 2 ? 0 : 11 - r;
    }

    final d1 = dv(c.substring(0, 12));
    final d2 = dv('${c.substring(0, 12)}$d1');
    return c.substring(12) == '$d1$d2';
  }

  /// `validateCPFouCNPJ`: 11 dígitos = CPF, 14 = CNPJ, resto inválido.
  static bool isValidCpfOuCnpj(String value) {
    final d = digits(value);
    if (d.length == 11) return isValidCpf(d);
    if (d.length == 14) return isValidCnpj(d);
    return false;
  }

  /// `validateEmail`.
  static bool isValidEmail(String v) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v);

  /// `validatePhone`: 10 ou 11 dígitos.
  static bool isValidPhone(String v) {
    final d = digits(v);
    return d.length >= 10 && d.length <= 11;
  }

  /// `validateCEP`: 8 dígitos.
  static bool isValidCep(String v) => digits(v).length == 8;

  /// `validatePercentage`: 0–100.
  static bool isValidPercentage(String v) {
    final n = double.tryParse(v.replaceFirst(',', '.')) ?? 0;
    return n >= 0 && n <= 100;
  }

  /// `validatePositiveDays`: inteiro 1–365.
  static bool isValidDays(String v) {
    final n = int.tryParse(digits(v));
    if (n == null) return false;
    return n >= 1 && n <= 365;
  }

  /// Idade completa como o web: `floor((hoje - nascimento) / 365.25 dias)`.
  static int ageInYears(DateTime birth, DateTime today) {
    final days = today.difference(birth).inMilliseconds /
        Duration.millisecondsPerDay;
    return (days / 365.25).floor();
  }
}

/// Formatter genérico que reaplica uma máscara do web a cada tecla.
class ProposalMaskFormatter extends TextInputFormatter {
  ProposalMaskFormatter(this.mask);

  final String Function(String) mask;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final masked = mask(newValue.text);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }

  static final cpfOuCnpj = ProposalMaskFormatter(ProposalRules.maskCpfOuCnpj);
  static final cpf = ProposalMaskFormatter(ProposalRules.maskCpf);
  static final rg = ProposalMaskFormatter(ProposalRules.maskRg);
  static final phone = ProposalMaskFormatter(ProposalRules.maskPhone);
  static final cep = ProposalMaskFormatter(ProposalRules.maskCep);
}

/// `maskEmail` do web: sem espaços, minúsculas (só e-mails do proponente e
/// do cônjuge do proponente, como no web).
class ProposalEmailFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final t = newValue.text.replaceAll(RegExp(r'\s'), '').toLowerCase();
    if (t == newValue.text) return newValue;
    return TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }
}

/// `maskPercentage` do web: inteiro até 100 + até 2 casas ("6", "6,", "6,5").
class ProposalPercentFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final value = newValue.text;
    final normalized = value.replaceFirst(',', '.');
    final parts = normalized.split('.');
    if (parts.length > 2) return oldValue;
    var intPart = parts[0].replaceAll(RegExp(r'\D'), '');
    if (intPart.length > 3) intPart = intPart.substring(0, 3);
    var decPart =
        parts.length > 1 ? parts[1].replaceAll(RegExp(r'\D'), '') : '';
    if (decPart.length > 2) decPart = decPart.substring(0, 2);
    final n = intPart.isEmpty ? 0 : int.parse(intPart);
    final limited = n > 100 ? '100' : intPart;
    final hasSep = value.contains(',') || value.contains('.');
    final out = (!hasSep && decPart.isEmpty)
        ? limited
        : (decPart.isNotEmpty ? '$limited,$decPart' : '$limited,');
    return TextEditingValue(
      text: out,
      selection: TextSelection.collapsed(offset: out.length),
    );
  }
}

/// Opções fixas do web (`AppSelect` de estado civil e regime de casamento
/// em `CreatePurchaseProposalPage.tsx`): mesmos valores gravados e os
/// MESMOS rótulos da tela do web.
const List<(String, String)> kProposalMaritalStatus = [
  ('solteiro', 'Solteiro(a)'),
  ('casado', 'Casado(a)'),
  ('divorciado', 'Divorciado(a)'),
  ('viuvo', 'Viúvo(a)'),
  ('uniao_estavel', 'União Estável'),
];

const List<(String, String)> kProposalMarriageRegime = [
  ('comunhao_parcial', 'Comunhão Parcial'),
  ('comunhao_universal', 'Comunhão Universal'),
  ('separacao_total', 'Separação Total'),
  ('participacao_final', 'Participação Final'),
];

const List<String> kProposalUfs = [
  'AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MT', 'MS',
  'MG', 'PA', 'PB', 'PR', 'PE', 'PI', 'RJ', 'RN', 'RS', 'RO', 'RR', 'SC',
  'SP', 'SE', 'TO',
];
