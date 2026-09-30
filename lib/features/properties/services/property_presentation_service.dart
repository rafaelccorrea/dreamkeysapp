import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';

/// PDF pronto para enviar ao cliente: bytes + nome sugerido pelo servidor.
class PropertyPresentationPdf {
  const PropertyPresentationPdf({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;
}

/// Apresentação do imóvel em PDF — paridade com
/// `propertyApi.downloadPresentationPdf` do web.
///
/// `GET /properties/:id/presentation-pdf` (property:view): o back monta o
/// PDF com fotos, valores, características, descrição e o contato de quem
/// gerou; não leva dados do proprietário nem o endereço completo. Mesmo
/// teto de espera do web (90 s) e o mesmo nome de reserva.
class PropertyPresentationService {
  PropertyPresentationService._();

  static final PropertyPresentationService instance =
      PropertyPresentationService._();

  final ApiService _api = ApiService.instance;

  static const String fallbackFileName = 'apresentacao-imovel.pdf';
  static const Duration timeout = Duration(seconds: 90);

  static String _endpoint(String propertyId) =>
      '/properties/$propertyId/presentation-pdf';

  /// Gera e baixa o PDF. Nunca lança: a falha volta no [ApiResponse] com o
  /// código HTTP (0 = sem conexão, 408 = passou do teto de espera, -1 =
  /// falha local) e, em `message`, só o que o servidor explicou (vazio
  /// quando não explicou — a tela descreve a causa pela família do código).
  Future<ApiResponse<PropertyPresentationPdf>> download(
    String propertyId,
  ) async {
    final endpoint = _endpoint(propertyId);
    try {
      // GET binário não passa pela renovação automática do ApiService:
      // garante um token com folga antes de pedir (a geração pode levar
      // perto de 1 minuto).
      await _api.garantirTokenFresco(margemSegundos: 120);
      final headers = await _api.buildOutboundHeaders(
        endpoint: endpoint,
        excludeContentType: true,
      );
      headers['Accept'] = 'application/pdf, application/json';

      final res = await http
          .get(Uri.parse('${ApiConstants.baseApiUrl}$endpoint'), headers: headers)
          .timeout(timeout);
      final type = (res.headers['content-type'] ?? '').toLowerCase();
      if (res.statusCode >= 200 &&
          res.statusCode < 300 &&
          !type.contains('application/json') &&
          res.bodyBytes.isNotEmpty) {
        return ApiResponse.success(
          data: PropertyPresentationPdf(
            bytes: res.bodyBytes,
            fileName: fileNameFromDisposition(
              res.headers['content-disposition'],
            ),
          ),
          statusCode: res.statusCode,
        );
      }
      // 2xx sem PDF (corpo vazio ou JSON) conta como falha do servidor.
      return ApiResponse.error(
        message: _serverMessage(res) ?? '',
        statusCode: res.statusCode >= 200 && res.statusCode < 300
            ? 500
            : res.statusCode,
      );
    } on TimeoutException {
      return ApiResponse.error(message: '', statusCode: 408);
    } on SocketException catch (e) {
      debugPrint('[PROPERTY_PRESENTATION] sem conexão: $e');
      return ApiResponse.error(message: '', statusCode: 0);
    } on http.ClientException catch (e) {
      debugPrint('[PROPERTY_PRESENTATION] conexão: $e');
      return ApiResponse.error(message: '', statusCode: 0);
    } catch (e) {
      debugPrint('[PROPERTY_PRESENTATION] download: $e');
      return ApiResponse.error(message: '', statusCode: -1, data: e);
    }
  }

  /// Nome do `Content-Disposition` com a mesma regex do web
  /// (`filename\*?=(?:UTF-8''|")?([^";]+)`); sem nome, o de reserva.
  static String fileNameFromDisposition(String? disposition) {
    final raw = disposition ?? '';
    final match = RegExp(
      'filename\\*?=(?:UTF-8\'\'|")?([^";]+)',
      caseSensitive: false,
    ).firstMatch(raw);
    var name = match?.group(1)?.trim() ?? '';
    if (name.isEmpty) return fallbackFileName;
    try {
      name = Uri.decodeComponent(name);
    } catch (_) {}
    return name.toLowerCase().endsWith('.pdf') ? name : '$name.pdf';
  }

  /// `message` do corpo JSON do Nest, quando houver.
  static String? _serverMessage(http.Response res) {
    try {
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is Map) {
        final m = body['message'];
        if (m is String && m.trim().isNotEmpty) return m.trim();
        if (m is List && m.isNotEmpty) return m.first.toString();
      }
    } catch (_) {}
    return null;
  }
}
