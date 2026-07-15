// Modelos de Backups / Exportação geral de leads — espelham
// `imobx-front/src/services/leadsExportApi.ts` e o `KanbanController`
// (`/kanban/leads-export-jobs` + `/kanban/leads-export-backups`).

String _asString(dynamic v, [String fallback = '']) =>
    v == null ? fallback : v.toString();

DateTime? _toDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

/// Modelo da planilha exportada.
enum LeadsExportTemplate {
  detailed,
  campaign,
  unknown;

  static LeadsExportTemplate fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'detailed':
        return LeadsExportTemplate.detailed;
      case 'campaign':
        return LeadsExportTemplate.campaign;
      default:
        return LeadsExportTemplate.unknown;
    }
  }

  String get apiValue =>
      this == LeadsExportTemplate.campaign ? 'campaign' : 'detailed';

  String get label {
    switch (this) {
      case LeadsExportTemplate.detailed:
        return 'Detalhado';
      case LeadsExportTemplate.campaign:
        return 'Campanha';
      case LeadsExportTemplate.unknown:
        return 'Exportação';
    }
  }
}

/// Formato do arquivo gerado.
enum LeadsExportFormat {
  xlsx,
  csv;

  static LeadsExportFormat fromRaw(String? raw) =>
      (raw ?? '').toLowerCase() == 'csv'
          ? LeadsExportFormat.csv
          : LeadsExportFormat.xlsx;

  String get apiValue => this == LeadsExportFormat.csv ? 'csv' : 'xlsx';

  String get label =>
      this == LeadsExportFormat.csv ? 'CSV (.csv)' : 'Excel (.xlsx)';
}

/// Status do job na fila.
enum LeadsExportJobStatus {
  pending,
  processing,
  completed,
  failed,
  cancelled,
  unknown;

  static LeadsExportJobStatus fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'pending':
        return LeadsExportJobStatus.pending;
      case 'processing':
        return LeadsExportJobStatus.processing;
      case 'completed':
        return LeadsExportJobStatus.completed;
      case 'failed':
        return LeadsExportJobStatus.failed;
      case 'cancelled':
      case 'canceled':
        return LeadsExportJobStatus.cancelled;
      default:
        return LeadsExportJobStatus.unknown;
    }
  }

  String get label {
    switch (this) {
      case LeadsExportJobStatus.pending:
        return 'Na fila';
      case LeadsExportJobStatus.processing:
        return 'Processando';
      case LeadsExportJobStatus.completed:
        return 'Concluída';
      case LeadsExportJobStatus.failed:
        return 'Falhou';
      case LeadsExportJobStatus.cancelled:
        return 'Cancelada';
      case LeadsExportJobStatus.unknown:
        return 'Exportação';
    }
  }

  /// Job vivo (aparece com progresso + polling).
  bool get isActive =>
      this == LeadsExportJobStatus.pending ||
      this == LeadsExportJobStatus.processing;
}

/// Evento da timeline de auditoria do job.
class LeadsExportEvent {
  final DateTime? at;
  final String type;
  final String message;

  const LeadsExportEvent({
    required this.at,
    required this.type,
    required this.message,
  });

  factory LeadsExportEvent.fromJson(Map<String, dynamic> json) {
    return LeadsExportEvent(
      at: _toDate(json['at']),
      type: _asString(json['type']),
      message: _asString(json['message']),
    );
  }

  static List<LeadsExportEvent> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => LeadsExportEvent.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}

/// Job da fila de exportação (`LeadsExportJobSummary`).
class LeadsExportJob {
  final String jobId;
  final LeadsExportJobStatus status;
  final String? stage;
  final double progress;
  final int fetched;
  final int totalExpected;
  final int totalRows;
  final LeadsExportTemplate template;
  final LeadsExportFormat format;
  final Map<String, dynamic> filters;
  final String? fileName;
  final int? fileSizeBytes;
  final String? error;
  final String? actorName;
  final List<LeadsExportEvent> events;
  final DateTime? createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;

  const LeadsExportJob({
    required this.jobId,
    required this.status,
    this.stage,
    required this.progress,
    required this.fetched,
    required this.totalExpected,
    required this.totalRows,
    required this.template,
    required this.format,
    required this.filters,
    this.fileName,
    this.fileSizeBytes,
    this.error,
    this.actorName,
    required this.events,
    this.createdAt,
    this.startedAt,
    this.completedAt,
  });

  factory LeadsExportJob.fromJson(Map<String, dynamic> json) {
    final actor = json['actor'];
    return LeadsExportJob(
      jobId: _asString(json['jobId'] ?? json['id']),
      status: LeadsExportJobStatus.fromRaw(json['status']?.toString()),
      stage: json['stage']?.toString(),
      progress: _toDouble(json['progress']),
      fetched: _toInt(json['fetched']),
      totalExpected: _toInt(json['totalExpected']),
      totalRows: _toInt(json['totalRows']),
      template: LeadsExportTemplate.fromRaw(json['template']?.toString()),
      format: LeadsExportFormat.fromRaw(json['format']?.toString()),
      filters: json['filters'] is Map
          ? Map<String, dynamic>.from(json['filters'] as Map)
          : const {},
      fileName: json['fileName']?.toString(),
      fileSizeBytes:
          json['fileSizeBytes'] == null ? null : _toInt(json['fileSizeBytes']),
      error: json['error']?.toString(),
      actorName: actor is Map ? actor['name']?.toString() : null,
      events: LeadsExportEvent.listFrom(json['events']),
      createdAt: _toDate(json['createdAt']),
      startedAt: _toDate(json['startedAt']),
      completedAt: _toDate(json['completedAt']),
    );
  }
}

/// Backup persistido de uma exportação concluída (disponível por 60 dias).
class LeadsExportBackup {
  final String id;
  final String? userName;
  final String? userEmail;
  final LeadsExportTemplate template;
  final LeadsExportFormat format;
  final Map<String, dynamic> filters;
  final int totalRows;
  final int fileSizeBytes;
  final String fileName;
  final int? durationMs;
  final String? label;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  const LeadsExportBackup({
    required this.id,
    this.userName,
    this.userEmail,
    required this.template,
    required this.format,
    required this.filters,
    required this.totalRows,
    required this.fileSizeBytes,
    required this.fileName,
    this.durationMs,
    this.label,
    this.expiresAt,
    this.createdAt,
  });

  factory LeadsExportBackup.fromJson(Map<String, dynamic> json) {
    return LeadsExportBackup(
      id: _asString(json['id']),
      userName: json['userName']?.toString(),
      userEmail: json['userEmail']?.toString(),
      template: LeadsExportTemplate.fromRaw(json['template']?.toString()),
      format: LeadsExportFormat.fromRaw(json['format']?.toString()),
      filters: json['filters'] is Map
          ? Map<String, dynamic>.from(json['filters'] as Map)
          : const {},
      totalRows: _toInt(json['totalRows']),
      fileSizeBytes: _toInt(json['fileSizeBytes']),
      fileName: _asString(json['fileName'], 'exportacao'),
      durationMs:
          json['durationMs'] == null ? null : _toInt(json['durationMs']),
      label: json['label']?.toString(),
      expiresAt: _toDate(json['expiresAt']),
      createdAt: _toDate(json['createdAt']),
    );
  }

  /// Dias restantes até expirar (null quando não expira).
  int? get daysToExpire {
    final exp = expiresAt;
    if (exp == null) return null;
    final diff = exp.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }
}

/// Resposta paginada da lista de backups.
class LeadsExportBackupList {
  final List<LeadsExportBackup> data;
  final int total;
  final String scope;
  final bool canAccessCompanyBackups;

  const LeadsExportBackupList({
    required this.data,
    required this.total,
    required this.scope,
    required this.canAccessCompanyBackups,
  });

  factory LeadsExportBackupList.fromJson(Map<String, dynamic> json) {
    final raw = json['data'];
    return LeadsExportBackupList(
      data: raw is List
          ? raw
              .whereType<Map>()
              .map((e) =>
                  LeadsExportBackup.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      total: _toInt(json['total']),
      scope: _asString(json['scope'], 'mine'),
      canAccessCompanyBackups: json['canAccessCompanyBackups'] == true,
    );
  }

  static const empty = LeadsExportBackupList(
    data: [],
    total: 0,
    scope: 'mine',
    canAccessCompanyBackups: false,
  );
}

/// Resultado do lead (filtro da exportação — paridade `RESULT_OPTIONS` web).
enum LeadsResultFilter {
  open,
  won,
  lost,
  cancelled;

  String get apiValue => name;

  String get label {
    switch (this) {
      case LeadsResultFilter.open:
        return 'Em andamento';
      case LeadsResultFilter.won:
        return 'Ganho (venda)';
      case LeadsResultFilter.lost:
        return 'Perdido';
      case LeadsResultFilter.cancelled:
        return 'Cancelado';
    }
  }
}

/// Rascunho de filtros da nova exportação (subset móvel do
/// `KanbanTasksListFilters` — período, resultado e busca).
class LeadsExportDraft {
  LeadsExportTemplate template;
  LeadsExportFormat format;
  DateTime? createdAfter;
  DateTime? createdBefore;
  LeadsResultFilter? result;
  String search;

  LeadsExportDraft({
    this.template = LeadsExportTemplate.detailed,
    this.format = LeadsExportFormat.xlsx,
    this.createdAfter,
    this.createdBefore,
    this.result,
    this.search = '',
  });

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Filtros no formato do backend (`KanbanTasksListFilters`).
  Map<String, dynamic> buildFilters() {
    final f = <String, dynamic>{};
    if (createdAfter != null) f['createdAtAfter'] = _ymd(createdAfter!);
    if (createdBefore != null) f['createdAtBefore'] = _ymd(createdBefore!);
    if (result != null) f['result'] = result!.apiValue;
    final s = search.trim();
    if (s.isNotEmpty) f['search'] = s;
    return f;
  }

  Map<String, dynamic> toPayload() => {
        'template': template.apiValue,
        'format': format.apiValue,
        'filters': buildFilters(),
      };
}
