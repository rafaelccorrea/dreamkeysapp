import 'package:flutter/foundation.dart';
import '../../core/constants/api_constants.dart';
import 'api_service.dart';

/// Modelos de dados de Perfil
class Profile {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? cellphone;
  final String? avatar;
  final String role;
  final String companyId;
  final String? companyName;
  final bool isAvailableForPublicSite;
  final UserPreferences preferences;
  final String createdAt;
  final String updatedAt;

  Profile({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.cellphone,
    this.avatar,
    required this.role,
    required this.companyId,
    this.companyName,
    required this.isAvailableForPublicSite,
    required this.preferences,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString(),
      cellphone: json['cellphone']?.toString(),
      avatar: json['avatar']?.toString(),
      role: json['role']?.toString() ?? '',
      companyId: json['companyId']?.toString() ?? json['company_id']?.toString() ?? '',
      companyName: json['companyName']?.toString() ?? json['company_name']?.toString(),
      isAvailableForPublicSite: json['isAvailableForPublicSite'] as bool? ?? json['is_available_for_public_site'] as bool? ?? false,
      preferences: json['preferences'] != null
          ? UserPreferences.fromJson(json['preferences'] as Map<String, dynamic>)
          : UserPreferences.empty(),
      createdAt: json['createdAt']?.toString() ?? json['created_at']?.toString() ?? '',
      updatedAt: json['updatedAt']?.toString() ?? json['updated_at']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'phone': phone,
      'cellphone': cellphone,
    };
  }
}

class UserPreferences {
  final NotificationPreferences notifications;
  final String language;
  final String timezone;

  UserPreferences({
    required this.notifications,
    required this.language,
    required this.timezone,
  });

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences(
      notifications: NotificationPreferences.fromJson(
        json['notifications'] as Map<String, dynamic>? ?? {},
      ),
      language: json['language']?.toString() ?? 'pt-BR',
      timezone: json['timezone']?.toString() ?? 'America/Sao_Paulo',
    );
  }

  factory UserPreferences.empty() {
    return UserPreferences(
      notifications: NotificationPreferences.empty(),
      language: 'pt-BR',
      timezone: 'America/Sao_Paulo',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'notifications': notifications.toJson(),
      'language': language,
      'timezone': timezone,
    };
  }
}

class NotificationPreferences {
  final bool email;
  final bool push;
  final bool sms;

  NotificationPreferences({
    required this.email,
    required this.push,
    required this.sms,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      email: json['email'] as bool? ?? true,
      push: json['push'] as bool? ?? true,
      sms: json['sms'] as bool? ?? false,
    );
  }

  factory NotificationPreferences.empty() {
    return NotificationPreferences(
      email: true,
      push: true,
      sms: false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'push': push,
      'sms': sms,
    };
  }
}

/// Serviço de Perfil
class ProfileService {
  ProfileService._();

  static final ProfileService instance = ProfileService._();
  final ApiService _apiService = ApiService.instance;

  /// Busca o perfil do usuário
  Future<ApiResponse<Profile>> getProfile() async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConstants.profile,
      );

      if (response.success && response.data != null) {
        final profile = Profile.fromJson(response.data!);
        return ApiResponse.success(
          data: profile,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar perfil',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROFILE_SERVICE] Erro ao buscar perfil: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Atualiza o perfil do usuário
  Future<ApiResponse<Profile>> updateProfile({
    String? name,
    String? phone,
    String? cellphone,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (phone != null) body['phone'] = phone;
      if (cellphone != null) body['cellphone'] = cellphone;

      final response = await _apiService.put<Map<String, dynamic>>(
        ApiConstants.profile,
        body: body,
      );

      if (response.success && response.data != null) {
        final profile = Profile.fromJson(response.data!);
        return ApiResponse.success(
          data: profile,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar perfil',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROFILE_SERVICE] Erro ao atualizar perfil: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Altera a senha do usuário
  Future<ApiResponse<void>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final response = await _apiService.put<Map<String, dynamic>>(
        ApiConstants.changePassword,
        body: {
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        },
      );

      if (response.success) {
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao alterar senha',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROFILE_SERVICE] Erro ao alterar senha: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Upload de avatar
  Future<ApiResponse<String>> uploadAvatar(String imagePath) async {
    try {
      // TODO: Implementar upload de arquivo multipart
      // Por enquanto retornar erro
      return ApiResponse.error(
        message: 'Upload de avatar não implementado ainda',
        statusCode: 501,
      );
    } catch (e) {
      debugPrint('❌ [PROFILE_SERVICE] Erro ao fazer upload de avatar: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}

