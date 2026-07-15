import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../models/collection_models.dart';

/// Permissões e módulo da Régua de Cobrança — strings exatas do web
/// (`financial.routes.tsx` do imobx-front).
class CollectionAccess {
  CollectionAccess._();

  /// Módulo da empresa que libera a entrada (mesmo do Análise de Crédito).
  static const String module = 'credit_and_collection';

  /// Ver a régua (`/collection`).
  static const String view = 'collection:view';

  /// Gerenciar regras e processar cobranças (`/collection/rules*`).
  static const String manage = 'collection:manage';
}

/// Serviço da **Régua de Cobrança** — consome `/collection*` (paridade com
/// `collectionService.ts` do imobx-front). O backend escopa por empresa via
/// header `X-Company-ID` (automático no [ApiService]).
class CollectionService {
  CollectionService._();

  static final CollectionService instance = CollectionService._();
  final ApiService _api = ApiService.instance;

  // Endpoints (privados — a fiação central pode promovê-los a ApiConstants).
  static const String _messages = '/collection';
  static const String _statistics = '/collection/statistics';
  static const String _process = '/collection/process';
  static const String _rules = '/collection/rules';
  static const String _rulesDefault = '/collection/rules/default';
  static String _ruleById(String id) => '/collection/rules/$id';
  static String _ruleToggle(String id) => '/collection/rules/$id/toggle';

  List<CollectionMessage> _parseMessages(dynamic raw) {
    final list = raw is List
        ? raw
        : raw is Map && raw['data'] is List
            ? raw['data'] as List
            : const [];
    return list
        .whereType<Map>()
        .map((e) => CollectionMessage.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  List<CollectionRule> _parseRules(dynamic raw) {
    final list = raw is List
        ? raw
        : raw is Map && raw['data'] is List
            ? raw['data'] as List
            : const [];
    return list
        .whereType<Map>()
        .map((e) => CollectionRule.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  CollectionRule? _parseRule(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      final body = raw['data'] is Map ? raw['data'] as Map : raw;
      return CollectionRule.fromJson(Map<String, dynamic>.from(body));
    }
    if (raw is Map) {
      return CollectionRule.fromJson(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  /// `GET /collection` — últimas mensagens de cobrança da empresa
  /// (o backend devolve as 500 mais recentes, ordenadas desc).
  Future<ApiResponse<List<CollectionMessage>>> getMessages() async {
    try {
      final response = await _api.get<dynamic>(_messages);
      if (response.success) {
        return ApiResponse.success(
          data: _parseMessages(response.data),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar mensagens de cobrança',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [COLLECTION] getMessages: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /collection/statistics` — totais, taxa de sucesso e canais.
  Future<ApiResponse<CollectionStatistics>> getStatistics() async {
    try {
      final response = await _api.get<Map<String, dynamic>>(_statistics);
      if (response.success && response.data != null) {
        final raw = response.data!;
        final body = raw['data'] is Map<String, dynamic>
            ? raw['data'] as Map<String, dynamic>
            : raw;
        return ApiResponse.success(
          data: CollectionStatistics.fromJson(body),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar estatísticas',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [COLLECTION] getStatistics: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /collection/process` — dispara o processamento manual
  /// (permissão `collection:manage`). O backend responde com `{ message }`.
  Future<ApiResponse<String>> processCollections() async {
    try {
      final response = await _api.post<dynamic>(_process);
      if (response.success) {
        final raw = response.data;
        String message = 'Processamento de cobranças iniciado';
        if (raw is Map) {
          final m = raw['message']?.toString();
          if (m != null && m.isNotEmpty) message = m;
          final processed = raw['processed'];
          if (processed is num) {
            message = '$processed cobranças processadas com sucesso!';
          }
        }
        return ApiResponse.success(
          data: message,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao processar cobranças',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [COLLECTION] processCollections: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /collection/rules` — todas as réguas da empresa.
  Future<ApiResponse<List<CollectionRule>>> getRules(
      {bool activeOnly = false}) async {
    try {
      final response = await _api.get<dynamic>(
        _rules,
        queryParameters: activeOnly ? const {'activeOnly': 'true'} : null,
      );
      if (response.success) {
        return ApiResponse.success(
          data: _parseRules(response.data),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar réguas',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [COLLECTION] getRules: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /collection/rules/:id` — detalhe de uma régua.
  Future<ApiResponse<CollectionRule>> getRule(String id) async {
    try {
      final response = await _api.get<dynamic>(_ruleById(id));
      if (response.success && response.data != null) {
        final rule = _parseRule(response.data);
        if (rule != null) {
          return ApiResponse.success(
            data: rule,
            statusCode: response.statusCode,
          );
        }
      }
      return ApiResponse.error(
        message: response.message ?? 'Régua não encontrada',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [COLLECTION] getRule: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /collection/rules` — cria uma régua.
  Future<ApiResponse<CollectionRule>> createRule(
      CollectionRulePayload payload) async {
    try {
      final response = await _api.post<dynamic>(_rules, body: payload.toJson());
      if (response.success) {
        return ApiResponse.success(
          data: _parseRule(response.data),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar régua',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [COLLECTION] createRule: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `PUT /collection/rules/:id` — atualiza uma régua.
  Future<ApiResponse<CollectionRule>> updateRule(
    String id,
    CollectionRulePayload payload,
  ) async {
    try {
      final response =
          await _api.put<dynamic>(_ruleById(id), body: payload.toJson());
      if (response.success) {
        return ApiResponse.success(
          data: _parseRule(response.data),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar régua',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [COLLECTION] updateRule: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `PUT /collection/rules/:id/toggle` — ativa/desativa uma régua.
  Future<ApiResponse<CollectionRule>> toggleRule(String id) async {
    try {
      final response = await _api.put<dynamic>(_ruleToggle(id));
      if (response.success) {
        return ApiResponse.success(
          data: _parseRule(response.data),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao alternar régua',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [COLLECTION] toggleRule: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `DELETE /collection/rules/:id` — exclui uma régua (204 sem body).
  Future<ApiResponse<void>> deleteRule(String id) async {
    try {
      final response = await _api.delete<dynamic>(_ruleById(id));
      if (response.success) {
        return ApiResponse.success(statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao excluir régua',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [COLLECTION] deleteRule: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /collection/rules/default` — cria as 4 réguas pré-configuradas
  /// (o backend recusa com 409 quando a empresa já tem réguas).
  Future<ApiResponse<List<CollectionRule>>> createDefaultRules() async {
    try {
      final response = await _api.get<dynamic>(_rulesDefault);
      if (response.success) {
        return ApiResponse.success(
          data: _parseRules(response.data),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar réguas padrão',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [COLLECTION] createDefaultRules: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}
