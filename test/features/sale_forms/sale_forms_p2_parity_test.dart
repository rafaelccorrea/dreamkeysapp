import 'package:flutter_test/flutter_test.dart';

import 'package:Intellisys/features/sale_forms/sale_form_list_display.dart';
import 'package:Intellisys/features/sale_forms/sale_form_rules.dart';
import 'package:Intellisys/features/sale_forms/sale_forms_filters_storage.dart';
import 'package:Intellisys/features/sale_forms/services/sale_form_lookup_service.dart';
import 'package:Intellisys/features/sale_forms/signature_lock_policy.dart';
import 'package:Intellisys/shared/services/sale_forms_service.dart';

void main() {
  group('Revisão tela a tela (2ª rodada)', () {
    test('detalhe: contagem de assinaturas entra na ficha das regras', () {
      final f = SaleForm({'id': 'x', 'status': 'waiting_for_signature'});
      expect(f.assinaturasTotal, 0);
      final g = saleFormComResumoDeAssinaturas(f, total: 3, assinadas: 1);
      expect(g.assinaturasTotal, 3);
      expect(g.assinaturasAssinadas, 1);
      expect(g.id, 'x');
      expect(identical(saleFormComResumoDeAssinaturas(f), f), isTrue);
    });

    test('edição confere o status recém-lido', () {
      expect(saleFormEdicaoBloqueada(SaleForm({'status': 'waiting_for_signature'})),
          isNull);
      expect(saleFormEdicaoBloqueada(SaleForm({'status': 'finalized'})),
          contains('finalizada'));
      expect(saleFormEdicaoBloqueada(SaleForm({'status': 'canceled'})),
          contains('cancelada'));
      expect(saleFormEdicaoBloqueada(SaleForm({'status': 'processing'})),
          contains('só para leitura'));
      expect(
        saleFormEdicaoBloqueada(SaleForm({
          'status': 'waiting_for_signature',
          'deletedAt': '2026-10-01T00:00:00Z',
        })),
        contains('excluída'),
      );
    });

    test('teto de 10 vinculados conta participantes da comissão', () {
      final dez = [for (var i = 0; i < 10; i++) 'u$i'];
      expect(saleFormVinculadosErro(dez, ['u1', null]), isNull);
      expect(saleFormVinculadosErro(dez, ['novo']), contains('Hoje são 11'));
    });

    test('filtros de equipe do web', () {
      // Modal de tipo: só `useInSaleForms === true`.
      expect(saleFormEquipeElegivel({'useInSaleForms': true}), isTrue);
      expect(saleFormEquipeElegivel({}), isFalse);
      // Trocar equipe: ausente vale; pessoal fica de fora.
      expect(saleFormEquipeElegivel({}, paraTrocarEquipe: true), isTrue);
      expect(
        saleFormEquipeElegivel({'useInSaleForms': false},
            paraTrocarEquipe: true),
        isFalse,
      );
      expect(
        saleFormEquipeElegivel({'isPersonal': true}, paraTrocarEquipe: true),
        isFalse,
      );
    });
  });

  group('V10 — status "processing"', () {
    test('rótulos iguais ao web', () {
      expect(SaleFormStatus.processing.label, 'Em processamento');
      expect(SaleFormStatus.processing.shortLabel, 'Em processo');
    });

    test('hero separa aguardando e em andamento', () {
      const st = SaleFormStats(
        total: 10,
        waitingForSignature: 3,
        processing: 2,
        finalized: 4,
        canceled: 1,
      );
      expect(saleFormsHeroResumo(st),
          '10 fichas · 3 aguardando assinatura · 2 em andamento');
      expect(saleFormsHeroResumo(SaleFormStats.zero), '0 fichas');
      expect(
        saleFormsHeroResumo(const SaleFormStats(
          total: 1,
          waitingForSignature: 0,
          processing: 1,
          finalized: 0,
          canceled: 0,
        )),
        '1 ficha · 1 em andamento',
      );
    });
  });

  group('V11 — rastreabilidade da linha', () {
    test('usa lastAudit.summary quando vem', () {
      final f = SaleForm({
        'lastAudit': {'summary': 'Editada por Ana'},
        'status': 'finalized',
      });
      expect(saleFormRastreioLinha(f), 'Editada por Ana');
    });

    test('sem resumo: desativada, recusa da trava e datas', () {
      final f = SaleForm({
        'status': 'waiting_for_signature',
        'ativo': false,
        'signatureLockRefusedAt': '2026-10-01T13:00:00.000Z',
        'signatureLockRefusalReason': 'Dados errados',
        'createdAt': '2026-09-30T12:00:00.000Z',
        'updatedAt': '2026-10-01T13:00:00.000Z',
      });
      final s = saleFormRastreioLinha(f);
      expect(s, contains('desativada automaticamente'));
      expect(s, contains('Recusa registrada no fluxo de assinatura pendente'));
      expect(s, contains('Justificativa: Dados errados'));
      expect(s, contains('Criada em'));
    });
  });

  group('V12 — nível das gerências', () {
    test('mantém o nível gravado quando nenhuma gerência entrou/saiu', () {
      expect(saleFormGerenciaNiveis([1, 3], 2), [1, 3]);
    });
    test('renumera 1..n quando entra uma gerência nova', () {
      expect(saleFormGerenciaNiveis([1, 3, null], 2), [1, 2, 3]);
    });
    test('renumera quando uma sai', () {
      expect(saleFormGerenciaNiveis([3], 2), [1]);
    });
    test('criação: posição entre todas as gerências', () {
      expect(saleFormGerenciaNiveis([null, null], 0), [1, 2]);
    });
  });

  group('V13 — saleUnitId', () {
    const units = [
      SaleFormSaleUnit(id: 'u1', name: 'Centro'),
      SaleFormSaleUnit(id: 'u2', name: 'Praia'),
    ];
    test('casa pelo nome exato', () {
      expect(saleFormSaleUnitIdFor(' Praia ', units), 'u2');
    });
    test('sem casar ou vazio não vai', () {
      expect(saleFormSaleUnitIdFor('praia', units), isNull);
      expect(saleFormSaleUnitIdFor('', units), isNull);
    });
  });

  group('V15 — nascimento no futuro', () {
    final hoje = DateTime(2026, 10, 3);
    test('futuro é erro; hoje e passado não', () {
      expect(saleFormBirthDateFutureError('2026-10-04', today: hoje),
          'Data de nascimento não pode ser no futuro');
      expect(saleFormBirthDateFutureError('2026-10-03', today: hoje), isNull);
      expect(saleFormBirthDateFutureError('1990-01-01', today: hoje), isNull);
      expect(saleFormBirthDateFutureError('', today: hoje), isNull);
      expect(saleFormBirthDateFutureError('Não aplicável', today: hoje), isNull);
    });

    test('a regra da aba do comprador barra o futuro', () {
      final e = computeSaleFormErrorsForTab(
        1,
        SaleFormRulesInput(
          fd: {'buyerBirthDate': '2030-01-01'},
          generalGroup: false,
          hasBuyerSpouse: false,
          hasSellerSpouse: false,
          isLancamentoOuMcmv: false,
          commissionModelNaoAplicavel: false,
          installmentsEnabled: false,
          installmentsEqual: true,
          installmentValues: const [],
          fichaAnteriorAosCamposNovos: false,
        ),
        today: hoje,
      );
      expect(e['buyerBirthDate'], 'Data de nascimento não pode ser no futuro');
    });
  });

  group('V15 — filtros persistidos', () {
    final agora = DateTime(2026, 10, 3, 12);
    const uuid = '0b6a8c2e-1f2d-4e5a-9b7c-123456789abc';

    test('ida e volta', () {
      final raw = encodeSaleFormsFilters(
        SaleFormFilters(
          search: ' joão ',
          statuses: const [SaleFormStatus.processing],
          userIds: const [uuid],
          teamIds: const [uuid, 'nao-e-uuid'],
          saleUnit: 'Centro',
          dateFrom: DateTime(2026, 9, 1),
          saleDateTo: DateTime(2026, 9, 30),
          sortBy: 'buyerName',
          sortOrder: 'ASC',
        ),
        showDeletedOnly: true,
        savedAt: agora,
      );
      final out = decodeSaleFormsFilters(raw, now: agora)!;
      expect(out.showDeletedOnly, isTrue);
      expect(out.filters.search, 'joão');
      expect(out.filters.effectiveStatuses, [SaleFormStatus.processing]);
      expect(out.filters.userIds, [uuid]);
      expect(out.filters.teamIds, [uuid]);
      expect(out.filters.saleUnit, 'Centro');
      expect(out.filters.dateFrom, DateTime(2026, 9, 1));
      expect(out.filters.saleDateTo, DateTime(2026, 9, 30));
      expect(out.filters.sortBy, 'buyerName');
      expect(out.filters.sortOrder, 'ASC');
      expect(out.filters.page, 1);
    });

    test('vence em 30 dias, ignora lixo e ordenação inválida', () {
      final raw = encodeSaleFormsFilters(
        const SaleFormFilters(sortBy: 'hack'),
        showDeletedOnly: false,
        savedAt: agora,
      );
      expect(
        decodeSaleFormsFilters(raw,
            now: agora.add(const Duration(days: 31))),
        isNull,
      );
      expect(decodeSaleFormsFilters(raw, now: agora)!.filters.sortBy,
          'createdAt');
      expect(decodeSaleFormsFilters('{x', now: agora), isNull);
      expect(decodeSaleFormsFilters(null, now: agora), isNull);
    });

    test('chave por empresa', () {
      expect(saleFormsFiltersKey('c1'), 'imobx_sale_forms_filters:c1');
      expect(saleFormsFiltersKey(null), 'imobx_sale_forms_filters');
    });
  });

  group('V7 — trava a cada tela', () {
    test('rotas que o web pula', () {
      for (final r in [
        '/',
        '/login',
        '/forgot-password',
        '/reset-password',
        '/two-factor',
        '/sale-forms',
        '/sale-forms/abc',
        '/sale-forms/pending-signatures',
        '/rental-forms',
      ]) {
        expect(signatureLockRotaIgnorada(r), isTrue, reason: r);
      }
    });
    test('demais telas consultam', () {
      for (final r in [null, '', '/home', '/properties', '/proposals',
          '/sale-formsx']) {
        expect(signatureLockRotaIgnorada(r), isFalse, reason: '$r');
      }
    });
  });
}
