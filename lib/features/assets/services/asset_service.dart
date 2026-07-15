import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../models/asset_models.dart';

/// Serviço do Patrimônio — consome `/assets` (paridade com `assetApi.ts` do
/// imobx-front). Módulo `asset_management`; permissões `asset:*` no backend.
class AssetService {
  AssetService._();

  static final AssetService instance = AssetService._();
  final ApiService _api = ApiService.instance;

  // Endpoints (migração para api_constants é da fiação central).
  static const String _base = '/assets';
  static const String _stats = '/assets/stats';
  static const String _movementsCreate = '/assets/movements';
  static String _byId(String id) => '$_base/$id';
  static String _transfer(String id) => '$_base/$id/transfer';
  static String _movements(String id) => '$_base/$id/movements';

  Asset? _parseOne(dynamic raw) {
    if (raw is Map) {
      final m = Map<String, dynamic>.from(raw);
      final inner = m['data'];
      if (inner is Map && m['id'] == null) {
        return Asset.fromJson(Map<String, dynamic>.from(inner));
      }
      return Asset.fromJson(m);
    }
    return null;
  }

  /// `GET /assets` — lista paginada `{ assets, total }` com filtros.
  Future<ApiResponse<AssetListResult>> getAssets({
    AssetFilters filters = const AssetFilters(),
  }) async {
    try {
      final response = await _api.get<dynamic>(
        _base,
        queryParameters: filters.toQueryParams(),
      );
      if (response.success) {
        final raw = response.data;
        final result = raw is Map
            ? AssetListResult.fromJson(Map<String, dynamic>.from(raw))
            : raw is List
                ? AssetListResult(
                    assets: raw
                        .whereType<Map>()
                        .map((e) =>
                            Asset.fromJson(Map<String, dynamic>.from(e)))
                        .toList(),
                    total: raw.length,
                  )
                : AssetListResult.empty;
        return ApiResponse.success(
          data: result,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar patrimônio',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [ASSET] getAssets: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /assets/stats` — totais por status/categoria + valor agregado.
  Future<ApiResponse<AssetStats>> getStats() async {
    try {
      final response = await _api.get<Map<String, dynamic>>(_stats);
      if (response.success && response.data != null) {
        final raw = response.data!;
        final body = raw['data'] is Map<String, dynamic>
            ? raw['data'] as Map<String, dynamic>
            : raw;
        return ApiResponse.success(
          data: AssetStats.fromJson(body),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar estatísticas',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [ASSET] getStats: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /assets/:id` — detalhe.
  Future<ApiResponse<Asset>> getById(String id) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(_byId(id));
      final parsed = _parseOne(response.data);
      if (response.success && parsed != null) {
        return ApiResponse.success(
          data: parsed,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Patrimônio não encontrado',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [ASSET] getById: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /assets` — cria (permissão `asset:create`).
  Future<ApiResponse<Asset>> create(AssetDraft draft) async {
    try {
      final response =
          await _api.post<Map<String, dynamic>>(_base, body: draft.toJson());
      if (response.success) {
        return ApiResponse.success(
          data: _parseOne(response.data),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar patrimônio',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [ASSET] create: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `PATCH /assets/:id` — atualiza (permissão `asset:update`).
  Future<ApiResponse<Asset>> update(String id, AssetDraft draft) async {
    try {
      final response = await _api.patch<Map<String, dynamic>>(
        _byId(id),
        body: draft.toJson(),
      );
      if (response.success) {
        return ApiResponse.success(
          data: _parseOne(response.data),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar patrimônio',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [ASSET] update: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `DELETE /assets/:id` — dá baixa (permissão `asset:delete`).
  Future<ApiResponse<void>> delete(String id) async {
    try {
      final response = await _api.delete<dynamic>(_byId(id));
      if (response.success) {
        return ApiResponse.success(statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao dar baixa no patrimônio',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [ASSET] delete: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /assets/:id/transfer` — transfere para usuário e/ou imóvel
  /// (permissão `asset:transfer`).
  Future<ApiResponse<Asset>> transfer(
    String id, {
    String? toUserId,
    String? toPropertyId,
    required String reason,
    String? notes,
  }) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        _transfer(id),
        body: {
          if (toUserId != null && toUserId.isNotEmpty) 'toUserId': toUserId,
          if (toPropertyId != null && toPropertyId.isNotEmpty)
            'toPropertyId': toPropertyId,
          'reason': reason.trim(),
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        },
      );
      if (response.success) {
        return ApiResponse.success(
          data: _parseOne(response.data),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao transferir patrimônio',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [ASSET] transfer: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /assets/:id/movements` — histórico de movimentações.
  Future<ApiResponse<List<AssetMovement>>> getMovements(String id) async {
    try {
      final response = await _api.get<dynamic>(_movements(id));
      if (response.success) {
        final raw = response.data;
        List<dynamic>? list;
        if (raw is List) {
          list = raw;
        } else if (raw is Map) {
          final inner = Map<String, dynamic>.from(raw)['data'];
          if (inner is List) list = inner;
        }
        final movements = (list ?? const [])
            .whereType<Map>()
            .map((e) => AssetMovement.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        return ApiResponse.success(
          data: movements,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar movimentações',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [ASSET] getMovements: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /assets/movements` — movimentação manual
  /// (permissão `asset:manage_status`). Exposto por paridade com o web.
  Future<ApiResponse<AssetMovement>> createMovement(
      Map<String, dynamic> body) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        _movementsCreate,
        body: body,
      );
      if (response.success && response.data != null) {
        final raw = response.data!;
        final inner = raw['data'] is Map<String, dynamic>
            ? raw['data'] as Map<String, dynamic>
            : raw;
        return ApiResponse.success(
          data: AssetMovement.fromJson(inner),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar movimentação',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [ASSET] createMovement: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}
