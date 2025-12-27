/// Validações reutilizáveis para formulários
class Validators {
  Validators._();

  /// Valida se o campo não está vazio
  static String? required(String? value, {String? message}) {
    if (value == null || value.trim().isEmpty) {
      return message ?? 'Este campo é obrigatório';
    }
    return null;
  }

  /// Valida email
  static String? email(String? value, {String? message}) {
    if (value == null || value.trim().isEmpty) {
      return message ?? 'Email é obrigatório';
    }

    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );

    if (!emailRegex.hasMatch(value.trim())) {
      return message ?? 'Por favor, insira um email válido';
    }

    return null;
  }

  /// Valida email obrigatório (combina required + email)
  static String? requiredEmail(String? value, {String? message}) {
    final requiredError = required(value, message: message);
    if (requiredError != null) {
      return requiredError;
    }
    return email(value, message: message);
  }

  /// Valida senha
  static String? password(String? value, {
    String? message,
    int minLength = 6,
    String? minLengthMessage,
  }) {
    if (value == null || value.isEmpty) {
      return message ?? 'Senha é obrigatória';
    }

    if (value.length < minLength) {
      return minLengthMessage ??
          'A senha deve ter pelo menos $minLength caracteres';
    }

    return null;
  }

  /// Valida confirmação de senha
  static String? confirmPassword(
    String? value,
    String? originalPassword, {
    String? message,
  }) {
    if (value == null || value.isEmpty) {
      return message ?? 'Confirmação de senha é obrigatória';
    }

    if (value != originalPassword) {
      return message ?? 'As senhas não coincidem';
    }

    return null;
  }

  /// Valida CPF
  static String? cpf(String? value, {String? message}) {
    if (value == null || value.trim().isEmpty) {
      return message ?? 'CPF é obrigatório';
    }

    // Remove caracteres não numéricos
    final cpfDigits = value.replaceAll(RegExp(r'[^0-9]'), '');

    if (cpfDigits.length != 11) {
      return message ?? 'CPF deve conter 11 dígitos';
    }

    // Valida se todos os dígitos são iguais
    if (RegExp(r'^(\d)\1+$').hasMatch(cpfDigits)) {
      return message ?? 'CPF inválido';
    }

    // Valida dígitos verificadores
    if (!_isValidCpf(cpfDigits)) {
      return message ?? 'CPF inválido';
    }

    return null;
  }

  /// Valida CNPJ
  static String? cnpj(String? value, {String? message}) {
    if (value == null || value.trim().isEmpty) {
      return message ?? 'CNPJ é obrigatório';
    }

    // Remove caracteres não numéricos
    final cnpjDigits = value.replaceAll(RegExp(r'[^0-9]'), '');

    if (cnpjDigits.length != 14) {
      return message ?? 'CNPJ deve conter 14 dígitos';
    }

    // Valida se todos os dígitos são iguais
    if (RegExp(r'^(\d)\1+$').hasMatch(cnpjDigits)) {
      return message ?? 'CNPJ inválido';
    }

    // Valida dígitos verificadores
    if (!_isValidCnpj(cnpjDigits)) {
      return message ?? 'CNPJ inválido';
    }

    return null;
  }

  /// Valida telefone/celular
  static String? phone(String? value, {String? message, bool required = true}) {
    if (value == null || value.trim().isEmpty) {
      if (required) {
        return message ?? 'Telefone é obrigatório';
      }
      return null;
    }

    // Remove caracteres não numéricos
    final phoneDigits = value.replaceAll(RegExp(r'[^0-9]'), '');

    // Aceita telefone (10 dígitos) ou celular (11 dígitos)
    if (phoneDigits.length < 10 || phoneDigits.length > 11) {
      return message ?? 'Telefone inválido';
    }

    return null;
  }

  /// Valida CEP
  static String? cep(String? value, {String? message}) {
    if (value == null || value.trim().isEmpty) {
      return message ?? 'CEP é obrigatório';
    }

    // Remove caracteres não numéricos
    final cepDigits = value.replaceAll(RegExp(r'[^0-9]'), '');

    if (cepDigits.length != 8) {
      return message ?? 'CEP deve conter 8 dígitos';
    }

    return null;
  }

  /// Valida número mínimo de caracteres
  static String? minLength(
    String? value,
    int min, {
    String? message,
  }) {
    if (value == null || value.trim().isEmpty) {
      return message ?? 'Este campo é obrigatório';
    }

    if (value.trim().length < min) {
      return message ?? 'Deve conter pelo menos $min caracteres';
    }

    return null;
  }

  /// Valida número máximo de caracteres
  static String? maxLength(
    String? value,
    int max, {
    String? message,
  }) {
    if (value == null || value.isEmpty) {
      return null;
    }

    if (value.length > max) {
      return message ?? 'Deve conter no máximo $max caracteres';
    }

    return null;
  }

  /// Valida número (inteiro)
  static String? number(String? value, {String? message}) {
    if (value == null || value.trim().isEmpty) {
      return message ?? 'Este campo é obrigatório';
    }

    if (int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), '')) == null) {
      return message ?? 'Por favor, insira um número válido';
    }

    return null;
  }

  /// Valida valor monetário
  static String? money(String? value, {String? message}) {
    if (value == null || value.trim().isEmpty) {
      return message ?? 'Este campo é obrigatório';
    }

    // Remove tudo exceto números e vírgula/ponto
    final cleanValue = value.replaceAll(RegExp(r'[^0-9,.]'), '');
    
    if (cleanValue.isEmpty) {
      return message ?? 'Por favor, insira um valor válido';
    }

    // Tenta converter para double
    final numericValue = double.tryParse(
      cleanValue.replaceAll(',', '.'),
    );

    if (numericValue == null || numericValue <= 0) {
      return message ?? 'Por favor, insira um valor válido';
    }

    return null;
  }

  /// Valida se é uma URL válida
  static String? url(String? value, {String? message, bool required = false}) {
    if (value == null || value.trim().isEmpty) {
      if (required) {
        return message ?? 'URL é obrigatória';
      }
      return null;
    }

    final urlRegex = RegExp(
      r'^https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)$',
    );

    if (!urlRegex.hasMatch(value.trim())) {
      return message ?? 'Por favor, insira uma URL válida';
    }

    return null;
  }

  /// Validação customizada com função
  static String? custom<T>(
    T? value,
    String? Function(T) validator, {
    bool required = false,
  }) {
    if (value == null || (value is String && value.trim().isEmpty)) {
      if (required) {
        return 'Este campo é obrigatório';
      }
      return null;
    }

    return validator(value);
  }

  /// Combina múltiplas validações
  static String? combine(List<String? Function()> validators) {
    for (final validator in validators) {
      final result = validator();
      if (result != null) {
        return result;
      }
    }
    return null;
  }

  // Métodos auxiliares privados

  static bool _isValidCpf(String cpf) {
    if (cpf.length != 11) return false;

    // Valida primeiro dígito verificador
    int sum = 0;
    for (int i = 0; i < 9; i++) {
      sum += int.parse(cpf[i]) * (10 - i);
    }
    int digit1 = (sum * 10) % 11;
    if (digit1 == 10) digit1 = 0;
    if (digit1 != int.parse(cpf[9])) return false;

    // Valida segundo dígito verificador
    sum = 0;
    for (int i = 0; i < 10; i++) {
      sum += int.parse(cpf[i]) * (11 - i);
    }
    int digit2 = (sum * 10) % 11;
    if (digit2 == 10) digit2 = 0;
    if (digit2 != int.parse(cpf[10])) return false;

    return true;
  }

  static bool _isValidCnpj(String cnpj) {
    if (cnpj.length != 14) return false;

    // Valida primeiro dígito verificador
    final weights1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    int sum = 0;
    for (int i = 0; i < 12; i++) {
      sum += int.parse(cnpj[i]) * weights1[i];
    }
    int digit1 = sum % 11 < 2 ? 0 : 11 - (sum % 11);
    if (digit1 != int.parse(cnpj[12])) return false;

    // Valida segundo dígito verificador
    final weights2 = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    sum = 0;
    for (int i = 0; i < 13; i++) {
      sum += int.parse(cnpj[i]) * weights2[i];
    }
    int digit2 = sum % 11 < 2 ? 0 : 11 - (sum % 11);
    if (digit2 != int.parse(cnpj[13])) return false;

    return true;
  }
}



