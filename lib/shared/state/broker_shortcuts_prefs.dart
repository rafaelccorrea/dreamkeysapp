import 'package:shared_preferences/shared_preferences.dart';

/// Atalhos configuráveis no Início (Funil, Agenda, Clientes, Rascunhos…).
class BrokerShortcutsPrefs {
  BrokerShortcutsPrefs._();
  static final BrokerShortcutsPrefs instance = BrokerShortcutsPrefs._();

  static const _key = 'broker_shortcuts_v1';

  static const defaultIds = [
    'kanban',
    'calendar',
    'clients',
    'drafts',
  ];

  static const allShortcuts = <BrokerShortcutDef>[
    BrokerShortcutDef('kanban', 'CRM / Funil', 'squareKanban'),
    BrokerShortcutDef('calendar', 'Agenda', 'calendarDays'),
    BrokerShortcutDef('clients', 'Clientes', 'users'),
    BrokerShortcutDef('drafts', 'Rascunhos', 'fileEdit'),
    BrokerShortcutDef('tasks', 'Minhas tarefas', 'listChecks'),
    BrokerShortcutDef('proposals', 'Propostas', 'fileSignature'),
    BrokerShortcutDef('matches', 'Matches', 'sparkles'),
    BrokerShortcutDef('properties', 'Imóveis', 'home'),
  ];

  Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key);
    if (raw == null || raw.isEmpty) return List.from(defaultIds);
    return raw;
  }

  Future<void> save(List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, ids);
  }
}

class BrokerShortcutDef {
  final String id;
  final String label;
  final String iconKey;

  const BrokerShortcutDef(this.id, this.label, this.iconKey);
}
