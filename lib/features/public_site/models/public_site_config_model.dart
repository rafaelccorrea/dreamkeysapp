import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

// ─── Helpers defensivos (null/string/number tolerantes) ──────────────────────

String? _asString(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  return v.toString();
}

bool _asBool(dynamic v, {bool fallback = false}) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.toLowerCase().trim();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
  }
  return fallback;
}

int _asInt(dynamic v, {int fallback = 0}) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? fallback;
  return fallback;
}

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) {
    return double.tryParse(v.replaceAll(',', '.').trim());
  }
  return null;
}

DateTime? _asDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String && v.trim().isNotEmpty) return DateTime.tryParse(v.trim());
  return null;
}

Map<String, dynamic> _asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return const {};
}

// ─── Status do domínio ───────────────────────────────────────────────────────

/// Paridade com `PublicSiteDomainStatus` do `publicSiteConfigApi.ts`.
enum PublicSiteDomainStatus {
  pendingDns('pending_dns', 'Aguardando DNS'),
  pendingReview('pending_review', 'Revisão manual'),
  active('active', 'Ativo'),
  disabled('disabled', 'Desativado');

  const PublicSiteDomainStatus(this.value, this.label);
  final String value;
  final String label;

  static PublicSiteDomainStatus fromValue(dynamic raw) {
    final s = _asString(raw)?.toLowerCase().trim();
    for (final st in PublicSiteDomainStatus.values) {
      if (st.value == s) return st;
    }
    return PublicSiteDomainStatus.pendingDns;
  }
}

// ─── Branding / Conteúdo / SEO ───────────────────────────────────────────────

class PublicSiteBranding {
  final String? primaryColor;
  final String? secondaryColor;
  final String? accentColor;
  final String? logoUrl;
  final String? faviconUrl;

  const PublicSiteBranding({
    this.primaryColor,
    this.secondaryColor,
    this.accentColor,
    this.logoUrl,
    this.faviconUrl,
  });

  factory PublicSiteBranding.fromJson(Map<String, dynamic> json) {
    return PublicSiteBranding(
      primaryColor: _asString(json['primaryColor']),
      secondaryColor: _asString(json['secondaryColor']),
      accentColor: _asString(json['accentColor']),
      logoUrl: _asString(json['logoUrl']),
      faviconUrl: _asString(json['faviconUrl']),
    );
  }

  Map<String, dynamic> toJson() => {
        if (primaryColor != null) 'primaryColor': primaryColor,
        if (secondaryColor != null) 'secondaryColor': secondaryColor,
        if (accentColor != null) 'accentColor': accentColor,
        if (logoUrl != null) 'logoUrl': logoUrl,
        if (faviconUrl != null) 'faviconUrl': faviconUrl,
      };
}

class PublicSiteSocialLinks {
  final String? instagram;
  final String? facebook;
  final String? youtube;
  final String? linkedin;
  final String? tiktok;

  const PublicSiteSocialLinks({
    this.instagram,
    this.facebook,
    this.youtube,
    this.linkedin,
    this.tiktok,
  });

  factory PublicSiteSocialLinks.fromJson(Map<String, dynamic> json) {
    return PublicSiteSocialLinks(
      instagram: _asString(json['instagram']),
      facebook: _asString(json['facebook']),
      youtube: _asString(json['youtube']),
      linkedin: _asString(json['linkedin']),
      tiktok: _asString(json['tiktok']),
    );
  }

  Map<String, dynamic> toJson() => {
        if (instagram != null) 'instagram': instagram,
        if (facebook != null) 'facebook': facebook,
        if (youtube != null) 'youtube': youtube,
        if (linkedin != null) 'linkedin': linkedin,
        if (tiktok != null) 'tiktok': tiktok,
      };
}

class PublicSiteContent {
  final String? tagline;
  final String? aboutText;
  final String? whatsapp;
  final String? phone;
  final String? email;
  final PublicSiteSocialLinks socialLinks;
  final String? ctaText;

  const PublicSiteContent({
    this.tagline,
    this.aboutText,
    this.whatsapp,
    this.phone,
    this.email,
    this.socialLinks = const PublicSiteSocialLinks(),
    this.ctaText,
  });

  factory PublicSiteContent.fromJson(Map<String, dynamic> json) {
    return PublicSiteContent(
      tagline: _asString(json['tagline']),
      aboutText: _asString(json['aboutText']),
      whatsapp: _asString(json['whatsapp']),
      phone: _asString(json['phone']),
      email: _asString(json['email']),
      socialLinks: PublicSiteSocialLinks.fromJson(_asMap(json['socialLinks'])),
      ctaText: _asString(json['ctaText']),
    );
  }

  Map<String, dynamic> toJson() => {
        if (tagline != null) 'tagline': tagline,
        if (aboutText != null) 'aboutText': aboutText,
        if (whatsapp != null) 'whatsapp': whatsapp,
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
        'socialLinks': socialLinks.toJson(),
        if (ctaText != null) 'ctaText': ctaText,
      };

  PublicSiteContent copyWith({
    String? tagline,
    String? aboutText,
    String? whatsapp,
    String? phone,
    String? email,
    String? ctaText,
  }) {
    return PublicSiteContent(
      tagline: tagline ?? this.tagline,
      aboutText: aboutText ?? this.aboutText,
      whatsapp: whatsapp ?? this.whatsapp,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      socialLinks: socialLinks,
      ctaText: ctaText ?? this.ctaText,
    );
  }
}

class PublicSiteSeo {
  final String? title;
  final String? description;
  final String? gaMeasurementId;

  const PublicSiteSeo({this.title, this.description, this.gaMeasurementId});

  factory PublicSiteSeo.fromJson(Map<String, dynamic> json) {
    return PublicSiteSeo(
      title: _asString(json['title']),
      description: _asString(json['description']),
      gaMeasurementId: _asString(json['gaMeasurementId']),
    );
  }

  Map<String, dynamic> toJson() => {
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (gaMeasurementId != null) 'gaMeasurementId': gaMeasurementId,
      };

  PublicSiteSeo copyWith({String? title, String? description}) {
    return PublicSiteSeo(
      title: title ?? this.title,
      description: description ?? this.description,
      gaMeasurementId: gaMeasurementId,
    );
  }
}

// ─── Blocos da home ──────────────────────────────────────────────────────────

class PublicSiteHomeBlock {
  final String id;
  final String type;
  final bool enabled;
  final Map<String, dynamic> settings;

  const PublicSiteHomeBlock({
    required this.id,
    required this.type,
    required this.enabled,
    this.settings = const {},
  });

  factory PublicSiteHomeBlock.fromJson(Map<String, dynamic> json) {
    return PublicSiteHomeBlock(
      id: _asString(json['id']) ?? '',
      type: _asString(json['type']) ?? 'hero',
      enabled: _asBool(json['enabled'], fallback: true),
      settings: _asMap(json['settings']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'enabled': enabled,
        if (settings.isNotEmpty) 'settings': settings,
      };

  PublicSiteHomeBlock copyWith({bool? enabled}) {
    return PublicSiteHomeBlock(
      id: id,
      type: type,
      enabled: enabled ?? this.enabled,
      settings: settings,
    );
  }
}

/// Catálogo de blocos (labels pt-BR) — paridade com
/// `PUBLIC_SITE_BLOCK_CATALOG` do `publicSiteBlocks.ts`.
class PublicSiteBlockCatalog {
  PublicSiteBlockCatalog._();

  static const Map<String, ({String label, String description})> _catalog = {
    'hero': (
      label: 'Banner principal',
      description: 'Título, imagem de capa e chamada para ação',
    ),
    'search': (
      label: 'Busca de imóveis',
      description: 'Filtros por cidade, estado e operação',
    ),
    'featured_carousel': (
      label: 'Carrossel de destaques',
      description: 'Imóveis em slide automático',
    ),
    'featured_cards': (
      label: 'Cards de destaque',
      description: 'Grade visual com imóveis selecionados',
    ),
    'categories': (
      label: 'Categorias',
      description: 'Atalhos por tipo de imóvel',
    ),
    'property_grid': (
      label: 'Listagem de imóveis',
      description: 'Catálogo completo em cards',
    ),
    'services': (
      label: 'Serviços',
      description: 'O que sua imobiliária oferece',
    ),
    'process': (
      label: 'Como funciona',
      description: 'Passo a passo do atendimento',
    ),
    'about': (
      label: 'Sobre nós',
      description: 'Texto institucional da empresa',
    ),
    'testimonials': (
      label: 'Depoimentos',
      description: 'Prova social de clientes',
    ),
    'stats': (
      label: 'Números',
      description: 'Estatísticas e resultados',
    ),
    'trust': (
      label: 'Selos de confiança',
      description: 'Credibilidade e parcerias',
    ),
    'cta': (
      label: 'Chamada final',
      description: 'Botão de contato / WhatsApp',
    ),
  };

  static String labelOf(String type) => _catalog[type]?.label ?? type;

  static String descriptionOf(String type) =>
      _catalog[type]?.description ?? '';

  static IconData iconOf(String type) {
    switch (type) {
      case 'hero':
        return LucideIcons.image;
      case 'search':
        return LucideIcons.search;
      case 'featured_carousel':
        return LucideIcons.galleryHorizontalEnd;
      case 'featured_cards':
        return LucideIcons.layoutGrid;
      case 'categories':
        return LucideIcons.shapes;
      case 'property_grid':
        return LucideIcons.grid3x3;
      case 'services':
        return LucideIcons.briefcase;
      case 'process':
        return LucideIcons.listOrdered;
      case 'about':
        return LucideIcons.building2;
      case 'testimonials':
        return LucideIcons.quote;
      case 'stats':
        return LucideIcons.chartBar;
      case 'trust':
        return LucideIcons.shieldCheck;
      case 'cta':
        return LucideIcons.megaphone;
      default:
        return LucideIcons.square;
    }
  }

  /// Preset por template — paridade com `getDefaultHomeBlocks` do web,
  /// usada quando `homeBlocks` vem vazio do backend.
  static List<PublicSiteHomeBlock> defaultsFor(String templateId) {
    const presets = <String, List<String>>{
      'modern': [
        'hero', 'categories', 'featured_cards', 'property_grid',
        'process', 'testimonials', 'about', 'cta',
      ],
      'classic': [
        'hero', 'featured_cards', 'categories', 'property_grid',
        'services', 'process', 'about', 'cta',
      ],
      'corporate': [
        'hero', 'services', 'featured_cards', 'categories',
        'property_grid', 'process', 'testimonials', 'cta',
      ],
      'luxury': [
        'hero', 'about', 'featured_carousel', 'property_grid',
        'process', 'cta',
      ],
      'compact': ['hero', 'property_grid', 'cta'],
      'premium': [
        'hero', 'stats', 'featured_carousel', 'featured_cards',
        'property_grid', 'about', 'testimonials', 'trust', 'cta',
      ],
    };
    final types = presets[templateId] ?? presets['modern']!;
    return [
      for (var i = 0; i < types.length; i++)
        PublicSiteHomeBlock(
          id: '${types[i]}-${i + 1}',
          type: types[i],
          enabled: true,
        ),
    ];
  }
}

// ─── Configuração do site ────────────────────────────────────────────────────

/// Paridade com `PublicSiteConfig` do `publicSiteConfigApi.ts`.
class PublicSiteConfig {
  final String id;
  final String companyId;
  final String? customDomain;
  final PublicSiteDomainStatus domainStatus;
  final String templateId;
  final PublicSiteBranding branding;
  final PublicSiteContent content;
  final PublicSiteSeo seo;
  final List<PublicSiteHomeBlock> homeBlocks;
  final bool isPublished;
  final DateTime? publishedAt;
  final String? subdomainUrl;
  final String? publicUrl;
  final bool premiumTemplateUnlocked;
  final DateTime? updatedAt;

  const PublicSiteConfig({
    required this.id,
    required this.companyId,
    this.customDomain,
    required this.domainStatus,
    required this.templateId,
    required this.branding,
    required this.content,
    required this.seo,
    this.homeBlocks = const [],
    required this.isPublished,
    this.publishedAt,
    this.subdomainUrl,
    this.publicUrl,
    this.premiumTemplateUnlocked = false,
    this.updatedAt,
  });

  factory PublicSiteConfig.fromJson(Map<String, dynamic> json) {
    final rawBlocks = json['homeBlocks'];
    return PublicSiteConfig(
      id: _asString(json['id']) ?? '',
      companyId: _asString(json['companyId']) ?? '',
      customDomain: _asString(json['customDomain']),
      domainStatus: PublicSiteDomainStatus.fromValue(json['domainStatus']),
      templateId: _asString(json['templateId']) ?? 'modern',
      branding: PublicSiteBranding.fromJson(_asMap(json['branding'])),
      content: PublicSiteContent.fromJson(_asMap(json['content'])),
      seo: PublicSiteSeo.fromJson(_asMap(json['seo'])),
      homeBlocks: rawBlocks is List
          ? rawBlocks
              .whereType<Map>()
              .map((e) =>
                  PublicSiteHomeBlock.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      isPublished: _asBool(json['isPublished']),
      publishedAt: _asDate(json['publishedAt']),
      subdomainUrl: _asString(json['subdomainUrl']),
      publicUrl: _asString(json['publicUrl']),
      premiumTemplateUnlocked: _asBool(json['premiumTemplateUnlocked']),
      updatedAt: _asDate(json['updatedAt']),
    );
  }

  /// URL "melhor esforço" do site — `publicUrl` do backend ou o domínio salvo.
  String? get bestPublicUrl {
    final direct = publicUrl?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final domain = customDomain?.trim();
    if (domain != null && domain.isNotEmpty) return 'https://$domain';
    return null;
  }

  /// Blocos para edição — defaults do template quando o backend devolve vazio
  /// (paridade com `resolveEditorHomeBlocks`).
  List<PublicSiteHomeBlock> get editorHomeBlocks =>
      homeBlocks.isNotEmpty
          ? homeBlocks
          : PublicSiteBlockCatalog.defaultsFor(templateId);
}

// ─── Templates ───────────────────────────────────────────────────────────────

class PublicSiteTemplateInfo {
  final String id;
  final String name;
  final String description;
  final bool isPremium;
  final double? monthlyPrice;
  final bool isUnlocked;

  const PublicSiteTemplateInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.isPremium,
    this.monthlyPrice,
    required this.isUnlocked,
  });

  factory PublicSiteTemplateInfo.fromJson(Map<String, dynamic> json) {
    final id = _asString(json['id']) ?? '';
    final isPremium = json['isPremium'] != null
        ? _asBool(json['isPremium'])
        : id == 'premium';
    return PublicSiteTemplateInfo(
      id: id,
      name: _asString(json['name']) ?? id,
      description: _asString(json['description']) ?? '',
      isPremium: isPremium,
      monthlyPrice: _asDouble(json['monthlyPrice']),
      isUnlocked: json['isUnlocked'] != null
          ? _asBool(json['isUnlocked'])
          : !isPremium,
    );
  }
}

// ─── DNS ─────────────────────────────────────────────────────────────────────

class PublicSiteDnsStep {
  final int order;
  final String title;
  final String description;
  final String? recordType;
  final String? host;
  final String? value;

  const PublicSiteDnsStep({
    required this.order,
    required this.title,
    required this.description,
    this.recordType,
    this.host,
    this.value,
  });

  factory PublicSiteDnsStep.fromJson(Map<String, dynamic> json) {
    return PublicSiteDnsStep(
      order: _asInt(json['order'], fallback: 1),
      title: _asString(json['title']) ?? '',
      description: _asString(json['description']) ?? '',
      recordType: _asString(json['recordType']),
      host: _asString(json['host']),
      value: _asString(json['value']),
    );
  }
}

/// Instruções de DNS — normalização com defaults idêntica à
/// `normalizePublicSiteDnsInstructions` do web (payload parcial tolerado).
class PublicSiteDnsInstructions {
  static const String defaultCnameTarget = 'sites.intellisysbr.com';

  final String cnameTarget;
  final String ttlRecommendation;
  final String propagationNote;
  final List<PublicSiteDnsStep> steps;

  const PublicSiteDnsInstructions({
    required this.cnameTarget,
    required this.ttlRecommendation,
    required this.propagationNote,
    required this.steps,
  });

  factory PublicSiteDnsInstructions.fromJson(Map<String, dynamic>? json) {
    final raw = json ?? const {};
    final target = _asString(raw['cnameTarget'])?.trim();
    final cname =
        (target != null && target.isNotEmpty) ? target : defaultCnameTarget;
    final rawSteps = raw['steps'];
    final steps = rawSteps is List
        ? rawSteps
            .whereType<Map>()
            .map((e) => PublicSiteDnsStep.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <PublicSiteDnsStep>[];
    return PublicSiteDnsInstructions(
      cnameTarget: cname,
      ttlRecommendation: _asString(raw['ttlRecommendation'])?.trim().isNotEmpty ==
              true
          ? raw['ttlRecommendation'].toString().trim()
          : '3600 (1 hora) ou padrão do registrador',
      propagationNote: _asString(raw['propagationNote'])?.trim().isNotEmpty ==
              true
          ? raw['propagationNote'].toString().trim()
          : 'Alterações de DNS podem levar de alguns minutos até 48 horas '
              'para propagar globalmente.',
      steps: steps.isNotEmpty ? steps : _defaultSteps(cname),
    );
  }

  static List<PublicSiteDnsStep> _defaultSteps(String cnameTarget) => [
        const PublicSiteDnsStep(
          order: 1,
          title: 'Escolha o domínio',
          description:
              'Use o domínio que você já possui (ex.: minhaimobiliaria.com.br). '
              'Recomendamos apontar o subdomínio www para o site.',
        ),
        const PublicSiteDnsStep(
          order: 2,
          title: 'Acesse o painel DNS',
          description:
              'Entre no painel do registrador (Registro.br, GoDaddy, Hostinger, '
              'Cloudflare etc.) e abra a zona DNS do domínio.',
        ),
        PublicSiteDnsStep(
          order: 3,
          title: 'Crie o registro CNAME',
          description:
              'Adicione um registro CNAME para o host www apontando para o '
              'destino Intellisys.',
          recordType: 'CNAME',
          host: 'www',
          value: cnameTarget,
        ),
        const PublicSiteDnsStep(
          order: 4,
          title: 'Domínio raiz (opcional)',
          description:
              'Muitos registradores não permitem CNAME na raiz (@). Configure '
              'redirecionamento do domínio raiz para o www no painel do provedor.',
        ),
        const PublicSiteDnsStep(
          order: 5,
          title: 'Verificação automática',
          description:
              'Salve o domínio e toque em "Verificar DNS". Quando o CNAME '
              'propagar, o domínio é ativado automaticamente.',
        ),
      ];
}

// ─── Verificação de DNS ──────────────────────────────────────────────────────

class VerifyCustomDomainDnsResult {
  final bool verified;
  final PublicSiteDomainStatus domainStatus;
  final String message;

  const VerifyCustomDomainDnsResult({
    required this.verified,
    required this.domainStatus,
    required this.message,
  });

  factory VerifyCustomDomainDnsResult.fromJson(Map<String, dynamic> json) {
    return VerifyCustomDomainDnsResult(
      verified: _asBool(json['verified']),
      domainStatus: PublicSiteDomainStatus.fromValue(json['domainStatus']),
      message: _asString(json['message']) ?? '',
    );
  }
}
