import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../models/insurance_models.dart';

/// Serviço de Seguros — consome `/insurance/*` (paridade com o
/// `insuranceService.ts` do imobx-front). Permissão de cotação no backend:
/// `insurance:create_quote`; contratação: `insurance:create_policy`.
class InsuranceService {
  InsuranceService._();

  static final InsuranceService instance = InsuranceService._();
  final ApiService _api = ApiService.instance;

  // Endpoints (constantes privadas — a fiação central fica no api_constants).
  static const String _quote = '/insurance/quote';
  static const String _quoteAll = '/insurance/quote-all';
  static const String _policy = '/insurance/policy';
  static const String _clients = '/clients';
  static String _propertyByCode(String code) => '/properties/$code';

  /// `GET /clients?document=` — busca cliente pelo CPF (só dígitos).
  Future<ApiResponse<InsuranceClient>> searchClientByCpf(String cpf) async {
    try {
      final digits = cpf.replaceAll(RegExp(r'[^0-9]'), '');
      final response = await _api.get<dynamic>(
        _clients,
        queryParameters: {'document': digits},
      );
      if (response.success) {
        final raw = response.data;
        // A rota devolve lista; algumas versões embrulham em {data: [...]}.
        final list = raw is List
            ? raw
            : raw is Map && raw['data'] is List
                ? raw['data'] as List
                : const [];
        if (list.isNotEmpty && list.first is Map) {
          return ApiResponse.success(
            data: InsuranceClient.fromJson(
              Map<String, dynamic>.from(list.first as Map),
            ),
            statusCode: response.statusCode,
          );
        }
        return ApiResponse.error(
          message: 'Cliente não encontrado',
          statusCode: 404,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar cliente',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [INSURANCE] searchClientByCpf: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /properties/:code` — busca imóvel pelo código ou ID.
  Future<ApiResponse<InsuranceProperty>> getPropertyByCode(String code) async {
    try {
      final response = await _api.get<dynamic>(
        _propertyByCode(Uri.encodeComponent(code.trim())),
      );
      if (response.success && response.data != null) {
        final raw = response.data;
        final body = raw is Map && raw['data'] is Map
            ? raw['data'] as Map
            : raw;
        if (body is Map) {
          return ApiResponse.success(
            data: InsuranceProperty.fromJson(Map<String, dynamic>.from(body)),
            statusCode: response.statusCode,
          );
        }
      }
      return ApiResponse.error(
        message: response.message ?? 'Imóvel não encontrado',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [INSURANCE] getPropertyByCode: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /insurance/quote` — cotação em UMA seguradora
  /// (`request.provider` obrigatório aqui).
  Future<ApiResponse<InsuranceQuote>> createQuote(
    InsuranceQuoteRequest request,
  ) async {
    try {
      final response = await _api.post<dynamic>(
        _quote,
        body: request.toJson(),
      );
      if (response.success && response.data is Map) {
        return ApiResponse.success(
          data: InsuranceQuote.fromJson(
            Map<String, dynamic>.from(response.data as Map),
          ),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar cotação',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [INSURANCE] createQuote: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /insurance/quote-all` — cotação simultânea em TODAS as
  /// seguradoras. O payload NÃO leva `provider`.
  Future<ApiResponse<List<InsuranceQuote>>> createQuoteAll(
    InsuranceQuoteRequest request,
  ) async {
    try {
      final body = request.toJson()..remove('provider');
      final response = await _api.post<dynamic>(_quoteAll, body: body);
      if (response.success && response.data is List) {
        final quotes = (response.data as List)
            .whereType<Map>()
            .map((e) => InsuranceQuote.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        return ApiResponse.success(
          data: quotes,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar cotações',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [INSURANCE] createQuoteAll: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /insurance/policy` — contrata a apólice a partir de uma cotação.
  /// Exige `rentalId` (a apólice nasce vinculada à locação).
  Future<ApiResponse<InsurancePolicy>> createPolicy({
    required String quoteId,
    required String rentalId,
    String? observations,
  }) async {
    try {
      final response = await _api.post<dynamic>(
        _policy,
        body: {
          'quoteId': quoteId,
          'rentalId': rentalId,
          if (observations != null && observations.isNotEmpty)
            'observations': observations,
        },
      );
      if (response.success && response.data is Map) {
        return ApiResponse.success(
          data: InsurancePolicy.fromJson(
            Map<String, dynamic>.from(response.data as Map),
          ),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao contratar seguro',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [INSURANCE] createPolicy: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}
