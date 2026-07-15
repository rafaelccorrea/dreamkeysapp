import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';
import '../models/zezin_models.dart';

/// Serviço do Zezin (assistente de IA) — consome `/whatsapp/zezin/*`
/// (paridade com `zezinApi` do imobx-front). O gating final (admin/dono +
/// plano Pro + módulo `ai_assistant`) é do backend via `ZezinAssistantGuard`;
/// aqui apenas espelhamos o fluxo do web: checar `availability` antes de tudo.
class ZezinService {
  ZezinService._();

  static final ZezinService instance = ZezinService._();
  final ApiService _api = ApiService.instance;

  // Endpoints (constantes privadas — a fiação central pode promovê-las ao
  // `ApiConstants` depois; manter em sincronia com o manifest da feature).
  static const String _availability = '/whatsapp/zezin/availability';
  static const String _config = '/whatsapp/zezin/config';
  static const String _ask = '/whatsapp/zezin/ask';
  static const String _askStream = '/whatsapp/zezin/ask-stream';
  static const String _suggestedQuestions =
      '/whatsapp/zezin/suggested-questions';
  static const String _suggestedQuestionsFollowUp =
      '/whatsapp/zezin/suggested-questions-follow-up';
  static const String _history = '/whatsapp/zezin/history';
  static String _historyThread(String threadId) =>
      '/whatsapp/zezin/history/thread/$threadId';
  static String _historyItem(String id) => '/whatsapp/zezin/history/$id';

  /// Alguns handlers do Nest embrulham a resposta em `{ data: {...} }`;
  /// outros devolvem o objeto direto. Normaliza os dois casos.
  Map<String, dynamic>? _unwrapMap(dynamic raw) {
    if (raw is Map) {
      final map = raw is Map<String, dynamic>
          ? raw
          : Map<String, dynamic>.from(raw);
      final inner = map['data'];
      if (inner is Map) {
        return inner is Map<String, dynamic>
            ? inner
            : Map<String, dynamic>.from(inner);
      }
      return map;
    }
    return null;
  }

  /// `GET /whatsapp/zezin/availability` — se o Zezin está liberado para o
  /// usuário/empresa. 403/404 são tratados como "indisponível" (paridade web).
  Future<ApiResponse<ZezinAvailability>> getAvailability() async {
    try {
      final response = await _api.get<Map<String, dynamic>>(_availability);
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: ZezinAvailability.fromJson(
              _unwrapMap(response.data) ?? response.data!),
          statusCode: response.statusCode,
        );
      }
      if (response.statusCode == 403 || response.statusCode == 404) {
        return ApiResponse.success(
          data: ZezinAvailability.unavailable,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao verificar disponibilidade',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [ZEZIN] getAvailability: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /whatsapp/zezin/config` — configuração atual (token mascarado).
  /// 404 → sucesso com `data == null` (ainda não configurado).
  Future<ApiResponse<ZezinConfig>> getConfig() async {
    try {
      final response = await _api.get<Map<String, dynamic>>(_config);
      if (response.success) {
        final body = _unwrapMap(response.data);
        return ApiResponse.success(
          data: body == null || body.isEmpty ? null : ZezinConfig.fromJson(body),
          statusCode: response.statusCode,
        );
      }
      if (response.statusCode == 404) {
        return ApiResponse.success(data: null, statusCode: 404);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar configuração',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [ZEZIN] getConfig: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /whatsapp/zezin/config` — cria/substitui a configuração
  /// (token completo obrigatório).
  Future<ApiResponse<ZezinConfig>> createOrUpdateConfig({
    required String phoneNumberId,
    required String apiToken,
    String? phoneNumber,
    bool isActive = true,
  }) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        _config,
        body: {
          'phoneNumberId': phoneNumberId.trim(),
          'apiToken': apiToken.trim(),
          if (phoneNumber != null && phoneNumber.trim().isNotEmpty)
            'phoneNumber': phoneNumber.trim(),
          'isActive': isActive,
        },
      );
      if (response.success) {
        final body = _unwrapMap(response.data);
        return ApiResponse.success(
          data: body == null ? null : ZezinConfig.fromJson(body),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao salvar configuração',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [ZEZIN] createOrUpdateConfig: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `PUT /whatsapp/zezin/config` — atualização parcial (sem trocar token).
  Future<ApiResponse<ZezinConfig>> updateConfig({
    String? phoneNumberId,
    String? apiToken,
    String? phoneNumber,
    bool? isActive,
  }) async {
    try {
      final response = await _api.put<Map<String, dynamic>>(
        _config,
        body: {
          if (phoneNumberId != null && phoneNumberId.trim().isNotEmpty)
            'phoneNumberId': phoneNumberId.trim(),
          if (apiToken != null && apiToken.trim().isNotEmpty)
            'apiToken': apiToken.trim(),
          if (phoneNumber != null && phoneNumber.trim().isNotEmpty)
            'phoneNumber': phoneNumber.trim(),
          'isActive': ?isActive,
        },
      );
      if (response.success) {
        final body = _unwrapMap(response.data);
        return ApiResponse.success(
          data: body == null ? null : ZezinConfig.fromJson(body),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar configuração',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [ZEZIN] updateConfig: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /whatsapp/zezin/ask` — pergunta com resposta completa (sem
  /// streaming). Usado como **fallback** quando o stream falha antes do
  /// primeiro chunk. Atenção: o fluxo sem stream não aceita `sectionId`.
  Future<ApiResponse<String>> ask(String message) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        _ask,
        body: {'message': message.trim()},
      );
      if (response.success && response.data != null) {
        final body = _unwrapMap(response.data) ?? response.data!;
        final answer = body['answer']?.toString() ?? '';
        return ApiResponse.success(
          data: answer,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'O Zezin não conseguiu responder',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [ZEZIN] ask: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /whatsapp/zezin/ask-stream` — resposta em streaming SSE (estilo
  /// ChatGPT). Eventos: `data: {"chunk":"..."}` e ao final
  /// `data: {"done":true,"conversationId":"..."}` (paridade com
  /// `zezinApi.askStream` do web).
  ///
  /// [sectionId] = threadId da conversa em curso (contexto). O
  /// `conversationId` devolvido no `onDone` deve virar o `sectionId` da
  /// próxima mensagem.
  ///
  /// Retorna quando o stream encerra. `onDone`/`onError` disparam no máximo
  /// uma vez cada.
  Future<void> askStream({
    required String message,
    String? sectionId,
    required void Function(String chunk) onChunk,
    required void Function(String? conversationId) onDone,
    required void Function(String message) onError,
  }) async {
    final client = http.Client();
    var doneEmitted = false;
    var errorEmitted = false;
    String? conversationId;

    void emitDone() {
      if (doneEmitted || errorEmitted) return;
      doneEmitted = true;
      onDone(conversationId);
    }

    void emitError(String msg) {
      if (doneEmitted || errorEmitted) return;
      errorEmitted = true;
      onError(msg);
    }

    void handleEventLine(String line) {
      if (!line.startsWith('data:')) return;
      final raw = line.substring(5).trim();
      if (raw.isEmpty) return;
      try {
        final data = jsonDecode(raw);
        if (data is! Map) return;
        final chunk = data['chunk'];
        if (chunk is String && chunk.isNotEmpty) onChunk(chunk);
        if (data['done'] == true) {
          final cid = data['conversationId']?.toString().trim();
          if (cid != null && cid.isNotEmpty) conversationId = cid;
          emitDone();
        }
        final err = data['error'];
        if (err != null) emitError(err.toString());
      } catch (_) {
        // linha parcial/não-JSON — ignora (paridade web)
      }
    }

    try {
      final uri = Uri.parse('${ApiConstants.baseApiUrl}$_askStream');
      final headers = await _api.buildOutboundHeaders(endpoint: _askStream);
      final request = http.Request('POST', uri)
        ..headers.addAll(headers)
        ..body = jsonEncode({
          'message': message.trim(),
          if (sectionId != null && sectionId.trim().isNotEmpty)
            'sectionId': sectionId.trim(),
        });

      // Timeout só para o handshake — a resposta pode demorar vários
      // segundos gerando tokens, então o corpo não tem timeout agressivo.
      final response =
          await client.send(request).timeout(const Duration(seconds: 30));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        String msg = 'Erro ${response.statusCode} ao falar com o Zezin';
        try {
          final body = await response.stream.bytesToString();
          final decoded = jsonDecode(body);
          if (decoded is Map && decoded['message'] != null) {
            msg = decoded['message'].toString();
          }
        } catch (_) {}
        emitError(msg);
        return;
      }

      var buffer = '';
      await for (final text
          in response.stream.transform(const Utf8Decoder(allowMalformed: true))) {
        buffer += text;
        final lines = buffer.split('\n');
        buffer = lines.removeLast();
        for (final line in lines) {
          handleEventLine(line.trimRight());
        }
        if (doneEmitted || errorEmitted) break;
      }
      if (buffer.trim().isNotEmpty) handleEventLine(buffer.trim());
      emitDone();
    } on TimeoutException {
      emitError('O Zezin demorou para responder. Tente novamente.');
    } catch (e) {
      debugPrint('❌ [ZEZIN] askStream: $e');
      emitError('Falha de conexão com o Zezin. Verifique sua internet.');
    } finally {
      client.close();
    }
  }

  /// `GET /whatsapp/zezin/suggested-questions` — atalhos fixos com dados reais.
  Future<ApiResponse<List<ZezinSuggestedQuestion>>>
      getSuggestedQuestions() async {
    return _getSuggestions(_suggestedQuestions);
  }

  /// `GET /whatsapp/zezin/suggested-questions-follow-up` — sugestões geradas
  /// por IA com base no histórico recente da conversa.
  Future<ApiResponse<List<ZezinSuggestedQuestion>>>
      getFollowUpSuggestions() async {
    return _getSuggestions(_suggestedQuestionsFollowUp);
  }

  Future<ApiResponse<List<ZezinSuggestedQuestion>>> _getSuggestions(
      String endpoint) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(endpoint);
      if (response.success && response.data != null) {
        final body = _unwrapMap(response.data) ?? response.data!;
        return ApiResponse.success(
          data: ZezinSuggestedQuestion.listFromJson(body['questions']),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar sugestões',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [ZEZIN] _getSuggestions($endpoint): $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /whatsapp/zezin/history` — conversas (uma entrada por thread),
  /// mais recentes primeiro.
  Future<ApiResponse<List<ZezinThreadSummary>>> getHistory(
      {int? limit}) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(
        _history,
        queryParameters: limit != null ? {'limit': '$limit'} : null,
      );
      if (response.success && response.data != null) {
        final body = _unwrapMap(response.data) ?? response.data!;
        final rawThreads = body['threads'];
        final threads = rawThreads is List
            ? rawThreads
                .whereType<Map>()
                .map((e) =>
                    ZezinThreadSummary.fromJson(Map<String, dynamic>.from(e)))
                .where((t) => t.threadId.isNotEmpty)
                .toList(growable: false)
            : <ZezinThreadSummary>[];
        return ApiResponse.success(
          data: threads,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar histórico',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [ZEZIN] getHistory: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /whatsapp/zezin/history/thread/:threadId` — mensagens da conversa.
  Future<ApiResponse<List<ZezinHistoryItem>>> getThreadMessages(
      String threadId) async {
    try {
      final response =
          await _api.get<Map<String, dynamic>>(_historyThread(threadId));
      if (response.success && response.data != null) {
        final body = _unwrapMap(response.data) ?? response.data!;
        final rawItems = body['items'];
        final items = rawItems is List
            ? rawItems
                .whereType<Map>()
                .map((e) =>
                    ZezinHistoryItem.fromJson(Map<String, dynamic>.from(e)))
                .toList(growable: false)
            : <ZezinHistoryItem>[];
        return ApiResponse.success(
          data: items,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar a conversa',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [ZEZIN] getThreadMessages: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `DELETE /whatsapp/zezin/history/thread/:threadId` — exclui a conversa
  /// inteira (soft delete).
  Future<ApiResponse<bool>> deleteThread(String threadId) async {
    try {
      final response =
          await _api.delete<Map<String, dynamic>>(_historyThread(threadId));
      if (response.success) {
        return ApiResponse.success(data: true, statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Não foi possível excluir a conversa',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [ZEZIN] deleteThread: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `DELETE /whatsapp/zezin/history/:id` — exclui uma troca do histórico.
  Future<ApiResponse<bool>> deleteHistoryItem(String id) async {
    try {
      final response =
          await _api.delete<Map<String, dynamic>>(_historyItem(id));
      if (response.success) {
        return ApiResponse.success(data: true, statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Não foi possível excluir',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [ZEZIN] deleteHistoryItem: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `PATCH /whatsapp/zezin/history/:id` — renomeia a conversa (o web passa
  /// o `threadId` como `:id`; espelhamos o mesmo comportamento).
  Future<ApiResponse<bool>> updateHistoryTitle(
      String threadId, String title) async {
    try {
      final trimmed = title.trim();
      final clamped =
          trimmed.length > 200 ? trimmed.substring(0, 200) : trimmed;
      final response = await _api.patch<Map<String, dynamic>>(
        _historyItem(threadId),
        body: {'title': clamped},
      );
      if (response.success) {
        return ApiResponse.success(data: true, statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Não foi possível atualizar o título',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [ZEZIN] updateHistoryTitle: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}
