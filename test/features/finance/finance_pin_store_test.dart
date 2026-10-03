import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Intellisys/features/finance/core/finance_pin_store.dart';

import 'finance_test_utils.dart';

void main() {
  late FakeClock clock;
  late MemoryFinancePinStorage storage;
  String? owner;

  FinancePinStore newStore() => FinancePinStore(
    storage: storage,
    clock: clock.call,
    ownerKeyProvider: () async => owner,
  );

  setUp(() {
    clock = FakeClock(DateTime(2026, 10, 3, 10));
    storage = MemoryFinancePinStorage();
    owner = 'user-1';
  });

  group('FinancePinSession', () {
    test('lê exp/em do token e vence em 2 h', () {
      final s = FinancePinSession.fromToken(
        fakePinJwt(clock.now),
        now: clock.now,
      )!;
      expect(s.expiraEm, clock.now.add(const Duration(hours: 2)));
      expect(s.isValidAt(clock.now), isTrue);
      expect(s.isValidAt(clock.now.add(const Duration(hours: 2))), isFalse);
    });

    test('só renova pelo uso com mais de 10 min de idade', () {
      final s = FinancePinSession.fromToken(
        fakePinJwt(clock.now),
        now: clock.now,
      )!;
      expect(
        s.shouldRefreshOnUse(clock.now.add(const Duration(minutes: 9))),
        isFalse,
      );
      expect(
        s.shouldRefreshOnUse(clock.now.add(const Duration(minutes: 11))),
        isTrue,
      );
    });
  });

  group('FinancePinStore', () {
    test('começa trancado; adopt destrava e grava no armazenamento', () async {
      final store = newStore();
      await store.ensureLoaded();
      expect(store.isUnlocked, isFalse);
      expect(store.everUnlocked, isFalse);

      await store.adopt(fakePinJwt(clock.now));
      expect(store.isUnlocked, isTrue);
      expect(store.everUnlocked, isTrue);
      expect(await store.tokenForRequest(), isNotNull);
      expect(storage.value, isNotNull);
      expect(jsonDecode(storage.value!)['ownerKey'], 'user-1');
    });

    test('vence em 2 h: tokenForRequest tranca e devolve null', () async {
      final store = newStore();
      await store.adopt(fakePinJwt(clock.now));
      clock.advance(const Duration(hours: 2, minutes: 1));
      expect(store.isUnlocked, isFalse);
      expect(await store.tokenForRequest(), isNull);
      expect(store.lockReason, FinanceLockReason.expired);
      expect(storage.value, isNull);
    });

    test('428 (lock pinRequired) tranca sem perder o "já destravou"', () async {
      final store = newStore();
      await store.adopt(fakePinJwt(clock.now));
      store.lock(FinanceLockReason.pinRequired);
      expect(store.isUnlocked, isFalse);
      // Expirou durante o uso → o PIN aparece POR CIMA da tela.
      expect(store.everUnlocked, isTrue);
    });

    test('ir para o segundo plano tranca (decisão do Edson)', () async {
      final store = newStore();
      await store.adopt(fakePinJwt(clock.now));
      store.handleLifecycle(AppLifecycleState.inactive);
      expect(store.isUnlocked, isTrue, reason: 'inactive não tranca');
      store.handleLifecycle(AppLifecycleState.paused);
      expect(store.isUnlocked, isFalse);
      expect(store.lockReason, FinanceLockReason.background);
    });

    test(
      'prompt de biometria/seletor segura a trava de segundo plano',
      () async {
        final store = newStore();
        await store.adopt(fakePinJwt(clock.now));
        await store.holdBackgroundLock(() async {
          store.handleLifecycle(AppLifecycleState.paused);
          expect(store.isUnlocked, isTrue);
        });
        expect(store.isHoldingBackgroundLock, isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 900));
        expect(store.isHoldingBackgroundLock, isFalse);
        store.handleLifecycle(AppLifecycleState.paused);
        expect(store.isUnlocked, isFalse);
      },
    );

    test('renovação pelo uso: 1 chamada com >10 min; 401 tranca', () async {
      final store = newStore();
      var calls = 0;
      String? next;
      store.refresher = (_) async {
        calls++;
        return next;
      };
      await store.adopt(fakePinJwt(clock.now));

      await store.touch();
      expect(calls, 0, reason: 'token novo não renova');

      clock.advance(const Duration(minutes: 11));
      next = fakePinJwt(clock.now);
      await store.touch();
      expect(calls, 1);
      expect(store.session!.emitidoEm, clock.now);

      clock.advance(const Duration(minutes: 11));
      next = null; // back recusou (401)
      await store.touch();
      expect(store.isUnlocked, isFalse);
      expect(store.lockReason, FinanceLockReason.expired);
    });

    test('falha de rede na renovação NÃO tranca', () async {
      final store = newStore();
      store.refresher = (_) async => throw StateError('sem rede');
      await store.adopt(fakePinJwt(clock.now));
      clock.advance(const Duration(minutes: 11));
      await store.touch();
      expect(store.isUnlocked, isTrue);
    });

    test('token renovado pelo header só vale com o portão aberto', () async {
      final store = newStore();
      await store.adopt(fakePinJwt(clock.now));
      store.lock(FinanceLockReason.background);
      await store.adoptRenewed(fakePinJwt(clock.now));
      expect(store.isUnlocked, isFalse);
    });

    test('outra pessoa logada não herda o desbloqueio', () async {
      final store = newStore();
      await store.adopt(fakePinJwt(clock.now));
      owner = 'user-2';
      expect(await store.tokenForRequest(), isNull);
      expect(store.everUnlocked, isFalse);
    });

    test('carrega do armazenamento só o token válido do mesmo dono', () async {
      final s = FinancePinSession.fromToken(
        fakePinJwt(clock.now),
        ownerKey: 'user-1',
        now: clock.now,
      )!;
      storage.value = jsonEncode(s.toJson());
      final a = newStore();
      await a.ensureLoaded();
      expect(a.isUnlocked, isTrue);

      storage.value = jsonEncode(s.toJson());
      owner = 'user-2';
      final b = newStore();
      await b.ensureLoaded();
      expect(b.isUnlocked, isFalse);
      expect(storage.value, isNull);
    });

    test('logout (clear) apaga tudo', () async {
      final store = newStore();
      await store.adopt(fakePinJwt(clock.now));
      store.clear();
      expect(store.isUnlocked, isFalse);
      expect(store.everUnlocked, isFalse);
      expect(storage.value, isNull);
    });
  });
}
