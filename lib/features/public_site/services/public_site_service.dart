import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../models/public_site_config_model.dart';

/// Serviço do **Meu Site** — consome `/public-site-config` (paridade com
/// `publicSiteConfigApi` do imobx-front). Endpoints como constantes privadas;
/// leitura exige `public_site:view`, escrita `public_site:manage` (o backend
/// aplica ambos + módulo `public_site_hosting`).
class PublicSiteService {
  PublicSiteService._();

  static final PublicSiteService instance = PublicSiteService._();
  final ApiService _api = ApiService.instance;

  // Endpoints (privados — a fiação central pode promovê-los a ApiConstants).
  static const String _base = '/public-site-config';
  static const String _customDomain = '$_base/custom-domain';
  static const String _verifyDns = '$_base/custom-domain/verify-dns';
  static const String _publish = '$_base/publish';
  static const String _unpublish = '$_base/unpublish';
  static const String _templates = '$_base/templates';
  static const String _dnsInstructions = '$_base/dns-instructions';

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

  ApiResponse<PublicSiteConfig> _configResponse(ApiResponse<dynamic> response,
      {required String fallbackError}) {
    if (response.success && response.data != null) {
      final body = _unwrap(response.data);
      if (body != null) {
        return ApiResponse.success(
          data: PublicSiteConfig.fromJson(body),
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

  /// `GET /public-site-config` — configuração do site da empresa atual
  /// (o backend cria na primeira leitura).
  Future<ApiResponse<PublicSiteConfig>> getConfig() async {
    try {
      final response = await _api.get<dynamic>(_base);
      return _configResponse(response,
          fallbackError: 'Erro ao carregar configuração do site');
    } catch (e) {
      debugPrint('❌ [PUBLIC_SITE] getConfig: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `PATCH /public-site-config` — atualiza template, branding, conteúdo,
  /// SEO e blocos da home. Envie SÓ as chaves alteradas (patch parcial).
  Future<ApiResponse<PublicSiteConfig>> updateConfig(
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _api.patch<dynamic>(_base, body: payload);
      return _configResponse(response, fallbackError: 'Erro ao salvar');
    } catch (e) {
      debugPrint('❌ [PUBLIC_SITE] updateConfig: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `PATCH /public-site-config/custom-domain` — salva o domínio próprio e
  /// dispara o registro do hostname (ativação automática quando o CNAME
  /// propagar).
  Future<ApiResponse<PublicSiteConfig>> updateCustomDomain(
    String customDomain,
  ) async {
    try {
      final response = await _api.patch<dynamic>(
        _customDomain,
        body: {'customDomain': customDomain},
      );
      return _configResponse(response,
          fallbackError: 'Erro ao salvar domínio');
    } catch (e) {
      debugPrint('❌ [PUBLIC_SITE] updateCustomDomain: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /public-site-config/custom-domain/verify-dns` — verifica a
  /// propagação do CNAME e ativa o domínio quando resolvido.
  Future<ApiResponse<VerifyCustomDomainDnsResult>> verifyCustomDomainDns()
      async {
    try {
      final response = await _api.post<dynamic>(_verifyDns);
      if (response.success && response.data != null) {
        final body = _unwrap(response.data);
        if (body != null) {
          return ApiResponse.success(
            data: VerifyCustomDomainDnsResult.fromJson(body),
            statusCode: response.statusCode,
          );
        }
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao verificar DNS',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PUBLIC_SITE] verifyCustomDomainDns: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /public-site-config/publish` — coloca o site no ar.
  Future<ApiResponse<PublicSiteConfig>> publish() async {
    try {
      final response = await _api.post<dynamic>(_publish);
      return _configResponse(response,
          fallbackError: 'Erro ao publicar o site');
    } catch (e) {
      debugPrint('❌ [PUBLIC_SITE] publish: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /public-site-config/unpublish` — tira o site do ar.
  Future<ApiResponse<PublicSiteConfig>> unpublish() async {
    try {
      final response = await _api.post<dynamic>(_unpublish);
      return _configResponse(response,
          fallbackError: 'Erro ao despublicar o site');
    } catch (e) {
      debugPrint('❌ [PUBLIC_SITE] unpublish: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /public-site-config/templates` — templates disponíveis (o backend
  /// marca Premium bloqueado/desbloqueado por empresa).
  Future<ApiResponse<List<PublicSiteTemplateInfo>>> getTemplates() async {
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
                .map((e) => PublicSiteTemplateInfo.fromJson(
                    Map<String, dynamic>.from(e)))
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
      debugPrint('❌ [PUBLIC_SITE] getTemplates: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /public-site-config/dns-instructions` — instruções de CNAME.
  /// Nunca falha: payload parcial/erro cai nos defaults (paridade com a
  /// normalização do web).
  Future<PublicSiteDnsInstructions> getDnsInstructions() async {
    try {
      final response = await _api.get<dynamic>(_dnsInstructions);
      if (response.success && response.data != null) {
        return PublicSiteDnsInstructions.fromJson(_unwrap(response.data));
      }
    } catch (e) {
      debugPrint('❌ [PUBLIC_SITE] getDnsInstructions: $e');
    }
    return PublicSiteDnsInstructions.fromJson(null);
  }
}
