import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../models/visit_report_model.dart';

/// Serviço dos Relatórios de Visita — consome `/visit-reports` (paridade com
/// `visitReportApi` do imobx-front / `VisitReportController` do imobx).
///
/// Endpoints declarados como constantes PRIVADAS por convenção desta feature —
/// a fiação central migra para `ApiConstants` (ver manifest).
class VisitReportService {
  VisitReportService._();

  static final VisitReportService instance = VisitReportService._();
  final ApiService _api = ApiService.instance;

  static const String _base = '/visit-reports';
  static String _byId(String id) => '$_base/$id';
  static String _generateLink(String id, int days) =>
      '$_base/$id/generate-signature-link?expiresInDays=$days';
  static String _signatureLink(String id) => '$_base/$id/signature-link';

  // Buscas dos pickers (mesmos endpoints dos selects do web:
  // `ClientSearchSelect` → /clients, `PropertySearchSelect` → /properties).
  static const String _clients = '/clients';
  static String _clientById(String id) => '$_clients/$id';
  static const String _properties = '/properties';

  List<VisitReport> _parseList(dynamic raw) {
    final list = raw is List
        ? raw
        : raw is Map && raw['data'] is List
            ? raw['data'] as List
            : const [];
    return list
        .whereType<Map>()
        .map((e) => VisitReport.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Map<String, dynamic> _unwrap(Map<String, dynamic> raw) =>
      raw['data'] is Map<String, dynamic>
          ? raw['data'] as Map<String, dynamic>
          : raw;

  /// `GET /visit-reports` — lista (array completo; sem paginação no backend).
  /// `scope=mine` traz só os do usuário; `scope=all` exige `visit:manage`.
  Future<ApiResponse<List<VisitReport>>> list({
    VisitReportFilters filters = VisitReportFilters.empty,
    bool scopeAll = false,
  }) async {
    try {
      final response = await _api.get<dynamic>(
        _base,
        queryParameters: filters.toQueryParams(scopeAll: scopeAll),
      );
      if (response.success && response.data != null) {
        final items = _parseList(response.data);
        // Mais recentes primeiro (defensivo — o backend já ordena desc).
        items.sort((a, b) {
          final da = a.visitDate ?? a.createdAt ?? DateTime(1970);
          final db = b.visitDate ?? b.createdAt ?? DateTime(1970);
          return db.compareTo(da);
        });
        return ApiResponse.success(
          data: items,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar relatórios de visita',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [VISIT_REPORT] list: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /visit-reports/:id` — detalhe.
  Future<ApiResponse<VisitReport>> getById(String id) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(_byId(id));
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: VisitReport.fromJson(_unwrap(response.data!)),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Relatório não encontrado',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [VISIT_REPORT] getById: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /visit-reports` — cria relatório (`CreateVisitReportDto`).
  Future<ApiResponse<VisitReport>> create(Map<String, dynamic> payload) async {
    try {
      final response =
          await _api.post<Map<String, dynamic>>(_base, body: payload);
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: VisitReport.fromJson(_unwrap(response.data!)),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar relatório',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [VISIT_REPORT] create: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `PUT /visit-reports/:id` — atualiza (`UpdateVisitReportDto`).
  Future<ApiResponse<VisitReport>> update(
    String id,
    Map<String, dynamic> payload,
  ) async {
    try {
      final response =
          await _api.put<Map<String, dynamic>>(_byId(id), body: payload);
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: VisitReport.fromJson(_unwrap(response.data!)),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao salvar relatório',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [VISIT_REPORT] update: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `DELETE /visit-reports/:id` — exclui.
  Future<ApiResponse<void>> remove(String id) async {
    try {
      final response = await _api.delete<dynamic>(_byId(id));
      if (response.success) {
        return ApiResponse.success(statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao excluir relatório',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [VISIT_REPORT] remove: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /visit-reports/:id/generate-signature-link?expiresInDays=` —
  /// gera (ou regenera) o link público de assinatura do cliente.
  Future<ApiResponse<VisitSignatureLink>> generateSignatureLink(
    String id, {
    int expiresInDays = 7,
  }) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        _generateLink(id, expiresInDays),
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: VisitSignatureLink.fromJson(_unwrap(response.data!)),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao gerar link de assinatura',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [VISIT_REPORT] generateSignatureLink: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /visit-reports/:id/signature-link` — link já gerado (para copiar).
  /// Falha (404) quando não há link válido.
  Future<ApiResponse<VisitSignatureLink>> getSignatureLink(String id) async {
    try {
      final response =
          await _api.get<Map<String, dynamic>>(_signatureLink(id));
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: VisitSignatureLink.fromJson(_unwrap(response.data!)),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Link expirado ou não encontrado',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [VISIT_REPORT] getSignatureLink: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  // ─── Pickers ───────────────────────────────────────────────────────────

  /// Busca de clientes (`GET /clients?search=&page=1&limit=25`) — mesmo
  /// contrato do `ClientSearchSelect` do web.
  Future<ApiResponse<List<ClientPickOption>>> searchClients(
    String term,
  ) async {
    try {
      final response = await _api.get<dynamic>(
        _clients,
        queryParameters: {
          if (term.trim().isNotEmpty) 'search': term.trim(),
          'page': '1',
          'limit': '25',
        },
      );
      if (response.success && response.data != null) {
        final raw = response.data;
        final list = raw is List
            ? raw
            : raw is Map && raw['data'] is List
                ? raw['data'] as List
                : raw is Map && raw['clients'] is List
                    ? raw['clients'] as List
                    : const [];
        return ApiResponse.success(
          data: list
              .whereType<Map>()
              .map((e) =>
                  ClientPickOption.fromJson(Map<String, dynamic>.from(e)))
              .where((c) => c.id.isNotEmpty && c.name.isNotEmpty)
              .toList(),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar clientes',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [VISIT_REPORT] searchClients: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Contato do cliente (telefone p/ envio do link via WhatsApp).
  Future<ClientPickOption?> getClientContact(String clientId) async {
    if (clientId.isEmpty) return null;
    try {
      final response =
          await _api.get<Map<String, dynamic>>(_clientById(clientId));
      if (response.success && response.data != null) {
        return ClientPickOption.fromJson(_unwrap(response.data!));
      }
    } catch (e) {
      debugPrint('⚠️ [VISIT_REPORT] getClientContact: $e');
    }
    return null;
  }

  /// Busca de imóveis (`GET /properties?search=&page=1&limit=25`) — mesmo
  /// contrato do `PropertySearchSelect` do web.
  Future<ApiResponse<List<PropertyPickOption>>> searchProperties(
    String term,
  ) async {
    try {
      final response = await _api.get<dynamic>(
        _properties,
        queryParameters: {
          if (term.trim().isNotEmpty) 'search': term.trim(),
          'page': '1',
          'limit': '25',
        },
      );
      if (response.success && response.data != null) {
        final raw = response.data;
        final list = raw is List
            ? raw
            : raw is Map && raw['properties'] is List
                ? raw['properties'] as List
                : raw is Map && raw['data'] is List
                    ? raw['data'] as List
                    : const [];
        return ApiResponse.success(
          data: list
              .whereType<Map>()
              .map((e) =>
                  PropertyPickOption.fromJson(Map<String, dynamic>.from(e)))
              .where((p) => p.id.isNotEmpty)
              .toList(),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar imóveis',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [VISIT_REPORT] searchProperties: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}
