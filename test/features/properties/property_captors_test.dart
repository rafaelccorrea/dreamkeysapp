import 'package:Intellisys/features/properties/services/property_owner_check_service.dart';
import 'package:Intellisys/features/properties/utils/property_captor_slots.dart';
import 'package:Intellisys/features/properties/utils/property_save_feedback.dart';
import 'package:Intellisys/shared/services/property_service.dart';
import 'package:Intellisys/shared/utils/property_finalidade.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('evaluateCaptorSlots (regra de slots do web)', () {
    test('sem finalidade: inválido e pede a finalidade', () {
      final e = evaluateCaptorSlots(
        finalidade: null,
        saleIds: const ['u1'],
        rentIds: const [],
      );
      expect(e.valid, isFalse);
      expect(e.finalidadeMissing, isTrue);
      expect(e.missingLabels, ['Finalidade']);
    });

    test('venda exige captador de venda; locação fica opcional', () {
      final falta = evaluateCaptorSlots(
        finalidade: PropertyFinalidade.venda,
        saleIds: const [],
        rentIds: const ['u1'],
      );
      expect(falta.valid, isFalse);
      expect(falta.missingRoles, [CaptorRole.venda]);
      expect(falta.missingLabels, ['Captador de venda']);

      final ok = evaluateCaptorSlots(
        finalidade: PropertyFinalidade.venda,
        saleIds: const ['u1'],
        rentIds: const [],
      );
      expect(ok.valid, isTrue);
    });

    test('ambos exige os dois; a mesma pessoa pode ocupar os dois', () {
      final falta = evaluateCaptorSlots(
        finalidade: PropertyFinalidade.ambos,
        saleIds: const [],
        rentIds: const [],
      );
      expect(falta.missingRoles, [CaptorRole.venda, CaptorRole.locacao]);
      expect(
        captorRuleMessage(falta, PropertyFinalidade.ambos),
        contains('um captador de venda e um de locação'),
      );
      final ok = evaluateCaptorSlots(
        finalidade: PropertyFinalidade.ambos,
        saleIds: const ['u1'],
        rentIds: const ['u1'],
      );
      expect(ok.valid, isTrue);
      expect(
        captorRuleMessage(ok, PropertyFinalidade.ambos),
        'Captação completa para venda e locação.',
      );
    });
  });

  group('splitCaptorsByRole', () {
    test('usa o papel gravado e joga quem não tem papel em venda', () {
      final r = splitCaptorsByRole(
        captors: const [
          (id: 'a', role: 'venda'),
          (id: 'b', role: 'locacao'),
          (id: 'a', role: 'locacao'),
        ],
        allIds: const ['a', 'b', 'c'],
        finalidadeGravada: PropertyFinalidade.ambos,
      );
      expect(r.sale, ['a', 'c']);
      expect(r.rent, ['b', 'a']);
    });

    test('resposta sem papel segue a finalidade (ou os dois sem ela)', () {
      final locacao = splitCaptorsByRole(
        captors: const [(id: 'a', role: null)],
        allIds: const ['a'],
        finalidadeGravada: PropertyFinalidade.locacao,
      );
      expect(locacao.sale, isEmpty);
      expect(locacao.rent, ['a']);

      final legado = splitCaptorsByRole(
        captors: const [],
        allIds: const ['a'],
        finalidadeGravada: null,
      );
      expect(legado.sale, ['a']);
      expect(legado.rent, ['a']);
    });
  });

  group('payload de criação', () {
    test('slots viram capturedById/Ids + captorAssignments', () {
      final p = captorCreatePayload(
        saleIds: const ['a'],
        rentIds: const ['b', 'a'],
        responsibleIds: const [],
        currentUserId: 'me',
      );
      expect(p['capturedById'], 'a');
      expect(p['capturedByIds'], ['a', 'b']);
      expect(p['captorAssignments'], [
        {'userId': 'a', 'role': 'venda'},
        {'userId': 'b', 'role': 'locacao'},
        {'userId': 'a', 'role': 'locacao'},
      ]);
      // Responsáveis vazios caem no usuário logado (web).
      expect(p['responsibleUserIds'], ['me']);
    });

    test('rascunho sem captador ainda manda capturedById (obrigatório no DTO)',
        () {
      final p = captorCreatePayload(
        saleIds: const [],
        rentIds: const [],
        responsibleIds: const ['r1'],
        currentUserId: 'me',
      );
      expect(p['capturedById'], 'me');
      expect(p.containsKey('captorAssignments'), isFalse);
      expect(p['responsibleUserIds'], ['r1']);
    });
  });

  group('diff de captadores na edição (imoveis-04)', () {
    test('nada mudou: nada vai no PATCH', () {
      final p = captorEditPatch(
        loadedSale: const ['a'],
        loadedRent: const ['b'],
        sale: const ['a'],
        rent: const ['b'],
        loadedResponsibles: const ['r1', 'r2'],
        responsibles: const ['r1', 'r2'],
      );
      expect(p, isEmpty);
    });

    test('trocou quem capta: vai a lista inteira + papéis', () {
      final p = captorEditPatch(
        loadedSale: const ['a'],
        loadedRent: const [],
        sale: const ['c'],
        rent: const [],
        loadedResponsibles: const ['r1'],
        responsibles: const ['r1'],
      );
      expect(p['capturedById'], 'c');
      expect(p['capturedByIds'], ['c']);
      expect(p['captorAssignments'], [
        {'userId': 'c', 'role': 'venda'},
      ]);
      expect(p.containsKey('responsibleUserIds'), isFalse);
    });

    test('mesmas pessoas com papel novo: só captorAssignments', () {
      final p = captorEditPatch(
        loadedSale: const ['a'],
        loadedRent: const [],
        sale: const ['a'],
        rent: const ['a'],
        loadedResponsibles: const ['r1'],
        responsibles: const ['r1'],
      );
      expect(p.containsKey('capturedByIds'), isFalse);
      expect(p['captorAssignments'], [
        {'userId': 'a', 'role': 'venda'},
        {'userId': 'a', 'role': 'locacao'},
      ]);
    });

    test('finalidade trocada sem mexer nos slots: reclassifica', () {
      final p = captorEditPatch(
        loadedSale: const ['a'],
        loadedRent: const ['a'],
        sale: const ['a'],
        rent: const ['a'],
        loadedResponsibles: const ['r1'],
        responsibles: const ['r1'],
        finalidadeChanged: true,
      );
      expect(p.keys, ['captorAssignments']);
    });

    test('responsáveis: só quando muda o conjunto ou o principal', () {
      final ordem = captorEditPatch(
        loadedSale: const ['a'],
        loadedRent: const [],
        sale: const ['a'],
        rent: const [],
        loadedResponsibles: const ['r1', 'r2'],
        responsibles: const ['r2', 'r1'],
      );
      expect(ordem['responsibleUserIds'], ['r2', 'r1']);

      final vazio = captorEditPatch(
        loadedSale: const ['a'],
        loadedRent: const [],
        sale: const ['a'],
        rent: const [],
        loadedResponsibles: const ['r1'],
        responsibles: const [],
      );
      expect(vazio, isEmpty);
    });
  });

  group('valores atuais na edição', () {
    test('Property lê o papel de cada captador', () {
      final p = Property.fromJson({
        'id': 'p1',
        'title': 'Casa',
        'type': 'house',
        'status': 'available',
        'captors': [
          {'id': 'a', 'name': 'Ana', 'role': 'venda'},
          {'id': 'a', 'name': 'Ana', 'role': 'locacao'},
          {'id': 'b', 'name': 'Bia', 'role': null},
        ],
        'capturedByIds': ['a', 'b'],
      });
      expect(p.captors!.map((c) => c.role).toList(), ['venda', 'locacao', null]);
      final ids = loadedCaptorIds(
        captors: [for (final c in p.captors!) (id: c.id, role: c.role)],
        capturedByIds: p.capturedByIds,
        capturedById: p.capturedById,
      );
      expect(ids, ['a', 'b']);
    });

    test('responsáveis: responsibleUserIds > responsibles > legado', () {
      expect(
        loadedResponsibleIds(
          responsibleUserIds: null,
          responsiblesFromList: const ['x'],
          responsibleUserId: 'y',
        ),
        ['x'],
      );
      expect(
        loadedResponsibleIds(
          responsibleUserIds: const [],
          responsiblesFromList: const [],
          responsibleUserId: 'y',
        ),
        ['y'],
      );
    });
  });

  group('resposta da edição com troca de captador', () {
    test('pendingChangeRequest vira aviso de aprovação (não "sucesso")', () {
      final p = Property.fromJson({
        'id': 'p1',
        'title': 'Casa',
        'type': 'house',
        'status': 'available',
        'pendingChangeRequest': {
          'id': 'cr1',
          'fields': ['capturedByIds', 'captorAssignments'],
          'fieldLabels': ['Captadores', 'Captadores (venda / locação)'],
        },
      });
      final f = PropertySaveFeedback.afterEdit(p);
      expect(f.tone, PropertySaveFeedbackTone.info);
      expect(f.message, contains('Captadores, Captadores (venda / locação)'));
      expect(f.message, contains('aguardam aprovação'));
    });
  });

  group('owner-check (imoveis-29)', () {
    test('payload e chave de confirmação como o web', () {
      final p = buildOwnerCheckPayload(
        ownerName: '  João ',
        ownerPhone: ' (11) 99999-0000 ',
        ownerDocument: '123.456.789-09',
      );
      expect(p, {
        'ownerName': 'João',
        'ownerPhone': '(11) 99999-0000',
        'ownerDocument': '12345678909',
      });
      expect(
        buildOwnerCheckPayload(
          ownerName: 'J',
          ownerPhone: '1',
          ownerDocument: '',
        ).containsKey('ownerDocument'),
        isFalse,
      );
      expect(
        buildOwnerAckKey(
          ownerName: 'João',
          ownerPhone: '(11) 9999',
          ownerDocument: '1.2',
        ),
        'João|119999|12',
      );
    });

    test('lê hasExisting e o motivo do casamento', () {
      final r = PropertyOwnerCheckResult.fromJson({
        'hasExisting': true,
        'properties': [
          {
            'id': 'p9',
            'code': '77',
            'title': 'Apto',
            'street': 'Rua A',
            'number': '1',
            'neighborhood': 'Centro',
            'city': 'SP',
            'state': 'SP',
            'matchReason': 'document',
          },
          {'title': 'sem id'},
        ],
      });
      expect(r.hasExisting, isTrue);
      expect(r.properties, hasLength(1));
      expect(r.properties.first.matchLabel, 'CPF/CNPJ');
      expect(
        PropertyOwnerCheckResult.fromJson({'hasExisting': false}).hasExisting,
        isFalse,
      );
    });
  });
}
