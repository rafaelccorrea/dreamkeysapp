import 'dart:convert';
import 'dart:ui';

import 'package:Intellisys/features/sale_forms/sale_forms_overview_filters.dart';
import 'package:Intellisys/features/sale_forms/widgets/sale_forms_dashboard_charts.dart';
import 'package:Intellisys/shared/services/sale_form_overview_service.dart';
import 'package:Intellisys/shared/services/sale_forms_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 3, 15, 30);

  group('período padrão e presets (D-3)', () {
    test('padrão = mês corrente inteiro, por dia, sem recortes', () {
      final f = overviewCurrentMonthDefault(now);
      expect(f.dateFrom, '2026-10-01');
      expect(f.dateTo, '2026-10-31');
      expect(f.granularity, 'day');
      expect(f.dimensionCount, 0);
      expect(resolveOverviewPresetId(f, now), 'mtd');
    });

    test('fevereiro bissexto termina no dia 29', () {
      final f = overviewCurrentMonthDefault(DateTime(2028, 2, 10));
      expect(f.dateTo, '2028-02-29');
    });

    test('presets iguais ao web (ids, rótulos e granularidade)', () {
      expect(kOverviewPresets.map((p) => '${p.id}:${p.label}'), [
        'today:Hoje',
        '7d:7 dias',
        'mtd:Mês atual',
        'last-month:Mês passado',
        'ytd:Ano',
      ]);
      String r(String id) {
        final p = kOverviewPresets.firstWhere((p) => p.id == id).compute(now);
        return '${overviewYmd(p.from)}|${overviewYmd(p.to)}|${p.granularity}';
      }

      expect(r('today'), '2026-10-03|2026-10-03|day');
      expect(r('7d'), '2026-09-27|2026-10-03|day');
      expect(r('last-month'), '2026-09-01|2026-09-30|day');
      expect(r('ytd'), '2026-01-01|2026-12-31|month');
    });

    test('mês passado em janeiro volta para dezembro do ano anterior', () {
      final p = kOverviewPresets
          .firstWhere((p) => p.id == 'last-month')
          .compute(DateTime(2027, 1, 15));
      expect(overviewYmd(p.from), '2026-12-01');
      expect(overviewYmd(p.to), '2026-12-31');
    });

    test('aplicar preset mantém corretor/equipe/unidade/status', () {
      const base = SaleFormsOverviewFilters(
        dateFrom: '2026-10-01',
        dateTo: '2026-10-31',
        userIds: ['u'],
        status: ['finalized'],
      );
      final ytd = kOverviewPresets.firstWhere((p) => p.id == 'ytd');
      final f = applyOverviewPreset(base, ytd, now);
      expect(f.dateFrom, '2026-01-01');
      expect(f.granularity, 'month');
      expect(f.userIds, ['u']);
      expect(f.status, ['finalized']);
      expect(resolveOverviewPresetId(f, now), 'ytd');
    });

    test('intervalo livre não casa com preset', () {
      const f = SaleFormsOverviewFilters(
        dateFrom: '2026-10-02',
        dateTo: '2026-10-20',
      );
      expect(resolveOverviewPresetId(f, now), isNull);
    });
  });

  group('granularidade coerente (coalesceGranularityForRange)', () {
    DateTime d(int y, int m, int dd) => DateTime(y, m, dd);
    test('dia vira semana >90 dias e mês >365', () {
      expect(
        coalesceOverviewGranularity(d(2026, 1, 1), d(2026, 3, 31), 'day'),
        'day',
      );
      expect(
        coalesceOverviewGranularity(d(2026, 1, 1), d(2026, 4, 30), 'day'),
        'week',
      );
      expect(
        coalesceOverviewGranularity(d(2025, 1, 1), d(2026, 3, 1), 'day'),
        'month',
      );
    });
    test('semana vira dia ≤7 dias; mês vira dia ≤14 e semana ≤45', () {
      expect(
        coalesceOverviewGranularity(d(2026, 1, 1), d(2026, 1, 7), 'week'),
        'day',
      );
      expect(
        coalesceOverviewGranularity(d(2026, 1, 1), d(2026, 1, 14), 'month'),
        'day',
      );
      expect(
        coalesceOverviewGranularity(d(2026, 1, 1), d(2026, 2, 14), 'month'),
        'week',
      );
      expect(
        coalesceOverviewGranularity(d(2026, 1, 1), d(2026, 3, 31), 'month'),
        'month',
      );
    });
  });

  test('rótulo do período (formatRangeLabel)', () {
    String? l(String a, String b) => formatOverviewRangeLabel(
      SaleFormsOverviewFilters(dateFrom: a, dateTo: b),
    );
    expect(l('2026-10-01', '2026-10-31'), 'Out/2026');
    expect(l('2026-10-01', '2026-10-15'), '1–15 Out/2026');
    expect(l('2026-09-27', '2026-10-03'), '27 Set – 3 Out/2026');
    expect(l('2025-12-01', '2026-01-31'), '1/Dez/2025 – 31/Jan/2026');
    expect(formatOverviewRangeLabel(const SaleFormsOverviewFilters()), isNull);
  });

  group('filtros guardados (D-4)', () {
    test('chave por empresa e usuário, prefixo igual ao web', () {
      expect(kSaleFormsOverviewStorageKey, 'dashboard:sale-forms:overview:v1');
      expect(
        saleFormsOverviewStorageKey(companyId: 'c1', userId: 'u1'),
        'dashboard:sale-forms:overview:v1:c1:u1',
      );
      expect(
        saleFormsOverviewStorageKey(companyId: 'c2', userId: 'u1'),
        isNot(saleFormsOverviewStorageKey(companyId: 'c1', userId: 'u1')),
      );
      expect(saleFormsOverviewStorageKey(), kSaleFormsOverviewStorageKey);
    });

    test('ida e volta preserva o estado', () {
      const f = SaleFormsOverviewFilters(
        dateFrom: '2026-09-01',
        dateTo: '2026-09-30',
        granularity: 'week',
        userIds: ['u1'],
        teamIds: ['t1', 't2'],
        unitIds: ['n1'],
        status: ['finalized', 'processing'],
      );
      expect(decodeOverviewFilters(encodeOverviewFilters(f), now), f);
    });

    test('JSON do web (mesmas chaves) é lido', () {
      final raw = jsonEncode({
        'granularity': 'day',
        'dateFrom': '2026-08-01',
        'dateTo': '2026-08-31',
        'userIds': ['a'],
        'teamIds': [],
        'unitIds': [],
        'status': ['waiting_for_signature'],
      });
      final f = decodeOverviewFilters(raw, now);
      expect(f.dateFrom, '2026-08-01');
      expect(f.userIds, ['a']);
      expect(f.status, ['waiting_for_signature']);
    });

    test('vazio/ilegível = mês corrente; campos ruins caem no padrão', () {
      final base = overviewCurrentMonthDefault(now);
      expect(decodeOverviewFilters(null, now), base);
      expect(decodeOverviewFilters('{oops', now), base);
      expect(decodeOverviewFilters('[]', now), base);
      final f = decodeOverviewFilters(
        jsonEncode({
          'dateFrom': 'ontem',
          'granularity': 'hora',
          'userIds': 'x',
          'status': ['canceled', 'finalized'],
        }),
        now,
      );
      expect(f.dateFrom, base.dateFrom);
      expect(f.dateTo, base.dateTo);
      expect(f.granularity, 'day');
      expect(f.userIds, isEmpty);
      expect(f.status, ['finalized']);
    });

    test('granularidade guardada é recoerida ao intervalo', () {
      final f = decodeOverviewFilters(
        jsonEncode({
          'dateFrom': '2026-10-01',
          'dateTo': '2026-10-05',
          'granularity': 'month',
        }),
        now,
      );
      expect(f.granularity, 'day');
    });

    test('store grava e lê no SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      const f = SaleFormsOverviewFilters(
        dateFrom: '2026-07-01',
        dateTo: '2026-07-31',
        teamIds: ['t9'],
      );
      await SaleFormsOverviewFiltersStore.instance.save(f);
      final back = await SaleFormsOverviewFiltersStore.instance.read(now: now);
      expect(back, f);
    });

    test('store sem nada guardado devolve o mês corrente', () async {
      SharedPreferences.setMockInitialValues({});
      final back = await SaleFormsOverviewFiltersStore.instance.read(now: now);
      expect(back, overviewCurrentMonthDefault(now));
    });
  });

  group('escopo (resolveEffectiveScopeUi + prune)', () {
    SaleFormsOverviewScopeUi ui(String tier) => SaleFormsOverviewScopeUi(
      showUserFilter: true,
      showTeamFilter: true,
      showUnitFilter: true,
      showBrokerRanking: true,
      showTeamRanking: true,
      showUnitSection: true,
      scopeTier: tier,
    );

    test('all: some o que tem ≤1 opção', () {
      final s = resolveOverviewEffectiveScope(
        ui('all'),
        users: 5,
        teams: 1,
        units: 1,
      );
      expect(s.showUserFilter, isTrue);
      expect(s.showTeamFilter, isFalse);
      expect(s.showTeamRanking, isFalse);
      expect(s.showUnitFilter, isFalse);
      expect(s.showUnitSection, isTrue);
    });

    test('team: sem filtro/seção de unidade; self: tudo oculto', () {
      final t = resolveOverviewEffectiveScope(
        ui('team'),
        users: 3,
        teams: 2,
        units: 4,
      );
      expect(t.showUnitFilter, isFalse);
      expect(t.showUnitSection, isFalse);
      expect(t.showBrokerRanking, isTrue);
      final s = resolveOverviewEffectiveScope(
        ui('self'),
        users: 3,
        teams: 2,
        units: 4,
      );
      expect([
        s.showUserFilter,
        s.showTeamFilter,
        s.showUnitFilter,
        s.showBrokerRanking,
        s.showTeamRanking,
        s.showUnitSection,
      ], everyElement(isFalse));
    });

    test('prune remove ids fora das opções e filtros ocultos', () {
      const f = SaleFormsOverviewFilters(
        userIds: ['u1', 'sumiu'],
        teamIds: ['t1'],
        unitIds: ['n1'],
        status: ['finalized'],
      );
      final out = pruneOverviewFiltersToScope(
        f,
        users: const [SaleFormsOverviewPickOption(id: 'u1', label: 'U')],
        teams: const [SaleFormsOverviewPickOption(id: 't1', label: 'T')],
        units: const [SaleFormsOverviewPickOption(id: 'n1', label: 'N')],
        scope: ui('all').copyWith(showTeamFilter: false),
      );
      expect(out.userIds, ['u1']);
      expect(out.teamIds, isEmpty);
      expect(out.unitIds, ['n1']);
      expect(out.status, ['finalized']);
    });
  });

  test('rótulos de métrica conforme o status (resolvePanelMetricLabels)', () {
    expect(
      resolveOverviewMetricLabels([]).vgvTitle,
      'VGV finalizado no período',
    );
    final one = resolveOverviewMetricLabels(['processing']);
    expect(one.vgvTitle, 'VGV — Em processamento');
    expect(one.showConversion, isFalse);
    expect(one.valuesScoped, isTrue);
    final many = resolveOverviewMetricLabels(['finalized', 'processing']);
    expect(many.vgvTitle, 'VGV no recorte filtrado');
    expect(many.showConversion, isTrue);
  });

  group('drill-down (FichasListDrawer)', () {
    const snap = SaleFormsOverviewFilters(
      dateFrom: '2026-10-01',
      dateTo: '2026-10-31',
      userIds: ['u1'],
      teamIds: ['t1'],
      unitIds: ['n1'],
      status: ['finalized', 'processing'],
    );

    test('KPI total herda o painel inteiro', () {
      final q = buildOverviewDrillFilters(snap).toQuery();
      expect(q['dateFrom'], '2026-10-01');
      expect(q['dateTo'], '2026-10-31');
      expect(q['userIds'], 'u1');
      expect(q['teamIds'], 't1');
      expect(q['unitIds'], 'n1');
      expect(q['statuses'], 'processing,finalized');
      expect(q['page'], '1');
      expect(q['limit'], '20');
      expect(q['sortBy'], 'createdAt');
      expect(q['sortOrder'], 'DESC');
      expect(q.containsKey('sharedOnly'), isFalse);
      expect(q.containsKey('listDeletedOnly'), isFalse);
    });

    test('linha do ranking troca só a dimensão clicada', () {
      final q = buildOverviewDrillFilters(
        snap,
        const OverviewDrillDimension(userIds: ['u9']),
      ).toQuery();
      expect(q['userIds'], 'u9');
      expect(q['teamIds'], 't1');
      expect(q['statuses'], 'processing,finalized');
    });

    test('unidade (fatia do donut/ranking) e compartilhadas', () {
      final u = buildOverviewDrillFilters(
        snap,
        const OverviewDrillDimension(unitIds: ['n7']),
      ).toQuery();
      expect(u['unitIds'], 'n7');
      final s = buildOverviewDrillFilters(
        snap,
        const OverviewDrillDimension(sharedOnly: true),
      ).toQuery();
      expect(s['sharedOnly'], 'true');
      expect(s['unitIds'], 'n1');
    });

    test('fatia de status substitui os status do painel', () {
      final q = buildOverviewDrillFilters(
        snap,
        overviewStatusDrill(SaleFormStatus.finalized, canViewAll: false),
      ).toQuery();
      expect(q['statuses'], 'finalized');
      expect(q['status'], 'finalized');
    });

    test('canceladas: view_all lista excluídas; sem view_all, status', () {
      final all = buildOverviewDrillFilters(
        snap,
        overviewStatusDrill(SaleFormStatus.canceled, canViewAll: true),
      ).toQuery();
      expect(all['listDeletedOnly'], 'true');
      expect(all.containsKey('statuses'), isFalse);
      final own = buildOverviewDrillFilters(
        snap,
        overviewStatusDrill(SaleFormStatus.canceled, canViewAll: false),
      ).toQuery();
      expect(own['statuses'], 'canceled');
      expect(own.containsKey('listDeletedOnly'), isFalse);
    });

    test('painel sem recortes não manda listas', () {
      final q = buildOverviewDrillFilters(
        const SaleFormsOverviewFilters(
          dateFrom: '2026-10-01',
          dateTo: '2026-10-31',
        ),
      ).toQuery();
      expect(
        q.keys,
        unorderedEquals([
          'page',
          'limit',
          'sortBy',
          'sortOrder',
          'dateFrom',
          'dateTo',
        ]),
      );
    });

    test('chave de status desconhecida não vira status', () {
      expect(overviewStatusFromKey('finalized'), SaleFormStatus.finalized);
      expect(overviewStatusFromKey('outro'), isNull);
    });
  });

  group('donut: toque na fatia', () {
    const size = Size(200, 200);
    test('topo = 1ª fatia, sentido horário', () {
      final values = [1.0, 1.0, 2.0];
      // Direita do centro (90°) cai na 1ª (0°–90°).
      expect(overviewDonutHitIndex(const Offset(190, 99), size, values), 0);
      // Embaixo (180°) cai na 2ª (90°–180°).
      expect(overviewDonutHitIndex(const Offset(101, 190), size, values), 1);
      // Esquerda (270°) cai na 3ª (180°–360°).
      expect(overviewDonutHitIndex(const Offset(10, 100), size, values), 2);
    });
    test('fora do anel ou sem valores = null', () {
      expect(
        overviewDonutHitIndex(const Offset(100, 100), size, [1.0]),
        isNull,
      );
      expect(
        overviewDonutHitIndex(const Offset(190, 100), size, [0.0]),
        isNull,
      );
    });
  });
}
