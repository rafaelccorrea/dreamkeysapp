import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../models/bio_page_model.dart';

/// Serviço do **Link in Bio** — consome `/bio-page` (paridade com
/// `bioPageApi` do imobx-front). Leitura exige `public_site:view`; escrita
/// `public_site:manage` (aplicados pelo backend).
class BioPageService {
  BioPageService._();

  static final BioPageService instance = BioPageService._();
  final ApiService _api = ApiService.instance;

  // Endpoints (privados — a fiação central pode promovê-los a ApiConstants).
  static const String _base = '/bio-page';
  static const String _slug = '$_base/slug';
  static const String _slugCheck = '$_base/slug/check';
  static const String _templates = '$_base/templates';
  static const String _publish = '$_base/publish';
  static const String _unpublish = '$_base/unpublish';
  static const String _analytics = '$_base/analytics';

  Map<String, dynamic>? _unwrap(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      final inner = raw['data'];
      if (inner is Map<String, dynamic>) return inner;
      if (inner is Map) return Map<String, dynamic>.from(inner);
      return raw;
    }
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  ApiResponse<BioPageConfig> _pageResponse(ApiResponse<dynamic> response,
      {required String fallbackError}) {
    if (response.success && response.data != null) {
      final body = _unwrap(response.data);
      if (body != null) {
        return ApiResponse.success(
          data: BioPageConfig.fromJson(body),
          statusCode: response.statusCode,
        );
      }
    }
    return ApiResponse.error(
      message: response.message ?? fallbackError,
      statusCode: response.statusCode,
      data: response.error,
    );
  }

  /// `GET /bio-page` — página da empresa (criada na primeira leitura).
  Future<ApiResponse<BioPageConfig>> getPage() async {
    try {
      final response = await _api.get<dynamic>(_base);
      return _pageResponse(response,
          fallbackError: 'Erro ao carregar a página Link in Bio');
    } catch (e) {
      debugPrint('❌ [BIO_PAGE] getPage: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `PATCH /bio-page` — atualiza perfil, links, template e customização.
  /// Envie SÓ as chaves alteradas (patch parcial).
  Future<ApiResponse<BioPageConfig>> update(
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _api.patch<dynamic>(_base, body: payload);
      return _pageResponse(response, fallbackError: 'Erro ao salvar');
    } catch (e) {
      debugPrint('❌ [BIO_PAGE] update: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `PATCH /bio-page/slug` — define a URL pública
  /// (`bio.intellisysbr.com/{slug}`). 409 = slug em uso por outra empresa.
  Future<ApiResponse<BioPageConfig>> updateSlug(String slug) async {
    try {
      final response = await _api.patch<dynamic>(_slug, body: {'slug': slug});
      if (!response.success && response.statusCode == 409) {
        return ApiResponse.error(
          message: 'Este slug já está em uso por outra empresa',
          statusCode: response.statusCode,
          data: response.error,
        );
      }
      return _pageResponse(response,
          fallbackError: 'Slug inválido ou reservado');
    } catch (e) {
      debugPrint('❌ [BIO_PAGE] updateSlug: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /bio-page/slug/check?slug=` — disponibilidade do slug.
  Future<ApiResponse<bool>> checkSlug(String slug) async {
    try {
      final response = await _api.get<dynamic>(
        _slugCheck,
        queryParameters: {'slug': slug},
      );
      if (response.success && response.data != null) {
        final body = _unwrap(response.data);
        if (body != null && body.containsKey('available')) {
          return ApiResponse.success(
            data: body['available'] == true,
            statusCode: response.statusCode,
          );
        }
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao verificar slug',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [BIO_PAGE] checkSlug: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /bio-page/templates` — templates com estado Premium por empresa.
  Future<ApiResponse<List<BioPageTemplateInfo>>> getTemplates() async {
    try {
      final response = await _api.get<dynamic>(_templates);
      if (response.success && response.data != null) {
        final raw = response.data;
        final list = raw is List
            ? raw
            : (raw is Map && raw['data'] is List ? raw['data'] as List : null);
        if (list != null) {
          return ApiResponse.success(
            data: list
                .whereType<Map>()
                .map((e) =>
                    BioPageTemplateInfo.fromJson(Map<String, dynamic>.from(e)))
                .toList(),
            statusCode: response.statusCode,
          );
        }
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar templates',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [BIO_PAGE] getTemplates: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /bio-page/publish` — coloca a página no ar.
  Future<ApiResponse<BioPageConfig>> publish() async {
    try {
      final response = await _api.post<dynamic>(_publish);
      return _pageResponse(response,
          fallbackError: 'Erro ao publicar a página');
    } catch (e) {
      debugPrint('❌ [BIO_PAGE] publish: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /bio-page/unpublish` — tira a página do ar.
  Future<ApiResponse<BioPageConfig>> unpublish() async {
    try {
      final response = await _api.post<dynamic>(_unpublish);
      return _pageResponse(response,
          fallbackError: 'Erro ao despublicar a página');
    } catch (e) {
      debugPrint('❌ [BIO_PAGE] unpublish: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /bio-page/analytics?days=` — visualizações, cliques e CTR.
  Future<ApiResponse<BioPageAnalytics>> getAnalytics({int days = 30}) async {
    try {
      final response = await _api.get<dynamic>(
        _analytics,
        queryParameters: {'days': '$days'},
      );
      if (response.success && response.data != null) {
        final body = _unwrap(response.data);
        if (body != null) {
          return ApiResponse.success(
            data: BioPageAnalytics.fromJson(body),
            statusCode: response.statusCode,
          );
        }
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar analytics',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [BIO_PAGE] getAnalytics: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}
