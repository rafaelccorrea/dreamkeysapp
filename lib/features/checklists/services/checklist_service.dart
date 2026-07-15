import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../models/checklist_models.dart';

/// Serviço dos Checklists standalone — consome `/sale-checklists` (paridade
/// com `checklist.service.ts` do imobx-front; módulo `checklist_management`
/// no backend). A listagem NÃO é paginada — o backend devolve o array
/// completo, já escopado pela hierarquia de acesso do usuário.
class ChecklistService {
  ChecklistService._();

  static final ChecklistService instance = ChecklistService._();
  final ApiService _api = ApiService.instance;

  // Endpoints (migração para api_constants é da fiação central).
  static const String _base = '/sale-checklists';
  static String _byId(String id) => '$_base/$id';
  static String _itemStatus(String id) => '$_base/$id/item-status';

  List<Checklist> _parseList(dynamic raw) {
    List<dynamic>? list;
    if (raw is List) {
      list = raw;
    } else if (raw is Map) {
      final m = Map<String, dynamic>.from(raw);
      final inner = m['checklists'] ?? m['data'] ?? m['items'];
      if (inner is List) list = inner;
    }
    if (list == null) return const [];
    return list
        .whereType<Map>()
        .map((e) => Checklist.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Checklist? _parseOne(dynamic raw) {
    if (raw is Map) {
      final m = Map<String, dynamic>.from(raw);
      final inner = m['data'];
      if (inner is Map && m['id'] == null) {
        return Checklist.fromJson(Map<String, dynamic>.from(inner));
      }
      return Checklist.fromJson(m);
    }
    return null;
  }

  /// `GET /sale-checklists` — lista com filtros opcionais.
  Future<ApiResponse<List<Checklist>>> getChecklists({
    ChecklistFilters filters = const ChecklistFilters(),
  }) async {
    try {
      final params = filters.toQueryParams();
      final response = await _api.get<dynamic>(
        _base,
        queryParameters: params.isEmpty ? null : params,
      );
      if (response.success) {
        return ApiResponse.success(
          data: _parseList(response.data),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar checklists',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [CHECKLIST] getChecklists: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /sale-checklists/:id` — detalhe.
  Future<ApiResponse<Checklist>> getById(String id) async {
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
        message: response.message ?? 'Checklist não encontrado',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [CHECKLIST] getById: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /sale-checklists` — cria (itens omitidos ⇒ template padrão do tipo).
  Future<ApiResponse<Checklist>> create({
    required String propertyId,
    required String clientId,
    required ChecklistType type,
    List<ChecklistItemDraft>? items,
    String? notes,
  }) async {
    try {
      final body = <String, dynamic>{
        'propertyId': propertyId,
        'clientId': clientId,
        'type': type.apiValue,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        if (items != null && items.isNotEmpty)
          'items': items.map((i) => i.toJson()).toList(),
      };
      final response =
          await _api.post<Map<String, dynamic>>(_base, body: body);
      final parsed = _parseOne(response.data);
      if (response.success) {
        return ApiResponse.success(
          data: parsed,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar checklist',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [CHECKLIST] create: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `PATCH /sale-checklists/:id` — atualiza tipo/itens/observações.
  Future<ApiResponse<Checklist>> update(
    String id, {
    ChecklistType? type,
    List<ChecklistItemDraft>? items,
    String? notes,
  }) async {
    try {
      final body = <String, dynamic>{
        if (type != null) 'type': type.apiValue,
        if (notes != null) 'notes': notes.trim(),
        if (items != null && items.isNotEmpty)
          'items': items.map((i) => i.toJson()).toList(),
      };
      final response =
          await _api.patch<Map<String, dynamic>>(_byId(id), body: body);
      final parsed = _parseOne(response.data);
      if (response.success) {
        return ApiResponse.success(
          data: parsed,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar checklist',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [CHECKLIST] update: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `PATCH /sale-checklists/:id/item-status` — atualiza o status de UM item.
  /// Devolve o checklist inteiro atualizado (com estatísticas recalculadas).
  Future<ApiResponse<Checklist>> updateItemStatus(
    String checklistId, {
    required String itemId,
    required ChecklistStatus status,
    String? notes,
  }) async {
    try {
      final response = await _api.patch<Map<String, dynamic>>(
        _itemStatus(checklistId),
        body: {
          'itemId': itemId,
          'status': status.apiValue,
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        },
      );
      final parsed = _parseOne(response.data);
      if (response.success && parsed != null) {
        return ApiResponse.success(
          data: parsed,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar item',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [CHECKLIST] updateItemStatus: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `DELETE /sale-checklists/:id` — remove (soft delete).
  Future<ApiResponse<void>> delete(String id) async {
    try {
      final response = await _api.delete<dynamic>(_byId(id));
      if (response.success) {
        return ApiResponse.success(statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao remover checklist',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [CHECKLIST] delete: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}
