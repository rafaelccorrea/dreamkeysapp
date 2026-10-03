import 'package:Intellisys/features/sale_forms/sale_form_property_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Imóvel da busca (propertyToSaleFormImovel)', () {
    test('mapeia os campos e aplica os padrões do web', () {
      final h = SaleFormPropertyHit.fromJson({
        'id': 'p1',
        'code': 'AP-120',
        'zipCode': '01310-100',
        'street': 'Av. Paulista',
        'complement': 'Ap 12',
        'neighborhood': 'Bela Vista',
        'city': 'São Paulo',
        'state': 'sp',
        'status': 'available',
      });
      expect(h.id, 'p1');
      expect(h.code, 'AP-120');
      expect(h.zipCode, '01310100');
      expect(h.address, 'Av. Paulista');
      expect(h.number, 'S/N');
      expect(h.complement, 'Ap 12');
      expect(h.state, 'SP');
      expect(h.status, 'available');
    });

    test('sem código usa o id; sem CEP/UF usa 00000000/SP', () {
      final h = SaleFormPropertyHit.fromJson({'id': 'p2', 'address': 'Rua A'});
      expect(h.code, 'p2');
      expect(h.zipCode, '00000000');
      expect(h.state, 'SP');
      expect(h.address, 'Rua A');
    });
  });

  test('vendido e alugado não podem ser vinculados (busca do web)', () {
    expect(saleFormPropertyLinkable('sold'), isFalse);
    expect(saleFormPropertyLinkable('RENTED'), isFalse);
    expect(saleFormPropertyLinkable('available'), isTrue);
    expect(saleFormPropertyLinkable(null), isTrue);
  });

  group('propertyId no payload', () {
    test('criar: só vai quando há vínculo', () {
      expect(saleFormPropertyIdPayload(isEdit: false, propertyId: 'x'),
          (true, 'x'));
      expect(saleFormPropertyIdPayload(isEdit: false, propertyId: null),
          (false, null));
      expect(saleFormPropertyIdPayload(isEdit: false, propertyId: '  '),
          (false, null));
    });

    test('editar: sempre vai; sem vínculo manda null (desfaz)', () {
      expect(saleFormPropertyIdPayload(isEdit: true, propertyId: 'x'),
          (true, 'x'));
      expect(saleFormPropertyIdPayload(isEdit: true, propertyId: null),
          (true, null));
    });
  });

  group('aviso do vínculo (linkedPropertyFinalizeNotice)', () {
    test('status que viram Vendido automaticamente: info', () {
      for (final s in kSaleFormAutoSoldStatuses) {
        final n = saleFormLinkedPropertyNotice(status: s, loading: false);
        expect(n.tone, SaleFormLinkedNoticeTone.info, reason: s);
        expect(n.situacao, contains('automaticamente'));
      }
    });

    test('rascunho e outros status: alerta', () {
      expect(
        saleFormLinkedPropertyNotice(status: 'draft', loading: false).tone,
        SaleFormLinkedNoticeTone.warn,
      );
      final outro =
          saleFormLinkedPropertyNotice(status: 'in_negotiation', loading: false);
      expect(outro.tone, SaleFormLinkedNoticeTone.warn);
      expect(outro.situacao, contains('Em Negociação'));
    });

    test('vendido, carregando e sem status: info', () {
      expect(
        saleFormLinkedPropertyNotice(status: 'sold', loading: false).situacao,
        contains('já está como vendido'),
      );
      expect(
        saleFormLinkedPropertyNotice(status: null, loading: true).situacao,
        contains('Consultando'),
      );
      expect(
        saleFormLinkedPropertyNotice(status: null, loading: false).situacao,
        contains('Não foi possível'),
      );
    });
  });
}
