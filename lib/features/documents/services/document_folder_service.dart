import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';
import '../models/document_folder_model.dart';

/// Pastas de documentos do CRM — paridade com `documentFolderApi` do web
/// (`imobx-front/src/services/documentFolderApi.ts`) e com o controller
/// `document-folders` do back (módulo `kanban_management`).
class DocumentFolderService {
  DocumentFolderService._();

  static final DocumentFolderService instance = DocumentFolderService._();
  final ApiService _api = ApiService.instance;

  static const String _base = '/document-folders';
  static String _fromTask(String taskId) => '$_base/from-task/$taskId';
  static String _byTask(String taskId) => '$_base/by-task/$taskId';
  static String _byId(String id) => '$_base/$id';
  static String _syncTemplate(String id) => '$_base/$id/sync-template';
  static String _itemUpload(String id, String itemId) =>
      '$_base/$id/items/$itemId/upload';
  static String _itemSendLink(String id, String itemId) =>
      '$_base/$id/items/$itemId/send-link';
  static String _itemReview(String id, String itemId) =>
      '$_base/$id/items/$itemId/review';
  static String _exportBundle(String id) => '$_base/$id/export-bundle';
  static String _activeTemplate(String empreendimentoId) =>
      '/document-templates/empreendimento/$empreendimentoId/active';

  ApiResponse<DocumentFolder> _folderFrom(ApiResponse<dynamic> r, String err) {
    if (r.success && r.data is Map) {
      try {
        return ApiResponse.success(
          data: DocumentFolder.fromJson(
            Map<String, dynamic>.from(r.data as Map),
          ),
          statusCode: r.statusCode,
        );
      } catch (e) {
        debugPrint('❌ [DOCUMENT_FOLDERS] parse: $e');
        return ApiResponse.error(
          message: 'Erro ao processar a pasta',
          statusCode: r.statusCode,
        );
      }
    }
    return ApiResponse.error(
      message: r.message ?? err,
      statusCode: r.statusCode,
    );
  }

  /// `GET /document-folders/by-task/:taskId` — `null` quando o card ainda não
  /// tem pasta.
  Future<ApiResponse<DocumentFolder?>> getByTask(String taskId) async {
    try {
      final r = await _api.get<dynamic>(_byTask(taskId));
      if (r.success) {
        if (r.data is Map && (r.data as Map).isNotEmpty) {
          return ApiResponse.success(
            data: DocumentFolder.fromJson(
              Map<String, dynamic>.from(r.data as Map),
            ),
            statusCode: r.statusCode,
          );
        }
        return ApiResponse.success(data: null, statusCode: r.statusCode);
      }
      return ApiResponse.error(
        message: r.message ?? 'Erro ao carregar a pasta de documentos',
        statusCode: r.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// `POST /document-folders/from-task/:taskId`.
  Future<ApiResponse<DocumentFolder>> createFromTask(String taskId) async {
    try {
      final r = await _api.post<dynamic>(_fromTask(taskId));
      return _folderFrom(r, 'Erro ao criar pasta');
    } catch (e) {
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// `POST /document-folders/:id/sync-template`.
  Future<ApiResponse<DocumentFolder>> syncFromTemplate(String folderId) async {
    try {
      final r = await _api.post<dynamic>(_syncTemplate(folderId));
      return _folderFrom(r, 'Erro ao aplicar modelo');
    } catch (e) {
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// `GET /document-folders/:id`.
  Future<ApiResponse<DocumentFolder>> getById(String folderId) async {
    try {
      final r = await _api.get<dynamic>(_byId(folderId));
      return _folderFrom(r, 'Erro ao carregar a pasta');
    } catch (e) {
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// `GET /document-folders` com os filtros do web (`search`, `status`,
  /// `assignedToId`, `incorporadoraStatus`, `empreendimentoId`, página).
  Future<ApiResponse<DocumentFolderListResult>> list({
    String? search,
    String? status,
    String? assignedToId,
    String? incorporadoraStatus,
    String? empreendimentoId,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final q = <String, String>{'page': '$page', 'limit': '$limit'};
      if (search != null && search.trim().isNotEmpty) {
        q['search'] = search.trim();
      }
      if (status != null && status.isNotEmpty) q['status'] = status;
      if (assignedToId != null && assignedToId.isNotEmpty) {
        q['assignedToId'] = assignedToId;
      }
      if (incorporadoraStatus != null && incorporadoraStatus.isNotEmpty) {
        q['incorporadoraStatus'] = incorporadoraStatus;
      }
      if (empreendimentoId != null && empreendimentoId.isNotEmpty) {
        q['empreendimentoId'] = empreendimentoId;
      }
      final r = await _api.get<dynamic>(_base, queryParameters: q);
      if (r.success && r.data is Map) {
        final m = Map<String, dynamic>.from(r.data as Map);
        final raw = m['data'];
        final folders = <DocumentFolder>[];
        if (raw is List) {
          for (final e in raw) {
            if (e is Map) {
              folders.add(
                DocumentFolder.fromJson(Map<String, dynamic>.from(e)),
              );
            }
          }
        }
        return ApiResponse.success(
          data: DocumentFolderListResult(
            data: folders,
            total: int.tryParse(m['total']?.toString() ?? '') ??
                folders.length,
            page: int.tryParse(m['page']?.toString() ?? '') ?? page,
            limit: int.tryParse(m['limit']?.toString() ?? '') ?? limit,
            visibilityScope: FolderListVisibilityScope.fromString(
              m['visibilityScope']?.toString(),
            ),
          ),
          statusCode: r.statusCode,
        );
      }
      return ApiResponse.error(
        message: r.message ?? 'Erro ao carregar pastas de documentos',
        statusCode: r.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Upload interno do arquivo de um item (já nasce aprovado) —
  /// `POST /document-folders/:id/items/:itemId/upload` (multipart `file`).
  Future<ApiResponse<DocumentFolder>> uploadItem(
    String folderId,
    String itemId,
    File file,
  ) async {
    try {
      final endpoint = _itemUpload(folderId, itemId);
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConstants.baseApiUrl}$endpoint'),
      );
      req.headers.addAll(
        await _api.buildOutboundHeaders(
          endpoint: endpoint,
          excludeContentType: true,
        ),
      );
      final name = file.path.split('/').last.split('\\').last;
      req.files.add(
        await http.MultipartFile.fromPath(
          'file',
          file.path,
          filename: name,
          contentType: _mediaTypeFor(name),
        ),
      );
      final streamed =
          await req.send().timeout(const Duration(seconds: 120));
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (body is Map) {
          return ApiResponse.success(
            data: DocumentFolder.fromJson(Map<String, dynamic>.from(body)),
            statusCode: res.statusCode,
          );
        }
      }
      return ApiResponse.error(
        message: _errorMessage(res) ?? 'Erro no upload',
        statusCode: res.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Gera o link público de envio do item — devolve a `uploadUrl`
  /// (`POST /document-folders/:id/items/:itemId/send-link`).
  Future<ApiResponse<String>> sendItemLink(
    String folderId,
    String itemId, {
    int? expirationDays,
    String? notes,
  }) async {
    try {
      final r = await _api.post<dynamic>(
        _itemSendLink(folderId, itemId),
        body: {
          'expirationDays': ?expirationDays,
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        },
      );
      if (r.success && r.data is Map) {
        final token = (r.data as Map)['token'];
        final url = token is Map ? token['uploadUrl']?.toString() : null;
        if (url != null && url.isNotEmpty) {
          return ApiResponse.success(data: url, statusCode: r.statusCode);
        }
        return ApiResponse.error(
          message: 'Link gerado sem endereço de envio',
          statusCode: r.statusCode,
        );
      }
      return ApiResponse.error(
        message: r.message ?? 'Erro ao gerar link',
        statusCode: r.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Aprova ou rejeita item enviado pelo cliente via link —
  /// `POST /document-folders/:id/items/:itemId/review`.
  Future<ApiResponse<DocumentFolder>> reviewItem(
    String folderId,
    String itemId, {
    required bool approve,
    String? notes,
  }) async {
    try {
      final r = await _api.post<dynamic>(
        _itemReview(folderId, itemId),
        body: {
          'action': approve ? 'approve' : 'reject',
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        },
      );
      return _folderFrom(r, 'Erro ao revisar documento');
    } catch (e) {
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Lote ZIP dos aprovados — `GET /document-folders/:id/export-bundle`.
  /// Devolve bytes + nome do arquivo (Content-Disposition).
  Future<ApiResponse<MapEntry<String, Uint8List>>> downloadBundle(
    String folderId,
  ) async {
    try {
      final endpoint = _exportBundle(folderId);
      final headers = await _api.buildOutboundHeaders(endpoint: endpoint);
      headers['Accept'] = 'application/zip, application/json';
      final res = await http
          .get(Uri.parse('${ApiConstants.baseApiUrl}$endpoint'), headers: headers)
          .timeout(const Duration(seconds: 180));
      final type = res.headers['content-type'] ?? '';
      if (res.statusCode >= 200 &&
          res.statusCode < 300 &&
          !type.contains('application/json')) {
        final name = _filenameFrom(res.headers['content-disposition']) ??
            'lote-documentos.zip';
        return ApiResponse.success(
          data: MapEntry(name, res.bodyBytes),
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.error(
        message: _errorMessage(res) ?? 'Erro ao gerar lote',
        statusCode: res.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Modelo ativo do empreendimento — o painel só libera "Iniciar pasta"
  /// quando há itens (`documentTemplateApi.getActive` do web).
  Future<ApiResponse<bool>> hasActiveTemplate(String empreendimentoId) async {
    try {
      final r = await _api.get<dynamic>(_activeTemplate(empreendimentoId));
      if (r.success) {
        final items = r.data is Map ? (r.data as Map)['items'] : null;
        return ApiResponse.success(
          data: items is List && items.isNotEmpty,
          statusCode: r.statusCode,
        );
      }
      return ApiResponse.error(
        message: r.message ?? 'Erro ao verificar o modelo',
        statusCode: r.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  String? _errorMessage(http.Response res) {
    try {
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is Map) {
        final m = body['message'];
        if (m is List) return m.join(', ');
        if (m != null) return m.toString();
      }
    } catch (_) {}
    return null;
  }

  String? _filenameFrom(String? disposition) {
    if (disposition == null) return null;
    final star = RegExp(r"filename\*=UTF-8''([^;]+)", caseSensitive: false)
        .firstMatch(disposition);
    if (star != null) return Uri.decodeComponent(star.group(1)!.trim());
    final plain = RegExp(r'filename="?([^";]+)"?', caseSensitive: false)
        .firstMatch(disposition);
    return plain?.group(1)?.trim();
  }

  MediaType? _mediaTypeFor(String name) {
    final ext = name.toLowerCase().split('.').last;
    switch (ext) {
      case 'pdf':
        return MediaType('application', 'pdf');
      case 'jpg':
      case 'jpeg':
        return MediaType('image', 'jpeg');
      case 'png':
        return MediaType('image', 'png');
      case 'webp':
        return MediaType('image', 'webp');
      case 'heic':
        return MediaType('image', 'heic');
      case 'doc':
        return MediaType('application', 'msword');
      case 'docx':
        return MediaType(
          'application',
          'vnd.openxmlformats-officedocument.wordprocessingml.document',
        );
      default:
        return null;
    }
  }
}
