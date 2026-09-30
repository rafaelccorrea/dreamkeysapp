import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';
import '../models/whatsapp_anexos.dart';
import '../models/whatsapp_models.dart';

/// Serviço do WhatsApp Inbox — consome `/whatsapp/*` (paridade com
/// `whatsappApi` + `whatsappUnofficialApi` do imobx-front). O backend escopa
/// tudo por empresa (X-Company-ID) e por SDR quando aplicável.
///
/// Endpoints (constantes privadas — a fiação central pode promovê-las para
/// `ApiConstants` depois):
///   GET   /whatsapp/messages                       (whatsapp:view_messages)
///   GET   /whatsapp/messages/conversations-count   (whatsapp:view_messages)
///   GET   /whatsapp/messages/unread-count          (whatsapp:view_messages)
///   GET   /whatsapp/messages/:id                   (rota que o web chama;
///                                                   o back ainda não tem)
///   POST  /whatsapp/messages/:id/read              (whatsapp:view_messages)
///   POST  /whatsapp/messages/:id/claim             (whatsapp:view_messages)
///   PATCH /whatsapp/conversations/finalize         (whatsapp:view_messages)
///   POST  /whatsapp/send             [multipart]   (whatsapp:send)
///   POST  /whatsapp/send-template                  (whatsapp:send)
///   GET   /whatsapp/templates                      (whatsapp:manage_config)
///   POST  /whatsapp/unofficial/messages/send       (whatsapp:send)
///   POST  /whatsapp/unofficial/messages/send-media [multipart] (whatsapp:send)
///   GET   /whatsapp/unofficial/config/status       (whatsapp:view)
///   GET   /whatsapp/unofficial/quick-messages      (whatsapp:view)
class WhatsAppService {
  WhatsAppService._();

  static final WhatsAppService instance = WhatsAppService._();
  final ApiService _api = ApiService.instance;

  static const String _kMessages = '/whatsapp/messages';
  static const String _kConversationsCount =
      '/whatsapp/messages/conversations-count';
  static const String _kUnreadCount = '/whatsapp/messages/unread-count';
  static String _kMessageRead(String id) => '/whatsapp/messages/$id/read';
  static String _kMessageById(String id) => '/whatsapp/messages/$id';
  static String _kMessageClaim(String id) => '/whatsapp/messages/$id/claim';
  static const String _kUnofficialSendMedia =
      '/whatsapp/unofficial/messages/send-media';
  static const String _kSend = '/whatsapp/send';
  static const String _kSendTemplate = '/whatsapp/send-template';
  static const String _kTemplates = '/whatsapp/templates';
  static const String _kFinalizeConversation =
      '/whatsapp/conversations/finalize';
  static const String _kUnofficialSend = '/whatsapp/unofficial/messages/send';
  static const String _kIntegrationStatus =
      '/whatsapp/unofficial/config/status';
  static const String _kQuickMessages = '/whatsapp/unofficial/quick-messages';

  /// Monta os parâmetros comuns da listagem/contagem — aba de atendimento +
  /// busca + filtros do painel. Paridade com `effectiveFilters` do
  /// `WhatsAppMessagesList.tsx`.
  Map<String, String> _buildListParams({
    required WhatsAppAttendanceTab tab,
    String? search,
    WhatsAppInboxFilters filters = const WhatsAppInboxFilters(),
    String? currentUserId,
  }) {
    final params = <String, String>{...filters.toQueryParams()};
    final s = (search ?? '').trim();
    if (s.isNotEmpty) params['search'] = s;
    switch (tab) {
      case WhatsAppAttendanceTab.mine:
        if (currentUserId != null && currentUserId.isNotEmpty) {
          params['assignedToId'] = currentUserId;
        }
        break;
      case WhatsAppAttendanceTab.waiting:
        params['unassignedOnly'] = 'true';
        break;
      case WhatsAppAttendanceTab.inProgress:
        params['assignedOnly'] = 'true';
        break;
      case WhatsAppAttendanceTab.finalized:
        params['finalizedOnly'] = 'true';
        break;
      case WhatsAppAttendanceTab.all:
        break;
    }
    return params;
  }

  /// `GET /whatsapp/messages?groupByPhone=true` — lista de conversas (uma por
  /// contato). Normaliza tanto o formato `{ conversations, total }` quanto o
  /// fallback `{ messages, total }`.
  Future<ApiResponse<WhatsAppConversationListResult>> getConversations({
    required WhatsAppAttendanceTab tab,
    String? search,
    WhatsAppInboxFilters filters = const WhatsAppInboxFilters(),
    String? currentUserId,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final params = _buildListParams(
        tab: tab,
        search: search,
        filters: filters,
        currentUserId: currentUserId,
      );
      params['limit'] = '$limit';
      params['offset'] = '$offset';
      params['groupByPhone'] = 'true';

      final response = await _api.get<Map<String, dynamic>>(
        _kMessages,
        queryParameters: params,
      );
      if (response.success && response.data != null) {
        final raw = response.data!;
        final conversations = <WhatsAppConversation>[];

        final rawConversations = raw['conversations'];
        if (rawConversations is List) {
          for (final item in rawConversations) {
            if (item is Map) {
              conversations.add(WhatsAppConversation.fromJson(
                  Map<String, dynamic>.from(item)));
            }
          }
        } else if (raw['messages'] is List) {
          // Fallback: lista plana — agrupa por telefone preservando a ordem.
          final seen = <String>{};
          for (final item in raw['messages'] as List) {
            if (item is! Map) continue;
            final m = WhatsAppMessage.fromJson(Map<String, dynamic>.from(item));
            if (m.phoneNumber.isEmpty || !seen.add(m.phoneNumber)) continue;
            conversations.add(WhatsAppConversation.fromMessage(m));
          }
        }

        final total = raw['total'] is num
            ? (raw['total'] as num).toInt()
            : conversations.length;
        return ApiResponse.success(
          data: WhatsAppConversationListResult(
            conversations: conversations,
            total: total,
          ),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar conversas',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [WHATSAPP] getConversations: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /whatsapp/messages/conversations-count` — total real de conversas
  /// (contatos distintos) sob os mesmos filtros da listagem.
  Future<int?> getConversationsCount({
    required WhatsAppAttendanceTab tab,
    String? search,
    WhatsAppInboxFilters filters = const WhatsAppInboxFilters(),
    String? currentUserId,
  }) async {
    try {
      final params = _buildListParams(
        tab: tab,
        search: search,
        filters: filters,
        currentUserId: currentUserId,
      );
      final response = await _api.get<Map<String, dynamic>>(
        _kConversationsCount,
        queryParameters: params,
      );
      if (response.success && response.data != null) {
        final count = response.data!['count'];
        if (count is num) return count.toInt();
      }
      return null;
    } catch (e) {
      debugPrint('❌ [WHATSAPP] getConversationsCount: $e');
      return null;
    }
  }

  /// `GET /whatsapp/messages/unread-count` — total de não lidas da empresa.
  Future<int?> getUnreadCount() async {
    try {
      final response =
          await _api.get<Map<String, dynamic>>(_kUnreadCount);
      if (response.success && response.data != null) {
        final count = response.data!['count'];
        if (count is num) return count.toInt();
      }
      return null;
    } catch (e) {
      debugPrint('❌ [WHATSAPP] getUnreadCount: $e');
      return null;
    }
  }

  /// `GET /whatsapp/messages?phoneNumber=...` — thread de um contato,
  /// paginada do mais recente para o mais antigo (ordem do backend).
  Future<ApiResponse<WhatsAppMessageListResult>> getMessages({
    required String phoneNumber,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(
        _kMessages,
        queryParameters: {
          'phoneNumber': phoneNumber,
          'limit': '$limit',
          'offset': '$offset',
        },
      );
      if (response.success && response.data != null) {
        final raw = response.data!;
        final messages = <WhatsAppMessage>[];
        if (raw['messages'] is List) {
          for (final item in raw['messages'] as List) {
            if (item is Map) {
              messages.add(
                  WhatsAppMessage.fromJson(Map<String, dynamic>.from(item)));
            }
          }
        }
        final total =
            raw['total'] is num ? (raw['total'] as num).toInt() : messages.length;
        return ApiResponse.success(
          data: WhatsAppMessageListResult(messages: messages, total: total),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar mensagens',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [WHATSAPP] getMessages: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /whatsapp/messages/:id/read` — marca uma mensagem como lida.
  Future<bool> markAsRead(String messageId) async {
    try {
      final response = await _api.post<dynamic>(_kMessageRead(messageId));
      return response.success;
    } catch (e) {
      debugPrint('❌ [WHATSAPP] markAsRead: $e');
      return false;
    }
  }

  /// O back ainda não tem `GET /whatsapp/messages/:id` (29/09/2026): o web
  /// chama essa rota para renovar a URL assinada da mídia e recebe 404. Depois
  /// do primeiro 404 a sessão para de tentar e a tela renova relendo a
  /// thread (ver `_renovarMidia` na conversa).
  static bool _rotaDaMensagemAusente = false;

  /// `GET /whatsapp/messages/:id` — mensagem com a `mediaUrl` assinada de
  /// novo (paridade com `whatsappApi.getMessage`). `null` quando o back não
  /// devolve a mensagem.
  Future<WhatsAppMessage?> getMessage(String messageId) async {
    if (_rotaDaMensagemAusente || messageId.isEmpty) return null;
    try {
      final response =
          await _api.get<Map<String, dynamic>>(_kMessageById(messageId));
      if (response.success && response.data != null) {
        return WhatsAppMessage.fromJson(response.data!);
      }
      if (response.statusCode == 404) _rotaDaMensagemAusente = true;
      return null;
    } catch (e) {
      debugPrint('❌ [WHATSAPP] getMessage: $e');
      return null;
    }
  }

  /// `POST /whatsapp/messages/:id/claim` — o atendente assume para si a
  /// conversa da fila (Aguardando). Paridade com `whatsappApi
  /// .claimConversation` (29/09/2026). O back recusa com a frase do motivo
  /// ("Você está pausado ou inativo…", "Esta conversa já está com outro
  /// atendente."), que vai direto para a tela.
  Future<ApiResponse<void>> claimConversation(String messageId) async {
    try {
      final response = await _api.post<dynamic>(_kMessageClaim(messageId));
      if (response.success) {
        return ApiResponse.success(statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao assumir conversa.',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [WHATSAPP] claimConversation: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `PATCH /whatsapp/conversations/finalize` — finaliza a conversa (sai das
  /// abas ativas; nova mensagem do contato reabre automaticamente).
  Future<ApiResponse<void>> finalizeConversation(String phoneNumber) async {
    try {
      final response = await _api.patch<dynamic>(
        _kFinalizeConversation,
        body: {'phoneNumber': phoneNumber},
      );
      if (response.success) {
        return ApiResponse.success(statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao finalizar conversa',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [WHATSAPP] finalizeConversation: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Envia mensagem de texto pelo canal resolvido.
  ///
  /// - Oficial (Meta): `POST /whatsapp/send` em **multipart/form-data**
  ///   (mesmo formato do web — o endpoint usa FileInterceptor).
  /// - Não oficial (Baileys): `POST /whatsapp/unofficial/messages/send` JSON.
  Future<ApiResponse<void>> sendText({
    required String to,
    required String message,
    String? clientId,
    bool viaUnofficial = false,
  }) async {
    if (viaUnofficial) {
      try {
        final response = await _api.post<dynamic>(
          _kUnofficialSend,
          body: {'to': to, 'message': message},
        );
        if (response.success) {
          return ApiResponse.success(statusCode: response.statusCode);
        }
        return ApiResponse.error(
          message: response.message ?? 'Erro ao enviar mensagem',
          statusCode: response.statusCode,
          data: response.error,
        );
      } catch (e) {
        debugPrint('❌ [WHATSAPP] sendText (unofficial): $e');
        return ApiResponse.error(
          message: 'Erro de conexão: ${e.toString()}',
          statusCode: 0,
        );
      }
    }

    // Canal oficial — multipart (paridade com `whatsappApi.sendMessage`).
    try {
      final uri = Uri.parse('${ApiConstants.baseApiUrl}$_kSend');
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(await _api.buildOutboundHeaders(
        endpoint: _kSend,
        excludeContentType: true,
      ));
      request.fields['to'] = to;
      request.fields['message'] = message;
      if (clientId != null && clientId.isNotEmpty) {
        request.fields['clientId'] = clientId;
      }
      final streamed =
          await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ApiResponse.success(statusCode: response.statusCode);
      }
      String message0 = 'Erro ao enviar mensagem';
      try {
        final body = response.body;
        final match = RegExp('"message"\\s*:\\s*"([^"]+)"').firstMatch(body);
        if (match != null) message0 = match.group(1)!;
      } catch (_) {}
      return ApiResponse.error(
        message: message0,
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [WHATSAPP] sendText (official): $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Envia UM anexo da bandeja (29/09/2026) — paridade com
  /// `whatsappApi.sendMessage` (canal oficial) e
  /// `whatsappUnofficialApi.sendMedia` (QR Code):
  /// - Oficial: `POST /whatsapp/send` multipart; imagem no campo `image`
  ///   (o campo histórico), documento e áudio no campo `file`; a legenda vai
  ///   em `message`.
  /// - QR Code: `POST /whatsapp/unofficial/messages/send-media` multipart com
  ///   `media` e `caption`.
  ///
  /// Timeout de 90 s (upload + S3 + Meta), o mesmo do web. Quando a
  /// requisição saiu e a resposta não voltou (timeout, queda de rede), o erro
  /// leva `{'naoConfirmado': true}` em `error`: a mensagem pode ter saído, e
  /// reenviar duplicaria o arquivo na cliente.
  Future<ApiResponse<void>> sendMedia({
    required String to,
    required WhatsAppAnexo anexo,
    String? caption,
    String? clientId,
    bool viaUnofficial = false,
  }) async {
    final endpoint = viaUnofficial ? _kUnofficialSendMedia : _kSend;
    final legenda = (caption ?? '').trim();
    final http.MultipartRequest request;
    try {
      // O upload pode levar dezenas de segundos e o multipart não passa pelo
      // refresh automático do ApiService: o token precisa chegar válido.
      await _api.garantirTokenFresco(margemSegundos: 120);
      request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConstants.baseApiUrl}$endpoint'),
      );
      request.headers.addAll(await _api.buildOutboundHeaders(
        endpoint: endpoint,
        excludeContentType: true,
      ));
      request.fields['to'] = to;
      final String campo;
      if (viaUnofficial) {
        campo = 'media';
        if (legenda.isNotEmpty) request.fields['caption'] = legenda;
      } else {
        campo = anexo.ehImagem ? 'image' : 'file';
        request.fields['message'] = legenda;
        if (clientId != null && clientId.isNotEmpty) {
          request.fields['clientId'] = clientId;
        }
      }
      // O tipo vai explícito: o back decide imagem × documento × áudio por
      // ele (e o QR Code manda como vídeo tudo que não for `image/*`).
      request.files.add(await http.MultipartFile.fromPath(
        campo,
        anexo.caminho,
        filename: anexo.nomeParaEnvio,
        contentType: _tipoDoConteudo(anexo.mime),
      ));
    } catch (e) {
      debugPrint('❌ [WHATSAPP] sendMedia (preparo): $e');
      return ApiResponse.error(
        message: 'Não foi possível preparar "${anexo.nome}" para envio: $e',
        statusCode: 0,
      );
    }

    try {
      final streamed =
          await request.send().timeout(const Duration(seconds: 90));
      final response = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ApiResponse.success(statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: _mensagemDoErro(
          response.body,
          'Erro ao enviar "${anexo.nome}" (HTTP ${response.statusCode}).',
        ),
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [WHATSAPP] sendMedia: $e');
      return ApiResponse.error(
        message: e is TimeoutException
            ? 'O envio de "${anexo.nome}" passou de 90 segundos sem resposta do servidor.'
            : 'A conexão caiu durante o envio de "${anexo.nome}".',
        statusCode: 0,
        data: const {'naoConfirmado': true},
      );
    }
  }

  static MediaType _tipoDoConteudo(String mime) {
    try {
      if (mime.isNotEmpty) return MediaType.parse(mime);
    } catch (_) {}
    return MediaType('application', 'octet-stream');
  }

  /// Frase do back (`message` em texto ou lista) ou [padrao].
  static String _mensagemDoErro(String body, String padrao) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final m = decoded['message'];
        if (m is String && m.trim().isNotEmpty) return m.trim();
        if (m is List && m.isNotEmpty) {
          return m.map((e) => e.toString()).join('\n');
        }
        final erro = decoded['error'];
        if (erro is String && erro.trim().isNotEmpty) return erro.trim();
      }
    } catch (_) {}
    return padrao;
  }

  /// `POST /whatsapp/send-template` — envia template aprovado (reabre a
  /// janela de 24h da API oficial).
  Future<ApiResponse<void>> sendTemplate({
    required String to,
    required String templateName,
    List<String> parameters = const [],
    String? clientId,
  }) async {
    try {
      final body = <String, dynamic>{
        'to': to,
        'templateName': templateName,
        if (parameters.isNotEmpty) 'parameters': parameters,
        if (clientId != null && clientId.isNotEmpty) 'clientId': clientId,
      };
      final response = await _api.post<dynamic>(_kSendTemplate, body: body);
      if (response.success) {
        return ApiResponse.success(statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao enviar template',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [WHATSAPP] sendTemplate: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /whatsapp/templates` — templates aprovados na Meta. Exige
  /// `whatsapp:manage_config` no backend: quem não tem recebe 403 e a UI
  /// oferece digitação manual do nome do template.
  Future<ApiResponse<List<WhatsAppTemplate>>> getTemplates() async {
    try {
      final response = await _api.get<dynamic>(_kTemplates);
      if (response.success) {
        final raw = response.data;
        final templates = <WhatsAppTemplate>[];
        if (raw is List) {
          for (final item in raw) {
            if (item is Map) {
              templates.add(
                  WhatsAppTemplate.fromJson(Map<String, dynamic>.from(item)));
            }
          }
        }
        return ApiResponse.success(
          data: templates,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar templates',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [WHATSAPP] getTemplates: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /whatsapp/unofficial/quick-messages` — biblioteca "mensagem pronta"
  /// da empresa (compartilhadas + pessoais do usuário). Exige `whatsapp:view`.
  ///
  /// Devolve LISTA VAZIA em qualquer tropeço (403 sem permissão, módulo
  /// desligado, empresa que nunca foi semeada). Quem chama sempre tem os
  /// modelos locais — a biblioteca é um acréscimo, nunca o piso.
  Future<List<WhatsAppQuickMessage>> getQuickMessages({
    String? search,
    String? category,
  }) async {
    try {
      final params = <String, String>{};
      final s = (search ?? '').trim();
      if (s.isNotEmpty) params['search'] = s;
      final c = (category ?? '').trim();
      if (c.isNotEmpty) params['category'] = c;

      final response = await _api.get<dynamic>(
        _kQuickMessages,
        queryParameters: params.isEmpty ? null : params,
      );
      if (!response.success || response.data == null) return const [];

      // O controller devolve o array cru; toleramos `{ data: [...] }`.
      final raw = response.data;
      final list = raw is List
          ? raw
          : (raw is Map && raw['data'] is List
              ? raw['data'] as List
              : const []);

      return list
          .whereType<Map>()
          .map(
            (e) => WhatsAppQuickMessage.fromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .where((m) => m.isActive && m.message.trim().isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('❌ [WHATSAPP] getQuickMessages: $e');
      return const [];
    }
  }

  /// `GET /whatsapp/unofficial/config/status` — resolve o canal usado no
  /// atendimento (oficial × QR Code). Exige `whatsapp:view`; sem a permissão
  /// (403) degradamos para "oficial" sem quebrar a tela.
  Future<WhatsAppIntegrationStatus?> getIntegrationStatus() async {
    try {
      final response =
          await _api.get<Map<String, dynamic>>(_kIntegrationStatus);
      if (response.success && response.data != null) {
        return WhatsAppIntegrationStatus.fromJson(response.data!);
      }
      return null;
    } catch (e) {
      debugPrint('❌ [WHATSAPP] getIntegrationStatus: $e');
      return null;
    }
  }
}
