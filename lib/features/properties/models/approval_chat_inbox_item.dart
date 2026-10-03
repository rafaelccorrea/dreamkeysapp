/// Hora da última mensagem na lista, estilo caixa de mensagens: "agora",
/// "12 min", "14:05" (hoje), "ontem", "dd/mm" (este ano) ou "dd/mm/aa".
String formatApprovalInboxTime(DateTime? at, {DateTime? now}) {
  if (at == null) return '';
  final ref = now ?? DateTime.now();
  final diff = ref.difference(at);
  String two(int v) => v.toString().padLeft(2, '0');
  if (diff.inMinutes < 1 && !diff.isNegative) return 'agora';
  if (diff.inMinutes < 60 && !diff.isNegative) return '${diff.inMinutes} min';
  final today = DateTime(ref.year, ref.month, ref.day);
  final day = DateTime(at.year, at.month, at.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return '${two(at.hour)}:${two(at.minute)}';
  if (days == 1) return 'ontem';
  if (at.year == ref.year) return '${two(at.day)}/${two(at.month)}';
  return '${two(at.day)}/${two(at.month)}/${two(at.year % 100)}';
}

/// Item da **caixa de conversas de aprovação** (`GET
/// /properties/approval-chat-inbox`) — uma conversa por imóvel × fila
/// (cadastro/disponibilidade ou publicação no site). Mesmo formato do
/// `ApprovalChatInboxItem` do web (`propertyApi.ts`). O back só devolve as
/// conversas de que o usuário participa.
class ApprovalChatInboxItem {
  final String propertyId;
  final String propertyTitle;
  final String? propertyCode;

  /// `availability` ou `publication`.
  final String approvalContext;
  final int messageCount;
  final int unreadCount;
  final bool isViewed;
  final DateTime? lastViewedAt;
  final DateTime? lastMessageAt;
  final String? lastPreview;
  final String? lastUserName;

  const ApprovalChatInboxItem({
    required this.propertyId,
    required this.propertyTitle,
    required this.approvalContext,
    this.propertyCode,
    this.messageCount = 0,
    this.unreadCount = 0,
    this.isViewed = true,
    this.lastViewedAt,
    this.lastMessageAt,
    this.lastPreview,
    this.lastUserName,
  });

  /// Fila de publicação no site (o resto é cadastro/disponibilidade, como o
  /// web lê).
  bool get isPublication => approvalContext == 'publication';

  bool get hasUnread => unreadCount > 0;

  /// Chave única da conversa (imóvel × fila) — `convKey` do web.
  String get key => '$propertyId::$approvalContext';

  /// Texto da segunda linha: "Fulano: prévia", senão o código, senão
  /// "Sem mensagens" (regra do web).
  String get previewLine {
    final preview = lastPreview?.trim() ?? '';
    if (preview.isNotEmpty) {
      final who = lastUserName?.trim() ?? '';
      return who.isEmpty ? preview : '$who: $preview';
    }
    final code = propertyCode?.trim() ?? '';
    if (code.isNotEmpty) return 'Cód. $code';
    return 'Sem mensagens';
  }

  ApprovalChatInboxItem markedAsSeen() => ApprovalChatInboxItem(
        propertyId: propertyId,
        propertyTitle: propertyTitle,
        approvalContext: approvalContext,
        propertyCode: propertyCode,
        messageCount: messageCount,
        unreadCount: 0,
        isViewed: true,
        lastViewedAt: DateTime.now(),
        lastMessageAt: lastMessageAt,
        lastPreview: lastPreview,
        lastUserName: lastUserName,
      );

  static ApprovalChatInboxItem? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final id = map['propertyId']?.toString().trim() ?? '';
    if (id.isEmpty) return null;
    String? text(dynamic v) {
      final s = v?.toString().trim() ?? '';
      return s.isEmpty ? null : s;
    }

    int count(dynamic v) {
      if (v is int) return v < 0 ? 0 : v;
      if (v is num) return v < 0 ? 0 : v.toInt();
      final n = int.tryParse('${v ?? ''}') ?? 0;
      return n < 0 ? 0 : n;
    }

    DateTime? date(dynamic v) {
      final s = text(v);
      return s == null ? null : DateTime.tryParse(s)?.toLocal();
    }

    final ctx = text(map['approvalContext'])?.toLowerCase();
    return ApprovalChatInboxItem(
      propertyId: id,
      propertyTitle: text(map['propertyTitle']) ?? '',
      propertyCode: text(map['propertyCode']),
      approvalContext: ctx == 'publication' ? 'publication' : 'availability',
      messageCount: count(map['messageCount']),
      unreadCount: count(map['unreadCount']),
      isViewed: map['isViewed'] != false,
      lastViewedAt: date(map['lastViewedAt']),
      lastMessageAt: date(map['lastMessageAt']),
      lastPreview: text(map['lastPreview']),
      lastUserName: text(map['lastUserName']),
    );
  }

  /// Lista da resposta (array direto ou `{ data: [...] }`), na ordem do back
  /// (mais recente primeiro).
  static List<ApprovalChatInboxItem> listFrom(dynamic raw) {
    final list = raw is List
        ? raw
        : (raw is Map && raw['data'] is List ? raw['data'] as List : const []);
    return list
        .map(ApprovalChatInboxItem.fromJson)
        .whereType<ApprovalChatInboxItem>()
        .toList();
  }

  /// Soma das não lidas (chip "Não lidas" do web).
  static int totalUnread(Iterable<ApprovalChatInboxItem> items) =>
      items.fold(0, (acc, it) => acc + it.unreadCount);

  /// Busca local do web: título, código, prévia e autor.
  static List<ApprovalChatInboxItem> filter(
    List<ApprovalChatInboxItem> items,
    String query,
  ) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items.where((it) {
      final hay = '${it.propertyTitle} ${it.propertyCode ?? ''} '
              '${it.lastPreview ?? ''} ${it.lastUserName ?? ''}'
          .toLowerCase();
      return hay.contains(q);
    }).toList();
  }
}
