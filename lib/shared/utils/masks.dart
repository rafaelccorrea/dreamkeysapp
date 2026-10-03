/// Máscaras de formatação para campos de texto
class Masks {
  Masks._();

  /// Aplica máscara de CPF: 000.000.000-00
  static String cpf(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length <= 3) {
      return digits;
    } else if (digits.length <= 6) {
      return '${digits.substring(0, 3)}.${digits.substring(3)}';
    } else if (digits.length <= 9) {
      return '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6)}';
    } else {
      return '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6, 9)}-${digits.substring(9, 11)}';
    }
  }

  /// Remove máscara de CPF, retornando apenas números
  static String unmaskCpf(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// Aplica máscara de CNPJ: XX.XXX.XXX/XXXX-XX.
  ///
  /// Aceita o CNPJ ALFANUMÉRICO (Receita/SERPRO, 2026): os 12 primeiros
  /// caracteres podem ser letras ou números e os 2 últimos (DV) são sempre
  /// números. Letras são postas em maiúsculas — paridade com `maskCNPJ` do
  /// web (`masks.ts`). CNPJ só numérico continua igual.
  static String cnpj(String value) {
    final raw = unmaskCnpj(value);
    // Na posição dos DVs (13º e 14º) só entram dígitos.
    final b = StringBuffer();
    var count = 0;
    for (var i = 0; i < raw.length && count < 14; i++) {
      final ch = raw[i];
      final isDigit = ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57;
      if (count >= 12 && !isDigit) continue;
      if (count == 2 || count == 5) b.write('.');
      if (count == 8) b.write('/');
      if (count == 12) b.write('-');
      b.write(ch);
      count++;
    }
    return b.toString();
  }

  /// Remove a máscara do CNPJ: só letras (maiúsculas) e números — o CNPJ
  /// alfanumérico perde as letras se a limpeza for só por dígitos.
  static String unmaskCnpj(String value) {
    return value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  /// `true` quando o documento digitado é CPF: só dígitos e até 11. Com
  /// letra (CNPJ alfanumérico) ou mais de 11 caracteres, é CNPJ — mesma
  /// regra do `formatDocument` do web.
  static bool isCpfDocument(String value) {
    final clean = unmaskCnpj(value);
    if (RegExp(r'[A-Z]').hasMatch(clean)) return false;
    return clean.length <= 11;
  }

  /// Máscara dinâmica CPF ↔ CNPJ (aceita CNPJ alfanumérico).
  static String cpfOrCnpj(String value) {
    return isCpfDocument(value) ? cpf(value) : cnpj(value);
  }

  /// Dígitos de um telefone brasileiro SEM o DDI 55.
  ///
  /// Número colado/preenchido com DDI (`+55 11 98765-4321`, `5511987654321`)
  /// tem 12 ou 13 dígitos começando por 55; sem tirar o DDI, a máscara de 11
  /// dígitos cortava o FIM do número e gravava "(55) 11987-6543" (transv-20).
  /// Mesma regra do web (`whatsappAiPreAtendimento.ts`/`whatsappBusca.ts`):
  /// só remove quando sobram 10 ou 11 dígitos — um número de 11 dígitos com
  /// DDD 55 (RS) fica intacto.
  static String brPhoneDigits(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if ((digits.length == 12 || digits.length == 13) &&
        digits.startsWith('55')) {
      return digits.substring(2);
    }
    return digits;
  }

  /// Aplica máscara de telefone: (00) 0000-0000 ou (00) 00000-0000
  /// (remove o DDI 55 de números completos — ver [brPhoneDigits]).
  static String phone(String value) {
    final digits = brPhoneDigits(value);
    if (digits.length <= 2) {
      return digits.isEmpty ? '' : '($digits';
    } else if (digits.length <= 6) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2)}';
    } else if (digits.length <= 10) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2, 6)}-${digits.substring(6)}';
    } else {
      // Celular com 11 dígitos
      return '(${digits.substring(0, 2)}) ${digits.substring(2, 7)}-${digits.substring(7, 11)}';
    }
  }

  /// Remove máscara de telefone, retornando apenas números (sem o DDI 55
  /// de um número completo — ver [brPhoneDigits]).
  static String unmaskPhone(String value) {
    return brPhoneDigits(value);
  }

  /// Aplica máscara de CEP: 00000-000
  static String cep(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length <= 5) {
      return digits;
    } else {
      return '${digits.substring(0, 5)}-${digits.substring(5, 8)}';
    }
  }

  /// Remove máscara de CEP, retornando apenas números
  static String unmaskCep(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// Aplica máscara de valor monetário: R$ 0,00
  static String money(String value) {
    // Remove tudo exceto números
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    
    if (digits.isEmpty) return '';

    // Converte para valor monetário
    final amount = int.parse(digits) / 100;
    final formatted = amount.toStringAsFixed(2).replaceAll('.', ',');

    return 'R\$ $formatted';
  }

  /// Remove máscara de valor monetário, retornando apenas números (em centavos)
  static int unmaskMoney(String value) {
    final cleanValue = value.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(cleanValue) ?? 0;
  }

  /// Aplica máscara de porcentagem: 0,00%
  static String percentage(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    
    if (digits.isEmpty) return '';

    final amount = int.parse(digits) / 100;
    final formatted = amount.toStringAsFixed(2).replaceAll('.', ',');

    return '$formatted%';
  }

  /// Remove máscara de porcentagem
  static double unmaskPercentage(String value) {
    final cleanValue = value.replaceAll(RegExp(r'[^0-9]'), '');
    return (int.tryParse(cleanValue) ?? 0) / 100;
  }

  /// Aplica máscara de data: 00/00/0000
  static String date(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length <= 2) {
      return digits;
    } else if (digits.length <= 4) {
      return '${digits.substring(0, 2)}/${digits.substring(2)}';
    } else {
      return '${digits.substring(0, 2)}/${digits.substring(2, 4)}/${digits.substring(4, 8)}';
    }
  }

  /// Remove máscara de data
  static String unmaskDate(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// Aplica máscara de hora: 00:00
  static String time(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length <= 2) {
      return digits;
    } else {
      return '${digits.substring(0, 2)}:${digits.substring(2, 4)}';
    }
  }

  /// Remove máscara de hora
  static String unmaskTime(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// Remove todas as máscaras de um valor, retornando apenas números
  static String unmaskAll(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// Capitaliza primeira letra de cada palavra
  static String capitalize(String value) {
    if (value.isEmpty) return value;
    
    return value.split(' ').map((word) {
      if (word.isEmpty) return word;
      return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
    }).join(' ');
  }

  /// Remove acentos de uma string
  static String removeAccents(String value) {
    const withAccents = 'àáâãäèéêëìíîïòóôõöùúûüçñÀÁÂÃÄÈÉÊËÌÍÎÏÒÓÔÕÖÙÚÛÜÇÑ';
    const withoutAccents = 'aaaaaeeeeeiiiiooooouuuucnAAAAAEEEEEIIIIOOOOOUUUUCN';
    
    String result = value;
    for (int i = 0; i < withAccents.length; i++) {
      result = result.replaceAll(withAccents[i], withoutAccents[i]);
    }
    return result;
  }
}











