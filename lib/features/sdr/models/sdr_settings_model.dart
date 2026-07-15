/// Configurações do SDR com IA — paridade 1:1 com `SDRSettings` /
/// `UpdateSDRSettingsDto` do `sdrSettingsService.ts` (imobx-front) e com o
/// `sdr-settings.dto.ts` do backend. `fromJson` defensivo (bool/number/string
/// tolerante) + normalização com os mesmos clamps da página web.
library;

bool _asBool(dynamic v, [bool fallback = false]) {
  if (v == null) return fallback;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().trim().toLowerCase();
  if (s == 'true' || s == '1') return true;
  if (s == 'false' || s == '0') return false;
  return fallback;
}

int _asInt(dynamic v, int fallback) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse(v.toString()) ?? fallback;
}

String _asString(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  return v.toString();
}

List<String> _asStringList(dynamic v) {
  if (v is! List) return const [];
  return v
      .map((e) => e?.toString().trim() ?? '')
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
}

int _clamp(int n, int min, int max) => n < min ? min : (n > max ? max : n);

/// Tom de voz do assistente.
enum SdrTone {
  professional('professional', 'Profissional'),
  friendly('friendly', 'Amigável'),
  casual('casual', 'Casual');

  const SdrTone(this.value, this.label);

  final String value;
  final String label;

  static SdrTone fromValue(dynamic raw) {
    final s = raw?.toString().trim().toLowerCase() ?? '';
    return SdrTone.values.firstWhere(
      (t) => t.value == s,
      orElse: () => SdrTone.professional,
    );
  }
}

class SdrSettings {
  const SdrSettings({
    // Gerais
    required this.enabled,
    required this.autoRespond,
    required this.responseDelaySeconds,
    // Ações automáticas
    required this.canCreateLead,
    required this.canAddToFunnel,
    // Gestão de leads
    required this.canUpdateLeadStatus,
    required this.canAddLeadNote,
    required this.canAssignLead,
    // Visitas
    required this.canScheduleVisit,
    required this.canRescheduleVisit,
    required this.canCancelVisit,
    required this.canAddVisitFeedback,
    required this.requireVisitConfirmation,
    // Comunicação
    required this.canSendWhatsapp,
    required this.canSendEmail,
    required this.canSendSms,
    required this.canSendPropertyBrochure,
    // Documentação
    required this.canGenerateProposal,
    required this.canRequestDocuments,
    // Follow-ups
    required this.canScheduleFollowup,
    required this.canSendReminders,
    required this.autoFollowupDays,
    // Inteligência
    required this.canRecommendProperties,
    required this.canCalculateFinancing,
    required this.canCompareProperties,
    required this.canProvideNeighborhoodInfo,
    // Limites
    required this.maxPropertiesPerSearch,
    required this.maxMessagesPerDay,
    required this.maxVisitsPerDay,
    // Horário de atendimento
    required this.businessHoursStart,
    required this.businessHoursEnd,
    required this.workOnWeekends,
    // Personalização
    required this.greetingMessage,
    required this.signature,
    required this.tone,
    // IA e contexto
    required this.aiContextHours,
    required this.reengagementEnabled,
    required this.reengagementHours,
    required this.phraseBlacklist,
    required this.requireHandoffConfirmation,
  });

  final bool enabled;
  final bool autoRespond;

  /// 8–60s (mínimo 8 para evitar gargalos, paridade web).
  final int responseDelaySeconds;

  final bool canCreateLead;
  final bool canAddToFunnel;

  final bool canUpdateLeadStatus;
  final bool canAddLeadNote;
  final bool canAssignLead;

  final bool canScheduleVisit;
  final bool canRescheduleVisit;
  final bool canCancelVisit;
  final bool canAddVisitFeedback;
  final bool requireVisitConfirmation;

  final bool canSendWhatsapp;
  final bool canSendEmail;
  final bool canSendSms;
  final bool canSendPropertyBrochure;

  final bool canGenerateProposal;
  final bool canRequestDocuments;

  final bool canScheduleFollowup;
  final bool canSendReminders;

  /// 1–30 dias.
  final int autoFollowupDays;

  final bool canRecommendProperties;
  final bool canCalculateFinancing;
  final bool canCompareProperties;
  final bool canProvideNeighborhoodInfo;

  /// 1–12.
  final int maxPropertiesPerSearch;

  /// 1–50.
  final int maxMessagesPerDay;

  /// 1–10.
  final int maxVisitsPerDay;

  /// Formato `HH:mm:ss` (ex.: `08:00:00`).
  final String businessHoursStart;
  final String businessHoursEnd;
  final bool workOnWeekends;

  final String greetingMessage;
  final String signature;
  final SdrTone tone;

  /// 1–168 horas.
  final int aiContextHours;
  final bool reengagementEnabled;

  /// 1–168 horas.
  final int reengagementHours;
  final List<String> phraseBlacklist;
  final bool requireHandoffConfirmation;

  /// Padrões idênticos ao `getDefaultSDRSettings()` do web.
  factory SdrSettings.defaults() {
    return const SdrSettings(
      enabled: true,
      autoRespond: true,
      responseDelaySeconds: 8,
      canCreateLead: true,
      canAddToFunnel: true,
      canUpdateLeadStatus: false,
      canAddLeadNote: false,
      canAssignLead: false,
      canScheduleVisit: false,
      canRescheduleVisit: false,
      canCancelVisit: false,
      canAddVisitFeedback: false,
      requireVisitConfirmation: false,
      canSendWhatsapp: false,
      canSendEmail: false,
      canSendSms: false,
      canSendPropertyBrochure: false,
      canGenerateProposal: false,
      canRequestDocuments: false,
      canScheduleFollowup: false,
      canSendReminders: false,
      autoFollowupDays: 7,
      canRecommendProperties: false,
      canCalculateFinancing: false,
      canCompareProperties: false,
      canProvideNeighborhoodInfo: false,
      maxPropertiesPerSearch: 3,
      maxMessagesPerDay: 20,
      maxVisitsPerDay: 3,
      businessHoursStart: '08:00:00',
      businessHoursEnd: '18:00:00',
      workOnWeekends: false,
      greetingMessage: '',
      signature: '',
      tone: SdrTone.professional,
      aiContextHours: 24,
      reengagementEnabled: false,
      reengagementHours: 24,
      phraseBlacklist: [],
      requireHandoffConfirmation: false,
    );
  }

  /// Parsing defensivo + normalização (mesmos clamps do `loadSettings` web).
  factory SdrSettings.fromJson(Map<String, dynamic> json) {
    return SdrSettings(
      enabled: _asBool(json['enabled'], true),
      autoRespond: _asBool(json['autoRespond'], true),
      responseDelaySeconds:
          _clamp(_asInt(json['responseDelaySeconds'], 8), 8, 60),
      canCreateLead: _asBool(json['canCreateLead'], true),
      canAddToFunnel: _asBool(json['canAddToFunnel'], true),
      canUpdateLeadStatus: _asBool(json['canUpdateLeadStatus']),
      canAddLeadNote: _asBool(json['canAddLeadNote']),
      canAssignLead: _asBool(json['canAssignLead']),
      canScheduleVisit: _asBool(json['canScheduleVisit']),
      canRescheduleVisit: _asBool(json['canRescheduleVisit']),
      canCancelVisit: _asBool(json['canCancelVisit']),
      canAddVisitFeedback: _asBool(json['canAddVisitFeedback']),
      requireVisitConfirmation: _asBool(json['requireVisitConfirmation']),
      canSendWhatsapp: _asBool(json['canSendWhatsapp']),
      canSendEmail: _asBool(json['canSendEmail']),
      canSendSms: _asBool(json['canSendSms']),
      canSendPropertyBrochure: _asBool(json['canSendPropertyBrochure']),
      canGenerateProposal: _asBool(json['canGenerateProposal']),
      canRequestDocuments: _asBool(json['canRequestDocuments']),
      canScheduleFollowup: _asBool(json['canScheduleFollowup']),
      canSendReminders: _asBool(json['canSendReminders']),
      autoFollowupDays: _clamp(_asInt(json['autoFollowupDays'], 7), 1, 30),
      canRecommendProperties: _asBool(json['canRecommendProperties']),
      canCalculateFinancing: _asBool(json['canCalculateFinancing']),
      canCompareProperties: _asBool(json['canCompareProperties']),
      canProvideNeighborhoodInfo: _asBool(json['canProvideNeighborhoodInfo']),
      maxPropertiesPerSearch:
          _clamp(_asInt(json['maxPropertiesPerSearch'], 3), 1, 12),
      maxMessagesPerDay: _clamp(_asInt(json['maxMessagesPerDay'], 20), 1, 50),
      maxVisitsPerDay: _clamp(_asInt(json['maxVisitsPerDay'], 3), 1, 10),
      businessHoursStart:
          _asString(json['businessHoursStart'], '08:00:00'),
      businessHoursEnd: _asString(json['businessHoursEnd'], '18:00:00'),
      workOnWeekends: _asBool(json['workOnWeekends']),
      greetingMessage: _asString(json['greetingMessage']),
      signature: _asString(json['signature']),
      tone: SdrTone.fromValue(json['tone']),
      aiContextHours: _clamp(_asInt(json['aiContextHours'], 24), 1, 168),
      reengagementEnabled: _asBool(json['reengagementEnabled']),
      reengagementHours: _clamp(_asInt(json['reengagementHours'], 24), 1, 168),
      phraseBlacklist: _asStringList(json['phraseBlacklist']),
      requireHandoffConfirmation: _asBool(json['requireHandoffConfirmation']),
    );
  }

  /// DTO completo enviado no `PUT /sdr-settings` — espelha o `buildDto`
  /// da `SDRSettingsPage.tsx`.
  Map<String, dynamic> toUpdateJson() {
    return {
      'enabled': enabled,
      'autoRespond': autoRespond,
      'responseDelaySeconds': responseDelaySeconds,
      'canCreateLead': canCreateLead,
      'canUpdateLeadStatus': canUpdateLeadStatus,
      'canAddLeadNote': canAddLeadNote,
      'canAssignLead': canAssignLead,
      'canAddToFunnel': canAddToFunnel,
      'canScheduleVisit': canScheduleVisit,
      'canRescheduleVisit': canRescheduleVisit,
      'canCancelVisit': canCancelVisit,
      'canAddVisitFeedback': canAddVisitFeedback,
      'requireVisitConfirmation': requireVisitConfirmation,
      'canSendWhatsapp': canSendWhatsapp,
      'canSendEmail': canSendEmail,
      'canSendSms': canSendSms,
      'canSendPropertyBrochure': canSendPropertyBrochure,
      'canGenerateProposal': canGenerateProposal,
      'canRequestDocuments': canRequestDocuments,
      'canScheduleFollowup': canScheduleFollowup,
      'canSendReminders': canSendReminders,
      'autoFollowupDays': autoFollowupDays,
      'canRecommendProperties': canRecommendProperties,
      'canCalculateFinancing': canCalculateFinancing,
      'canCompareProperties': canCompareProperties,
      'canProvideNeighborhoodInfo': canProvideNeighborhoodInfo,
      'maxPropertiesPerSearch': maxPropertiesPerSearch,
      'maxMessagesPerDay': maxMessagesPerDay,
      'maxVisitsPerDay': maxVisitsPerDay,
      'businessHoursStart': businessHoursStart,
      'businessHoursEnd': businessHoursEnd,
      'workOnWeekends': workOnWeekends,
      'greetingMessage': greetingMessage,
      'signature': signature,
      'tone': tone.value,
      'aiContextHours': aiContextHours,
      'reengagementEnabled': reengagementEnabled,
      'reengagementHours': reengagementHours,
      'phraseBlacklist': phraseBlacklist,
      'requireHandoffConfirmation': requireHandoffConfirmation,
    };
  }

  SdrSettings copyWith({
    bool? enabled,
    bool? autoRespond,
    int? responseDelaySeconds,
    bool? canCreateLead,
    bool? canAddToFunnel,
    bool? canUpdateLeadStatus,
    bool? canAddLeadNote,
    bool? canAssignLead,
    bool? canScheduleVisit,
    bool? canRescheduleVisit,
    bool? canCancelVisit,
    bool? canAddVisitFeedback,
    bool? requireVisitConfirmation,
    bool? canSendWhatsapp,
    bool? canSendEmail,
    bool? canSendSms,
    bool? canSendPropertyBrochure,
    bool? canGenerateProposal,
    bool? canRequestDocuments,
    bool? canScheduleFollowup,
    bool? canSendReminders,
    int? autoFollowupDays,
    bool? canRecommendProperties,
    bool? canCalculateFinancing,
    bool? canCompareProperties,
    bool? canProvideNeighborhoodInfo,
    int? maxPropertiesPerSearch,
    int? maxMessagesPerDay,
    int? maxVisitsPerDay,
    String? businessHoursStart,
    String? businessHoursEnd,
    bool? workOnWeekends,
    String? greetingMessage,
    String? signature,
    SdrTone? tone,
    int? aiContextHours,
    bool? reengagementEnabled,
    int? reengagementHours,
    List<String>? phraseBlacklist,
    bool? requireHandoffConfirmation,
  }) {
    return SdrSettings(
      enabled: enabled ?? this.enabled,
      autoRespond: autoRespond ?? this.autoRespond,
      responseDelaySeconds: responseDelaySeconds ?? this.responseDelaySeconds,
      canCreateLead: canCreateLead ?? this.canCreateLead,
      canAddToFunnel: canAddToFunnel ?? this.canAddToFunnel,
      canUpdateLeadStatus: canUpdateLeadStatus ?? this.canUpdateLeadStatus,
      canAddLeadNote: canAddLeadNote ?? this.canAddLeadNote,
      canAssignLead: canAssignLead ?? this.canAssignLead,
      canScheduleVisit: canScheduleVisit ?? this.canScheduleVisit,
      canRescheduleVisit: canRescheduleVisit ?? this.canRescheduleVisit,
      canCancelVisit: canCancelVisit ?? this.canCancelVisit,
      canAddVisitFeedback: canAddVisitFeedback ?? this.canAddVisitFeedback,
      requireVisitConfirmation:
          requireVisitConfirmation ?? this.requireVisitConfirmation,
      canSendWhatsapp: canSendWhatsapp ?? this.canSendWhatsapp,
      canSendEmail: canSendEmail ?? this.canSendEmail,
      canSendSms: canSendSms ?? this.canSendSms,
      canSendPropertyBrochure:
          canSendPropertyBrochure ?? this.canSendPropertyBrochure,
      canGenerateProposal: canGenerateProposal ?? this.canGenerateProposal,
      canRequestDocuments: canRequestDocuments ?? this.canRequestDocuments,
      canScheduleFollowup: canScheduleFollowup ?? this.canScheduleFollowup,
      canSendReminders: canSendReminders ?? this.canSendReminders,
      autoFollowupDays: autoFollowupDays ?? this.autoFollowupDays,
      canRecommendProperties:
          canRecommendProperties ?? this.canRecommendProperties,
      canCalculateFinancing:
          canCalculateFinancing ?? this.canCalculateFinancing,
      canCompareProperties: canCompareProperties ?? this.canCompareProperties,
      canProvideNeighborhoodInfo:
          canProvideNeighborhoodInfo ?? this.canProvideNeighborhoodInfo,
      maxPropertiesPerSearch:
          maxPropertiesPerSearch ?? this.maxPropertiesPerSearch,
      maxMessagesPerDay: maxMessagesPerDay ?? this.maxMessagesPerDay,
      maxVisitsPerDay: maxVisitsPerDay ?? this.maxVisitsPerDay,
      businessHoursStart: businessHoursStart ?? this.businessHoursStart,
      businessHoursEnd: businessHoursEnd ?? this.businessHoursEnd,
      workOnWeekends: workOnWeekends ?? this.workOnWeekends,
      greetingMessage: greetingMessage ?? this.greetingMessage,
      signature: signature ?? this.signature,
      tone: tone ?? this.tone,
      aiContextHours: aiContextHours ?? this.aiContextHours,
      reengagementEnabled: reengagementEnabled ?? this.reengagementEnabled,
      reengagementHours: reengagementHours ?? this.reengagementHours,
      phraseBlacklist: phraseBlacklist ?? this.phraseBlacklist,
      requireHandoffConfirmation:
          requireHandoffConfirmation ?? this.requireHandoffConfirmation,
    );
  }

  /// `HH:mm:ss` → `HH:mm` para exibição.
  static String hourLabel(String hms) {
    final parts = hms.split(':');
    if (parts.length >= 2) {
      final h = parts[0].padLeft(2, '0');
      final m = parts[1].padLeft(2, '0');
      return '$h:$m';
    }
    return hms;
  }
}
