// Modelos do WhatsApp Inbox — espelham `types/whatsapp.ts` do imobx-front e
// as respostas de `GET /whatsapp/messages` (com e sem `groupByPhone`),
// `GET /whatsapp/templates` e `GET /whatsapp/unofficial/config/status` do
// backend NestJS. Parsing 100% defensivo (null/string/number tolerante).

// ─── Helpers de parsing ──────────────────────────────────────────────────────

int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

bool _toBool(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.toLowerCase().trim();
    return s == 'true' || s == '1';
  }
  return false;
}

String? _toStringOrNull(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

DateTime? _toDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

Map<String, dynamic>? _toMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}

/// Formata um número normalizado (`5511999999999`) como telefone brasileiro
/// legível: `+55 (11) 99999-9999`. Números fora do padrão voltam com `+`.
String formatWhatsAppPhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return raw;
  if (digits.startsWith('55') && (digits.length == 12 || digits.length == 13)) {
    final ddd = digits.substring(2, 4);
    final number = digits.substring(4);
    final split = number.length - 4;
    return '+55 ($ddd) ${number.substring(0, split)}-${number.substring(split)}';
  }
  return '+$digits';
}

// ─── Enums ───────────────────────────────────────────────────────────────────

/// Direção da mensagem (1:1 com o backend).
enum WhatsAppMessageDirection {
  inbound,
  outbound;

  static WhatsAppMessageDirection fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'outbound':
        return WhatsAppMessageDirection.outbound;
      default:
        return WhatsAppMessageDirection.inbound;
    }
  }
}

/// Status de entrega da mensagem.
enum WhatsAppMessageStatus {
  pending,
  sent,
  delivered,
  read,
  failed,
  unknown;

  static WhatsAppMessageStatus fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'pending':
        return WhatsAppMessageStatus.pending;
      case 'sent':
        return WhatsAppMessageStatus.sent;
      case 'delivered':
        return WhatsAppMessageStatus.delivered;
      case 'read':
        return WhatsAppMessageStatus.read;
      case 'failed':
        return WhatsAppMessageStatus.failed;
      default:
        return WhatsAppMessageStatus.unknown;
    }
  }

  String get label {
    switch (this) {
      case WhatsAppMessageStatus.pending:
        return 'Enviando';
      case WhatsAppMessageStatus.sent:
        return 'Enviada';
      case WhatsAppMessageStatus.delivered:
        return 'Entregue';
      case WhatsAppMessageStatus.read:
        return 'Lida';
      case WhatsAppMessageStatus.failed:
        return 'Falhou';
      case WhatsAppMessageStatus.unknown:
        return '—';
    }
  }
}

/// Tipo do conteúdo da mensagem.
enum WhatsAppMessageType {
  text,
  image,
  video,
  audio,
  voice,
  document,
  location,
  contact,
  sticker,
  unknown;

  static WhatsAppMessageType fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'text':
        return WhatsAppMessageType.text;
      case 'image':
        return WhatsAppMessageType.image;
      case 'video':
        return WhatsAppMessageType.video;
      case 'audio':
        return WhatsAppMessageType.audio;
      case 'voice':
        return WhatsAppMessageType.voice;
      case 'document':
        return WhatsAppMessageType.document;
      case 'location':
        return WhatsAppMessageType.location;
      case 'contact':
        return WhatsAppMessageType.contact;
      case 'sticker':
        return WhatsAppMessageType.sticker;
      default:
        return WhatsAppMessageType.unknown;
    }
  }

  String get label {
    switch (this) {
      case WhatsAppMessageType.text:
        return 'Texto';
      case WhatsAppMessageType.image:
        return 'Imagem';
      case WhatsAppMessageType.video:
        return 'Vídeo';
      case WhatsAppMessageType.audio:
        return 'Áudio';
      case WhatsAppMessageType.voice:
        return 'Áudio';
      case WhatsAppMessageType.document:
        return 'Documento';
      case WhatsAppMessageType.location:
        return 'Localização';
      case WhatsAppMessageType.contact:
        return 'Contato';
      case WhatsAppMessageType.sticker:
        return 'Figurinha';
      case WhatsAppMessageType.unknown:
        return 'Mensagem';
    }
  }

  /// Valor enviado à API nos filtros (`messageType=`).
  String get apiValue => name;

  bool get isMedia =>
      this != WhatsAppMessageType.text && this != WhatsAppMessageType.unknown;
}

/// Origem de integração da mensagem/canal — oficial (Meta Cloud API) ou
/// não oficial (QR Code / Baileys).
enum WhatsAppIntegrationSource {
  official,
  unofficial,
  unknown;

  static WhatsAppIntegrationSource fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'official':
        return WhatsAppIntegrationSource.official;
      case 'unofficial':
        return WhatsAppIntegrationSource.unofficial;
      default:
        return WhatsAppIntegrationSource.unknown;
    }
  }

  String get label {
    switch (this) {
      case WhatsAppIntegrationSource.official:
        return 'API Oficial';
      case WhatsAppIntegrationSource.unofficial:
        return 'QR Code';
      case WhatsAppIntegrationSource.unknown:
        return '—';
    }
  }
}

/// Aba de atendimento do inbox — paridade com `WhatsAppAttendanceTab` do web.
enum WhatsAppAttendanceTab {
  all,
  waiting,
  inProgress,
  mine,
  finalized;

  String get label {
    switch (this) {
      case WhatsAppAttendanceTab.all:
        return 'Todas';
      case WhatsAppAttendanceTab.waiting:
        return 'Aguardando';
      case WhatsAppAttendanceTab.inProgress:
        return 'Em atendimento';
      case WhatsAppAttendanceTab.mine:
        return 'Minhas';
      case WhatsAppAttendanceTab.finalized:
        return 'Finalizadas';
    }
  }
}

// ─── Mensagem ────────────────────────────────────────────────────────────────

class WhatsAppMessage {
  final String id;
  final String phoneNumber;
  final String? contactName;
  final String? contactAvatarUrl;
  final WhatsAppMessageType messageType;
  final WhatsAppMessageDirection direction;
  final String? message;
  final String? mediaUrl;
  final String? mediaMimeType;
  final String? mediaFileName;
  final WhatsAppMessageStatus status;
  final String? clientId;
  final String? clientName;
  final String? kanbanTaskId;
  final String? userId;
  final String? userName;
  final bool isAiResponse;
  final String? assignedToId;
  final String? assignedToName;
  final String? detectedSource;
  final WhatsAppIntegrationSource integrationSource;
  final DateTime? createdAt;
  final DateTime? readAt;

  const WhatsAppMessage({
    required this.id,
    required this.phoneNumber,
    this.contactName,
    this.contactAvatarUrl,
    this.messageType = WhatsAppMessageType.text,
    this.direction = WhatsAppMessageDirection.inbound,
    this.message,
    this.mediaUrl,
    this.mediaMimeType,
    this.mediaFileName,
    this.status = WhatsAppMessageStatus.unknown,
    this.clientId,
    this.clientName,
    this.kanbanTaskId,
    this.userId,
    this.userName,
    this.isAiResponse = false,
    this.assignedToId,
    this.assignedToName,
    this.detectedSource,
    this.integrationSource = WhatsAppIntegrationSource.unknown,
    this.createdAt,
    this.readAt,
  });

  bool get isOutbound => direction == WhatsAppMessageDirection.outbound;
  bool get isInbound => direction == WhatsAppMessageDirection.inbound;

  /// Recebida e ainda não marcada como lida no CRM.
  bool get isUnread =>
      isInbound && readAt == null && status != WhatsAppMessageStatus.read;

  /// Texto de pré-visualização para a lista de conversas.
  String get preview {
    final text = (message ?? '').trim();
    if (text.isNotEmpty) return text;
    if (messageType.isMedia) return messageType.label;
    return 'Mensagem';
  }

  factory WhatsAppMessage.fromJson(Map<String, dynamic> json) {
    final user = _toMap(json['user']);
    final assignedTo = _toMap(json['assignedTo']);
    final client = _toMap(json['client']);
    return WhatsAppMessage(
      id: _toStringOrNull(json['id']) ?? '',
      phoneNumber: _toStringOrNull(json['phoneNumber']) ?? '',
      contactName: _toStringOrNull(json['contactName']),
      contactAvatarUrl: _toStringOrNull(json['contactAvatarUrl']),
      messageType:
          WhatsAppMessageType.fromRaw(_toStringOrNull(json['messageType'])),
      direction:
          WhatsAppMessageDirection.fromRaw(_toStringOrNull(json['direction'])),
      message: _toStringOrNull(json['message']),
      mediaUrl: _toStringOrNull(json['mediaUrl']),
      mediaMimeType: _toStringOrNull(json['mediaMimeType']),
      mediaFileName: _toStringOrNull(json['mediaFileName']),
      status: WhatsAppMessageStatus.fromRaw(_toStringOrNull(json['status'])),
      clientId: _toStringOrNull(json['clientId']) ??
          _toStringOrNull(client?['id']),
      clientName: _toStringOrNull(client?['name']),
      kanbanTaskId: _toStringOrNull(json['kanbanTaskId']),
      userId: _toStringOrNull(json['userId']),
      userName: _toStringOrNull(user?['name']),
      isAiResponse: _toBool(json['isAiResponse']),
      assignedToId: _toStringOrNull(json['assignedToId']) ??
          _toStringOrNull(assignedTo?['id']),
      assignedToName: _toStringOrNull(assignedTo?['name']),
      detectedSource: _toStringOrNull(json['detectedSource']),
      integrationSource: WhatsAppIntegrationSource.fromRaw(
          _toStringOrNull(json['integrationSource'])),
      createdAt: _toDate(json['createdAt']),
      readAt: _toDate(json['readAt']),
    );
  }
}

// ─── Conversa (agrupada por telefone) ────────────────────────────────────────

class WhatsAppConversation {
  final String phoneNumber;
  final String? contactName;
  final String? clientId;
  final String? clientName;
  final WhatsAppMessage? lastMessage;
  final int unreadCount;
  final int messageCount;
  final DateTime? lastMessageAt;
  final String? kanbanTaskId;

  const WhatsAppConversation({
    required this.phoneNumber,
    this.contactName,
    this.clientId,
    this.clientName,
    this.lastMessage,
    this.unreadCount = 0,
    this.messageCount = 0,
    this.lastMessageAt,
    this.kanbanTaskId,
  });

  /// Melhor nome para exibir: contato → cliente → telefone formatado.
  String get displayName {
    final contact = (contactName ?? '').trim();
    if (contact.isNotEmpty) return contact;
    final client = (clientName ?? '').trim();
    if (client.isNotEmpty) return client;
    return formatWhatsAppPhone(phoneNumber);
  }

  String get formattedPhone => formatWhatsAppPhone(phoneNumber);
  bool get hasUnread => unreadCount > 0;
  bool get hasTask =>
      (kanbanTaskId ?? lastMessage?.kanbanTaskId) != null;

  DateTime? get effectiveLastMessageAt =>
      lastMessageAt ?? lastMessage?.createdAt;

  factory WhatsAppConversation.fromJson(Map<String, dynamic> json) {
    final client = _toMap(json['client']);
    final last = _toMap(json['lastMessage']);
    return WhatsAppConversation(
      phoneNumber: _toStringOrNull(json['phoneNumber']) ?? '',
      contactName: _toStringOrNull(json['contactName']),
      clientId:
          _toStringOrNull(json['clientId']) ?? _toStringOrNull(client?['id']),
      clientName: _toStringOrNull(client?['name']),
      lastMessage: last != null ? WhatsAppMessage.fromJson(last) : null,
      unreadCount: _toInt(json['unreadCount']),
      messageCount: _toInt(json['messageCount']),
      lastMessageAt: _toDate(json['lastMessageAt']),
      kanbanTaskId: _toStringOrNull(json['kanbanTaskId']),
    );
  }

  /// Fallback quando o backend responde a lista plana de mensagens (sem
  /// `groupByPhone`): vira uma conversa por mensagem.
  factory WhatsAppConversation.fromMessage(WhatsAppMessage m) {
    return WhatsAppConversation(
      phoneNumber: m.phoneNumber,
      contactName: m.contactName,
      clientId: m.clientId,
      clientName: m.clientName,
      lastMessage: m,
      unreadCount: m.isUnread ? 1 : 0,
      messageCount: 1,
      lastMessageAt: m.createdAt,
      kanbanTaskId: m.kanbanTaskId,
    );
  }
}

// ─── Resultados paginados ────────────────────────────────────────────────────

class WhatsAppConversationListResult {
  final List<WhatsAppConversation> conversations;
  final int total;

  const WhatsAppConversationListResult({
    required this.conversations,
    required this.total,
  });

  static const empty =
      WhatsAppConversationListResult(conversations: [], total: 0);
}

class WhatsAppMessageListResult {
  final List<WhatsAppMessage> messages;
  final int total;

  const WhatsAppMessageListResult({required this.messages, required this.total});

  static const empty = WhatsAppMessageListResult(messages: [], total: 0);
}

// ─── Template aprovado (Meta Cloud API) ──────────────────────────────────────

class WhatsAppTemplate {
  final String name;
  final String language;
  final String status;
  final String? category;
  final int bodyVariableCount;
  final int headerVariableCount;

  const WhatsAppTemplate({
    required this.name,
    required this.language,
    required this.status,
    this.category,
    this.bodyVariableCount = 0,
    this.headerVariableCount = 0,
  });

  bool get isApproved => status.toUpperCase() == 'APPROVED';

  factory WhatsAppTemplate.fromJson(Map<String, dynamic> json) {
    return WhatsAppTemplate(
      name: _toStringOrNull(json['name']) ?? '',
      language: _toStringOrNull(json['language']) ?? 'pt_BR',
      status: _toStringOrNull(json['status']) ?? '',
      category: _toStringOrNull(json['category']),
      bodyVariableCount: _toInt(json['bodyVariableCount']),
      headerVariableCount: _toInt(json['headerVariableCount']),
    );
  }
}

// ─── Status das integrações (oficial × QR Code) ──────────────────────────────

/// Espelha `WhatsAppIntegrationStatus` de `types/whatsapp-unofficial.ts`.
class WhatsAppIntegrationStatus {
  final String activeProvider; // official | unofficial | both | none
  final bool officialConfigured;
  final bool unofficialSessionActive;
  final String? chatIntegrationSource;
  final String? resolvedChatIntegrationSource;
  final String? phoneNumber;

  const WhatsAppIntegrationStatus({
    this.activeProvider = 'none',
    this.officialConfigured = false,
    this.unofficialSessionActive = false,
    this.chatIntegrationSource,
    this.resolvedChatIntegrationSource,
    this.phoneNumber,
  });

  /// Paridade com `isChatUsingUnofficialIntegration` do imobx-front.
  bool get usesUnofficialChat {
    final resolved = resolvedChatIntegrationSource;
    if (resolved != null && resolved.isNotEmpty) {
      return resolved == 'unofficial';
    }
    if (activeProvider == 'unofficial') return true;
    if (activeProvider == 'official') return false;
    if (activeProvider == 'both') return chatIntegrationSource != 'official';
    return unofficialSessionActive;
  }

  WhatsAppIntegrationSource get chatSource => usesUnofficialChat
      ? WhatsAppIntegrationSource.unofficial
      : WhatsAppIntegrationSource.official;

  bool get hasAnyChannel => activeProvider != 'none';

  factory WhatsAppIntegrationStatus.fromJson(Map<String, dynamic> json) {
    return WhatsAppIntegrationStatus(
      activeProvider: _toStringOrNull(json['activeProvider']) ?? 'none',
      officialConfigured: _toBool(json['officialConfigured']),
      unofficialSessionActive: _toBool(json['unofficialSessionActive']),
      chatIntegrationSource: _toStringOrNull(json['chatIntegrationSource']),
      resolvedChatIntegrationSource:
          _toStringOrNull(json['resolvedChatIntegrationSource']),
      phoneNumber: _toStringOrNull(json['phoneNumber']),
    );
  }
}

// ─── Filtros do inbox ────────────────────────────────────────────────────────

/// Filtros do painel (espelha `WhatsAppMessagesQueryParams` — subconjunto que
/// faz sentido no app). Abas de atendimento e busca ficam fora daqui.
class WhatsAppInboxFilters {
  final bool unreadOnly;
  final bool? hasTask;
  final WhatsAppMessageType? messageType;
  final DateTime? startDate;
  final DateTime? endDate;

  const WhatsAppInboxFilters({
    this.unreadOnly = false,
    this.hasTask,
    this.messageType,
    this.startDate,
    this.endDate,
  });

  int get activeCount {
    var n = 0;
    if (unreadOnly) n++;
    if (hasTask != null) n++;
    if (messageType != null) n++;
    if (startDate != null) n++;
    if (endDate != null) n++;
    return n;
  }

  bool get isEmpty => activeCount == 0;

  static String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, String> toQueryParams() {
    final params = <String, String>{};
    if (unreadOnly) params['unreadOnly'] = 'true';
    if (hasTask != null) params['hasTask'] = hasTask.toString();
    if (messageType != null) params['messageType'] = messageType!.apiValue;
    if (startDate != null) params['startDate'] = _fmtDate(startDate!);
    if (endDate != null) params['endDate'] = _fmtDate(endDate!);
    return params;
  }
}
