import 'package:flutter/foundation.dart';

import '../../core/constants/api_constants.dart';
import 'api_service.dart';
import 'secure_storage_service.dart';

class NoteListItem {
  final String id;
  final String title;
  final String? content;
  final String priority;
  final bool isPinned;
  final String? reminderDate;
  final String? color;

  NoteListItem({
    required this.id,
    required this.title,
    this.content,
    required this.priority,
    required this.isPinned,
    this.reminderDate,
    this.color,
  });

  factory NoteListItem.fromJson(Map<String, dynamic> j) {
    return NoteListItem(
      id: j['id']?.toString() ?? '',
      title: j['title']?.toString() ?? '',
      content: j['content']?.toString(),
      priority: j['priority']?.toString() ?? '',
      isPinned: j['isPinned'] == true,
      reminderDate: j['reminderDate']?.toString(),
      color: j['color']?.toString(),
    );
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

/// Serviço de anotações — espelha `GET /notes` do Nest (`NotesController`).
class NotesService {
  NotesService._();
  static final NotesService instance = NotesService._();
  final ApiService _api = ApiService.instance;

  Future<ApiResponse<NotesListResult>> listNotes({
    int page = 1,
    int limit = 30,
    String? search,
    /// `active` | `archived` — alinhado ao `NoteQueryDto` / web.
    String status = 'active',
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

  /// `GET /notes/stats`
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

  /// `POST /notes` — exige `companyId` no corpo (igual ao `CreateNoteDto` / web).
  Future<ApiResponse<NoteListItem>> createNote({
    required String title,
    String? content,
    String priority = 'medium',
    bool isPinned = false,
  }) async {
    try {
      final companyId = await SecureStorageService.instance.getCompanyId();
      if (companyId == null || companyId.trim().isEmpty) {
        return ApiResponse.error(
          message: 'Nenhuma empresa selecionada. Entre de novo ou escolha a empresa.',
          statusCode: 0,
        );
      }
      final t = title.trim();
      if (t.isEmpty) {
        return ApiResponse.error(message: 'Título é obrigatório.', statusCode: 0);
      }
      final body = <String, dynamic>{
        'title': t,
        'companyId': companyId.trim(),
        'priority': priority,
        'isPinned': isPinned,
        'hasReminder': false,
      };
      final c = content?.trim();
      if (c != null && c.isNotEmpty) {
        body['content'] = c;
      }
      final res = await _api.post<Map<String, dynamic>>(
        ApiConstants.notes,
        body: body,
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao criar anotação',
          statusCode: res.statusCode,
        );
      }
      var map = Map<String, dynamic>.from(res.data!);
      if (map['id'] == null) {
        final inner = map['data'];
        if (inner is Map) {
          final im = Map<String, dynamic>.from(inner);
          if (im['id'] != null) map = im;
        }
      }
      return ApiResponse.success(
        data: NoteListItem.fromJson(map),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [NOTES] createNote: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }
}
