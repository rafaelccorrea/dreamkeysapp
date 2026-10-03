import 'package:intl/intl.dart' show DateFormat;

import '../../../shared/services/property_service.dart';
import '../models/property_activity_models.dart';
import '../widgets/details/property_history_entry_tile.dart'
    show propertyHistoryEventTitle;

/// Lógica pura dos sinais da lista de imóveis (sem I/O), testável:
/// - linha de "última atividade" do card (`lastActivity`, web
///   `PropertiesPage.tsx` ~2907);
/// - lembrete de imóveis parados (`stale-for-user`, web
///   `StalePropertiesModal.tsx`): urgência, cooldown por ação e poda;
/// - IDs com "Edição pendente" (`pending-property-ids`).

/// "Status alterado · 03/10/2026 14:05 · Maria" — o texto da linha do card
/// do web (`labelForHistoryEvent` · `formatPropertyHistoryDateTime` · nome).
String propertyLastActivityLine(PropertyLastActivity a) {
  final parts = <String>[
    propertyHistoryEventTitle(
      PropertyHistoryEntry(id: '', event: a.event, createdAt: DateTime(0)),
    ),
  ];
  if (a.createdAt != null) {
    parts.add(DateFormat('dd/MM/yyyy HH:mm').format(a.createdAt!));
  }
  if ((a.userName ?? '').isNotEmpty) parts.add(a.userName!);
  return parts.join(' · ');
}

/// `{ propertyIds: [...] }` de `GET /property-change-requests/
/// pending-property-ids` (também aceita a lista na raiz).
Set<String> parsePendingEditPropertyIds(dynamic raw) {
  final list = raw is Map ? raw['propertyIds'] : raw;
  if (list is! List) return <String>{};
  return {
    for (final v in list)
      if ((v?.toString().trim() ?? '').isNotEmpty) v.toString().trim(),
  };
}

// ── Imóveis parados (stale-for-user) ─────────────────────────────────────

/// Item de `GET /properties/stale-for-user` (disponíveis, ativos, sem
/// atualização há 14+ dias, onde o usuário é responsável/captador).
class StaleProperty {
  final String id;
  final String title;
  final String? code;
  final String? street;
  final String? number;
  final String? city;
  final String? state;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastUpdateEntryAt;

  const StaleProperty({
    required this.id,
    required this.title,
    this.code,
    this.street,
    this.number,
    this.city,
    this.state,
    this.createdAt,
    this.updatedAt,
    this.lastUpdateEntryAt,
  });

  static List<StaleProperty> listFrom(dynamic raw) {
    final list = raw is Map ? raw['data'] : raw;
    if (list is! List) return const [];
    final out = <StaleProperty>[];
    for (final e in list) {
      if (e is! Map) continue;
      String? opt(dynamic v) {
        final s = v?.toString().trim() ?? '';
        return s.isEmpty ? null : s;
      }

      DateTime? date(dynamic v) {
        final s = opt(v);
        return s == null ? null : DateTime.tryParse(s);
      }

      final id = opt(e['id']) ?? opt(e['propertyId']);
      if (id == null) continue;
      out.add(
        StaleProperty(
          id: id,
          title: opt(e['title']) ?? '',
          code: opt(e['code']),
          street: opt(e['street']),
          number: opt(e['number']),
          city: opt(e['city']),
          state: opt(e['state']),
          createdAt: date(e['createdAt']),
          updatedAt: date(e['updatedAt']),
          lastUpdateEntryAt: date(e['lastUpdateEntryAt']),
        ),
      );
    }
    return out;
  }

  /// Data de referência do web (`getReferenceAt`): último registro, senão
  /// atualização, senão cadastro.
  DateTime? get referenceAt => lastUpdateEntryAt ?? updatedAt ?? createdAt;

  /// Dias sem atualizar (web: `lastUpdateEntryAt` ou `createdAt`).
  int daysSince(DateTime now) {
    final ref = lastUpdateEntryAt ?? createdAt;
    if (ref == null) return 0;
    return now.difference(ref).inDays;
  }

  String get address => [street, number, city, state]
      .where((p) => (p ?? '').isNotEmpty)
      .join(', ');
}

/// Faixa de urgência do web: até 30, 30–60, mais de 60 dias.
enum StaleUrgency {
  atencao('Até 30 dias'),
  alto('30 a 60 dias'),
  critico('Mais de 60 dias');

  const StaleUrgency(this.label);
  final String label;

  static StaleUrgency of(int days) {
    if (days > 60) return StaleUrgency.critico;
    if (days > 30) return StaleUrgency.alto;
    return StaleUrgency.atencao;
  }
}

/// O que o usuário fez com o item — define por quanto tempo ele some.
enum StaleTrackingAction {
  remindLater('remind_later', Duration(hours: 12)),
  openUpdate('open_update', Duration(hours: 24)),
  snoozeWeek('snooze_week', Duration(days: 7));

  const StaleTrackingAction(this.value, this.cooldown);
  final String value;
  final Duration cooldown;

  static StaleTrackingAction fromValue(String? v) => StaleTrackingAction.values
      .firstWhere((a) => a.value == v, orElse: () => remindLater);
}

/// Entrada do controle local (mesmo formato do `localStorage` do web).
class StaleTrackingEntry {
  final int? referenceAtMs;
  final StaleTrackingAction action;
  final DateTime trackedAt;

  const StaleTrackingEntry({
    required this.referenceAtMs,
    required this.action,
    required this.trackedAt,
  });

  Map<String, dynamic> toJson() => {
        'referenceAtMs': referenceAtMs,
        'action': action.value,
        'trackedAt': trackedAt.toUtc().toIso8601String(),
      };

  static StaleTrackingEntry? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final tracked = DateTime.tryParse(raw['trackedAt']?.toString() ?? '');
    if (tracked == null) return null;
    final ref = raw['referenceAtMs'];
    return StaleTrackingEntry(
      referenceAtMs: ref is num ? ref.toInt() : null,
      action: StaleTrackingAction.fromValue(raw['action']?.toString()),
      trackedAt: tracked,
    );
  }
}

/// Regras do lembrete — espelho do `StalePropertiesModal.tsx`.
class StaleReminderRules {
  StaleReminderRules._();

  /// Entradas mais velhas que isso são descartadas (web: 30 dias).
  static const Duration maxAge = Duration(days: 30);

  static Map<String, StaleTrackingEntry> prune(
    Map<String, StaleTrackingEntry> map,
    DateTime now,
  ) {
    return {
      for (final e in map.entries)
        if (now.difference(e.value.trackedAt) <= maxAge) e.key: e.value,
    };
  }

  /// Mostra de novo quando: nunca foi tratado, a ficha mudou desde então
  /// (referência diferente) ou o cooldown da última ação já passou.
  static bool shouldShow(
    StaleProperty p,
    Map<String, StaleTrackingEntry> map,
    DateTime now,
  ) {
    final entry = map[p.id];
    if (entry == null) return true;
    final currentRef = p.referenceAt?.millisecondsSinceEpoch;
    if (entry.referenceAtMs != currentRef) return true;
    return now.difference(entry.trackedAt) >= entry.action.cooldown;
  }

  static Map<String, StaleTrackingEntry> track(
    Map<String, StaleTrackingEntry> map,
    Iterable<StaleProperty> items,
    StaleTrackingAction action,
    DateTime now,
  ) {
    final next = prune(map, now);
    for (final p in items) {
      next[p.id] = StaleTrackingEntry(
        referenceAtMs: p.referenceAt?.millisecondsSinceEpoch,
        action: action,
        trackedAt: now,
      );
    }
    return next;
  }
}
