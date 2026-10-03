import 'package:Intellisys/features/properties/utils/property_list_signals.dart';
import 'package:Intellisys/features/properties/widgets/predictive_analysis_sheet.dart';
import 'package:Intellisys/shared/services/property_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lastActivity', () {
    test('parse e linha do card como o web', () {
      final a = PropertyLastActivity.tryParse({
        'event': 'status_changed',
        'createdAt': '2026-10-03T14:05:00',
        'description': 'Disponível → Vendido',
        'userName': 'Maria',
      })!;
      expect(a.description, 'Disponível → Vendido');
      expect(
        propertyLastActivityLine(a),
        'Status alterado · 03/10/2026 14:05 · Maria',
      );
    });

    test('evento desconhecido vira palavras; sem evento = nulo', () {
      final a = PropertyLastActivity.tryParse({'event': 'foo_bar'})!;
      expect(propertyLastActivityLine(a), 'Foo Bar');
      expect(PropertyLastActivity.tryParse({'event': ''}), isNull);
      expect(PropertyLastActivity.tryParse(null), isNull);
    });
  });

  test('pending-property-ids', () {
    expect(
      parsePendingEditPropertyIds({
        'propertyIds': ['a', ' b ', '', null],
      }),
      {'a', 'b'},
    );
    expect(parsePendingEditPropertyIds(['x']), {'x'});
    expect(parsePendingEditPropertyIds('lixo'), isEmpty);
  });

  group('Imóveis parados', () {
    final now = DateTime(2026, 10, 3, 12);
    StaleProperty item(String id, DateTime ref) =>
        StaleProperty(id: id, title: 'T', lastUpdateEntryAt: ref);

    test('parse da lista e urgência', () {
      final list = StaleProperty.listFrom([
        {
          'id': 'p1',
          'title': 'Casa',
          'street': 'Rua A',
          'number': '1',
          'city': 'Goiânia',
          'state': 'GO',
          'lastUpdateEntryAt': '2026-07-01T00:00:00Z',
        },
        {'title': 'sem id'},
      ]);
      expect(list, hasLength(1));
      expect(list.first.address, 'Rua A, 1, Goiânia, GO');
      expect(StaleUrgency.of(14), StaleUrgency.atencao);
      expect(StaleUrgency.of(31), StaleUrgency.alto);
      expect(StaleUrgency.of(61), StaleUrgency.critico);
    });

    test('cooldown por ação e ficha alterada', () {
      final p = item('p1', DateTime(2026, 9, 1));
      var map = StaleReminderRules.track(
        {},
        [p],
        StaleTrackingAction.remindLater,
        now,
      );
      expect(StaleReminderRules.shouldShow(p, map, now), isFalse);
      expect(
        StaleReminderRules.shouldShow(
          p,
          map,
          now.add(const Duration(hours: 12)),
        ),
        isTrue,
      );
      map = StaleReminderRules.track(
        map,
        [p],
        StaleTrackingAction.snoozeWeek,
        now,
      );
      expect(
        StaleReminderRules.shouldShow(p, map, now.add(const Duration(days: 6))),
        isFalse,
      );
      // A ficha mudou desde o "adiar": volta a aparecer.
      final changed = item('p1', DateTime(2026, 9, 20));
      expect(StaleReminderRules.shouldShow(changed, map, now), isTrue);
    });

    test('poda entradas com mais de 30 dias e serializa', () {
      final p = item('p1', DateTime(2026, 9, 1));
      final map = StaleReminderRules.track(
        {},
        [p],
        StaleTrackingAction.openUpdate,
        now.subtract(const Duration(days: 31)),
      );
      expect(StaleReminderRules.prune(map, now), isEmpty);
      final back = StaleTrackingEntry.tryParse(map['p1']!.toJson())!;
      expect(back.action, StaleTrackingAction.openUpdate);
      expect(back.referenceAtMs, p.referenceAt!.millisecondsSinceEpoch);
    });
  });

  group('Análise preditiva', () {
    test('mensagens de erro do web', () {
      expect(predictiveAnalysisErrorMessage(400, null), contains('limite diário'));
      expect(predictiveAnalysisErrorMessage(429, null), contains('Aguarde'));
      expect(predictiveAnalysisErrorMessage(500, 'Falhou'), 'Falhou');
    });

    test('rótulo da probabilidade', () {
      expect(predictiveProbabilityLabel(70), 'Alta');
      expect(predictiveProbabilityLabel(40), 'Média');
      expect(predictiveProbabilityLabel(39.9), 'Baixa');
    });
  });
}
