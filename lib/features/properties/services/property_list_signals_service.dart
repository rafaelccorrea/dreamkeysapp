import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/services/api_service.dart';
import '../utils/property_list_signals.dart';

/// Membro da empresa no formato mínimo de `GET /users/company-members/simple`
/// (seletor "Corretor responsável" do filtro, como no web).
class PropertyFilterMember {
  final String id;
  final String name;
  final String email;

  const PropertyFilterMember({
    required this.id,
    required this.name,
    this.email = '',
  });
}

/// Chamadas da lista de imóveis que não são do `PropertyService`: selo
/// "Edição pendente", lembrete de imóveis parados (com o controle local de
/// "lembrar depois") e membros para o filtro de responsável.
class PropertyListSignalsService {
  PropertyListSignalsService._();

  static final PropertyListSignalsService instance =
      PropertyListSignalsService._();

  final ApiService _api = ApiService.instance;

  static const String _kTrackingKey = 'stale_properties_tracking_v1';

  /// O web abre o lembrete uma vez por sessão do navegador
  /// (`sessionStorage`); aqui, uma vez por execução do app.
  static bool staleReminderHandledThisSession = false;

  /// `GET /property-change-requests/pending-property-ids`. Falha/404 = vazio
  /// (nunca quebra a listagem), como no web.
  Future<Set<String>> getPendingEditPropertyIds() async {
    try {
      final r = await _api.get<dynamic>(
        '/property-change-requests/pending-property-ids',
      );
      if (!r.success) return <String>{};
      return parsePendingEditPropertyIds(r.data);
    } catch (e) {
      debugPrint('⚠️ [PROPERTY_SIGNALS] pending-property-ids: $e');
      return <String>{};
    }
  }

  /// `GET /properties/stale-for-user`. Falha = lista vazia (silencioso).
  Future<List<StaleProperty>> getStaleProperties() async {
    try {
      final r = await _api.get<dynamic>('/properties/stale-for-user');
      if (!r.success) return const [];
      return StaleProperty.listFrom(r.data);
    } catch (e) {
      debugPrint('⚠️ [PROPERTY_SIGNALS] stale-for-user: $e');
      return const [];
    }
  }

  /// Itens que devem aparecer agora (aplica o controle local e já poda e
  /// regrava as entradas vencidas).
  Future<List<StaleProperty>> getStalePropertiesToShow() async {
    final items = await getStaleProperties();
    if (items.isEmpty) return items;
    final now = DateTime.now();
    final map = StaleReminderRules.prune(await _readTracking(), now);
    await _writeTracking(map);
    return items
        .where((p) => StaleReminderRules.shouldShow(p, map, now))
        .toList();
  }

  Future<void> trackStale(
    Iterable<StaleProperty> items,
    StaleTrackingAction action,
  ) async {
    if (items.isEmpty) return;
    final map = StaleReminderRules.track(
      await _readTracking(),
      items,
      action,
      DateTime.now(),
    );
    await _writeTracking(map);
  }

  Future<Map<String, StaleTrackingEntry>> _readTracking() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kTrackingKey);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, StaleTrackingEntry>{};
      decoded.forEach((k, v) {
        final e = StaleTrackingEntry.tryParse(v);
        if (e != null) out[k.toString()] = e;
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeTracking(Map<String, StaleTrackingEntry> map) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kTrackingKey,
        jsonEncode({for (final e in map.entries) e.key: e.value.toJson()}),
      );
    } catch (_) {
      // Falha de armazenamento não pode travar o lembrete.
    }
  }

  /// `GET /users/company-members/simple` (sem cache: a empresa pode mudar).
  Future<List<PropertyFilterMember>> getCompanyMembers() async {
    try {
      final r = await _api.get<dynamic>('/users/company-members/simple');
      if (!r.success || r.data == null) return const [];
      final raw = r.data;
      final list = raw is List
          ? raw
          : (raw is Map && raw['data'] is List)
              ? raw['data'] as List
              : const <dynamic>[];
      final out = <PropertyFilterMember>[];
      for (final m in list) {
        if (m is! Map) continue;
        final id = m['id']?.toString().trim() ?? '';
        final name = (m['name'] ?? m['fullName'] ?? '').toString().trim();
        if (id.isEmpty || name.isEmpty) continue;
        out.add(
          PropertyFilterMember(
            id: id,
            name: name,
            email: m['email']?.toString().trim() ?? '',
          ),
        );
      }
      out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return out;
    } catch (e) {
      debugPrint('⚠️ [PROPERTY_SIGNALS] company-members: $e');
      return const [];
    }
  }
}
