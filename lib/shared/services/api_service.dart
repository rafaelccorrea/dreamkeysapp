import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/api_constants.dart';
import '../../core/utils/api_connection_message.dart';
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

  /// Verifica se uma rota é exceção (não envia X-Company-ID).
  ///
  /// Paridade com `imobx-front/src/services/api.ts`:
  ///   const isAuthRoute = config.url?.includes('/auth/');
  ///   const isPublicRoute = config.url?.includes('/public/');
  ///
  /// Cobre TODO o espaço `/auth/*` (login, logout, refresh, profile, avatar,
  /// change-password, sessions, 2fa, document-self-service, etc.) e o
  /// espaço `/public/*`. Refresh proativo de token e header `Authorization`
  /// também respeitam essa lista nas chamadas de auth sem token.
  bool _isExceptionRoute(String? endpoint) {
    if (endpoint == null) return false;
    if (endpoint.contains('/auth/')) return true;
    if (endpoint.startsWith('/public/')) return true;
    return false;
  }

  /// Rotas em que o token NÃO deve ser enviado (login/logout/refresh/etc.).
  /// Subconjunto de `_isExceptionRoute`. As demais `/auth/*` (profile, avatar,
  /// sessions, etc.) ainda exigem token mas NÃO recebem `X-Company-ID`.
  bool _isAuthRouteWithoutToken(String? endpoint) {
    if (endpoint == null) return false;
    const noTokenRoutes = {
      '/auth/broker/login',
      '/auth/login',
      '/auth/logout',
      '/auth/refresh',
      '/auth/forgot-password',
      '/auth/reset-password',
      '/auth/check-2fa',
      '/auth/verify-2fa',
    };
    return noTokenRoutes.contains(endpoint);
  }

  /// Verifica se uma rota tem Company ID opcional (envia se tiver, não
  /// bloqueia se faltar). Paridade direta com o `api.ts` do imobx-front.
  bool _isOptionalCompanyIdRoute(String? endpoint) {
    if (endpoint == null) return false;

    // `/companies` (lista) — usada para OBTER o Company ID, então nunca
    // bloqueia. Detalhes de uma empresa (`/companies/<id>`) NÃO são
    // opcionais e seguem o fluxo padrão.
    if (endpoint == ApiConstants.companies || endpoint.endsWith('/companies')) {
      return true;
    }

    // Permissões do próprio usuário — pode ser chamado antes da seleção
    // de empresa (`/permissions/my-permissions`).
    if (endpoint.contains('/permissions/my-permissions')) return true;

    // Assinaturas / planos — `subscriptions/*`, `plans*`.
    if (endpoint.contains('/subscriptions/') || endpoint.contains('/plans')) {
      return true;
    }

    // Notificações — escopo pessoal pode existir sem empresa.
    if (endpoint.contains('/notifications')) return true;

    // Teams — listagem inicial pode acontecer antes do Company ID estar
    // gravado (corrida de inicialização).
    if (endpoint.contains('/teams')) return true;

    // Proxy Autentique (assinaturas de proposta/autorização) — Company ID
    // opcional, paridade `isAutentiqueRoute` no `api.ts` do imobx-front.
    if (endpoint.contains('/autentique')) return true;

    return false;
  }

  /// Rotas onde o Company ID pode estar a ser gravado em paralelo (paridade com
  /// `api.ts` do imobx-front: dashboard, /properties, /kanban).
  bool _mayReceiveCompanyIdSoon(String? endpoint) {
    if (endpoint == null) return false;
    if (endpoint.contains('/dashboard')) return true;
    if (endpoint.startsWith('/properties')) return true;
    if (endpoint.startsWith('/kanban')) return true;
    return false;
  }

  /// Aguarda Company ID aparecer (ex.: após login enquanto `/companies` grava o ID)
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

  /// Helper público para serviços que usam `http.MultipartRequest` ou
  /// `http.get/post/...` direto (fora do `_executeRequest`). Devolve o
  /// mapa de headers seguindo as **mesmas regras** do interceptor do
  /// `imobx-front` (Authorization + X-Company-ID quando aplicável).
  ///
  /// Use sempre que precisar disparar uma requisição multipart ou outro
  /// fluxo que não passa pelo `_executeRequest` (ex.: `/gallery/upload`,
  /// `/properties/import`, `/properties/export`, `/auth/avatar`). Evita
  /// regredir o bug "Usuário deve estar associado a uma empresa" causado
  /// por requests sem o header `X-Company-ID`.
  ///
  /// Quando `excludeContentType` é `true`, o `Content-Type` não é
  /// adicionado — útil para multipart, em que o `http.MultipartRequest`
  /// já define o `Content-Type` com o `boundary` correto.
  Future<Map<String, String>> buildOutboundHeaders({
    String? endpoint,
    bool excludeContentType = false,
  }) async {
    final headers = await _getDefaultHeaders(endpoint);
    if (excludeContentType) {
      headers.remove(ApiConstants.contentTypeHeader);
    }
    return headers;
  }

  /// Headers padrão para requisições.
  ///
  /// Regras (paridade `imobx-front/src/services/api.ts`):
  ///   - `/auth/*` e `/public/*` → não envia `Authorization` apenas em rotas
  ///     auth sem token (login/logout/refresh/etc.); não envia `X-Company-ID`
  ///     em nenhuma `/auth/*` ou `/public/*`.
  ///   - Rotas opcionais (`_isOptionalCompanyIdRoute`) → envia
  ///     `X-Company-ID` se houver, sem bloquear quando faltar.
  ///   - Demais rotas (kanban, properties, dashboard, clients, …) →
  ///     `X-Company-ID` é obrigatório. Em rotas que podem estar correndo
  ///     com a inicialização (`_mayReceiveCompanyIdSoon`) aguardamos até
  ///     2s pelo ID antes de bloquear.
  Future<Map<String, String>> _getDefaultHeaders(String? endpoint) async {
    final isAuthOrPublic = _isExceptionRoute(endpoint);
    final isAuthNoToken = _isAuthRouteWithoutToken(endpoint);
    final isOptionalRoute = _isOptionalCompanyIdRoute(endpoint);
    final mayReceiveCompanySoon = _mayReceiveCompanyIdSoon(endpoint);

    final headers = <String, String>{
      ApiConstants.contentTypeHeader: ApiConstants.contentTypeJson,
      ApiConstants.acceptHeader: ApiConstants.contentTypeJson,
    };

    // Token: ausente apenas em login/logout/refresh/forgot-password/etc.
    // Demais rotas `/auth/*` (profile, avatar, sessions…) ainda exigem o
    // bearer para autenticar a operação do próprio usuário.
    if (_token != null && !isAuthNoToken) {
      headers[ApiConstants.authorizationHeader] =
          '${ApiConstants.bearerPrefix} $_token';
    }

    // X-Company-ID: nunca em `/auth/*` nem `/public/*`.
    if (isAuthOrPublic) return headers;

    String? companyId = await SecureStorageService.instance.getCompanyId();

    if (isOptionalRoute) {
      if (companyId != null && companyId.isNotEmpty) {
        headers['X-Company-ID'] = companyId;
      }
      return headers;
    }

    // Rotas protegidas — Company ID obrigatório.
    if (companyId == null || companyId.isEmpty) {
      if (mayReceiveCompanySoon && _token != null) {
        debugPrint(
          '⏳ [API_SERVICE] Aguardando Company ID (dashboard/imóveis/kanban)...',
        );
        companyId = await _waitForCompanyId(
          maxWait: const Duration(milliseconds: 2000),
        );
      }
    }

    if (companyId == null || companyId.isEmpty) {
      debugPrint(
        '❌ [API_SERVICE] BLOQUEADO: rota protegida sem Company ID — endpoint: $endpoint',
      );
      throw Exception('Company ID não encontrado. Requisição bloqueada.');
    }

    headers['X-Company-ID'] = companyId;
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
    Map<String, dynamic>? body,
    bool retryOn401 = true,
  }) async {
    return _executeRequest<T>(
      () async {
        final uri = Uri.parse('${ApiConstants.baseApiUrl}$endpoint');

        final defaultHeaders = await _getDefaultHeaders(endpoint);
        final merged = <String, String>{...defaultHeaders, ...?headers};
        if (body != null) {
          merged['Content-Type'] = 'application/json';
        }

        final response = await http
            .delete(
              uri,
              headers: merged,
              body: body != null ? jsonEncode(body) : null,
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

      // Tratar erros relacionados a Company ID inválido (400/403).
      //
      // ATENÇÃO: a heurística precisa ser específica — qualquer mensagem de
      // validação que mencione "empresa" (ex.: "Campo obrigatório conforme
      // configuração da empresa: …") foi capturada por engano antes,
      // apagando o `companyId` do dispositivo e desautenticando o usuário.
      // Aqui só reagimos a indícios concretos de Company ID inválido /
      // sem acesso ao recurso da empresa.
      if ((response.statusCode == 400 || response.statusCode == 403) &&
          response.error != null) {
        final errorData = response.error;
        final errorMessage = errorData is Map<String, dynamic>
            ? (errorData['message']?.toString().toLowerCase() ?? '')
            : errorData.toString().toLowerCase();

        bool isCompanyIdProblem;
        if (response.statusCode == 403) {
          // 403 com menção a empresa/company normalmente significa "sem
          // acesso à empresa" — manter o comportamento antigo neste caso.
          isCompanyIdProblem = errorMessage.contains('company') ||
              errorMessage.contains('empresa');
        } else {
          // 400: precisa ser sobre o Company ID em si, não sobre uma
          // configuração da empresa qualquer.
          isCompanyIdProblem = errorMessage.contains('company id') ||
              errorMessage.contains('company_id') ||
              errorMessage.contains('company not found') ||
              errorMessage.contains('invalid company') ||
              errorMessage.contains('missing company') ||
              errorMessage.contains('x-company-id') ||
              errorMessage.contains('empresa não encontrada') ||
              errorMessage.contains('empresa nao encontrada') ||
              errorMessage.contains('empresa inválida') ||
              errorMessage.contains('empresa invalida') ||
              errorMessage.contains('sem acesso à empresa') ||
              errorMessage.contains('sem acesso a empresa') ||
              errorMessage.contains('selecione uma empresa');
        }

        if (isCompanyIdProblem) {
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

      debugPrint(
        '❌ [API_SERVICE] Falha de rede → ${ApiConstants.baseApiUrl}$endpoint → $e',
      );

      return ApiResponse.error(
        message: ApiConnectionMessage.forException(e),
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
    final rawBody = response.body;
    
    debugPrint('📥 [API_SERVICE] _handleResponse');
    debugPrint('   - statusCode: $statusCode');
    debugPrint('   - rawBody length: ${rawBody.length}');
    debugPrint('   - rawBody: $rawBody');
    
    dynamic body;
    if (rawBody.isNotEmpty) {
      try {
        body = jsonDecode(rawBody);
      } catch (e) {
        debugPrint(
          '⚠️ [API_SERVICE] jsonDecode ignorado ($statusCode): $e',
        );
        body = null;
      }
    } else {
      body = null;
    }

    debugPrint('   - parsed body type: ${body?.runtimeType}');
    if (body is Map) {
      debugPrint('   - parsed body keys: ${body.keys.toList()}');
    }

    if (statusCode >= 200 && statusCode < 300) {
      debugPrint('✅ [API_SERVICE] Status code OK, retornando success');
      // jsonDecode às vezes devolve Map sem reificação Map<String, dynamic>, e
      // `body is T` falha — o dashboard (e outros GET) ficavam sem `data` mesmo com 200.
      dynamic normalized = body;
      if (body is Map && body is! Map<String, dynamic>) {
        normalized = Map<String, dynamic>.from(body);
      }
      final data = normalized is T ? normalized : null;
      return ApiResponse.success(data: data, statusCode: statusCode);
    } else {
      debugPrint('❌ [API_SERVICE] Status code de erro');
      final errorMessage = _extractErrorMessage(body);
      debugPrint('   - errorMessage: $errorMessage');
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
