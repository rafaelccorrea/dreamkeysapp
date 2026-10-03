import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:Intellisys/features/finance/adiantamento/adiantamento_rules.dart';
import 'package:Intellisys/features/finance/aprovacoes/approvals_models.dart';
import 'package:Intellisys/features/finance/core/finance_access.dart';
import 'package:Intellisys/features/finance/core/finance_api_client.dart';
import 'package:Intellisys/features/finance/core/finance_deep_link.dart';
import 'package:Intellisys/features/finance/core/finance_me.dart';
import 'package:Intellisys/features/finance/core/finance_pin_store.dart';
import 'package:Intellisys/features/finance/home/meu_dinheiro_card.dart';
import 'package:Intellisys/features/finance/meu_financeiro/models/drill_models.dart';
import 'package:Intellisys/features/finance/meu_financeiro/models/meu_financeiro_models.dart';
import 'package:Intellisys/features/finance/notificacoes/finance_notifications_controller.dart';
import 'package:Intellisys/features/finance/solicitacoes/models/request_models.dart';
import 'package:Intellisys/features/finance/solicitacoes/models/request_rules.dart';
import 'package:Intellisys/features/finance/solicitacoes/services/requests_service.dart';

FinanceMe _me(String role, {List<String>? permissoes, bool linked = true}) =>
    FinanceMe.fromJson({
      'linked': linked,
      'userId': 'u1',
      'role': role,
      'permissoes': ?permissoes,
    });

SolicitacaoForm _formOk() => SolicitacaoForm()
  ..companyId = 'c1'
  ..type = 'SERVICOS'
  ..title = 'Pintura da fachada'
  ..justification = 'Orçamento aprovado pela diretoria'
  ..amount = 1500;

RequestTipo _tipo({String motor = 'PAGAMENTO', Map<String, dynamic>? base, List<Map<String, dynamic>>? campos}) =>
    RequestTipo.fromJson({
      'id': 't1',
      'nome': 'Pagamento a fornecedor',
      'motor': motor,
      'camposBase': base ?? {},
      'campos': campos ?? [],
    });

void main() {
  group('Solicitação — validações (paridade com o web)', () {
    test('obrigatórios: empresa, tipo, título, justificativa, valor > 0', () {
      final e = validarSolicitacao(SolicitacaoForm());
      expect(e.keys, containsAll(['companyId', 'type', 'title', 'justification', 'amount']));
      expect(e['companyId'], 'Empresa é obrigatória');
      expect(validarSolicitacao(_formOk()), isEmpty);
    });

    test('"Outros" sem tipo configurado exige descrição', () {
      final f = _formOk()..type = 'OUTROS';
      expect(validarSolicitacao(f)['outrosDescricao'], 'Descreva o que é esse "Outros"');
      f.outrosDescricao = 'Brindes';
      expect(validarSolicitacao(f), isEmpty);
    });

    test('cartão: cartão, data e parcelas 2..24; sem rateio', () {
      final f = _formOk()
        ..paymentMethod = 'CARTAO_CREDITO'
        ..cartaoParcelado = true
        ..installments = 30;
      final e = validarSolicitacao(f);
      expect(e.keys, containsAll(['creditCardId', 'purchaseDate', 'installments']));
      f
        ..creditCardId = 'k'
        ..purchaseDate = DateTime(2026, 10, 1)
        ..installments = 3;
      expect(validarSolicitacao(f), isEmpty);
      f.rateio = true;
      expect(validarSolicitacao(f)['rateio'], contains('cartão'));
    });

    test('rateio: soma tem de bater com o valor (±0,01)', () {
      expect(
        validarRateio([(companyId: 'a', amount: 1000), (companyId: 'b', amount: 499.99)], 1500),
        isNull,
      );
      expect(
        validarRateio([(companyId: 'a', amount: 1000), (companyId: 'b', amount: 400)], 1500),
        'A soma dos beneficiários deve igualar o valor solicitado',
      );
      expect(validarRateio([(companyId: null, amount: 1500)], 1500), isNotNull);
    });

    test('tipo: natureza obrigatória, campos do tipo e comprovante do reembolso', () {
      final f = _formOk()
        ..tipo = _tipo(
          motor: 'REEMBOLSO',
          campos: [
            {'chave': 'km', 'rotulo': 'Km rodados', 'kind': 'NUMERO', 'obrigatorio': true},
            {'chave': 'ok', 'rotulo': 'Confere?', 'kind': 'SIM_NAO', 'obrigatorio': true},
          ],
        );
      final e = validarSolicitacao(f);
      expect(e['naturezaId'], 'Escolha a natureza da solicitação.');
      expect(e['campo:km'], 'Preencha "Km rodados"');
      expect(e.containsKey('campo:ok'), isFalse); // SIM_NAO não é obrigatório
      expect(e['anexos'], 'Anexe o comprovante');
      // Na edição o comprovante não é exigido de novo.
      expect(validarSolicitacao(f, edicao: true).containsKey('anexos'), isFalse);
    });

    test('padrões do back para campos base (reembolso esconde fornecedor)', () {
      final t = _tipo(motor: 'REEMBOLSO');
      expect(t.base('fornecedor').visivel, isFalse);
      expect(t.base('comprovante').obrigatorio, isTrue);
      expect(_tipo().base('fornecedor').visivel, isTrue);
      expect(_tipo(base: {'fornecedor': {'visivel': true, 'obrigatorio': true}}).base('fornecedor').obrigatorio, isTrue);
    });
  });

  group('Solicitação — corpo do envio', () {
    test('nova: tipoId, companyId, qtdAnexos e notas com "Outros"', () {
      final f = _formOk()
        ..tipo = _tipo()
        ..naturezaId = 'n1'
        ..type = 'OUTROS'
        ..outrosDescricao = 'Brindes'
        ..notes = 'urgente'
        ..qtdAnexos = 2;
      final b = buildRequestBody(f);
      expect(b['tipoId'], 't1');
      expect(b['companyId'], 'c1');
      expect(b['qtdAnexos'], 2);
      expect(b['notes'], 'Tipo (Outros): Brindes\nurgente');
      expect(b.containsKey('feePercent'), isFalse);
    });

    test('reembolso não manda fornecedor', () {
      final f = _formOk()
        ..tipo = _tipo(motor: 'REEMBOLSO')
        ..supplierId = 's1';
      expect(buildRequestBody(f).containsKey('supplierId'), isFalse);
    });

    test('edição: sem tipoId/companyId; corrigir reprovada leva companyId, beneficiaries e mensagem', () {
      final f = _formOk()..tipo = _tipo();
      final edit = buildRequestBody(f, edicao: true);
      expect(edit.containsKey('tipoId'), isFalse);
      expect(edit.containsKey('companyId'), isFalse);
      expect(edit.containsKey('qtdAnexos'), isFalse);
      expect(edit['categoryId'], ''); // vazio limpa no back
      final fix = buildRequestBody(f, edicao: true, corrigindoReprovada: true, mensagem: ' corrigi o valor ');
      expect(fix['companyId'], 'c1');
      expect(fix['beneficiaries'], isEmpty);
      expect(fix['mensagem'], 'corrigi o valor');
    });

    test('cartão à vista manda 1 parcela e a data YYYY-MM-DD', () {
      final f = _formOk()
        ..paymentMethod = 'CARTAO_CREDITO'
        ..creditCardId = 'k'
        ..purchaseDate = DateTime(2026, 10, 3);
      final b = buildRequestBody(f);
      expect(b['installments'], 1);
      expect(b['purchaseDate'], '2026-10-03');
    });

    test('separarNotas desfaz juntarNotas', () {
      final s = separarNotas(juntarNotas('Brindes', 'linha 1\nlinha 2'));
      expect(s.outros, 'Brindes');
      expect(s.notes, 'linha 1\nlinha 2');
      expect(separarNotas('só nota').outros, '');
    });
  });

  group('Solicitação — reconciliação depois de timeout/409', () {
    final now = DateTime.utc(2026, 10, 3, 12);
    FinanceRequest r(String title, double v, String c, DateTime at) => FinanceRequest.fromJson({
      'id': '$title-$at',
      'title': title,
      'status': 'PENDENTE',
      'amountRequested': v.toStringAsFixed(2),
      'company': {'id': c, 'name': 'X'},
      'createdAt': at.toIso8601String(),
    });

    test('acha pelo título (sem caixa), centavos, empresa e ≤ 10 min — a mais nova', () {
      final rows = [
        r('Pintura', 1500, 'c1', now.subtract(const Duration(minutes: 3))),
        r('  PINTURA ', 1500, 'c1', now.subtract(const Duration(minutes: 1))),
        r('Pintura', 1500, 'c2', now),
        r('Pintura', 1500.01, 'c1', now),
        r('Pintura', 1500, 'c1', now.subtract(const Duration(minutes: 11))),
      ];
      final achou = acharRecemCriada(rows, title: 'pintura', amount: 1500, companyId: 'c1', now: now);
      expect(achou?.title, '  PINTURA ');
      expect(
        acharRecemCriada(rows, title: 'Outra', amount: 1500, companyId: 'c1', now: now),
        isNull,
      );
    });

    test('409 no POST → reconfere a lista e devolve a que entrou', () async {
      final calls = <String>[];
      final client = FinanceApiClient(
        httpClient: MockClient((req) async {
          calls.add('${req.method} ${req.url.path}');
          if (req.method == 'POST') return http.Response('{"message":"conflito"}', 409);
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 'r9',
                  'title': 'Pintura',
                  'status': 'PENDENTE',
                  'amountRequested': '1500.00',
                  'company': {'id': 'c1'},
                  'createdAt': DateTime.now().toUtc().toIso8601String(),
                },
              ],
              'total': 1,
              'page': 1,
              'pageSize': 20,
            }),
            200,
          );
        }),
        accessTokenProvider: () async => 't',
        companyIdProvider: () async => 'c1',
        pinStore: FinancePinStore(storage: MemoryFinancePinStorage(), ownerKeyProvider: () async => 'u'),
        baseUrl: 'https://fin.test/api/v1',
      );
      final res = await RequestsService(client: client).create({
        'title': 'Pintura',
        'amountRequested': 1500.0,
        'companyId': 'c1',
      });
      expect(res, isA<CriacaoOk>());
      expect((res as CriacaoOk).reconciliada, isTrue);
      expect(res.request.id, 'r9');
      expect(calls, ['POST /api/v1/requests', 'GET /api/v1/requests']);
    });
  });

  group('Anexos', () {
    test('tipos aceitos e limite', () {
      expect(validarAnexo('nota.pdf', 100, limiteBytes: 5 << 20), isNull);
      expect(validarAnexo('foto.HEIC', 100, limiteBytes: 5 << 20), 'Tipo não aceito: só PDF, JPG, PNG ou WebP');
      expect(validarAnexo('grande.png', 6 << 20, limiteBytes: 5 << 20), contains('limite de envio é 5 MB'));
      expect(anexoMime('a.JPG'), 'image/jpeg');
    });

    test('corretor usa base64 de 5 MB; time financeiro, multipart de 30 MB', () {
      expect(usaUploadMultipart(_me('CORRETOR', permissoes: ['attachments:attach'])), isFalse);
      expect(limiteAnexoBytes(_me('GESTOR')), 5 * 1024 * 1024);
      expect(usaUploadMultipart(_me('ANALISTA_FINANCEIRO', permissoes: ['attachments:attach'])), isTrue);
      expect(usaUploadMultipart(_me('ANALISTA_FINANCEIRO', permissoes: [])), isFalse);
      expect(limiteAnexoBytes(_me('ADMIN')), 30 * 1024 * 1024);
      expect(usaUploadMultipart(null), isFalse);
    });
  });

  group('Pedir adiantamento', () {
    test('vendas: agrupa por venda, só PENDING/APPROVED somam, maior primeiro', () {
      final v = vendasParaAdiantamento([
        {'saleId': 's1', 'status': 'PAID', 'commissionValue': 999, 'sale': {'fichaVenda': 'FV-1'}},
        {'saleId': 's1', 'status': 'PENDING', 'commissionValue': '100.50'},
        {'saleId': 's2', 'status': 'APPROVED', 'commissionValue': 300, 'sale': {'propertyAddress': 'Rua A', 'unit': '12'}},
        {'saleId': null, 'status': 'PENDING', 'commissionValue': 50},
        {'saleId': 's3', 'status': 'WAITING_FOR_SIGNATURE', 'commissionValue': 800},
      ]);
      expect(v.map((e) => e.saleId), ['s2', 's1', 's3']);
      expect(v[1].aReceber, 100.5);
      expect(v[1].detalhe, 'Ficha FV-1');
      expect(v[0].detalhe, 'Rua A · 12');
      expect(v[2].aReceber, 0);
    });

    test('validações do web', () {
      final e = validarAdiantamento(description: ' ', value: null);
      expect(e, {'companyId': 'Informe a empresa', 'description': 'Descreva o adiantamento', 'value': 'Informe o valor'});
      expect(validarAdiantamento(companyId: 'c', description: 'x', value: 0)['value'], isNotNull);
      expect(validarAdiantamento(companyId: 'c', description: 'x', value: 0.01), isEmpty);
    });

    test('corpo sem taxa nem teto; saleIds só com mais de uma venda', () {
      final one = buildAdiantamentoBody(companyId: 'c', brokerId: 'u', saleIds: ['s1'], description: ' d ', value: 10);
      expect(one, {'companyId': 'c', 'brokerId': 'u', 'saleId': 's1', 'description': 'd', 'value': 10.0});
      final two = buildAdiantamentoBody(companyId: 'c', brokerId: 'u', saleIds: ['s1', 's2'], description: 'd', value: 10, notes: 'n');
      expect(two['saleIds'], ['s1', 's2']);
      expect(two.containsKey('feePercent'), isFalse);
      expect(two.containsKey('capOverrideReason'), isFalse);
      expect(deveReenviarSemSaleIds(two, 'property saleIds should not exist'), isTrue);
      expect(deveReenviarSemSaleIds(one, 'property saleIds should not exist'), isFalse);
      expect(deveReenviarSemSaleIds(two, 'Saldo livre R\$ 10'), isFalse);
    });
  });

  group('Para aprovar — quem aprova e regras', () {
    test('crachá do CRM (financial:access ou master/admin) E matriz', () {
      expect(canSeeParaAprovar(crmRole: 'broker', hasFinancialAccess: false, me: _me('GESTOR')), isFalse);
      expect(canSeeParaAprovar(crmRole: 'manager', hasFinancialAccess: true, me: _me('GESTOR')), isTrue);
      expect(canSeeParaAprovar(crmRole: 'admin', hasFinancialAccess: false, me: _me('DIRETOR')), isTrue);
      expect(canSeeParaAprovar(crmRole: 'MASTER', hasFinancialAccess: false, me: _me('ADMIN')), isTrue);
      expect(canSeeParaAprovar(crmRole: 'admin', hasFinancialAccess: true, me: _me('CORRETOR')), isFalse);
      expect(canSeeParaAprovar(crmRole: 'admin', hasFinancialAccess: true, me: _me('ANALISTA_FINANCEIRO')), isFalse);
      expect(canSeeParaAprovar(crmRole: 'admin', hasFinancialAccess: true, me: _me('CORRETOR', linked: false)), isTrue);
      expect(canSeeParaAprovar(crmRole: 'admin', hasFinancialAccess: true, me: null), isTrue);
    });

    test('exceção por pessoa: concedida/revogada', () {
      final concedida = FinanceMe.fromJson({'linked': true, 'role': 'CORRETOR', 'concedidas': ['approvals:view']});
      final revogada = FinanceMe.fromJson({'linked': true, 'role': 'GESTOR', 'revogadas': ['approvals:view']});
      expect(canSeeParaAprovar(crmRole: 'admin', hasFinancialAccess: true, me: concedida), isTrue);
      expect(canSeeParaAprovar(crmRole: 'admin', hasFinancialAccess: true, me: revogada), isFalse);
    });

    test('decidir no lote e aprovar adiantamento', () {
      expect(canDecideApprovals(_me('GESTOR')), isTrue);
      expect(canDecideApprovals(_me('GESTOR', permissoes: [])), isFalse);
      expect(canDecideApprovals(_me('CORRETOR')), isFalse);
      expect(canApproveAdvance(_me('GESTOR')), isFalse);
      expect(canApproveAdvance(_me('DIRETOR_FINANCEIRO')), isTrue);
      expect(canApproveAdvance(_me('GESTOR', permissoes: ['commission-advances:approve'])), isTrue);
      expect(financeTemPermissao(_me('X'), 'k'), isNull);
    });

    test('motivo da recusa: 5..500', () {
      expect(validarMotivoRecusa(' abc '), isNotNull);
      expect(validarMotivoRecusa('valor errado'), isNull);
      expect(validarMotivoRecusa('x' * 501), isNotNull);
    });

    test('lote: fatias de 10 e adiantamento fora do lote', () {
      final f = fatiasDoLote(List.generate(23, (i) => i));
      expect(f.map((e) => e.length), [10, 10, 3]);
      final items = [
        ApprovalItem.fromJson({'source': 'REQUEST', 'id': '1', 'title': 'a'}),
        ApprovalItem.fromJson({'source': 'ADVANCE', 'id': '2', 'title': 'b'}),
      ];
      final s = separarParaAprovar(items);
      expect(s.lote.single.id, '1');
      expect(s.adiantamentos.single.id, '2');
    });

    test('query do Meu aval não manda os padrões do back', () {
      expect(meuAvalQuery(), {'situacao': 'MEU_AVAL', 'page': 1, 'pageSize': 25});
      expect(meuAvalQuery(search: ' x ', sortDir: 'desc'), containsPair('sortDir', 'desc'));
      expect(meuAvalQuery(search: ' x ')['search'], 'x');
    });

    test('adiantamento: cobrado com taxa e justificativa acima do saldo', () {
      expect(cobradoComTaxa(1000, 5), 1050);
      expect(cobradoComTaxa(333.33, 3), 343.33);
      expect(precisaJustificarTeto(saldoLivre: 1000, aReceber: 2000, cobrado: 1000.005), isFalse);
      expect(precisaJustificarTeto(saldoLivre: 1000, aReceber: 2000, cobrado: 1050), isTrue);
      expect(precisaJustificarTeto(saldoLivre: 0, aReceber: 0, cobrado: 0), isTrue);
    });

    test('resultado do lote', () {
      expect(resumoDoLote(ok: 3, falhas: 0, aprovar: true), '3 itens aprovados.');
      expect(resumoDoLote(ok: 0, falhas: 2, aprovar: false), startsWith('Nenhum item recusado.'));
    });

    test('BulkResult lê duplicidade', () {
      final r = BulkResult.fromJson({
        'succeeded': [{'source': 'REQUEST', 'id': '1'}],
        'failed': [
          {'source': 'PAYABLE', 'id': '2', 'error': 'dup', 'code': 'LANCAMENTO_EM_DOBRO', 'suspeitos': [{'code': 'CP-1'}]},
        ],
      });
      expect(r.succeeded, ['REQUEST:1']);
      expect(r.failed.single.duplicidade, isTrue);
      expect(r.failed.single.suspeitos, ['CP-1']);
    });
  });

  group('Deep links do Financeiro', () {
    test('rotas /financeiro/* → telas do app (o resto vira "só no web")', () {
      expect(matchFinanceRoute('/financeiro').kind, FinanceRouteKind.meuDashboard);
      expect(matchFinanceRoute('/financeiro/meu-dashboard?venda=s1').saleId, 's1');
      expect(matchFinanceRoute('/financeiro/solicitacoes').kind, FinanceRouteKind.solicitacoes);
      expect(matchFinanceRoute('/financeiro/solicitacoes?id=r1').id, 'r1');
      expect(matchFinanceRoute('/financeiro/solicitacoes/nova').kind, FinanceRouteKind.novaSolicitacao);
      final d = matchFinanceRoute('/financeiro/solicitacoes/r1');
      expect((d.kind, d.id), (FinanceRouteKind.solicitacao, 'r1'));
      expect(matchFinanceRoute('/financeiro/solicitacoes/r1/editar').kind, FinanceRouteKind.editarSolicitacao);
      expect(matchFinanceRoute('/financeiro/aprovacoes/decisao/meu-aval').kind, FinanceRouteKind.aprovacoes);
      expect(matchFinanceRoute('/financeiro/adiantamentos/novo').kind, FinanceRouteKind.pedirAdiantamento);
      expect(matchFinanceRoute('/financeiro/adiantamentos').kind, FinanceRouteKind.meuDashboard);
      final v = matchFinanceRoute('/financeiro/vendas?saleId=s9');
      expect((v.kind, v.saleId), (FinanceRouteKind.meuDashboard, 's9'));
      final chat = matchFinanceRoute('/financeiro/vendas?saleId=s9&chat=1');
      expect((chat.kind, chat.webLabel), (FinanceRouteKind.webOnly, 'Conversa da venda'));
      final cp = matchFinanceRoute('/financeiro/contas-a-pagar?focus=1');
      expect((cp.kind, cp.webLabel), (FinanceRouteKind.webOnly, 'Contas a pagar'));
      expect(matchFinanceRoute('/financeiro/xyz').webLabel, 'Esta tela do Financeiro');
    });

    FinanceNotification n(String type, {String? requestId, String? saleId, String? dealId}) =>
        FinanceNotification.fromJson({
          'id': '1',
          'type': type,
          'message': 'm',
          'requestId': requestId,
          'saleId': saleId,
          'dealId': dealId,
        });

    test('notificação → rota (ordem do destino() do web)', () {
      expect(financeNotificationRoute(n('REQUEST_APPROVED', requestId: 'r1')), '/financeiro/solicitacoes/r1');
      expect(financeNotificationRoute(n('REQUEST_SUA_VEZ', requestId: 'r1')), '/financeiro/solicitacoes/r1');
      expect(financeNotificationRoute(n('REQUEST_SUA_VEZ', requestId: 'r1'), podeAprovar: true), '/financeiro/aprovacoes');
      expect(financeNotificationRoute(n('ADVANCE_APPROVAL_PENDING'), podeAprovar: true), '/financeiro/aprovacoes');
      expect(financeNotificationRoute(n('SALE_COMMENT', saleId: 's1')), contains('chat=1'));
      expect(financeNotificationRoute(n('REPASSE_PAID', saleId: 's1')), '/financeiro/meu-dashboard?venda=s1');
      expect(financeNotificationRoute(n('PAYABLE_APPROVAL_PENDING')), '/financeiro/contas-a-pagar');
      expect(financeNotificationRoute(n('SALE_CREATED', dealId: 'd1')), '/financeiro/pipeline');
      expect(financeNotificationRoute(n('RECEIVABLE_OVERDUE')), '/financeiro/contas-a-receber');
      expect(financeNotificationRoute(n('COMMISSION_DEBIT')), '/financeiro/meu-dashboard');
      expect(financeNotificationRoute(n('REFUND_DUE_TODAY')), isNull);
      // Toda rota devolvida casa com uma tela do app ou com o aviso.
      expect(matchFinanceRoute(financeNotificationRoute(n('PAYABLE_OVERDUE'))!).kind, FinanceRouteKind.webOnly);
    });

    test('títulos com fallback "Financeiro"', () {
      expect(financeNotificationTitle('REQUEST_SUA_VEZ'), 'Chegou a sua vez de assinar');
      expect(financeNotificationTitle('NOVO_TIPO'), 'Financeiro');
    });

    test('socket: backoff 2 s × 2^n até 60 s e origem sem /api/v1', () {
      expect(financeSocketBackoff(0), const Duration(seconds: 2));
      expect(financeSocketBackoff(3), const Duration(seconds: 16));
      expect(financeSocketBackoff(10), const Duration(seconds: 60));
      expect(financeSocketOrigin('https://api.financeiro.intellisysbr.com/api/v1'), 'https://api.financeiro.intellisysbr.com');
      expect(financeSocketOrigin('http://10.0.2.2:3001/api/v1'), 'http://10.0.2.2:3001');
    });
  });

  group('Meu Financeiro — mês do gráfico e drill-downs', () {
    test('mês clicado: [1º, último]; mês atual abre o início (atrasados)', () {
      final hoje = DateTime(2026, 10, 3);
      expect(mesDoGraficoRange('2026-08', hoje), ('2026-08-01', '2026-08-31'));
      expect(mesDoGraficoRange('2026-10', hoje), (null, '2026-10-31'));
      expect(mesDoGraficoRange('2027-02', hoje), ('2027-02-01', '2027-02-28'));
    });

    test('janela do gráfico: 6 para trás e 5 à frente', () {
      final mensal = [
        for (var i = -12; i <= 6; i++)
          MonthlyEarning(month: () {
            final d = DateTime(2026, 10 + i, 1);
            return '${d.year}-${d.month.toString().padLeft(2, '0')}';
          }()),
      ];
      final j = janelaDoGrafico(mensal, DateTime(2026, 10, 3));
      expect(j.first.month, '2026-04');
      expect(j.last.month, '2027-03');
      expect(j, hasLength(12));
    });

    test('consulta da venda e origem do repasse', () {
      final v = VendaConsulta.fromJson({
        'saleId': 's1',
        'status': 'PENDING',
        'imovel': {'endereco': 'Rua B'},
        'compradores': ['Ana'],
        'valores': {'vgv': 500000, 'vgc': 25000, 'comissaoPct': 5},
        'parcelas': [{'numero': 1, 'valor': 10000, 'status': 'RECEIVED'}],
        'participantes': [
          {'brokerId': 'b', 'nome': 'Zé', 'papeis': [{'papel': 'CAPTADOR', 'percentual': 2}], 'totais': null},
        ],
      });
      expect(v.titulo, 'Rua B');
      expect(v.participantes.single.totais, isNull);
      expect(saleStatusLabel('PENDING'), 'A vencer');
      expect(papelNaVendaLabel('GESTOR'), 'Gerente');
      final o = RepasseOrigem.fromJson({
        'repasseId': 'r',
        'status': 'PAID',
        'descontos': {'liquido': 900, 'nfValor': 100},
        'aindaVem': {'parcelas': [{'numero': 2, 'meuValor': 50, 'status': 'PENDING'}], 'totalAReceber': 50},
      });
      expect(o.liquido, 900);
      expect(o.aindaVem.single.numero, 2);
    });
  });

  group('Card "Meu dinheiro"', () {
    test('usa brokers[0]; sem corretor → esconde', () {
      expect(MeuDinheiroData.fromJson({'brokers': []}), isNull);
      final d = MeuDinheiroData.fromJson({
        'brokers': [
          {'devido': 300, 'recebido': 100, 'retido': 50, 'aReceber': 150, 'saldoAdiantamento': 20, 'sales': [{}, {}]},
        ],
      })!;
      expect(d.totals.devido, 300);
      expect(d.vendas, 2);
      expect(d.saldoAdiantamento, 20);
    });
  });

  test('FinanceMe sabe se o back mandou permissoes', () {
    expect(FinanceMe.fromJson({'role': 'X'}).hasPermissoesList, isFalse);
    expect(FinanceMe.fromJson({'role': 'X', 'permissoes': []}).hasPermissoesList, isTrue);
  });
}
