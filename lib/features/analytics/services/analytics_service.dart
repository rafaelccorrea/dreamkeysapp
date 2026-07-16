import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../models/advanced_models.dart';
import '../models/compare_models.dart';
import '../models/multichannel_models.dart';
import '../models/parse_utils.dart';
import '../models/property_analytics_models.dart';

/// Serviço do domínio Analytics — consome os mesmos endpoints do painel web:
/// multicanal (`/analytics/public-site/*`), avançado (`/matches/performance`,
/// `/ai-assistant/*`, `/dashboard/conversion-funnel`, `/analytics/captures`),
/// imóveis (`/dashboard/property-analytics*`) e comparações
/// (`/matches/performance/compare/*`).
class AnalyticsService {
  AnalyticsService._();

  static final AnalyticsService instance = AnalyticsService._();
  final ApiService _api = ApiService.instance;

  // ─── Endpoints (paridade 1:1 com o imobx-front) ─────────────────────────
  static const String _sourcesFilterCities =
      '/analytics/public-site/sources/filter-cities';
  static const String _sourcesSummary =
      '/analytics/public-site/sources/summary';
  static const String _engagementSummary =
      '/analytics/public-site/engagement/summary';
  static const String _recentAttributions =
      '/analytics/public-site/sources/recent-attributions';
  static const String _performanceDashboard = '/matches/performance/dashboard';
  static const String _matches = '/matches';
  static const String _brokerPerformance =
      '/ai-assistant/analytics/broker-performance';
  static const String _churnPrediction = '/ai-assistant/predictive/churn';
  static const String _conversionFunnel = '/dashboard/conversion-funnel';
  static const String _capturesStatistics = '/analytics/captures/statistics';
  static const String _propertyAnalytics = '/dashboard/property-analytics';
  static const String _propertyEngagement =
      '/dashboard/property-analytics/engagement';
  static const String _compareUsers = '/matches/performance/compare/users';
  static const String _compareTeams = '/matches/performance/compare/teams';
  static const String _companyMembersSimple = '/users/company-members/simple';
  static const String _teams = '/teams';

  // ─── Helpers ─────────────────────────────────────────────────────────────

  ApiResponse<T> _mapError<T>(ApiResponse<dynamic> res, String fallback) {
    return ApiResponse.error(
      message: res.message ?? fallback,
      statusCode: res.statusCode,
      data: res.error,
    );
  }

  ApiResponse<T> _connError<T>(Object e, String tag) {
    debugPrint('❌ [ANALYTICS] $tag: $e');
    return ApiResponse.error(
      message: 'Erro de conexão: $e',
      statusCode: 0,
    );
  }

  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const {};
  }

  /// Extrai lista de uma resposta que pode vir crua, em `{data: []}` ou em
  /// objeto único (a IA às vezes devolve um item só).
  List<Map<String, dynamic>> _asMapList(dynamic raw, {String? listKey}) {
    if (raw is List) return parseMapList(raw);
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      if (listKey != null && map[listKey] is List) {
        return parseMapList(map[listKey]);
      }
      if (map['data'] is List) return parseMapList(map['data']);
      if (map.isNotEmpty && listKey == null) return [map];
    }
    return const [];
  }

  static String _dateOnly(DateTime d) => d.toIso8601String().split('T').first;

  // ─── Multicanal ──────────────────────────────────────────────────────────

  /// `GET /analytics/public-site/sources/filter-cities`
  Future<ApiResponse<List<CityOption>>> getFilterCities() async {
    try {
      final res = await _api.get<dynamic>(_sourcesFilterCities);
      if (res.success && res.data != null) {
        final list = _asMapList(res.data)
            .map(CityOption.fromJson)
            .where((c) => c.key.isNotEmpty)
            .toList(growable: false);
        return ApiResponse.success(data: list, statusCode: res.statusCode);
      }
      return _mapError(res, 'Erro ao carregar cidades');
    } catch (e) {
      return _connError(e, 'getFilterCities');
    }
  }

  /// `GET /analytics/public-site/sources/summary`
  Future<ApiResponse<SourcesSummary>> getSourcesSummary({
    String period = 'monthly',
    List<String> cities = const [],
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final params = <String, String>{'period': period};
      if (cities.isNotEmpty) params['cities'] = cities.join('|');
      if (startDate != null) params['startDate'] = _dateOnly(startDate);
      if (endDate != null) params['endDate'] = _dateOnly(endDate);
      final res =
          await _api.get<dynamic>(_sourcesSummary, queryParameters: params);
      if (res.success && res.data != null) {
        return ApiResponse.success(
          data: SourcesSummary.fromJson(_asMap(res.data)),
          statusCode: res.statusCode,
        );
      }
      return _mapError(res, 'Erro ao carregar canais de origem');
    } catch (e) {
      return _connError(e, 'getSourcesSummary');
    }
  }

  /// `GET /analytics/public-site/engagement/summary` — exige cidade única.
  Future<ApiResponse<EngagementSummaryData>> getEngagementSummary({
    required String city,
    required String state,
    String period = 'monthly',
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final params = <String, String>{
        'city': city,
        'state': state,
        'period': period,
      };
      if (startDate != null) params['startDate'] = _dateOnly(startDate);
      if (endDate != null) params['endDate'] = _dateOnly(endDate);
      final res =
          await _api.get<dynamic>(_engagementSummary, queryParameters: params);
      if (res.success && res.data != null) {
        return ApiResponse.success(
          data: EngagementSummaryData.fromJson(_asMap(res.data)),
          statusCode: res.statusCode,
        );
      }
      return _mapError(res, 'Erro ao carregar engajamento');
    } catch (e) {
      return _connError(e, 'getEngagementSummary');
    }
  }

  /// `GET /analytics/public-site/sources/recent-attributions`
  Future<ApiResponse<RecentAttributionsData>> getRecentAttributions({
    String period = 'monthly',
    List<String> cities = const [],
    String? channel,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final params = <String, String>{
        'period': period,
        'type': 'leads',
        'limit': '$limit',
        'offset': '$offset',
      };
      if (cities.isNotEmpty) params['cities'] = cities.join('|');
      if (channel != null && channel.isNotEmpty) params['channel'] = channel;
      final res = await _api.get<dynamic>(
        _recentAttributions,
        queryParameters: params,
      );
      if (res.success && res.data != null) {
        return ApiResponse.success(
          data: RecentAttributionsData.fromJson(_asMap(res.data)),
          statusCode: res.statusCode,
        );
      }
      return _mapError(res, 'Erro ao carregar leads recentes');
    } catch (e) {
      return _connError(e, 'getRecentAttributions');
    }
  }

  // ─── Analytics avançado ──────────────────────────────────────────────────

  /// `GET /matches/performance/dashboard`
  Future<ApiResponse<PerformanceDashboard>> getPerformanceDashboard({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final params = <String, String>{};
      if (startDate != null) {
        params['startDate'] = startDate.toIso8601String();
      }
      if (endDate != null) params['endDate'] = endDate.toIso8601String();
      final res = await _api.get<dynamic>(
        _performanceDashboard,
        queryParameters: params.isEmpty ? null : params,
      );
      if (res.success && res.data != null) {
        return ApiResponse.success(
          data: PerformanceDashboard.fromJson(_asMap(res.data)),
          statusCode: res.statusCode,
        );
      }
      return _mapError(res, 'Erro ao carregar performance da empresa');
    } catch (e) {
      return _connError(e, 'getPerformanceDashboard');
    }
  }

  /// `GET /matches?status=pending` — resumo de matches pendentes.
  Future<ApiResponse<PendingMatchesSummary>> getPendingMatches({
    int limit = 50,
  }) async {
    try {
      final res = await _api.get<dynamic>(
        _matches,
        queryParameters: {'status': 'pending', 'page': '1', 'limit': '$limit'},
      );
      if (res.success && res.data != null) {
        final raw = res.data;
        List<Map<String, dynamic>> list;
        var total = 0;
        if (raw is List) {
          list = parseMapList(raw);
          total = list.length;
        } else {
          final map = _asMap(raw);
          list = parseMapList(map['matches'] ?? map['data']);
          total = parseInt(map['total'], list.length);
        }
        final matches =
            list.map(PendingMatch.fromJson).toList(growable: false);
        return ApiResponse.success(
          data: PendingMatchesSummary.fromMatches(matches, total: total),
          statusCode: res.statusCode,
        );
      }
      return _mapError(res, 'Erro ao carregar matches pendentes');
    } catch (e) {
      return _connError(e, 'getPendingMatches');
    }
  }

  /// `POST /ai-assistant/analytics/broker-performance`
  Future<ApiResponse<List<BrokerPerformance>>> getBrokersPerformance({
    String period = 'month',
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final body = <String, dynamic>{'period': period};
      if (startDate != null) {
        body['startDate'] = startDate.toIso8601String();
      }
      if (endDate != null) body['endDate'] = endDate.toIso8601String();
      final res = await _api.post<dynamic>(_brokerPerformance, body: body);
      if (res.success && res.data != null) {
        final list = _asMapList(res.data)
            .map(BrokerPerformance.fromJson)
            .toList()
          ..sort((a, b) => b.overallScore.compareTo(a.overallScore));
        return ApiResponse.success(data: list, statusCode: res.statusCode);
      }
      return _mapError(res, 'Erro ao analisar corretores');
    } catch (e) {
      return _connError(e, 'getBrokersPerformance');
    }
  }

  /// `POST /ai-assistant/predictive/churn` (análise em lote)
  Future<ApiResponse<ChurnAnalysis>> getChurnAnalysis() async {
    try {
      final res = await _api.post<dynamic>(
        _churnPrediction,
        body: const <String, dynamic>{},
      );
      if (res.success && res.data != null) {
        final list = _asMapList(res.data)
            .map(ChurnPrediction.fromJson)
            .toList(growable: false);
        return ApiResponse.success(
          data: ChurnAnalysis.fromPredictions(list),
          statusCode: res.statusCode,
        );
      }
      return _mapError(res, 'Erro na análise de churn');
    } catch (e) {
      return _connError(e, 'getChurnAnalysis');
    }
  }

  /// `GET /dashboard/conversion-funnel?startDate=YYYY-MM-DD&endDate=...`
  Future<ApiResponse<ConversionFunnelData>> getConversionFunnel({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final res = await _api.get<dynamic>(
        _conversionFunnel,
        queryParameters: {
          'startDate': _dateOnly(startDate),
          'endDate': _dateOnly(endDate),
        },
      );
      if (res.success && res.data != null) {
        return ApiResponse.success(
          data: ConversionFunnelData.fromJson(_asMap(res.data)),
          statusCode: res.statusCode,
        );
      }
      return _mapError(res, 'Erro ao carregar funil de conversão');
    } catch (e) {
      return _connError(e, 'getConversionFunnel');
    }
  }

  /// `GET /analytics/captures/statistics`
  Future<ApiResponse<CapturesStats>> getCapturesStatistics({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final params = <String, String>{};
      if (startDate != null) {
        params['startDate'] = startDate.toIso8601String();
      }
      if (endDate != null) params['endDate'] = endDate.toIso8601String();
      final res = await _api.get<dynamic>(
        _capturesStatistics,
        queryParameters: params.isEmpty ? null : params,
      );
      if (res.success && res.data != null) {
        return ApiResponse.success(
          data: CapturesStats.fromJson(_asMap(res.data)),
          statusCode: res.statusCode,
        );
      }
      return _mapError(res, 'Erro ao carregar captações');
    } catch (e) {
      return _connError(e, 'getCapturesStatistics');
    }
  }

  // ─── Analytics de imóveis ────────────────────────────────────────────────

  /// `GET /dashboard/property-analytics`
  Future<ApiResponse<PropertyAnalyticsData>> getPropertyAnalytics({
    PropertyAnalyticsFilters filters = const PropertyAnalyticsFilters(),
  }) async {
    try {
      final params = filters.toQueryParams();
      final res = await _api.get<dynamic>(
        _propertyAnalytics,
        queryParameters: params.isEmpty ? null : params,
      );
      if (res.success && res.data != null) {
        return ApiResponse.success(
          data: PropertyAnalyticsData.fromJson(_asMap(res.data)),
          statusCode: res.statusCode,
        );
      }
      return _mapError(res, 'Erro ao carregar analytics de imóveis');
    } catch (e) {
      return _connError(e, 'getPropertyAnalytics');
    }
  }

  /// `GET /dashboard/property-analytics/engagement`
  Future<ApiResponse<List<PropertyEngagement>>> getPropertyEngagement({
    int days = 3,
    String sortBy = 'total',
  }) async {
    try {
      final res = await _api.get<dynamic>(
        _propertyEngagement,
        queryParameters: {'days': '$days', 'sortBy': sortBy},
      );
      if (res.success && res.data != null) {
        final list = _asMapList(res.data)
            .map(PropertyEngagement.fromJson)
            .toList(growable: false);
        return ApiResponse.success(data: list, statusCode: res.statusCode);
      }
      return _mapError(res, 'Erro ao carregar engajamento de imóveis');
    } catch (e) {
      return _connError(e, 'getPropertyEngagement');
    }
  }

  // ─── Comparações ─────────────────────────────────────────────────────────

  /// `GET /users/company-members/simple` — todos os membros (para seleção).
  Future<ApiResponse<List<MemberOption>>> getCompanyMembers() async {
    try {
      final res = await _api.get<dynamic>(_companyMembersSimple);
      if (res.success && res.data != null) {
        final list = _asMapList(res.data)
            .map(MemberOption.fromJson)
            .where((m) => m.id.isNotEmpty)
            .toList(growable: false);
        return ApiResponse.success(data: list, statusCode: res.statusCode);
      }
      return _mapError(res, 'Erro ao carregar corretores');
    } catch (e) {
      return _connError(e, 'getCompanyMembers');
    }
  }

  /// `GET /teams` — equipes da empresa (para seleção).
  Future<ApiResponse<List<TeamOption>>> getTeams() async {
    try {
      final res = await _api.get<dynamic>(_teams);
      if (res.success && res.data != null) {
        final list = _asMapList(res.data)
            .map(TeamOption.fromJson)
            .where((t) => t.id.isNotEmpty)
            .toList(growable: false);
        return ApiResponse.success(data: list, statusCode: res.statusCode);
      }
      return _mapError(res, 'Erro ao carregar equipes');
    } catch (e) {
      return _connError(e, 'getTeams');
    }
  }

  /// `POST /matches/performance/compare/users` (2 a 4 corretores)
  Future<ApiResponse<UsersComparison>> compareUsers({
    required List<String> userIds,
    CompareFilters filters = const CompareFilters(),
  }) async {
    try {
      final body = <String, dynamic>{'userIds': userIds, ...filters.toBody()};
      final res = await _api.post<dynamic>(_compareUsers, body: body);
      if (res.success && res.data != null) {
        return ApiResponse.success(
          data: UsersComparison.fromJson(_asMap(res.data)),
          statusCode: res.statusCode,
        );
      }
      return _mapError(res, 'Erro ao comparar corretores');
    } catch (e) {
      return _connError(e, 'compareUsers');
    }
  }

  /// `POST /matches/performance/compare/teams` (2 a 4 equipes)
  Future<ApiResponse<TeamsComparison>> compareTeams({
    required List<String> teamIds,
    CompareFilters filters = const CompareFilters(),
  }) async {
    try {
      final body = <String, dynamic>{'teamIds': teamIds, ...filters.toBody()};
      final res = await _api.post<dynamic>(_compareTeams, body: body);
      if (res.success && res.data != null) {
        return ApiResponse.success(
          data: TeamsComparison.fromJson(_asMap(res.data)),
          statusCode: res.statusCode,
        );
      }
      return _mapError(res, 'Erro ao comparar equipes');
    } catch (e) {
      return _connError(e, 'compareTeams');
    }
  }
}
