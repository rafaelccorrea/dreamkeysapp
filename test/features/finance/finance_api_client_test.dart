import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Intellisys/features/finance/core/finance_api_client.dart';
import 'package:Intellisys/features/finance/core/finance_errors.dart';
import 'package:Intellisys/features/finance/core/finance_pin_store.dart';

import 'finance_test_utils.dart';

void main() {
  group('buildFinanceHeaders', () {
    test('Bearer do CRM + X-Company-ID + X-Finance-Pin', () {
      final h = buildFinanceHeaders(
        accessToken: 'crm-jwt',
        companyId: 'empresa-uuid',
        pinToken: 'pin-jwt',
      );
      expect(h['Authorization'], 'Bearer crm-jwt');
      expect(h['X-Company-ID'], 'empresa-uuid');
      expect(h['X-Finance-Pin'], 'pin-jwt');
      expect(h['Content-Type'], 'application/json');
    });

    test('sem PIN não manda o header vazio', () {
      final h = buildFinanceHeaders(accessToken: 't', companyId: 'c');
      expect(h.containsKey('X-Finance-Pin'), isFalse);
    });
  });

  test('buildFinanceUri descarta query nula/vazia', () {
    final uri = buildFinanceUri('https://x/api/v1/', '/requests', {
      'page': 1,
      'search': '',
      'status': null,
    });
    expect(uri.toString(), 'https://x/api/v1/requests?page=1');
  });

  group('FinanceApiClient', () {
    late FakeClock clock;
    late FinancePinStore store;
    late List<http.BaseRequest> sent;

    FinanceApiClient client(
      Future<http.Response> Function(http.Request r) handler, {
      String? company = 'empresa-uuid',
    }) {
      return FinanceApiClient(
        httpClient: MockClient((r) {
          sent.add(r);
          return handler(r);
        }),
        accessTokenProvider: () async => 'crm-jwt',
        companyIdProvider: () async => company,
        pinStore: store,
        baseUrl: 'https://fin.test/api/v1',
      );
    }

    setUp(() async {
      clock = FakeClock(DateTime(2026, 10, 3, 10));
      sent = [];
      store = FinancePinStore(
        storage: MemoryFinancePinStorage(),
        clock: clock.call,
        ownerKeyProvider: () async => 'user-1',
      );
      await store.ensureLoaded();
    });

    test(
      'X-Company-ID vai também em /auth/* (armadilha do ApiService)',
      () async {
        final c = client((_) async => http.Response('{"linked":true}', 200));
        await c.get<Map<String, dynamic>>('/auth/me');
        await c.get<Map<String, dynamic>>('/auth/pin/status');
        for (final r in sent) {
          expect(r.headers['X-Company-ID'], 'empresa-uuid');
          expect(r.headers['Authorization'], 'Bearer crm-jwt');
        }
      },
    );

    test('manda o PIN atual e adota o X-Finance-Pin-Token renovado', () async {
      final antigo = fakePinJwt(clock.now);
      await store.adopt(antigo);
      clock.advance(const Duration(minutes: 6));
      final novo = fakePinJwt(clock.now);
      final c = client(
        (_) async => http.Response(
          '{"ok":true}',
          200,
          headers: {'x-finance-pin-token': novo},
        ),
      );
      final res = await c.get<Map<String, dynamic>>(
        '/repasses/broker-dashboard',
      );
      expect(res.success, isTrue);
      expect(sent.single.headers['X-Finance-Pin'], antigo);
      await Future<void>.delayed(Duration.zero);
      expect(store.session!.token, novo);
    });

    test('428 FINANCE_PIN_REQUIRED tranca o PIN', () async {
      await store.adopt(fakePinJwt(clock.now));
      final c = client(
        (_) async => http.Response(
          jsonEncode({
            'statusCode': 428,
            'code': 'FINANCE_PIN_REQUIRED',
            'message': 'Digite seu PIN para acessar o Financeiro.',
          }),
          428,
        ),
      );
      final res = await c.get<dynamic>('/requests');
      expect(res.success, isFalse);
      expect(res.financeError!.kind, FinanceErrorKind.pinRequired);
      expect(store.isUnlocked, isFalse);
      expect(store.lockReason, FinanceLockReason.pinRequired);
      expect(store.everUnlocked, isTrue, reason: 'PIN por cima da tela');
    });

    test('401 NÃO tranca o PIN nem desloga: vira erro na tela', () async {
      await store.adopt(fakePinJwt(clock.now));
      final c = client(
        (_) async => http.Response('{"message":"Unauthorized"}', 401),
      );
      final res = await c.get<dynamic>('/repasses/broker-dashboard');
      expect(res.financeError!.kind, FinanceErrorKind.unauthorized);
      expect(res.statusCode, 401);
      expect(store.isUnlocked, isTrue);
      expect(sent, hasLength(1), reason: 'sem retry em laço');
    });

    test('403 COMPANY_NOT_PROVISIONED vira mensagem de empresa', () async {
      final c = client(
        (_) async => http.Response(
          jsonEncode({'code': 'COMPANY_NOT_PROVISIONED', 'message': 'x'}),
          403,
        ),
      );
      final res = await c.get<dynamic>('/repasses/broker-dashboard');
      final e = res.financeError!;
      expect(e.kind, FinanceErrorKind.companyNotProvisioned);
      expect(e.message, contains('não tem o módulo Financeiro'));
    });

    test('sem empresa selecionada nem chega a chamar', () async {
      final c = client((_) async => http.Response('{}', 200), company: null);
      final res = await c.get<dynamic>('/requests');
      expect(res.success, isFalse);
      expect(sent, isEmpty);
    });

    test('falha de rede vira FinanceErrorKind.network', () async {
      final c = client((_) async => throw http.ClientException('offline'));
      final res = await c.get<dynamic>('/requests');
      expect(res.financeError!.kind, FinanceErrorKind.network);
    });
  });

  group('FinanceError.fromResponse', () {
    test('422 PIN_INCORRETO expõe tentativas restantes', () {
      final e = FinanceError.fromResponse(422, {
        'code': 'PIN_INCORRETO',
        'message': 'PIN incorreto. Restam 3 tentativas…',
        'tentativasRestantes': 3,
      });
      expect(e.kind, FinanceErrorKind.validation);
      expect(e.tentativasRestantes, 3);
    });

    test('429 PIN_BLOQUEADO expõe bloqueadoAte', () {
      final e = FinanceError.fromResponse(429, {
        'code': 'PIN_BLOQUEADO',
        'message': 'Muitas tentativas…',
        'bloqueadoAte': '2026-10-03T13:15:00.000Z',
      });
      expect(e.kind, FinanceErrorKind.tooMany);
      expect(e.bloqueadoAte, isNotNull);
    });

    test('403 de papel traduz allowedRoles', () {
      final e = FinanceError.fromResponse(403, {
        'message': 'Seu papel não permite.',
        'allowedRoles': ['GERENTE_FINANCEIRO', 'ADMIN'],
      });
      expect(e.kind, FinanceErrorKind.forbidden);
      expect(e.message, contains('Gerente financeiro'));
      expect(e.message, contains('Administrador'));
    });

    test('428 sem o código do PIN não é tratado como PIN', () {
      final e = FinanceError.fromResponse(428, {'message': 'outro'});
      expect(e.kind, isNot(FinanceErrorKind.pinRequired));
    });
  });
}
