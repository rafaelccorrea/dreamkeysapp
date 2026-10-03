import 'package:Intellisys/features/properties/services/property_map_service.dart';
import 'package:Intellisys/shared/services/property_service.dart';
import 'package:flutter_test/flutter_test.dart';

PropertyMapMarker _m(
  String id, {
  double lat = -16.68,
  double lng = -49.25,
  String type = 'house',
  String status = 'available',
  String? city,
  double? price,
  double? sale,
  double? rent,
  double? area,
}) =>
    PropertyMapMarker(
      id: id,
      lat: lat,
      lng: lng,
      title: 'Imóvel $id',
      type: type,
      status: status,
      city: city,
      price: price ?? sale ?? rent,
      salePrice: sale,
      rentPrice: rent,
      area: area,
    );

void main() {
  group('buildPropertyMapQuery', () {
    test('mantém só as chaves lidas pelo /properties/map e anexa bounds', () {
      final q = buildPropertyMapQuery(
        PropertyFilters(
          type: PropertyType.apartment,
          minPrice: 500000,
          maxPrice: 1250000.5,
          bedrooms: 2,
          features: const ['piscina'],
          isActive: true,
          sortBy: 'createdAt',
          sortOrder: 'DESC',
          onlyMyData: true,
          portfolioScope: PortfolioScope.available,
          search: '  setor bueno ',
        ),
        bounds: const PropertyMapBounds(
          north: -16.6,
          south: -16.8,
          east: -49.2,
          west: -49.3,
        ),
      );
      expect(q['type'], 'apartment');
      expect(q['minPrice'], '500000');
      expect(q['maxPrice'], '1250000.5');
      expect(q['bedrooms'], '2');
      expect(q['onlyMyData'], 'true');
      expect(q['portfolioScope'], 'available');
      expect(q['search'], 'setor bueno');
      expect(q.containsKey('features'), isFalse);
      expect(q.containsKey('isActive'), isFalse);
      expect(q.containsKey('sortBy'), isFalse);
      expect(q.containsKey('sortOrder'), isFalse);
      expect(q['n'], '-16.6');
      expect(q['s'], '-16.8');
      expect(q['e'], '-49.2');
      expect(q['w'], '-49.3');
    });

    test('sem filtros nem bounds = query vazia', () {
      expect(buildPropertyMapQuery(null), isEmpty);
    });
  });

  group('PropertyMapResult.fromJson', () {
    test('lê marcadores, ignora inválidos e aceita envelope', () {
      final r = PropertyMapResult.fromJson({
        'success': true,
        'data': {
          'markers': [
            {
              'id': 'a',
              'lat': '-16.7',
              'lng': -49.26,
              'title': 'Casa',
              'type': 'house',
              'status': 'available',
              'salePrice': '450000',
              'rentPrice': null,
              'bedrooms': 3,
              'area': '120.5',
            },
            {'id': 'sem-coord', 'lat': null, 'lng': 1},
            {'lat': 1, 'lng': 1},
            {'id': 'fora', 'lat': 120, 'lng': 1},
          ],
          'total': 300,
          'truncated': true,
        },
      });
      expect(r.markers, hasLength(1));
      final m = r.markers.single;
      expect(m.lat, -16.7);
      expect(m.salePrice, 450000);
      expect(m.area, 120.5);
      expect(m.bedrooms, 3);
      expect(r.total, 300);
      expect(r.truncated, isTrue);
    });
  });

  group('agrupamento', () {
    test('faixas de valor em ordem crescente + "Sem preço" no fim', () {
      final g = buildPropertyMapGroups([
        _m('1', sale: 3000000),
        _m('2', sale: 200000),
        _m('3'),
        _m('4', sale: 240000),
      ], PropertyMapGroupBy.price);
      expect(g.groups.map((e) => e.key), ['tier-0', 'tier-4', 'no-price']);
      expect(g.groups.first.markers.map((m) => m.id), ['2', '4']);
      expect(g.colorByMarkerId['3'], kMapNeutralColor);
    });

    test('cidade: maior grupo primeiro e cor estável por nome', () {
      final g = buildPropertyMapGroups([
        _m('1', city: 'Goiânia'),
        _m('2', city: 'Anápolis'),
        _m('3', city: 'goiânia '),
        _m('4'),
      ], PropertyMapGroupBy.city);
      expect(g.groups.first.label, 'Goiânia');
      expect(g.groups.first.markers, hasLength(2));
      expect(g.groups.last.label, isNot('Goiânia'));
      expect(
        g.groups.firstWhere((x) => x.label == 'Sem cidade').color,
        kMapNeutralColor,
      );
      expect(g.colorByMarkerId['1'], mapColorFromPalette('goiânia'));
    });

    test('operação: venda, aluguel, ambos e sem preço', () {
      expect(markerOperation(_m('a', sale: 1, rent: 1)), PropertyMapOperation.both);
      expect(markerOperation(_m('b', rent: 10)), PropertyMapOperation.rent);
      expect(markerOperation(_m('c', sale: 10)), PropertyMapOperation.sale);
      expect(markerOperation(_m('d')), PropertyMapOperation.none);
    });

    test('hash igual ao do web (inteiro de 32 bits)', () {
      // Valores calculados com a função do web (propertyMapGrouping.ts).
      expect(mapHashString('a'), 97);
      expect(mapHashString('goiânia'), mapHashString('goiânia'));
      expect(mapHashString('uma cidade com nome bem comprido'), greaterThan(0));
    });
  });

  test('ordenação por preço manda "sem preço" para o fim no crescente', () {
    final list = [_m('x'), _m('caro', sale: 900), _m('barato', rent: 10)];
    expect(
      sortPropertyMapMarkers(list, PropertyMapSort.priceAsc).map((m) => m.id),
      ['barato', 'caro', 'x'],
    );
    expect(
      sortPropertyMapMarkers(list, PropertyMapSort.priceDesc).map((m) => m.id),
      ['caro', 'barato', 'x'],
    );
    expect(
      sortPropertyMapMarkers(list, PropertyMapSort.relevance).map((m) => m.id),
      ['x', 'caro', 'barato'],
    );
  });

  test('médias da área visível', () {
    final stats = computePropertyMapAreaStats([
      _m('1', sale: 300000, area: 100),
      _m('2', sale: 500000, area: 0),
      _m('3', rent: 2000),
      _m('fora', lat: 10, lng: 10, sale: 9999999),
    ], const PropertyMapBounds(north: 0, south: -30, east: -40, west: -60));
    expect(stats.count, 3);
    expect(stats.avgSale, 400000);
    expect(stats.avgRent, 2000);
    expect(stats.avgPricePerSqm, 3000);
  });

  test('pílula de preço compacta', () {
    expect(compactMapPrice(null), 'Consulte');
    expect(compactMapPrice(450000), r'R$ 450 mil');
    expect(compactMapPrice(1250000), r'R$ 1,3 mi');
    expect(compactMapPrice(12000000), r'R$ 12 mi');
    expect(mapPillPriceLabel(_m('r', rent: 2500)), r'R$ 3 mil/mês');
  });

  group('clusterização', () {
    test('pontos próximos juntam no zoom baixo e separam no zoom alto', () {
      final ms = [
        _m('a', lat: -16.680, lng: -49.250),
        _m('b', lat: -16.681, lng: -49.251),
        _m('c', lat: -15.800, lng: -47.900),
      ];
      final low = clusterPropertyMapMarkers(ms, 10);
      expect(low, hasLength(2));
      expect(low.first.markers.map((m) => m.id), ['a', 'b']);
      final high = clusterPropertyMapMarkers(ms, 18);
      expect(high, hasLength(3));
      expect(high.every((c) => c.isSingle), isTrue);
    });
  });

  test('região mais densa ignora pontos isolados', () {
    final ms = [
      _m('1', lat: -16.68, lng: -49.26),
      _m('2', lat: -16.69, lng: -49.27),
      _m('3', lat: -16.70, lng: -49.28),
      _m('longe', lat: -23.55, lng: -46.63),
    ];
    expect(pickDensestMapRegion(ms).map((m) => m.id), ['1', '2', '3']);
    expect(pickDensestMapRegion(ms.take(2).toList()), hasLength(2));
  });

  group('filtros', () {
    test('chips e remoção de um filtro', () {
      final f = PropertyFilters(
        type: PropertyType.house,
        city: 'Goiânia',
        minPrice: 300000,
        bedrooms: 3,
        finalidade: 'locacao',
        code: '123',
      );
      final chips = buildPropertyMapFilterChips(f);
      expect(chips.map((c) => c.key),
          ['type', 'city', 'minPrice', 'bedrooms', 'finalidade', 'code']);
      expect(chips.firstWhere((c) => c.key == 'minPrice').label,
          r'Mín R$ 300.000');
      final without = propertyFiltersWithout(f, 'city');
      expect(without.city, isNull);
      expect(without.type, PropertyType.house);
      expect(without.code, '123');
    });

    test('remover um filtro preserva os filtros estendidos do drawer', () {
      final f = PropertyFilters(
        city: 'Goiânia',
        sector: 'Sul',
        teamId: 't1',
        suites: 2,
        minSalePrice: 100,
        listDeletedOnly: true,
      );
      final w = propertyFiltersWithout(f, 'city');
      expect(w.city, isNull);
      expect(w.sector, 'Sul');
      expect(w.teamId, 't1');
      expect(w.suites, 2);
      expect(w.minSalePrice, 100);
      expect(w.listDeletedOnly, isTrue);
      final chips = buildPropertyMapFilterChips(f).map((c) => c.key);
      expect(chips, containsAll(['sector', 'teamId', 'listDeletedOnly']));
    });

    test('o /properties/map recebe os mesmos filtros da listagem', () {
      final f = PropertyFilters(
        city: 'Goiânia',
        sector: 'Sul',
        suites: 2,
        zipCode: '74000-000',
        minRentPrice: 1000,
        sortBy: 'price',
        isActive: true,
      );
      expect(propertyMapIgnoredFilterKeys(f), isEmpty);
      expect(propertyMapIgnoredFilterKeys(null), isEmpty);
      final q = buildPropertyMapQuery(f);
      expect(q['suites'], '2');
      expect(q['zipCode'], '74000-000');
      expect(q['minRentPrice'], isNotNull);
      expect(q.containsKey('sortBy'), isFalse);
    });

    test('compose aplica aba, busca e "só meus" sobre a base', () {
      final f = composePropertyMapFilters(
        base: PropertyFilters(
          city: 'Goiânia',
          portfolioScope: PortfolioScope.sold,
          search: 'antigo',
          onlyMyData: true,
          sortBy: 'price',
        ),
        scope: PortfolioScope.available,
        search: ' bueno ',
      );
      expect(f.city, 'Goiânia');
      expect(f.portfolioScope, PortfolioScope.available);
      expect(f.search, 'bueno');
      expect(f.onlyMyData, isNull);
      expect(f.sortBy, isNull);
    });
  });
}
