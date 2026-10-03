import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:Intellisys/features/finance/core/finance_api_client.dart';
import 'package:Intellisys/features/finance/core/finance_format.dart';
import 'package:Intellisys/features/finance/core/finance_me.dart';
import 'package:Intellisys/features/finance/core/finance_pin_store.dart';
import 'package:Intellisys/features/finance/core/finance_visibility.dart';
import 'package:Intellisys/features/finance/meu_financeiro/models/meu_financeiro_models.dart';
import 'package:Intellisys/features/finance/meu_financeiro/pages/meu_financeiro_page.dart';
import 'package:Intellisys/features/finance/meu_financeiro/services/meu_financeiro_service.dart';
import 'package:Intellisys/shared/services/api_service.dart';
import 'package:Intellisys/shared/services/subscription_access_gate.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  group('Plano só Financeiro (decisão 4)', () {
    test('sem CRM e com Financeiro abre no Meu Financeiro', () {
      const modules = ['user_management', 'financial_management'];
      final d = decideProductAccess(modules);
      expect(d, AccessGateDecision.financeOnly);
      expect(SubscriptionAccessGate.routeFor(d), '/financeiro/meu-dashboard');
    });

    test('sem CRM e sem Financeiro mantém o aviso de plano', () {
      expect(
        decideProductAccess(const ['user_management']),
        AccessGateDecision.crmNotIncluded,
      );
    });

    test('com CRM, lista vazia ou master: segue normal', () {
      expect(
        decideProductAccess(const [
          'kanban_management',
          'financial_management',
        ]),
        AccessGateDecision.allow,
      );
      expect(decideProductAccess(const []), AccessGateDecision.allow);
      expect(
        decideProductAccess(const ['financial_management'], role: 'master'),
        AccessGateDecision.allow,
      );
    });

    test('rotas: Financeiro e plataforma liberados; CRM não', () {
      const d = AccessGateDecision.financeOnly;
      expect(
        SubscriptionAccessGate.isRouteAllowed(d, '/financeiro/meu-dashboard'),
        isTrue,
      );
      expect(SubscriptionAccessGate.isRouteAllowed(d, '/profile'), isTrue);
      expect(SubscriptionAccessGate.isRouteAllowed(d, '/home'), isFalse);
      expect(SubscriptionAccessGate.isRouteAllowed(d, '/kanban'), isFalse);
    });
  });

  group('Gating do Financeiro', () {
    test('módulo da empresa obrigatório, sem bypass', () {
      expect(companyHasFinanceModule(const ['financial_management']), isTrue);
      expect(companyHasFinanceModule(const ['kanban_management']), isFalse);
      expect(companyHasFinanceModule(null), isNull);
    });

    FinanceMe me(
      String role, {
      List<String> rev = const [],
      bool linked = true,
    }) => FinanceMe(linked: linked, role: role, revogadas: rev);

    test('Meu Financeiro: todo papel menos PENDENTE', () {
      expect(
        isFinanceTelaPermitida(me('CORRETOR'), FinanceTela.meuDashboard),
        isTrue,
      );
      expect(
        isFinanceTelaPermitida(me('GESTOR'), FinanceTela.meuDashboard),
        isTrue,
      );
      expect(
        isFinanceTelaPermitida(me('PENDENTE'), FinanceTela.meuDashboard),
        isFalse,
      );
      expect(
        isFinanceTelaPermitida(me('PENDENTE'), FinanceTela.adiantamentos),
        isTrue,
      );
    });

    test('aprovações: gestor sim, analista e corretor não', () {
      expect(
        isFinanceTelaPermitida(me('GESTOR'), FinanceTela.aprovacoes),
        isTrue,
      );
      expect(
        isFinanceTelaPermitida(
          me('ANALISTA_FINANCEIRO'),
          FinanceTela.aprovacoes,
        ),
        isFalse,
      );
      expect(
        isFinanceTelaPermitida(me('CORRETOR'), FinanceTela.aprovacoes),
        isFalse,
      );
    });

    test('revogada vence a matriz; linked:false/404 não tem gating', () {
      expect(
        isFinanceTelaPermitida(
          me('CORRETOR', rev: ['requests:view']),
          FinanceTela.solicitacoes,
        ),
        isFalse,
      );
      expect(
        isFinanceTelaPermitida(me('', linked: false), FinanceTela.solicitacoes),
        isTrue,
      );
      expect(isFinanceTelaPermitida(null, FinanceTela.solicitacoes), isTrue);
    });
  });

  group('Formatação', () {
    test('Decimal do Prisma em string e number', () {
      expect(financeNum('10200.00'), 10200.0);
      expect(financeNum(12.5), 12.5);
      expect(financeNum(null), 0);
    });

    test('ocultar valores mascara dígitos e mantém o sinal', () {
      expect(formatBrl(1234.5), r'R$ 1.234,50');
      expect(formatBrl(1234.5, hidden: true), r'R$ ••••');
      expect(formatBrl(-7, hidden: true), r'-R$ ••');
    });

    test('data de calendário UTC não volta um dia', () {
      expect(formatFinanceDate('2026-10-05T00:00:00.000Z'), '05/10/26');
    });
  });

  test('envelope paginado aceita array cru', () {
    final p = FinancePage.parse<RequestSummary>([
      {
        'id': '1',
        'title': 'a',
        'status': 'PENDENTE',
        'amountRequested': '10.00',
      },
    ], RequestSummary.fromJson);
    expect(p.total, 1);
    expect(p.data.single.amountRequested, 10);
  });

  test('insight: assinatura pendente vem antes de tudo', () {
    final s = BrokerDashboardSummary.fromJson({
      'totals': {'aReceber': 100, 'saldoDevedor': 50},
      'aguardandoAssinatura': {'count': 2, 'valor': 300},
    });
    expect(meuFinanceiroInsight(s).title, 'Ação sua · assinatura');
    final s2 = BrokerDashboardSummary.fromJson({
      'totals': {'aReceber': 100, 'saldoDevedor': 50},
    });
    expect(meuFinanceiroInsight(s2).title, 'Atenção · adiantamento');
  });

  test(
    'Meu Financeiro carrega as 7 fontes em PARALELO (sem cascata)',
    () async {
      final pending = <Completer<http.Response>>[];
      final paths = <String>[];
      final client = FinanceApiClient(
        httpClient: MockClient((r) {
          paths.add(r.url.path);
          final c = Completer<http.Response>();
          pending.add(c);
          return c.future;
        }),
        accessTokenProvider: () async => 't',
        companyIdProvider: () async => 'c',
        pinStore: FinancePinStore(
          storage: MemoryFinancePinStorage(),
          ownerKeyProvider: () async => 'u',
        ),
        baseUrl: 'https://fin.test/api/v1',
      );
      final svc = MeuFinanceiroService(
        client: client,
        meLoader: () async {
          final r = await client.get<Map<String, dynamic>>('/auth/me');
          return ApiResponse<FinanceMe?>.success(
            data: r.data == null ? null : FinanceMe.fromJson(r.data!),
            statusCode: r.statusCode,
          );
        },
      );
      final future = svc.loadAll(
        proximosQuery: const ProximosQuery(),
        vendasQuery: const VendasQuery(),
      );
      // Nenhuma resposta chegou e as 7 chamadas já saíram (inclui as
      // fichas aguardando assinatura, fase 2).
      for (var i = 0; i < 20 && pending.length < 7; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(pending, hasLength(7));
      expect(
        paths,
        containsAll([
          '/api/v1/repasses/broker-dashboard',
          '/api/v1/repasses/broker-dashboard/proximos',
          '/api/v1/repasses/broker-dashboard/vendas',
          '/api/v1/commission-advances',
          '/api/v1/requests',
          '/api/v1/auth/me',
          '/api/v1/repasses/broker-dashboard/assinaturas',
        ]),
      );
      for (final c in pending) {
        c.complete(
          http.Response('{"data":[],"total":0,"page":1,"pageSize":5}', 200),
        );
      }
      final snap = await future;
      expect(snap.summary.ok, isTrue);
      expect(snap.requests.data!.total, 0);
    },
  );
}
