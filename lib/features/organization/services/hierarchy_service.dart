import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../models/org_user_model.dart';

/// Serviço da Hierarquia de gestores — consome `/admin/users` (lista para a
/// árvore) e `/hierarchy/*` (atribuição), paridade com `usersApi` +
/// `hierarchyApi` do imobx-front. Ambas as rotas são de ADMIN/MASTER.
class HierarchyService {
  HierarchyService._();

  static final HierarchyService instance = HierarchyService._();
  final ApiService _api = ApiService.instance;

  // Endpoints privados da feature.
  static const String _adminUsers = '/admin/users';
  static const String _assignManager = '/hierarchy/assign-manager';
  static const String _removeManager = '/hierarchy/remove-manager';

  List<OrgUser> _parseUsers(dynamic raw) {
    final list = raw is Map
        ? raw['data']
        : raw; // aceita `{data:[...]}` ou lista crua
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => OrgUser.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// `GET /admin/users?limit=100` — usuários da empresa (árvore + atribuição).
  Future<ApiResponse<List<OrgUser>>> getUsers({String? role}) async {
    try {
      final response = await _api.get<dynamic>(
        _adminUsers,
        queryParameters: {
          'limit': '100',
          'role': ?role,
        },
      );
      if (response.success) {
        return ApiResponse.success(
          data: _parseUsers(response.data),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar usuários',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [HIERARCHY] getUsers: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /hierarchy/assign-manager` — atribui gestor a colaboradores.
  Future<ApiResponse<String>> assignManager({
    required List<String> userIds,
    required String managerId,
  }) async {
    try {
      final response = await _api.post<dynamic>(_assignManager, body: {
        'userIds': userIds,
        'managerId': managerId,
      });
      if (response.success) {
        final raw = response.data;
        final message = raw is Map
            ? raw['message']?.toString() ?? 'Gestor atribuído com sucesso!'
            : 'Gestor atribuído com sucesso!';
        return ApiResponse.success(
          data: message,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao atribuir gestor',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [HIERARCHY] assignManager: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /hierarchy/remove-manager` — desvincula colaboradores do gestor.
  Future<ApiResponse<String>> removeManager({
    required List<String> userIds,
  }) async {
    try {
      final response = await _api.post<dynamic>(_removeManager, body: {
        'userIds': userIds,
      });
      if (response.success) {
        final raw = response.data;
        final message = raw is Map
            ? raw['message']?.toString() ?? 'Gestor removido com sucesso!'
            : 'Gestor removido com sucesso!';
        return ApiResponse.success(
          data: message,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao remover gestor',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [HIERARCHY] removeManager: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}
