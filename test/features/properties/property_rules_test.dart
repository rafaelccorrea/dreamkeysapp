import 'package:Intellisys/features/properties/utils/property_form_extras.dart';
import 'package:Intellisys/features/properties/utils/property_publish_rules.dart';
import 'package:Intellisys/features/properties/utils/property_save_feedback.dart';
import 'package:Intellisys/shared/services/property_service.dart';
import 'package:flutter_test/flutter_test.dart';

Property _property(Map<String, dynamic> extra) => Property.fromJson({
      'id': 'p1',
      'title': 'Casa',
      'type': 'house',
      'status': 'available',
      'isActive': true,
      ...extra,
    });

void main() {
  group('Publicar no site (regra das 5 fotos)', () {
    test('usa publishableImageCount da API', () {
      final p = _property({'publishableImageCount': 5});
      expect(publishableSitePhotoCount(p), 5);
      expect(sitePublishBlockReason(p), isNull);
    });

    test('menos de 5 fotos bloqueia com a contagem', () {
      final p = _property({'publishableImageCount': 3});
      expect(sitePublishBlockReason(p), contains('atualmente: 3'));
    });

    test('inativo e status diferente de disponível bloqueiam antes', () {
      expect(
        sitePublishBlockReason(
          _property({'isActive': false, 'publishableImageCount': 9}),
        ),
        'Propriedade deve estar ativa',
      );
      expect(
        sitePublishBlockReason(
          _property({'status': 'sold', 'publishableImageCount': 9}),
        ),
        'Status deve ser "Disponível"',
      );
    });

    test('sem o campo, conta as fotos válidas (sem vídeo nem ocultas)', () {
      final p = _property({
        'images': [
          {'id': '1', 'url': 'https://x/1.jpg'},
          {'id': '2', 'url': 'https://x/2.jpg', 'showOnPublicSite': false},
          {'id': '3', 'url': 'https://x/3.mp4', 'mediaType': 'video'},
          {'id': '4', 'url': ''},
        ],
      });
      expect(publishableSitePhotoCount(p), 1);
    });

    test('aprovação financeira pendente trava vendido/alugado', () {
      expect(
        financialApprovalLockReason(
          _property({'hasPendingFinancialApproval': true}),
        ),
        isNotNull,
      );
      expect(financialApprovalLockReason(_property({})), isNull);
    });
  });

  group('Aviso depois do PATCH (imoveis-14)', () {
    test('sem nada a mais: sucesso', () {
      final f = PropertySaveFeedback.afterEdit(_property({}));
      expect(f.tone, PropertySaveFeedbackTone.success);
      expect(f.message, contains('atualizada com sucesso'));
    });

    test('pendingChangeRequest: avisa o que foi para aprovação', () {
      final f = PropertySaveFeedback.afterEdit(_property({
        'pendingChangeRequest': {
          'id': 'cr1',
          'fields': ['salePrice', 'title'],
          'fieldLabels': ['Preço de venda', 'Título'],
        },
      }));
      expect(f.tone, PropertySaveFeedbackTone.info);
      expect(f.message, contains('Preço de venda, Título'));
      expect(f.message, isNot(contains('atualizada com sucesso')));
    });

    test('resubmittedForApproval vence e cita o motivo', () {
      final f = PropertySaveFeedback.afterEdit(_property({
        'resubmittedForApproval': {
          'stage': 'publication',
          'reason': 'Fotos escuras',
        },
      }));
      expect(f.tone, PropertySaveFeedbackTone.warning);
      expect(f.message, contains('«Fotos escuras»'));
      expect(f.message, contains('publicação no site'));
    });
  });

  group('Permuta', () {
    test('sem resposta e "sim" sem valor bloqueiam', () {
      expect(
        exchangeValidationError(acceptsExchange: null, exchangeMaxValue: null),
        isNotNull,
      );
      expect(
        exchangeValidationError(acceptsExchange: true, exchangeMaxValue: 0),
        'Informe o valor máximo aceito na permuta.',
      );
      expect(
        exchangeValidationError(acceptsExchange: true, exchangeMaxValue: 1),
        isNull,
      );
      expect(
        exchangeValidationError(acceptsExchange: false, exchangeMaxValue: null),
        isNull,
      );
    });

    test('payload', () {
      expect(
        exchangeApiFields(acceptsExchange: null, exchangeMaxValue: 10),
        isEmpty,
      );
      expect(
        exchangeApiFields(acceptsExchange: false, exchangeMaxValue: 10),
        {'acceptsExchange': false, 'exchangeMaxValue': null},
      );
      expect(
        exchangeApiFields(acceptsExchange: true, exchangeMaxValue: 200000),
        {'acceptsExchange': true, 'exchangeMaxValue': 200000.0},
      );
    });
  });

  group('Cômodos extras do catálogo', () {
    const catalog = [
      PropertyCatalogItem(id: '1', kind: 'room', name: 'Escritório'),
      PropertyCatalogItem(id: '2', kind: 'room', name: 'Despensa'),
    ];

    test('mantém cômodo gravado que saiu do catálogo, sem repetir', () {
      final names = extraRoomNames(catalog, const [
        PropertyExtraRoom(name: 'escritório', quantity: 1),
        PropertyExtraRoom(name: 'Adega', quantity: 2),
      ]);
      expect(names, ['Escritório', 'Despensa', 'Adega']);
    });

    test('quantidade 0 remove; teto 99', () {
      var rooms = setExtraRoomQuantity(const [], 'Escritório', 2);
      expect(extraRoomQuantity(rooms, 'escritório'), 2);
      rooms = setExtraRoomQuantity(rooms, 'Escritório', 150);
      expect(extraRoomQuantity(rooms, 'Escritório'), 99);
      rooms = setExtraRoomQuantity(rooms, 'Escritório', 0);
      expect(rooms, isEmpty);
    });

    test('comparação ignora a ordem', () {
      const a = [
        PropertyExtraRoom(name: 'A', quantity: 1),
        PropertyExtraRoom(name: 'B', quantity: 2),
      ];
      const b = [
        PropertyExtraRoom(name: 'B', quantity: 2),
        PropertyExtraRoom(name: 'A', quantity: 1),
      ];
      expect(sameExtraRooms(a, b), isTrue);
      expect(sameExtraRooms(a, const [PropertyExtraRoom(name: 'A', quantity: 1)]),
          isFalse);
    });

    test('infraestrutura entra nas características sem repetir', () {
      final merged = mergeFeatureOptions(['Piscina', 'Elevador'], const [
        PropertyCatalogItem(id: '3', kind: 'infrastructure', name: 'piscina'),
        PropertyCatalogItem(id: '4', kind: 'infrastructure', name: 'Gerador'),
      ]);
      expect(merged, ['Piscina', 'Elevador', 'Gerador']);
    });
  });
}
