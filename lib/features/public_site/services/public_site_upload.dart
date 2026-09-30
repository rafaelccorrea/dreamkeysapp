import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';

/// Upload multipart usado por Meu Site (capa do banner, logo, favicon) e Link
/// in Bio (avatar, fundo) — 29/09/2026 (integ-23 / integ-29).
///
/// Por que existe: o `ApiService` não faz multipart, e o back (Multer) filtra
/// pelo `mimetype` do arquivo. O `http.MultipartFile` manda
/// `application/octet-stream` por padrão, e aí o filtro do back recusa foto e
/// vídeo válidos. Aqui o tipo sai da extensão, os headers vêm do
/// `buildOutboundHeaders` (Authorization + X-Company-ID, mesma regra do web) e
/// a mensagem de erro é a do back (causa real), não um texto genérico.
class PublicSiteUpload {
  PublicSiteUpload._();

  static const Map<String, String> _mimeByExt = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'gif': 'image/gif',
    'svg': 'image/svg+xml',
    'ico': 'image/x-icon',
    'heic': 'image/heic',
    'heif': 'image/heif',
    'mp4': 'video/mp4',
    'm4v': 'video/mp4',
    'mov': 'video/quicktime',
    'webm': 'video/webm',
  };

  static String extensionOf(String path) {
    final name = path.split('/').last.split('\\').last;
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  static String? mimeOf(String path) => _mimeByExt[extensionOf(path)];

  static bool isVideoPath(String path) =>
      (mimeOf(path) ?? '').startsWith('video/');

  /// Extrai a mensagem do corpo de erro do Nest (`message` string ou lista).
  static String? _messageFrom(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final m = decoded['message'];
        if (m is String && m.trim().isNotEmpty) return m.trim();
        if (m is List && m.isNotEmpty) {
          return m.map((e) => e.toString()).join(' · ');
        }
        final e = decoded['error'];
        if (e is String && e.trim().isNotEmpty) return e.trim();
      }
    } catch (_) {}
    return null;
  }

  /// `POST` multipart com o arquivo no campo `file` e [fields] extras.
  /// Devolve o JSON do corpo (Map) em caso de sucesso.
  static Future<ApiResponse<Map<String, dynamic>>> post({
    required String endpoint,
    required File file,
    Map<String, String> fields = const {},
    required String fallbackError,
    Duration timeout = const Duration(seconds: 180),
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseApiUrl}$endpoint');
      final request = http.MultipartRequest('POST', uri);
      final headers = await ApiService.instance.buildOutboundHeaders(
        endpoint: endpoint,
        excludeContentType: true,
      );
      request.headers.addAll(headers);

      final mime = mimeOf(file.path);
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          file.path,
          contentType: mime != null ? MediaType.parse(mime) : null,
        ),
      );
      request.fields.addAll(fields);

      final streamed = await request.send().timeout(timeout);
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map) {
            final inner = decoded['data'];
            final body = inner is Map
                ? Map<String, dynamic>.from(inner)
                : Map<String, dynamic>.from(decoded);
            return ApiResponse.success(
              data: body,
              statusCode: response.statusCode,
            );
          }
        } catch (e) {
          debugPrint('❌ [PUBLIC_SITE_UPLOAD] parse $endpoint: $e');
        }
        return ApiResponse.error(
          message: 'Resposta inesperada do servidor ao enviar o arquivo',
          statusCode: response.statusCode,
        );
      }

      final reason = _messageFrom(response.body);
      return ApiResponse.error(
        message: reason ??
            (response.statusCode == 413
                ? 'Arquivo maior que o limite aceito pelo servidor'
                : '$fallbackError (HTTP ${response.statusCode})'),
        statusCode: response.statusCode,
        data: response.body,
      );
    } catch (e) {
      debugPrint('❌ [PUBLIC_SITE_UPLOAD] $endpoint: $e');
      return ApiResponse.error(
        message: 'Erro de conexão ao enviar o arquivo: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}
