import 'package:Intellisys/features/properties/utils/property_extra_fields.dart';
import 'package:Intellisys/features/properties/utils/property_fallback_title.dart';
import 'package:Intellisys/features/properties/utils/property_owner_address.dart';
import 'package:Intellisys/shared/services/property_service.dart';
import 'package:flutter_test/flutter_test.dart';

Property _property(Map<String, dynamic> extra) => Property.fromJson({
      'id': 'p1',
      'title': 'Casa',
      'type': 'house',
      'status': 'available',
      ...extra,
    });

PropertyExtraFieldValues _v(Map<String, String> texts,
        [Map<String, bool> flags = const {}]) =>
    PropertyExtraFieldValues(texts: texts, flags: flags);

void main() {
  group('Ficha adicional — criação (forma do buildCreatePropertyApiPayload)',
      () {
    test('marcadores sempre vão (false por padrão); vazios não vão', () {
      final api = const PropertyExtraFieldValues()
          .createApiFields(publishToSite: false);
      for (final f in PropertyExtraFlag.fichaFlags) {
        expect(api[f.key], isFalse, reason: f.key);
      }
      expect(api['isSitePremiumLine'], isFalse);
      for (final k in PropertyExtraTextKey.all) {
        expect(api.containsKey(k), isFalse, reason: k);
      }
    });

    test('números e textos convertidos como no web', () {
      final api = _v({
        'rooms': '3',
        'builtYear': '2015',
        'unitFloor': '-2',
        'floors': '12',
        'buildings': '2',
        'elevators': '4',
        'lotArea': '1.200,50',
        'ownersPercentage': '12,5',
        'ownersRate': '8',
        'alternativeCode': '  ABC-1 ',
        'sunPosition': 'Nascente',
        'houseRules': 'Sem pets',
      }, {
        'hasExclusivity': true,
        'guarantor': true,
      }).createApiFields(publishToSite: false);
      expect(api['rooms'], 3);
      expect(api['builtYear'], 2015);
      expect(api['unitFloor'], -2);
      expect(api['floors'], 12);
      expect(api['buildings'], 2);
      expect(api['elevators'], 4);
      expect(api['lotArea'], 1200.5);
      expect(api['ownersPercentage'], 12.5);
      expect(api['ownersRate'], 8.0);
      expect(api['alternativeCode'], 'ABC-1');
      expect(api['sunPosition'], 'Nascente');
      expect(api['houseRules'], 'Sem pets');
      expect(api['hasExclusivity'], isTrue);
      expect(api['guarantor'], isTrue);
      expect(api['bail'], isFalse);
    });

    test('ano fora de 1800-2100 vai null (nunca 0), igual ao web', () {
      expect(
        _v({'builtYear': '0'}).createApiFields(publishToSite: false)['builtYear'],
        isNull,
      );
      expect(
        _v({'builtYear': '0'})
            .createApiFields(publishToSite: false)
            .containsKey('builtYear'),
        isTrue,
      );
    });

    test('linha premium só vai true com o imóvel no site', () {
      final v = _v({}, {'isSitePremiumLine': true});
      expect(v.createApiFields(publishToSite: false)['isSitePremiumLine'],
          isFalse);
      expect(v.createApiFields(publishToSite: true)['isSitePremiumLine'],
          isTrue);
    });
  });

  group('Ficha adicional — edição manda só o que mudou', () {
    final loaded = PropertyExtraFieldValues.fromProperty(_property({
      'hasPlaque': true,
      'builtYear': 2001,
      'unitFloor': 5,
      'lotArea': '360.00',
      'nearby': 'Escola',
      'rooms': 2,
      'isSitePremiumLine': true,
    }));

    test('preenche a partir do Property', () {
      expect(loaded.flag('hasPlaque'), isTrue);
      expect(loaded.flag('isSitePremiumLine'), isTrue);
      expect(loaded.text('builtYear'), '2001');
      expect(loaded.text('unitFloor'), '5');
      expect(loaded.text('lotArea'), '360');
      expect(loaded.text('nearby'), 'Escola');
      expect(loaded.text('rooms'), '2');
    });

    test('sem mudança, nada vai no PATCH', () {
      expect(loaded.editApiFields(loaded, publishToSite: true), isEmpty);
    });

    test('mudou / apagou: só as chaves tocadas; apagado vai null', () {
      final texts = Map<String, String>.from(loaded.texts)
        ..['nearby'] = ''
        ..['floors'] = '10';
      final flags = Map<String, bool>.from(loaded.flags)..['hasPlaque'] = false;
      final api = PropertyExtraFieldValues(texts: texts, flags: flags)
          .editApiFields(loaded, publishToSite: true);
      expect(api, {'hasPlaque': false, 'nearby': null, 'floors': 10});
    });

    test('tirar do site desliga a linha premium', () {
      final api = loaded.editApiFields(loaded, publishToSite: false);
      expect(api, {'isSitePremiumLine': false});
    });

    test('rascunho local guarda e restaura', () {
      final back = PropertyExtraFieldValues.fromDraft(loaded.toDraft())!;
      expect(back.editApiFields(loaded, publishToSite: true), isEmpty);
      expect(PropertyExtraFieldValues.fromDraft(null), isNull);
    });
  });

  group('Ficha adicional — limites do DTO', () {
    test('valores válidos passam', () {
      expect(
        _v({'builtYear': '1990', 'unitFloor': '-5', 'ownersRate': '100'})
            .validationError(),
        isNull,
      );
    });

    test('fora do intervalo avisa antes do 400', () {
      expect(_v({'builtYear': '1700'}).validationError(), contains('1800'));
      expect(_v({'floors': '201'}).validationError(), contains('Andares'));
      expect(_v({'elevators': '101'}).validationError(), contains('Elevadores'));
      expect(_v({'unitFloor': '-6'}).validationError(), contains('Andar'));
      expect(_v({'ownersPercentage': '120'}).validationError(),
          contains('% proprietário'));
      expect(_v({'alternativeCode': 'x' * 51}).validationError(), isNotNull);
    });

    test('salas só no tipo Comercial (contaSalas do web)', () {
      expect(propertyTypeCountsRooms('commercial'), isTrue);
      expect(propertyTypeCountsRooms('office'), isFalse);
      expect(propertyTypeCountsRooms('house'), isFalse);
    });
  });

  group('Área digitada no app', () {
    test('ponto decimal não vira milhar (120.5 não é 1205)', () {
      expect(parseDecimalInput('120.5'), 120.5);
      expect(parseDecimalInput('120.0'), 120.0);
      expect(parseDecimalInput('1.200,50'), 1200.5);
      expect(parseDecimalInput('85,3'), 85.3);
      expect(parseDecimalInput(''), isNull);
      expect(parseDecimalInput('abc'), isNull);
    });
  });

  group('Endereço do proprietário', () {
    const parts = PropertyOwnerAddressValues(
      zipCode: '01310-100',
      street: 'Av. Paulista',
      number: '1000',
      complement: 'Apto 42',
      neighborhood: 'Bela Vista',
      city: 'São Paulo',
      state: 'sp',
    );

    test('criação manda as partes preenchidas, CEP só dígitos e UF maiúscula',
        () {
      expect(parts.createApiFields(), {
        'ownerZipCode': '01310100',
        'ownerStreet': 'Av. Paulista',
        'ownerNumber': '1000',
        'ownerComplement': 'Apto 42',
        'ownerNeighborhood': 'Bela Vista',
        'ownerCity': 'São Paulo',
        'ownerState': 'SP',
      });
      expect(const PropertyOwnerAddressValues().createApiFields(), isEmpty);
    });

    test('texto legado montado como no web; sem partes mantém o antigo', () {
      expect(
        parts.composeLegacy(''),
        'Av. Paulista, nº 1000, Apto 42, Bela Vista, São Paulo, SP, 01310-100',
      );
      expect(
        const PropertyOwnerAddressValues().composeLegacy('Rua Velha, 1'),
        'Rua Velha, 1',
      );
    });

    test('edição: só o que mudou; apagado vai null', () {
      const next = PropertyOwnerAddressValues(
        zipCode: '01310-100',
        street: 'Av. Paulista',
        number: '2000',
        neighborhood: 'Bela Vista',
        city: 'São Paulo',
        state: 'SP',
      );
      expect(next.editApiFields(parts), {
        'ownerNumber': '2000',
        'ownerComplement': null,
      });
      expect(parts.editApiFields(parts), isEmpty);
    });

    test('lê do bloco owner e, na falta, da raiz do imóvel', () {
      final p = _property({
        'owner': {
          'name': 'Ana',
          'address': 'legado',
          'zipCode': '30140071',
          'street': 'Rua A',
        },
        'ownerCity': 'Belo Horizonte',
      });
      final v = PropertyOwnerAddressValues.fromOwner(p.owner);
      expect(v.zipCode, '30140-071');
      expect(v.street, 'Rua A');
      expect(v.city, 'Belo Horizonte');
    });

    test('detalhe: partes formatadas; sem partes, o texto legado', () {
      final p = _property({
        'owner': {
          'zipCode': '30140071',
          'street': 'Rua A',
          'number': '10',
          'neighborhood': 'Centro',
          'city': 'Belo Horizonte',
          'state': 'mg',
        },
      });
      expect(
        ownerAddressDisplay(p.owner),
        'Rua A, nº 10\nCentro — Belo Horizonte/MG\nCEP 30140-071',
      );
      final legado = _property({
        'owner': {'address': 'Rua Velha, 1'},
      });
      expect(ownerAddressDisplay(legado.owner), 'Rua Velha, 1');
      expect(ownerAddressDisplay(null), '');
    });

    test('rascunho local guarda e restaura', () {
      final back = PropertyOwnerAddressValues.fromDraft(parts.toDraft())!;
      expect(back.editApiFields(parts), isEmpty);
    });
  });

  group('Título de fallback quando a IA falha (web propertyFallbackTitle)', () {
    test('sem tipo e sem cidade não monta nada', () {
      expect(buildFallbackPropertyTitle(), '');
    });

    test('tipo + gancho + localização', () {
      expect(
        buildFallbackPropertyTitle(
          type: 'apartment',
          city: 'Betim',
          neighborhood: 'Centro',
          bedrooms: 3,
        ),
        'Apartamento · 3 qts · Centro, Betim',
      );
      expect(
        buildFallbackPropertyTitle(
          type: 'house',
          city: 'Betim',
          features: const ['Piscina'],
        ),
        'Casa · Piscina · Betim',
      );
    });

    test('terreno usa a metragem; condomínio vem na frente', () {
      expect(
        buildFallbackPropertyTitle(
          type: 'land',
          city: 'Contagem',
          totalArea: 360,
          condominiumName: 'Vila Real - Condomínio Residencial',
        ),
        'Vila Real · Terreno · 360 m² · Contagem',
      );
    });

    test('comercial não usa quartos; vagas como gancho', () {
      expect(
        buildFallbackPropertyTitle(
          type: 'commercial',
          city: 'BH',
          bedrooms: 4,
          parkingSpaces: 1,
        ),
        'Imóvel Comercial · 1 vaga · BH',
      );
    });

    test('corta em 100 preferindo o separador', () {
      final t = buildFallbackPropertyTitle(
        type: 'house',
        city: 'C' * 60,
        neighborhood: 'B' * 60,
      );
      expect(t.length, lessThanOrEqualTo(100));
    });
  });
}
