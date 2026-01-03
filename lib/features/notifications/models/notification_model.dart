/// Modelo de dados para Notificação
class NotificationModel {
  final String id;
  final String type;
  final NotificationPriority priority;
  final String title;
  final String message;
  final bool read;
  final DateTime? readAt;
  final String? actionUrl;
  final String? entityType;
  final String? entityId;
  final Map<String, dynamic>? metadata;
  final String userId;
  final String? companyId;
  final DateTime createdAt;
  final DateTime updatedAt;

  NotificationModel({
    required this.id,
    required this.type,
    required this.priority,
    required this.title,
    required this.message,
    required this.read,
    this.readAt,
    this.actionUrl,
    this.entityType,
    this.entityId,
    this.metadata,
    required this.userId,
    this.companyId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      priority: _parsePriority(json['priority']?.toString() ?? 'low'),
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      read: json['read'] as bool? ?? false,
      readAt: json['readAt'] != null
          ? DateTime.parse(json['readAt'].toString())
          : null,
      actionUrl: json['actionUrl']?.toString(),
      entityType: json['entityType']?.toString(),
      entityId: json['entityId']?.toString(),
      metadata: json['metadata'] as Map<String, dynamic>?,
      userId: json['userId']?.toString() ?? '',
      companyId: json['companyId']?.toString(),
      createdAt: DateTime.parse(json['createdAt'].toString()),
      updatedAt: DateTime.parse(json['updatedAt'].toString()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'priority': priority.name,
      'title': title,
      'message': message,
      'read': read,
      'readAt': readAt?.toIso8601String(),
      'actionUrl': actionUrl,
      'entityType': entityType,
      'entityId': entityId,
      'metadata': metadata,
      'userId': userId,
      'companyId': companyId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  NotificationModel copyWith({
    String? id,
    String? type,
    NotificationPriority? priority,
    String? title,
    String? message,
    bool? read,
    DateTime? readAt,
    String? actionUrl,
    String? entityType,
    String? entityId,
    Map<String, dynamic>? metadata,
    String? userId,
    String? companyId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      type: type ?? this.type,
      priority: priority ?? this.priority,
      title: title ?? this.title,
      message: message ?? this.message,
      read: read ?? this.read,
      readAt: readAt ?? this.readAt,
      actionUrl: actionUrl ?? this.actionUrl,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      metadata: metadata ?? this.metadata,
      userId: userId ?? this.userId,
      companyId: companyId ?? this.companyId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static NotificationPriority _parsePriority(String priority) {
    switch (priority.toLowerCase()) {
      case 'urgent':
        return NotificationPriority.urgent;
      case 'high':
        return NotificationPriority.high;
      case 'medium':
        return NotificationPriority.medium;
      case 'low':
      default:
        return NotificationPriority.low;
    }
  }
}

/// Prioridades de notificação
enum NotificationPriority {
  urgent,
  high,
  medium,
  low;

  String get label {
    switch (this) {
      case NotificationPriority.urgent:
        return 'Urgente';
      case NotificationPriority.high:
        return 'Alta';
      case NotificationPriority.medium:
        return 'Média';
      case NotificationPriority.low:
        return 'Baixa';
    }
  }

  /// Cores para cada prioridade
  String get color {
    switch (this) {
      case NotificationPriority.urgent:
        return '#dc2626'; // vermelho
      case NotificationPriority.high:
        return '#ea580c'; // laranja
      case NotificationPriority.medium:
        return '#2563eb'; // azul
      case NotificationPriority.low:
        return '#64748b'; // cinza
    }
  }

  /// Ícones para cada prioridade
  String get icon {
    switch (this) {
      case NotificationPriority.urgent:
        return 'alert-circle';
      case NotificationPriority.high:
        return 'alert-triangle';
      case NotificationPriority.medium:
        return 'info';
      case NotificationPriority.low:
        return 'message-circle';
    }
  }
}

/// Resposta da lista de notificações
class NotificationListResponse {
  final List<NotificationModel> notifications;
  final int total;
  final int page;
  final int limit;
  final int totalPages;
  final int unreadCount;

  NotificationListResponse({
    required this.notifications,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
    required this.unreadCount,
  });

  factory NotificationListResponse.fromJson(Map<String, dynamic> json) {
    return NotificationListResponse(
      notifications: (json['notifications'] as List<dynamic>?)
              ?.map((e) => NotificationModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      total: json['total'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      limit: json['limit'] as int? ?? 20,
      totalPages: json['totalPages'] as int? ?? 0,
      unreadCount: json['unreadCount'] as int? ?? 0,
    );
  }
}

/// Parâmetros de query para listar notificações
class NotificationQueryParams {
  final bool? read;
  final String? type;
  final String? companyId;
  final int? page;
  final int? limit;

  NotificationQueryParams({
    this.read,
    this.type,
    this.companyId,
    this.page,
    this.limit,
  });

  Map<String, String> toQueryMap() {
    final map = <String, String>{};
    if (read != null) {
      map['read'] = read.toString();
    }
    if (type != null && type!.isNotEmpty) {
      map['type'] = type!;
    }
    if (companyId != null && companyId!.isNotEmpty) {
      map['companyId'] = companyId!;
    }
    if (page != null) {
      map['page'] = page.toString();
    }
    if (limit != null) {
      map['limit'] = limit.toString();
    }
    return map;
  }
}

/// Resposta de contador de não lidas
class UnreadCountResponse {
  final int count;

  UnreadCountResponse({required this.count});

  factory UnreadCountResponse.fromJson(Map<String, dynamic> json) {
    return UnreadCountResponse(
      count: json['count'] as int? ?? 0,
    );
  }
}

/// Resposta de contador por empresa
class UnreadCountByCompanyResponse {
  final Map<String, int> countByCompany;

  UnreadCountByCompanyResponse({required this.countByCompany});

  factory UnreadCountByCompanyResponse.fromJson(Map<String, dynamic> json) {
    final countByCompany = <String, int>{};
    if (json['countByCompany'] != null) {
      (json['countByCompany'] as Map<String, dynamic>).forEach((key, value) {
        countByCompany[key] = value as int? ?? 0;
      });
    }
    return UnreadCountByCompanyResponse(countByCompany: countByCompany);
  }
}

/// Resposta de marcação em massa
class BulkReadResponse {
  final int affected;
  final int unreadCount;

  BulkReadResponse({
    required this.affected,
    required this.unreadCount,
  });

  factory BulkReadResponse.fromJson(Map<String, dynamic> json) {
    return BulkReadResponse(
      affected: json['affected'] as int? ?? 0,
      unreadCount: json['unreadCount'] as int? ?? 0,
    );
  }
}

/// Metadata de notificação de match de propriedade
class PropertyMatchNotificationMetadata {
  final String propertyId;
  final String propertyTitle;
  final String? propertyCode;
  final int totalMatches;
  final int highScoreMatches;
  final String? propertyType;
  final String? propertyCity;
  final String? propertyState;
  final double? propertyPrice;
  final List<MatchScore>? matchScores;

  PropertyMatchNotificationMetadata({
    required this.propertyId,
    required this.propertyTitle,
    this.propertyCode,
    required this.totalMatches,
    required this.highScoreMatches,
    this.propertyType,
    this.propertyCity,
    this.propertyState,
    this.propertyPrice,
    this.matchScores,
  });

  factory PropertyMatchNotificationMetadata.fromJson(
      Map<String, dynamic> json) {
    return PropertyMatchNotificationMetadata(
      propertyId: json['propertyId']?.toString() ?? '',
      propertyTitle: json['propertyTitle']?.toString() ?? '',
      propertyCode: json['propertyCode']?.toString(),
      totalMatches: json['totalMatches'] as int? ?? 0,
      highScoreMatches: json['highScoreMatches'] as int? ?? 0,
      propertyType: json['propertyType']?.toString(),
      propertyCity: json['propertyCity']?.toString(),
      propertyState: json['propertyState']?.toString(),
      propertyPrice: (json['propertyPrice'] as num?)?.toDouble(),
      matchScores: json['matchScores'] != null
          ? (json['matchScores'] as List<dynamic>)
              .map((e) => MatchScore.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
    );
  }
}

class MatchScore {
  final String clientId;
  final double score;

  MatchScore({
    required this.clientId,
    required this.score,
  });

  factory MatchScore.fromJson(Map<String, dynamic> json) {
    return MatchScore(
      clientId: json['clientId']?.toString() ?? '',
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
    );
  }
}









