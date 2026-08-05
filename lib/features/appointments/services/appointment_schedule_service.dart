import 'package:flutter/foundation.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';

/// Regra de horários + disponibilidade do novo modelo da agenda — paridade
/// com `appointmentScheduleApi.ts` do imobx-front.
///
/// Datas trafegam como "relógio de parede" de Brasília (`YYYY-MM-DDTHH:mm`),
/// sem conversão de fuso — mesmo contrato do web.

// ─── Constantes de domínio (espelham o web) ──────────────────────────────────

const Map<int, String> kWeekdayLabels = {
  0: 'Domingo',
  1: 'Segunda-feira',
  2: 'Terça-feira',
  3: 'Quarta-feira',
  4: 'Quinta-feira',
  5: 'Sexta-feira',
  6: 'Sábado',
};

const Map<int, String> kWeekdayShortLabels = {
  0: 'Dom',
  1: 'Seg',
  2: 'Ter',
  3: 'Qua',
  4: 'Qui',
  5: 'Sex',
  6: 'Sáb',
};

/// Ordem de exibição segunda→domingo (WEEKDAY_ORDER do web).
const List<int> kWeekdayOrder = [1, 2, 3, 4, 5, 6, 0];

/// Opções de intervalo mínimo entre compromissos (chips do web).
const List<int> kGapOptions = [0, 15, 30, 45, 60, 90, 120];

/// Rótulo do gap: 0 → "Sem intervalo", 90 → "1h30", 60 → "1h", 30 → "30min".
String formatGapLabel(int minutes) {
  if (minutes <= 0) return 'Sem intervalo';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}min';
  if (m == 0) return '${h}h';
  return '${h}h${m.toString().padLeft(2, '0')}';
}

// ─── Models ──────────────────────────────────────────────────────────────────

class ScheduleInterval {
  /// 'HH:mm'
  final String start;
  final String end;

  const ScheduleInterval({required this.start, required this.end});

  factory ScheduleInterval.fromJson(Map<String, dynamic> json) {
    return ScheduleInterval(
      start: json['start']?.toString() ?? '08:00',
      end: json['end']?.toString() ?? '18:00',
    );
  }

  Map<String, dynamic> toJson() => {'start': start, 'end': end};

  ScheduleInterval copyWith({String? start, String? end}) =>
      ScheduleInterval(start: start ?? this.start, end: end ?? this.end);

  /// Minutos desde 00:00 — pra validar `end > start`.
  static int minutesOf(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  bool get isValid => minutesOf(end) > minutesOf(start);
}

class ScheduleDay {
  /// 0=domingo … 6=sábado (mesmo weekday do web).
  final int weekday;
  final bool enabled;
  final List<ScheduleInterval> intervals;

  const ScheduleDay({
    required this.weekday,
    required this.enabled,
    required this.intervals,
  });

  factory ScheduleDay.fromJson(Map<String, dynamic> json) {
    return ScheduleDay(
      weekday: (json['weekday'] as num?)?.toInt() ?? 0,
      enabled: json['enabled'] == true,
      intervals: (json['intervals'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => ScheduleInterval.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'weekday': weekday,
        'enabled': enabled,
        'intervals': intervals.map((e) => e.toJson()).toList(),
      };

  ScheduleDay copyWith({
    int? weekday,
    bool? enabled,
    List<ScheduleInterval>? intervals,
  }) =>
      ScheduleDay(
        weekday: weekday ?? this.weekday,
        enabled: enabled ?? this.enabled,
        intervals: intervals ?? this.intervals,
      );
}

/// DEFAULT_WEEKLY_HOURS do web: dom off; seg–sex 08:00–12:00 + 13:30–18:00;
/// sáb off mas com 09:00–13:00 pré-preenchido.
List<ScheduleDay> defaultWeeklyHours() => [
      const ScheduleDay(weekday: 0, enabled: false, intervals: []),
      for (var d = 1; d <= 5; d++)
        ScheduleDay(weekday: d, enabled: true, intervals: const [
          ScheduleInterval(start: '08:00', end: '12:00'),
          ScheduleInterval(start: '13:30', end: '18:00'),
        ]),
      const ScheduleDay(weekday: 6, enabled: false, intervals: [
        ScheduleInterval(start: '09:00', end: '13:00'),
      ]),
    ];

class ScheduleSettings {
  final String userId;
  final bool enforceWorkingHours;
  final List<ScheduleDay> weeklyHours;
  final int gapMinutes;
  final bool requireInviteConfirmation;

  /// `false` = usuário nunca salvou (primeira visita usa defaults).
  final bool configured;

  const ScheduleSettings({
    required this.userId,
    required this.enforceWorkingHours,
    required this.weeklyHours,
    required this.gapMinutes,
    required this.requireInviteConfirmation,
    required this.configured,
  });

  factory ScheduleSettings.fromJson(Map<String, dynamic> json) {
    return ScheduleSettings(
      userId: json['userId']?.toString() ?? '',
      enforceWorkingHours: json['enforceWorkingHours'] == true,
      weeklyHours: (json['weeklyHours'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => ScheduleDay.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      gapMinutes: (json['gapMinutes'] as num?)?.toInt() ?? 0,
      requireInviteConfirmation: json['requireInviteConfirmation'] == true,
      configured: json['configured'] == true,
    );
  }
}

class SaveScheduleSettingsPayload {
  final bool enforceWorkingHours;
  final int gapMinutes;
  final bool requireInviteConfirmation;
  final List<ScheduleDay> weeklyHours;

  const SaveScheduleSettingsPayload({
    required this.enforceWorkingHours,
    required this.gapMinutes,
    required this.requireInviteConfirmation,
    required this.weeklyHours,
  });

  Map<String, dynamic> toJson() => {
        'enforceWorkingHours': enforceWorkingHours,
        'gapMinutes': gapMinutes,
        'requireInviteConfirmation': requireInviteConfirmation,
        'weeklyHours': weeklyHours.map((e) => e.toJson()).toList(),
      };
}

/// Código do problema de disponibilidade (`AvailabilityIssueCode` do web).
/// `outside_working_hours` | `overlap` | `gap` — mantido cru + label pt-BR.
class AvailabilityIssue {
  final String code;
  final String message;
  final String? conflictAppointmentId;
  final String? conflictTitle;
  final String? conflictStart;
  final String? conflictEnd;

  const AvailabilityIssue({
    required this.code,
    required this.message,
    this.conflictAppointmentId,
    this.conflictTitle,
    this.conflictStart,
    this.conflictEnd,
  });

  factory AvailabilityIssue.fromJson(Map<String, dynamic> json) {
    return AvailabilityIssue(
      code: json['code']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      conflictAppointmentId: json['conflictAppointmentId']?.toString(),
      conflictTitle: json['conflictTitle']?.toString(),
      conflictStart: json['conflictStart']?.toString(),
      conflictEnd: json['conflictEnd']?.toString(),
    );
  }

  String get label {
    switch (code) {
      case 'outside_working_hours':
        return 'Fora da grade de horários';
      case 'overlap':
        return 'Conflito de agenda';
      case 'gap':
        return 'Sem intervalo mínimo';
      default:
        return message.isNotEmpty ? message : 'Indisponível';
    }
  }
}

class AvailabilityUserResult {
  final String userId;
  final String userName;
  final bool isOwner;
  final bool available;
  final List<AvailabilityIssue> issues;

  const AvailabilityUserResult({
    required this.userId,
    required this.userName,
    required this.isOwner,
    required this.available,
    required this.issues,
  });

  factory AvailabilityUserResult.fromJson(Map<String, dynamic> json) {
    return AvailabilityUserResult(
      userId: json['userId']?.toString() ?? '',
      userName: json['userName']?.toString() ?? '',
      isOwner: json['isOwner'] == true,
      available: json['available'] == true,
      issues: (json['issues'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => AvailabilityIssue.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class AvailabilityCheckResult {
  final bool available;
  final List<AvailabilityUserResult> results;

  const AvailabilityCheckResult({
    required this.available,
    required this.results,
  });

  factory AvailabilityCheckResult.fromJson(Map<String, dynamic> json) {
    return AvailabilityCheckResult(
      available: json['available'] == true,
      results: (json['results'] as List? ?? const [])
          .whereType<Map>()
          .map((e) =>
              AvailabilityUserResult.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  List<AvailabilityUserResult> get unavailable =>
      results.where((r) => !r.available).toList();
}

class AvailabilitySlot {
  /// 'HH:mm'
  final String time;
  final bool available;
  final String? reason;

  /// Nomes de quem está ocupado nesse horário.
  final List<String> blockedFor;

  const AvailabilitySlot({
    required this.time,
    required this.available,
    this.reason,
    required this.blockedFor,
  });

  factory AvailabilitySlot.fromJson(Map<String, dynamic> json) {
    return AvailabilitySlot(
      time: json['time']?.toString() ?? '',
      available: json['available'] == true,
      reason: json['reason']?.toString(),
      blockedFor: (json['blockedFor'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

class AvailabilitySlotsResult {
  final String date;
  final int durationMinutes;
  final List<AvailabilitySlot> slots;

  const AvailabilitySlotsResult({
    required this.date,
    required this.durationMinutes,
    required this.slots,
  });

  factory AvailabilitySlotsResult.fromJson(Map<String, dynamic> json) {
    return AvailabilitySlotsResult(
      date: json['date']?.toString() ?? '',
      durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 0,
      slots: (json['slots'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => AvailabilitySlot.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

// ─── Service ─────────────────────────────────────────────────────────────────

class AppointmentScheduleService {
  AppointmentScheduleService._();

  static final AppointmentScheduleService instance =
      AppointmentScheduleService._();
  final ApiService _api = ApiService.instance;

  Map<String, dynamic>? _unwrap(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      final inner = raw['data'];
      if (inner is Map<String, dynamic>) return inner;
      if (inner is Map) return Map<String, dynamic>.from(inner);
      return raw;
    }
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  /// `GET /appointments/schedule-settings` — grade do usuário logado.
  Future<ApiResponse<ScheduleSettings>> getScheduleSettings() async {
    try {
      final res = await _api
          .get<dynamic>(ApiConstants.appointmentScheduleSettings);
      final body = _unwrap(res.data);
      if (res.success && body != null) {
        return ApiResponse.success(
          data: ScheduleSettings.fromJson(body),
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.error(
        message: res.message ?? 'Erro ao carregar horários',
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [SCHEDULE] getScheduleSettings: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `PUT /appointments/schedule-settings`.
  Future<ApiResponse<ScheduleSettings>> saveScheduleSettings(
    SaveScheduleSettingsPayload payload,
  ) async {
    try {
      final res = await _api.put<dynamic>(
        ApiConstants.appointmentScheduleSettings,
        body: payload.toJson(),
      );
      final body = _unwrap(res.data);
      if (res.success && body != null) {
        return ApiResponse.success(
          data: ScheduleSettings.fromJson(body),
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.error(
        message: res.message ?? 'Erro ao salvar horários',
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [SCHEDULE] saveScheduleSettings: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /appointments/availability/check` — o par início/fim vale para
  /// dono + convidados? Datas em "relógio de parede" `YYYY-MM-DDTHH:mm`.
  /// Na EDIÇÃO, `excludeAppointmentId` é OBRIGATÓRIO (senão o compromisso
  /// colide consigo mesmo).
  Future<ApiResponse<AvailabilityCheckResult>> checkAvailability({
    required String startDate,
    required String endDate,
    List<String>? userIds,
    String? excludeAppointmentId,
  }) async {
    try {
      final res = await _api.post<dynamic>(
        ApiConstants.appointmentAvailabilityCheck,
        body: {
          'startDate': startDate,
          'endDate': endDate,
          if (userIds != null && userIds.isNotEmpty) 'userIds': userIds,
          if (excludeAppointmentId != null &&
              excludeAppointmentId.isNotEmpty)
            'excludeAppointmentId': excludeAppointmentId,
        },
      );
      final body = _unwrap(res.data);
      if (res.success && body != null) {
        return ApiResponse.success(
          data: AvailabilityCheckResult.fromJson(body),
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.error(
        message: res.message ?? 'Erro ao verificar disponibilidade',
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [SCHEDULE] checkAvailability: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /appointments/availability/slots` — slots de INÍCIO do dia
  /// (malha de 15min) com quem está ocupado em cada um.
  Future<ApiResponse<AvailabilitySlotsResult>> getDaySlots({
    required String date,
    required int durationMinutes,
    List<String>? userIds,
    String? excludeAppointmentId,
  }) async {
    try {
      final params = <String, String>{
        'date': date,
        'durationMinutes': durationMinutes.toString(),
        if (userIds != null && userIds.isNotEmpty)
          'userIds': userIds.join(','),
        if (excludeAppointmentId != null && excludeAppointmentId.isNotEmpty)
          'excludeAppointmentId': excludeAppointmentId,
      };
      final res = await _api.get<dynamic>(
        ApiConstants.appointmentAvailabilitySlots,
        queryParameters: params,
      );
      final body = _unwrap(res.data);
      if (res.success && body != null) {
        return ApiResponse.success(
          data: AvailabilitySlotsResult.fromJson(body),
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.error(
        message: res.message ?? 'Erro ao carregar horários do dia',
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [SCHEDULE] getDaySlots: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}
