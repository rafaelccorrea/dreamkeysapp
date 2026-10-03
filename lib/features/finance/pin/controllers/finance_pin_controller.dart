import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/finance_errors.dart';
import '../services/finance_pin_service.dart';

/// Fases da tela do PIN (paridade com `FinancePinGate.tsx:31-38,117-251`).
enum FinancePinPhase {
  /// Consultando `GET /auth/pin/status`.
  loading,

  /// O status não carregou (rede): tela de "tentar de novo".
  loadError,

  /// Primeiro acesso: digitar o PIN novo.
  create,

  /// Primeiro acesso: repetir o PIN novo.
  confirmCreate,

  /// Digitar o PIN.
  enter,

  /// 5 erros: bloqueado até [FinancePinController.bloqueadoAte].
  blocked,

  /// "Esqueci": código de 6 números do e-mail.
  code,

  /// "Esqueci": PIN novo.
  newPin,

  /// "Esqueci": repetir o PIN novo.
  confirmNewPin,
}

/// Como o desbloqueio aconteceu — a tela usa para oferecer (ou atualizar)
/// a biometria.
enum FinanceUnlockMethod { created, typed, reset, biometric }

/// Máquina de estados da tela do PIN. Sem widget: a lógica é testada com um
/// [FinancePinApi] falso.
class FinancePinController extends ChangeNotifier {
  FinancePinController({
    required FinancePinApi api,
    DateTime Function()? clock,
    this.onUnlocked,
    this.onBiometricPinRejected,
  }) : _api = api,
       _clock = clock ?? DateTime.now;

  final FinancePinApi _api;
  final DateTime Function() _clock;

  /// Desbloqueou: o token já está no store. Recebe o PIN para a biometria.
  final void Function(String pin, FinanceUnlockMethod method)? onUnlocked;

  /// O PIN guardado para a biometria foi recusado (422/404): apagá-lo.
  final VoidCallback? onBiometricPinRejected;

  FinancePinPhase _phase = FinancePinPhase.loading;
  String _buffer = '';
  String? _firstPin;
  String? _code;
  String? _error;
  String? _info;
  DateTime? _bloqueadoAte;
  String? _enviadoPara;
  bool _busy = false;
  int _errorTick = 0;
  bool _disposed = false;

  FinancePinPhase get phase => _phase;
  String get buffer => _buffer;
  String? get error => _error;
  String? get info => _info;
  DateTime? get bloqueadoAte => _bloqueadoAte;
  String? get enviadoPara => _enviadoPara;
  bool get busy => _busy;

  /// Muda a cada erro — a tela "treme" os pontos.
  int get errorTick => _errorTick;

  /// 6 no código do e-mail; 4 no resto.
  int get length => _phase == FinancePinPhase.code ? 6 : 4;

  bool get acceptsDigits =>
      !_busy &&
      (_phase == FinancePinPhase.create ||
          _phase == FinancePinPhase.confirmCreate ||
          _phase == FinancePinPhase.enter ||
          _phase == FinancePinPhase.code ||
          _phase == FinancePinPhase.newPin ||
          _phase == FinancePinPhase.confirmNewPin);

  /// Tempo que falta do bloqueio (zero quando já soltou).
  Duration get blockedRemaining {
    final ate = _bloqueadoAte;
    if (ate == null) return Duration.zero;
    final d = ate.difference(_clock());
    return d.isNegative ? Duration.zero : d;
  }

  Future<void> start() async {
    _set(FinancePinPhase.loading, clearMessages: true);
    final res = await _api.status();
    if (_disposed) return;
    if (!res.success || res.data == null) {
      _error = res.message ?? 'Não deu para abrir o Financeiro agora.';
      _set(FinancePinPhase.loadError);
      return;
    }
    final s = res.data!;
    if (!s.configurado) {
      _set(FinancePinPhase.create);
    } else if (s.bloqueadoAte != null && s.bloqueadoAte!.isAfter(_clock())) {
      _bloqueadoAte = s.bloqueadoAte;
      _set(FinancePinPhase.blocked);
    } else {
      _set(FinancePinPhase.enter);
    }
  }

  void addDigit(int digit) {
    if (!acceptsDigits || digit < 0 || digit > 9) return;
    if (_buffer.length >= length) return;
    _buffer += '$digit';
    _error = null;
    notifyListeners();
    if (_buffer.length == length) unawaited(_submit());
  }

  void backspace() {
    if (_busy || _buffer.isEmpty) return;
    _buffer = _buffer.substring(0, _buffer.length - 1);
    notifyListeners();
  }

  /// O bloqueio venceu (a tela chama pelo cronômetro).
  void blockExpired() {
    if (_phase != FinancePinPhase.blocked) return;
    if (blockedRemaining > Duration.zero) return;
    _bloqueadoAte = null;
    _set(FinancePinPhase.enter, clearMessages: true);
  }

  /// "Esqueci meu PIN": manda o código por e-mail.
  Future<void> forgot() async {
    if (_busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    final res = await _api.esqueci();
    if (_disposed) return;
    _busy = false;
    if (res.success) {
      _enviadoPara = res.data?.enviadoPara;
      _code = null;
      _info =
          'Enviamos um código de 6 números para ${_enviadoPara ?? 'seu e-mail'}. Ele vale 10 minutos.';
      _set(FinancePinPhase.code);
      return;
    }
    final e = _errorOf(res.error, res.message);
    if (e.statusCode == 404) {
      _info = 'Você ainda não tem PIN — é só criar um.';
      _set(FinancePinPhase.create);
      return;
    }
    if (e.code == 'PIN_CODIGO_RECENTE') {
      // Um código acabou de sair: a pessoa provavelmente já o tem.
      _info = e.message;
      _set(FinancePinPhase.code);
      return;
    }
    _fail(e.message);
  }

  /// Volta do fluxo de "esqueci" para digitar o PIN.
  void backToEnter() {
    if (_busy) return;
    _code = null;
    _firstPin = null;
    _set(
      blockedRemaining > Duration.zero
          ? FinancePinPhase.blocked
          : FinancePinPhase.enter,
      clearMessages: true,
    );
  }

  /// PIN liberado pela biometria: conferido no back como um digitado.
  Future<void> submitBiometricPin(String pin) async {
    if (_busy || _phase != FinancePinPhase.enter) return;
    await _verify(pin, viaBiometric: true);
  }

  Future<void> _submit() async {
    final value = _buffer;
    switch (_phase) {
      case FinancePinPhase.create:
        final fraco = motivoPinFraco(value);
        if (fraco != null) {
          _fail(fraco);
          return;
        }
        _firstPin = value;
        _set(FinancePinPhase.confirmCreate, clearMessages: true);
      case FinancePinPhase.confirmCreate:
        if (value != _firstPin) {
          _firstPin = null;
          _set(FinancePinPhase.create);
          {
            _fail('Os PINs não conferem. Crie de novo.');
            return;
          }
        }
        await _run(
          () => _api.setup(value),
          onOk: () {
            _done(value, FinanceUnlockMethod.created);
          },
          onError: (e) {
            if (e.statusCode == 409) {
              _firstPin = null;
              _info = 'Você já tem um PIN. Digite-o para entrar.';
              _set(FinancePinPhase.enter);
              return;
            }
            _firstPin = null;
            _set(FinancePinPhase.create);
            _fail(e.message);
          },
        );
      case FinancePinPhase.enter:
        await _verify(value);
      case FinancePinPhase.code:
        _code = value;
        _set(FinancePinPhase.newPin, clearMessages: true);
      case FinancePinPhase.newPin:
        final fraco = motivoPinFraco(value);
        if (fraco != null) {
          _fail(fraco);
          return;
        }
        _firstPin = value;
        _set(FinancePinPhase.confirmNewPin, clearMessages: true);
      case FinancePinPhase.confirmNewPin:
        if (value != _firstPin) {
          _firstPin = null;
          _set(FinancePinPhase.newPin);
          {
            _fail('Os PINs não conferem. Digite o novo PIN de novo.');
            return;
          }
        }
        await _run(
          () => _api.redefinir(_code ?? '', value),
          onOk: () {
            _done(value, FinanceUnlockMethod.reset);
          },
          onError: (e) {
            _firstPin = null;
            if (e.statusCode == 404) {
              _info = 'Você ainda não tem PIN — é só criar um.';
              _set(FinancePinPhase.create);
              return;
            }
            // Código errado/vencido volta ao código; PIN fraco, ao PIN novo.
            final sobreCodigo =
                e.message.toLowerCase().contains('código') ||
                e.message.toLowerCase().contains('codigo');
            if (sobreCodigo) {
              _code = null;
              _set(FinancePinPhase.code);
            } else {
              _set(FinancePinPhase.newPin);
            }
            _fail(e.message);
          },
        );
      case FinancePinPhase.loading:
      case FinancePinPhase.loadError:
      case FinancePinPhase.blocked:
        break;
    }
  }

  Future<void> _verify(String pin, {bool viaBiometric = false}) async {
    await _run(
      () => _api.verify(pin),
      onOk: () {
        _done(
          pin,
          viaBiometric
              ? FinanceUnlockMethod.biometric
              : FinanceUnlockMethod.typed,
        );
      },
      onError: (e) {
        if (viaBiometric &&
            (e.statusCode == 422 ||
                e.statusCode == 404 ||
                e.statusCode == 400)) {
          onBiometricPinRejected?.call();
        }
        if (e.statusCode == 429) {
          _bloqueadoAte =
              e.bloqueadoAte ?? _clock().add(const Duration(minutes: 15));
          _set(FinancePinPhase.blocked);
          _fail(e.message, clearBuffer: true);
          return;
        }
        if (e.statusCode == 404) {
          // O PIN foi redefinido por quem administra Acessos.
          _info = 'Seu PIN foi redefinido. Crie um novo.';
          _set(FinancePinPhase.create);
          return;
        }
        _fail(
          viaBiometric
              ? 'O PIN guardado não confere mais — digite o PIN. ${e.message}'
              : e.message,
        );
      },
    );
  }

  Future<void> _run(
    Future<dynamic> Function() call, {
    required VoidCallback onOk,
    required void Function(FinanceError e) onError,
  }) async {
    _busy = true;
    _error = null;
    notifyListeners();
    final res = await call();
    if (_disposed) return;
    _busy = false;
    if (res.success == true) {
      onOk();
    } else {
      onError(_errorOf(res.error, res.message as String?));
    }
  }

  void _done(String pin, FinanceUnlockMethod method) {
    _buffer = '';
    _firstPin = null;
    _code = null;
    _error = null;
    notifyListeners();
    onUnlocked?.call(pin, method);
  }

  FinanceError _errorOf(dynamic error, String? message) {
    if (error is FinanceError) return error;
    return FinanceError(
      kind: FinanceErrorKind.server,
      statusCode: 0,
      message: message ?? 'Erro no Financeiro.',
    );
  }

  void _fail(String message, {bool clearBuffer = true}) {
    _error = message;
    if (clearBuffer) _buffer = '';
    _errorTick++;
    notifyListeners();
  }

  void _set(FinancePinPhase phase, {bool clearMessages = false}) {
    _phase = phase;
    _buffer = '';
    if (clearMessages) {
      _error = null;
      _info = null;
    }
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
