// Modelos do módulo **Régua de Cobrança** — espelham as entities
// `collection-message.entity.ts` / `collection-rule.entity.ts` e as respostas
// de `GET /collection`, `GET /collection/statistics` e `/collection/rules`
// do backend (paridade com `collectionService.ts` do imobx-front).

/// Canal de envio da cobrança (1:1 com `CollectionChannel` do backend).
enum CollectionChannel {
  email,
  whatsapp,
  sms,
  unknown;

  static CollectionChannel fromRaw(String? raw) {
    switch ((raw ?? '').toUpperCase()) {
      case 'EMAIL':
        return CollectionChannel.email;
      case 'WHATSAPP':
        return CollectionChannel.whatsapp;
      case 'SMS':
        return CollectionChannel.sms;
      default:
        return CollectionChannel.unknown;
    }
  }

  /// Valor exato aceito pela API nos payloads de régua.
  String get raw {
    switch (this) {
      case CollectionChannel.email:
        return 'EMAIL';
      case CollectionChannel.whatsapp:
        return 'WHATSAPP';
      case CollectionChannel.sms:
        return 'SMS';
      case CollectionChannel.unknown:
        return 'EMAIL';
    }
  }

  String get label {
    switch (this) {
      case CollectionChannel.email:
        return 'Email';
      case CollectionChannel.whatsapp:
        return 'WhatsApp';
      case CollectionChannel.sms:
        return 'SMS';
      case CollectionChannel.unknown:
        return 'Canal';
    }
  }
}

/// Status da mensagem de cobrança (1:1 com `CollectionMessageStatus`).
enum CollectionMessageStatus {
  pending,
  queued,
  sent,
  delivered,
  read,
  failed,
  bounced,
  unknown;

  static CollectionMessageStatus fromRaw(String? raw) {
    switch ((raw ?? '').toUpperCase()) {
      case 'PENDING':
        return CollectionMessageStatus.pending;
      case 'QUEUED':
        return CollectionMessageStatus.queued;
      case 'SENT':
        return CollectionMessageStatus.sent;
      case 'DELIVERED':
        return CollectionMessageStatus.delivered;
      case 'READ':
        return CollectionMessageStatus.read;
      case 'FAILED':
        return CollectionMessageStatus.failed;
      case 'BOUNCED':
        return CollectionMessageStatus.bounced;
      default:
        return CollectionMessageStatus.unknown;
    }
  }

  String get label {
    switch (this) {
      case CollectionMessageStatus.pending:
        return 'Pendente';
      case CollectionMessageStatus.queued:
        return 'Na fila';
      case CollectionMessageStatus.sent:
        return 'Enviada';
      case CollectionMessageStatus.delivered:
        return 'Entregue';
      case CollectionMessageStatus.read:
        return 'Lida';
      case CollectionMessageStatus.failed:
        return 'Falhou';
      case CollectionMessageStatus.bounced:
        return 'Devolvida';
      case CollectionMessageStatus.unknown:
        return 'Status';
    }
  }

  /// Saiu com sucesso (enviada / entregue / lida).
  bool get isSuccess =>
      this == CollectionMessageStatus.sent ||
      this == CollectionMessageStatus.delivered ||
      this == CollectionMessageStatus.read;

  /// Falhou de vez (falha de envio ou email devolvido).
  bool get isFailure =>
      this == CollectionMessageStatus.failed ||
      this == CollectionMessageStatus.bounced;

  /// Ainda não saiu (aguardando envio ou na fila).
  bool get isWaiting =>
      this == CollectionMessageStatus.pending ||
      this == CollectionMessageStatus.queued;
}

/// Gatilho da régua (1:1 com `CollectionTrigger` do backend).
enum CollectionTrigger {
  daysBeforeDue,
  onDueDate,
  daysAfterDue,
  unknown;

  static CollectionTrigger fromRaw(String? raw) {
    switch ((raw ?? '').toUpperCase()) {
      case 'DAYS_BEFORE_DUE':
        return CollectionTrigger.daysBeforeDue;
      case 'ON_DUE_DATE':
        return CollectionTrigger.onDueDate;
      case 'DAYS_AFTER_DUE':
        return CollectionTrigger.daysAfterDue;
      default:
        return CollectionTrigger.unknown;
    }
  }

  /// Valor exato aceito pela API nos payloads de régua.
  String get raw {
    switch (this) {
      case CollectionTrigger.daysBeforeDue:
        return 'DAYS_BEFORE_DUE';
      case CollectionTrigger.onDueDate:
        return 'ON_DUE_DATE';
      case CollectionTrigger.daysAfterDue:
        return 'DAYS_AFTER_DUE';
      case CollectionTrigger.unknown:
        return 'DAYS_BEFORE_DUE';
    }
  }

  String get label {
    switch (this) {
      case CollectionTrigger.daysBeforeDue:
        return 'Dias antes do vencimento';
      case CollectionTrigger.onDueDate:
        return 'No dia do vencimento';
      case CollectionTrigger.daysAfterDue:
        return 'Dias após o vencimento';
      case CollectionTrigger.unknown:
        return 'Gatilho';
    }
  }

  /// O gatilho "no dia" não usa quantidade de dias.
  bool get usesDays => this != CollectionTrigger.onDueDate;

  /// Rótulo compacto para chips ("3 dias antes", "No vencimento", "5 dias após").
  String shortLabel(int days) {
    switch (this) {
      case CollectionTrigger.daysBeforeDue:
        return '$days dia${days == 1 ? '' : 's'} antes';
      case CollectionTrigger.onDueDate:
        return 'No vencimento';
      case CollectionTrigger.daysAfterDue:
        return '$days dia${days == 1 ? '' : 's'} após';
      case CollectionTrigger.unknown:
        return 'Gatilho';
    }
  }
}

double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

int _toInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? fallback;
}

bool _toBool(dynamic v, [bool fallback = false]) {
  if (v is bool) return v;
  final s = v?.toString().toLowerCase();
  if (s == 'true' || s == '1') return true;
  if (s == 'false' || s == '0') return false;
  return fallback;
}

DateTime? _toDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

/// Mensagem de cobrança enviada (ou aguardando envio) — `GET /collection`.
class CollectionMessage {
  final String id;
  final CollectionChannel channel;
  final String recipientName;
  final String? recipientEmail;
  final String? recipientPhone;
  final String? subject;
  final String message;
  final CollectionMessageStatus status;
  final String? errorMessage;
  final DateTime? sentAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final DateTime? failedAt;
  final DateTime? createdAt;
  final String? ruleName;

  const CollectionMessage({
    required this.id,
    required this.channel,
    required this.recipientName,
    required this.message,
    required this.status,
    this.recipientEmail,
    this.recipientPhone,
    this.subject,
    this.errorMessage,
    this.sentAt,
    this.deliveredAt,
    this.readAt,
    this.failedAt,
    this.createdAt,
    this.ruleName,
  });

  /// Contato exibido conforme o canal (email → email; demais → telefone).
  String? get contact {
    final email = recipientEmail?.trim();
    final phone = recipientPhone?.trim();
    if (channel == CollectionChannel.email) {
      return (email?.isNotEmpty ?? false) ? email : phone;
    }
    return (phone?.isNotEmpty ?? false) ? phone : email;
  }

  /// Melhor data para exibir na lista (envio → criação).
  DateTime? get bestDate => sentAt ?? failedAt ?? createdAt;

  factory CollectionMessage.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? nested(String key) {
      final v = json[key];
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
      return null;
    }

    final rule = nested('collectionRule') ?? nested('collection_rule');

    return CollectionMessage(
      id: json['id']?.toString() ?? '',
      channel: CollectionChannel.fromRaw(json['channel']?.toString()),
      recipientName:
          (json['recipientName'] ?? json['recipient_name'])?.toString() ?? '',
      recipientEmail:
          (json['recipientEmail'] ?? json['recipient_email'])?.toString(),
      recipientPhone:
          (json['recipientPhone'] ?? json['recipient_phone'])?.toString(),
      subject: json['subject']?.toString(),
      message: json['message']?.toString() ?? '',
      status: CollectionMessageStatus.fromRaw(json['status']?.toString()),
      errorMessage:
          (json['errorMessage'] ?? json['error_message'])?.toString(),
      sentAt: _toDate(json['sentAt'] ?? json['sent_at']),
      deliveredAt: _toDate(json['deliveredAt'] ?? json['delivered_at']),
      readAt: _toDate(json['readAt'] ?? json['read_at']),
      failedAt: _toDate(json['failedAt'] ?? json['failed_at']),
      createdAt: _toDate(json['createdAt'] ?? json['created_at']),
      ruleName: rule?['name']?.toString(),
    );
  }
}

/// Resposta de `GET /collection/statistics`.
class CollectionStatistics {
  final int total;
  final int sent;
  final int delivered;
  final int read;
  final int failed;

  /// Fração 0..1 (o web multiplica por 100 para exibir).
  final double successRate;
  final int byEmail;
  final int byWhatsapp;
  final int bySms;

  const CollectionStatistics({
    required this.total,
    required this.sent,
    required this.delivered,
    required this.read,
    required this.failed,
    required this.successRate,
    required this.byEmail,
    required this.byWhatsapp,
    required this.bySms,
  });

  static const zero = CollectionStatistics(
    total: 0,
    sent: 0,
    delivered: 0,
    read: 0,
    failed: 0,
    successRate: 0,
    byEmail: 0,
    byWhatsapp: 0,
    bySms: 0,
  );

  /// Quantas saíram com sucesso (enviadas + entregues + lidas).
  int get successCount => sent + delivered + read;

  factory CollectionStatistics.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> channel() {
      final v = json['byChannel'] ?? json['by_channel'];
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
      return const {};
    }

    final byChannel = channel();
    return CollectionStatistics(
      total: _toInt(json['total']),
      sent: _toInt(json['sent']),
      delivered: _toInt(json['delivered']),
      read: _toInt(json['read']),
      failed: _toInt(json['failed']),
      successRate: _toDouble(json['successRate'] ?? json['success_rate']),
      byEmail: _toInt(byChannel['email']),
      byWhatsapp: _toInt(byChannel['whatsapp']),
      bySms: _toInt(byChannel['sms']),
    );
  }
}

/// Régua de cobrança configurada — `GET /collection/rules`.
class CollectionRule {
  final String id;
  final String name;
  final String? description;
  final CollectionTrigger trigger;
  final int triggerDays;
  final CollectionChannel channel;
  final String messageTemplate;
  final String? subjectTemplate;
  final bool isActive;
  final int priority;

  /// Formato do backend: `HH:mm:ss`.
  final String sendTime;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CollectionRule({
    required this.id,
    required this.name,
    required this.trigger,
    required this.triggerDays,
    required this.channel,
    required this.messageTemplate,
    required this.isActive,
    required this.priority,
    required this.sendTime,
    this.description,
    this.subjectTemplate,
    this.createdAt,
    this.updatedAt,
  });

  /// Horário compacto "HH:mm" para chips.
  String get sendTimeShort {
    final t = sendTime.trim();
    return t.length >= 5 ? t.substring(0, 5) : t;
  }

  factory CollectionRule.fromJson(Map<String, dynamic> json) {
    return CollectionRule(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      trigger: CollectionTrigger.fromRaw(json['trigger']?.toString()),
      triggerDays: _toInt(json['triggerDays'] ?? json['trigger_days'], 1),
      channel: CollectionChannel.fromRaw(json['channel']?.toString()),
      messageTemplate:
          (json['messageTemplate'] ?? json['message_template'])?.toString() ??
              '',
      subjectTemplate:
          (json['subjectTemplate'] ?? json['subject_template'])?.toString(),
      isActive: _toBool(json['isActive'] ?? json['is_active'], true),
      priority: _toInt(json['priority'], 1),
      sendTime:
          (json['sendTime'] ?? json['send_time'])?.toString() ?? '09:00:00',
      createdAt: _toDate(json['createdAt'] ?? json['created_at']),
      updatedAt: _toDate(json['updatedAt'] ?? json['updated_at']),
    );
  }
}

/// Payload de criação/edição de régua (`POST`/`PUT /collection/rules`).
/// Espelha `CreateCollectionRuleDto` / `UpdateCollectionRuleDto` do backend.
class CollectionRulePayload {
  final String name;
  final String? description;
  final CollectionTrigger trigger;
  final int triggerDays;
  final CollectionChannel channel;
  final String messageTemplate;
  final String? subjectTemplate;
  final bool isActive;
  final int priority;

  /// `HH:mm:ss` — mesmo normalizado do web (`normalizeTime`).
  final String sendTime;

  const CollectionRulePayload({
    required this.name,
    required this.trigger,
    required this.triggerDays,
    required this.channel,
    required this.messageTemplate,
    required this.isActive,
    required this.priority,
    required this.sendTime,
    this.description,
    this.subjectTemplate,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'description': description ?? '',
      'trigger': trigger.raw,
      'triggerDays': triggerDays,
      'channel': channel.raw,
      'messageTemplate': messageTemplate,
      'subjectTemplate': subjectTemplate ?? '',
      'isActive': isActive,
      'priority': priority,
      'sendTime': sendTime,
    };
  }
}

/// Aba ativa da visão de cobranças — filtro aplicado no cliente
/// (o endpoint `GET /collection` devolve as últimas 500 mensagens).
enum CollectionMessageTab { all, delivered, waiting, failed }

/// Filtros do modal (canal + status) — aplicados no cliente.
class CollectionMessageFilters {
  final CollectionChannel? channel;
  final CollectionMessageStatus? status;

  const CollectionMessageFilters({this.channel, this.status});

  static const empty = CollectionMessageFilters();

  int get activeCount => (channel != null ? 1 : 0) + (status != null ? 1 : 0);

  bool matches(CollectionMessage m) {
    if (channel != null && m.channel != channel) return false;
    if (status != null && m.status != status) return false;
    return true;
  }

  CollectionMessageFilters copyWith({
    CollectionChannel? channel,
    CollectionMessageStatus? status,
    bool clearChannel = false,
    bool clearStatus = false,
  }) {
    return CollectionMessageFilters(
      channel: clearChannel ? null : (channel ?? this.channel),
      status: clearStatus ? null : (status ?? this.status),
    );
  }
}
