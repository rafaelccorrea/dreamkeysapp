import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../models/property_activity_models.dart';

/// Acesso às atividades e métricas do imóvel (histórico, atualizações e
/// engajamento) — paridade com a ficha web. Todas as leituras retornam
/// vazio/silencioso em falha para não derrubar a UI.
class PropertyActivityService {
  PropertyActivityService._();
  static final PropertyActivityService instance = PropertyActivityService._();

  final ApiService _api = ApiService.instance;

  /// `GET /properties/:id/history` → timeline de eventos (mais recente primeiro).
  Future<List<PropertyHistoryEntry>> getHistory(
    String propertyId, {
    int limit = 100,
  }) async {
    try {
      final response = await _api.get<List<dynamic>>(
        '/properties/$propertyId/history',
        queryParameters: {'limit': '$limit', 'enrich': 'true'},
      );
      if (response.success && response.data != null) {
        return response.data!
            .whereType<Map>()
            .map((e) =>
                PropertyHistoryEntry.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      return const [];
    } catch (e) {
      debugPrint('❌ [ACTIVITY] Erro ao carregar histórico: $e');
      return const [];
    }
  }

  /// `GET /properties/:id/updates` → atualizações paginadas.
  Future<PropertyUpdatesResponse> getUpdates(
    String propertyId, {
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(
        '/properties/$propertyId/updates',
        queryParameters: {'page': '$page', 'limit': '$limit'},
      );
      if (response.success && response.data != null) {
        return PropertyUpdatesResponse.fromJson(response.data!);
      }
      return PropertyUpdatesResponse.empty;
    } catch (e) {
      debugPrint('❌ [ACTIVITY] Erro ao carregar atualizações: $e');
      return PropertyUpdatesResponse.empty;
    }
  }

  /// `POST /properties/:id/updates` → cria atualização manual.
  Future<PropertyUpdateEntry?> createUpdate(
    String propertyId,
    String content,
  ) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return null;
    try {
      final response = await _api.post<Map<String, dynamic>>(
        '/properties/$propertyId/updates',
        body: {'content': trimmed},
      );
      if (response.success && response.data != null) {
        return PropertyUpdateEntry.fromJson(response.data!);
      }
      return null;
    } catch (e) {
      debugPrint('❌ [ACTIVITY] Erro ao criar atualização: $e');
      return null;
    }
  }

  /// `GET /dashboard/property-analytics/engagement` → métricas agregadas.
  Future<PropertyEngagementStats?> getEngagement(
    String propertyId, {
    int days = 30,
  }) async {
    try {
      final response = await _api.get<List<dynamic>>(
        '/dashboard/property-analytics/engagement',
        queryParameters: {'propertyIds': propertyId, 'days': '$days'},
      );
      if (response.success && response.data != null) {
        final match = response.data!
            .whereType<Map>()
            .map((e) =>
                PropertyEngagementStats.fromJson(Map<String, dynamic>.from(e)))
            .where((s) => s.propertyId == propertyId)
            .toList();
        if (match.isNotEmpty) return match.first;
        // Backend pode devolver único item sem casar id — usa o primeiro.
        if (response.data!.isNotEmpty && response.data!.first is Map) {
          return PropertyEngagementStats.fromJson(
            Map<String, dynamic>.from(response.data!.first as Map),
          );
        }
      }
      return null;
    } catch (e) {
      debugPrint('❌ [ACTIVITY] Erro ao carregar engajamento: $e');
      return null;
    }
  }

  /// `GET /dashboard/property-analytics/engagement-by-channel` → por origem.
  Future<List<PropertyEngagementByChannel>> getEngagementByChannel(
    String propertyId, {
    int days = 30,
  }) async {
    try {
      final response = await _api.get<List<dynamic>>(
        '/dashboard/property-analytics/engagement-by-channel',
        queryParameters: {'propertyIds': propertyId, 'days': '$days'},
      );
      if (response.success && response.data != null) {
        return response.data!
            .whereType<Map>()
            .map((e) => PropertyEngagementByChannel.fromJson(
                Map<String, dynamic>.from(e)))
            .toList();
      }
      return const [];
    } catch (e) {
      debugPrint('❌ [ACTIVITY] Erro ao carregar engajamento por canal: $e');
      return const [];
    }
  }
}
