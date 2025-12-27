import 'package:flutter/foundation.dart';
import 'api_service.dart';
import '../../core/constants/api_constants.dart';

/// Modelos de dados do Dashboard
class DashboardResponse {
  final DashboardUser user;
  final DashboardStats stats;
  final DashboardPerformance performance;
  final DashboardGamification gamification;
  final DashboardActivityStats activityStats;
  final List<DashboardActivity> recentActivities;
  final List<DashboardAppointment> upcomingAppointments;
  final DashboardMonthlyGoals? monthlyGoals;
  final DashboardConversionMetrics conversionMetrics;
  final String lastUpdated;

  DashboardResponse({
    required this.user,
    required this.stats,
    required this.performance,
    required this.gamification,
    required this.activityStats,
    required this.recentActivities,
    required this.upcomingAppointments,
    this.monthlyGoals,
    required this.conversionMetrics,
    required this.lastUpdated,
  });

  factory DashboardResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    return DashboardResponse(
      user: DashboardUser.fromJson(data['user'] as Map<String, dynamic>),
      stats: DashboardStats.fromJson(data['stats'] as Map<String, dynamic>),
      performance: DashboardPerformance.fromJson(
        data['performance'] as Map<String, dynamic>,
      ),
      gamification: DashboardGamification.fromJson(
        data['gamification'] as Map<String, dynamic>,
      ),
      activityStats: DashboardActivityStats.fromJson(
        data['activityStats'] as Map<String, dynamic>,
      ),
      recentActivities: (data['recentActivities'] as List<dynamic>)
          .map((e) => DashboardActivity.fromJson(e as Map<String, dynamic>))
          .toList(),
      upcomingAppointments: (data['upcomingAppointments'] as List<dynamic>)
          .map((e) => DashboardAppointment.fromJson(e as Map<String, dynamic>))
          .toList(),
      monthlyGoals: data['monthlyGoals'] != null
          ? DashboardMonthlyGoals.fromJson(
              data['monthlyGoals'] as Map<String, dynamic>,
            )
          : null,
      conversionMetrics: DashboardConversionMetrics.fromJson(
        data['conversionMetrics'] as Map<String, dynamic>,
      ),
      lastUpdated: json['lastUpdated'] as String? ?? '',
    );
  }
}

class DashboardUser {
  final String id;
  final String name;
  final String email;
  final String role;
  final String? avatar;

  DashboardUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.avatar,
  });

  factory DashboardUser.fromJson(Map<String, dynamic> json) {
    return DashboardUser(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      avatar: json['avatar']?.toString(),
    );
  }
}

class DashboardStats {
  final int myProperties;
  final int myClients;
  final int myInspections;
  final int myAppointments;
  final double myCommissions;
  final int myTasks;
  final int myKeys;
  final int myNotes;
  final int myMatches;

  DashboardStats({
    required this.myProperties,
    required this.myClients,
    required this.myInspections,
    required this.myAppointments,
    required this.myCommissions,
    required this.myTasks,
    required this.myKeys,
    required this.myNotes,
    required this.myMatches,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    return DashboardStats(
      myProperties: json['myProperties'] as int? ?? 0,
      myClients: json['myClients'] as int? ?? 0,
      myInspections: json['myInspections'] as int? ?? 0,
      myAppointments: json['myAppointments'] as int? ?? 0,
      myCommissions: (json['myCommissions'] as num?)?.toDouble() ?? 0.0,
      myTasks: json['myTasks'] as int? ?? 0,
      myKeys: json['myKeys'] as int? ?? 0,
      myNotes: json['myNotes'] as int? ?? 0,
      myMatches: json['myMatches'] as int? ?? 0,
    );
  }
}

class DashboardPerformance {
  final double thisMonth;
  final double lastMonth;
  final double growthPercentage;
  final int ranking;
  final int totalUsers;
  final int points;

  DashboardPerformance({
    required this.thisMonth,
    required this.lastMonth,
    required this.growthPercentage,
    required this.ranking,
    required this.totalUsers,
    required this.points,
  });

  factory DashboardPerformance.fromJson(Map<String, dynamic> json) {
    return DashboardPerformance(
      thisMonth: (json['thisMonth'] as num?)?.toDouble() ?? 0.0,
      lastMonth: (json['lastMonth'] as num?)?.toDouble() ?? 0.0,
      growthPercentage: (json['growthPercentage'] as num?)?.toDouble() ?? 0.0,
      ranking: json['ranking'] as int? ?? 0,
      totalUsers: json['totalUsers'] as int? ?? 0,
      points: json['points'] as int? ?? 0,
    );
  }
}

class DashboardGamification {
  final int currentPoints;
  final int level;
  final List<DashboardAchievement> achievements;
  final DashboardPointsBreakdown pointsBreakdown;

  DashboardGamification({
    required this.currentPoints,
    required this.level,
    required this.achievements,
    required this.pointsBreakdown,
  });

  factory DashboardGamification.fromJson(Map<String, dynamic> json) {
    return DashboardGamification(
      currentPoints: json['currentPoints'] as int? ?? 0,
      level: json['level'] as int? ?? 0,
      achievements: (json['achievements'] as List<dynamic>?)
              ?.map((e) => DashboardAchievement.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      pointsBreakdown: DashboardPointsBreakdown.fromJson(
        json['pointsBreakdown'] as Map<String, dynamic>,
      ),
    );
  }
}

class DashboardAchievement {
  final String id;
  final String achievementId;
  final String name;
  final String description;
  final String icon;
  final String earnedAt;

  DashboardAchievement({
    required this.id,
    required this.achievementId,
    required this.name,
    required this.description,
    required this.icon,
    required this.earnedAt,
  });

  factory DashboardAchievement.fromJson(Map<String, dynamic> json) {
    return DashboardAchievement(
      id: json['id']?.toString() ?? '',
      achievementId: json['achievementId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      icon: json['icon']?.toString() ?? '',
      earnedAt: json['earnedAt']?.toString() ?? '',
    );
  }
}

class DashboardPointsBreakdown {
  final int sales;
  final int rentals;
  final int clients;
  final int appointments;
  final int tasks;
  final int other;

  DashboardPointsBreakdown({
    required this.sales,
    required this.rentals,
    required this.clients,
    required this.appointments,
    required this.tasks,
    required this.other,
  });

  factory DashboardPointsBreakdown.fromJson(Map<String, dynamic> json) {
    return DashboardPointsBreakdown(
      sales: json['sales'] as int? ?? 0,
      rentals: json['rentals'] as int? ?? 0,
      clients: json['clients'] as int? ?? 0,
      appointments: json['appointments'] as int? ?? 0,
      tasks: json['tasks'] as int? ?? 0,
      other: json['other'] as int? ?? 0,
    );
  }
}

class DashboardActivityStats {
  final int totalVisits;
  final int appointmentsThisMonth;
  final double completionRate;

  DashboardActivityStats({
    required this.totalVisits,
    required this.appointmentsThisMonth,
    required this.completionRate,
  });

  factory DashboardActivityStats.fromJson(Map<String, dynamic> json) {
    return DashboardActivityStats(
      totalVisits: json['totalVisits'] as int? ?? 0,
      appointmentsThisMonth: json['appointmentsThisMonth'] as int? ?? 0,
      completionRate: (json['completionRate'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class DashboardActivity {
  final String id;
  final String type;
  final String title;
  final String description;
  final String time;
  final String status;
  final String createdAt;

  DashboardActivity({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.time,
    required this.status,
    required this.createdAt,
  });

  factory DashboardActivity.fromJson(Map<String, dynamic> json) {
    return DashboardActivity(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      time: json['time']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }
}

class DashboardAppointment {
  final String id;
  final String title;
  final String date;
  final String time;
  final String client;
  final String type;

  DashboardAppointment({
    required this.id,
    required this.title,
    required this.date,
    required this.time,
    required this.client,
    required this.type,
  });

  factory DashboardAppointment.fromJson(Map<String, dynamic> json) {
    return DashboardAppointment(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      time: json['time']?.toString() ?? '',
      client: json['client']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
    );
  }
}

class DashboardMonthlyGoals {
  final DashboardGoal? sales;
  final DashboardGoal? commissions;

  DashboardMonthlyGoals({
    this.sales,
    this.commissions,
  });

  factory DashboardMonthlyGoals.fromJson(Map<String, dynamic> json) {
    return DashboardMonthlyGoals(
      sales: json['sales'] != null
          ? DashboardGoal.fromJson(json['sales'] as Map<String, dynamic>)
          : null,
      commissions: json['commissions'] != null
          ? DashboardGoal.fromJson(json['commissions'] as Map<String, dynamic>)
          : null,
    );
  }
}

class DashboardGoal {
  final double current;
  final double target;
  final double percentage;

  DashboardGoal({
    required this.current,
    required this.target,
    required this.percentage,
  });

  factory DashboardGoal.fromJson(Map<String, dynamic> json) {
    return DashboardGoal(
      current: (json['current'] as num?)?.toDouble() ?? 0.0,
      target: (json['target'] as num?)?.toDouble() ?? 0.0,
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class DashboardConversionMetrics {
  final double visitsToSales;
  final double clientsToClosed;
  final int matchesAccepted;

  DashboardConversionMetrics({
    required this.visitsToSales,
    required this.clientsToClosed,
    required this.matchesAccepted,
  });

  factory DashboardConversionMetrics.fromJson(Map<String, dynamic> json) {
    return DashboardConversionMetrics(
      visitsToSales: (json['visitsToSales'] as num?)?.toDouble() ?? 0.0,
      clientsToClosed: (json['clientsToClosed'] as num?)?.toDouble() ?? 0.0,
      matchesAccepted: json['matchesAccepted'] as int? ?? 0,
    );
  }
}

/// Serviço do Dashboard
class DashboardService {
  DashboardService._();

  static final DashboardService instance = DashboardService._();
  final ApiService _apiService = ApiService.instance;

  /// Busca dados do dashboard do usuário
  Future<ApiResponse<DashboardResponse>> getUserDashboard({
    String dateRange = '30d',
    String compareWith = 'previous_period',
    String metric = 'all',
    String? startDate,
    String? endDate,
    int activitiesLimit = 10,
    int appointmentsLimit = 5,
  }) async {
    debugPrint('📊 [DASHBOARD API] Iniciando busca de dados do dashboard');
    debugPrint('📊 [DASHBOARD API] Parâmetros:');
    debugPrint('   - dateRange: $dateRange');
    debugPrint('   - compareWith: $compareWith');
    debugPrint('   - metric: $metric');
    debugPrint('   - startDate: $startDate');
    debugPrint('   - endDate: $endDate');
    debugPrint('   - activitiesLimit: $activitiesLimit');
    debugPrint('   - appointmentsLimit: $appointmentsLimit');
    debugPrint('📊 [DASHBOARD API] Endpoint: ${ApiConstants.dashboardUser}');
    
    try {
      final queryParams = <String, String>{
        'dateRange': dateRange,
        'compareWith': compareWith,
        'metric': metric,
        'activitiesLimit': activitiesLimit.toString(),
        'appointmentsLimit': appointmentsLimit.toString(),
      };

      if (startDate != null) queryParams['startDate'] = startDate;
      if (endDate != null) queryParams['endDate'] = endDate;

      debugPrint('📊 [DASHBOARD API] Query params: $queryParams');
      debugPrint('📊 [DASHBOARD API] Fazendo requisição GET...');

      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConstants.dashboardUser,
        queryParameters: queryParams,
      );

      debugPrint('📊 [DASHBOARD API] Resposta recebida:');
      debugPrint('   - success: ${response.success}');
      debugPrint('   - statusCode: ${response.statusCode}');
      debugPrint('   - message: ${response.message}');
      
      if (response.data != null) {
        debugPrint('   - data: ${response.data}');
        debugPrint('📊 [DASHBOARD API] Parseando resposta...');
      } else {
        debugPrint('   - data: null');
      }

      if (response.success && response.data != null) {
        try {
          final dashboardResponse = DashboardResponse.fromJson(response.data!);
          debugPrint('✅ [DASHBOARD API] Dashboard parseado com sucesso!');
          debugPrint('   - User: ${dashboardResponse.user.name} (${dashboardResponse.user.email})');
          debugPrint('   - Stats: ${dashboardResponse.stats.myProperties} imóveis, ${dashboardResponse.stats.myClients} clientes');
          debugPrint('   - Performance: R\$ ${dashboardResponse.performance.thisMonth} (${dashboardResponse.performance.growthPercentage.toStringAsFixed(1)}% crescimento)');
          debugPrint('   - Ranking: #${dashboardResponse.performance.ranking} de ${dashboardResponse.performance.totalUsers}');
          debugPrint('   - Gamificação: Nível ${dashboardResponse.gamification.level}, ${dashboardResponse.gamification.currentPoints} pontos');
          debugPrint('   - Conquistas: ${dashboardResponse.gamification.achievements.length}');
          debugPrint('   - Atividades recentes: ${dashboardResponse.recentActivities.length}');
          debugPrint('   - Próximos agendamentos: ${dashboardResponse.upcomingAppointments.length}');
          
          return ApiResponse.success(
            data: dashboardResponse,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [DASHBOARD API] Erro ao parsear resposta: $e');
          debugPrint('❌ [DASHBOARD API] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados do dashboard: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      debugPrint('❌ [DASHBOARD API] Resposta não foi bem-sucedida');
      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar dados do dashboard',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [DASHBOARD API] Erro de conexão: $e');
      debugPrint('❌ [DASHBOARD API] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}

