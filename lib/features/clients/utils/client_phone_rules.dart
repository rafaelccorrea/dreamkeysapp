/// Regras de telefone do cadastro de cliente — porte de
/// `imobx-front/src/utils/clientPhoneDuplicates.ts` e do `validatePhone` do
/// web. O back aplica a mesma checagem de duplicata
/// (`assertNoDuplicateClientPhones`), então validar aqui evita a mensagem
/// genérica do servidor.
class ClientPhoneEntry {
  const ClientPhoneEntry(this.key, this.label, this.value);

  final String key;
  final String label;
  final String? value;
}

class ClientPhoneDuplicate {
  const ClientPhoneDuplicate({
    required this.field,
    required this.label,
    required this.duplicateOf,
    required this.duplicateOfLabel,
  });

  final String field;
  final String label;
  final String duplicateOf;
  final String duplicateOfLabel;

  /// `getDuplicateClientPhoneMessage` do web — no meio da frase só a inicial
  /// vira minúscula: "WhatsApp" mantém a grafia da marca.
  String get message =>
      '$label não pode ser igual ao ${_inSentence(duplicateOfLabel)}';

  static String _inSentence(String label) {
    if (label.isEmpty || label.startsWith('WhatsApp')) return label;
    return label[0].toLowerCase() + label.substring(1);
  }
}

class ClientPhoneRules {
  ClientPhoneRules._();

  static const int _minPhoneDigits = 8;

  static String digits(String? value) =>
      (value ?? '').replaceAll(RegExp(r'\D'), '');

  /// `maskPhoneAuto` do web: com 12–13 dígitos começando em 55, usa os
  /// últimos 11; com 10/11, aplica a máscara; fora disso devolve o valor
  /// original para não truncar o telefone gravado.
  static String maskAuto(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return '';
    final d = digits(raw);
    if (d.length >= 12 && d.startsWith('55')) {
      return _mask(d.substring(d.length - 11));
    }
    if (d.length == 10 || d.length == 11) return _mask(d);
    return raw;
  }

  static String _mask(String d) {
    if (d.length == 11) {
      return '(${d.substring(0, 2)}) ${d.substring(2, 7)}-${d.substring(7)}';
    }
    return '(${d.substring(0, 2)}) ${d.substring(2, 6)}-${d.substring(6)}';
  }

  /// `validatePhone` do web: 10 ou 11 dígitos (DDD + número).
  static bool isValidPhone(String? value) {
    final d = digits(value);
    return d.length >= 10 && d.length <= 11;
  }

  static String _normalizeKey(String phone) {
    var d = digits(phone);
    if (d.startsWith('55') && d.length >= 12) d = d.substring(2);
    if (d.length == 10 && RegExp(r'^[6789]').hasMatch(d.substring(2))) {
      d = '${d.substring(0, 2)}9${d.substring(2)}';
    }
    return d;
  }

  static bool _comparable(String? value) =>
      value != null &&
      value.trim().isNotEmpty &&
      digits(value).length >= _minPhoneDigits;

  /// Primeiro par de telefones equivalentes, na ordem das entradas.
  static ClientPhoneDuplicate? findDuplicate(List<ClientPhoneEntry> entries) {
    final seen = <ClientPhoneEntry>[];
    for (final entry in entries) {
      if (!_comparable(entry.value)) continue;
      for (final previous in seen) {
        if (_normalizeKey(entry.value!) == _normalizeKey(previous.value!)) {
          return ClientPhoneDuplicate(
            field: entry.key,
            label: entry.label,
            duplicateOf: previous.key,
            duplicateOfLabel: previous.label,
          );
        }
      }
      seen.add(entry);
    }
    return null;
  }

  /// `buildClientContactPhoneEntries` do web.
  static List<ClientPhoneEntry> contactEntries({
    String? phone,
    String? secondaryPhone,
    String? whatsapp,
  }) {
    return [
      ClientPhoneEntry('phone', 'Telefone principal', phone),
      ClientPhoneEntry('secondaryPhone', 'Telefone secundário', secondaryPhone),
      ClientPhoneEntry('whatsapp', 'WhatsApp', whatsapp),
    ];
  }

  /// `buildClientProfilePhoneEntries` do web (cliente + cônjuge).
  static List<ClientPhoneEntry> profileEntries({
    String? phone,
    String? secondaryPhone,
    String? whatsapp,
    String? spousePhone,
    String? spouseWhatsapp,
  }) {
    return [
      ...contactEntries(
        phone: phone,
        secondaryPhone: secondaryPhone,
        whatsapp: whatsapp,
      ),
      ClientPhoneEntry('spousePhone', 'Telefone do cônjuge', spousePhone),
      ClientPhoneEntry('spouseWhatsapp', 'WhatsApp do cônjuge', spouseWhatsapp),
    ];
  }

  /// `applyDuplicateClientPhoneErrors`: a mensagem vai para os dois campos.
  static Map<String, String> duplicateErrors(List<ClientPhoneEntry> entries) {
    final dup = findDuplicate(entries);
    if (dup == null) return const {};
    return {
      dup.field: dup.message,
      if (dup.duplicateOf != dup.field) dup.duplicateOf: dup.message,
    };
  }

  /// `validateEmail` do web.
  static bool isValidEmail(String value) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim());

  /// `validateCPF` do web (dígitos verificadores).
  static bool isValidCpf(String value) {
    final cpf = digits(value);
    if (cpf.length != 11) return false;
    if (RegExp(r'^(\d)\1{10}$').hasMatch(cpf)) return false;
    var sum = 0;
    for (var i = 0; i < 9; i++) {
      sum += int.parse(cpf[i]) * (10 - i);
    }
    var rem = (sum * 10) % 11;
    if (rem == 10 || rem == 11) rem = 0;
    if (rem != int.parse(cpf[9])) return false;
    sum = 0;
    for (var i = 0; i < 10; i++) {
      sum += int.parse(cpf[i]) * (11 - i);
    }
    rem = (sum * 10) % 11;
    if (rem == 10 || rem == 11) rem = 0;
    return rem == int.parse(cpf[10]);
  }
}
