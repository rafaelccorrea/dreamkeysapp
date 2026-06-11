import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Cache leve para consulta offline (clientes + subtarefas recentes).
class BrokerOfflineCache {
  BrokerOfflineCache._();
  static final BrokerOfflineCache instance = BrokerOfflineCache._();

  static const _clientsKey = 'broker_offline_clients_v1';
  static const _subtasksKey = 'broker_offline_subtasks_v1';

  Future<void> saveClients(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clientsKey, jsonEncode(items.take(80).toList()));
  }

  Future<List<Map<String, dynamic>>> loadClients() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_clientsKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSubtasks(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_subtasksKey, jsonEncode(items.take(60).toList()));
  }

  Future<List<Map<String, dynamic>>> loadSubtasks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_subtasksKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return [];
    }
  }
}
