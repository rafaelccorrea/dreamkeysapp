import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import '../../../core/session/session_bootstrap.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/services/secure_storage_service.dart';
import 'finance_config.dart';
import 'finance_errors.dart';
import 'finance_pin_store.dart';

/// Cabeçalhos de toda chamada ao Financeiro (função pura, coberta por teste).
///
/// Contrato (`financeiro-app-plano.md` §3):
/// - `Authorization: Bearer <JWT do CRM>` — sem troca de token;
/// - `X-Company-ID` SEMPRE, inclusive em `/auth/*` (o `/auth/me` usa o
///   header para o `companyDenial`). É por isso que este cliente NÃO usa o
///   `ApiService.buildOutboundHeaders`, que corta o header em `/auth/*`;
/// - `X-Finance-Pin` quando há desbloqueio.
Map<String, String> buildFinanceHeaders({
  required String? accessToken,
  required String companyId,
  String? pinToken,
  bool json = true,
}) {
  return <String, String>{
    'Accept': 'application/json',
    if (json) 'Content-Type': 'application/json',
    if (accessToken != null && accessToken.isNotEmpty)
      'Authorization': 'Bearer $accessToken',
    FinanceConfig.companyHeader: companyId,
    if (pinToken != null && pinToken.isNotEmpty)
      FinanceConfig.pinHeader: pinToken,
  };
}

/// Monta a URL com query, descartando valores nulos/vazios (o back usa
/// `forbidNonWhitelisted`; mandar `search=` vazio à toa é ruído).
Uri buildFinanceUri(
  String baseUrl,
  String path, [
  Map<String, Object?>? query,
]) {
  final base = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  final p = path.startsWith('/') ? path : '/$path';
  final uri = Uri.parse('$base$p');
  final q = <String, String>{};
  query?.forEach((k, v) {
    if (v == null) return;
    final s = v.toString();
    if (s.isEmpty) return;
    q[k] = s;
  });
  return q.isEmpty ? uri : uri.replace(queryParameters: q);
}

/// Cliente HTTP do microserviço Financeiro.
///
/// - Renova o JWT do CRM antes de chamar (fila única do `ApiService`), então
///   um 401 daqui com token fresco quer dizer "não alcança o Financeiro" — e
///   **nunca** desloga o app (bug "loga, mas sai" do web).
/// - Lê o `X-Finance-Pin-Token` de toda resposta (janela deslizante).
/// - 428 `FINANCE_PIN_REQUIRED` tranca o [FinancePinStore]: o portão mostra o
///   PIN por cima da tela, sem desmontá-la.
/// - Erros viram [FinanceError] em `ApiResponse.error`.
class FinanceApiClient {
  FinanceApiClient({
    http.Client? httpClient,
    Future<String?> Function()? accessTokenProvider,
    Future<String?> Function()? companyIdProvider,
    FinancePinStore? pinStore,
    String? baseUrl,
  }) : _http = httpClient ?? http.Client(),
       _accessToken = accessTokenProvider ?? _defaultAccessToken,
       _companyId = companyIdProvider ?? _defaultCompanyId,
       _pinStoreOverride = pinStore,
       baseUrl = baseUrl ?? FinanceConfig.baseUrl;

  static final FinanceApiClient instance = FinanceApiClient();

  final http.Client _http;
  final Future<String?> Function() _accessToken;
  final Future<String?> Function() _companyId;
  final FinancePinStore? _pinStoreOverride;
  final String baseUrl;

  FinancePinStore get _pins => _pinStoreOverride ?? FinancePinStore.instance;

  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, Object?>? query,
    Duration? timeout,
  }) => _send<T>('GET', path, query: query, timeout: timeout);

  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? body,
    Map<String, String>? extraHeaders,
    Duration? timeout,
  }) => _send<T>(
    'POST',
    path,
    body: body,
    extraHeaders: extraHeaders,
    timeout: timeout,
  );

  Future<ApiResponse<T>> patch<T>(
    String path, {
    Object? body,
    Duration? timeout,
  }) => _send<T>('PATCH', path, body: body, timeout: timeout);

  Future<ApiResponse<T>> delete<T>(String path, {Duration? timeout}) =>
      _send<T>('DELETE', path, timeout: timeout);

  /// Upload multipart (anexos do time financeiro — `POST
  /// /financial/anexos/upload`). Mesmos cabeçalhos/erros das outras chamadas.
  Future<ApiResponse<T>> postMultipart<T>(
    String path, {
    required List<int> bytes,
    required String filename,
    String fileField = 'file',
    String? mimeType,
    Map<String, String> fields = const {},
    Duration? timeout,
  }) async {
    final companyId = await _companyId();
    if (companyId == null || companyId.isEmpty) {
      return ApiResponse<T>.error(
        message: FinanceError.noCompany().message,
        statusCode: 0,
        data: FinanceError.noCompany(),
      );
    }
    final accessToken = await _accessToken();
    final pinToken = await _pins.tokenForRequest();
    final uri = buildFinanceUri(baseUrl, path);
    http.Response response;
    try {
      final req = http.MultipartRequest('POST', uri)
        ..headers.addAll(
          buildFinanceHeaders(
            accessToken: accessToken,
            companyId: companyId,
            pinToken: pinToken,
            json: false,
          ),
        )
        ..fields.addAll(fields)
        ..files.add(
          http.MultipartFile.fromBytes(
            fileField,
            bytes,
            filename: filename,
            contentType: mimeType == null ? null : _mediaType(mimeType),
          ),
        );
      final streamed = await _http
          .send(req)
          .timeout(timeout ?? FinanceConfig.uploadTimeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      final e = FinanceError.network(timeout: true);
      return ApiResponse<T>.error(message: e.message, statusCode: 0, data: e);
    } catch (err) {
      debugPrint('⚠️ [FINANCE_API] upload ${uri.path} falhou: $err');
      final e = FinanceError.network();
      return ApiResponse<T>.error(message: e.message, statusCode: 0, data: e);
    }
    return handleResponse<T>(response, sentPinToken: pinToken);
  }

  static MediaType? _mediaType(String mime) {
    try {
      return MediaType.parse(mime);
    } catch (_) {
      return null;
    }
  }

  Future<ApiResponse<T>> _send<T>(
    String method,
    String path, {
    Map<String, Object?>? query,
    Object? body,
    Map<String, String>? extraHeaders,
    Duration? timeout,
  }) async {
    final companyId = await _companyId();
    if (companyId == null || companyId.isEmpty) {
      return ApiResponse<T>.error(
        message: FinanceError.noCompany().message,
        statusCode: 0,
        data: FinanceError.noCompany(),
      );
    }
    final accessToken = await _accessToken();
    final pinToken = await _pins.tokenForRequest();
    final headers = {
      ...buildFinanceHeaders(
        accessToken: accessToken,
        companyId: companyId,
        pinToken: pinToken,
        json: body != null || method != 'GET',
      ),
      ...?extraHeaders,
    };
    final uri = buildFinanceUri(baseUrl, path, query);

    http.Response response;
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      final streamed = await _http
          .send(req)
          .timeout(timeout ?? FinanceConfig.timeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      final e = FinanceError.network(timeout: true);
      return ApiResponse<T>.error(message: e.message, statusCode: 0, data: e);
    } catch (err) {
      // SocketException, ClientException, handshake… — tudo é "sem rede".
      debugPrint('⚠️ [FINANCE_API] $method ${uri.path} falhou: $err');
      final e = FinanceError.network();
      return ApiResponse<T>.error(message: e.message, statusCode: 0, data: e);
    }

    return handleResponse<T>(response, sentPinToken: pinToken);
  }

  /// Trata a resposta (pública para os testes): renova o PIN pelo header,
  /// tranca no 428 e normaliza o erro. Nunca desloga.
  ApiResponse<T> handleResponse<T>(
    http.Response response, {
    String? sentPinToken,
  }) {
    final renovado = response.headers[FinanceConfig.pinRenewedHeader];
    if (renovado != null && renovado.isNotEmpty) {
      unawaited(_pins.adoptRenewed(renovado));
    }

    dynamic decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = null;
      }
    }

    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      dynamic data = decoded;
      if (decoded is Map && decoded is! Map<String, dynamic>) {
        data = decoded.map((k, v) => MapEntry(k.toString(), v));
      }
      return ApiResponse<T>.success(
        data: data is T ? data : null,
        statusCode: status,
      );
    }

    final error = FinanceError.fromResponse(status, decoded);
    if (error.kind == FinanceErrorKind.pinRequired) {
      // Só tranca se o token recusado ainda é o atual (uma resposta atrasada
      // não derruba um desbloqueio feito depois).
      final atual = _pins.session?.token;
      if (atual == null || atual == sentPinToken) {
        _pins.lock(FinanceLockReason.pinRequired);
      }
    }
    if (error.kind == FinanceErrorKind.unauthorized) {
      debugPrint(
        '⚠️ [FINANCE_API] 401 em ${response.request?.url.path} — '
        'sessão do app mantida (o Financeiro não desloga)',
      );
    }
    return ApiResponse<T>.error(
      message: error.message,
      statusCode: status,
      data: error,
    );
  }

  static Future<String?> _defaultAccessToken() =>
      ApiService.instance.garantirTokenFresco(margemSegundos: 120);

  static Future<String?> _defaultCompanyId() async {
    var id = await SecureStorageService.instance.getCompanyId();
    if (id != null && id.isNotEmpty) return id;
    if (SessionBootstrap.instance.userHasNoCompany) return null;
    await SessionBootstrap.instance.ensureReady(
      timeout: const Duration(seconds: 8),
    );
    id = await SecureStorageService.instance.getCompanyId();
    return id;
  }
}

/// Leitura do erro normalizado de uma resposta do [FinanceApiClient].
extension FinanceApiResponseX<T> on ApiResponse<T> {
  FinanceError? get financeError {
    final e = error;
    if (e is FinanceError) return e;
    if (success) return null;
    return FinanceError(
      kind: FinanceErrorKind.server,
      statusCode: statusCode,
      message: message ?? 'Erro no Financeiro.',
    );
  }
}
