import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/constants/api_constants.dart';

/// Serviço base para chamadas de API
class ApiService {
  ApiService._();

  static final ApiService instance = ApiService._();
  String? _token;

  /// Define o token de autenticação
  void setToken(String? token) {
    _token = token;
  }

  /// Remove o token de autenticação
  void clearToken() {
    _token = null;
  }

  /// Headers padrão para requisições
  Map<String, String> get _defaultHeaders => {
    ApiConstants.contentTypeHeader: ApiConstants.contentTypeJson,
    ApiConstants.acceptHeader: ApiConstants.contentTypeJson,
    if (_token != null)
      ApiConstants.authorizationHeader: '${ApiConstants.bearerPrefix} $_token',
  };

  /// Realiza uma requisição GET
  Future<ApiResponse<T>> get<T>(
    String endpoint, {
    Map<String, String>? queryParameters,
    Map<String, String>? headers,
  }) async {
    try {
      var uri = Uri.parse('${ApiConstants.baseApiUrl}$endpoint');
      if (queryParameters != null && queryParameters.isNotEmpty) {
        uri = uri.replace(queryParameters: queryParameters);
      }

      final response = await http
          .get(uri, headers: {..._defaultHeaders, ...?headers})
          .timeout(ApiConstants.connectTimeout);

      return _handleResponse<T>(response);
    } catch (e) {
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Realiza uma requisição POST
  Future<ApiResponse<T>> post<T>(
    String endpoint, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseApiUrl}$endpoint');

      final response = await http
          .post(
            uri,
            headers: {..._defaultHeaders, ...?headers},
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(ApiConstants.connectTimeout);

      return _handleResponse<T>(response);
    } catch (e) {
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Realiza uma requisição PUT
  Future<ApiResponse<T>> put<T>(
    String endpoint, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseApiUrl}$endpoint');

      final response = await http
          .put(
            uri,
            headers: {..._defaultHeaders, ...?headers},
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(ApiConstants.connectTimeout);

      return _handleResponse<T>(response);
    } catch (e) {
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Realiza uma requisição PATCH
  Future<ApiResponse<T>> patch<T>(
    String endpoint, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseApiUrl}$endpoint');

      final response = await http
          .patch(
            uri,
            headers: {..._defaultHeaders, ...?headers},
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(ApiConstants.connectTimeout);

      return _handleResponse<T>(response);
    } catch (e) {
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Realiza uma requisição DELETE
  Future<ApiResponse<T>> delete<T>(
    String endpoint, {
    Map<String, String>? headers,
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseApiUrl}$endpoint');

      final response = await http
          .delete(uri, headers: {..._defaultHeaders, ...?headers})
          .timeout(ApiConstants.connectTimeout);

      return _handleResponse<T>(response);
    } catch (e) {
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Trata a resposta da API
  ApiResponse<T> _handleResponse<T>(http.Response response) {
    final statusCode = response.statusCode;
    final body = response.body.isNotEmpty ? jsonDecode(response.body) : null;

    if (statusCode >= 200 && statusCode < 300) {
      return ApiResponse.success(data: body as T?, statusCode: statusCode);
    } else {
      final errorMessage = _extractErrorMessage(body);
      return ApiResponse.error(
        message: errorMessage,
        statusCode: statusCode,
        data: body,
      );
    }
  }

  /// Extrai mensagem de erro da resposta
  String _extractErrorMessage(dynamic body) {
    if (body == null) return 'Erro desconhecido';
    if (body is Map<String, dynamic>) {
      return body['message'] as String? ?? 'Erro desconhecido';
    }
    return 'Erro desconhecido';
  }
}

/// Resposta padronizada da API
class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? message;
  final int statusCode;
  final dynamic error;

  ApiResponse({
    required this.success,
    this.data,
    this.message,
    required this.statusCode,
    this.error,
  });

  factory ApiResponse.success({T? data, required int statusCode}) {
    return ApiResponse<T>(success: true, data: data, statusCode: statusCode);
  }

  factory ApiResponse.error({
    required String message,
    required int statusCode,
    dynamic data,
  }) {
    return ApiResponse<T>(
      success: false,
      message: message,
      statusCode: statusCode,
      error: data,
    );
  }
}
