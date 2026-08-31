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
      userId: json['userId']?.toString() ?? json['user_id']?.toString() ?? '',
      latitude: parseDouble(json['latitude']),
      longitude: parseDouble(json['longitude']),
      accuracy: parseDoubleOrNull(json['accuracy']),
      checkedInAt: parseDate(json['checkedInAt'] ?? json['checked_in_at']),
      expiresAt: parseDate(json['expiresAt'] ?? json['expires_at']),
      checkedOutAt: parseDateOrNull(
        json['checkedOutAt'] ?? json['checked_out_at'],
      ),
      checkedOutByType:
          json['checkedOutByType']?.toString() ??
          json['checked_out_by_type']?.toString(),
      checkedOutByUserId:
          json['checkedOutByUserId']?.toString() ??
          json['checked_out_by_user_id']?.toString(),
      checkedOutByUser: json['checkedOutByUser'] is Map
          ? CheckInUser.fromJson(
              Map<String, dynamic>.from(json['checkedOutByUser']),
            )
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

  const CheckInUser({required this.id, this.name, this.email, this.avatar});

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

  /// Minutos antes de expirar em que o usuário é avisado.
  final int expiryWarningMinutes;

  /// A distribuição automática de leads favorece quem tem check-in vigente.
  final bool leadPriorityEnabled;

  /// `prefer` = presentes primeiro com fallback; `exclusive` = só presentes.
  final String leadPriorityMode;

  /// Janelas por dia (`mon`..`sun`). `null` = empresa nunca configurou, então
  /// o check-in vale a qualquer hora. Dia com lista vazia = dia sem check-in.
  final Map<String, List<CheckInWindow>>? windows;

  /// Fuso IANA em que as janelas são avaliadas (relógio do servidor).
  final String timezone;

  /// Ao fim de cada janela, distribuir a fila de leads para quem fez check-in.
  final bool autoDistributeOnWindowEnd;

  /// Teto de leads por usuário por rodada automática. `null` = sem teto.
  final int? maxAutoPerUserPerRun;

  /// Só quem fez check-in DENTRO da janela encerrada entra na rodada.
  final bool windowCheckInOnly;

  /// Check-in de sábado vale como presença até domingo 23:59.
  final bool weekendUsesSaturdayCheckIn;

  /// Dias extras de bloqueio por equipe: `{ [teamId]: ['tue'] }`.
  final Map<String, List<String>>? teamBlockDays;

  final CheckInCompany? company;

  const CheckInSettings({
    required this.id,
    required this.companyId,
    required this.enabled,
    required this.radiusMeters,
    required this.durationHours,
    this.expiryWarningMinutes = 15,
    this.leadPriorityEnabled = false,
    this.leadPriorityMode = 'prefer',
    this.windows,
    this.timezone = 'America/Sao_Paulo',
    this.autoDistributeOnWindowEnd = false,
    this.maxAutoPerUserPerRun,
    this.windowCheckInOnly = false,
    this.weekendUsesSaturdayCheckIn = false,
    this.teamBlockDays,
    this.company,
  });

  /// A empresa restringe horário de check-in.
  bool get hasWindows => windows != null;

  /// Janelas de um dia (`mon`..`sun`); vazio = dia sem check-in.
  List<CheckInWindow> windowsFor(String weekday) =>
      windows?[weekday] ?? const [];

  /// A presença influencia a distribuição de leads de alguma forma — é o que
  /// justifica insistir no check-in para o corretor.
  bool get affectsLeadDistribution =>
      enabled && (leadPriorityEnabled || autoDistributeOnWindowEnd);

  factory CheckInSettings.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0.0;
      return 0.0;
    }

    int parseInt(dynamic v, [int fallback = 0]) {
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    int? parseIntOrNull(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    Map<String, List<CheckInWindow>>? parseWindows(dynamic raw) {
      if (raw is! Map) return null;
      final out = <String, List<CheckInWindow>>{};
      for (final key in kCheckInWeekdayOrder) {
        out[key] = CheckInWindow.listFrom(raw[key]);
      }
      return out;
    }

    Map<String, List<String>>? parseTeamBlockDays(dynamic raw) {
      if (raw is! Map) return null;
      final out = <String, List<String>>{};
      raw.forEach((key, value) {
        if (value is List) {
          out[key.toString()] = value
              .map((e) => e.toString())
              .toList(growable: false);
        }
      });
      return out;
    }

    return CheckInSettings(
      id: json['id']?.toString() ?? '',
      companyId:
          json['companyId']?.toString() ?? json['company_id']?.toString() ?? '',
      enabled: json['enabled'] as bool? ?? false,
      radiusMeters: parseInt(json['radiusMeters'] ?? json['radius_meters']),
      durationHours: parseDouble(
        json['durationHours'] ?? json['duration_hours'],
      ),
      expiryWarningMinutes: parseInt(
        json['expiryWarningMinutes'] ?? json['expiry_warning_minutes'],
        15,
      ),
      leadPriorityEnabled:
          (json['leadPriorityEnabled'] ?? json['lead_priority_enabled'])
              as bool? ??
          false,
      leadPriorityMode:
          (json['leadPriorityMode'] ?? json['lead_priority_mode'])
              ?.toString() ??
          'prefer',
      windows: parseWindows(json['windows']),
      timezone: json['timezone']?.toString() ?? 'America/Sao_Paulo',
      autoDistributeOnWindowEnd:
          (json['autoDistributeOnWindowEnd'] ??
                  json['auto_distribute_on_window_end'])
              as bool? ??
          false,
      maxAutoPerUserPerRun: parseIntOrNull(
        json['maxAutoPerUserPerRun'] ?? json['max_auto_per_user_per_run'],
      ),
      windowCheckInOnly:
          (json['windowCheckInOnly'] ?? json['window_check_in_only'])
              as bool? ??
          false,
      weekendUsesSaturdayCheckIn:
          (json['weekendUsesSaturdayCheckIn'] ??
                  json['weekend_uses_saturday_check_in'])
              as bool? ??
          false,
      teamBlockDays: parseTeamBlockDays(
        json['teamBlockDays'] ?? json['team_block_days'],
      ),
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

/// Ordem e rótulos dos dias da semana usados pelas janelas de check-in.
/// Espelha `WEEKDAY_ORDER` / `WEEKDAY_LABEL` de `checkInApi.ts` no web.
const List<String> kCheckInWeekdayOrder = [
  'mon',
  'tue',
  'wed',
  'thu',
  'fri',
  'sat',
  'sun',
];

const Map<String, String> kCheckInWeekdayLabels = {
  'mon': 'Segunda',
  'tue': 'Terça',
  'wed': 'Quarta',
  'thu': 'Quinta',
  'fri': 'Sexta',
  'sat': 'Sábado',
  'sun': 'Domingo',
};

/// Forma longa usada nas frases ("você não fez check-in na segunda-feira").
const Map<String, String> kCheckInWeekdayLabelsLong = {
  'mon': 'segunda-feira',
  'tue': 'terça-feira',
  'wed': 'quarta-feira',
  'thu': 'quinta-feira',
  'fri': 'sexta-feira',
  'sat': 'sábado',
  'sun': 'domingo',
};

/// Janela de horário em que o check-in é aceito. `HH:mm`, fim INCLUSIVO no
/// minuto (08:00–09:00 aceita 09:00:59 e recusa 09:01).
class CheckInWindow {
  final String start;
  final String end;

  const CheckInWindow({required this.start, required this.end});

  /// Rótulo curto para chip/linha ("08:00–09:00").
  String get label => '$start–$end';

  factory CheckInWindow.fromJson(Map<String, dynamic> json) => CheckInWindow(
    start: json['start']?.toString() ?? '',
    end: json['end']?.toString() ?? '',
  );

  static List<CheckInWindow> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => CheckInWindow.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}

/// Próxima janela disponível (hoje ou em outro dia).
class CheckInNextWindow {
  final String weekday;
  final CheckInWindow window;
  final bool isToday;

  const CheckInNextWindow({
    required this.weekday,
    required this.window,
    required this.isToday,
  });

  String get weekdayLabel => kCheckInWeekdayLabels[weekday] ?? weekday;

  factory CheckInNextWindow.fromJson(Map<String, dynamic> json) {
    return CheckInNextWindow(
      weekday: json['weekday']?.toString() ?? '',
      window: json['window'] is Map
          ? CheckInWindow.fromJson(Map<String, dynamic>.from(json['window']))
          : const CheckInWindow(start: '', end: ''),
      isToday: json['isToday'] as bool? ?? false,
    );
  }
}

/// Liberação concedida pelo gestor para fazer check-in fora da janela
/// (`check_in_exceptions` no backend). Vale no máximo 24h e é consumida no
/// primeiro check-in.
class CheckInExceptionGrant {
  final String id;
  final DateTime? validUntil;
  final String? note;

  const CheckInExceptionGrant({required this.id, this.validUntil, this.note});

  factory CheckInExceptionGrant.fromJson(Map<String, dynamic> json) {
    return CheckInExceptionGrant(
      id: json['id']?.toString() ?? '',
      validUntil: json['validUntil'] is String
          ? DateTime.tryParse(json['validUntil'] as String)
          : null,
      note: json['note']?.toString(),
    );
  }
}

/// Bloqueio semanal: quem não fez check-in no dia obrigatório fica travado
/// até domingo. O dia vem embutido em `reason` (`no_mon_checkin`,
/// `no_tue_checkin`… para as regras por equipe).
class CheckInBlock {
  final String id;
  final String userId;
  final String weekStart;
  final String reason;
  final String? releasedBy;
  final DateTime? releasedAt;
  final String? releaseReason;
  final DateTime? createdAt;
  final CheckInUser? user;
  final CheckInUser? releasedByUser;

  const CheckInBlock({
    required this.id,
    required this.userId,
    required this.weekStart,
    required this.reason,
    this.releasedBy,
    this.releasedAt,
    this.releaseReason,
    this.createdAt,
    this.user,
    this.releasedByUser,
  });

  bool get isReleased => releasedAt != null;

  /// Dia da semana que originou o bloqueio (`no_tue_checkin` → `tue`).
  String? get weekdayKey {
    final m = RegExp(r'^no_([a-z]{3})_checkin$').firstMatch(reason);
    final key = m?.group(1);
    return key != null && kCheckInWeekdayOrder.contains(key) ? key : null;
  }

  /// "terça-feira" — usado nas frases do motivo.
  String? get weekdayLabel {
    final key = weekdayKey;
    return key == null ? null : kCheckInWeekdayLabelsLong[key];
  }

  /// Frase pronta do motivo do bloqueio.
  String get reasonLabel {
    final dia = weekdayLabel;
    return dia == null
        ? 'Sem check-in no dia obrigatório'
        : 'Sem check-in na $dia';
  }

  factory CheckInBlock.fromJson(Map<String, dynamic> json) {
    DateTime? parseDateOrNull(dynamic v) {
      if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
      return null;
    }

    return CheckInBlock(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? json['user_id']?.toString() ?? '',
      weekStart:
          json['weekStart']?.toString() ?? json['week_start']?.toString() ?? '',
      reason: json['reason']?.toString() ?? '',
      releasedBy: json['releasedBy']?.toString(),
      releasedAt: parseDateOrNull(json['releasedAt'] ?? json['released_at']),
      releaseReason: json['releaseReason']?.toString(),
      createdAt: parseDateOrNull(json['createdAt'] ?? json['created_at']),
      user: json['user'] is Map
          ? CheckInUser.fromJson(Map<String, dynamic>.from(json['user']))
          : null,
      releasedByUser: json['releasedByUser'] is Map
          ? CheckInUser.fromJson(
              Map<String, dynamic>.from(json['releasedByUser']),
            )
          : null,
    );
  }
}

/// Rótulos das ações registradas na auditoria de check-in.
const Map<String, String> kCheckInAuditLabels = {
  'force_check_in': 'Check-in registrado pelo gestor',
  'grant_exception': 'Liberação fora do horário',
  'unblock': 'Bloqueio liberado',
  'weekly_block': 'Bloqueio semanal (sem check-in no dia obrigatório)',
  'undo_check_in': 'Check-in desfeito',
};

/// Uma linha do histórico de ações do gestor/sistema sobre check-ins.
class CheckInAuditEntry {
  final String id;
  final String action;
  final String targetUserId;
  final String? actorId;
  final Map<String, dynamic>? payload;
  final DateTime? createdAt;
  final CheckInUser? actor;
  final CheckInUser? targetUser;

  const CheckInAuditEntry({
    required this.id,
    required this.action,
    required this.targetUserId,
    this.actorId,
    this.payload,
    this.createdAt,
    this.actor,
    this.targetUser,
  });

  String get actionLabel => kCheckInAuditLabels[action] ?? action;

  /// Ação do sistema (cron) não tem gestor por trás.
  bool get isSystem => actorId == null || actorId!.isEmpty;

  /// Observação que o gestor escreveu ao agir, quando houver.
  String? get note {
    final raw = payload?['note'] ?? payload?['reason'];
    final s = raw?.toString().trim();
    return s == null || s.isEmpty ? null : s;
  }

  factory CheckInAuditEntry.fromJson(Map<String, dynamic> json) {
    return CheckInAuditEntry(
      id: json['id']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      targetUserId: json['targetUserId']?.toString() ?? '',
      actorId: json['actorId']?.toString(),
      payload: json['payload'] is Map
          ? Map<String, dynamic>.from(json['payload'])
          : null,
      createdAt: json['createdAt'] is String
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      actor: json['actor'] is Map
          ? CheckInUser.fromJson(Map<String, dynamic>.from(json['actor']))
          : null,
      targetUser: json['targetUser'] is Map
          ? CheckInUser.fromJson(Map<String, dynamic>.from(json['targetUser']))
          : null,
    );
  }
}

/// Por que o check-in não pode ser feito agora (`reasonCannot` do backend).
enum CheckInBlockedReason {
  /// Empresa não habilitou check-in por localização.
  disabled,

  /// Já existe um check-in vigente — o botão vira "check-out".
  alreadyActive,

  /// Bloqueio semanal por falta de check-in no dia obrigatório.
  blocked,

  /// Fora da janela de horário e sem liberação do gestor.
  outsideWindow;

  static CheckInBlockedReason? tryParse(String? raw) {
    switch (raw) {
      case 'disabled':
        return CheckInBlockedReason.disabled;
      case 'already_active':
        return CheckInBlockedReason.alreadyActive;
      case 'blocked':
        return CheckInBlockedReason.blocked;
      case 'outside_window':
        return CheckInBlockedReason.outsideWindow;
      default:
        return null;
    }
  }
}

/// `GET /check-in/status` — a fonte de verdade sobre o que o usuário pode
/// fazer AGORA: janela vigente/próxima, bloqueio semanal, liberação do gestor
/// e check-in ativo. O relógio é o do servidor, no fuso da empresa — por isso
/// a tela reconsulta a cada minuto em vez de calcular no aparelho.
class CheckInStatus {
  final bool enabled;
  final String timezone;
  final DateTime? serverTime;

  /// Hora local da empresa em `HH:mm` (não é a hora do aparelho).
  final String localTime;
  final String weekday;

  /// `false` = empresa não configurou janelas (check-in a qualquer hora).
  final bool windowsRestricted;
  final bool insideWindow;
  final CheckInWindow? currentWindow;
  final CheckInNextWindow? nextWindow;
  final List<CheckInWindow> todayWindows;
  final String? nextWindowText;
  final bool blocked;
  final CheckInBlock? block;
  final CheckInExceptionGrant? exception;
  final CheckIn? activeCheckIn;
  final bool canCheckInNow;
  final CheckInBlockedReason? reasonCannot;

  const CheckInStatus({
    required this.enabled,
    required this.timezone,
    this.serverTime,
    required this.localTime,
    required this.weekday,
    required this.windowsRestricted,
    required this.insideWindow,
    this.currentWindow,
    this.nextWindow,
    this.todayWindows = const [],
    this.nextWindowText,
    required this.blocked,
    this.block,
    this.exception,
    this.activeCheckIn,
    required this.canCheckInNow,
    this.reasonCannot,
  });

  String get weekdayLabel => kCheckInWeekdayLabels[weekday] ?? weekday;

  /// Há uma liberação do gestor ainda válida.
  bool get hasUsableException {
    final until = exception?.validUntil;
    return until != null && until.isAfter(DateTime.now());
  }

  /// Texto do motivo pelo qual o botão de check-in está travado
  /// (`null` = liberado, ou já existe check-in ativo e o botão vira check-out).
  ///
  /// Paridade com `blockedReason` do `CheckInPage.tsx`, com uma correção: o
  /// dia sai do próprio bloqueio, então uma regra de equipe (ex.: terça) não
  /// aparece como "segunda-feira".
  String? get lockedReason {
    switch (reasonCannot) {
      case CheckInBlockedReason.blocked:
        final dia = block?.weekdayLabel;
        return dia == null
            ? 'Você está bloqueado nesta semana por falta de check-in. Peça a liberação ao seu gestor.'
            : 'Você não fez check-in na $dia e está bloqueado nesta semana. Peça a liberação ao seu gestor.';
      case CheckInBlockedReason.outsideWindow:
        final proximo = nextWindowText?.trim();
        final agora = 'Fora do horário de check-in (agora $localTime).';
        return proximo == null || proximo.isEmpty ? agora : '$agora $proximo';
      case CheckInBlockedReason.disabled:
        return 'O check-in por localização não está habilitado para esta empresa.';
      case CheckInBlockedReason.alreadyActive:
      case null:
        return null;
    }
  }

  factory CheckInStatus.fromJson(Map<String, dynamic> json) {
    return CheckInStatus(
      enabled: json['enabled'] as bool? ?? false,
      timezone: json['timezone']?.toString() ?? 'America/Sao_Paulo',
      serverTime: json['serverTime'] is String
          ? DateTime.tryParse(json['serverTime'] as String)
          : null,
      localTime: json['localTime']?.toString() ?? '',
      weekday: json['weekday']?.toString() ?? '',
      windowsRestricted: json['windowsRestricted'] as bool? ?? false,
      insideWindow: json['insideWindow'] as bool? ?? true,
      currentWindow: json['currentWindow'] is Map
          ? CheckInWindow.fromJson(
              Map<String, dynamic>.from(json['currentWindow']),
            )
          : null,
      nextWindow: json['nextWindow'] is Map
          ? CheckInNextWindow.fromJson(
              Map<String, dynamic>.from(json['nextWindow']),
            )
          : null,
      todayWindows: CheckInWindow.listFrom(json['todayWindows']),
      nextWindowText: json['nextWindowText']?.toString(),
      blocked: json['blocked'] as bool? ?? false,
      block: json['block'] is Map
          ? CheckInBlock.fromJson(Map<String, dynamic>.from(json['block']))
          : null,
      exception: json['exception'] is Map
          ? CheckInExceptionGrant.fromJson(
              Map<String, dynamic>.from(json['exception']),
            )
          : null,
      activeCheckIn: json['activeCheckIn'] is Map
          ? CheckIn.fromJson(Map<String, dynamic>.from(json['activeCheckIn']))
          : null,
      canCheckInNow: json['canCheckInNow'] as bool? ?? false,
      reasonCannot: CheckInBlockedReason.tryParse(
        json['reasonCannot']?.toString(),
      ),
    );
  }
}

/// `GET /check-in/visible-users` — o recorte é decidido no servidor:
/// admin/master vê a empresa, gestor vê a equipe, os demais só a si.
class CheckInVisibleUsers {
  /// `all`, `team` ou `self`.
  final String scope;
  final List<CheckInUser> users;

  const CheckInVisibleUsers({required this.scope, required this.users});

  static const empty = CheckInVisibleUsers(scope: 'self', users: []);

  /// O usuário enxerga mais gente do que só ele mesmo.
  bool get isManagerScope => scope == 'all' || scope == 'team';

  factory CheckInVisibleUsers.fromJson(Map<String, dynamic> json) {
    final raw = json['users'];
    return CheckInVisibleUsers(
      scope: json['scope']?.toString() ?? 'self',
      users: raw is List
          ? raw
                .whereType<Map>()
                .map((e) => CheckInUser.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
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
      return ApiResponse.error(message: 'Erro de conexão: $e', statusCode: 0);
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
      return ApiResponse.error(message: 'Erro de conexão: $e', statusCode: 0);
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
      return ApiResponse.error(message: 'Erro de conexão: $e', statusCode: 0);
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
      return ApiResponse.error(message: 'Erro de conexão: $e', statusCode: 0);
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
    String? status,
    String? closedBy,
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
      if (status != null && status.isNotEmpty) {
        params['status'] = status;
      }
      if (closedBy != null && closedBy.isNotEmpty) {
        params['closedBy'] = closedBy;
      }
      final qs = params.entries
          .map(
            (e) =>
                '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
          )
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
      return ApiResponse.error(message: 'Erro de conexão: $e', statusCode: 0);
    }
  }

  /// `GET /check-in/settings` — configurações da empresa.
  Future<ApiResponse<CheckInSettings>> getSettings() async {
    try {
      final response = await _api.get<Map<String, dynamic>>(
        '/check-in/settings',
      );
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
      return ApiResponse.error(message: 'Erro de conexão: $e', statusCode: 0);
    }
  }

  /// `GET /check-in/status` — o que o usuário pode fazer AGORA.
  ///
  /// É a chamada que carrega as regras novas (janelas de horário, bloqueio
  /// semanal e liberação do gestor). Sem ela a tela só descobre o problema
  /// depois de tentar e levar 400 do backend.
  Future<ApiResponse<CheckInStatus>> getStatus() async {
    try {
      final response = await _api.get<Map<String, dynamic>>('/check-in/status');
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: CheckInStatus.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar o status do check-in.',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [CHECK_IN] erro no status: $e');
      return ApiResponse.error(message: 'Erro de conexão: $e', statusCode: 0);
    }
  }

  /// `GET /check-in/visible-users` — quem o usuário pode ver/filtrar.
  /// O recorte é decidido no servidor; o app apenas obedece.
  Future<ApiResponse<CheckInVisibleUsers>> getVisibleUsers() async {
    try {
      final response = await _api.get<Map<String, dynamic>>(
        '/check-in/visible-users',
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: CheckInVisibleUsers.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar o escopo de equipe.',
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'Erro de conexão: $e', statusCode: 0);
    }
  }

  /// `POST /check-in/force` — gestor registra o check-in pelo colaborador,
  /// ignorando janela, raio e bloqueio. Requer `check_in:manage_settings`.
  Future<ApiResponse<CheckIn>> forceCheckIn({
    required String userId,
    String? note,
  }) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        '/check-in/force',
        body: {
          'userId': userId,
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        },
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: CheckIn.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Não foi possível registrar o check-in.',
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'Erro de conexão: $e', statusCode: 0);
    }
  }

  /// `POST /check-in/exceptions` — gestor libera UM check-in fora da janela.
  /// `validUntil` no máximo 24h à frente; o backend recusa acima disso.
  Future<ApiResponse<CheckInExceptionGrant>> grantException({
    required String userId,
    required DateTime validUntil,
    String? note,
  }) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        '/check-in/exceptions',
        body: {
          'userId': userId,
          'validUntil': validUntil.toUtc().toIso8601String(),
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        },
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: CheckInExceptionGrant.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Não foi possível liberar o check-in.',
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'Erro de conexão: $e', statusCode: 0);
    }
  }

  /// `POST /check-in/unblock` — gestor libera o bloqueio semanal.
  /// O motivo é obrigatório e fica registrado na auditoria.
  Future<ApiResponse<CheckInBlock>> unblock({
    required String userId,
    required String reason,
  }) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        '/check-in/unblock',
        body: {'userId': userId, 'reason': reason.trim()},
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: CheckInBlock.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Não foi possível liberar o bloqueio.',
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'Erro de conexão: $e', statusCode: 0);
    }
  }

  /// `GET /check-in/blocks` — bloqueios da semana. `week` = segunda-feira
  /// (`YYYY-MM-DD`); sem ela o backend devolve a semana atual.
  Future<ApiResponse<List<CheckInBlock>>> listBlocks({String? week}) async {
    try {
      final response = await _api.get<dynamic>(
        week != null && week.isNotEmpty
            ? '/check-in/blocks?week=${Uri.encodeQueryComponent(week)}'
            : '/check-in/blocks',
      );
      if (response.success) {
        final raw = response.data;
        return ApiResponse.success(
          data: raw is List
              ? raw
                    .whereType<Map>()
                    .map(
                      (e) =>
                          CheckInBlock.fromJson(Map<String, dynamic>.from(e)),
                    )
                    .toList()
              : <CheckInBlock>[],
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar os bloqueios.',
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'Erro de conexão: $e', statusCode: 0);
    }
  }

  /// `GET /check-in/audit` — histórico de ações do gestor e do sistema.
  Future<ApiResponse<List<CheckInAuditEntry>>> listAudit({
    int limit = 60,
  }) async {
    try {
      final response = await _api.get<dynamic>('/check-in/audit?limit=$limit');
      if (response.success) {
        final raw = response.data;
        return ApiResponse.success(
          data: raw is List
              ? raw
                    .whereType<Map>()
                    .map(
                      (e) => CheckInAuditEntry.fromJson(
                        Map<String, dynamic>.from(e),
                      ),
                    )
                    .toList()
              : <CheckInAuditEntry>[],
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar o histórico de ações.',
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'Erro de conexão: $e', statusCode: 0);
    }
  }
}
