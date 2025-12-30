/// Modelos de dados para Chat

/// Tipo de Sala de Chat
enum ChatRoomType {
  direct('direct', 'Direto'),
  group('group', 'Grupo'),
  support('support', 'Suporte');

  final String value;
  final String label;

  const ChatRoomType(this.value, this.label);

  static ChatRoomType fromString(String? value) {
    if (value == null) return direct;
    return ChatRoomType.values.firstWhere(
      (e) => e.value == value.toLowerCase(),
      orElse: () => direct,
    );
  }
}

/// Status de Mensagem
enum ChatMessageStatus {
  sending('sending', 'Enviando'),
  sent('sent', 'Enviado'),
  delivered('delivered', 'Entregue'),
  read('read', 'Lido');

  final String value;
  final String label;

  const ChatMessageStatus(this.value, this.label);

  static ChatMessageStatus fromString(String? value) {
    if (value == null) return sent;
    return ChatMessageStatus.values.firstWhere(
      (e) => e.value == value.toLowerCase(),
      orElse: () => sent,
    );
  }
}

/// Tipo de Evento do Sistema
enum ChatSystemEventType {
  participantJoined('participant_joined', 'Participante entrou'),
  participantLeft('participant_left', 'Participante saiu'),
  participantRemoved('participant_removed', 'Participante removido');

  final String value;
  final String label;

  const ChatSystemEventType(this.value, this.label);

  static ChatSystemEventType? fromString(String? value) {
    if (value == null) return null;
    try {
      return ChatSystemEventType.values.firstWhere(
        (e) => e.value == value.toLowerCase(),
      );
    } catch (e) {
      return null;
    }
  }
}

/// Participante do Chat
class ChatParticipant {
  final String id;
  final String userId;
  final String userName;
  final String? userAvatar;
  final bool isActive;
  final bool? isAdmin;
  final DateTime? lastReadAt;
  final DateTime joinedAt;

  ChatParticipant({
    required this.id,
    required this.userId,
    required this.userName,
    this.userAvatar,
    required this.isActive,
    this.isAdmin,
    this.lastReadAt,
    required this.joinedAt,
  });

  factory ChatParticipant.fromJson(Map<String, dynamic> json) {
    return ChatParticipant(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? json['user_id']?.toString() ?? '',
      userName:
          json['userName']?.toString() ?? json['user_name']?.toString() ?? '',
      userAvatar:
          json['userAvatar']?.toString() ?? json['user_avatar']?.toString(),
      isActive: json['isActive'] as bool? ?? json['is_active'] as bool? ?? true,
      isAdmin: json['isAdmin'] as bool? ?? json['is_admin'] as bool?,
      lastReadAt: json['lastReadAt'] != null || json['last_read_at'] != null
          ? DateTime.parse(
              json['lastReadAt']?.toString() ??
                  json['last_read_at']?.toString() ??
                  '',
            )
          : null,
      joinedAt: DateTime.parse(
        json['joinedAt']?.toString() ?? json['joined_at']?.toString() ?? '',
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'userName': userName,
      if (userAvatar != null) 'userAvatar': userAvatar,
      'isActive': isActive,
      if (isAdmin != null) 'isAdmin': isAdmin,
      if (lastReadAt != null) 'lastReadAt': lastReadAt?.toIso8601String(),
      'joinedAt': joinedAt.toIso8601String(),
    };
  }
}

/// Sala de Chat
class ChatRoom {
  final String id;
  final String companyId;
  final ChatRoomType type;
  final String? name;
  final String? createdBy;
  final String? imageUrl;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final List<ChatParticipant> participants;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool? isArchived;
  final int? unreadCount;

  ChatRoom({
    required this.id,
    required this.companyId,
    required this.type,
    this.name,
    this.createdBy,
    this.imageUrl,
    this.lastMessage,
    this.lastMessageAt,
    required this.participants,
    required this.createdAt,
    required this.updatedAt,
    this.isArchived,
    this.unreadCount,
  });

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    final participantsList = json['participants'] as List<dynamic>? ?? [];

    return ChatRoom(
      id: json['id']?.toString() ?? '',
      companyId:
          json['companyId']?.toString() ?? json['company_id']?.toString() ?? '',
      type: ChatRoomType.fromString(json['type']?.toString()),
      name: json['name']?.toString(),
      createdBy:
          json['createdBy']?.toString() ?? json['created_by']?.toString(),
      imageUrl: json['imageUrl']?.toString() ?? json['image_url']?.toString(),
      lastMessage:
          json['lastMessage']?.toString() ?? json['last_message']?.toString(),
      lastMessageAt:
          json['lastMessageAt'] != null || json['last_message_at'] != null
          ? DateTime.parse(
              json['lastMessageAt']?.toString() ??
                  json['last_message_at']?.toString() ??
                  '',
            )
          : null,
      participants: participantsList
          .map((p) => ChatParticipant.fromJson(p as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(
        json['createdAt']?.toString() ?? json['created_at']?.toString() ?? '',
      ),
      updatedAt: DateTime.parse(
        json['updatedAt']?.toString() ?? json['updated_at']?.toString() ?? '',
      ),
      isArchived: json['isArchived'] as bool? ?? json['is_archived'] as bool?,
      unreadCount:
          (json['unreadCount'] as num?)?.toInt() ??
          (json['unread_count'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'companyId': companyId,
      'type': type.value,
      if (name != null) 'name': name,
      if (createdBy != null) 'createdBy': createdBy,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (lastMessage != null) 'lastMessage': lastMessage,
      if (lastMessageAt != null)
        'lastMessageAt': lastMessageAt?.toIso8601String(),
      'participants': participants.map((p) => p.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      if (isArchived != null) 'isArchived': isArchived,
      if (unreadCount != null) 'unreadCount': unreadCount,
    };
  }

  /// Retorna o nome de exibição da sala
  String getDisplayName(String? currentUserId) {
    if (type == ChatRoomType.support) {
      return 'Suporte';
    }

    if (type == ChatRoomType.group && name != null && name!.isNotEmpty) {
      return name!;
    }

    if (type == ChatRoomType.direct) {
      // Para conversas diretas, retorna o nome do outro participante
      final otherParticipant = participants.firstWhere(
        (p) => p.userId != currentUserId,
        orElse: () => participants.first,
      );
      return otherParticipant.userName;
    }

    return name ?? 'Chat sem nome';
  }

  /// Retorna a imagem de exibição da sala
  String? getDisplayImage(String? currentUserId) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return imageUrl;
    }

    if (type == ChatRoomType.direct) {
      // Para conversas diretas, retorna o avatar do outro participante
      final otherParticipant = participants.firstWhere(
        (p) => p.userId != currentUserId,
        orElse: () => participants.first,
      );
      return otherParticipant.userAvatar;
    }

    return null;
  }
}

/// Mensagem de Chat
class ChatMessage {
  final String id;
  final String roomId;
  final String senderId;
  final String senderName;
  final String? senderAvatar;
  final String content;
  final String? imageUrl;
  final String? fileUrl;
  final String? fileName;
  final String? fileType;
  final String? documentUrl;
  final String? documentName;
  final String? documentMimeType;
  final ChatMessageStatus status;
  final bool isEdited;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? tempId;
  final bool? isPending;
  final bool? isSystemMessage;
  final ChatSystemEventType? systemEventType;

  ChatMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.senderName,
    this.senderAvatar,
    required this.content,
    this.imageUrl,
    this.fileUrl,
    this.fileName,
    this.fileType,
    this.documentUrl,
    this.documentName,
    this.documentMimeType,
    required this.status,
    required this.isEdited,
    required this.isDeleted,
    required this.createdAt,
    required this.updatedAt,
    this.tempId,
    this.isPending,
    this.isSystemMessage,
    this.systemEventType,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id']?.toString() ?? '',
      roomId: json['roomId']?.toString() ?? json['room_id']?.toString() ?? '',
      senderId:
          json['senderId']?.toString() ?? json['sender_id']?.toString() ?? '',
      senderName:
          json['senderName']?.toString() ??
          json['sender_name']?.toString() ??
          '',
      senderAvatar:
          json['senderAvatar']?.toString() ?? json['sender_avatar']?.toString(),
      content: json['content']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString() ?? json['image_url']?.toString(),
      fileUrl: json['fileUrl']?.toString() ?? json['file_url']?.toString(),
      fileName: json['fileName']?.toString() ?? json['file_name']?.toString(),
      fileType: json['fileType']?.toString() ?? json['file_type']?.toString(),
      documentUrl:
          json['documentUrl']?.toString() ?? json['document_url']?.toString(),
      documentName:
          json['documentName']?.toString() ?? json['document_name']?.toString(),
      documentMimeType:
          json['documentMimeType']?.toString() ??
          json['document_mime_type']?.toString(),
      status: ChatMessageStatus.fromString(json['status']?.toString()),
      isEdited:
          json['isEdited'] as bool? ?? json['is_edited'] as bool? ?? false,
      isDeleted:
          json['isDeleted'] as bool? ?? json['is_deleted'] as bool? ?? false,
      createdAt: DateTime.parse(
        json['createdAt']?.toString() ?? json['created_at']?.toString() ?? '',
      ),
      updatedAt: DateTime.parse(
        json['updatedAt']?.toString() ?? json['updated_at']?.toString() ?? '',
      ),
      tempId: json['tempId']?.toString() ?? json['temp_id']?.toString(),
      isPending: json['isPending'] as bool? ?? json['is_pending'] as bool?,
      isSystemMessage:
          json['isSystemMessage'] as bool? ??
          json['is_system_message'] as bool? ??
          false,
      systemEventType: ChatSystemEventType.fromString(
        json['systemEventType']?.toString() ??
            json['system_event_type']?.toString(),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'roomId': roomId,
      'senderId': senderId,
      'senderName': senderName,
      if (senderAvatar != null) 'senderAvatar': senderAvatar,
      'content': content,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (fileUrl != null) 'fileUrl': fileUrl,
      if (fileName != null) 'fileName': fileName,
      if (fileType != null) 'fileType': fileType,
      if (documentUrl != null) 'documentUrl': documentUrl,
      if (documentName != null) 'documentName': documentName,
      if (documentMimeType != null) 'documentMimeType': documentMimeType,
      'status': status.value,
      'isEdited': isEdited,
      'isDeleted': isDeleted,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      if (tempId != null) 'tempId': tempId,
      if (isPending != null) 'isPending': isPending,
      if (isSystemMessage != null) 'isSystemMessage': isSystemMessage,
      if (systemEventType != null) 'systemEventType': systemEventType!.value,
    };
  }

  /// Verifica se a mensagem tem anexo
  bool get hasAttachment {
    return imageUrl != null || fileUrl != null || documentUrl != null;
  }

  /// Retorna a URL do anexo (prioriza documento, depois arquivo, depois imagem)
  String? get attachmentUrl {
    return documentUrl ?? fileUrl ?? imageUrl;
  }

  /// Retorna o nome do anexo
  String? get attachmentName {
    return documentName ?? fileName;
  }

  /// Verifica se pode ser deletada (menos de 5 minutos)
  bool canBeDeleted() {
    final now = DateTime.now();
    final difference = now.difference(createdAt);
    return difference.inMinutes < 5;
  }
}

/// Usuário da Empresa (para seleção no chat)
class CompanyUser {
  final String id;
  final String name;
  final String email;
  final String? avatar;
  final String? phone;
  final String role;
  final bool isOnline;
  final DateTime? lastActivity;

  CompanyUser({
    required this.id,
    required this.name,
    required this.email,
    this.avatar,
    this.phone,
    required this.role,
    required this.isOnline,
    this.lastActivity,
  });

  factory CompanyUser.fromJson(Map<String, dynamic> json) {
    return CompanyUser(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      avatar: json['avatar']?.toString(),
      phone: json['phone']?.toString(),
      role: json['role']?.toString() ?? '',
      isOnline:
          json['isOnline'] as bool? ?? json['is_online'] as bool? ?? false,
      lastActivity:
          json['lastActivity'] != null || json['last_activity'] != null
          ? DateTime.parse(
              json['lastActivity']?.toString() ??
                  json['last_activity']?.toString() ??
                  '',
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      if (avatar != null) 'avatar': avatar,
      if (phone != null) 'phone': phone,
      'role': role,
      'isOnline': isOnline,
      if (lastActivity != null) 'lastActivity': lastActivity?.toIso8601String(),
    };
  }
}

/// Histórico da Sala
class ChatRoomHistory {
  final String roomId;
  final String name;
  final String? createdBy;
  final String? createdByName;
  final DateTime createdAt;
  final List<ChatRoomHistoryParticipant> participants;

  ChatRoomHistory({
    required this.roomId,
    required this.name,
    this.createdBy,
    this.createdByName,
    required this.createdAt,
    required this.participants,
  });

  factory ChatRoomHistory.fromJson(Map<String, dynamic> json) {
    final participantsList = json['participants'] as List<dynamic>? ?? [];

    return ChatRoomHistory(
      roomId: json['roomId']?.toString() ?? json['room_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      createdBy:
          json['createdBy']?.toString() ?? json['created_by']?.toString(),
      createdByName:
          json['createdByName']?.toString() ??
          json['created_by_name']?.toString(),
      createdAt: DateTime.parse(
        json['createdAt']?.toString() ?? json['created_at']?.toString() ?? '',
      ),
      participants: participantsList
          .map(
            (p) =>
                ChatRoomHistoryParticipant.fromJson(p as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'roomId': roomId,
      'name': name,
      if (createdBy != null) 'createdBy': createdBy,
      if (createdByName != null) 'createdByName': createdByName,
      'createdAt': createdAt.toIso8601String(),
      'participants': participants.map((p) => p.toJson()).toList(),
    };
  }
}

/// Participante do Histórico
class ChatRoomHistoryParticipant {
  final String userId;
  final String userName;
  final bool isAdmin;
  final DateTime joinedAt;
  final DateTime? leftAt;
  final bool isActive;

  ChatRoomHistoryParticipant({
    required this.userId,
    required this.userName,
    required this.isAdmin,
    required this.joinedAt,
    this.leftAt,
    required this.isActive,
  });

  factory ChatRoomHistoryParticipant.fromJson(Map<String, dynamic> json) {
    return ChatRoomHistoryParticipant(
      userId: json['userId']?.toString() ?? json['user_id']?.toString() ?? '',
      userName:
          json['userName']?.toString() ?? json['user_name']?.toString() ?? '',
      isAdmin: json['isAdmin'] as bool? ?? json['is_admin'] as bool? ?? false,
      joinedAt: DateTime.parse(
        json['joinedAt']?.toString() ?? json['joined_at']?.toString() ?? '',
      ),
      leftAt: json['leftAt'] != null || json['left_at'] != null
          ? DateTime.parse(
              json['leftAt']?.toString() ?? json['left_at']?.toString() ?? '',
            )
          : null,
      isActive: json['isActive'] as bool? ?? json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'userName': userName,
      'isAdmin': isAdmin,
      'joinedAt': joinedAt.toIso8601String(),
      if (leftAt != null) 'leftAt': leftAt?.toIso8601String(),
      'isActive': isActive,
    };
  }
}
