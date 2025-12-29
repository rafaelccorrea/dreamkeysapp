/// Modelos de dados do sistema Kanban

/// Prioridade da tarefa
enum KanbanPriority {
  low,
  medium,
  high,
  urgent;

  String get label {
    switch (this) {
      case KanbanPriority.low:
        return 'Baixa';
      case KanbanPriority.medium:
        return 'Média';
      case KanbanPriority.high:
        return 'Alta';
      case KanbanPriority.urgent:
        return 'Urgente';
    }
  }

  String get color {
    switch (this) {
      case KanbanPriority.low:
        return '#64748B';
      case KanbanPriority.medium:
        return '#3B82F6';
      case KanbanPriority.high:
        return '#F59E0B';
      case KanbanPriority.urgent:
        return '#EF4444';
    }
  }
}

/// Status do projeto
enum KanbanProjectStatus {
  active,
  completed,
  archived,
  cancelled;

  String get label {
    switch (this) {
      case KanbanProjectStatus.active:
        return 'Ativo';
      case KanbanProjectStatus.completed:
        return 'Concluído';
      case KanbanProjectStatus.archived:
        return 'Arquivado';
      case KanbanProjectStatus.cancelled:
        return 'Cancelado';
    }
  }
}

/// Coluna do Kanban
class KanbanColumn {
  final String id;
  final String title;
  final String? description;
  final String? color;
  final int position;
  final bool isActive;
  final String teamId;
  final String createdById;
  final DateTime createdAt;
  final DateTime updatedAt;

  KanbanColumn({
    required this.id,
    required this.title,
    this.description,
    this.color,
    required this.position,
    required this.isActive,
    required this.teamId,
    required this.createdById,
    required this.createdAt,
    required this.updatedAt,
  });

  factory KanbanColumn.fromJson(Map<String, dynamic> json) {
    return KanbanColumn(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      color: json['color']?.toString(),
      position: json['position'] as int? ?? 0,
      isActive: json['isActive'] as bool? ?? true,
      teamId: json['teamId']?.toString() ?? '',
      createdById: json['createdById']?.toString() ?? '',
      createdAt: DateTime.parse(json['createdAt'].toString()),
      updatedAt: DateTime.parse(json['updatedAt'].toString()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'color': color,
      'position': position,
      'isActive': isActive,
      'teamId': teamId,
      'createdById': createdById,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  KanbanColumn copyWith({
    String? id,
    String? title,
    String? description,
    String? color,
    int? position,
    bool? isActive,
    String? teamId,
    String? createdById,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return KanbanColumn(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      color: color ?? this.color,
      position: position ?? this.position,
      isActive: isActive ?? this.isActive,
      teamId: teamId ?? this.teamId,
      createdById: createdById ?? this.createdById,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Tarefa do Kanban
class KanbanTask {
  final String id;
  final String title;
  final String? description;
  final String columnId;
  final int position;
  final KanbanPriority? priority;
  final bool isCompleted;
  final String? assignedToId;
  final String createdById;
  final DateTime? dueDate;
  final String? projectId;
  final List<String>? tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Relacionamentos populados
  final KanbanUser? assignedTo;
  final KanbanUser? createdBy;
  final KanbanProject? project;
  final int? commentsCount;

  KanbanTask({
    required this.id,
    required this.title,
    this.description,
    required this.columnId,
    required this.position,
    this.priority,
    required this.isCompleted,
    this.assignedToId,
    required this.createdById,
    this.dueDate,
    this.projectId,
    this.tags,
    required this.createdAt,
    required this.updatedAt,
    this.assignedTo,
    this.createdBy,
    this.project,
    this.commentsCount,
  });

  factory KanbanTask.fromJson(Map<String, dynamic> json) {
    return KanbanTask(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      columnId: json['columnId']?.toString() ?? '',
      position: json['position'] as int? ?? 0,
      priority: json['priority'] != null
          ? _parsePriority(json['priority'].toString())
          : null,
      isCompleted: json['isCompleted'] as bool? ?? false,
      assignedToId: json['assignedToId']?.toString(),
      createdById: json['createdById']?.toString() ?? '',
      dueDate: json['dueDate'] != null
          ? DateTime.parse(json['dueDate'].toString())
          : null,
      projectId: json['projectId']?.toString(),
      tags: json['tags'] != null
          ? List<String>.from(json['tags'] as List)
          : null,
      createdAt: DateTime.parse(json['createdAt'].toString()),
      updatedAt: DateTime.parse(json['updatedAt'].toString()),
      assignedTo: json['assignedTo'] != null
          ? KanbanUser.fromJson(json['assignedTo'] as Map<String, dynamic>)
          : null,
      createdBy: json['createdBy'] != null
          ? KanbanUser.fromJson(json['createdBy'] as Map<String, dynamic>)
          : null,
      project: json['project'] != null
          ? KanbanProject.fromJson(json['project'] as Map<String, dynamic>)
          : null,
      commentsCount: json['commentsCount'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'columnId': columnId,
      'position': position,
      'priority': priority?.name,
      'isCompleted': isCompleted,
      'assignedToId': assignedToId,
      'createdById': createdById,
      'dueDate': dueDate?.toIso8601String(),
      'projectId': projectId,
      'tags': tags,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  KanbanTask copyWith({
    String? id,
    String? title,
    String? description,
    String? columnId,
    int? position,
    KanbanPriority? priority,
    bool? isCompleted,
    String? assignedToId,
    String? createdById,
    DateTime? dueDate,
    String? projectId,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
    KanbanUser? assignedTo,
    KanbanUser? createdBy,
    KanbanProject? project,
    int? commentsCount,
  }) {
    return KanbanTask(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      columnId: columnId ?? this.columnId,
      position: position ?? this.position,
      priority: priority ?? this.priority,
      isCompleted: isCompleted ?? this.isCompleted,
      assignedToId: assignedToId ?? this.assignedToId,
      createdById: createdById ?? this.createdById,
      dueDate: dueDate ?? this.dueDate,
      projectId: projectId ?? this.projectId,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      assignedTo: assignedTo ?? this.assignedTo,
      createdBy: createdBy ?? this.createdBy,
      project: project ?? this.project,
      commentsCount: commentsCount ?? this.commentsCount,
    );
  }

  static KanbanPriority _parsePriority(String priority) {
    switch (priority.toLowerCase()) {
      case 'urgent':
        return KanbanPriority.urgent;
      case 'high':
        return KanbanPriority.high;
      case 'medium':
        return KanbanPriority.medium;
      case 'low':
      default:
        return KanbanPriority.low;
    }
  }
}

/// Projeto do Kanban
class KanbanProject {
  final String id;
  final String name;
  final String? description;
  final KanbanProjectStatus status;
  final DateTime? startDate;
  final DateTime? dueDate;
  final DateTime? completedAt;
  final String? completedById;
  final String teamId;
  final String createdById;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int taskCount;
  final int? completedTaskCount;
  final bool? isPersonal;
  final double? progress;
  final KanbanUser? createdBy;
  final KanbanUser? completedBy;

  KanbanProject({
    required this.id,
    required this.name,
    this.description,
    required this.status,
    this.startDate,
    this.dueDate,
    this.completedAt,
    this.completedById,
    required this.teamId,
    required this.createdById,
    required this.createdAt,
    required this.updatedAt,
    required this.taskCount,
    this.completedTaskCount,
    this.isPersonal,
    this.progress,
    this.createdBy,
    this.completedBy,
  });

  factory KanbanProject.fromJson(Map<String, dynamic> json) {
    return KanbanProject(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      status: _parseStatus(json['status']?.toString() ?? 'active'),
      startDate: json['startDate'] != null
          ? DateTime.parse(json['startDate'].toString())
          : null,
      dueDate: json['dueDate'] != null
          ? DateTime.parse(json['dueDate'].toString())
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'].toString())
          : null,
      completedById: json['completedById']?.toString(),
      teamId: json['teamId']?.toString() ?? '',
      createdById: json['createdById']?.toString() ?? '',
      createdAt: DateTime.parse(json['createdAt'].toString()),
      updatedAt: DateTime.parse(json['updatedAt'].toString()),
      taskCount: json['taskCount'] as int? ?? 0,
      completedTaskCount: json['completedTaskCount'] as int?,
      isPersonal: json['isPersonal'] as bool?,
      progress: (json['progress'] as num?)?.toDouble(),
      createdBy: json['createdBy'] != null
          ? KanbanUser.fromJson(json['createdBy'] as Map<String, dynamic>)
          : null,
      completedBy: json['completedBy'] != null
          ? KanbanUser.fromJson(json['completedBy'] as Map<String, dynamic>)
          : null,
    );
  }

  static KanbanProjectStatus _parseStatus(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return KanbanProjectStatus.completed;
      case 'archived':
        return KanbanProjectStatus.archived;
      case 'cancelled':
        return KanbanProjectStatus.cancelled;
      case 'active':
      default:
        return KanbanProjectStatus.active;
    }
  }
}

/// Usuário do Kanban
class KanbanUser {
  final String id;
  final String name;
  final String email;
  final String? avatar;

  KanbanUser({
    required this.id,
    required this.name,
    required this.email,
    this.avatar,
  });

  factory KanbanUser.fromJson(Map<String, dynamic> json) {
    return KanbanUser(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      avatar: json['avatar']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      if (avatar != null) 'avatar': avatar,
    };
  }
}

/// Permissões do Kanban
class KanbanPermissions {
  final bool canCreateTasks;
  final bool canEditTasks;
  final bool canDeleteTasks;
  final bool canMoveTasks;
  final bool canCreateColumns;
  final bool canEditColumns;
  final bool canDeleteColumns;

  KanbanPermissions({
    required this.canCreateTasks,
    required this.canEditTasks,
    required this.canDeleteTasks,
    required this.canMoveTasks,
    required this.canCreateColumns,
    required this.canEditColumns,
    required this.canDeleteColumns,
  });

  factory KanbanPermissions.fromJson(Map<String, dynamic> json) {
    return KanbanPermissions(
      canCreateTasks: json['canCreateTasks'] as bool? ?? false,
      canEditTasks: json['canEditTasks'] as bool? ?? false,
      canDeleteTasks: json['canDeleteTasks'] as bool? ?? false,
      canMoveTasks: json['canMoveTasks'] as bool? ?? false,
      canCreateColumns: json['canCreateColumns'] as bool? ?? false,
      canEditColumns: json['canEditColumns'] as bool? ?? false,
      canDeleteColumns: json['canDeleteColumns'] as bool? ?? false,
    );
  }
}

/// Quadro Kanban completo
class KanbanBoard {
  final List<KanbanColumn> columns;
  final List<KanbanTask> tasks;
  final List<KanbanProject>? projects;
  final KanbanPermissions? permissions;
  final KanbanTeam? team;

  KanbanBoard({
    required this.columns,
    required this.tasks,
    this.projects,
    this.permissions,
    this.team,
  });

  factory KanbanBoard.fromJson(Map<String, dynamic> json) {
    return KanbanBoard(
      columns: (json['columns'] as List<dynamic>?)
              ?.map((e) => KanbanColumn.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      tasks: (json['tasks'] as List<dynamic>?)
              ?.map((e) => KanbanTask.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      projects: json['projects'] != null
          ? (json['projects'] as List<dynamic>)
              .map((e) => KanbanProject.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
      permissions: json['permissions'] != null
          ? KanbanPermissions.fromJson(
              json['permissions'] as Map<String, dynamic>)
          : null,
      team: json['team'] != null
          ? KanbanTeam.fromJson(json['team'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// Equipe do Kanban
class KanbanTeam {
  final String id;
  final String name;

  KanbanTeam({
    required this.id,
    required this.name,
  });

  factory KanbanTeam.fromJson(Map<String, dynamic> json) {
    return KanbanTeam(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }
}

/// DTOs para criação/atualização

class CreateColumnDto {
  final String title;
  final String? description;
  final String? color;
  final String teamId;

  CreateColumnDto({
    required this.title,
    this.description,
    this.color,
    required this.teamId,
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      if (description != null) 'description': description,
      if (color != null) 'color': color,
      'teamId': teamId,
    };
  }
}

class UpdateColumnDto {
  final String? title;
  final String? description;
  final String? color;
  final int? position;

  UpdateColumnDto({
    this.title,
    this.description,
    this.color,
    this.position,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (title != null) map['title'] = title;
    if (description != null) map['description'] = description;
    if (color != null) map['color'] = color;
    if (position != null) map['position'] = position;
    return map;
  }
}

class CreateTaskDto {
  final String title;
  final String? description;
  final String columnId;
  final KanbanPriority? priority;
  final String? assignedToId;
  final DateTime? dueDate;
  final String? projectId;
  final List<String>? tags;

  CreateTaskDto({
    required this.title,
    this.description,
    required this.columnId,
    this.priority,
    this.assignedToId,
    this.dueDate,
    this.projectId,
    this.tags,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'title': title,
      'columnId': columnId,
    };
    
    if (description != null && description!.isNotEmpty) {
      json['description'] = description;
    }
    
    if (priority != null) {
      json['priority'] = priority!.name;
    }
    
    if (assignedToId != null && assignedToId!.isNotEmpty) {
      json['assignedToId'] = assignedToId;
    }
    
    if (dueDate != null) {
      // Formato ISO 8601: apenas data com hora 00:00:00 em UTC
      // Exemplo: "2024-01-25T00:00:00Z"
      final utcDate = DateTime.utc(
        dueDate!.year,
        dueDate!.month,
        dueDate!.day,
        0, // hora
        0, // minuto
        0, // segundo
      );
      json['dueDate'] = utcDate.toIso8601String();
    }
    
    // IMPORTANTE: Não enviar projectId se for null ou vazio
    // A API valida que projectId deve ser UUID válido se fornecido
    // Se não fornecido, não deve estar no JSON
    if (projectId != null && projectId!.isNotEmpty && projectId!.trim().isNotEmpty) {
      json['projectId'] = projectId;
    }
    
    if (tags != null && tags!.isNotEmpty) {
      json['tags'] = tags;
    }
    
    return json;
  }
}

class UpdateTaskDto {
  final String? title;
  final String? description;
  final String? columnId;
  final int? position;
  final String? priority;
  final String? assignedToId;
  final DateTime? dueDate;
  final String? projectId;
  final List<String>? tags;

  UpdateTaskDto({
    this.title,
    this.description,
    this.columnId,
    this.position,
    this.priority,
    this.assignedToId,
    this.dueDate,
    this.projectId,
    this.tags,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (title != null) map['title'] = title;
    if (description != null) map['description'] = description;
    if (columnId != null) map['columnId'] = columnId;
    if (position != null) map['position'] = position;
    if (priority != null) map['priority'] = priority;
    // assignedToId pode ser null para remover responsável - sempre enviar
    map['assignedToId'] = assignedToId;
    if (dueDate != null) {
      // Formatar como YYYY-MM-DDTHH:MM:SS.000Z (meia-noite UTC)
      final utcDate = DateTime.utc(
        dueDate!.year,
        dueDate!.month,
        dueDate!.day,
      );
      map['dueDate'] = utcDate.toIso8601String();
    }
    if (projectId != null) map['projectId'] = projectId;
    // Tags: enviar array vazio se null, ou a lista se tiver valores
    map['tags'] = tags ?? [];
    return map;
  }
}

class MoveTaskDto {
  final String taskId;
  final String targetColumnId;
  final int targetPosition;

  MoveTaskDto({
    required this.taskId,
    required this.targetColumnId,
    required this.targetPosition,
  });

  Map<String, dynamic> toJson() {
    return {
      'taskId': taskId,
      'targetColumnId': targetColumnId,
      'targetPosition': targetPosition,
    };
  }
}

/// Comentário de tarefa
/// Anexo de comentário
class Attachment {
  final String id;
  final String filename;
  final String url;
  final int size;
  final String mimeType;
  final DateTime uploadedAt;

  Attachment({
    required this.id,
    required this.filename,
    required this.url,
    required this.size,
    required this.mimeType,
    required this.uploadedAt,
  });

  factory Attachment.fromJson(Map<String, dynamic> json) {
    return Attachment(
      id: json['id']?.toString() ?? '',
      filename: json['filename']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      size: json['size'] as int? ?? 0,
      mimeType: json['mimeType']?.toString() ?? '',
      uploadedAt: DateTime.parse(json['uploadedAt'].toString()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'filename': filename,
      'url': url,
      'size': size,
      'mimeType': mimeType,
      'uploadedAt': uploadedAt.toIso8601String(),
    };
  }
}

/// Comentário de tarefa
class KanbanTaskComment {
  final String id;
  final String taskId;
  final String userId;
  final String message;
  final List<Attachment> attachments;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Relacionamentos populados
  final KanbanUser? user;

  KanbanTaskComment({
    required this.id,
    required this.taskId,
    required this.userId,
    required this.message,
    required this.attachments,
    required this.createdAt,
    required this.updatedAt,
    this.user,
  });

  factory KanbanTaskComment.fromJson(Map<String, dynamic> json) {
    return KanbanTaskComment(
      id: json['id']?.toString() ?? '',
      taskId: json['taskId']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      attachments: json['attachments'] != null
          ? (json['attachments'] as List)
              .map((e) => Attachment.fromJson(e as Map<String, dynamic>))
              .toList()
          : [],
      createdAt: DateTime.parse(json['createdAt'].toString()),
      updatedAt: DateTime.parse(json['updatedAt'].toString()),
      user: json['user'] != null
          ? KanbanUser.fromJson(json['user'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'taskId': taskId,
      'userId': userId,
      'message': message,
      'attachments': attachments.map((a) => a.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

/// Entrada de histórico
class HistoryEntry {
  final String id;
  final String action;
  final KanbanUser? user;
  final HistoryColumn? fromColumn;
  final HistoryColumn? toColumn;
  final String? oldValue;
  final String? newValue;
  final String? description;
  final String? field;
  final String? fieldLabel;
  final DateTime createdAt;

  HistoryEntry({
    required this.id,
    required this.action,
    this.user,
    this.fromColumn,
    this.toColumn,
    this.oldValue,
    this.newValue,
    this.description,
    this.field,
    this.fieldLabel,
    required this.createdAt,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      id: json['id']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      user: json['user'] != null
          ? KanbanUser.fromJson(json['user'] as Map<String, dynamic>)
          : null,
      fromColumn: json['fromColumn'] != null
          ? HistoryColumn.fromJson(json['fromColumn'] as Map<String, dynamic>)
          : null,
      toColumn: json['toColumn'] != null
          ? HistoryColumn.fromJson(json['toColumn'] as Map<String, dynamic>)
          : null,
      oldValue: json['oldValue']?.toString(),
      newValue: json['newValue']?.toString(),
      description: json['description']?.toString(),
      field: json['field']?.toString(),
      fieldLabel: json['fieldLabel']?.toString(),
      createdAt: DateTime.parse(json['createdAt'].toString()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'action': action,
      'user': user?.toJson(),
      'fromColumn': fromColumn?.toJson(),
      'toColumn': toColumn?.toJson(),
      'oldValue': oldValue,
      'newValue': newValue,
      'description': description,
      'field': field,
      'fieldLabel': fieldLabel,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

/// Coluna para histórico (versão simplificada)
class HistoryColumn {
  final String id;
  final String title;
  final String color;

  HistoryColumn({
    required this.id,
    required this.title,
    required this.color,
  });

  factory HistoryColumn.fromJson(Map<String, dynamic> json) {
    return HistoryColumn(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      color: json['color']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'color': color,
    };
  }
}

/// DTO para criar comentário (não usado - usa FormData diretamente)
/// O comentário é criado via FormData com 'message' e 'files'

/// DTO para criar projeto Kanban
class CreateKanbanProjectDto {
  final String name;
  final String? description;
  final String teamId;
  final String? startDate;
  final String? dueDate;

  CreateKanbanProjectDto({
    required this.name,
    this.description,
    required this.teamId,
    this.startDate,
    this.dueDate,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (description != null) 'description': description,
      'teamId': teamId,
      if (startDate != null) 'startDate': startDate,
      if (dueDate != null) 'dueDate': dueDate,
    };
  }
}

/// DTO para atualizar projeto Kanban
class UpdateKanbanProjectDto {
  final String? name;
  final String? description;
  final String? status;
  final String? startDate;
  final String? dueDate;

  UpdateKanbanProjectDto({
    this.name,
    this.description,
    this.status,
    this.startDate,
    this.dueDate,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (name != null) map['name'] = name;
    if (description != null) map['description'] = description;
    if (status != null) map['status'] = status;
    if (startDate != null) map['startDate'] = startDate;
    if (dueDate != null) map['dueDate'] = dueDate;
    return map;
  }
}

