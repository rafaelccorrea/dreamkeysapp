import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../models/credit_analysis_model.dart';

/// Serviço de Análise de Crédito — consome `/credit-analysis` (paridade com
/// `creditAnalysisService.ts` do imobx-front). Backend: módulo
/// `credit_and_collection`, permissões `credit_analysis:view|create|review`.
class CreditAnalysisService {
  CreditAnalysisService._();

  static final CreditAnalysisService instance = CreditAnalysisService._();
  final ApiService _api = ApiService.instance;

  // Endpoints (espelham `CreditAnalysisController` no backend).
  static const String _base = '/credit-analysis';
  static const String _statistics = '/credit-analysis/statistics';
  static const String _settings = '/credit-analysis/settings';
  static String _byId(String id) => '/credit-analysis/$id';

  List<CreditAnalysis> _parseList(dynamic raw) {
    final list = raw is List
        ? raw
        : raw is Map && raw['data'] is List
            ? raw['data'] as List
            : const [];
    return list
        .whereType<Map>()
        .map((e) => CreditAnalysis.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// `GET /credit-analysis` — todas as análises (opcional: cpf/status/rentalId).
  Future<ApiResponse<List<CreditAnalysis>>> getAnalyses({
    String? cpf,
    String? status,
    String? rentalId,
  }) async {
    try {
      final params = <String, String>{};
      if (cpf != null && cpf.trim().isNotEmpty) params['cpf'] = cpf.trim();
      if (status != null && status.isNotEmpty) params['status'] = status;
      if (rentalId != null && rentalId.isNotEmpty) {
        params['rentalId'] = rentalId;
      }
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
        message: response.message ?? 'Erro ao carregar análises de crédito',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [CREDIT_ANALYSIS] getAnalyses: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /credit-analysis/statistics` — agregados para o hero/KPIs.
  Future<ApiResponse<CreditAnalysisStatistics>> getStatistics() async {
    try {
      final response = await _api.get<Map<String, dynamic>>(_statistics);
      if (response.success && response.data != null) {
        final raw = response.data!;
        final body = raw['data'] is Map<String, dynamic>
            ? raw['data'] as Map<String, dynamic>
            : raw;
        return ApiResponse.success(
          data: CreditAnalysisStatistics.fromJson(body),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar estatísticas',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [CREDIT_ANALYSIS] getStatistics: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /credit-analysis/:id` — parecer completo de uma análise.
  Future<ApiResponse<CreditAnalysis>> getById(String id) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(_byId(id));
      if (response.success && response.data != null) {
        final raw = response.data!;
        final body = raw['data'] is Map<String, dynamic>
            ? raw['data'] as Map<String, dynamic>
            : raw;
        return ApiResponse.success(
          data: CreditAnalysis.fromJson(body),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Análise não encontrada',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [CREDIT_ANALYSIS] getById: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /credit-analysis` — solicita nova análise (consulta síncrona).
  /// A resposta pode voltar com `status == ERROR` + `errorMessage` amigável.
  Future<ApiResponse<CreditAnalysis>> createAnalysis({
    required String analyzedCpf,
    String? analyzedName,
    String? rentalId,
  }) async {
    try {
      final body = <String, dynamic>{
        'analyzedCpf': analyzedCpf.replaceAll(RegExp(r'[^0-9]'), ''),
        if (analyzedName != null && analyzedName.trim().isNotEmpty)
          'analyzedName': analyzedName.trim(),
        if (rentalId != null && rentalId.isNotEmpty) 'rentalId': rentalId,
      };
      final response = await _api.post<Map<String, dynamic>>(
        _base,
        body: body,
      );
      if (response.success && response.data != null) {
        final raw = response.data!;
        final parsed = raw['data'] is Map<String, dynamic>
            ? raw['data'] as Map<String, dynamic>
            : raw;
        return ApiResponse.success(
          data: CreditAnalysis.fromJson(parsed),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar análise de crédito',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [CREDIT_ANALYSIS] createAnalysis: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /credit-analysis/settings` — regras de aprovação/rejeição
  /// automática (exibição só leitura no app; edição fica no painel web).
  Future<ApiResponse<CreditAnalysisSettings>> getSettings() async {
    try {
      final response = await _api.get<Map<String, dynamic>>(_settings);
      if (response.success && response.data != null) {
        final raw = response.data!;
        final body = raw['data'] is Map<String, dynamic>
            ? raw['data'] as Map<String, dynamic>
            : raw;
        return ApiResponse.success(
          data: CreditAnalysisSettings.fromJson(body),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar configurações',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [CREDIT_ANALYSIS] getSettings: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}
