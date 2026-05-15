import 'package:flutter/foundation.dart';

import '../../core/constants/api_constants.dart';
import 'api_service.dart';
import 'secure_storage_service.dart';

class NoteListItem {
  final String id;
  final String title;
  final String? content;
  final String priority;
  final String type;
  final String status;
  final bool isPinned;
  final bool hasReminder;
  final String? reminderDate;
  final String? color;
  final String? clientName;
  final String? clientPhone;
  final String? clientEmail;
  final List<String> tags;
  final int imageCount;
  final String? authorName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  NoteListItem({
    required this.id,
    required this.title,
    this.content,
    required this.priority,
    this.type = 'basic',
    this.status = 'active',
    required this.isPinned,
    this.hasReminder = false,
    this.reminderDate,
    this.color,
    this.clientName,
    this.clientPhone,
    this.clientEmail,
    this.tags = const [],
    this.imageCount = 0,
    this.authorName,
    this.createdAt,
    this.updatedAt,
  });

  bool get isAdvanced => type.toLowerCase() == 'advanced';

  bool get hasClient =>
      (clientName?.trim().isNotEmpty ?? false) ||
      (clientPhone?.trim().isNotEmpty ?? false) ||
      (clientEmail?.trim().isNotEmpty ?? false);

  int get wordCount {
    final t = content?.trim();
    if (t == null || t.isEmpty) return 0;
    return t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  static List<String> _parseStringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  factory NoteListItem.fromJson(Map<String, dynamic> j) {
    final user = j['user'];
    String? author;
    if (user is Map) {
      author = user['name']?.toString();
    }

    final images = j['images'];
    final imageCount = images is List ? images.length : 0;

    return NoteListItem(
      id: j['id']?.toString() ?? '',
      title: j['title']?.toString() ?? '',
      content: j['content']?.toString(),
      priority: j['priority']?.toString() ?? 'medium',
      type: j['type']?.toString() ?? 'basic',
      status: j['status']?.toString() ?? 'active',
      isPinned: j['isPinned'] == true,
      hasReminder: j['hasReminder'] == true,
      reminderDate: j['reminderDate']?.toString(),
      color: j['color']?.toString(),
      clientName: j['clientName']?.toString(),
      clientPhone: j['clientPhone']?.toString(),
      clientEmail: j['clientEmail']?.toString(),
      tags: _parseStringList(j['tags']),
      imageCount: imageCount,
      authorName: author,
      createdAt: _parseDate(j['createdAt']),
      updatedAt: _parseDate(j['updatedAt']),
    );
  }
}

/// Payload de criação — campos de anotação “rica” (cliente, lembrete, tags, cor).
class CreateNoteRequest {
  const CreateNoteRequest({
    required this.title,
    this.content,
    this.priority = 'medium',
    this.isPinned = false,
    this.hasReminder = false,
    this.reminderDate,
    this.color = '#3B82F6',
    this.tags = const [],
    this.clientName,
    this.clientPhone,
    this.clientEmail,
  });

  final String title;
  final String? content;
  final String priority;
  final bool isPinned;
  final bool hasReminder;
  final DateTime? reminderDate;
  final String color;
  final List<String> tags;
  final String? clientName;
  final String? clientPhone;
  final String? clientEmail;

  Map<String, dynamic> toJson(String companyId) {
    final body = <String, dynamic>{
      'title': title.trim(),
      'companyId': companyId.trim(),
      'type': 'advanced',
      'priority': priority,
      'isPinned': isPinned,
      'hasReminder': hasReminder,
      'color': color,
    };
    final c = content?.trim();
    if (c != null && c.isNotEmpty) body['content'] = c;
    if (tags.isNotEmpty) body['tags'] = tags;
    final cn = clientName?.trim();
    if (cn != null && cn.isNotEmpty) body['clientName'] = cn;
    final cp = clientPhone?.trim();
    if (cp != null && cp.isNotEmpty) body['clientPhone'] = cp;
    final ce = clientEmail?.trim();
    if (ce != null && ce.isNotEmpty) body['clientEmail'] = ce;
    if (hasReminder && reminderDate != null) {
      body['reminderDate'] = reminderDate!.toUtc().toIso8601String();
    }
    return body;
  }
}

/// `GET /notes/stats` — mesmo contrato do web (`NoteStats`).
class NotesStats {
  final int total;
  final int basic;
  final int advanced;
  final int pinned;
  final int withReminders;

  const NotesStats({
    required this.total,
    required this.basic,
    required this.advanced,
    required this.pinned,
    required this.withReminders,
  });

  factory NotesStats.fromJson(Map<String, dynamic> j) {
    int n(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.round();
      return int.tryParse(v.toString()) ?? 0;
    }

    return NotesStats(
      total: n(j['total']),
      basic: n(j['basic']),
      advanced: n(j['advanced']),
      pinned: n(j['pinned']),
      withReminders: n(j['withReminders']),
    );
  }
}

class NotesListResult {
  final List<NoteListItem> items;
  final int total;
  final int page;
  final int totalPages;

  NotesListResult({
    required this.items,
    required this.total,
    required this.page,
    required this.totalPages,
  });
}

/// Serviço de anotações — espelha `NotesController` do Nest.
class NotesService {
  NotesService._();
  static final NotesService instance = NotesService._();
  final ApiService _api = ApiService.instance;

  static Map<String, dynamic> _unwrapNoteMap(Map<String, dynamic> map) {
    if (map['id'] != null) return map;
    final inner = map['data'];
    if (inner is Map) return Map<String, dynamic>.from(inner);
    return map;
  }

  Future<String?> _requireCompanyId() async {
    final companyId = await SecureStorageService.instance.getCompanyId();
    if (companyId == null || companyId.trim().isEmpty) return null;
    return companyId.trim();
  }

  Future<ApiResponse<NotesListResult>> listNotes({
    int page = 1,
    int limit = 30,
    String? search,
    String status = 'active',
    String? type,
    String? priority,
    bool? isPinned,
    bool? hasReminder,
  }) async {
    try {
      final qp = <String, String>{
        'page': '$page',
        'limit': '$limit',
        'status': status,
      };
      if (search != null && search.trim().isNotEmpty) {
        qp['search'] = search.trim();
      }
      if (type != null && type.isNotEmpty) qp['type'] = type;
      if (priority != null && priority.isNotEmpty) qp['priority'] = priority;
      if (isPinned != null) qp['isPinned'] = isPinned.toString();
      if (hasReminder != null) qp['hasReminder'] = hasReminder.toString();

      final res = await _api.get<Map<String, dynamic>>(
        ApiConstants.notes,
        queryParameters: qp,
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao listar anotações',
          statusCode: res.statusCode,
        );
      }
      final root = res.data!;
      final raw = root['data'];
      if (raw is! List) {
        return ApiResponse.error(
          message: 'Formato de resposta inválido',
          statusCode: res.statusCode,
        );
      }
      final items = raw
          .map((e) => NoteListItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      return ApiResponse.success(
        data: NotesListResult(
          items: items,
          total: int.tryParse(root['total']?.toString() ?? '') ?? items.length,
          page: int.tryParse(root['page']?.toString() ?? '') ?? page,
          totalPages:
              int.tryParse(root['totalPages']?.toString() ?? '') ?? 1,
        ),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [NOTES] $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<NotesStats>> getStats() async {
    try {
      final res = await _api.get<Map<String, dynamic>>(ApiConstants.notesStats);
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao carregar estatísticas',
          statusCode: res.statusCode,
        );
      }
      var map = Map<String, dynamic>.from(res.data!);
      final inner = map['data'];
      if (inner is Map &&
          (inner['total'] != null || inner['basic'] != null)) {
        map = Map<String, dynamic>.from(inner);
      }
      return ApiResponse.success(
        data: NotesStats.fromJson(map),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [NOTES] getStats: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<NoteListItem>> getNote(String id) async {
    try {
      final res = await _api.get<Map<String, dynamic>>(
        ApiConstants.noteById(id),
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao carregar anotação',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: NoteListItem.fromJson(_unwrapNoteMap(res.data!)),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [NOTES] getNote: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<NoteListItem>> createNote(CreateNoteRequest request) async {
    try {
      final companyId = await _requireCompanyId();
      if (companyId == null) {
        return ApiResponse.error(
          message:
              'Nenhuma empresa selecionada. Entre de novo ou escolha a empresa.',
          statusCode: 0,
        );
      }
      if (request.title.trim().isEmpty) {
        return ApiResponse.error(
          message: 'Título é obrigatório.',
          statusCode: 0,
        );
      }
      if (request.hasReminder && request.reminderDate == null) {
        return ApiResponse.error(
          message: 'Informe data e hora do lembrete.',
          statusCode: 0,
        );
      }

      final res = await _api.post<Map<String, dynamic>>(
        ApiConstants.notes,
        body: request.toJson(companyId),
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao criar anotação',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: NoteListItem.fromJson(_unwrapNoteMap(res.data!)),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [NOTES] createNote: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<NoteListItem>> togglePin(String id) async {
    try {
      final res = await _api.patch<Map<String, dynamic>>(
        ApiConstants.noteTogglePin(id),
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao fixar anotação',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: NoteListItem.fromJson(_unwrapNoteMap(res.data!)),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [NOTES] togglePin: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<NoteListItem>> archiveNote(String id) async {
    try {
      final res = await _api.patch<Map<String, dynamic>>(
        ApiConstants.noteArchive(id),
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao arquivar',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: NoteListItem.fromJson(_unwrapNoteMap(res.data!)),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [NOTES] archive: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<NoteListItem>> restoreNote(String id) async {
    try {
      final res = await _api.patch<Map<String, dynamic>>(
        ApiConstants.noteRestore(id),
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao restaurar',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: NoteListItem.fromJson(_unwrapNoteMap(res.data!)),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [NOTES] restore: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<void>> deleteNote(String id) async {
    try {
      final res = await _api.delete(ApiConstants.noteById(id));
      if (!res.success) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao excluir anotação',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(data: null, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('❌ [NOTES] delete: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Compat — criação mínima legada.
  Future<ApiResponse<NoteListItem>> createNoteSimple({
    required String title,
    String? content,
    String priority = 'medium',
    bool isPinned = false,
  }) {
    return createNote(
      CreateNoteRequest(
        title: title,
        content: content,
        priority: priority,
        isPinned: isPinned,
      ),
    );
  }
}
