import 'package:flutter_test/flutter_test.dart';

import 'package:Intellisys/features/sale_forms/sale_form_new_from_proposal.dart';
import 'package:Intellisys/features/sale_forms/sale_form_rules.dart';

/// Paridade da criação/edição da ficha de venda com o web
/// (`CreateSaleFormPage.tsx`) — itens V-C1..V-C11 e V-L1 da auditoria de
/// 03/10/2026.
void main() {
  group('V-C7 RG (maskRG do web)', () {
    test('só dígitos no formato 00.000.000-0', () {
      expect(saleFormMaskRg('123456789'), '12.345.678-9');
      expect(saleFormMaskRg('MG 12.345.678-9'), '12.345.678-9');
      expect(saleFormMaskRg('1234'), '12.34');
      expect(saleFormMaskRg('12345678'), '12.345.678');
      expect(saleFormMaskRg(''), '');
    });

    test('mais dígitos: corta depois do 1º dígito após o hífen (como o web)',
        () {
      expect(saleFormMaskRg('1234567890123'), '12.345.678-9');
    });
  });

  group('V-C10 limites (maxLength do web)', () {
    TextEditingValue fmt(SaleFormFieldFormatter f, String v) =>
        f.formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: v));

    test('corta o que passa do limite', () {
      final f = SaleFormFieldFormatter(SaleFormMask.none, maxLength: 50);
      expect(fmt(f, 'x' * 60).text.length, 50);
      final cep = SaleFormFieldFormatter(SaleFormMask.cep, maxLength: 9);
      expect(fmt(cep, '12345678999').text, '12345-678');
    });

    test('"N/A" vira "Não aplicável" mesmo com limite menor (CEP 9)', () {
      final f = SaleFormFieldFormatter(SaleFormMask.cep, maxLength: 9);
      expect(fmt(f, 'n/a').text, kSaleFormNa);
    });

    test('RG pela máscara do formatter', () {
      final f = SaleFormFieldFormatter(SaleFormMask.rg, maxLength: 50);
      expect(fmt(f, '123456789').text, '12.345.678-9');
    });
  });

  group('V-C9 profissões', () {
    test('lista igual ao PROFISSOES_COMUNS do web', () {
      expect(kSaleFormProfissoesComuns.length, 46);
      expect(kSaleFormProfissoesComuns.first, 'Advogado');
      expect(kSaleFormProfissoesComuns.last, 'Outro');
    });

    test('sugere pelo que contém, sem caixa', () {
      expect(saleFormProfissoesSugeridas('engen'), ['Engenheiro', 'Engenheira']);
      expect(saleFormProfissoesSugeridas(''), kSaleFormProfissoesComuns);
      // Já escolhida: não sugere ela mesma.
      expect(saleFormProfissoesSugeridas('Outro'), isEmpty);
    });
  });

  group('V-C8 unidade responsável', () {
    test('só unidades; sem "Não se aplica"', () {
      final op = saleFormUnidadeOpcoes(['Centro', 'Sul'], '');
      expect(op.opcoes, ['Centro', 'Sul']);
      expect(op.rotulos, isEmpty);
    });

    test('valor gravado fora da lista fica como "(indisponível)"', () {
      final op = saleFormUnidadeOpcoes(['Centro'], 'Filial antiga');
      expect(op.opcoes, ['Centro', 'Filial antiga']);
      expect(op.rotulos['Filial antiga'], 'Filial antiga (indisponível)');
      final na = saleFormUnidadeOpcoes(['Centro'], kSaleFormNa);
      expect(na.opcoes, contains(kSaleFormNa));
    });
  });

  group('V-C1 nome de quem está na comissão', () {
    const membros = {'u1': 'Ana Corretora'};

    test('corretor sem nome no GET: resolve pelo membro', () {
      expect(saleFormNomeParticipante(id: 'u1', nomesPorId: membros),
          'Ana Corretora');
    });

    test('sem membro: nome gravado, senão null', () {
      expect(saleFormNomeParticipante(id: 'x', nomeGravado: 'Bia'), 'Bia');
      expect(saleFormNomeParticipante(id: 'x'), isNull);
    });

    test('gerência prefere o nome gravado', () {
      expect(
        saleFormNomeParticipante(
          id: 'u1',
          nomeGravado: 'Ana (gestora)',
          nomesPorId: membros,
          preferirGravado: true,
        ),
        'Ana (gestora)',
      );
    });
  });

  group('V-C2 gerência antiga sem gestorId', () {
    final vinc = [(id: 'g1', name: 'Carlos'), (id: 'g2', name: 'Dora')];

    test('casa o id pelo nome entre os vinculados', () {
      expect(saleFormGestorIdPorNome('Dora', vinc), 'g2');
      expect(saleFormGestorIdPorNome(' Carlos ', vinc), 'g1');
    });

    test('sem casar: null', () {
      expect(saleFormGestorIdPorNome('Fulano', vinc), isNull);
      expect(saleFormGestorIdPorNome(null, vinc), isNull);
    });

    test('linha antiga sem usuário não barra; linha nova barra', () {
      expect(
        saleFormLinhaSemUsuarioPermitida(ehGerencia: true, legadoSemId: true),
        isTrue,
      );
      expect(
        saleFormLinhaSemUsuarioPermitida(ehGerencia: true, legadoSemId: false),
        isFalse,
      );
      expect(
        saleFormLinhaSemUsuarioPermitida(ehGerencia: false, legadoSemId: true),
        isFalse,
      );
    });

    test('salva a linha só com o nome, como o payload do web', () {
      expect(
        saleFormGerenciaLinha(nivel: 1, porcentagem: 2, nome: 'Fulano'),
        {'nivel': 1, 'porcentagem': 2.0, 'nome': 'Fulano', 'emitirNota': false},
      );
      expect(
        saleFormGerenciaLinha(
          nivel: 2,
          porcentagem: 1,
          nome: 'Dora',
          gestorId: 'g2',
          papel: 'gestor_sdr',
          emitirNota: true,
        ),
        {
          'nivel': 2,
          'porcentagem': 1.0,
          'nome': 'Dora',
          'gestorId': 'g2',
          'papel': 'gestor_sdr',
          'emitirNota': true,
        },
      );
    });
  });

  group('V-C4 captadores aninhados', () {
    final raw = [
      {'id': 'c1', 'nome': 'Edu', 'porcentagem': 2},
      {'id': '', 'porcentagem': 5},
      {'id': 'c2', 'porcentagem': '1.5'},
    ];

    test('reenvia como o web (sem id não vai)', () {
      expect(saleFormCaptadoresPayload(raw), [
        {'id': 'c1', 'nome': 'Edu', 'porcentagem': 2},
        {'id': 'c2', 'porcentagem': 1.5},
      ]);
      expect(saleFormCaptadoresPayload(null), isNull);
    });

    test('soma na trava de corretores', () {
      expect(saleFormCaptadoresSoma(raw), 8.5);
      expect(saleFormCaptadoresSoma(null), 0);
    });
  });

  group('V-C6 erros 400 do back', () {
    test('details.validationErrors aninhado', () {
      final body = {
        'statusCode': 400,
        'details': {
          'validationErrors': [
            {'field': 'buyerEmail', 'message': 'buyerEmail must be an email, E-mail inválido'},
            {
              'field': 'empreendimentoData',
              'children': [
                {'field': 'incorporadora', 'message': 'Incorporadora é obrigatória'},
              ],
            },
          ],
        },
      };
      final e = saleFormApiValidationErrors(body);
      expect(e.map((x) => x.campo), ['buyerEmail', 'empreendimentoData.incorporadora']);
      expect(e.first.mensagem, 'E-mail inválido');
      expect(saleFormCampoDoErroApi(e[1].campo), 'incorporadora');
      expect(saleFormAbaDoCampo('incorporadora'), 5);
      expect(saleFormAbaDoCampo('buyerEmail'), 1);
    });

    test('errors na raiz e corpo inválido', () {
      final e = saleFormApiValidationErrors({
        'errors': [
          {'field': 'saleUnit', 'message': 'Unidade inválida'},
        ],
      });
      expect(e.single.campo, 'saleUnit');
      expect(saleFormApiValidationErrors('x'), isEmpty);
      expect(saleFormApiValidationErrors(null), isEmpty);
    });

    test('campos aninhados e abas', () {
      expect(saleFormCampoDoErroApi('commissionInstallments.quantidadeParcelas'),
          'commissionInstallmentsCount');
      expect(saleFormCampoDoErroApi('commissionInstallments.valoresParcelas.0'),
          'commissionInstallmentValues');
      expect(saleFormCampoDoErroApi('commissionsData.corretores.0.id'),
          'commissionsData');
      expect(saleFormAbaDoCampo('commissionsData'), 7);
      expect(saleFormAbaDoCampo('sellerSpouseComplement'), 4);
      expect(saleFormAbaDoCampo('saleUnit'), 0);
      expect(saleFormAbaDoCampo('qualquer'), isNull);
    });
  });

  group('V-C11 mensagens do web', () {
    SaleFormRulesInput input(Map<String, String> fd) => SaleFormRulesInput(
          fd: fd,
          hasBuyerSpouse: true,
          hasSellerSpouse: false,
          generalGroup: false,
          isLancamentoOuMcmv: false,
          commissionModelNaoAplicavel: false,
          installmentsEnabled: false,
          installmentsEqual: true,
          installmentValues: const [],
          fichaAnteriorAosCamposNovos: false,
        );

    test('textos iguais aos do web', () {
      final geral = computeSaleFormErrorsForTab(0, input({}));
      expect(geral['saleUnit'], 'Unidade de venda é obrigatória');
      final comprador =
          computeSaleFormErrorsForTab(1, input({'buyerPhone': '1234'}));
      expect(comprador['buyerPhone'], 'Telefone inválido (mín. 10 dígitos)');
      final conjuge = computeSaleFormErrorsForTab(
          2, input({'buyerSpousePhone': '12', 'buyerSpouseZipCode': '1'}));
      expect(conjuge['buyerSpouseName'],
          'Nome do cônjuge é obrigatório quando “Possui cônjuge/sócio” está marcado');
      expect(conjuge['buyerSpousePhone'], 'Telefone inválido');
      expect(conjuge['buyerSpouseZipCode'], 'CEP inválido');
      final vendedor =
          computeSaleFormErrorsForTab(3, input({'sellerPhone': '12'}));
      expect(vendedor['sellerPhone'], 'Telefone inválido');
    });
  });

  group('V-L1 nova ficha da proposta', () {
    test('só retoma rascunho da MESMA proposta', () {
      expect(saleFormRascunhoDaProposta({'propostaId': 'p1'}, 'p1'), isTrue);
      expect(saleFormRascunhoDaProposta({'propostaId': 'p2'}, 'p1'), isFalse);
      expect(saleFormRascunhoDaProposta({}, 'p1'), isFalse);
      expect(saleFormRascunhoDaProposta(null, 'p1'), isFalse);
    });
  });
}
