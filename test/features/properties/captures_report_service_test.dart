import 'dart:convert';

import 'package:Intellisys/features/clients/utils/client_spreadsheet.dart';
import 'package:Intellisys/features/properties/services/captures_report_service.dart';
import 'package:Intellisys/shared/services/property_service.dart';
import 'package:flutter_test/flutter_test.dart';

CapturesReportProperty _p(
  String id, {
  String? teamId,
  String? capturedById,
  String? captorName,
  List<CapturesReportPerson> captors = const [],
  String? code,
  String title = 'Casa',
}) =>
    CapturesReportProperty(
      id: id,
      code: code,
      title: title,
      status: 'available',
      type: 'house',
      teamId: teamId,
      capturedById: capturedById,
      capturedBy: captorName == null
          ? null
          : CapturesReportPerson(id: capturedById ?? 'x', name: captorName),
      captors: captors,
    );

const _ctx = CapturesTeamContext(
  {'t1', 't2'},
  {'t1': 'União Centro', 't2': 'União Sul'},
);

void main() {
  group('CapturesReportQuery', () {
    test('período em AAAA-MM-DD e listas separadas por vírgula', () {
      final q = CapturesReportQuery(
        allDates: false,
        createdFrom: DateTime(2026, 9, 1),
        createdTo: DateTime(2026, 9, 30),
        propertyTeamIds: const ['t1', ' ', 't2', 't1'],
        capturerIds: const ['u1'],
        includeInactive: true,
      );
      expect(q.toQueryParameters(), {
        'createdFrom': '2026-09-01',
        'createdTo': '2026-09-30',
        'propertyTeamIds': 't1,t2',
        'capturerIds': 'u1',
        'includeInactive': 'true',
      });
      expect(q.hasOptionalFilters, isTrue);
    });

    test('todo o cadastro ignora as datas', () {
      final q = CapturesReportQuery(
        allDates: true,
        createdFrom: DateTime(2026, 9, 1),
        createdTo: DateTime(2026, 9, 30),
      );
      expect(q.toQueryParameters(), {'allDates': 'true'});
    });

    test('cacheKey ignora a ordem das seleções', () {
      final a = CapturesReportQuery(
        allDates: false,
        createdFrom: DateTime(2026, 1, 1),
        createdTo: DateTime(2026, 1, 31),
        capturerIds: const ['b', 'a'],
      );
      final b = CapturesReportQuery(
        allDates: false,
        createdFrom: DateTime(2026, 1, 1),
        createdTo: DateTime(2026, 1, 31),
        capturerIds: const ['a', 'b'],
      );
      expect(a.cacheKey, b.cacheKey);
    });
  });

  test('período: validação e rótulo', () {
    expect(isValidCapturesRange(DateTime(2026, 2, 1), DateTime(2026, 1, 1)),
        isFalse);
    expect(isValidCapturesRange(DateTime(2026, 1, 1, 15), DateTime(2026, 1, 1)),
        isTrue);
    expect(
      capturesPeriodLabel(
        allDates: false,
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 30),
      ),
      '01/09/2026 – 30/09/2026',
    );
    expect(capturesStartOfMonth(DateTime(2026, 10, 3, 9)), DateTime(2026, 10));
  });

  test('CapturesReportResult.fromJson lê o envelope do back', () {
    final r = CapturesReportResult.fromJson({
      'total': 2,
      'properties': [
        {
          'id': 'p1',
          'code': '31020',
          'title': 'Apto',
          'status': 'available',
          'type': 'apartment',
          'team': {'id': 't1', 'name': 'União Centro'},
          'capturedById': 'u1',
          'capturedBy': {'id': 'u1', 'name': 'Ana', 'phone': '62999'},
          'captors': [
            {'id': 'u1', 'name': 'Ana'},
            {'id': 'u2', 'name': 'Bia'},
          ],
          'responsibles': [
            {'id': 'u3', 'name': 'Caio'},
          ],
          'salePrice': '450000.00',
          'bedrooms': '3',
          'owner': {'name': 'Dono', 'email': 'd@x.com', 'phone': '1'},
          'createdAt': '2026-09-10T12:00:00.000Z',
        },
        {'title': 'sem id'},
      ],
      'statistics': {
        'totalProperties': 2,
        'byCapturer': [
          {
            'capturerId': 'u1',
            'capturerName': 'Ana',
            'capturerEmail': 'a@x.com',
            'propertiesCount': 2,
          },
        ],
        'conversionRate': {'propertiesSold': 1, 'propertiesSoldRate': 50},
      },
    });
    expect(r.properties, hasLength(1));
    final p = r.properties.single;
    expect(p.teamId, 't1');
    expect(p.salePrice, 450000);
    expect(p.bedrooms, 3);
    expect(p.primaryCaptor?.name, 'Ana');
    expect(p.responsibleName, 'Caio');
    expect(p.ownerEmail, 'd@x.com');
    expect(p.createdAt, isNotNull);
    expect(r.statistics.byCapturer.single.propertiesCount, 2);
    expect(r.statistics.propertiesSoldRate, 50);
  });

  group('equipes', () {
    test('rótulo da tabela distingue sem equipe e fora do cadastro', () {
      expect(capturesTableTeamLabel(_p('a'), _ctx), kNoTeamLabel);
      expect(capturesTableTeamLabel(_p('a', teamId: 'tx'), _ctx),
          kOutsideTeamLabel);
      expect(capturesTableTeamLabel(_p('a', teamId: 't2'), _ctx), 'União Sul');
      expect(capturesExportTeamLabel(_p('a', teamId: 'tx'), _ctx), '');
    });

    test('ranking por equipe do imóvel e filtro só das configuradas', () {
      final ranking = buildTeamRanking([
        _p('1', teamId: 't1'),
        _p('2', teamId: 't2'),
        _p('3', teamId: 't2'),
        _p('4'),
        _p('5', teamId: 'tx'),
      ], _ctx);
      expect(ranking.first.name, 'União Sul');
      expect(ranking.first.count, 2);
      expect(ranking.map((r) => r.id),
          containsAll([kNoReportTeamKey, kOutsideConfiguredTeamKey]));
      expect(onlyConfiguredTeams(ranking, _ctx).map((r) => r.id), ['t2', 't1']);
    });

    test('equipes duplicadas viram uma opção e expandem todos os ids', () {
      const teams = [
        PropertyFormTeamOption(id: 'a1', name: 'União Esmeraldas', color: ''),
        PropertyFormTeamOption(id: 'a2', name: 'união esmeraldas', color: ''),
        PropertyFormTeamOption(id: 'b1', name: 'Alfa', color: ''),
      ];
      final opts = buildCapturesTeamOptions(teams);
      expect(opts.map((o) => o.name), ['Alfa', 'União Esmeraldas']);
      expect(
        expandCapturesTeamIds(['a1', 'zz'], opts)..sort(),
        ['a1', 'a2', 'zz'],
      );
    });
  });

  test('ranking de captadores usa o captador principal', () {
    final ranking = buildCapturerRanking([
      _p('1', capturedById: 'u1', captorName: 'Ana'),
      _p('2', capturedById: 'u2', captorName: 'Bia'),
      _p('3', capturedById: 'u2', captorName: 'Bia'),
      _p('4', captors: const [CapturesReportPerson(id: 'u3', name: 'Caio')]),
      _p('5'),
    ]);
    expect(ranking.map((r) => (r.name, r.count)),
        [('Bia', 2), ('Ana', 1), ('Caio', 1)]);
  });

  test('busca local por código, captador e equipe', () {
    final list = [
      _p('1', code: '31020', teamId: 't1'),
      _p('2', code: '400', capturedById: 'u9', captorName: 'Zé Captador'),
    ];
    expect(filterCapturesProperties(list, '3102', _ctx).single.id, '1');
    expect(filterCapturesProperties(list, 'captador', _ctx).single.id, '2');
    expect(filterCapturesProperties(list, 'centro', _ctx).single.id, '1');
    expect(filterCapturesProperties(list, '  ', _ctx), hasLength(2));
  });

  test('resumo de downloads por usuário', () {
    final items = [
      ImageDownloadItem(
        id: '1',
        propertyId: 'p',
        propertyTitle: 'A',
        isZip: true,
        count: 10,
        userId: 'u1',
        userName: 'Ana',
        downloadedAt: DateTime(2026, 9, 1),
      ),
      ImageDownloadItem(
        id: '2',
        propertyId: 'p',
        propertyTitle: 'A',
        isZip: false,
        count: 1,
        userId: 'u1',
        userName: 'Ana',
        downloadedAt: DateTime(2026, 9, 5),
      ),
      const ImageDownloadItem(
        id: '3',
        propertyId: 'p',
        propertyTitle: 'A',
        isZip: false,
        count: 2,
      ),
    ];
    final s = summarizeImageDownloads(items);
    expect(s.first.user, 'Ana');
    expect(s.first.downloads, 2);
    expect(s.first.images, 11);
    expect(s.first.lastAt, DateTime(2026, 9, 5));
    expect(s.last.user, '(usuário removido)');
  });

  test('planilha tem as 4 abas do web e abre como xlsx', () {
    final sheets = buildCapturesWorkbookSheets(
      properties: [
        _p('1', code: '10', teamId: 't1', capturedById: 'u1', captorName: 'Ana'),
      ],
      statistics: const CapturesStatistics(propertiesSold: 1),
      teamContext: _ctx,
      query: CapturesReportQuery(
        allDates: false,
        createdFrom: DateTime(2026, 9, 1),
        createdTo: DateTime(2026, 9, 30),
      ),
      teamLabels: '',
      capturerLabels: 'Ana',
      responsibleLabels: '',
      publicSiteBase: 'https://site.com',
    );
    expect(sheets.map((s) => s.name), [
      'Resumo',
      'Ranking Captadores',
      'Ranking Equipes (imóvel)',
      'Imóveis',
    ]);
    final imoveis = sheets.last.rows;
    expect(imoveis.first, hasLength(42));
    final linkCol = imoveis.first.indexOf('Link no Site');
    expect(imoveis[1][linkCol], 'https://site.com/imovel/10');
    expect(imoveis[1][imoveis.first.indexOf('Equipe do imóvel')],
        'União Centro');
    final resumo = sheets.first.rows;
    expect(resumo.any((r) => r.first == 'Equipes do imóvel' && r[1] == 'Todas'),
        isTrue);

    final bytes = ClientSpreadsheet.buildXlsxSheets([
      for (final s in sheets) (name: s.name, rows: s.rows, widths: s.widths),
    ]);
    expect(bytes.sublist(0, 2), utf8.encode('PK'));
    final text = latin1.decode(bytes);
    expect(text, contains('xl/worksheets/sheet4.xml'));
    expect(text, contains('Ranking Equipes (imóvel)'.substring(0, 14)));
  });
}
