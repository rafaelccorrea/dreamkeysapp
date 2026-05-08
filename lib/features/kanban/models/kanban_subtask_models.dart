/// Modelos de **subtarefas** (checklist) que vivem **dentro de um card**
/// (`KanbanTask`) do Kanban — paridade com o entity `KanbanSubTask` do
/// backend (`imobx/src/entities/kanban-subtask.entity.ts`) e o front web
/// (`imobx-front/src/services/kanbanSubtasksApi.ts`).
library;

import 'kanban_models.dart';

// ─── Tipo de atividade (taskType) ─────────────────────────────────────

/// Tipo de atividade (paridade com `imobx-front/src/constants/subTaskTypes.ts`).
enum SubTaskType {
  ligar('ligar', 'Ligar'),
  email('email', 'Email'),
  reuniao('reuniao', 'Reunião'),
  tarefa('tarefa', 'Tarefa'),
  almoco('almoco', 'Almoço'),
  visita('visita', 'Visita'),
  whatsapp('whatsapp', 'WhatsApp');

  final String value;
  final String label;

  const SubTaskType(this.value, this.label);

  static SubTaskType? fromString(String? raw) {
    if (raw == null) return null;
    final v = raw.trim().toLowerCase();
    if (v.isEmpty) return null;
    for (final t in SubTaskType.values) {
      if (t.value == v) return t;
    }
    return null;
  }
}

// ─── Resumo do card pai embutido nas respostas ─────────────────────────

/// Resumo da `KanbanTask` (cartão pai) que vem embutido em vários
/// endpoints de subtarefa (`parentTask`). Não confundir com o modelo
/// completo `KanbanTask` em `kanban_models.dart`.
class ParentTaskSummary {
  final String id;
  final String title;
  final String? columnId;
  final String? columnTitle;
  final String? teamId;
  final String? teamName;
  final String? projectId;
  final String? projectName;
  final KanbanPriority? priority;
  final bool? isCompleted;
  final String? status;
  final DateTime? dueDate;

  const ParentTaskSummary({
    required this.id,
    required this.title,
    this.columnId,
    this.columnTitle,
    this.teamId,
    this.teamName,
    this.projectId,
    this.projectName,
    this.priority,
    this.isCompleted,
    this.status,
    this.dueDate,
  });

  factory ParentTaskSummary.fromJson(Map<String, dynamic> json) {
    KanbanPriority? parsePriority(dynamic raw) {
      if (raw == null) return null;
      final v = raw.toString().toLowerCase();
      for (final p in KanbanPriority.values) {
        if (p.name == v) return p;
      }
      return null;
    }

    DateTime? parseDate(dynamic raw) {
      if (raw == null) return null;
      try {
        return DateTime.parse(raw.toString());
      } catch (_) {
        return null;
      }
    }

    return ParentTaskSummary(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      columnId: json['columnId']?.toString(),
      columnTitle: (json['column'] is Map)
          ? (json['column'] as Map)['title']?.toString()
          : json['columnTitle']?.toString(),
      teamId: json['teamId']?.toString(),
      teamName: (json['team'] is Map)
          ? (json['team'] as Map)['name']?.toString()
          : json['teamName']?.toString(),
      projectId: json['projectId']?.toString(),
      projectName: (json['project'] is Map)
          ? (json['project'] as Map)['name']?.toString()
          : json['projectName']?.toString(),
      priority: parsePriority(json['priority']),
      isCompleted: json['isCompleted'] as bool?,
      status: json['status']?.toString(),
      dueDate: parseDate(json['dueDate']),
    );
  }
}

// ─── Subtarefa principal ───────────────────────────────────────────────

class KanbanSubTask {
  final String id;
  final String title;
  final String? description;
  final int position;
  final bool isCompleted;
  final DateTime? dueDate;
  final String? dueTime; // HH:mm
  final SubTaskType? taskType;
  final DateTime? completedAt;
  final String? assignedToId;
  final String taskId; // id do card pai (KanbanTask)
  final String? parentTaskTitle;
  final ParentTaskSummary? parentTask;
  final String createdById;
  final DateTime createdAt;
  final DateTime updatedAt;
  final KanbanUser? assignedTo;
  final KanbanUser? createdBy;
  final int? commentsCount;

  /// Disponível em `GET /kanban/subtasks/list` (alias do título do card pai).
  final String? taskTitle;

  const KanbanSubTask({
    required this.id,
    required this.title,
    this.description,
    required this.position,
    required this.isCompleted,
    this.dueDate,
    this.dueTime,
    this.taskType,
    this.completedAt,
    this.assignedToId,
    required this.taskId,
    this.parentTaskTitle,
    this.parentTask,
    required this.createdById,
    required this.createdAt,
    required this.updatedAt,
    this.assignedTo,
    this.createdBy,
    this.commentsCount,
    this.taskTitle,
  });

  factory KanbanSubTask.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic raw) {
      if (raw == null) return null;
      try {
        return DateTime.parse(raw.toString());
      } catch (_) {
        return null;
      }
    }

    DateTime parseDateRequired(dynamic raw) {
      try {
        return DateTime.parse(raw.toString());
      } catch (_) {
        return DateTime.now();
      }
    }

    KanbanUser? parseUser(dynamic raw) {
      if (raw is Map<String, dynamic>) return KanbanUser.fromJson(raw);
      if (raw is Map) {
        return KanbanUser.fromJson(Map<String, dynamic>.from(raw));
      }
      return null;
    }

    return KanbanSubTask(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      position: (json['position'] is int)
          ? json['position'] as int
          : int.tryParse('${json['position']}') ?? 0,
      isCompleted: json['isCompleted'] as bool? ?? false,
      dueDate: parseDate(json['dueDate']),
      dueTime: json['dueTime']?.toString(),
      taskType: SubTaskType.fromString(json['taskType']?.toString()),
      completedAt: parseDate(json['completedAt']),
      assignedToId: json['assignedToId']?.toString(),
      taskId: json['taskId']?.toString() ?? '',
      parentTaskTitle: json['parentTaskTitle']?.toString() ??
          json['taskTitle']?.toString(),
      parentTask: (json['parentTask'] is Map)
          ? ParentTaskSummary.fromJson(
              Map<String, dynamic>.from(json['parentTask'] as Map),
            )
          : null,
      createdById: json['createdById']?.toString() ?? '',
      createdAt: parseDateRequired(json['createdAt']),
      updatedAt: parseDateRequired(json['updatedAt']),
      assignedTo: parseUser(json['assignedTo']),
      createdBy: parseUser(json['createdBy']),
      commentsCount: json['commentsCount'] is int
          ? json['commentsCount'] as int
          : int.tryParse('${json['commentsCount']}'),
      taskTitle: json['taskTitle']?.toString(),
    );
  }

  /// Considera atrasada quando há prazo no passado e a subtarefa **não**
  /// está concluída — o backend não calcula esse flag, é responsabilidade
  /// do cliente (idem web).
  bool get isOverdue {
    if (isCompleted) return false;
    if (dueDate == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);
    if (due.isBefore(today)) return true;
    // Se a data é hoje e há horário, comparar com agora.
    if (due.isAtSameMomentAs(today) && dueTime != null && dueTime!.isNotEmpty) {
      final parts = dueTime!.split(':');
      if (parts.length == 2) {
        final h = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (h != null && m != null) {
          final dueDt = DateTime(now.year, now.month, now.day, h, m);
          return dueDt.isBefore(now);
        }
      }
    }
    return false;
  }

  /// `'today'`, `'tomorrow'`, `'overdue'`, `'completed'` ou `'scheduled'` /
  /// `'no_date'` — usado para badges de status.
  String get bucket {
    if (isCompleted) return 'completed';
    if (isOverdue) return 'overdue';
    if (dueDate == null) return 'no_date';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);
    if (due.isAtSameMomentAs(today)) return 'today';
    if (due.difference(today).inDays == 1) return 'tomorrow';
    return 'scheduled';
  }

  KanbanSubTask copyWith({
    bool? isCompleted,
    DateTime? completedAt,
    String? title,
    String? description,
    DateTime? dueDate,
    String? dueTime,
    SubTaskType? taskType,
    String? assignedToId,
    KanbanUser? assignedTo,
  }) {
    return KanbanSubTask(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      position: position,
      isCompleted: isCompleted ?? this.isCompleted,
      dueDate: dueDate ?? this.dueDate,
      dueTime: dueTime ?? this.dueTime,
      taskType: taskType ?? this.taskType,
      completedAt: completedAt ?? this.completedAt,
      assignedToId: assignedToId ?? this.assignedToId,
      taskId: taskId,
      parentTaskTitle: parentTaskTitle,
      parentTask: parentTask,
      createdById: createdById,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      assignedTo: assignedTo ?? this.assignedTo,
      createdBy: createdBy,
      commentsCount: commentsCount,
      taskTitle: taskTitle,
    );
  }
}

// ─── DTOs de criação / atualização ─────────────────────────────────────

class CreateSubTaskDto {
  final String title;
  final String? description;
  final String? assignedToId;
  final DateTime? dueDate;
  final String? dueTime;
  final SubTaskType? taskType;

  const CreateSubTaskDto({
    required this.title,
    this.description,
    this.assignedToId,
    this.dueDate,
    this.dueTime,
    this.taskType,
  });

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'title': title};
    final desc = description?.trim();
    if (desc != null && desc.isNotEmpty) m['description'] = desc;
    if (assignedToId != null && assignedToId!.isNotEmpty) {
      m['assignedToId'] = assignedToId;
    }
    if (dueDate != null) {
      // Backend usa `parseKanbanDateOnlyInput` aceitando `YYYY-MM-DD`.
      final d = dueDate!;
      final iso = '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      m['dueDate'] = iso;
    }
    if (dueTime != null && dueTime!.isNotEmpty) m['dueTime'] = dueTime;
    if (taskType != null) m['taskType'] = taskType!.value;
    return m;
  }
}

class UpdateSubTaskDto {
  final String? title;
  final String? description;
  final String? assignedToId;
  final DateTime? dueDate;
  final bool clearDueDate;
  final String? dueTime;
  final bool clearDueTime;
  final SubTaskType? taskType;
  final bool clearTaskType;
  final bool? isCompleted;
  final int? position;

  const UpdateSubTaskDto({
    this.title,
    this.description,
    this.assignedToId,
    this.dueDate,
    this.clearDueDate = false,
    this.dueTime,
    this.clearDueTime = false,
    this.taskType,
    this.clearTaskType = false,
    this.isCompleted,
    this.position,
  });

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (title != null) m['title'] = title!.trim();
    if (description != null) m['description'] = description!.trim();
    if (assignedToId != null) m['assignedToId'] = assignedToId;
    if (dueDate != null) {
      final d = dueDate!;
      m['dueDate'] = '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
    } else if (clearDueDate) {
      m['dueDate'] = null;
    }
    if (dueTime != null) {
      m['dueTime'] = dueTime;
    } else if (clearDueTime) {
      m['dueTime'] = null;
    }
    if (taskType != null) {
      m['taskType'] = taskType!.value;
    } else if (clearTaskType) {
      m['taskType'] = null;
    }
    if (isCompleted != null) m['isCompleted'] = isCompleted;
    if (position != null) m['position'] = position;
    return m;
  }
}

// ─── Filtros / response da listagem global ─────────────────────────────

/// Filtros aceitos por `GET /kanban/subtasks/list` (espelho do web).
class SubTasksListFilters {
  final String? taskId;
  final DateTime? dueDateFrom;
  final DateTime? dueDateTo;
  final bool? isCompleted;
  final List<String> userIds;
  final bool onlyMine;
  final String? cardSearch;
  final String? cardTeamId;
  final String? cardProjectId;
  final SubtaskKindFilter? subtaskKind;
  final int page;
  final int limit;

  const SubTasksListFilters({
    this.taskId,
    this.dueDateFrom,
    this.dueDateTo,
    this.isCompleted,
    this.userIds = const [],
    this.onlyMine = false,
    this.cardSearch,
    this.cardTeamId,
    this.cardProjectId,
    this.subtaskKind,
    this.page = 1,
    this.limit = 50,
  });

  static const SubTasksListFilters empty = SubTasksListFilters();

  Map<String, String> toQueryParams() {
    final out = <String, String>{
      'page': '$page',
      'limit': '$limit',
    };

    String fmtDate(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

    if (taskId != null && taskId!.isNotEmpty) out['taskId'] = taskId!;
    if (dueDateFrom != null) out['dueDateFrom'] = fmtDate(dueDateFrom!);
    if (dueDateTo != null) out['dueDateTo'] = fmtDate(dueDateTo!);
    if (isCompleted != null) {
      out['isCompleted'] = isCompleted! ? 'true' : 'false';
    }
    if (userIds.isNotEmpty) out['userIds'] = userIds.join(',');
    if (onlyMine) out['onlyMine'] = 'true';
    final cs = cardSearch?.trim();
    if (cs != null && cs.isNotEmpty) out['cardSearch'] = cs;
    if (cardTeamId != null && cardTeamId!.isNotEmpty) {
      out['cardTeamId'] = cardTeamId!;
    }
    if (cardProjectId != null && cardProjectId!.isNotEmpty) {
      out['cardProjectId'] = cardProjectId!;
    }
    if (subtaskKind != null) out['subtaskKind'] = subtaskKind!.value;
    return out;
  }

  SubTasksListFilters copyWith({
    String? taskId,
    DateTime? dueDateFrom,
    bool clearDueDateFrom = false,
    DateTime? dueDateTo,
    bool clearDueDateTo = false,
    bool? isCompleted,
    bool clearIsCompleted = false,
    List<String>? userIds,
    bool? onlyMine,
    String? cardSearch,
    String? cardTeamId,
    String? cardProjectId,
    SubtaskKindFilter? subtaskKind,
    bool clearSubtaskKind = false,
    int? page,
    int? limit,
  }) {
    return SubTasksListFilters(
      taskId: taskId ?? this.taskId,
      dueDateFrom: clearDueDateFrom ? null : (dueDateFrom ?? this.dueDateFrom),
      dueDateTo: clearDueDateTo ? null : (dueDateTo ?? this.dueDateTo),
      isCompleted: clearIsCompleted ? null : (isCompleted ?? this.isCompleted),
      userIds: userIds ?? this.userIds,
      onlyMine: onlyMine ?? this.onlyMine,
      cardSearch: cardSearch ?? this.cardSearch,
      cardTeamId: cardTeamId ?? this.cardTeamId,
      cardProjectId: cardProjectId ?? this.cardProjectId,
      subtaskKind: clearSubtaskKind ? null : (subtaskKind ?? this.subtaskKind),
      page: page ?? this.page,
      limit: limit ?? this.limit,
    );
  }
}

enum SubtaskKindFilter {
  ligar('ligar'),
  tarefa('tarefa'),
  ligarOrTarefa('ligar_or_tarefa');

  final String value;
  const SubtaskKindFilter(this.value);
}

class SubTasksListStats {
  final int total;
  final int completed;
  final int pending;
  final int overdue;
  final int byKindLigar;
  final int byKindTarefa;
  final int byKindOther;

  const SubTasksListStats({
    required this.total,
    required this.completed,
    required this.pending,
    required this.overdue,
    required this.byKindLigar,
    required this.byKindTarefa,
    required this.byKindOther,
  });

  static const SubTasksListStats zero = SubTasksListStats(
    total: 0,
    completed: 0,
    pending: 0,
    overdue: 0,
    byKindLigar: 0,
    byKindTarefa: 0,
    byKindOther: 0,
  );

  factory SubTasksListStats.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    int readInt(Map<String, dynamic> map, List<String> keys) {
      for (final k in keys) {
        if (map.containsKey(k)) {
          return asInt(map[k]);
        }
      }
      return 0;
    }

    int? readIntOrNull(Map<String, dynamic> map, List<String> keys) {
      for (final k in keys) {
        if (map.containsKey(k)) {
          return asInt(map[k]);
        }
      }
      return null;
    }

    Map<String, dynamic> asMap(dynamic raw) {
      if (raw is Map<String, dynamic>) return raw;
      if (raw is Map) return Map<String, dynamic>.from(raw);
      return const <String, dynamic>{};
    }

    final byKind = json['byKind'];
    final byKindMap =
        byKind is Map ? Map<String, dynamic>.from(byKind) : <String, dynamic>{};
    final countsMap = asMap(json['counts']);
    final statusMap = asMap(json['status']);
    final byStatusMap = asMap(json['byStatus']);

    final total = readIntOrNull(json, ['total', 'totalCount', 'total_count']) ??
        readInt(
          countsMap,
          ['total', 'all', 'totalCount', 'total_count'],
        );
    final completed =
        readIntOrNull(json, ['completed', 'completedCount', 'completed_count']) ??
            readIntOrNull(
              statusMap,
              ['completed', 'done', 'completedCount', 'completed_count'],
            ) ??
            readInt(
              byStatusMap,
              ['completed', 'done', 'completedCount', 'completed_count'],
            );
    final pending =
        readIntOrNull(json, ['pending', 'pendingCount', 'pending_count']) ??
            readIntOrNull(
              statusMap,
              ['pending', 'open', 'todo', 'pendingCount', 'pending_count'],
            ) ??
            readInt(
              byStatusMap,
              ['pending', 'open', 'todo', 'pendingCount', 'pending_count'],
            );
    final overdue =
        readIntOrNull(json, ['overdue', 'overdueCount', 'overdue_count']) ??
            readIntOrNull(
              statusMap,
              ['overdue', 'late', 'overdueCount', 'overdue_count'],
            ) ??
            readInt(
              byStatusMap,
              ['overdue', 'late', 'overdueCount', 'overdue_count'],
            );

    return SubTasksListStats(
      total: total,
      completed: completed,
      pending: pending,
      overdue: overdue,
      byKindLigar: asInt(byKindMap['ligar']),
      byKindTarefa: asInt(byKindMap['tarefa']),
      byKindOther: asInt(byKindMap['other']),
    );
  }
}

class SubTasksListResponse {
  final List<KanbanSubTask> data;
  final int total;
  final int page;
  final int limit;
  final int totalPages;
  final SubTasksListStats stats;

  const SubTasksListResponse({
    required this.data,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
    required this.stats,
  });

  static const SubTasksListResponse empty = SubTasksListResponse(
    data: [],
    total: 0,
    page: 1,
    limit: 50,
    totalPages: 1,
    stats: SubTasksListStats.zero,
  );

  factory SubTasksListResponse.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v, [int fallback = 0]) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    Map<String, dynamic> asMap(dynamic raw) {
      if (raw is Map<String, dynamic>) return raw;
      if (raw is Map) return Map<String, dynamic>.from(raw);
      return const <String, dynamic>{};
    }

    SubTasksListStats inferStatsFromData(List<KanbanSubTask> items) {
      final total = items.length;
      final completed = items.where((e) => e.isCompleted).length;
      final pending = items.where((e) => !e.isCompleted).length;
      final overdue = items.where((e) => e.isOverdue).length;
      final byKindLigar = items.where((e) => e.taskType == SubTaskType.ligar).length;
      final byKindTarefa = items.where((e) => e.taskType == SubTaskType.tarefa).length;
      final byKindOther = total - byKindLigar - byKindTarefa;
      return SubTasksListStats(
        total: total,
        completed: completed,
        pending: pending,
        overdue: overdue,
        byKindLigar: byKindLigar,
        byKindTarefa: byKindTarefa,
        byKindOther: byKindOther < 0 ? 0 : byKindOther,
      );
    }

    final maybeEnvelopeData = asMap(json['data']);
    final hasLikelyEnvelope =
        json.containsKey('success') ||
        json.containsKey('statusCode') ||
        (json['data'] is Map &&
            (maybeEnvelopeData.containsKey('data') ||
                maybeEnvelopeData.containsKey('items') ||
                maybeEnvelopeData.containsKey('results') ||
                maybeEnvelopeData.containsKey('stats') ||
                maybeEnvelopeData.containsKey('meta')));
    final payload = hasLikelyEnvelope && maybeEnvelopeData.isNotEmpty
        ? maybeEnvelopeData
        : json;

    final nestedDataMap = asMap(payload['data']);
    final meta = asMap(payload['meta']).isNotEmpty
        ? asMap(payload['meta'])
        : asMap(nestedDataMap['meta']);
    final pagination = asMap(payload['pagination']).isNotEmpty
        ? asMap(payload['pagination'])
        : asMap(nestedDataMap['pagination']);

    final raw =
        (payload['data'] is List ? payload['data'] : null) ??
        payload['items'] ??
        payload['results'] ??
        nestedDataMap['data'] ??
        nestedDataMap['items'] ??
        nestedDataMap['results'];
    final list = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => KanbanSubTask.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <KanbanSubTask>[];

    final rawStats =
        payload['stats'] ??
        nestedDataMap['stats'] ??
        meta['stats'] ??
        payload['summary'] ??
        nestedDataMap['summary'];
    final parsedStats = rawStats is Map
        ? SubTasksListStats.fromJson(Map<String, dynamic>.from(rawStats))
        : SubTasksListStats.zero;
    final statsLooksEmpty =
        parsedStats.total == 0 &&
        parsedStats.completed == 0 &&
        parsedStats.pending == 0 &&
        parsedStats.overdue == 0;
    final effectiveStats =
        (statsLooksEmpty && list.isNotEmpty) ? inferStatsFromData(list) : parsedStats;

    return SubTasksListResponse(
      data: list,
      total: asInt(
        payload['total'] ??
            nestedDataMap['total'] ??
            meta['total'] ??
            pagination['total'],
        list.length,
      ),
      page: asInt(
        payload['page'] ??
            nestedDataMap['page'] ??
            meta['page'] ??
            pagination['page'],
        1,
      ),
      limit: asInt(
        payload['limit'] ??
            nestedDataMap['limit'] ??
            meta['limit'] ??
            pagination['limit'],
        list.length,
      ),
      totalPages:
          asInt(
            payload['totalPages'] ??
                payload['total_pages'] ??
                nestedDataMap['totalPages'] ??
                nestedDataMap['total_pages'] ??
                meta['totalPages'] ??
                meta['total_pages'] ??
                pagination['totalPages'] ??
                pagination['total_pages'],
            1,
          ),
      stats: effectiveStats,
    );
  }
}
