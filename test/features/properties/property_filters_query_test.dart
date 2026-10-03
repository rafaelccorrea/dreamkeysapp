import 'package:Intellisys/shared/services/property_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Filtros da listagem', () {
    test('"Apenas inativos" vai como portfolioScope=inactive, sem isActive', () {
      final f = PropertyFilters(portfolioScope: PortfolioScope.inactive);
      final q = f.toQueryParams();
      expect(q['portfolioScope'], 'inactive');
      expect(q.containsKey('isActive'), isFalse);
    });

    test('todas as abas do back têm valor', () {
      expect(
        PortfolioScope.values.map((s) => s.value),
        [
          'available',
          'pending',
          'rejected',
          'sold',
          'rented',
          'negotiation',
          'others',
          'inactive',
        ],
      );
      expect(PortfolioScope.fromValue(' Rented '), PortfolioScope.rented);
      expect(PortfolioScope.fromValue('xpto'), isNull);
    });

    test('ordenação, finalidade e código vão na query', () {
      final q = PropertyFilters(
        sortBy: 'salePrice',
        sortOrder: 'ASC',
        finalidade: 'locacao',
        code: ' AP-1 ',
      ).toQueryParams();
      expect(q['sortBy'], 'salePrice');
      expect(q['sortOrder'], 'ASC');
      expect(q['finalidade'], 'locacao');
      expect(q['code'], 'AP-1');
    });

    test('drawer limpa de verdade e preserva busca/aba', () {
      final base = PropertyFilters(
        type: PropertyType.house,
        minPrice: 10,
        search: 'centro',
        portfolioScope: PortfolioScope.rented,
        onlyMyData: true,
      );
      final next = base.withAdvancedFilters(finalidade: 'venda');
      expect(next.type, isNull);
      expect(next.minPrice, isNull);
      expect(next.finalidade, 'venda');
      expect(next.search, 'centro');
      expect(next.portfolioScope, PortfolioScope.rented);
      expect(next.onlyMyData, isTrue);
    });

    test('corpo da exportação usa a whitelist do back', () {
      final f = PropertyFilters(
        type: PropertyType.apartment,
        city: ' Goiânia ',
        state: '',
        minPrice: 100000,
        condominiumId: 'c1', // fora da whitelist de exportação
        isActive: false, // o back não lê
        portfolioScope: PortfolioScope.negotiation,
        search: 'jardim',
      );
      expect(f.toExportFilters(), {
        'type': 'apartment',
        'portfolioScope': 'negotiation',
        'city': 'Goiânia',
        'minPrice': 100000.0,
        'search': 'jardim',
      });
    });
  });

  group('Filtros estendidos (paridade web)', () {
    PropertyFilters full() => PropertyFilters(
          zipCode: ' 74000-000 ',
          sector: 'Setor Sul',
          ownerName: 'Maria',
          ownerPhone: '62999',
          number: '120',
          propertyUnity: '302',
          tower: 'B',
          block: '12',
          lot: '7',
          createdFrom: '2026-01-01',
          createdTo: '2026-01-31',
          teamId: 't1',
          captorsTeamId: 't2',
          responsibleUserId: 'u1',
          responsibleWithoutCaptor: true,
          minSalePrice: 100000,
          maxSalePrice: 500000,
          minRentPrice: 1000,
          maxRentPrice: 5000,
          suites: 2,
          rooms: 3,
        );

    test('todos vão na query com os nomes do web', () {
      final q = full().toQueryParams();
      expect(q, containsPair('zipCode', '74000-000'));
      expect(q, containsPair('sector', 'Setor Sul'));
      expect(q, containsPair('ownerName', 'Maria'));
      expect(q, containsPair('ownerPhone', '62999'));
      expect(q, containsPair('number', '120'));
      expect(q, containsPair('propertyUnity', '302'));
      expect(q, containsPair('tower', 'B'));
      expect(q, containsPair('block', '12'));
      expect(q, containsPair('lot', '7'));
      expect(q, containsPair('createdFrom', '2026-01-01'));
      expect(q, containsPair('createdTo', '2026-01-31'));
      expect(q, containsPair('teamId', 't1'));
      expect(q, containsPair('captorsTeamId', 't2'));
      expect(q, containsPair('responsibleUserId', 'u1'));
      expect(q, containsPair('responsibleWithoutCaptor', true));
      expect(q, containsPair('minSalePrice', 100000.0));
      expect(q, containsPair('maxSalePrice', 500000.0));
      expect(q, containsPair('minRentPrice', 1000.0));
      expect(q, containsPair('maxRentPrice', 5000.0));
      expect(q, containsPair('suites', 2));
      expect(q, containsPair('rooms', 3));
      expect(q.containsKey('listDeletedOnly'), isFalse);
    });

    test('vazios e "sem captador" desligado não vão', () {
      final q = PropertyFilters(
        ownerName: '  ',
        responsibleWithoutCaptor: false,
      ).toQueryParams();
      expect(q.containsKey('ownerName'), isFalse);
      expect(q.containsKey('responsibleWithoutCaptor'), isFalse);
      expect(PropertyFilters().hasExtendedListFilters, isFalse);
      expect(full().hasExtendedListFilters, isTrue);
    });

    test('"só excluídos" ignora aba e inativos', () {
      final q = PropertyFilters(
        listDeletedOnly: true,
        portfolioScope: PortfolioScope.rented,
        includeInactive: true,
      ).toQueryParams();
      expect(q['listDeletedOnly'], isTrue);
      expect(q.containsKey('portfolioScope'), isFalse);
      expect(q.containsKey('includeInactive'), isFalse);
      // Não é filtro do drawer (tem atalho próprio).
      expect(
        PropertyFilters(listDeletedOnly: true).hasExtendedListFilters,
        isFalse,
      );
    });

    test('exportação leva os estendidos, nunca listDeletedOnly', () {
      final body = full()
          .copyWithNullable(listDeletedOnly: true)
          .toExportFilters();
      expect(body['sector'], 'Setor Sul');
      expect(body['captorsTeamId'], 't2');
      expect(body['createdFrom'], '2026-01-01');
      expect(body['minSalePrice'], 100000.0);
      expect(body['rooms'], 3);
      expect(body.containsKey('listDeletedOnly'), isFalse);
    });

    test('copyWith e copyWithNullable preservam os estendidos', () {
      final base = full().copyWithNullable(listDeletedOnly: true);
      final a = base.copyWith(search: 'x');
      expect(a.toQueryParams()['ownerName'], 'Maria');
      expect(a.listDeletedOnly, isTrue);
      final b = base.copyWithNullable(
        portfolioScope: PortfolioScope.sold,
        resetListDeletedOnly: true,
      );
      expect(b.listDeletedOnly, isNull);
      expect(b.suites, 2);
      expect(b.toQueryParams()['portfolioScope'], 'sold');
    });

    test('drawer troca os estendidos e mantém "só excluídos"', () {
      final base = full().copyWithNullable(
        listDeletedOnly: true,
        portfolioScope: PortfolioScope.available,
      );
      final next = base.withAdvancedFilters(rooms: 1);
      expect(next.rooms, 1);
      expect(next.ownerName, isNull);
      expect(next.responsibleUserId, isNull);
      expect(next.minSalePrice, isNull);
      expect(next.listDeletedOnly, isTrue);
      expect(next.portfolioScope, PortfolioScope.available);
    });

    test('portfolio-counts usa a mesma montagem (sem a aba)', () {
      // getPortfolioCounts parte de toQueryParams() e só tira aba/ordenação.
      final q = full().toQueryParams()
        ..remove('portfolioScope')
        ..remove('sortBy')
        ..remove('sortOrder');
      expect(q['minRentPrice'], 1000.0);
      expect(q['teamId'], 't1');
    });
  });

  group('Respostas', () {
    test('portfolio-counts', () {
      final c = PropertyPortfolioCounts.fromJson({
        'total': 30,
        'available': 10,
        'rented': 4,
        'inactive': 6,
      });
      expect(c.total, 30);
      expect(c.of(PortfolioScope.rented), 4);
      expect(c.of(PortfolioScope.others), isNull);
    });

    test('nome do arquivo exportado pelo Content-Disposition', () {
      expect(
        propertyExportFileName(
          'attachment; filename="propriedades_2026-10-03.xlsx"',
        ),
        'propriedades_2026-10-03.xlsx',
      );
      expect(
        propertyExportFileName("attachment; filename*=UTF-8''im%C3%B3veis.csv"),
        'imóveis.csv',
      );
      expect(propertyExportFileName(null), isNull);
    });

    test('prévia da exportação', () {
      final p = PropertyExportPreview.fromJson(
        {'total': 12000, 'scopeLabel': 'Meus imóveis', 'limit': 10000},
      );
      expect(p.exceedsLimit, isTrue);
      expect(p.scopeLabel, 'Meus imóveis');
    });

    test('recent-deals', () {
      final page = RecentDealsResult.fromJson({
        'data': [
          {
            'id': 'a',
            'code': 'AP-1',
            'status': 'sold',
            'soldAt': '2026-09-30T12:00:00Z',
            'concludedAt': '2026-09-30T12:00:00Z',
          },
          {'id': 'b', 'status': 'rented', 'rentedAt': '2026-09-29T12:00:00Z'},
        ],
        'total': 2,
        'page': 1,
        'limit': 24,
      });
      expect(page.items, hasLength(2));
      expect(page.items.first.isSold, isTrue);
      expect(page.items.last.isSold, isFalse);
      expect(page.totalPages, 1);
    });
  });
}
