import 'package:Intellisys/shared/services/sale_form_overview_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SaleFormsOverviewFilters.toQuery (buildParams do web)', () {
    test('manda período, granularidade, ids/status em CSV e limit 10', () {
      const f = SaleFormsOverviewFilters(
        dateFrom: '2026-10-01',
        dateTo: '2026-10-31',
        granularity: 'day',
        userIds: ['u1', 'u2'],
        teamIds: ['t1'],
        unitIds: ['n1', 'n2'],
        status: ['finalized', 'processing'],
      );
      expect(f.toQuery(), {
        'dateFrom': '2026-10-01',
        'dateTo': '2026-10-31',
        'granularity': 'day',
        'userIds': 'u1,u2',
        'teamIds': 't1',
        'unitIds': 'n1,n2',
        'status': 'finalized,processing',
        'limit': '10',
      });
    });

    test('listas vazias não vão; limit pode ser omitido', () {
      const f = SaleFormsOverviewFilters(
        dateFrom: '2026-10-01',
        dateTo: '2026-10-31',
      );
      final q = f.toQuery(limit: null);
      expect(q.keys, unorderedEquals(['dateFrom', 'dateTo', 'granularity']));
    });

    test('dimensionCount conta cada recorte uma vez', () {
      const f = SaleFormsOverviewFilters(
        userIds: ['a', 'b'],
        status: ['finalized'],
      );
      expect(f.dimensionCount, 2);
      expect(const SaleFormsOverviewFilters().dimensionCount, 0);
    });
  });

  group('igualdade (panelFiltersEqual)', () {
    test('listas comparadas sem ordem', () {
      const a = SaleFormsOverviewFilters(
        dateFrom: '2026-10-01',
        dateTo: '2026-10-31',
        userIds: ['x', 'y'],
        status: ['processing', 'finalized'],
      );
      const b = SaleFormsOverviewFilters(
        dateFrom: '2026-10-01',
        dateTo: '2026-10-31',
        userIds: ['y', 'x'],
        status: ['finalized', 'processing'],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == b.copyWith(granularity: 'week'), isFalse);
      expect(a == b.copyWith(unitIds: ['u']), isFalse);
    });
  });

  test('parseOverviewPickOptions lê {id,name,avatar} e descarta sem id', () {
    final out = parseOverviewPickOptions([
      {'id': 'a', 'name': ' Ana ', 'avatar': 'http://x'},
      {'id': '', 'name': 'Sem id'},
      {'id': 'b', 'name': 'Bruno', 'color': '#fff'},
      'lixo',
    ]);
    expect(out.map((o) => o.id), ['a', 'b']);
    expect(out.first.label, 'Ana');
    expect(out.first.avatar, 'http://x');
    expect(parseOverviewPickOptions(null), isEmpty);
  });

  test('scope-ui: fromJson e copyWith preservam o tier', () {
    final ui = SaleFormsOverviewScopeUi.fromJson({
      'showUserFilter': true,
      'showTeamFilter': 'true',
      'showUnitFilter': false,
      'showBrokerRanking': true,
      'showTeamRanking': true,
      'showUnitSection': true,
      'scopeTier': 'unit',
    });
    expect(ui.showTeamFilter, isTrue);
    expect(ui.showUnitFilter, isFalse);
    final c = ui.copyWith(showUnitSection: false);
    expect(c.showUnitSection, isFalse);
    expect(c.scopeTier, 'unit');
    expect(c.showUserFilter, isTrue);
  });
}
