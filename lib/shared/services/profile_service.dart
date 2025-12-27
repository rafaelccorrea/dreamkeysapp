import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../core/constants/api_constants.dart';
import 'api_service.dart';
import 'secure_storage_service.dart';

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
  final List<String>? tagIds;
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
    this.tagIds,
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
      tagIds: json['tagIds'] != null
          ? (json['tagIds'] as List<dynamic>).map((e) => e.toString()).toList()
          : json['tag_ids'] != null
              ? (json['tag_ids'] as List<dynamic>).map((e) => e.toString()).toList()
              : null,
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
    List<String>? tagIds,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (phone != null) body['phone'] = phone;
      if (cellphone != null) body['cellphone'] = cellphone;
      if (tagIds != null) body['tagIds'] = tagIds;

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
  Future<ApiResponse<String>> uploadAvatar(File imageFile) async {
    try {
      debugPrint('📸 [PROFILE_SERVICE] Iniciando upload de avatar');

      final token = await SecureStorageService.instance.getAccessToken();
      if (token == null || token.isEmpty) {
        return ApiResponse.error(
          message: 'Token de autenticação não encontrado',
          statusCode: 401,
        );
      }

      // Validar tamanho do arquivo (máximo 5MB)
      final fileSize = await imageFile.length();
      if (fileSize > 5 * 1024 * 1024) {
        return ApiResponse.error(
          message: 'Arquivo muito grande. Tamanho máximo: 5MB',
          statusCode: 400,
        );
      }

      final uri = Uri.parse('${ApiConstants.baseApiUrl}${ApiConstants.avatar}');
      final request = http.MultipartRequest('POST', uri);

      // Headers
      request.headers['Authorization'] = 'Bearer $token';

      // Adicionar arquivo
      final fileStream = http.ByteStream(imageFile.openRead());
      final fileLength = await imageFile.length();
      final multipartFile = http.MultipartFile(
        'avatar',
        fileStream,
        fileLength,
        filename: imageFile.path.split('/').last,
      );
      request.files.add(multipartFile);

      debugPrint('📸 [PROFILE_SERVICE] Enviando arquivo: ${imageFile.path} (${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB)');

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
          final avatarUrl = jsonData['avatarUrl']?.toString() ?? jsonData['avatar']?.toString() ?? jsonData['data']?.toString() ?? '';
          
          if (avatarUrl.isEmpty) {
            debugPrint('⚠️ [PROFILE_SERVICE] Resposta não contém URL do avatar');
            return ApiResponse.error(
              message: 'Resposta inválida do servidor',
              statusCode: response.statusCode,
            );
          }

          debugPrint('✅ [PROFILE_SERVICE] Avatar enviado com sucesso: $avatarUrl');
          return ApiResponse.success(
            data: avatarUrl,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [PROFILE_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar resposta: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      String errorMessage = 'Erro ao fazer upload do avatar';
      try {
        final errorData = jsonDecode(response.body) as Map<String, dynamic>?;
        errorMessage = errorData?['message']?.toString() ?? errorMessage;
      } catch (e) {
        errorMessage = response.body.isNotEmpty ? response.body : errorMessage;
      }

      debugPrint('❌ [PROFILE_SERVICE] Erro no upload: ${response.statusCode} - $errorMessage');
      return ApiResponse.error(
        message: errorMessage,
        statusCode: response.statusCode,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [PROFILE_SERVICE] Erro ao fazer upload de avatar: $e');
      debugPrint('❌ [PROFILE_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Remove o avatar do usuário
  Future<ApiResponse<Profile>> removeAvatar() async {
    try {
      final response = await _apiService.put<Map<String, dynamic>>(
        ApiConstants.profile,
        body: {'avatar': null},
      );

      if (response.success && response.data != null) {
        final profile = Profile.fromJson(response.data!);
        return ApiResponse.success(
          data: profile,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao remover avatar',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROFILE_SERVICE] Erro ao remover avatar: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Atualiza a visibilidade pública do perfil
  Future<ApiResponse<bool>> updatePublicVisibility(bool isVisible) async {
    try {
      final response = await _apiService.patch<Map<String, dynamic>>(
        '${ApiConstants.profile}/public-visibility',
        body: {'isAvailableForPublicSite': isVisible},
      );

      if (response.success) {
        final isAvailable = response.data?['isAvailableForPublicSite'] as bool? ?? isVisible;
        return ApiResponse.success(
          data: isAvailable,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar visibilidade',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROFILE_SERVICE] Erro ao atualizar visibilidade: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}

/// Modelo de Sessão
class Session {
  final String id;
  final String userId;
  final String device;
  final String browser;
  final String? operatingSystem;
  final String? location;
  final String ipAddress;
  final bool isCurrent;
  final String lastActivity;
  final String createdAt;

  Session({
    required this.id,
    required this.userId,
    required this.device,
    required this.browser,
    this.operatingSystem,
    this.location,
    required this.ipAddress,
    required this.isCurrent,
    required this.lastActivity,
    required this.createdAt,
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? json['user_id']?.toString() ?? '',
      device: json['device']?.toString() ?? '',
      browser: json['browser']?.toString() ?? '',
      operatingSystem: json['operatingSystem']?.toString() ?? json['operating_system']?.toString(),
      location: json['location']?.toString(),
      ipAddress: json['ipAddress']?.toString() ?? json['ip_address']?.toString() ?? '',
      isCurrent: json['isCurrent'] as bool? ?? json['is_current'] as bool? ?? false,
      lastActivity: json['lastActivity']?.toString() ?? json['last_activity']?.toString() ?? '',
      createdAt: json['createdAt']?.toString() ?? json['created_at']?.toString() ?? '',
    );
  }
}

/// Serviço de Sessões
class SessionService {
  SessionService._();

  static final SessionService instance = SessionService._();
  final ApiService _apiService = ApiService.instance;

  /// Lista todas as sessões ativas do usuário
  Future<ApiResponse<List<Session>>> getSessions() async {
    try {
      final response = await _apiService.get<dynamic>(
        '${ApiConstants.profile}/sessions',
      );

      if (response.success && response.data != null) {
        try {
          dynamic dataToParse = response.data;
          
          // Se for um Map, tentar extrair 'data' ou 'results'
          if (dataToParse is Map<String, dynamic>) {
            dataToParse = dataToParse['data'] ?? dataToParse['results'] ?? dataToParse;
          }

          // Garantir que é uma lista
          if (dataToParse is List) {
            final sessions = (dataToParse as List)
                .map((e) => Session.fromJson(e as Map<String, dynamic>))
                .toList();
            
            return ApiResponse.success(
              data: sessions,
              statusCode: response.statusCode,
            );
          }

          return ApiResponse.error(
            message: 'Formato de resposta inválido',
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [SESSION_SERVICE] Erro ao parsear sessões: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar sessões',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [SESSION_SERVICE] Erro ao buscar sessões: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Encerra uma sessão específica
  Future<ApiResponse<void>> endSession(String sessionId) async {
    try {
      final response = await _apiService.delete<dynamic>(
        '${ApiConstants.profile}/sessions/$sessionId',
      );

      if (response.success) {
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao encerrar sessão',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [SESSION_SERVICE] Erro ao encerrar sessão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Encerra todas as outras sessões (exceto a atual)
  Future<ApiResponse<void>> endAllOtherSessions() async {
    try {
      final response = await _apiService.delete<dynamic>(
        '${ApiConstants.profile}/sessions/others',
      );

      if (response.success) {
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao encerrar sessões',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [SESSION_SERVICE] Erro ao encerrar sessões: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}

