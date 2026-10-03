import 'package:flutter_test/flutter_test.dart';
import 'package:Intellisys/features/finance/core/finance_errors.dart';
import 'package:Intellisys/features/finance/pin/controllers/finance_pin_controller.dart';
import 'package:Intellisys/features/finance/pin/services/finance_pin_service.dart';
import 'package:Intellisys/shared/services/api_service.dart';

import 'finance_test_utils.dart';

ApiResponse<T> _err<T>(int status, Map<String, dynamic> body) {
  final e = FinanceError.fromResponse(status, body);
  return ApiResponse<T>.error(message: e.message, statusCode: status, data: e);
}

class FakePinApi implements FinancePinApi {
  ApiResponse<FinancePinStatus> statusRes = ApiResponse.success(
    data: const FinancePinStatus(configurado: true),
    statusCode: 200,
  );
  ApiResponse<void> setupRes = ApiResponse.success(statusCode: 200);
  ApiResponse<void> verifyRes = ApiResponse.success(statusCode: 200);
  ApiResponse<void> redefinirRes = ApiResponse.success(statusCode: 200);
  ApiResponse<FinancePinForgot> esqueciRes = ApiResponse.success(
    data: const FinancePinForgot(enviadoPara: 'e***@x.com'),
    statusCode: 200,
  );
  final calls = <String>[];

  @override
  Future<ApiResponse<FinancePinStatus>> status() async {
    calls.add('status');
    return statusRes;
  }

  @override
  Future<ApiResponse<void>> setup(String pin) async {
    calls.add('setup:$pin');
    return setupRes;
  }

  @override
  Future<ApiResponse<void>> verify(String pin) async {
    calls.add('verify:$pin');
    return verifyRes;
  }

  @override
  Future<ApiResponse<FinancePinForgot>> esqueci() async {
    calls.add('esqueci');
    return esqueciRes;
  }

  @override
  Future<ApiResponse<void>> redefinir(String codigo, String pin) async {
    calls.add('redefinir:$codigo:$pin');
    return redefinirRes;
  }
}

Future<void> _type(FinancePinController c, String digits) async {
  for (final ch in digits.split('')) {
    c.addDigit(int.parse(ch));
  }
  await Future<void>.delayed(Duration.zero);
}

void main() {
  late FakePinApi api;
  late FakeClock clock;
  late List<(String, FinanceUnlockMethod)> unlocked;
  late int bioRejected;

  FinancePinController newController() => FinancePinController(
    api: api,
    clock: clock.call,
    onUnlocked: (pin, m) => unlocked.add((pin, m)),
    onBiometricPinRejected: () => bioRejected++,
  );

  setUp(() {
    api = FakePinApi();
    clock = FakeClock(DateTime(2026, 10, 3, 10));
    unlocked = [];
    bioRejected = 0;
  });

  test('motivoPinFraco: repetidos e sequências são recusados', () {
    expect(motivoPinFraco('1111'), isNotNull);
    expect(motivoPinFraco('1234'), isNotNull);
    expect(motivoPinFraco('4321'), isNotNull);
    expect(motivoPinFraco('123'), isNotNull);
    expect(motivoPinFraco('2580'), isNull);
  });

  test('sem PIN: criar → confirmar → setup → destrava', () async {
    api.statusRes = ApiResponse.success(
      data: const FinancePinStatus(configurado: false),
      statusCode: 200,
    );
    final c = newController();
    await c.start();
    expect(c.phase, FinancePinPhase.create);

    await _type(c, '1234');
    expect(c.phase, FinancePinPhase.create, reason: 'sequência recusada');
    expect(c.error, contains('sequências'));

    await _type(c, '2580');
    expect(c.phase, FinancePinPhase.confirmCreate);
    await _type(c, '2581');
    expect(c.phase, FinancePinPhase.create, reason: 'não conferem');

    await _type(c, '2580');
    await _type(c, '2580');
    expect(api.calls, contains('setup:2580'));
    expect(unlocked.single, ('2580', FinanceUnlockMethod.created));
  });

  test('setup 409 (PIN criado em outro aparelho) vai para digitar', () async {
    api.statusRes = ApiResponse.success(
      data: const FinancePinStatus(configurado: false),
      statusCode: 200,
    );
    api.setupRes = _err(409, {'message': 'Você já tem um PIN.'});
    final c = newController();
    await c.start();
    await _type(c, '2580');
    await _type(c, '2580');
    expect(c.phase, FinancePinPhase.enter);
    expect(unlocked, isEmpty);
  });

  test('digitar: 422 mostra tentativas restantes', () async {
    api.verifyRes = _err(422, {
      'code': 'PIN_INCORRETO',
      'message':
          'PIN incorreto. Restam 3 tentativas antes do bloqueio de 15 minutos.',
      'tentativasRestantes': 3,
    });
    final c = newController();
    await c.start();
    expect(c.phase, FinancePinPhase.enter);
    final tick = c.errorTick;
    await _type(c, '9999');
    expect(c.phase, FinancePinPhase.enter);
    expect(c.error, contains('Restam 3 tentativas'));
    expect(c.buffer, isEmpty);
    expect(c.errorTick, tick + 1);
  });

  test('digitar: 429 bloqueia até bloqueadoAte e solta depois', () async {
    final ate = clock.now.add(const Duration(minutes: 15));
    api.verifyRes = _err(429, {
      'code': 'PIN_BLOQUEADO',
      'message': 'Muitas tentativas erradas.',
      'bloqueadoAte': ate.toUtc().toIso8601String(),
    });
    final c = newController();
    await c.start();
    await _type(c, '9999');
    expect(c.phase, FinancePinPhase.blocked);
    expect(c.acceptsDigits, isFalse);
    expect(c.blockedRemaining.inMinutes, 15);

    clock.advance(const Duration(minutes: 16));
    c.blockExpired();
    expect(c.phase, FinancePinPhase.enter);
  });

  test('status já bloqueado abre direto na contagem', () async {
    api.statusRes = ApiResponse.success(
      data: FinancePinStatus(
        configurado: true,
        bloqueadoAte: clock.now.add(const Duration(minutes: 5)),
      ),
      statusCode: 200,
    );
    final c = newController();
    await c.start();
    expect(c.phase, FinancePinPhase.blocked);
  });

  test('digitar: 404 (PIN redefinido pelo admin) volta a criar', () async {
    api.verifyRes = _err(404, {'message': 'Você ainda não criou seu PIN.'});
    final c = newController();
    await c.start();
    await _type(c, '2580');
    expect(c.phase, FinancePinPhase.create);
  });

  test('esqueci → código → novo PIN → redefinir → destrava', () async {
    final c = newController();
    await c.start();
    await c.forgot();
    expect(c.phase, FinancePinPhase.code);
    expect(c.length, 6);
    expect(c.enviadoPara, 'e***@x.com');

    await _type(c, '123456');
    expect(c.phase, FinancePinPhase.newPin);
    await _type(c, '1357');
    expect(c.phase, FinancePinPhase.confirmNewPin);
    await _type(c, '1357');
    expect(api.calls, contains('redefinir:123456:1357'));
    expect(unlocked.single, ('1357', FinanceUnlockMethod.reset));
  });

  test('redefinir com código errado volta ao código', () async {
    api.redefinirRes = _err(400, {
      'message': 'Código incorreto. Restam 4 tentativas.',
    });
    final c = newController();
    await c.start();
    await c.forgot();
    await _type(c, '000000');
    await _type(c, '1357');
    await _type(c, '1357');
    expect(c.phase, FinancePinPhase.code);
    expect(c.error, contains('Código incorreto'));
  });

  test('esqueci com código recente (429) vai ao código mesmo assim', () async {
    api.esqueciRes = _err(429, {
      'code': 'PIN_CODIGO_RECENTE',
      'message': 'Um código acabou de ser enviado. Aguarde 40s.',
    });
    final c = newController();
    await c.start();
    await c.forgot();
    expect(c.phase, FinancePinPhase.code);
    expect(c.info, contains('Aguarde'));
  });

  test('PIN da biometria recusado (422) apaga o PIN guardado', () async {
    api.verifyRes = _err(422, {
      'code': 'PIN_INCORRETO',
      'message': 'PIN incorreto. Restam 4 tentativas.',
    });
    final c = newController();
    await c.start();
    await c.submitBiometricPin('2580');
    expect(bioRejected, 1);
    expect(c.phase, FinancePinPhase.enter);
    expect(unlocked, isEmpty);
  });

  test('biometria aceita destrava pelo /verify', () async {
    final c = newController();
    await c.start();
    await c.submitBiometricPin('2580');
    expect(api.calls, contains('verify:2580'));
    expect(unlocked.single, ('2580', FinanceUnlockMethod.biometric));
  });

  test('status sem rede mostra "tentar de novo"', () async {
    api.statusRes = ApiResponse.error(message: 'Sem conexão', statusCode: 0);
    final c = newController();
    await c.start();
    expect(c.phase, FinancePinPhase.loadError);
    expect(c.acceptsDigits, isFalse);
  });
}
