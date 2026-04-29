import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/constants/api_constants.dart';
import 'api_service.dart';

/// Modelo de Permission
class Permission {
  final String id;
  final String name;
  final String description;
  final String category;
  final bool isActive;

  Permission({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.isActive,
  });

  factory Permission.fromJson(Map<String, dynamic> json) {
    return Permission(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      isActive: json['isActive'] as bool? ?? false,
    );
  }
}

/// Modelo de MyPermissions Response
class MyPermissionsResponse {
  final String userId;
  final String userName;
  final String userEmail;
  final List<Permission> permissions;
  final List<String> permissionNames;

  MyPermissionsResponse({
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.permissions,
    required this.permissionNames,
  });

  factory MyPermissionsResponse.fromJson(Map<String, dynamic> json) {
    return MyPermissionsResponse(
      userId: json['userId']?.toString() ?? '',
      userName: json['userName']?.toString() ?? '',
      userEmail: json['userEmail']?.toString() ?? '',
      permissions: json['permissions'] != null
          ? (json['permissions'] as List)
              .map((p) => Permission.fromJson(p as Map<String, dynamic>))
              .toList()
          : [],
      permissionNames: json['permissionNames'] != null
          ? List<String>.from((json['permissionNames'] as List).map((e) => e.toString()))
          : [],
    );
  }
}

/// Serviço para gerenciar permissões
class PermissionService {
  PermissionService._();

  static final PermissionService instance = PermissionService._();
  final ApiService _apiService = ApiService.instance;
  final _storage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  // Chaves de cache
  static const String _cacheKey = 'intellisys_permissions_cache';
  static const int _cacheValidityMinutes = 5;

  /// Busca permissões do usuário (my-permissions)
  Future<ApiResponse<MyPermissionsResponse>> getMyPermissions() async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConstants.myPermissions,
      );

      if (response.success && response.data != null) {
        final permissions = MyPermissionsResponse.fromJson(response.data!);
        debugPrint('✅ [PERMISSION_SERVICE] ${permissions.permissionNames.length} permissões carregadas');
        return ApiResponse.success(
          data: permissions,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar permissões',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [PERMISSION_SERVICE] Erro ao carregar permissões: $e');
      debugPrint('📚 [PERMISSION_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro ao carregar permissões: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Salva permissões no cache
  Future<void> savePermissionsCache({
    required List<String> permissions,
    required String role,
    required String? companyId,
    required String userId,
  }) async {
    try {
      final cacheData = {
        'permissions': permissions,
        'role': role,
        'companyId': companyId ?? '',
        'userId': userId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      await _storage.write(
        key: _cacheKey,
        value: jsonEncode(cacheData),
      );

      debugPrint('✅ [PERMISSION_SERVICE] Cache de permissões salvo');
    } catch (e) {
      debugPrint('❌ [PERMISSION_SERVICE] Erro ao salvar cache: $e');
    }
  }

  /// Obtém cache de permissões
  Future<Map<String, dynamic>?> getPermissionsCache() async {
    try {
      final cacheData = await _storage.read(key: _cacheKey);
      if (cacheData != null) {
        return jsonDecode(cacheData) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('❌ [PERMISSION_SERVICE] Erro ao ler cache: $e');
      return null;
    }
  }

  /// Verifica se o cache é válido
  Future<bool> isCacheValid({
    required String? currentCompanyId,
    required String currentUserId,
  }) async {
    try {
      final cache = await getPermissionsCache();
      if (cache == null) return false;

      final cacheCompanyId = cache['companyId']?.toString() ?? '';
      final cacheUserId = cache['userId']?.toString() ?? '';
      final cacheTimestamp = cache['timestamp'] as int? ?? 0;

      // Verificar se Company ID e User ID correspondem
      if (cacheCompanyId != (currentCompanyId ?? '') || cacheUserId != currentUserId) {
        return false;
      }

      // Verificar se não expirou
      final cacheAge = DateTime.now().millisecondsSinceEpoch - cacheTimestamp;
      final cacheAgeMinutes = cacheAge / (1000 * 60);
      
      return cacheAgeMinutes < _cacheValidityMinutes;
    } catch (e) {
      debugPrint('❌ [PERMISSION_SERVICE] Erro ao verificar cache: $e');
      return false;
    }
  }

  /// Limpa o cache de permissões
  Future<void> clearPermissionsCache() async {
    try {
      await _storage.delete(key: _cacheKey);
      debugPrint('✅ [PERMISSION_SERVICE] Cache de permissões limpo');
    } catch (e) {
      debugPrint('❌ [PERMISSION_SERVICE] Erro ao limpar cache: $e');
    }
  }
}

