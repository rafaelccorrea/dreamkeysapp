import 'package:flutter/foundation.dart';

import '../../core/constants/api_constants.dart';
import 'api_service.dart';

class NoteListItem {
  final String id;
  final String title;
  final String? content;
  final String priority;
  final bool isPinned;
  final String? reminderDate;

  NoteListItem({
    required this.id,
    required this.title,
    this.content,
    required this.priority,
    required this.isPinned,
    this.reminderDate,
  });

  factory NoteListItem.fromJson(Map<String, dynamic> j) {
    return NoteListItem(
      id: j['id']?.toString() ?? '',
      title: j['title']?.toString() ?? '',
      content: j['content']?.toString(),
      priority: j['priority']?.toString() ?? '',
      isPinned: j['isPinned'] == true,
      reminderDate: j['reminderDate']?.toString(),
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
  }) async {
    try {
      final qp = <String, String>{
        'page': '$page',
        'limit': '$limit',
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
}
