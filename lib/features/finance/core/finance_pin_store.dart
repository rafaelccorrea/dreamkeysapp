import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../shared/services/secure_storage_service.dart';
import '../../../shared/utils/jwt_utils.dart';

/// Token de desbloqueio do Financeiro (o `X-Finance-Pin` do back).
///
/// É um JWT curto (`typ: fpin`, `exp` = 2 h, `em` = emissão em ms) assinado
/// pelo back — o app só LÊ o payload para saber quando vence; quem valida é o
/// back (`finance-pin.service.ts:55-58,177-179`).
@immutable
class FinancePinSession {
  final String token;
  final DateTime expiraEm;
  final DateTime emitidoEm;

  /// `sub` do JWT do CRM de quem desbloqueou — o token é da PESSOA (não da
  /// empresa), e outra pessoa logada no mesmo aparelho não pode herdá-lo.
  final String? ownerKey;

  const FinancePinSession({
    required this.token,
    required this.expiraEm,
    required this.emitidoEm,
    this.ownerKey,
  });

  /// Margem para não mandar um token que vence no caminho.
  static const Duration skew = Duration(seconds: 5);

  /// Uso da tela com token mais velho que isto renova (`FinancePinGate.tsx:25-26`).
  static const Duration refreshOnUseAfter = Duration(minutes: 10);

  bool isValidAt(DateTime now) => now.isBefore(expiraEm.subtract(skew));

  bool shouldRefreshOnUse(DateTime now) =>
      isValidAt(now) && now.difference(emitidoEm) > refreshOnUseAfter;

  /// Monta a sessão a partir do token emitido pelo back. `exp`/`em` do
  /// payload mandam; `expiraEm` (ISO da resposta) é o reserva.
  static FinancePinSession? fromToken(
    String token, {
    String? expiraEmIso,
    String? ownerKey,
    required DateTime now,
  }) {
    final t = token.trim();
    if (t.isEmpty) return null;
    final claims = JwtUtils.decodeToken(t) ?? const <String, dynamic>{};
    DateTime? exp;
    final rawExp = claims['exp'];
    if (rawExp is num) {
      exp = DateTime.fromMillisecondsSinceEpoch(rawExp.toInt() * 1000);
    }
    exp ??= expiraEmIso == null
        ? null
        : DateTime.tryParse(expiraEmIso)?.toLocal();
    exp ??= now.add(const Duration(hours: 2));
    DateTime emitido = now;
    final rawEm = claims['em'];
    if (rawEm is num) {
      emitido = DateTime.fromMillisecondsSinceEpoch(rawEm.toInt());
    } else if (claims['iat'] is num) {
      emitido = DateTime.fromMillisecondsSinceEpoch(
        (claims['iat'] as num).toInt() * 1000,
      );
    }
    return FinancePinSession(
      token: t,
      expiraEm: exp,
      emitidoEm: emitido,
      ownerKey: ownerKey,
    );
  }

  Map<String, dynamic> toJson() => {
    'token': token,
    'expiraEm': expiraEm.millisecondsSinceEpoch,
    'emitidoEm': emitidoEm.millisecondsSinceEpoch,
    'ownerKey': ownerKey,
  };

  static FinancePinSession? fromJson(Map<String, dynamic> json) {
    final token = json['token']?.toString() ?? '';
    final exp = json['expiraEm'];
    final em = json['emitidoEm'];
    if (token.isEmpty || exp is! num || em is! num) return null;
    return FinancePinSession(
      token: token,
      expiraEm: DateTime.fromMillisecondsSinceEpoch(exp.toInt()),
      emitidoEm: DateTime.fromMillisecondsSinceEpoch(em.toInt()),
      ownerKey: json['ownerKey']?.toString(),
    );
  }
}

/// Por que o Financeiro está trancado agora.
enum FinanceLockReason {
  /// Ainda não destravou nesta sessão do app.
  notUnlocked,

  /// O token de 2 h venceu (timer ou conferência).
  expired,

  /// O back respondeu 428 `FINANCE_PIN_REQUIRED`.
  pinRequired,

  /// O app foi para o segundo plano (decisão do Edson, 03/10/2026).
  background,

  /// Logout / troca de usuário.
  logout,
}

/// Onde o token mora. Abstrato para os testes rodarem sem plugin.
abstract class FinancePinStorage {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

/// Armazenamento seguro do app (o mesmo `FlutterSecureStorage` do
/// `SecureStorageService`). A chave também é apagada pelo
/// `SecureStorageService.clearTokens()` — logout e sessão vencida.
class SecureFinancePinStorage implements FinancePinStorage {
  const SecureFinancePinStorage();

  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(
        key: SecureStorageService.financePinSessionKey,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String value) async {
    try {
      await _storage.write(
        key: SecureStorageService.financePinSessionKey,
        value: value,
      );
    } catch (e) {
      debugPrint('⚠️ [FINANCE_PIN] Falha ao gravar o token: $e');
    }
  }

  @override
  Future<void> delete() async {
    try {
      await _storage.delete(key: SecureStorageService.financePinSessionKey);
    } catch (_) {}
  }
}

/// Memória (testes).
class MemoryFinancePinStorage implements FinancePinStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async => value = v;
  @override
  Future<void> delete() async => value = null;
}

/// Renovação por uso: `POST /auth/pin/refresh`. Devolve o token novo, ou
/// `null` quando o back recusou (401 = token vencido → tranca). Lança em
/// falha de rede (não tranca).
typedef FinancePinRefresher = Future<String?> Function(String currentToken);

/// Estado do PIN do Financeiro — a máquina de estados do portão.
///
/// Paridade com `financePinStore.ts` + `FinancePinGate.tsx` do web, mais as
/// decisões do Edson (03/10/2026): **tranca ao ir para o segundo plano** e o
/// token de 2 h do back segue como teto, renovado pelo uso.
class FinancePinStore extends ChangeNotifier with WidgetsBindingObserver {
  FinancePinStore({
    FinancePinStorage? storage,
    DateTime Function()? clock,
    Future<String?> Function()? ownerKeyProvider,
  }) : _storage = storage ?? const SecureFinancePinStorage(),
       _clock = clock ?? DateTime.now,
       _ownerKeyProvider = ownerKeyProvider ?? crmSubject;

  static final FinancePinStore instance = FinancePinStore();

  final FinancePinStorage _storage;
  final DateTime Function() _clock;
  final Future<String?> Function() _ownerKeyProvider;

  FinancePinSession? _session;
  bool _loaded = false;
  Future<void>? _loading;
  bool _everUnlocked = false;
  FinanceLockReason _lockReason = FinanceLockReason.notUnlocked;
  Timer? _expiryTimer;
  bool _refreshing = false;
  int _backgroundHolds = 0;
  bool _observing = false;

  /// Renovação por uso — ligada pelo `FinancePinService`.
  FinancePinRefresher? refresher;

  DateTime get now => _clock();
  FinancePinSession? get session => _session;
  FinanceLockReason get lockReason => _lockReason;

  /// Destravado agora (token presente e no prazo).
  bool get isUnlocked => _session != null && _session!.isValidAt(now);

  /// Já destravou alguma vez nesta sessão do app? Decide entre "PIN em tela
  /// cheia" (entrada) e "PIN por cima da tela" (expirou durante o uso).
  bool get everUnlocked => _everUnlocked;

  /// Carrega o token salvo (uma vez). Token de outra pessoa ou vencido é
  /// descartado.
  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    _attachLifecycle();
    try {
      final raw = await _storage.read();
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        final s = decoded is Map
            ? FinancePinSession.fromJson(
                decoded.map((k, v) => MapEntry(k.toString(), v)),
              )
            : null;
        final owner = await _ownerKeyProvider();
        if (s != null &&
            s.isValidAt(now) &&
            (s.ownerKey == null || s.ownerKey == owner)) {
          _session = s;
          _everUnlocked = true;
          _scheduleExpiry();
        } else {
          await _storage.delete();
        }
      }
    } catch (e) {
      debugPrint('⚠️ [FINANCE_PIN] Token salvo ilegível: $e');
      await _storage.delete();
    } finally {
      _loaded = true;
      _loading = null;
    }
    notifyListeners();
  }

  /// Token pronto para ir no `X-Finance-Pin`, ou `null` (trancado). Confere
  /// o prazo e o dono — sessão de outra pessoa é apagada aqui.
  Future<String?> tokenForRequest() async {
    await ensureLoaded();
    final s = _session;
    if (s == null) return null;
    if (!s.isValidAt(now)) {
      lock(FinanceLockReason.expired);
      return null;
    }
    if (s.ownerKey != null) {
      final owner = await _ownerKeyProvider();
      if (owner != null && owner != s.ownerKey) {
        clear();
        return null;
      }
    }
    return s.token;
  }

  /// Desbloqueio (setup/verify/redefinir/refresh devolveram `{token, expiraEm}`).
  Future<void> adopt(String token, {String? expiraEm}) async {
    final owner = await _ownerKeyProvider();
    final s = FinancePinSession.fromToken(
      token,
      expiraEmIso: expiraEm,
      ownerKey: owner,
      now: now,
    );
    if (s == null) return;
    _session = s;
    _everUnlocked = true;
    _loaded = true;
    _scheduleExpiry();
    await _storage.write(jsonEncode(s.toJson()));
    notifyListeners();
  }

  /// Token reemitido pelo back no `X-Finance-Pin-Token` (janela deslizante).
  /// Só vale com o portão aberto: resposta atrasada não destranca.
  Future<void> adoptRenewed(String token) async {
    final atual = _session;
    if (atual == null || token.trim().isEmpty || token == atual.token) return;
    final s = FinancePinSession.fromToken(
      token,
      ownerKey: atual.ownerKey,
      now: now,
    );
    if (s == null) return;
    _session = s;
    _scheduleExpiry();
    await _storage.write(jsonEncode(s.toJson()));
    // Sem notify: o estado visível (destravado) não mudou.
  }

  /// Tranca. A tela continua montada embaixo do PIN (formulário preservado).
  void lock(FinanceLockReason reason) {
    final hadSession = _session != null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _session = null;
    _lockReason = reason;
    unawaited(_storage.delete());
    if (hadSession || reason == FinanceLockReason.pinRequired) {
      debugPrint('🔒 [FINANCE_PIN] Trancado (${reason.name})');
    }
    notifyListeners();
  }

  /// Logout / troca de usuário: apaga tudo, inclusive o "já destravou".
  void clear() {
    _everUnlocked = false;
    lock(FinanceLockReason.logout);
    _lockReason = FinanceLockReason.notUnlocked;
  }

  /// Uso da tela (toque/rolagem). Com token de mais de 10 min, renova — uma
  /// chamada em voo por vez. 401 na renovação tranca; falha de rede, não.
  Future<void> touch() async {
    final s = _session;
    final fn = refresher;
    if (s == null || fn == null || _refreshing) return;
    if (!s.shouldRefreshOnUse(now)) return;
    _refreshing = true;
    try {
      final novo = await fn(s.token);
      if (_session?.token != s.token) return; // trancou/trocou no meio
      if (novo == null) {
        lock(FinanceLockReason.expired);
      } else {
        await adoptRenewed(novo);
      }
    } catch (e) {
      debugPrint('⚠️ [FINANCE_PIN] Renovação por uso falhou (rede): $e');
    } finally {
      _refreshing = false;
    }
  }

  // ─── Segundo plano ──────────────────────────────────────────────────────

  /// Segura a trava de segundo plano enquanto [action] roda — para o
  /// seletor de arquivo/câmera e o prompt de biometria, que tiram o app do
  /// primeiro plano sem a pessoa ter saído.
  Future<T> holdBackgroundLock<T>(Future<T> Function() action) async {
    _backgroundHolds++;
    try {
      return await action();
    } finally {
      // O `resumed` chega logo depois do prompt fechar: solta no próximo
      // ciclo para ele não contar como "voltou do segundo plano".
      Future<void>.delayed(const Duration(milliseconds: 800), () {
        if (_backgroundHolds > 0) _backgroundHolds--;
      });
    }
  }

  bool get isHoldingBackgroundLock => _backgroundHolds > 0;

  /// Mudança de ciclo de vida (pública para os testes).
  void handleLifecycle(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        if (_backgroundHolds > 0) return;
        if (_session != null) lock(FinanceLockReason.background);
      case AppLifecycleState.resumed:
        // Voltou: se venceu enquanto estava fora, tranca agora.
        final s = _session;
        if (s != null && !s.isValidAt(now)) lock(FinanceLockReason.expired);
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      handleLifecycle(state);

  void _attachLifecycle() {
    if (_observing) return;
    try {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    } catch (_) {
      // Sem binding (teste puro): o teste chama `handleLifecycle`.
    }
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    final s = _session;
    if (s == null) return;
    final wait = s.expiraEm.subtract(FinancePinSession.skew).difference(now);
    if (wait.isNegative) {
      _expiryTimer = null;
      return;
    }
    _expiryTimer = Timer(wait, () {
      if (_session?.token == s.token) lock(FinanceLockReason.expired);
    });
  }

  /// `sub` do JWT do CRM logado — a identidade do PIN no aparelho.
  static Future<String?> crmSubject() async {
    final token = await SecureStorageService.instance.getAccessToken();
    if (token == null || token.isEmpty) return null;
    final claims = JwtUtils.decodeToken(token);
    return claims?['sub']?.toString() ?? claims?['userId']?.toString();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
