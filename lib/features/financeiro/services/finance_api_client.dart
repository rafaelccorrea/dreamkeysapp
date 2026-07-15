import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../shared/services/api_service.dart';
import '../../../shared/services/auth_service.dart';
import '../../../shared/services/secure_storage_service.dart';

/// Cliente HTTP do **microserviço Financeiro** (ERP União).
///
/// O módulo Financeiro NÃO vive na API principal do CRM: é um backend
/// apartado (mesmo padrão do `financeiroApi.ts` do imobx-front, que usa
/// `VITE_FINANCEIRO_API_URL`). Por isso este cliente existe em vez de usar o
/// `ApiService.instance` compartilhado (cujo `baseApiUrl` aponta para a API
/// principal).
///
/// Auth bridging (paridade com o web):
///   - forwarda o `Authorization: Bearer <access_token>` do CRM;
///   - forwarda o `X-Company-ID` da empresa selecionada;
///   - em 401 tenta UM refresh via [AuthService.refreshToken] e reexecuta.
///
/// Retorna sempre [ApiResponse] (a mesma classe do `ApiService` compartilhado)
/// para que as telas usem exatamente o padrão do resto do app.
///
/// Base URL:
///   - produção: `https://api.financeiro.intellisysbr.com/api/v1`
///     (mesma de `VITE_FINANCEIRO_API_URL` no `.env.production` do imobx-front);
///   - override em dev: `--dart-define=FINANCE_API_BASE_URL=http://10.0.2.2:3001/api/v1`.
class FinanceApiClient {
  FinanceApiClient._();

  static final FinanceApiClient instance = FinanceApiClient._();

  /// Base do microserviço financeiro em produção.
  static const String _productionBaseUrl =
      'https://api.financeiro.intellisysbr.com/api/v1';

  /// Override opcional via `--dart-define=FINANCE_API_BASE_URL=...`.
  static const String _envBaseUrl = String.fromEnvironment(
    'FINANCE_API_BASE_URL',
  );

  static const Duration _timeout = Duration(seconds: 30);

  /// Base efetiva (sem barra final).
  static String get baseUrl {
    final raw = _envBaseUrl.isNotEmpty ? _envBaseUrl : _productionBaseUrl;
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  // ── HTTP verbs ─────────────────────────────────────────────────────────────

  /// GET no microserviço financeiro. Se [parser] for fornecido, o corpo já
  /// decodificado (Map/List) é convertido dentro de try/catch — erro de parse
  /// vira `ApiResponse.error` em vez de exceção solta na tela.
  Future<ApiResponse<T>> get<T>(
    String endpoint, {
    Map<String, String>? queryParameters,
    T Function(dynamic body)? parser,
  }) {
    return _send<T>(
      'GET',
      endpoint,
      queryParameters: queryParameters,
      parser: parser,
    );
  }

  /// POST com body JSON opcional.
  Future<ApiResponse<T>> post<T>(
    String endpoint, {
    Object? body,
    Map<String, String>? queryParameters,
    T Function(dynamic body)? parser,
  }) {
    return _send<T>(
      'POST',
      endpoint,
      body: body,
      queryParameters: queryParameters,
      parser: parser,
    );
  }

  /// PATCH com body JSON opcional.
  Future<ApiResponse<T>> patch<T>(
    String endpoint, {
    Object? body,
    T Function(dynamic body)? parser,
  }) {
    return _send<T>('PATCH', endpoint, body: body, parser: parser);
  }

  /// DELETE (corpo de resposta geralmente vazio).
  Future<ApiResponse<T>> delete<T>(
    String endpoint, {
    T Function(dynamic body)? parser,
  }) {
    return _send<T>('DELETE', endpoint, parser: parser);
  }

  // ── Núcleo ─────────────────────────────────────────────────────────────────

  Future<ApiResponse<T>> _send<T>(
    String method,
    String endpoint, {
    Object? body,
    Map<String, String>? queryParameters,
    T Function(dynamic body)? parser,
    bool retryOn401 = true,
  }) async {
    try {
      var uri = Uri.parse('$baseUrl$endpoint');
      if (queryParameters != null && queryParameters.isNotEmpty) {
        uri = uri.replace(queryParameters: queryParameters);
      }

      final headers = await _buildHeaders();
      final encoded = body != null ? jsonEncode(body) : null;

      http.Response response;
      switch (method) {
        case 'GET':
          response = await http.get(uri, headers: headers).timeout(_timeout);
          break;
        case 'POST':
          response = await http
              .post(uri, headers: headers, body: encoded)
              .timeout(_timeout);
          break;
        case 'PATCH':
          response = await http
              .patch(uri, headers: headers, body: encoded)
              .timeout(_timeout);
          break;
        case 'DELETE':
          response = await http.delete(uri, headers: headers).timeout(_timeout);
          break;
        default:
          throw ArgumentError('Método HTTP não suportado: $method');
      }

      // 401 → tenta UM refresh de sessão via AuthService e reexecuta.
      if (response.statusCode == 401 && retryOn401) {
        debugPrint('🔄 [FINANCE_API] 401 — tentando refresh de sessão...');
        final refreshed = await AuthService.instance.refreshToken();
        if (refreshed.success && refreshed.data != null) {
          return _send<T>(
            method,
            endpoint,
            body: body,
            queryParameters: queryParameters,
            parser: parser,
            retryOn401: false,
          );
        }
        return ApiResponse.error(
          message: 'Sessão expirada. Faça login novamente.',
          statusCode: 401,
        );
      }

      return _handleResponse<T>(response, parser);
    } catch (e) {
      debugPrint('❌ [FINANCE_API] $method $baseUrl$endpoint → $e');
      return ApiResponse.error(
        message: 'Erro de conexão com o Financeiro. '
            'Verifique sua internet e tente novamente.',
        statusCode: 0,
      );
    }
  }

  Future<Map<String, String>> _buildHeaders() async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    final token = await SecureStorageService.instance.getAccessToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final companyId = await SecureStorageService.instance.getCompanyId();
    if (companyId != null && companyId.isNotEmpty) {
      headers['X-Company-ID'] = companyId;
    }

    return headers;
  }

  ApiResponse<T> _handleResponse<T>(
    http.Response response,
    T Function(dynamic body)? parser,
  ) {
    final statusCode = response.statusCode;
    dynamic decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = null;
      }
    }

    if (statusCode >= 200 && statusCode < 300) {
      if (parser != null) {
        try {
          return ApiResponse.success(
            data: parser(decoded),
            statusCode: statusCode,
          );
        } catch (e) {
          debugPrint('❌ [FINANCE_API] Erro de parse: $e');
          return ApiResponse.error(
            message: 'Resposta inesperada do servidor financeiro.',
            statusCode: statusCode,
            data: decoded,
          );
        }
      }
      dynamic normalized = decoded;
      if (decoded is Map && decoded is! Map<String, dynamic>) {
        normalized = Map<String, dynamic>.from(decoded);
      }
      return ApiResponse.success(
        data: normalized is T ? normalized : null,
        statusCode: statusCode,
      );
    }

    return ApiResponse.error(
      message: _friendlyError(statusCode, decoded),
      statusCode: statusCode,
      data: decoded,
    );
  }

  /// Mensagens pt-BR — mesmo contrato do `handleError` do financeiroApi web.
  String _friendlyError(int status, dynamic body) {
    String message = 'Erro interno do servidor';
    if (body is Map) {
      final raw = body['message'];
      if (raw is String && raw.isNotEmpty) {
        message = raw;
      } else if (raw is List && raw.isNotEmpty) {
        message = raw.join('; ');
      }
    }

    switch (status) {
      case 400:
        return 'Dados inválidos: $message';
      case 401:
        return 'Não autorizado. Faça login novamente.';
      case 403:
        return 'Acesso negado. Você não tem permissão para esta ação.';
      case 404:
        return 'Registro não encontrado.';
      case 409:
        return 'Conflito: $message';
      case 422:
        return 'Dados de validação inválidos: $message';
      case 500:
        return 'Erro interno do servidor. Tente novamente mais tarde.';
      default:
        return 'Erro $status: $message';
    }
  }
}
