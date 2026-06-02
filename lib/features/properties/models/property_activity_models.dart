import '../../../shared/utils/json_datetime.dart';

/// Referência mínima de usuário em eventos/atualizações.
class PropertyUserRef {
  final String id;
  final String? name;
  final String? email;
  final String? avatar;

  const PropertyUserRef({
    required this.id,
    this.name,
    this.email,
    this.avatar,
  });

  static PropertyUserRef? fromJson(dynamic json) {
    if (json is! Map) return null;
    final map = Map<String, dynamic>.from(json);
    final id = map['id']?.toString();
    if (id == null || id.isEmpty) return null;
    return PropertyUserRef(
      id: id,
      name: map['name']?.toString(),
      email: map['email']?.toString(),
      avatar: map['avatar']?.toString(),
    );
  }
}

/// Entrada do histórico do imóvel (aba Atividades — "Histórico").
class PropertyHistoryEntry {
  final String id;
  final String event;
  final String? description;
  final PropertyUserRef? user;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  const PropertyHistoryEntry({
    required this.id,
    required this.event,
    required this.createdAt,
    this.description,
    this.user,
    this.metadata,
  });

  factory PropertyHistoryEntry.fromJson(Map<String, dynamic> json) {
    return PropertyHistoryEntry(
      id: json['id']?.toString() ?? '',
      event: json['event']?.toString() ?? 'updated',
      description: json['description']?.toString(),
      user: PropertyUserRef.fromJson(json['user']),
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : null,
      createdAt: parseApiDateTime(json['createdAt']),
    );
  }
}

/// Atualização do imóvel (aba Atividades — "Atualizações").
class PropertyUpdateEntry {
  final String id;
  final String content;
  final String source; // 'manual' | 'system'
  final PropertyUserRef? user;
  final DateTime createdAt;

  const PropertyUpdateEntry({
    required this.id,
    required this.content,
    required this.source,
    required this.createdAt,
    this.user,
  });

  bool get isSystem => source == 'system';

  factory PropertyUpdateEntry.fromJson(Map<String, dynamic> json) {
    return PropertyUpdateEntry(
      id: json['id']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      source: json['source']?.toString() ?? 'manual',
      user: PropertyUserRef.fromJson(json['user']),
      createdAt: parseApiDateTime(json['createdAt']),
    );
  }
}

/// Resposta paginada de atualizações.
class PropertyUpdatesResponse {
  final List<PropertyUpdateEntry> data;
  final int total;
  final int page;
  final int limit;

  const PropertyUpdatesResponse({
    required this.data,
    required this.total,
    required this.page,
    required this.limit,
  });

  static const empty = PropertyUpdatesResponse(
    data: [],
    total: 0,
    page: 1,
    limit: 20,
  );

  factory PropertyUpdatesResponse.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v, int fallback) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    final list = json['data'];
    return PropertyUpdatesResponse(
      data: list is List
          ? list
              .whereType<Map>()
              .map((e) =>
                  PropertyUpdateEntry.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      total: asInt(json['total'], 0),
      page: asInt(json['page'], 1),
      limit: asInt(json['limit'], 20),
    );
  }
}

/// Métricas de engajamento do imóvel (aba Desempenho).
class PropertyEngagementStats {
  final String propertyId;
  final int views;
  final int prints;
  final int whatsappClicks;
  final int phoneClicks;
  final int emailClicks;
  final int favorites;

  const PropertyEngagementStats({
    required this.propertyId,
    this.views = 0,
    this.prints = 0,
    this.whatsappClicks = 0,
    this.phoneClicks = 0,
    this.emailClicks = 0,
    this.favorites = 0,
  });

  int get total =>
      views + prints + whatsappClicks + phoneClicks + emailClicks + favorites;

  factory PropertyEngagementStats.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    return PropertyEngagementStats(
      propertyId: json['propertyId']?.toString() ?? '',
      views: asInt(json['views']),
      prints: asInt(json['prints']),
      whatsappClicks: asInt(json['whatsappClicks']),
      phoneClicks: asInt(json['phoneClicks']),
      emailClicks: asInt(json['emailClicks']),
      favorites: asInt(json['favorites']),
    );
  }
}

/// Engajamento por canal/origem (aba Desempenho — "Por origem").
class PropertyEngagementByChannel {
  final String channel;
  final String label;
  final int views;
  final int whatsappClicks;
  final int phoneClicks;
  final int emailClicks;
  final int favorites;
  final int shares;

  const PropertyEngagementByChannel({
    required this.channel,
    required this.label,
    this.views = 0,
    this.whatsappClicks = 0,
    this.phoneClicks = 0,
    this.emailClicks = 0,
    this.favorites = 0,
    this.shares = 0,
  });

  factory PropertyEngagementByChannel.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    return PropertyEngagementByChannel(
      channel: json['channel']?.toString() ?? '',
      label: json['label']?.toString() ?? json['channel']?.toString() ?? '',
      views: asInt(json['views']),
      whatsappClicks: asInt(json['whatsappClicks']),
      phoneClicks: asInt(json['phoneClicks']),
      emailClicks: asInt(json['emailClicks']),
      favorites: asInt(json['favorites']),
      shares: asInt(json['shares']),
    );
  }
}

/// Rótulos pt-BR dos eventos de histórico (espelha `propertyHistoryLabels.ts`).
String propertyHistoryEventLabel(String event) {
  switch (event) {
    case 'created':
      return 'Imóvel cadastrado';
    case 'status_changed':
      return 'Status alterado';
    case 'availability_requested':
      return 'Enviado para análise de cadastro';
    case 'availability_approved':
      return 'Disponibilidade aprovada';
    case 'availability_rejected':
      return 'Disponibilidade recusada';
    case 'owner_authorization_invalidated':
      return 'Autorização do proprietário invalidada';
    case 'owner_authorization_sent':
      return 'Autorização do proprietário enviada';
    case 'owner_authorization_signed':
      return 'Autorização do proprietário assinada';
    case 'owner_authorization_signature_waived':
      return 'Assinatura do proprietário dispensada';
    case 'publication_requested':
      return 'Publicação solicitada';
    case 'publication_approved':
      return 'Publicação aprovada';
    case 'publication_rejected':
      return 'Publicação recusada';
    case 'vote_cast':
      return 'Voto registrado';
    case 'vote_updated':
      return 'Voto atualizado';
    case 'approval_thread_message':
      return 'Mensagem na aprovação';
    case 'approval_reminder_sent':
      return 'Lembrete de aprovação enviado';
    case 'owner_contact_notify_requested':
      return 'Contato do proprietário solicitado';
    case 'marked_as_sold':
      return 'Marcado como vendido';
    case 'marked_as_rented':
      return 'Marcado como alugado';
    case 'updated':
      return 'Ficha atualizada';
    case 'deleted':
      return 'Imóvel excluído';
    case 'reverted_to_revision':
      return 'Revertido para versão anterior';
    case 'approval_rules_bulk_status':
      return 'Regras de aprovação atualizadas';
    case 'lifecycle_registration':
      return 'Cadastro inicial';
    case 'lifecycle_ficha_atualizada':
      return 'Ficha atualizada';
    default:
      return 'Atividade';
  }
}
