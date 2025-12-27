import '../../core/constants/api_constants.dart';
import 'api_service.dart';

/// Modelos de dados
class LoginRequest {
  final String email;
  final String password;

  LoginRequest({
    required this.email,
    required this.password,
  });

  Map<String, dynamic> toJson() => {
        'email': email,
        'password': password,
      };
}

class LoginResponse {
  final User user;
  final String token;
  final String refreshToken;

  LoginResponse({
    required this.user,
    required this.token,
    required this.refreshToken,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      token: json['token'] as String,
      refreshToken: json['refreshToken'] as String,
    );
  }
}

class User {
  final String id;
  final String name;
  final String email;
  final String role;
  final bool owner;
  final String? avatar;
  final String companyId;
  final String createdAt;
  final String updatedAt;
  final String? managerId;
  final List<String>? managedUserIds;
  final bool? isAvailableForPublicSite;

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.owner,
    this.avatar,
    required this.companyId,
    required this.createdAt,
    required this.updatedAt,
    this.managerId,
    this.managedUserIds,
    this.isAvailableForPublicSite,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      role: json['role'] as String,
      owner: json['owner'] as bool? ?? false,
      avatar: json['avatar'] as String?,
      companyId: json['companyId'] as String,
      createdAt: json['createdAt'] as String,
      updatedAt: json['updatedAt'] as String,
      managerId: json['managerId'] as String?,
      managedUserIds: json['managedUserIds'] != null
          ? List<String>.from(json['managedUserIds'] as List)
          : null,
      isAvailableForPublicSite:
          json['isAvailableForPublicSite'] as bool? ?? false,
    );
  }
}

class CheckTwoFactorResponse {
  final bool requires2FA;
  final bool emailExists;
  final bool hasTwoFactorConfigured;

  CheckTwoFactorResponse({
    required this.requires2FA,
    required this.emailExists,
    required this.hasTwoFactorConfigured,
  });

  factory CheckTwoFactorResponse.fromJson(Map<String, dynamic> json) {
    return CheckTwoFactorResponse(
      requires2FA: json['requires2FA'] as bool? ?? false,
      emailExists: json['emailExists'] as bool? ?? false,
      hasTwoFactorConfigured:
          json['hasTwoFactorConfigured'] as bool? ?? false,
    );
  }
}

/// Serviço de autenticação
class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();
  final ApiService _apiService = ApiService.instance;

  /// Realiza o login
  Future<ApiResponse<LoginResponse>> login(LoginRequest request) async {
    final response = await _apiService.post<Map<String, dynamic>>(
      ApiConstants.login,
      body: request.toJson(),
    );

    if (response.success && response.data != null) {
      final loginResponse = LoginResponse.fromJson(response.data!);
      // Define o token no serviço de API
      _apiService.setToken(loginResponse.token);
      return ApiResponse.success(
        data: loginResponse,
        statusCode: response.statusCode,
      );
    }

    return ApiResponse.error(
      message: response.message ?? 'Erro ao realizar login',
      statusCode: response.statusCode,
      data: response.error,
    );
  }

  /// Verifica se o email requer 2FA
  Future<ApiResponse<CheckTwoFactorResponse>> check2FA(String email) async {
    final response = await _apiService.get<Map<String, dynamic>>(
      ApiConstants.check2FA,
      queryParameters: {'email': email},
    );

    if (response.success && response.data != null) {
      final checkResponse =
          CheckTwoFactorResponse.fromJson(response.data!);
      return ApiResponse.success(
        data: checkResponse,
        statusCode: response.statusCode,
      );
    }

    return ApiResponse.error(
      message: response.message ?? 'Erro ao verificar 2FA',
      statusCode: response.statusCode,
      data: response.error,
    );
  }

  /// Verifica código 2FA
  Future<ApiResponse<LoginResponse>> verify2FA({
    required String tempToken,
    required String code,
  }) async {
    final response = await _apiService.post<Map<String, dynamic>>(
      ApiConstants.verify2FA,
      body: {
        'tempToken': tempToken,
        'code': code,
      },
    );

    if (response.success && response.data != null) {
      final loginResponse = LoginResponse.fromJson(response.data!);
      _apiService.setToken(loginResponse.token);
      return ApiResponse.success(
        data: loginResponse,
        statusCode: response.statusCode,
      );
    }

    return ApiResponse.error(
      message: response.message ?? 'Código 2FA inválido',
      statusCode: response.statusCode,
      data: response.error,
    );
  }

  /// Realiza logout
  Future<ApiResponse<void>> logout() async {
    final response = await _apiService.post<void>(ApiConstants.logout);
    _apiService.clearToken();
    return response;
  }

  /// Solicita recuperação de senha
  Future<ApiResponse<void>> forgotPassword(String email) async {
    return await _apiService.post<void>(
      ApiConstants.forgotPassword,
      body: {'email': email},
    );
  }

  /// Reseta a senha
  Future<ApiResponse<void>> resetPassword({
    required String token,
    required String password,
    required String confirmPassword,
  }) async {
    return await _apiService.post<void>(
      ApiConstants.resetPassword,
      body: {
        'token': token,
        'password': password,
        'confirmPassword': confirmPassword,
      },
    );
  }
}
