import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';
import '../models/ticket_models.dart';

/// Fonte exibível de um anexo: URL assinada (S3) OU bytes baixados via
/// stream autenticado (storage local) — espelha `getAttachmentUrl` do web.
class TicketAttachmentSource {
  final String? url;
  final Uint8List? bytes;

  const TicketAttachmentSource({this.url, this.bytes});

  bool get hasData => url != null || bytes != null;
}

/// Serviço de Tickets/Suporte — consome o microserviço `intellisys-tickets`
/// através do proxy da API principal (`/tickets-proxy/*`, ver
/// `TicketsProxyController` no imobx). Assim o app usa o MESMO baseUrl,
/// Authorization e `X-Company-ID` de todas as outras rotas.
///
/// Paridade com `ticketsApi` do imobx-front (visão do solicitante):
///   - `GET    /tickets`                     → lista (empresa vê os próprios)
///   - `POST   /tickets`                     → abrir ticket (perm ticket:create)
///   - `GET    /tickets/:id`                 → detalhe + conversa + histórico
///   - `DELETE /tickets/:id`                 → excluir (só sem atendimento)
///   - `POST   /tickets/:id/comments`        → responder ({ body })
///   - `POST   /tickets/:id/attachments`     → anexo (multipart `file`)
///   - `GET    /tickets/attachments/:id/link`     → URL assinada ou modo buffer
///   - `GET    /tickets/attachments/:id/download` → stream binário autenticado
class TicketService {
  TicketService._();

  static final TicketService instance = TicketService._();
  final ApiService _api = ApiService.instance;

  // Endpoints (constantes privadas — a fiação central não é necessária aqui,
  // pois tudo passa pelo proxy `/tickets-proxy` da API principal).
  static const String _base = '/tickets-proxy/tickets';
  static String _ticketById(String id) => '$_base/${Uri.encodeComponent(id)}';
  static String _ticketComments(String id) => '${_ticketById(id)}/comments';
  static String _ticketAttachments(String id) =>
      '${_ticketById(id)}/attachments';
  static String _attachmentLink(String attachmentId) =>
      '$_base/attachments/${Uri.encodeComponent(attachmentId)}/link';
  static String _attachmentDownload(String attachmentId) =>
      '$_base/attachments/${Uri.encodeComponent(attachmentId)}/download';

  /// `GET /tickets` — meus tickets (o backend escopa pela empresa).
  Future<ApiResponse<TicketListResult>> list({
    int page = 1,
    int limit = 100,
    TicketStatus? status,
    TicketCategory? category,
    String? search,
  }) async {
    try {
      final query = <String, String>{'page': '$page', 'limit': '$limit'};
      if (status != null && status != TicketStatus.unknown) {
        query['status'] = status.apiValue;
      }
      if (category != null) query['category'] = category.apiValue;
      final s = search?.trim();
      if (s != null && s.isNotEmpty) query['search'] = s;

      final response = await _api.get<dynamic>(_base, queryParameters: query);
      if (response.success && response.data != null) {
        final raw = response.data;
        final result = raw is Map<String, dynamic>
            ? TicketListResult.fromJson(raw)
            : raw is Map
            ? TicketListResult.fromJson(Map<String, dynamic>.from(raw))
            : raw is List
            ? TicketListResult(
                items: raw
                    .whereType<Map>()
                    .map((e) => Ticket.fromJson(Map<String, dynamic>.from(e)))
                    .toList(),
                total: raw.length,
                page: page,
                limit: limit,
              )
            : TicketListResult.empty;
        return ApiResponse.success(
          data: result,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar os tickets',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [TICKETS] list: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /tickets/:id` — detalhe com conversa, anexos e histórico.
  Future<ApiResponse<TicketDetail>> getDetail(String id) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(_ticketById(id));
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: TicketDetail.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Ticket não encontrado',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [TICKETS] getDetail: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /tickets` — abre um ticket (permissão `ticket:create`).
  Future<ApiResponse<Ticket>> create(CreateTicketPayload payload) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        _base,
        body: payload.toJson(),
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: Ticket.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao abrir o ticket',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [TICKETS] create: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /tickets/:id/comments` — envia uma resposta na conversa.
  Future<ApiResponse<TicketComment>> addComment(
    String ticketId,
    String body,
  ) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        _ticketComments(ticketId),
        body: {'body': body},
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: TicketComment.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao enviar a mensagem',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [TICKETS] addComment: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `DELETE /tickets/:id` — exclui o ticket (o backend só permite para o
  /// solicitante enquanto não há atendimento).
  Future<ApiResponse<bool>> remove(String ticketId) async {
    try {
      final response = await _api.delete<dynamic>(_ticketById(ticketId));
      if (response.success) {
        return ApiResponse.success(data: true, statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao excluir o ticket',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [TICKETS] remove: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /tickets/:id/attachments` — envia um anexo (multipart `file`).
  /// Quando [commentId] é informado, o anexo fica ligado àquela mensagem.
  Future<ApiResponse<TicketAttachment>> uploadAttachment(
    String ticketId,
    File file, {
    String? commentId,
  }) async {
    try {
      final endpoint = _ticketAttachments(ticketId);
      final uri = Uri.parse('${ApiConstants.baseApiUrl}$endpoint');
      final request = http.MultipartRequest('POST', uri);

      // Headers padronizados (Authorization + X-Company-ID); sem Content-Type
      // porque o MultipartRequest define o boundary correto sozinho.
      final headers = await _api.buildOutboundHeaders(
        endpoint: endpoint,
        excludeContentType: true,
      );
      request.headers.addAll(headers);

      if (commentId != null && commentId.isNotEmpty) {
        request.fields['commentId'] = commentId;
      }

      final fileName = file.path.split('/').last.split('\\').last;
      request.files.add(
        http.MultipartFile(
          'file',
          http.ByteStream(file.openRead()),
          await file.length(),
          filename: fileName,
        ),
      );

      final streamed = await request.send().timeout(
        const Duration(seconds: 60),
      );
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = response.body.isNotEmpty
            ? _tryDecodeMap(response.body)
            : null;
        return ApiResponse.success(
          data: body != null
              ? TicketAttachment.fromJson(body)
              : TicketAttachment(
                  id: '',
                  fileName: fileName,
                  mimeType: '',
                  sizeBytes: 0,
                ),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: 'Erro ao enviar o anexo (${response.statusCode})',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [TICKETS] uploadAttachment: $e');
      return ApiResponse.error(
        message: 'Erro de conexão ao enviar o anexo',
        statusCode: 0,
      );
    }
  }

  /// Resolve a fonte exibível de um anexo: URL assinada (S3, modo `redirect`)
  /// ou bytes baixados via stream autenticado (storage local, modo `buffer`).
  Future<TicketAttachmentSource?> resolveAttachment(String attachmentId) async {
    try {
      final linkResponse = await _api.get<Map<String, dynamic>>(
        _attachmentLink(attachmentId),
      );
      if (linkResponse.success && linkResponse.data != null) {
        final mode = linkResponse.data!['mode']?.toString();
        final url = linkResponse.data!['url']?.toString();
        if (mode == 'redirect' && url != null && url.isNotEmpty) {
          return TicketAttachmentSource(url: url);
        }
      }

      // Fallback: download autenticado (bytes) via proxy.
      final endpoint = _attachmentDownload(attachmentId);
      final uri = Uri.parse('${ApiConstants.baseApiUrl}$endpoint');
      final headers = await _api.buildOutboundHeaders(endpoint: endpoint);
      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 45));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return TicketAttachmentSource(bytes: response.bodyBytes);
      }
      return null;
    } catch (e) {
      debugPrint('❌ [TICKETS] resolveAttachment: $e');
      return null;
    }
  }

  /// `jsonDecode` tolerante — devolve null em vez de lançar exceção.
  Map<String, dynamic>? _tryDecodeMap(String raw) {
    try {
      final decoded = raw.isEmpty ? null : jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }
}
