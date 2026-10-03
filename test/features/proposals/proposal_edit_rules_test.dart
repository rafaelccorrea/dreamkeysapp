import 'package:Intellisys/features/proposals/utils/proposal_edit_rules.dart';
import 'package:Intellisys/features/proposals/utils/proposal_form_rules.dart';
import 'package:Intellisys/features/proposals/utils/proposal_list_header.dart';
import 'package:Intellisys/features/proposals/utils/proposal_signature_rules.dart';
import 'package:Intellisys/shared/services/purchase_proposals_service.dart';
import 'package:flutter_test/flutter_test.dart';

PurchaseProposal _p(Map<String, dynamic> raw) =>
    PurchaseProposal({'id': 'x', 'status': 'processing', ...raw});

void main() {
  group('proposalEdicaoBloqueada (back recusa PATCH)', () {
    test('em andamento pode editar', () {
      expect(proposalEdicaoBloqueada(status: ProposalStatus.processing), isNull);
    });
    test('finalizada, cancelada e excluída bloqueiam', () {
      expect(proposalEdicaoBloqueada(status: ProposalStatus.finalized),
          'Proposta finalizada não pode ser editada.');
      expect(proposalEdicaoBloqueada(status: ProposalStatus.canceled),
          'Proposta cancelada não pode ser editada.');
      expect(
        proposalEdicaoBloqueada(
          status: ProposalStatus.processing,
          deletedAt: DateTime(2026),
        ),
        'Proposta excluída não pode ser editada.',
      );
    });
  });

  group('proposalAtalhoDaLinha (botão da linha do web)', () {
    test('sem proposal:update, fora de andamento ou excluída: nada', () {
      expect(proposalAtalhoDaLinha(_p({}), canUpdate: false), isNull);
      expect(
        proposalAtalhoDaLinha(_p({'status': 'finalized'}), canUpdate: true),
        isNull,
      );
      expect(
        proposalAtalhoDaLinha(
          _p({'deletedAt': '2026-10-01T00:00:00Z'}),
          canUpdate: true,
        ),
        isNull,
      );
    });

    test('etapa liberada < 2: enviar, com etapa 1 forçada', () {
      final a = proposalAtalhoDaLinha(
        _p({'etapa': 2, 'maxEtapaLiberadaParaEnvio': 1}),
        canUpdate: true,
      )!;
      expect(a.tipo, ProposalAtalhoTipo.enviar);
      expect(a.etapa, 1);
    });

    test('etapa 2 liberada e enviada: assinaturas com etapa 2 forçada', () {
      final a = proposalAtalhoDaLinha(
        _p({
          'etapa': 1,
          'maxEtapaLiberadaParaEnvio': 2,
          'etapa2EnviadaParaAssinatura': true,
        }),
        canUpdate: true,
      )!;
      expect(a.tipo, ProposalAtalhoTipo.assinaturasProprietario);
      expect(a.etapa, 2);
    });

    test('sem o flag, cai em etapa == 2 (fallback do web)', () {
      final a = proposalAtalhoDaLinha(
        _p({'etapa': 2, 'maxEtapaLiberadaParaEnvio': 2}),
        canUpdate: true,
      )!;
      expect(a.tipo, ProposalAtalhoTipo.assinaturasProprietario);
    });

    test('etapa 2 não enviada ou etapa 3: Continuar abre a edição', () {
      expect(
        proposalAtalhoDaLinha(
          _p({
            'etapa': 2,
            'maxEtapaLiberadaParaEnvio': 2,
            'etapa2EnviadaParaAssinatura': false,
          }),
          canUpdate: true,
        )!.tipo,
        ProposalAtalhoTipo.continuar,
      );
      final a = proposalAtalhoDaLinha(
        _p({'etapa': 3, 'maxEtapaLiberadaParaEnvio': 3}),
        canUpdate: true,
      )!;
      expect(a.tipo, ProposalAtalhoTipo.continuar);
      expect(a.etapa, isNull);
    });
  });

  group('proposalReinicioDecision', () {
    const base1 = {'proposedPrice': '100.0'};
    const base2 = {'ownerName': 'Ana'};

    test('sem snapshot carregado: nunca reinicia', () {
      final d = proposalReinicioDecision(
        atual1: base1,
        carregado1: null,
        atual2: base2,
        carregado2: null,
        concluidas: const {1: true, 2: true},
      );
      expect(d.needsReinicio, isFalse);
    });

    test('alterou etapa concluída: pede reinício e diz qual', () {
      final d = proposalReinicioDecision(
        atual1: const {'proposedPrice': '200.0'},
        carregado1: base1,
        atual2: base2,
        carregado2: base2,
        concluidas: const {1: true, 2: false},
      );
      expect(d.needsReinicio, isTrue);
      expect(d.etapas, ['Etapa 1 (comprador, proposta e imóvel)']);
    });

    test('alterou etapa NÃO concluída: salva direto', () {
      final d = proposalReinicioDecision(
        atual1: base1,
        carregado1: base1,
        atual2: const {'ownerName': 'Bia'},
        carregado2: base2,
        concluidas: const {1: true, 2: false},
      );
      expect(d.needsReinicio, isFalse);
      expect(d.etapas, isEmpty);
    });
  });

  group('ProposalCepGate (useCepAutofill)', () {
    test('dispara com 8 dígitos e não repete o mesmo CEP', () {
      final g = ProposalCepGate();
      expect(g.gatilho('01310-10'), isNull);
      expect(g.gatilho('01310-100'), '01310100');
      expect(g.gatilho('01310-100'), isNull);
    });
    test('apagar e redigitar libera o mesmo CEP', () {
      final g = ProposalCepGate();
      g.gatilho('01310100');
      expect(g.gatilho('0131010'), isNull);
      expect(g.gatilho('01310100'), '01310100');
    });
    test('falha libera nova tentativa; force ignora a repetição', () {
      final g = ProposalCepGate();
      g.gatilho('01310100');
      g.falhou();
      expect(g.gatilho('01310100'), '01310100');
      expect(g.gatilho('01310100', force: true), '01310100');
    });
    test('mensagem de erro igual à do web', () {
      expect(kProposalCepErro, 'Erro ao buscar CEP');
    });
  });

  group('proposalPodeDecidirAnexo', () {
    test('só gestor, pendente e com etapa disponível (modal do web)', () {
      expect(
        proposalPodeDecidirAnexo(
          isGestor: true,
          status: 'pending_approval',
          etapasDisponiveis: const [2],
        ),
        isTrue,
      );
      expect(
        proposalPodeDecidirAnexo(
          isGestor: true,
          status: 'pending_approval',
          etapasDisponiveis: const [],
        ),
        isFalse,
      );
      expect(
        proposalPodeDecidirAnexo(
          isGestor: false,
          status: 'pending_approval',
          etapasDisponiveis: const [1],
        ),
        isFalse,
      );
      expect(
        proposalPodeDecidirAnexo(
          isGestor: true,
          status: 'approved',
          etapasDisponiveis: const [1],
        ),
        isFalse,
      );
    });
  });

  group('topo da lista (HeroFacts do web)', () {
    test('escopo, unidades e rascunho', () {
      final todos = proposalHeroFatos(
        canViewAll: true,
        unidadesDeVenda: 3,
        temRascunho: true,
      );
      expect(todos.escopo, 'vendo todas da imobiliária');
      expect(todos.unidades, '3 unidades de venda');
      expect(todos.rascunho, isTrue);
      final suas = proposalHeroFatos(
        canViewAll: false,
        unidadesDeVenda: 1,
        temRascunho: false,
      );
      expect(suas.escopo, 'vendo as suas fichas');
      expect(suas.unidades, '1 unidade de venda');
      expect(
        proposalHeroFatos(
          canViewAll: false,
          unidadesDeVenda: 0,
          temRascunho: false,
        ).unidades,
        isNull,
      );
    });

    test('composição da carteira', () {
      final c = proposalComposicao(
        total: 10,
        processing: 5,
        finalized: 3,
        canceled: 2,
      )!;
      expect(c.andamento, 0.5);
      expect(c.finalizadas, 0.3);
      expect(c.canceladas, 0.2);
      expect(
        proposalComposicao(
          total: 0,
          processing: 0,
          finalized: 0,
          canceled: 0,
        ),
        isNull,
      );
      expect(
        proposalComposicao(
          total: 4,
          processing: null,
          finalized: 1,
          canceled: 0,
        ),
        isNull,
      );
    });
  });

  test('rótulos de regime e estado civil iguais aos do web', () {
    expect(kProposalMarriageRegime.map((e) => e.$2), [
      'Comunhão Parcial',
      'Comunhão Universal',
      'Separação Total',
      'Participação Final',
    ]);
    expect(kProposalMaritalStatus.last.$2, 'União Estável');
  });
}
