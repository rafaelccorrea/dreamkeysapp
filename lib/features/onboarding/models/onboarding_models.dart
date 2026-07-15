/// Modelos do fluxo de onboarding — registro de conta e primeira empresa.
///
/// Paridade com o `imobx-front`:
///   - `RegisterForm.tsx` + `useAuth.register` → `POST /auth/register-with-confirmation`
///   - `EmailConfirmationPage.tsx` → `POST /auth/confirm-registration`
///   - `CreateFirstCompanyPage.tsx` + `companyApi.createCompany` → `POST /companies`
library;

/// Payload do registro de conta (`RegisterWithConfirmationDto` no backend).
///
/// O web envia documento/telefone FORMATADOS (o backend remove a máscara do
/// telefone via `@Transform`); espelhamos o mesmo comportamento.
class RegisterAccountRequest {
  final String name;
  final String email;
  final String password;
  final String document;
  final String phone;

  const RegisterAccountRequest({
    required this.name,
    required this.email,
    required this.password,
    required this.document,
    required this.phone,
  });

  Map<String, dynamic> toJson() {
    return {
      // O web força minúsculas no campo nome (RegisterForm.tsx).
      'name': name.trim().toLowerCase(),
      'email': email.trim().toLowerCase(),
      'password': password,
      'document': document.trim(),
      'phone': phone.trim(),
    };
  }
}

/// Resposta do `POST /auth/register-with-confirmation`
/// (`RegisterWithConfirmationResponseDto`).
class RegisterConfirmationInfo {
  final bool success;
  final String message;
  final String email;
  final int expirationHours;

  const RegisterConfirmationInfo({
    required this.success,
    required this.message,
    required this.email,
    required this.expirationHours,
  });

  factory RegisterConfirmationInfo.fromJson(Map<String, dynamic> json) {
    return RegisterConfirmationInfo(
      success: json['success'] == true,
      message: json['message']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      expirationHours: switch (json['expirationHours']) {
        final int v => v,
        final num v => v.toInt(),
        final String v => int.tryParse(v) ?? 24,
        _ => 24,
      },
    );
  }
}

/// Resposta do `POST /auth/confirm-registration`
/// (`ConfirmUserRegistrationResponseDto`).
class ConfirmRegistrationResult {
  final bool success;
  final String message;
  final String? userName;
  final String? userEmail;

  const ConfirmRegistrationResult({
    required this.success,
    required this.message,
    this.userName,
    this.userEmail,
  });

  factory ConfirmRegistrationResult.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    final userMap =
        user is Map ? Map<String, dynamic>.from(user) : const <String, dynamic>{};
    return ConfirmRegistrationResult(
      success: json['success'] == true,
      message: json['message']?.toString() ?? '',
      userName: userMap['name']?.toString(),
      userEmail: userMap['email']?.toString(),
    );
  }
}

/// Payload de criação da primeira empresa.
///
/// Espelha o objeto montado no `onSubmit` do `CreateFirstCompanyPage.tsx`:
/// `address` é a concatenação "rua, número[, complemento]".
class CreateFirstCompanyRequest {
  final String name;
  final String cnpj;
  final String corporateName;
  final String email;
  final String phone;
  final String street;
  final String number;
  final String? complement;
  final String neighborhood;
  final String city;
  final String state;
  final String zipCode;

  const CreateFirstCompanyRequest({
    required this.name,
    required this.cnpj,
    required this.corporateName,
    required this.email,
    required this.phone,
    required this.street,
    required this.number,
    this.complement,
    required this.neighborhood,
    required this.city,
    required this.state,
    required this.zipCode,
  });

  Map<String, dynamic> toJson() {
    final comp = complement?.trim();
    final address = [
      '${street.trim()}, ${number.trim()}',
      if (comp != null && comp.isNotEmpty) comp,
    ].join(', ');

    return {
      'name': name.trim(),
      'cnpj': cnpj.trim(),
      'corporateName': corporateName.trim(),
      'email': email.trim().toLowerCase(),
      'phone': phone.trim(),
      'address': address,
      'city': city.trim(),
      'state': state.trim().toUpperCase(),
      'zipCode': zipCode.trim(),
    };
  }
}

/// Empresa recém-criada (subconjunto do `Company` devolvido pelo backend).
class CreatedCompany {
  final String id;
  final String name;
  final String cnpj;
  final String? corporateName;
  final String? email;
  final String? phone;
  final String? city;
  final String? state;
  final String? logoUrl;

  const CreatedCompany({
    required this.id,
    required this.name,
    required this.cnpj,
    this.corporateName,
    this.email,
    this.phone,
    this.city,
    this.state,
    this.logoUrl,
  });

  factory CreatedCompany.fromJson(Map<String, dynamic> json) {
    return CreatedCompany(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      cnpj: json['cnpj']?.toString() ?? '',
      corporateName: json['corporateName']?.toString(),
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
      city: json['city']?.toString(),
      state: json['state']?.toString(),
      // O backend pode devolver `logo` ou `logoUrl` (normalização do web).
      logoUrl: (json['logoUrl'] ?? json['logo'])?.toString(),
    );
  }
}
