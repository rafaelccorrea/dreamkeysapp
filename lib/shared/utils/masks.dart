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

  /// Aplica máscara de CNPJ: 00.000.000/0000-00
  static String cnpj(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length <= 2) {
      return digits;
    } else if (digits.length <= 5) {
      return '${digits.substring(0, 2)}.${digits.substring(2)}';
    } else if (digits.length <= 8) {
      return '${digits.substring(0, 2)}.${digits.substring(2, 5)}.${digits.substring(5)}';
    } else if (digits.length <= 12) {
      return '${digits.substring(0, 2)}.${digits.substring(2, 5)}.${digits.substring(5, 8)}/${digits.substring(8)}';
    } else {
      return '${digits.substring(0, 2)}.${digits.substring(2, 5)}.${digits.substring(5, 8)}/${digits.substring(8, 12)}-${digits.substring(12, 14)}';
    }
  }

  /// Remove máscara de CNPJ, retornando apenas números
  static String unmaskCnpj(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// Aplica máscara de telefone: (00) 0000-0000 ou (00) 00000-0000
  static String phone(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
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

  /// Remove máscara de telefone, retornando apenas números
  static String unmaskPhone(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
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








