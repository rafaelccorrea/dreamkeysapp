import 'package:flutter/foundation.dart';
import 'api_service.dart';

/// Modelo do check-in retornado pela API.
class CheckIn {
  final String id;
  final String companyId;
  final String userId;
  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime checkedInAt;
  final DateTime expiresAt;
  final DateTime? checkedOutAt;
  /// `self`, `manager` ou `system` (auto-expirado pelo cron).
  final String? checkedOutByType;
  final String? checkedOutByUserId;
  final CheckInUser? checkedOutByUser;
  final DateTime createdAt;
  final CheckInUser? user;

  CheckIn({
    required this.id,
    required this.companyId,
    required this.userId,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    required this.checkedInAt,
    required this.expiresAt,
    this.checkedOutAt,
    this.checkedOutByType,
    this.checkedOutByUserId,
    this.checkedOutByUser,
    required this.createdAt,
    this.user,
  });

  /// Está vigente (não saiu e não expirou).
  bool get isActive {
    if (checkedOutAt != null) return false;
    return DateTime.now().isBefore(expiresAt);
  }

  /// Rótulo amigável para "quem encerrou" — paridade com `getCheckedOutByLabel`
  /// do web (`imobx-front/src/services/checkInApi.ts`).
  String get checkedOutByLabel {
    if (checkedOutAt == null) return '—';
    switch (checkedOutByType) {
      case 'self':
        return 'Próprio usuário';
      case 'manager':
        final name = checkedOutByUser?.name;
        return name != null && name.isNotEmpty ? 'Gestor: $name' : 'Gestor';
      case 'system':
        return 'Sistema (expiração)';
      default:
        return '—';
    }
  }

  factory CheckIn.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0.0;
      return 0.0;
    }

    double? parseDoubleOrNull(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    DateTime parseDate(dynamic v) {
      if (v is DateTime) return v;
      if (v is String) {
        return DateTime.tryParse(v) ?? DateTime.fromMillisecondsSinceEpoch(0);
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    DateTime? parseDateOrNull(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
      return null;
    }

    return CheckIn(
      id: json['id']?.toString() ?? '',
      companyId:
          json['companyId']?.toString() ?? json['company_id']?.toString() ?? '',
      userId:
          json['userId']?.toString() ?? json['user_id']?.toString() ?? '',
      latitude: parseDouble(json['latitude']),
      longitude: parseDouble(json['longitude']),
      accuracy: parseDoubleOrNull(json['accuracy']),
      checkedInAt: parseDate(json['checkedInAt'] ?? json['checked_in_at']),
      expiresAt: parseDate(json['expiresAt'] ?? json['expires_at']),
      checkedOutAt:
          parseDateOrNull(json['checkedOutAt'] ?? json['checked_out_at']),
      checkedOutByType: json['checkedOutByType']?.toString() ??
          json['checked_out_by_type']?.toString(),
      checkedOutByUserId: json['checkedOutByUserId']?.toString() ??
          json['checked_out_by_user_id']?.toString(),
      checkedOutByUser: json['checkedOutByUser'] is Map
          ? CheckInUser.fromJson(
              Map<String, dynamic>.from(json['checkedOutByUser']))
          : null,
      createdAt: parseDate(json['createdAt'] ?? json['created_at']),
      user: json['user'] is Map
          ? CheckInUser.fromJson(Map<String, dynamic>.from(json['user']))
          : null,
    );
  }
}

/// Mini representação do usuário associado a um check-in.
class CheckInUser {
  final String id;
  final String? name;
  final String? email;
  final String? avatar;

  const CheckInUser({
    required this.id,
    this.name,
    this.email,
    this.avatar,
  });

  factory CheckInUser.fromJson(Map<String, dynamic> json) {
    return CheckInUser(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString(),
      email: json['email']?.toString(),
      avatar: json['avatar']?.toString(),
    );
  }
}

/// Configurações de check-in da empresa.
class CheckInSettings {
  final String id;
  final String companyId;
  final bool enabled;
  final int radiusMeters;
  final double durationHours;
  final CheckInCompany? company;

  const CheckInSettings({
    required this.id,
    required this.companyId,
    required this.enabled,
    required this.radiusMeters,
    required this.durationHours,
    this.company,
  });

  factory CheckInSettings.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0.0;
      return 0.0;
    }

    int parseInt(dynamic v) {
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    return CheckInSettings(
      id: json['id']?.toString() ?? '',
      companyId:
          json['companyId']?.toString() ?? json['company_id']?.toString() ?? '',
      enabled: json['enabled'] as bool? ?? false,
      radiusMeters: parseInt(json['radiusMeters'] ?? json['radius_meters']),
      durationHours: parseDouble(json['durationHours'] ?? json['duration_hours']),
      company: json['company'] is Map
          ? CheckInCompany.fromJson(Map<String, dynamic>.from(json['company']))
          : null,
    );
  }
}

class CheckInCompany {
  final String id;
  final String? name;
  final double? latitude;
  final double? longitude;
  final String? address;

  const CheckInCompany({
    required this.id,
    this.name,
    this.latitude,
    this.longitude,
    this.address,
  });

  factory CheckInCompany.fromJson(Map<String, dynamic> json) {
    double? parseDoubleOrNull(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    return CheckInCompany(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString(),
      latitude: parseDoubleOrNull(json['latitude']),
      longitude: parseDoubleOrNull(json['longitude']),
      address: json['address']?.toString(),
    );
  }
}

/// Resposta paginada da lista de check-ins.
class CheckInListResponse {
  final List<CheckIn> data;
  final int total;
  final int page;
  final int limit;
  final int totalPages;

  const CheckInListResponse({
    required this.data,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });

  static const empty = CheckInListResponse(
    data: [],
    total: 0,
    page: 1,
    limit: 20,
    totalPages: 0,
  );

  factory CheckInListResponse.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic v) {
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    final dataRaw = json['data'];
    final data = dataRaw is List
        ? dataRaw
            .whereType<Map>()
            .map((e) => CheckIn.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <CheckIn>[];
    return CheckInListResponse(
      data: data,
      total: parseInt(json['total']),
      page: parseInt(json['page']),
      limit: parseInt(json['limit']),
      totalPages: parseInt(json['totalPages'] ?? json['total_pages']),
    );
  }
}

/// Cliente HTTP de check-in — paridade com `imobx-front/src/services/checkInApi.ts`.
class CheckInService {
  CheckInService._();
  static final CheckInService instance = CheckInService._();
  final ApiService _api = ApiService.instance;

  /// `POST /check-in` — registra check-in usando lat/lon do dispositivo.
  /// O backend valida raio + duplicidade; em caso de raio, lança 400 com
  /// `message` legível.
  Future<ApiResponse<CheckIn>> doCheckIn({
    required double latitude,
    required double longitude,
    double? accuracy,
  }) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        '/check-in',
        body: {
          'latitude': latitude,
          'longitude': longitude,
          if (accuracy != null) 'accuracy': accuracy,
        },
      );
      if (response.success && response.data != null) {
        try {
          return ApiResponse.success(
            data: CheckIn.fromJson(response.data!),
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [CHECK_IN] erro parseando resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar resposta do servidor.',
            statusCode: response.statusCode,
          );
        }
      }
      return ApiResponse.error(
        message: response.message ?? 'Não foi possível fazer check-in.',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [CHECK_IN] erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: $e',
        statusCode: 0,
      );
    }
  }

  /// `POST /check-in/check-out` — encerra o check-in ativo do próprio usuário.
  Future<ApiResponse<CheckIn>> doCheckOut() async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        '/check-in/check-out',
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: CheckIn.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Não foi possível fazer check-out.',
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(
        message: 'Erro de conexão: $e',
        statusCode: 0,
      );
    }
  }

  /// `POST /check-in/:id/undo` — gestor força check-out de outro usuário.
  /// Requer `check_in:manage_settings`.
  Future<ApiResponse<CheckIn>> undoCheckIn(String checkInId) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        '/check-in/$checkInId/undo',
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: CheckIn.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Não foi possível desfazer o check-in.',
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(
        message: 'Erro de conexão: $e',
        statusCode: 0,
      );
    }
  }

  /// `GET /check-in/active` — retorna o check-in ativo do próprio usuário,
  /// `null` se não houver (backend devolve 200 null).
  Future<ApiResponse<CheckIn?>> getActiveCheckIn() async {
    try {
      final response = await _api.get<dynamic>('/check-in/active');
      if (response.success) {
        final raw = response.data;
        if (raw == null || raw is! Map) {
          return ApiResponse.success(
            data: null,
            statusCode: response.statusCode,
          );
        }
        return ApiResponse.success(
          data: CheckIn.fromJson(Map<String, dynamic>.from(raw)),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar check-in ativo.',
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(
        message: 'Erro de conexão: $e',
        statusCode: 0,
      );
    }
  }

  /// `GET /check-in?scope=...&page=...` — lista de check-ins paginada.
  /// `scope`: `mine` (próprios) ou `all` (todos da empresa, requer
  /// `check_in:view` com escopo de gestão).
  Future<ApiResponse<CheckInListResponse>> listCheckIns({
    String scope = 'mine',
    String? fromDate,
    String? toDate,
    String? userId,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final params = <String, String>{
        'scope': scope,
        'page': page.toString(),
        'limit': limit.toString(),
      };
      if (fromDate != null && fromDate.isNotEmpty) {
        params['fromDate'] = fromDate;
      }
      if (toDate != null && toDate.isNotEmpty) {
        params['toDate'] = toDate;
      }
      if (userId != null && userId.isNotEmpty) {
        params['userId'] = userId;
      }
      final qs = params.entries
          .map((e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      final response = await _api.get<Map<String, dynamic>>('/check-in?$qs');
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: CheckInListResponse.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao listar check-ins.',
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(
        message: 'Erro de conexão: $e',
        statusCode: 0,
      );
    }
  }

  /// `GET /check-in/settings` — configurações da empresa.
  Future<ApiResponse<CheckInSettings>> getSettings() async {
    try {
      final response =
          await _api.get<Map<String, dynamic>>('/check-in/settings');
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: CheckInSettings.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar configurações.',
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(
        message: 'Erro de conexão: $e',
        statusCode: 0,
      );
    }
  }
}
