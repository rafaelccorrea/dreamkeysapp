/// Modelos do Zezin (assistente de IA) — paridade com
/// `imobx-front/src/types/zezin.ts`.
///
/// Todos os `fromJson` são defensivos: toleram `null`, número vindo como
/// string, boolean como string, etc. (o backend NestJS às vezes serializa
/// campos de formas diferentes conforme a rota).
library;

String _asString(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  if (v is String) return v;
  return v.toString();
}

String? _asStringOrNull(dynamic v) {
  if (v == null) return null;
  final s = v is String ? v : v.toString();
  return s.trim().isEmpty ? null : s;
}

bool _asBool(dynamic v, [bool fallback = false]) {
  if (v == null) return fallback;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().toLowerCase().trim();
  if (s == 'true' || s == '1' || s == 'yes') return true;
  if (s == 'false' || s == '0' || s == 'no') return false;
  return fallback;
}

int _asInt(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? fallback;
}

DateTime? _asDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  return DateTime.tryParse(v.toString());
}

/// `GET /whatsapp/zezin/availability` — Zezin é exclusivo para
/// administradores/donos no plano Pro com o módulo Assistente de IA.
class ZezinAvailability {
  const ZezinAvailability({
    required this.available,
    this.assistantName = 'Zezin',
    this.configConfigured = false,
  });

  final bool available;
  final String assistantName;

  /// Se número e token do WhatsApp já foram configurados em `/zezin/config`.
  final bool configConfigured;

  factory ZezinAvailability.fromJson(Map<String, dynamic> json) {
    return ZezinAvailability(
      available: _asBool(json['available']),
      assistantName: _asString(json['assistantName'], 'Zezin'),
      configConfigured: _asBool(json['configConfigured']),
    );
  }

  static const ZezinAvailability unavailable =
      ZezinAvailability(available: false);
}

/// Configuração do Zezin (número + token do WhatsApp Business).
/// O `apiToken` volta **mascarado** do backend (ex.: `************5678`).
class ZezinConfig {
  const ZezinConfig({
    required this.id,
    required this.companyId,
    required this.phoneNumberId,
    this.phoneNumber,
    this.apiTokenMasked,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String companyId;
  final String phoneNumberId;
  final String? phoneNumber;

  /// Token mascarado — nunca é o valor real; não reexibir em campos de edição.
  final String? apiTokenMasked;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ZezinConfig.fromJson(Map<String, dynamic> json) {
    return ZezinConfig(
      id: _asString(json['id']),
      companyId: _asString(json['companyId']),
      phoneNumberId: _asString(json['phoneNumberId']),
      phoneNumber: _asStringOrNull(json['phoneNumber']),
      apiTokenMasked: _asStringOrNull(json['apiToken']),
      isActive: _asBool(json['isActive'], true),
      createdAt: _asDate(json['createdAt']),
      updatedAt: _asDate(json['updatedAt']),
    );
  }
}

/// Sugestão de pergunta (atalho com dados reais) —
/// `GET /whatsapp/zezin/suggested-questions[-follow-up]`.
class ZezinSuggestedQuestion {
  const ZezinSuggestedQuestion({
    required this.id,
    required this.label,
    required this.message,
  });

  final String id;

  /// Texto curto exibido no chip.
  final String label;

  /// Mensagem completa enviada ao Zezin quando o chip é tocado.
  final String message;

  factory ZezinSuggestedQuestion.fromJson(Map<String, dynamic> json) {
    final label = _asString(json['label']);
    return ZezinSuggestedQuestion(
      id: _asString(json['id'], label),
      label: label,
      message: _asString(json['message'], label),
    );
  }

  static List<ZezinSuggestedQuestion> listFromJson(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) =>
            ZezinSuggestedQuestion.fromJson(Map<String, dynamic>.from(e)))
        .where((q) => q.label.trim().isNotEmpty)
        .toList(growable: false);
  }
}

/// Uma conversa (thread) do histórico — `GET /whatsapp/zezin/history`.
class ZezinThreadSummary {
  const ZezinThreadSummary({
    required this.threadId,
    required this.title,
    this.updatedAt,
    this.messageCount = 0,
  });

  final String threadId;
  final String title;
  final DateTime? updatedAt;
  final int messageCount;

  factory ZezinThreadSummary.fromJson(Map<String, dynamic> json) {
    return ZezinThreadSummary(
      threadId: _asString(json['threadId'], _asString(json['id'])),
      title: _asString(json['title'], 'Conversa'),
      updatedAt: _asDate(json['updatedAt'] ?? json['createdAt']),
      messageCount: _asInt(json['messageCount']),
    );
  }

  ZezinThreadSummary copyWith({
    String? title,
    DateTime? updatedAt,
    int? messageCount,
  }) {
    return ZezinThreadSummary(
      threadId: threadId,
      title: title ?? this.title,
      updatedAt: updatedAt ?? this.updatedAt,
      messageCount: messageCount ?? this.messageCount,
    );
  }
}

/// Item persistido do histórico (uma troca pergunta + resposta) —
/// `GET /whatsapp/zezin/history/thread/:threadId`.
class ZezinHistoryItem {
  const ZezinHistoryItem({
    required this.id,
    required this.message,
    required this.answer,
    this.title,
    this.createdAt,
    this.threadId,
  });

  final String id;
  final String message;
  final String answer;
  final String? title;
  final DateTime? createdAt;
  final String? threadId;

  factory ZezinHistoryItem.fromJson(Map<String, dynamic> json) {
    return ZezinHistoryItem(
      id: _asString(json['id']),
      message: _asString(json['message']),
      answer: _asString(json['answer']),
      title: _asStringOrNull(json['title']),
      createdAt: _asDate(json['createdAt']),
      threadId: _asStringOrNull(json['threadId']),
    );
  }
}

/// Papel de uma mensagem do chat local.
enum ZezinChatRole { user, assistant }

/// Mensagem exibida no chat (modelo de UI — inclui as trocas persistidas do
/// histórico e as mensagens da sessão atual, streaming incluso).
class ZezinChatMessage {
  ZezinChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.isStreaming = false,
    this.isError = false,
  });

  final String id;
  final ZezinChatRole role;
  String content;

  /// Resposta ainda chegando pelo stream (mostra cursor/indicador).
  bool isStreaming;

  /// Resposta terminou em erro (exibida com tom de alerta).
  bool isError;

  bool get isUser => role == ZezinChatRole.user;

  /// Converte trocas persistidas do histórico em pares de bolhas.
  static List<ZezinChatMessage> fromHistory(List<ZezinHistoryItem> items) {
    final list = <ZezinChatMessage>[];
    for (final item in items) {
      list.add(ZezinChatMessage(
        id: 'user-${item.id}',
        role: ZezinChatRole.user,
        content: item.message,
      ));
      list.add(ZezinChatMessage(
        id: 'assistant-${item.id}',
        role: ZezinChatRole.assistant,
        content: item.answer,
      ));
    }
    return list;
  }
}
