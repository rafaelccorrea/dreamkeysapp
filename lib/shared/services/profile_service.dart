import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../core/constants/api_constants.dart';
import 'api_service.dart';
import 'secure_storage_service.dart';
import '../utils/avatar_url_resolver.dart';

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
      avatar: AvatarUrlResolver.resolve(json['avatar']?.toString()),
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
      debugPrint('👤 [PROFILE_SERVICE] Buscando perfil do usuário...');
      debugPrint('👤 [PROFILE_SERVICE] Endpoint: ${ApiConstants.profile}');
      
      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConstants.profile,
      );

      debugPrint('👤 [PROFILE_SERVICE] Resposta recebida:');
      debugPrint('👤 [PROFILE_SERVICE] - Success: ${response.success}');
      debugPrint('👤 [PROFILE_SERVICE] - Status Code: ${response.statusCode}');
      debugPrint('👤 [PROFILE_SERVICE] - Message: ${response.message}');
      debugPrint('👤 [PROFILE_SERVICE] - Data: ${response.data}');

      if (response.success && response.data != null) {
        try {
          final profile = Profile.fromJson(response.data!);
          debugPrint('✅ [PROFILE_SERVICE] Perfil parseado com sucesso:');
          debugPrint('✅ [PROFILE_SERVICE] - ID: ${profile.id}');
          debugPrint('✅ [PROFILE_SERVICE] - Nome: ${profile.name}');
          debugPrint('✅ [PROFILE_SERVICE] - Email: ${profile.email}');
          debugPrint('✅ [PROFILE_SERVICE] - Telefone: ${profile.phone ?? "N/A"}');
          debugPrint('✅ [PROFILE_SERVICE] - Celular: ${profile.cellphone ?? "N/A"}');
          debugPrint('✅ [PROFILE_SERVICE] - Avatar: ${profile.avatar ?? "N/A"}');
          debugPrint('✅ [PROFILE_SERVICE] - Role: ${profile.role}');
          debugPrint('✅ [PROFILE_SERVICE] - Tags: ${profile.tagIds?.length ?? 0} tags');
          
          return ApiResponse.success(
            data: profile,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [PROFILE_SERVICE] Erro ao parsear perfil: $e');
          debugPrint('❌ [PROFILE_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados do perfil: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      debugPrint('❌ [PROFILE_SERVICE] Erro ao buscar perfil: ${response.message}');
      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar perfil',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [PROFILE_SERVICE] Erro ao buscar perfil: $e');
      debugPrint('❌ [PROFILE_SERVICE] StackTrace: $stackTrace');
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
      debugPrint('✏️ [PROFILE_SERVICE] Atualizando perfil do usuário...');
      debugPrint('✏️ [PROFILE_SERVICE] Endpoint: ${ApiConstants.profile}');
      
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (phone != null) body['phone'] = phone;
      if (cellphone != null) body['cellphone'] = cellphone;
      if (tagIds != null) body['tagIds'] = tagIds;

      debugPrint('✏️ [PROFILE_SERVICE] Dados para atualização:');
      debugPrint('✏️ [PROFILE_SERVICE] - Name: ${name ?? "não alterado"}');
      debugPrint('✏️ [PROFILE_SERVICE] - Phone: ${phone ?? "não alterado"}');
      debugPrint('✏️ [PROFILE_SERVICE] - Cellphone: ${cellphone ?? "não alterado"}');
      debugPrint('✏️ [PROFILE_SERVICE] - TagIds: ${tagIds?.length ?? 0} tags');
      debugPrint('✏️ [PROFILE_SERVICE] - Body completo: $body');

      final response = await _apiService.put<Map<String, dynamic>>(
        ApiConstants.profile,
        body: body,
      );

      debugPrint('✏️ [PROFILE_SERVICE] Resposta recebida:');
      debugPrint('✏️ [PROFILE_SERVICE] - Success: ${response.success}');
      debugPrint('✏️ [PROFILE_SERVICE] - Status Code: ${response.statusCode}');
      debugPrint('✏️ [PROFILE_SERVICE] - Message: ${response.message}');
      debugPrint('✏️ [PROFILE_SERVICE] - Data: ${response.data}');

      if (response.success && response.data != null) {
        try {
          final profile = Profile.fromJson(response.data!);
          debugPrint('✅ [PROFILE_SERVICE] Perfil atualizado com sucesso:');
          debugPrint('✅ [PROFILE_SERVICE] - Nome: ${profile.name}');
          debugPrint('✅ [PROFILE_SERVICE] - Telefone: ${profile.phone ?? "N/A"}');
          debugPrint('✅ [PROFILE_SERVICE] - Celular: ${profile.cellphone ?? "N/A"}');
          debugPrint('✅ [PROFILE_SERVICE] - Tags: ${profile.tagIds?.length ?? 0} tags');
          
          return ApiResponse.success(
            data: profile,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [PROFILE_SERVICE] Erro ao parsear perfil atualizado: $e');
          debugPrint('❌ [PROFILE_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados do perfil: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      debugPrint('❌ [PROFILE_SERVICE] Erro ao atualizar perfil: ${response.message}');
      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar perfil',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [PROFILE_SERVICE] Erro ao atualizar perfil: $e');
      debugPrint('❌ [PROFILE_SERVICE] StackTrace: $stackTrace');
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
      debugPrint('🔐 [PROFILE_SERVICE] Alterando senha do usuário...');
      debugPrint('🔐 [PROFILE_SERVICE] Endpoint: ${ApiConstants.changePassword}');
      debugPrint('🔐 [PROFILE_SERVICE] - Current Password: ${currentPassword.isNotEmpty ? "***" : "vazio"}');
      debugPrint('🔐 [PROFILE_SERVICE] - New Password: ${newPassword.isNotEmpty ? "***" : "vazio"}');

      final response = await _apiService.put<Map<String, dynamic>>(
        ApiConstants.changePassword,
        body: {
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        },
      );

      debugPrint('🔐 [PROFILE_SERVICE] Resposta recebida:');
      debugPrint('🔐 [PROFILE_SERVICE] - Success: ${response.success}');
      debugPrint('🔐 [PROFILE_SERVICE] - Status Code: ${response.statusCode}');
      debugPrint('🔐 [PROFILE_SERVICE] - Message: ${response.message}');

      if (response.success) {
        debugPrint('✅ [PROFILE_SERVICE] Senha alterada com sucesso');
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }

      debugPrint('❌ [PROFILE_SERVICE] Erro ao alterar senha: ${response.message}');
      return ApiResponse.error(
        message: response.message ?? 'Erro ao alterar senha',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [PROFILE_SERVICE] Erro ao alterar senha: $e');
      debugPrint('❌ [PROFILE_SERVICE] StackTrace: $stackTrace');
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
        // O upload em si deu certo (2xx). Tentamos extrair a URL só para
        // diagnóstico/optimismo, mas NÃO falhamos se o backend não ecoar a URL
        // no formato esperado — o chamador recarrega o perfil (`getProfile`)
        // e obtém o avatar real resolvido pelo CDN. Falhar aqui era a causa do
        // bug "não consigo alterar a foto" (upload salvava, UI reportava erro).
        String avatarUrl = '';
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            final candidate = decoded['avatarUrl'] ??
                decoded['avatar'] ??
                (decoded['data'] is Map<String, dynamic>
                    ? (decoded['data']['avatar'] ??
                        decoded['data']['avatarUrl'])
                    : decoded['data']) ??
                (decoded['user'] is Map<String, dynamic>
                    ? decoded['user']['avatar']
                    : null);
            avatarUrl = candidate?.toString() ?? '';
          }
        } catch (e) {
          debugPrint('⚠️ [PROFILE_SERVICE] Corpo não-JSON no upload (ok): $e');
        }

        debugPrint('✅ [PROFILE_SERVICE] Avatar enviado (2xx). URL ecoada: '
            '${avatarUrl.isEmpty ? "(nenhuma — recarregando perfil)" : avatarUrl}');
        return ApiResponse.success(
          data: avatarUrl,
          statusCode: response.statusCode,
        );
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
      debugPrint('🗑️ [PROFILE_SERVICE] Removendo avatar do usuário...');
      debugPrint('🗑️ [PROFILE_SERVICE] Endpoint: ${ApiConstants.profile}');
      
      final response = await _apiService.put<Map<String, dynamic>>(
        ApiConstants.profile,
        body: {'avatar': null},
      );

      debugPrint('🗑️ [PROFILE_SERVICE] Resposta recebida:');
      debugPrint('🗑️ [PROFILE_SERVICE] - Success: ${response.success}');
      debugPrint('🗑️ [PROFILE_SERVICE] - Status Code: ${response.statusCode}');
      debugPrint('🗑️ [PROFILE_SERVICE] - Message: ${response.message}');
      debugPrint('🗑️ [PROFILE_SERVICE] - Data: ${response.data}');

      if (response.success && response.data != null) {
        try {
          final profile = Profile.fromJson(response.data!);
          debugPrint('✅ [PROFILE_SERVICE] Avatar removido com sucesso');
          debugPrint('✅ [PROFILE_SERVICE] - Avatar atual: ${profile.avatar ?? "removido"}');
          
          return ApiResponse.success(
            data: profile,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [PROFILE_SERVICE] Erro ao parsear perfil após remover avatar: $e');
          debugPrint('❌ [PROFILE_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados do perfil: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      debugPrint('❌ [PROFILE_SERVICE] Erro ao remover avatar: ${response.message}');
      return ApiResponse.error(
        message: response.message ?? 'Erro ao remover avatar',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [PROFILE_SERVICE] Erro ao remover avatar: $e');
      debugPrint('❌ [PROFILE_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Atualiza a visibilidade pública do perfil
  Future<ApiResponse<bool>> updatePublicVisibility(bool isVisible) async {
    try {
      debugPrint('👁️ [PROFILE_SERVICE] Atualizando visibilidade pública do perfil...');
      debugPrint('👁️ [PROFILE_SERVICE] Endpoint: ${ApiConstants.profile}/public-visibility');
      debugPrint('👁️ [PROFILE_SERVICE] - Nova visibilidade: $isVisible');
      
      final response = await _apiService.patch<Map<String, dynamic>>(
        '${ApiConstants.profile}/public-visibility',
        body: {'isAvailableForPublicSite': isVisible},
      );

      debugPrint('👁️ [PROFILE_SERVICE] Resposta recebida:');
      debugPrint('👁️ [PROFILE_SERVICE] - Success: ${response.success}');
      debugPrint('👁️ [PROFILE_SERVICE] - Status Code: ${response.statusCode}');
      debugPrint('👁️ [PROFILE_SERVICE] - Message: ${response.message}');
      debugPrint('👁️ [PROFILE_SERVICE] - Data: ${response.data}');

      if (response.success) {
        final isAvailable = response.data?['isAvailableForPublicSite'] as bool? ?? isVisible;
        debugPrint('✅ [PROFILE_SERVICE] Visibilidade atualizada com sucesso: $isAvailable');
        
        return ApiResponse.success(
          data: isAvailable,
          statusCode: response.statusCode,
        );
      }

      debugPrint('❌ [PROFILE_SERVICE] Erro ao atualizar visibilidade: ${response.message}');
      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar visibilidade',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [PROFILE_SERVICE] Erro ao atualizar visibilidade: $e');
      debugPrint('❌ [PROFILE_SERVICE] StackTrace: $stackTrace');
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
      debugPrint('🔐 [SESSION_SERVICE] Buscando sessões ativas do usuário...');
      debugPrint('🔐 [SESSION_SERVICE] Endpoint: ${ApiConstants.profile}/sessions');
      
      final response = await _apiService.get<dynamic>(
        '${ApiConstants.profile}/sessions',
      );

      debugPrint('🔐 [SESSION_SERVICE] Resposta recebida:');
      debugPrint('🔐 [SESSION_SERVICE] - Success: ${response.success}');
      debugPrint('🔐 [SESSION_SERVICE] - Status Code: ${response.statusCode}');
      debugPrint('🔐 [SESSION_SERVICE] - Message: ${response.message}');
      debugPrint('🔐 [SESSION_SERVICE] - Data type: ${response.data.runtimeType}');

      if (response.success && response.data != null) {
        try {
          dynamic dataToParse = response.data;
          
          // Se for um Map, tentar extrair 'data' ou 'results'
          if (dataToParse is Map<String, dynamic>) {
            debugPrint('🔐 [SESSION_SERVICE] Data é um Map, extraindo lista...');
            dataToParse = dataToParse['data'] ?? dataToParse['results'] ?? dataToParse;
          }

          // Garantir que é uma lista
          if (dataToParse is List) {
            debugPrint('🔐 [SESSION_SERVICE] Parseando ${dataToParse.length} sessões...');
            final sessions = dataToParse
                .map((e) => Session.fromJson(e as Map<String, dynamic>))
                .toList();
            
            debugPrint('✅ [SESSION_SERVICE] ${sessions.length} sessões parseadas com sucesso');
            for (var i = 0; i < sessions.length; i++) {
              final session = sessions[i];
              debugPrint('✅ [SESSION_SERVICE] Sessão ${i + 1}: ${session.device} - ${session.browser} (${session.isCurrent ? "atual" : "outra"})');
            }
            
            return ApiResponse.success(
              data: sessions,
              statusCode: response.statusCode,
            );
          }

          debugPrint('❌ [SESSION_SERVICE] Formato de resposta inválido: não é uma lista');
          return ApiResponse.error(
            message: 'Formato de resposta inválido',
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [SESSION_SERVICE] Erro ao parsear sessões: $e');
          debugPrint('❌ [SESSION_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      debugPrint('❌ [SESSION_SERVICE] Erro ao buscar sessões: ${response.message}');
      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar sessões',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [SESSION_SERVICE] Erro ao buscar sessões: $e');
      debugPrint('❌ [SESSION_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Encerra uma sessão específica
  Future<ApiResponse<void>> endSession(String sessionId) async {
    try {
      debugPrint('🔐 [SESSION_SERVICE] Encerrando sessão específica...');
      debugPrint('🔐 [SESSION_SERVICE] Endpoint: ${ApiConstants.profile}/sessions/$sessionId');
      debugPrint('🔐 [SESSION_SERVICE] - Session ID: $sessionId');
      
      final response = await _apiService.delete<dynamic>(
        '${ApiConstants.profile}/sessions/$sessionId',
      );

      debugPrint('🔐 [SESSION_SERVICE] Resposta recebida:');
      debugPrint('🔐 [SESSION_SERVICE] - Success: ${response.success}');
      debugPrint('🔐 [SESSION_SERVICE] - Status Code: ${response.statusCode}');
      debugPrint('🔐 [SESSION_SERVICE] - Message: ${response.message}');

      if (response.success) {
        debugPrint('✅ [SESSION_SERVICE] Sessão encerrada com sucesso');
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }

      debugPrint('❌ [SESSION_SERVICE] Erro ao encerrar sessão: ${response.message}');
      return ApiResponse.error(
        message: response.message ?? 'Erro ao encerrar sessão',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [SESSION_SERVICE] Erro ao encerrar sessão: $e');
      debugPrint('❌ [SESSION_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Encerra todas as outras sessões (exceto a atual)
  Future<ApiResponse<void>> endAllOtherSessions() async {
    try {
      debugPrint('🔐 [SESSION_SERVICE] Encerrando todas as outras sessões...');
      debugPrint('🔐 [SESSION_SERVICE] Endpoint: ${ApiConstants.profile}/sessions/others');
      
      final response = await _apiService.delete<dynamic>(
        '${ApiConstants.profile}/sessions/others',
      );

      debugPrint('🔐 [SESSION_SERVICE] Resposta recebida:');
      debugPrint('🔐 [SESSION_SERVICE] - Success: ${response.success}');
      debugPrint('🔐 [SESSION_SERVICE] - Status Code: ${response.statusCode}');
      debugPrint('🔐 [SESSION_SERVICE] - Message: ${response.message}');

      if (response.success) {
        debugPrint('✅ [SESSION_SERVICE] Todas as outras sessões encerradas com sucesso');
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }

      debugPrint('❌ [SESSION_SERVICE] Erro ao encerrar sessões: ${response.message}');
      return ApiResponse.error(
        message: response.message ?? 'Erro ao encerrar sessões',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [SESSION_SERVICE] Erro ao encerrar sessões: $e');
      debugPrint('❌ [SESSION_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}

