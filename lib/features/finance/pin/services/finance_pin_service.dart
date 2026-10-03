import '../../../../shared/services/api_service.dart';
import '../../core/finance_api_client.dart';
import '../../core/finance_errors.dart';
import '../../core/finance_pin_store.dart';

/// `GET /auth/pin/status`.
class FinancePinStatus {
  final bool configurado;
  final DateTime? bloqueadoAte;

  const FinancePinStatus({required this.configurado, this.bloqueadoAte});

  factory FinancePinStatus.fromJson(Map<String, dynamic> json) {
    final ate = json['bloqueadoAte'];
    return FinancePinStatus(
      configurado: json['configurado'] == true,
      bloqueadoAte: ate is String ? DateTime.tryParse(ate)?.toLocal() : null,
    );
  }
}

/// `POST /auth/pin/esqueci` → `{enviadoPara: "e***@x", expiraEm}`.
class FinancePinForgot {
  final String enviadoPara;
  final DateTime? expiraEm;

  const FinancePinForgot({required this.enviadoPara, this.expiraEm});
}

/// Contrato que a tela do PIN usa (fake nos testes).
abstract class FinancePinApi {
  Future<ApiResponse<FinancePinStatus>> status();
  Future<ApiResponse<void>> setup(String pin);
  Future<ApiResponse<void>> verify(String pin);
  Future<ApiResponse<FinancePinForgot>> esqueci();
  Future<ApiResponse<void>> redefinir(String codigo, String pin);
}

/// Por que o PIN novo é recusado (porte de `motivoPinFraco`,
/// `finance-pin.regras.ts:45-54`) — conferido aqui para não gastar uma ida
/// ao back com 1234.
String? motivoPinFraco(String pin) {
  if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
    return 'O PIN tem de ter exatamente 4 números.';
  }
  final d = pin.split('').map(int.parse).toList();
  if (d.every((x) => x == d[0])) {
    return 'Evite números repetidos (como 1111). Escolha outro PIN.';
  }
  final passos = [for (var i = 1; i < d.length; i++) d[i] - d[i - 1]];
  if (passos.every((p) => p == 1) || passos.every((p) => p == -1)) {
    return 'Evite sequências (como 1234 ou 4321). Escolha outro PIN.';
  }
  return null;
}

/// Endpoints do PIN (`finance-pin.controller.ts`). Todo desbloqueio grava o
/// token no [FinancePinStore].
class FinancePinService implements FinancePinApi {
  FinancePinService({FinanceApiClient? client, FinancePinStore? store})
    : _clientOverride = client,
      _storeOverride = store;

  static final FinancePinService instance = FinancePinService();

  final FinanceApiClient? _clientOverride;
  final FinancePinStore? _storeOverride;

  FinanceApiClient get _client => _clientOverride ?? FinanceApiClient.instance;
  FinancePinStore get _store => _storeOverride ?? FinancePinStore.instance;

  /// Liga a renovação por uso do store a `POST /auth/pin/refresh`.
  void attach() {
    _store.refresher ??= refresh;
  }

  @override
  Future<ApiResponse<FinancePinStatus>> status() async {
    final res = await _client.get<Map<String, dynamic>>('/auth/pin/status');
    if (res.success && res.data != null) {
      return ApiResponse.success(
        data: FinancePinStatus.fromJson(res.data!),
        statusCode: res.statusCode,
      );
    }
    return _fail(res);
  }

  @override
  Future<ApiResponse<void>> setup(String pin) =>
      _unlock('/auth/pin/setup', {'pin': pin});

  @override
  Future<ApiResponse<void>> verify(String pin) =>
      _unlock('/auth/pin/verify', {'pin': pin});

  @override
  Future<ApiResponse<void>> redefinir(String codigo, String pin) =>
      _unlock('/auth/pin/redefinir', {'codigo': codigo, 'pin': pin});

  @override
  Future<ApiResponse<FinancePinForgot>> esqueci() async {
    final res = await _client.post<Map<String, dynamic>>(
      '/auth/pin/esqueci',
      body: const <String, dynamic>{},
    );
    if (res.success) {
      final m = res.data ?? const <String, dynamic>{};
      final exp = m['expiraEm'];
      return ApiResponse.success(
        data: FinancePinForgot(
          enviadoPara: m['enviadoPara']?.toString() ?? 'seu e-mail',
          expiraEm: exp is String ? DateTime.tryParse(exp)?.toLocal() : null,
        ),
        statusCode: res.statusCode,
      );
    }
    return _fail(res);
  }

  /// Renovação por uso. `null` = o back recusou (tranca); lança se não houve
  /// resposta (rede) — o store não tranca por queda de rede.
  Future<String?> refresh(String currentToken) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/auth/pin/refresh',
      body: const <String, dynamic>{},
    );
    if (res.success) {
      final token = res.data?['token']?.toString();
      if (token == null || token.isEmpty) return null;
      return token;
    }
    final err = res.financeError;
    if (err?.kind == FinanceErrorKind.network) {
      throw StateError(err!.message);
    }
    return null;
  }

  Future<ApiResponse<void>> _unlock(
    String path,
    Map<String, dynamic> body,
  ) async {
    final res = await _client.post<Map<String, dynamic>>(path, body: body);
    if (res.success) {
      final token = res.data?['token']?.toString() ?? '';
      if (token.isEmpty) {
        return ApiResponse.error(
          message: 'O Financeiro não devolveu o desbloqueio. Tente de novo.',
          statusCode: res.statusCode,
        );
      }
      await _store.adopt(token, expiraEm: res.data?['expiraEm']?.toString());
      return ApiResponse.success(statusCode: res.statusCode);
    }
    return _fail(res);
  }

  ApiResponse<R> _fail<R>(ApiResponse<dynamic> res) => ApiResponse<R>.error(
    message: res.message ?? 'Erro no Financeiro.',
    statusCode: res.statusCode,
    data: res.financeError,
  );
}
