import '../../../../shared/utils/avatar_url_resolver.dart';

/// Status de disponibilidade do SDR na roleta — os valores do back
/// (`SDRAvailabilityStatus`: active, paused_manual, paused_scheduled) mais o
/// `scheduled_pause`, que o tipo do web também prevê.
///
/// Paridade com a normalização do `SDRAvailabilityPanel`: status vazio vira
/// `active` (`item.status || 'active'`), mas um valor desconhecido NÃO vira
/// ativo — no web só `status === 'active'` conta como "na roleta".
enum SdrAvailabilityStatus {
  active('active'),
  pausedManual('paused_manual'),
  pausedScheduled('paused_scheduled'),
  scheduledPause('scheduled_pause'),
  other('');

  const SdrAvailabilityStatus(this.value);

  final String value;

  static SdrAvailabilityStatus fromValue(Object? raw) {
    final v = raw?.toString().trim() ?? '';
    if (v.isEmpty) return SdrAvailabilityStatus.active;
    for (final s in SdrAvailabilityStatus.values) {
      if (s != SdrAvailabilityStatus.other && s.value == v) return s;
    }
    return SdrAvailabilityStatus.other;
  }
}

/// Um SDR da roleta — item de `GET /whatsapp/sdr-availability`
/// (`SDRAvailabilityWithUser` no back, `SDRAvailabilityItem` no web).
///
/// Datas chegam em ISO 8601 com `Z` (IsoDateResponseInterceptor) e ficam no
/// fuso do aparelho.
class SdrAvailability {
  final String userId;
  final String userName;

  /// URL já resolvida para o CDN (ver [AvatarUrlResolver]).
  final String? userAvatarUrl;
  final String? userEmail;
  final SdrAvailabilityStatus status;
  final String? pauseReason;
  final DateTime? pauseStart;
  final DateTime? pauseEnd;
  final DateTime? scheduledPauseStart;
  final DateTime? scheduledPauseEnd;
  final String? scheduledPauseReason;
  final int? conversationsCount;
  final DateTime? lastActivity;

  /// Check-in vigente na imobiliária (presença física).
  final bool checkInActive;

  /// SDR de locação (21/09/2026): recebe só conversas de locação, com o card
  /// no funil de locação. `null` = o back ainda não tem a marcação (a coluna
  /// não existe) — a tela esconde tudo de Locação, como o web.
  final bool? soLocacao;

  const SdrAvailability({
    required this.userId,
    required this.userName,
    required this.status,
    this.userAvatarUrl,
    this.userEmail,
    this.pauseReason,
    this.pauseStart,
    this.pauseEnd,
    this.scheduledPauseStart,
    this.scheduledPauseEnd,
    this.scheduledPauseReason,
    this.conversationsCount,
    this.lastActivity,
    this.checkInActive = false,
    this.soLocacao,
  });

  /// Na roleta = `status === 'active'` (normalização do web).
  bool get isActive => status == SdrAvailabilityStatus.active;

  /// Nome para avisos — nunca vazio.
  String get displayName => userName.isEmpty ? 'SDR' : userName;

  /// Motivo da folga agendada. O back não manda `scheduledPauseReason`: o
  /// agendamento grava o motivo em `pauseReason`, que só continua sendo da
  /// folga enquanto ninguém pausou o SDR à mão depois (a pausa manual e a
  /// desativação do usuário sobrescrevem o motivo).
  String? get leaveReason {
    final proprio = scheduledPauseReason?.trim();
    if (proprio != null && proprio.isNotEmpty) return proprio;
    if (scheduledPauseStart == null) return null;
    if (status == SdrAvailabilityStatus.pausedManual) return null;
    final motivo = pauseReason?.trim();
    return (motivo == null || motivo.isEmpty) ? null : motivo;
  }

  factory SdrAvailability.fromJson(Map<String, dynamic> json) {
    final so = json['soLocacao'];
    final conversas = json['conversationsCount'];
    return SdrAvailability(
      userId: json['userId']?.toString() ?? '',
      userName: (json['userName']?.toString() ?? '').trim(),
      userAvatarUrl: AvatarUrlResolver.resolve(json['userAvatar']?.toString()),
      userEmail: _texto(json['userEmail']),
      status: SdrAvailabilityStatus.fromValue(json['status']),
      pauseReason: _texto(json['pauseReason']),
      pauseStart: _data(json['pauseStart']),
      pauseEnd: _data(json['pauseEnd']),
      scheduledPauseStart: _data(json['scheduledPauseStart']),
      scheduledPauseEnd: _data(json['scheduledPauseEnd']),
      scheduledPauseReason: _texto(json['scheduledPauseReason']),
      conversationsCount: conversas is num ? conversas.toInt() : null,
      lastActivity: _data(json['lastActivity']),
      checkInActive: json['checkInActive'] == true,
      // Só boolean conta: back antigo não manda o campo e a marca some.
      soLocacao: so is bool ? so : null,
    );
  }

  /// Espelho local de `setManualAvailability` do back: ligar zera motivo e
  /// folga agendada; pausar grava o motivo e mantém o agendamento.
  SdrAvailability withManualAvailability(
    bool active, {
    required String pauseReason,
  }) {
    return SdrAvailability(
      userId: userId,
      userName: userName,
      userAvatarUrl: userAvatarUrl,
      userEmail: userEmail,
      status: active
          ? SdrAvailabilityStatus.active
          : SdrAvailabilityStatus.pausedManual,
      pauseReason: active ? null : pauseReason,
      pauseStart: pauseStart,
      pauseEnd: pauseEnd,
      scheduledPauseStart: active ? null : scheduledPauseStart,
      scheduledPauseEnd: active ? null : scheduledPauseEnd,
      scheduledPauseReason: active ? null : scheduledPauseReason,
      conversationsCount: conversationsCount,
      lastActivity: lastActivity,
      checkInActive: checkInActive,
      soLocacao: soLocacao,
    );
  }

  SdrAvailability withSoLocacao(bool value) {
    return SdrAvailability(
      userId: userId,
      userName: userName,
      userAvatarUrl: userAvatarUrl,
      userEmail: userEmail,
      status: status,
      pauseReason: pauseReason,
      pauseStart: pauseStart,
      pauseEnd: pauseEnd,
      scheduledPauseStart: scheduledPauseStart,
      scheduledPauseEnd: scheduledPauseEnd,
      scheduledPauseReason: scheduledPauseReason,
      conversationsCount: conversationsCount,
      lastActivity: lastActivity,
      checkInActive: checkInActive,
      soLocacao: value,
    );
  }
}

String? _texto(Object? v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

DateTime? _data(Object? v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString())?.toLocal();
}
