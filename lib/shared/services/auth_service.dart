import 'package:flutter/foundation.dart';
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
      token: json['access_token'] as String? ?? json['token'] as String? ?? json['accessToken'] as String? ?? '',
      refreshToken: json['refresh_token'] as String? ?? json['refreshToken'] as String? ?? '',
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
  final String? companyId;
  final String createdAt;
  final String? updatedAt;
  final String? managerId;
  final List<String>? managedUserIds;
  final bool? isAvailableForPublicSite;
  final String? document;
  final String? phone;

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.owner,
    this.avatar,
    this.companyId,
    required this.createdAt,
    this.updatedAt,
    this.managerId,
    this.managedUserIds,
    this.isAvailableForPublicSite,
    this.document,
    this.phone,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      owner: json['owner'] as bool? ?? false,
      avatar: json['avatar']?.toString(),
      companyId: json['companyId']?.toString() ?? json['company_id']?.toString(),
      createdAt: json['createdAt']?.toString() ?? json['created_at']?.toString() ?? '',
      updatedAt: json['updatedAt']?.toString() ?? json['updated_at']?.toString(),
      managerId: json['managerId']?.toString() ?? json['manager_id']?.toString(),
      managedUserIds: json['managedUserIds'] != null
          ? List<String>.from((json['managedUserIds'] as List).map((e) => e.toString()))
          : json['managed_user_ids'] != null
              ? List<String>.from((json['managed_user_ids'] as List).map((e) => e.toString()))
              : null,
      isAvailableForPublicSite:
          json['isAvailableForPublicSite'] as bool? ?? json['is_available_for_public_site'] as bool? ?? false,
      document: json['document']?.toString(),
      phone: json['phone']?.toString(),
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
      // Log para debug
      debugPrint('📥 [AUTH_SERVICE] Response data: ${response.data}');
      
      try {
        final loginResponse = LoginResponse.fromJson(response.data!);
        // Define o token no serviço de API
        _apiService.setToken(loginResponse.token);
        return ApiResponse.success(
          data: loginResponse,
          statusCode: response.statusCode,
        );
      } catch (e, stackTrace) {
        debugPrint('❌ [AUTH_SERVICE] Erro ao fazer parse do LoginResponse: $e');
        debugPrint('📚 [AUTH_SERVICE] StackTrace: $stackTrace');
        debugPrint('📋 [AUTH_SERVICE] JSON recebido: ${response.data}');
        rethrow;
      }
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
