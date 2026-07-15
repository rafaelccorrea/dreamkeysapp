import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../models/mcmv_models.dart';

/// Serviço do MCMV — consome `/mcmv/*` (paridade com `mcmvApi` do
/// imobx-front / `McmvController`, `McmvBlacklistController` e
/// `McmvTemplatesController` do backend NestJS).
///
/// Endpoints declarados como constantes privadas — a migração para
/// `ApiConstants` é responsabilidade da fiação central (ver manifest).
class McmvService {
  McmvService._();

  static final McmvService instance = McmvService._();
  final ApiService _api = ApiService.instance;

  // ─── Endpoints ────────────────────────────────────────────────────────────
  static const String _leads = '/mcmv/leads';
  static String _leadCapture(String id) => '/mcmv/leads/$id/capture';
  static String _leadStatus(String id) => '/mcmv/leads/$id/status';
  static String _leadRate(String id) => '/mcmv/leads/$id/rate';
  static String _leadConvert(String id) => '/mcmv/leads/$id/convert';
  static const String _blacklist = '/mcmv/blacklist';
  static String _blacklistById(String id) => '/mcmv/blacklist/$id';
  static const String _templates = '/mcmv/templates';

  // ─── Helpers ──────────────────────────────────────────────────────────────

  /// Desembrulha `{ data: {...} }` quando o backend envelopa a resposta.
  Map<String, dynamic>? _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      final inner = raw['data'];
      if (inner is Map<String, dynamic>) return inner;
      if (inner is Map) return Map<String, dynamic>.from(inner);
      return raw;
    }
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  /// Extrai uma lista de mapas de respostas `[...]` ou `{ data: [...] }`.
  List<Map<String, dynamic>> _asList(dynamic raw) {
    final source = raw is Map ? (raw['data'] ?? raw['items']) : raw;
    if (source is List) {
      return source
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  ApiResponse<T> _connectionError<T>(Object e) => ApiResponse.error(
        message: 'Erro de conexão: $e',
        statusCode: 0,
      );

  // ─── Leads ────────────────────────────────────────────────────────────────

  /// `GET /mcmv/leads` — lista paginada; ao listar, os leads são marcados como
  /// visualizados pela empresa (comportamento do backend).
  Future<ApiResponse<McmvLeadListResult>> listLeads({
    McmvLeadFilters filters = const McmvLeadFilters(),
  }) async {
    try {
      final response = await _api.get<dynamic>(
        _leads,
        queryParameters: filters.toQueryParams(),
      );
      if (response.success && response.data != null) {
        final map = _asMap(response.data);
        final result = map != null
            ? McmvLeadListResult.fromJson(map)
            : McmvLeadListResult.empty;
        return ApiResponse.success(
          data: result,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar leads',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [MCMV] listLeads: $e');
      return _connectionError(e);
    }
  }

  /// Busca um lead pelo id varrendo a lista paginada — o backend NÃO expõe
  /// `GET /mcmv/leads/:id` (mesma estratégia do `MCMVLeadDetailsPage` do web).
  Future<ApiResponse<McmvLead>> findLeadById(String id) async {
    try {
      var page = 1;
      const limit = 100;
      while (page <= 10) {
        final res = await listLeads(
          filters: McmvLeadFilters(page: page, limit: limit),
        );
        if (!res.success || res.data == null) {
          return ApiResponse.error(
            message: res.message ?? 'Erro ao carregar lead',
            statusCode: res.statusCode,
          );
        }
        for (final lead in res.data!.items) {
          if (lead.id == id) {
            return ApiResponse.success(data: lead, statusCode: res.statusCode);
          }
        }
        if (!res.data!.hasNext) break;
        page++;
      }
      return ApiResponse.error(message: 'Lead não encontrado', statusCode: 404);
    } catch (e) {
      debugPrint('❌ [MCMV] findLeadById: $e');
      return _connectionError(e);
    }
  }

  /// `POST /mcmv/leads/:id/capture` — captura o lead para a empresa; o status
  /// muda para `contacted` e o lead é atribuído a quem capturou.
  Future<ApiResponse<McmvLead>> captureLead(String leadId) async {
    try {
      final response = await _api.post<dynamic>(_leadCapture(leadId));
      return _leadResponse(response, 'Erro ao capturar lead');
    } catch (e) {
      debugPrint('❌ [MCMV] captureLead: $e');
      return _connectionError(e);
    }
  }

  /// `PUT /mcmv/leads/:id/status` — atualiza o status de um lead capturado.
  Future<ApiResponse<McmvLead>> updateLeadStatus(
    String leadId,
    McmvLeadStatus status,
  ) async {
    try {
      final response = await _api.put<dynamic>(
        _leadStatus(leadId),
        body: {'status': status.apiValue},
      );
      return _leadResponse(response, 'Erro ao atualizar status');
    } catch (e) {
      debugPrint('❌ [MCMV] updateLeadStatus: $e');
      return _connectionError(e);
    }
  }

  /// `POST /mcmv/leads/:id/rate` — avalia o lead (1–5) com comentário
  /// opcional (máx. 1000 caracteres).
  Future<ApiResponse<McmvLead>> rateLead(
    String leadId,
    int rating, {
    String? comment,
  }) async {
    try {
      final body = <String, dynamic>{'rating': rating};
      final c = comment?.trim();
      if (c != null && c.isNotEmpty) body['comment'] = c;
      final response = await _api.post<dynamic>(_leadRate(leadId), body: body);
      return _leadResponse(response, 'Erro ao avaliar lead');
    } catch (e) {
      debugPrint('❌ [MCMV] rateLead: $e');
      return _connectionError(e);
    }
  }

  /// `POST /mcmv/leads/:id/convert` — converte o lead em cliente do sistema
  /// (cria o cliente e muda o status para `converted`).
  Future<ApiResponse<McmvConvertResult>> convertLeadToClient(
    String leadId,
  ) async {
    try {
      final response = await _api.post<dynamic>(_leadConvert(leadId));
      if (response.success && response.data != null) {
        final map = _asMap(response.data);
        if (map != null) {
          return ApiResponse.success(
            data: McmvConvertResult.fromJson(map),
            statusCode: response.statusCode,
          );
        }
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao converter lead',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [MCMV] convertLeadToClient: $e');
      return _connectionError(e);
    }
  }

  ApiResponse<McmvLead> _leadResponse(
    ApiResponse<dynamic> response,
    String fallbackError,
  ) {
    if (response.success && response.data != null) {
      final map = _asMap(response.data);
      if (map != null) {
        return ApiResponse.success(
          data: McmvLead.fromJson(map),
          statusCode: response.statusCode,
        );
      }
    }
    return ApiResponse.error(
      message: response.message ?? fallbackError,
      statusCode: response.statusCode,
      data: response.error,
    );
  }

  // ─── Blacklist ────────────────────────────────────────────────────────────

  /// `GET /mcmv/blacklist` — lista entradas (com filtros opcionais).
  Future<ApiResponse<List<McmvBlacklistEntry>>> listBlacklist({
    McmvBlacklistFilters filters = const McmvBlacklistFilters(),
  }) async {
    try {
      final params = filters.toQueryParams();
      final response = await _api.get<dynamic>(
        _blacklist,
        queryParameters: params.isEmpty ? null : params,
      );
      if (response.success && response.data != null) {
        final entries = _asList(response.data)
            .map(McmvBlacklistEntry.fromJson)
            .toList();
        return ApiResponse.success(
          data: entries,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar blacklist',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [MCMV] listBlacklist: $e');
      return _connectionError(e);
    }
  }

  /// `POST /mcmv/blacklist` — adiciona entrada (exige CPF, email OU telefone).
  Future<ApiResponse<McmvBlacklistEntry>> addToBlacklist(
    McmvBlacklistCreateRequest request,
  ) async {
    try {
      final response =
          await _api.post<dynamic>(_blacklist, body: request.toJson());
      if (response.success && response.data != null) {
        final map = _asMap(response.data);
        if (map != null) {
          return ApiResponse.success(
            data: McmvBlacklistEntry.fromJson(map),
            statusCode: response.statusCode,
          );
        }
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao adicionar à blacklist',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [MCMV] addToBlacklist: $e');
      return _connectionError(e);
    }
  }

  /// `DELETE /mcmv/blacklist/:id` — remove a entrada.
  Future<ApiResponse<void>> removeFromBlacklist(String id) async {
    try {
      final response = await _api.delete<dynamic>(_blacklistById(id));
      if (response.success) {
        return ApiResponse.success(statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao remover da blacklist',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [MCMV] removeFromBlacklist: $e');
      return _connectionError(e);
    }
  }

  // ─── Templates ────────────────────────────────────────────────────────────

  /// `GET /mcmv/templates` — templates da empresa + padrões do sistema
  /// (`companyId == null`).
  Future<ApiResponse<List<McmvTemplate>>> listTemplates() async {
    try {
      final response = await _api.get<dynamic>(_templates);
      if (response.success && response.data != null) {
        final templates =
            _asList(response.data).map(McmvTemplate.fromJson).toList();
        return ApiResponse.success(
          data: templates,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar templates',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [MCMV] listTemplates: $e');
      return _connectionError(e);
    }
  }
}
