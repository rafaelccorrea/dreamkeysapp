import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/api_constants.dart';
import 'secure_storage_service.dart';
import 'auth_service.dart';
import '../utils/jwt_utils.dart';

/// Serviço base para chamadas de API
class ApiService {
  ApiService._();

  static final ApiService instance = ApiService._();
  String? _token;
  bool _isRefreshing = false;
  final List<_PendingRequest> _pendingRequests = [];

  /// Inicializa o serviço carregando o token salvo
  Future<void> initialize() async {
    try {
      final token = await SecureStorageService.instance.getAccessToken();
      if (token != null && token.isNotEmpty) {
        _token = token;
        debugPrint('✅ [API_SERVICE] Token carregado do armazenamento');
      }
    } catch (e) {
      debugPrint('⚠️ [API_SERVICE] Erro ao carregar token: $e');
    }
  }

  /// Define o token de autenticação
  void setToken(String? token) {
    _token = token;
  }

  /// Remove o token de autenticação
  void clearToken() {
    debugPrint('🧹 [API_SERVICE] Limpando token da memória...');
    _token = null;
    // Não limpar do storage aqui, pois isso é responsabilidade do AuthService
    // para evitar limpar tokens que ainda podem ser válidos
  }

  /// Verifica se uma rota é exceção (não exige Company ID obrigatório)
  /// Rotas de autenticação que NÃO requerem token (login, logout, etc)
  bool _isExceptionRoute(String? endpoint) {
    if (endpoint == null) return false;

    // Rotas de autenticação que NÃO requerem token
    final authRoutesWithoutToken = [
      '/auth/broker/login',
      '/auth/login',
      '/auth/logout',
      '/auth/refresh',
      '/auth/forgot-password',
      '/auth/reset-password',
      '/auth/check-2fa',
      '/auth/verify-2fa',
    ];
    
    if (authRoutesWithoutToken.contains(endpoint)) return true;

    // Rotas públicas - NÃO enviar Company ID
    if (endpoint.startsWith('/public/')) return true;

    return false;
  }

  /// Verifica se uma rota tem Company ID opcional (enviar se tiver, mas não bloquear se não tiver)
  bool _isOptionalCompanyIdRoute(String? endpoint) {
    if (endpoint == null) return false;

    // Listar companies - usado para OBTER Company ID
    if (endpoint == ApiConstants.companies || endpoint.endsWith('/companies')) {
      return true;
    }

    // My permissions - pode ser chamado antes de ter Company ID
    if (endpoint.contains('/permissions/my-permissions')) {
      return true;
    }

    // Rotas de assinatura
    if (endpoint.contains('/subscriptions/') || endpoint.contains('/plans')) {
      return true;
    }

    // Rotas de notificações
    if (endpoint.contains('/notifications')) {
      return true;
    }

    // Rotas de teams
    if (endpoint.contains('/teams')) {
      return true;
    }

    return false;
  }

  /// Verifica se é uma rota de dashboard (tem tratamento especial)
  bool _isDashboardRoute(String? endpoint) {
    if (endpoint == null) return false;
    return endpoint.contains('/dashboard');
  }

  /// Aguarda Company ID aparecer (para rotas de dashboard)
  Future<String?> _waitForCompanyId({Duration maxWait = const Duration(milliseconds: 500)}) async {
    final startTime = DateTime.now();
    
    while (DateTime.now().difference(startTime) < maxWait) {
      final companyId = await SecureStorageService.instance.getCompanyId();
      if (companyId != null && companyId.isNotEmpty) {
        return companyId;
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
    
    return null;
  }

  /// Headers padrão para requisições
  /// [endpoint] - Endpoint da requisição para determinar se deve incluir token e Company ID
  Future<Map<String, String>> _getDefaultHeaders(String? endpoint) async {
    final isAuthRoute = _isExceptionRoute(endpoint);
    final isOptionalRoute = _isOptionalCompanyIdRoute(endpoint);
    final isDashboardRoute = _isDashboardRoute(endpoint);
    
    final headers = <String, String>{
      ApiConstants.contentTypeHeader: ApiConstants.contentTypeJson,
      ApiConstants.acceptHeader: ApiConstants.contentTypeJson,
    };

    // Não incluir token em rotas de autenticação (login, logout, etc)
    if (_token != null && !isAuthRoute) {
      headers[ApiConstants.authorizationHeader] =
          '${ApiConstants.bearerPrefix} $_token';
    }

    // Gerenciar X-Company-ID conforme regras da documentação
    // Rotas de perfil (/auth/profile, etc) não requerem Company ID
    final isProfileRoute = endpoint != null && 
        (endpoint.startsWith('/auth/profile') || 
         endpoint.startsWith('/auth/avatar') ||
         endpoint.startsWith('/auth/change-password'));
    
    if (!isAuthRoute && !isProfileRoute) {
      String? companyId = await SecureStorageService.instance.getCompanyId();

      // Para rotas opcionais, enviar se tiver, mas não bloquear se não tiver
      if (isOptionalRoute) {
        if (companyId != null && companyId.isNotEmpty) {
          headers['X-Company-ID'] = companyId;
        }
        // Não bloquear - retornar headers normalmente
      } else {
        // Para rotas protegidas, Company ID é obrigatório
        // Se não tiver e for rota de dashboard, aguardar um pouco
        if (companyId == null || companyId.isEmpty) {
          if (isDashboardRoute && _token != null) {
            debugPrint('⏳ [API_SERVICE] Aguardando Company ID para rota de dashboard...');
            companyId = await _waitForCompanyId();
          }
        }

        // Se ainda não tem Company ID, bloquear requisição
        if (companyId == null || companyId.isEmpty) {
          debugPrint('❌ [API_SERVICE] BLOQUEADO: Tentativa de acessar rota protegida sem Company ID');
          debugPrint('   Endpoint: $endpoint');
          throw Exception('Company ID não encontrado. Requisição bloqueada.');
        }

        headers['X-Company-ID'] = companyId;
      }
    }

    return headers;
  }

  /// Realiza uma requisição GET
  Future<ApiResponse<T>> get<T>(
    String endpoint, {
    Map<String, String>? queryParameters,
    Map<String, String>? headers,
    bool retryOn401 = true,
  }) async {
    return _executeRequest<T>(
      () async {
        var uri = Uri.parse('${ApiConstants.baseApiUrl}$endpoint');
        if (queryParameters != null && queryParameters.isNotEmpty) {
          uri = uri.replace(queryParameters: queryParameters);
        }

        final defaultHeaders = await _getDefaultHeaders(endpoint);
        final response = await http
            .get(uri, headers: {...defaultHeaders, ...?headers})
            .timeout(ApiConstants.connectTimeout);

        return _handleResponse<T>(response);
      },
      retryOn401: retryOn401,
      endpoint: endpoint,
    );
  }

  /// Realiza uma requisição POST
  Future<ApiResponse<T>> post<T>(
    String endpoint, {
    Object? body,
    Map<String, String>? headers,
    bool retryOn401 = true,
  }) async {
    return _executeRequest<T>(
      () async {
        final uri = Uri.parse('${ApiConstants.baseApiUrl}$endpoint');

        final defaultHeaders = await _getDefaultHeaders(endpoint);
        final response = await http
            .post(
              uri,
              headers: {...defaultHeaders, ...?headers},
              body: body != null ? jsonEncode(body) : null,
            )
            .timeout(ApiConstants.connectTimeout);

        return _handleResponse<T>(response);
      },
      retryOn401: retryOn401,
      endpoint: endpoint,
    );
  }

  /// Realiza uma requisição PUT
  Future<ApiResponse<T>> put<T>(
    String endpoint, {
    Object? body,
    Map<String, String>? headers,
    bool retryOn401 = true,
  }) async {
    return _executeRequest<T>(
      () async {
        final uri = Uri.parse('${ApiConstants.baseApiUrl}$endpoint');

        final defaultHeaders = await _getDefaultHeaders(endpoint);
        final response = await http
            .put(
              uri,
              headers: {...defaultHeaders, ...?headers},
              body: body != null ? jsonEncode(body) : null,
            )
            .timeout(ApiConstants.connectTimeout);

        return _handleResponse<T>(response);
      },
      retryOn401: retryOn401,
      endpoint: endpoint,
    );
  }

  /// Realiza uma requisição PATCH
  Future<ApiResponse<T>> patch<T>(
    String endpoint, {
    Object? body,
    Map<String, String>? headers,
    bool retryOn401 = true,
  }) async {
    return _executeRequest<T>(
      () async {
        final uri = Uri.parse('${ApiConstants.baseApiUrl}$endpoint');

        final defaultHeaders = await _getDefaultHeaders(endpoint);
        final response = await http
            .patch(
              uri,
              headers: {...defaultHeaders, ...?headers},
              body: body != null ? jsonEncode(body) : null,
            )
            .timeout(ApiConstants.connectTimeout);

        return _handleResponse<T>(response);
      },
      retryOn401: retryOn401,
      endpoint: endpoint,
    );
  }

  /// Realiza uma requisição DELETE
  Future<ApiResponse<T>> delete<T>(
    String endpoint, {
    Map<String, String>? headers,
    bool retryOn401 = true,
  }) async {
    return _executeRequest<T>(
      () async {
        final uri = Uri.parse('${ApiConstants.baseApiUrl}$endpoint');

        final defaultHeaders = await _getDefaultHeaders(endpoint);
        final response = await http
            .delete(
              uri,
              headers: {...defaultHeaders, ...?headers},
            )
            .timeout(ApiConstants.connectTimeout);

        return _handleResponse<T>(response);
      },
      retryOn401: retryOn401,
      endpoint: endpoint,
    );
  }

  /// Executa uma requisição com tratamento automático de 401
  Future<ApiResponse<T>> _executeRequest<T>(
    Future<ApiResponse<T>> Function() request, {
    required bool retryOn401,
    String? endpoint,
  }) async {
    try {
      // Refresh proativo: verificar se token expira em menos de 2 minutos
      if (_token != null && endpoint != null && retryOn401) {
        // Não fazer refresh proativo em rotas de autenticação
        if (!endpoint.startsWith('/auth/')) {
          final timeUntilExpiry = JwtUtils.getTimeUntilExpiry(_token!);

          if (timeUntilExpiry != null &&
              timeUntilExpiry < 120 &&
              timeUntilExpiry > 0) {
            debugPrint(
              '🔄 [API_SERVICE] Token expira em ${timeUntilExpiry}s, fazendo refresh proativo...',
            );

            // Fazer refresh proativo
            final refreshSuccess = await _refreshTokenIfNeeded();

            if (!refreshSuccess) {
              debugPrint('❌ [API_SERVICE] Refresh proativo falhou');
              return ApiResponse.error(
                message: 'Sessão expirada. Faça login novamente.',
                statusCode: 401,
              );
            }

            debugPrint('✅ [API_SERVICE] Refresh proativo bem-sucedido');
          }
        }
      }

      final response = await request();

      // Tratar erros relacionados a Company ID inválido (400/403)
      if ((response.statusCode == 400 || response.statusCode == 403) &&
          response.error != null) {
        final errorData = response.error;
        final errorMessage = errorData is Map<String, dynamic>
            ? (errorData['message']?.toString().toLowerCase() ?? '')
            : errorData.toString().toLowerCase();

        if (errorMessage.contains('company') ||
            errorMessage.contains('empresa')) {
          debugPrint('⚠️ [API_SERVICE] Erro relacionado a Company ID inválido');
          debugPrint('   Status: ${response.statusCode}');
          debugPrint('   Mensagem: $errorMessage');

          // Limpar Company ID inválido
          await SecureStorageService.instance.clearCompanyId();
          debugPrint('🧹 [API_SERVICE] Company ID inválido removido');

          // Retornar erro específico
          return ApiResponse.error(
            message: 'Company ID inválido ou sem acesso. Por favor, selecione uma empresa novamente.',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      // Se recebeu 401 e pode tentar refresh
      // IMPORTANTE: Não tentar refresh em rotas de autenticação (login, logout, etc)
      if (response.statusCode == 401 &&
          retryOn401 &&
          !_isRefreshing &&
          endpoint != null &&
          !endpoint.startsWith('/auth/')) {
        debugPrint('🔄 [API_SERVICE] Token expirado, tentando refresh...');

        // Tentar refresh token
        final refreshResponse = await _refreshTokenIfNeeded();

        if (refreshResponse) {
          // Reexecutar a requisição original
          debugPrint(
            '✅ [API_SERVICE] Token renovado, reexecutando requisição...',
          );
          return await request();
        } else {
          // Refresh falhou, retornar erro
          debugPrint('❌ [API_SERVICE] Falha ao renovar token');
          return ApiResponse.error(
            message: 'Sessão expirada. Faça login novamente.',
            statusCode: 401,
          );
        }
      }

      return response;
    } catch (e) {
      // Tratar exceção de Company ID não encontrado
      if (e.toString().contains('Company ID não encontrado')) {
        debugPrint('❌ [API_SERVICE] Company ID não encontrado - requisição bloqueada');
        return ApiResponse.error(
          message: 'Company ID não encontrado. Por favor, selecione uma empresa.',
          statusCode: 0,
        );
      }

      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Tenta renovar o token se necessário
  Future<bool> _refreshTokenIfNeeded() async {
    if (_isRefreshing) {
      // Se já está renovando, aguardar
      debugPrint('⏳ [API_SERVICE] Refresh já em andamento, aguardando...');
      return await _waitForRefresh();
    }

    _isRefreshing = true;
    try {
      final authService = AuthService.instance;
      final refreshResponse = await authService.refreshToken();

      if (refreshResponse.success && refreshResponse.data != null) {
        _token = refreshResponse.data!.token;
        _notifyPendingRequests(true);
        return true;
      } else {
        _notifyPendingRequests(false);
        return false;
      }
    } catch (e) {
      debugPrint('❌ [API_SERVICE] Erro ao renovar token: $e');
      _notifyPendingRequests(false);
      return false;
    } finally {
      _isRefreshing = false;
    }
  }

  /// Aguarda o refresh em andamento
  Future<bool> _waitForRefresh() async {
    final completer = Completer<bool>();
    _pendingRequests.add(_PendingRequest(completer: completer));
    return completer.future;
  }

  /// Notifica requisições pendentes sobre o resultado do refresh
  void _notifyPendingRequests(bool success) {
    for (final pending in _pendingRequests) {
      pending.completer.complete(success);
    }
    _pendingRequests.clear();
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

/// Classe auxiliar para requisições pendentes durante refresh
class _PendingRequest {
  final Completer<bool> completer;
  _PendingRequest({required this.completer});
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
