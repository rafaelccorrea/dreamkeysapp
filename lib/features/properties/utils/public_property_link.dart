import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../shared/services/api_service.dart';
import '../../../shared/services/property_service.dart';
import '../../../shared/services/secure_storage_service.dart';
import '../../../shared/utils/broker_message_templates.dart';

/// Resolve a base pública do site da empresa e monta o link compartilhável
/// do imóvel — paridade com `publicPropertySiteUrl.ts` do imobx-front
/// (`{base}/imovel/{código || id}`).
///
/// A base vem de `GET /public-site-config` (`publicUrl || subdomainUrl`).
/// Esse endpoint exige `public_site:view` — corretor comum recebe 403. Pra
/// não deixar a equipe sem o link, a empresa legada União cai no mesmo
/// fallback hardcoded do web (imobiliariauniao.com.br).
class PublicPropertyLink {
  PublicPropertyLink._();

  /// Empresa legada com site em imobiliariauniao.com.br (mesmo ID do web).
  static const String uniaoCompanyId = '13b0ff9c-10e4-4abc-9fd8-313ecc1d132c';
  static const String _uniaoSiteUrl = 'https://www.imobiliariauniao.com.br';

  static String? _cachedBase;
  static String? _cachedForCompanyId;
  static bool _cacheResolved = false;

  /// Base do site sem barra final, ou `null` quando a empresa não tem site.
  /// Cacheada por empresa durante a sessão (troca de empresa refaz a busca).
  static Future<String?> resolveBaseUrl() async {
    String? companyId;
    try {
      companyId = await SecureStorageService.instance.getCompanyId();
    } catch (_) {}

    if (_cacheResolved && _cachedForCompanyId == companyId) {
      return _cachedBase;
    }

    String? base;
    try {
      final res = await ApiService.instance
          .get<Map<String, dynamic>>('/public-site-config');
      if (res.success && res.data != null) {
        final data = res.data!;
        final pub = (data['publicUrl'] as String?)?.trim();
        final sub = (data['subdomainUrl'] as String?)?.trim();
        base = (pub != null && pub.isNotEmpty)
            ? pub
            : ((sub != null && sub.isNotEmpty) ? sub : null);
      }
    } catch (e) {
      debugPrint('⚠️ [PUBLIC_LINK] /public-site-config: $e');
    }

    if ((base == null || base.isEmpty) && companyId == uniaoCompanyId) {
      base = _uniaoSiteUrl;
    }

    _cachedBase = (base == null || base.isEmpty)
        ? null
        : base.replaceAll(RegExp(r'/+$'), '');
    _cachedForCompanyId = companyId;
    _cacheResolved = true;
    return _cachedBase;
  }

  /// URL pública completa do imóvel (`https://site/imovel/31020`) ou `null`
  /// sem base. Prefere o código; cai pro id (paridade com o web).
  static String? buildUrl(Property property, String? baseUrl) {
    final base = baseUrl?.trim();
    if (base == null || base.isEmpty) return null;
    final code = property.code?.trim();
    final identifier =
        (code != null && code.isNotEmpty) ? code : property.id.trim();
    if (identifier.isEmpty) return null;
    return '$base/imovel/${Uri.encodeComponent(identifier)}';
  }

  /// Conveniência: resolve a base e monta a URL numa chamada só.
  static Future<String?> resolveUrl(Property property) async {
    return buildUrl(property, await resolveBaseUrl());
  }

  /// Linha de preço pra mensagem ("R\$ 850.000" / "R\$ 2.400/mês") ou null.
  static String? priceLine(Property property) {
    String fmt(double v) => NumberFormat.currency(
          locale: 'pt_BR',
          symbol: 'R\$',
          decimalDigits: v % 1 == 0 ? 0 : 2,
        ).format(v);
    final sale = property.salePrice;
    if (sale != null && sale > 0) return fmt(sale);
    final rent = property.rentPrice;
    if (rent != null && rent > 0) return '${fmt(rent)}/mês';
    return null;
  }

  /// Mensagem pronta de divulgação (título, código, endereço, preço + link).
  /// Ponto único — sheet, rodapé do detalhe e listagem enviam o MESMO texto.
  static String shareMessage(Property property, String? url) {
    final base = BrokerMessageTemplates.propertyShare(
      propertyTitle: property.title,
      address: [property.address, property.city]
          .where((s) => s.trim().isNotEmpty)
          .join(', '),
      code: property.code,
      priceLine: priceLine(property),
    );
    return url == null || url.isEmpty ? base : '$base\n$url';
  }
}
