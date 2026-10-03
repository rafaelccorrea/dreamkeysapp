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
///
/// 29/09/2026 (integ-28, parcial): `pending_ssl` e `failed` não existiam
/// aqui e o `fromValue` caía em "Aguardando DNS" — quem já tinha o DNS certo
/// via a mensagem errada. O rótulo e a cor já saem certos; o texto por
/// situação e o motivo da recusa (`domainRejectionReason`) ficam no P1.
enum PublicSiteDomainStatus {
  pendingDns('pending_dns', 'Aguardando DNS'),

  /// DNS ok; o certificado HTTPS está sendo emitido (normal, 1 a 5 min).
  pendingSsl('pending_ssl', 'Emitindo HTTPS'),
  pendingReview('pending_review', 'Revisão manual'),
  active('active', 'Ativo'),

  /// DNS ok, mas o HTTPS não fechou no prazo (o back guarda o motivo).
  failed('failed', 'Falhou'),
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

/// String vazia vira `null` — 29/09/2026 (integ-03). O back faz merge raso
/// (`{...config.content, ...dto.content}`) e valida com `@IsOptional`, que só
/// pula null/undefined: mandar `''` num campo `@IsEmail` devolvia 400 e
/// travava o save inteiro de "Textos e contato" para quem não tem e-mail.
/// `null` explícito passa na validação E limpa o valor salvo.
String? _nullIfBlank(String? v) {
  final t = v?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

/// Sentinela do `copyWith` para distinguir "não mexer" de "limpar (null)".
const Object _keep = Object();

/// Limites do vídeo/foto de capa — espelham o back
/// (`PUBLIC_SITE_HERO_*` em shared/constants/public-site.constant).
const int kPublicSiteHeroVideoMaxSeconds = 10;
const int kPublicSiteHeroVideoMaxBytes = 25 * 1024 * 1024;
const int kPublicSiteHeroImageMaxBytes = 10 * 1024 * 1024;

/// Preço do template Premium do site — paridade com
/// `PUBLIC_SITE_PREMIUM_TEMPLATE_PRICE`.
const double kPublicSitePremiumTemplatePrice = 89.9;

/// Máximo de conquistas (selos) — paridade com `MAX_TRUST_SEALS` do web.
const int kPublicSiteMaxTrustSeals = 6;

/// Templates que desenham o botão flutuante de WhatsApp (mesma lista do
/// storefront / `FLOATING_WHATSAPP_TEMPLATES`).
const Set<String> kFloatingWhatsappTemplates = {'premium', 'luxury'};

/// Paleta de fábrica por template — sugestão e "voltar ao de fábrica" no
/// estúdio de cor (paridade com `TEMPLATE_FACTORY_PAINTS`).
const Map<String, ({String primary, String secondary, String accent})>
    kPublicSiteFactoryPaints = {
  'classic': (primary: '#A63126', secondary: '#592722', accent: '#4A90E2'),
  'modern': (primary: '#2563EB', secondary: '#0F172A', accent: '#38BDF8'),
  'corporate': (primary: '#1E3A5F', secondary: '#0F172A', accent: '#94A3B8'),
  'compact': (primary: '#0D9488', secondary: '#134E4A', accent: '#2DD4BF'),
  'luxury': (primary: '#B08D57', secondary: '#12141A', accent: '#D6BC94'),
  'premium': (primary: '#C9A962', secondary: '#1A1816', accent: '#E8D5A3'),
};

class PublicSiteBranding {
  final String? primaryColor;
  final String? secondaryColor;
  final String? accentColor;
  final String? logoUrl;
  final String? faviconUrl;

  /// Foto de capa do banner (qualquer template). Nunca convive com o vídeo.
  final String? heroImageUrl;

  /// Vídeo de capa (só o template Premium reproduz).
  final String? heroVideoUrl;
  final int? heroVideoDurationSeconds;

  /// Marca d'água do banner (Premium): a logo grande e translúcida.
  final bool? heroLogoWatermark;

  const PublicSiteBranding({
    this.primaryColor,
    this.secondaryColor,
    this.accentColor,
    this.logoUrl,
    this.faviconUrl,
    this.heroImageUrl,
    this.heroVideoUrl,
    this.heroVideoDurationSeconds,
    this.heroLogoWatermark,
  });

  factory PublicSiteBranding.fromJson(Map<String, dynamic> json) {
    return PublicSiteBranding(
      primaryColor: _asString(json['primaryColor']),
      secondaryColor: _asString(json['secondaryColor']),
      accentColor: _asString(json['accentColor']),
      logoUrl: _asString(json['logoUrl']),
      faviconUrl: _asString(json['faviconUrl']),
      heroImageUrl: _asString(json['heroImageUrl']),
      heroVideoUrl: _asString(json['heroVideoUrl']),
      heroVideoDurationSeconds: json['heroVideoDurationSeconds'] == null
          ? null
          : _asInt(json['heroVideoDurationSeconds']),
      heroLogoWatermark: json['heroLogoWatermark'] == null
          ? null
          : _asBool(json['heroLogoWatermark']),
    );
  }

  /// Payload do futuro "Salvar marca" (integ-23, P1 — o app ainda não tem
  /// essa tela nem chama este método). A capa (foto/vídeo) NÃO vai aqui: ela
  /// é gravada pelo `POST/DELETE /public-site-config/hero-media`, e reenviar
  /// a URL no PATCH dispararia a regra de exclusividade foto x vídeo do back.
  Map<String, dynamic> toJson() => {
        'primaryColor': _nullIfBlank(primaryColor),
        'secondaryColor': _nullIfBlank(secondaryColor),
        'accentColor': _nullIfBlank(accentColor),
        'logoUrl': _nullIfBlank(logoUrl),
        'faviconUrl': _nullIfBlank(faviconUrl),
        if (heroLogoWatermark != null) 'heroLogoWatermark': heroLogoWatermark,
      };

  bool get hasHeroMedia =>
      (heroImageUrl ?? '').trim().isNotEmpty ||
      (heroVideoUrl ?? '').trim().isNotEmpty;

  PublicSiteBranding copyWith({
    Object? primaryColor = _keep,
    Object? secondaryColor = _keep,
    Object? accentColor = _keep,
    Object? logoUrl = _keep,
    Object? faviconUrl = _keep,
    Object? heroLogoWatermark = _keep,
  }) {
    return PublicSiteBranding(
      primaryColor: identical(primaryColor, _keep)
          ? this.primaryColor
          : primaryColor as String?,
      secondaryColor: identical(secondaryColor, _keep)
          ? this.secondaryColor
          : secondaryColor as String?,
      accentColor: identical(accentColor, _keep)
          ? this.accentColor
          : accentColor as String?,
      logoUrl: identical(logoUrl, _keep) ? this.logoUrl : logoUrl as String?,
      faviconUrl:
          identical(faviconUrl, _keep) ? this.faviconUrl : faviconUrl as String?,
      heroImageUrl: heroImageUrl,
      heroVideoUrl: heroVideoUrl,
      heroVideoDurationSeconds: heroVideoDurationSeconds,
      heroLogoWatermark: identical(heroLogoWatermark, _keep)
          ? this.heroLogoWatermark
          : heroLogoWatermark as bool?,
    );
  }
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
        'instagram': _nullIfBlank(instagram),
        'facebook': _nullIfBlank(facebook),
        'youtube': _nullIfBlank(youtube),
        'linkedin': _nullIfBlank(linkedin),
        'tiktok': _nullIfBlank(tiktok),
      };
}

/// Conquista/selo real da imobiliária — paridade com `PublicSiteTrustSeal`.
class PublicSiteTrustSeal {
  final String title;
  final String? desc;

  const PublicSiteTrustSeal({required this.title, this.desc});

  factory PublicSiteTrustSeal.fromJson(Map<String, dynamic> json) {
    return PublicSiteTrustSeal(
      title: _asString(json['title']) ?? '',
      desc: _asString(json['desc']),
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title.trim(),
        if (_nullIfBlank(desc) != null) 'desc': desc!.trim(),
      };
}

/// Botão flutuante de WhatsApp (Premium e Luxo) — paridade com
/// `PublicSiteFloatingWhatsapp`. `enabled` ausente = ligado.
class PublicSiteFloatingWhatsapp {
  final bool? enabled;
  final String? phone;
  final String? message;

  const PublicSiteFloatingWhatsapp({this.enabled, this.phone, this.message});

  factory PublicSiteFloatingWhatsapp.fromJson(Map<String, dynamic> json) {
    return PublicSiteFloatingWhatsapp(
      enabled: json['enabled'] == null ? null : _asBool(json['enabled']),
      phone: _asString(json['phone']),
      message: _asString(json['message']),
    );
  }

  bool get isOn => enabled != false;

  /// Os três campos vão SEMPRE explícitos (como no web): chave ausente no
  /// PATCH = o back mantém o valor antigo, e aí religar não persistiria.
  Map<String, dynamic> toJson() => {
        'enabled': enabled != false,
        'phone': phone?.trim() ?? '',
        'message': message?.trim() ?? '',
      };
}

/// Ajustes do cabeçalho (6 templates) — paridade com `PublicSiteHeaderConfig`.
class PublicSiteHeaderConfig {
  final bool sticky;
  final bool showTopBar;
  final bool showPhone;

  /// `'left'` | `'center'`.
  final String brandAlign;

  /// `'whatsapp'` | `'phone'` | `'none'`.
  final String ctaMode;
  final String ctaText;

  const PublicSiteHeaderConfig({
    this.sticky = true,
    this.showTopBar = true,
    this.showPhone = true,
    this.brandAlign = 'left',
    this.ctaMode = 'whatsapp',
    this.ctaText = '',
  });

  factory PublicSiteHeaderConfig.fromJson(Map<String, dynamic> json) {
    final align = _asString(json['brandAlign']);
    final mode = _asString(json['ctaMode']);
    return PublicSiteHeaderConfig(
      sticky: json['sticky'] != false,
      showTopBar: json['showTopBar'] != false,
      showPhone: json['showPhone'] != false,
      brandAlign: align == 'center' ? 'center' : 'left',
      ctaMode: (mode == 'phone' || mode == 'none') ? mode! : 'whatsapp',
      ctaText: _asString(json['ctaText']) ?? '',
    );
  }

  /// Todos os campos explícitos — paridade com `buildHeaderPayload` do web.
  Map<String, dynamic> toJson() => {
        'sticky': sticky,
        'showTopBar': showTopBar,
        'showPhone': showPhone,
        'brandAlign': brandAlign,
        'ctaMode': ctaMode,
        'ctaText': ctaText.trim(),
      };

  PublicSiteHeaderConfig copyWith({
    bool? sticky,
    bool? showTopBar,
    bool? showPhone,
    String? brandAlign,
    String? ctaMode,
    String? ctaText,
  }) {
    return PublicSiteHeaderConfig(
      sticky: sticky ?? this.sticky,
      showTopBar: showTopBar ?? this.showTopBar,
      showPhone: showPhone ?? this.showPhone,
      brandAlign: brandAlign ?? this.brandAlign,
      ctaMode: ctaMode ?? this.ctaMode,
      ctaText: ctaText ?? this.ctaText,
    );
  }
}

class PublicSiteContent {
  final String? tagline;
  final String? aboutText;
  final String? whatsapp;
  final String? phone;
  final String? email;
  final PublicSiteSocialLinks socialLinks;
  final String? ctaText;

  /// 29/09/2026: campos que o web edita e o app só LÊ por enquanto (a tela
  /// deles é o integ-24, P1). Ficam fora do [toJson] de propósito — ver lá.
  final String? address;
  final String? businessHours;
  final List<PublicSiteTrustSeal> trustSeals;
  final PublicSiteFloatingWhatsapp? floatingWhatsapp;

  /// Cabeçalho do site (tela no integ-26, P1). null = nunca configurado.
  /// Também fica fora do [toJson].
  final PublicSiteHeaderConfig? header;

  const PublicSiteContent({
    this.tagline,
    this.aboutText,
    this.whatsapp,
    this.phone,
    this.email,
    this.socialLinks = const PublicSiteSocialLinks(),
    this.ctaText,
    this.address,
    this.businessHours,
    this.trustSeals = const [],
    this.floatingWhatsapp,
    this.header,
  });

  factory PublicSiteContent.fromJson(Map<String, dynamic> json) {
    final rawSeals = json['trustSeals'];
    final rawFloating = json['floatingWhatsapp'];
    final rawHeader = json['header'];
    return PublicSiteContent(
      tagline: _asString(json['tagline']),
      aboutText: _asString(json['aboutText']),
      whatsapp: _asString(json['whatsapp']),
      phone: _asString(json['phone']),
      email: _asString(json['email']),
      socialLinks: PublicSiteSocialLinks.fromJson(_asMap(json['socialLinks'])),
      ctaText: _asString(json['ctaText']),
      address: _asString(json['address']),
      businessHours: _asString(json['businessHours']),
      trustSeals: rawSeals is List
          ? rawSeals
              .whereType<Map>()
              .map((e) =>
                  PublicSiteTrustSeal.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      floatingWhatsapp: rawFloating is Map
          ? PublicSiteFloatingWhatsapp.fromJson(
              Map<String, dynamic>.from(rawFloating))
          : null,
      header: rawHeader is Map
          ? PublicSiteHeaderConfig.fromJson(Map<String, dynamic>.from(rawHeader))
          : null,
    );
  }

  /// Payload do "Salvar conteúdo" (aba Textos e contato) — 29/09/2026,
  /// integ-03.
  ///
  /// Campo vazio vai como `null` explícito: limpa o valor salvo e passa no
  /// `@IsOptional` do DTO, que só pula null/undefined. Antes ia `''`, o
  /// `@IsEmail` recusava (400) e quem não tem e-mail não conseguia salvar
  /// nem a frase, o sobre, o WhatsApp ou o SEO.
  ///
  /// Só entram as chaves que a aba do app edita. Redes sociais, endereço,
  /// horário, selos, WhatsApp flutuante e cabeçalho ficam FORA: o back faz
  /// merge raso (`{...salvo, ...enviado}`), então o que o web configurou
  /// nesses campos continua intacto — nada é apagado nem sobrescrito com um
  /// valor velho carregado quando a tela abriu.
  Map<String, dynamic> toJson() => {
        'tagline': _nullIfBlank(tagline),
        'aboutText': _nullIfBlank(aboutText),
        'whatsapp': _nullIfBlank(whatsapp),
        'phone': _nullIfBlank(phone),
        'email': _nullIfBlank(email),
        'ctaText': _nullIfBlank(ctaText),
      };

  PublicSiteContent copyWith({
    String? tagline,
    String? aboutText,
    String? whatsapp,
    String? phone,
    String? email,
    String? ctaText,
    PublicSiteSocialLinks? socialLinks,
    String? address,
    String? businessHours,
    List<PublicSiteTrustSeal>? trustSeals,
    Object? floatingWhatsapp = _keep,
    Object? header = _keep,
  }) {
    return PublicSiteContent(
      tagline: tagline ?? this.tagline,
      aboutText: aboutText ?? this.aboutText,
      whatsapp: whatsapp ?? this.whatsapp,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      socialLinks: socialLinks ?? this.socialLinks,
      ctaText: ctaText ?? this.ctaText,
      address: address ?? this.address,
      businessHours: businessHours ?? this.businessHours,
      trustSeals: trustSeals ?? this.trustSeals,
      floatingWhatsapp: identical(floatingWhatsapp, _keep)
          ? this.floatingWhatsapp
          : floatingWhatsapp as PublicSiteFloatingWhatsapp?,
      header: identical(header, _keep)
          ? this.header
          : header as PublicSiteHeaderConfig?,
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

  /// SEO da mesma aba (integ-03): vazio = `null` explícito, que limpa no
  /// merge raso do back. O ID do Google Analytics ainda não tem campo no app
  /// (integ-24) e fica fora — o back preserva o que o web salvou.
  Map<String, dynamic> toJson() => {
        'title': _nullIfBlank(title),
        'description': _nullIfBlank(description),
      };

  PublicSiteSeo copyWith({
    String? title,
    String? description,
    String? gaMeasurementId,
  }) {
    return PublicSiteSeo(
      title: title ?? this.title,
      description: description ?? this.description,
      gaMeasurementId: gaMeasurementId ?? this.gaMeasurementId,
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
    'ribbon': (
      label: 'Fita de assinatura',
      description: 'Faixa em rolagem contínua, logo abaixo do banner',
    ),
    'lead_form': (
      label: 'Formulário de captação',
      description: 'Formulário que transforma visitantes em leads no CRM',
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
      case 'ribbon':
        return LucideIcons.ribbon;
      case 'lead_form':
        return LucideIcons.clipboardList;
      default:
        return LucideIcons.square;
    }
  }

  /// Preset por template — cópia EXATA de `TEMPLATE_BLOCK_PRESETS` do back
  /// (`public-site-blocks.types.ts`) e de `TEMPLATE_PRESETS` do web
  /// (`publicSiteBlocks.ts`). Usada quando `homeBlocks` vem vazio do backend.
  ///
  /// integ-F1 (03/10/2026): os presets antigos do app não tinham
  /// `lead_form`. Com `homeBlocks` vazio, o site público desenha os defaults
  /// do back (com o formulário); ao salvar/reordenar uma seção, o app gravava
  /// os SEUS defaults e o site perdia o formulário de captação. O Premium
  /// também divergia (`stats` em vez de `ribbon`).
  static const Map<String, List<String>> templatePresets = {
    'modern': [
      'hero', 'categories', 'featured_cards', 'property_grid',
      'process', 'testimonials', 'about', 'lead_form', 'cta',
    ],
    'classic': [
      'hero', 'featured_cards', 'categories', 'property_grid',
      'services', 'process', 'about', 'lead_form', 'cta',
    ],
    'corporate': [
      'hero', 'services', 'featured_cards', 'categories',
      'property_grid', 'process', 'testimonials', 'lead_form', 'cta',
    ],
    'luxury': [
      'hero', 'about', 'featured_carousel', 'property_grid',
      'process', 'lead_form', 'cta',
    ],
    'compact': ['hero', 'property_grid', 'lead_form', 'cta'],
    'premium': [
      'hero', 'ribbon', 'featured_carousel', 'featured_cards',
      'property_grid', 'about', 'testimonials', 'trust', 'lead_form', 'cta',
    ],
  };

  static List<PublicSiteHomeBlock> defaultsFor(String templateId) {
    final types = templatePresets[templateId] ?? templatePresets['modern']!;
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

/// Dica por provedor (Registro.br, Cloudflare, GoDaddy…) — paridade com
/// `PublicSiteDnsProviderHint`.
class PublicSiteDnsProviderHint {
  final String name;
  final String? url;
  final String hint;

  const PublicSiteDnsProviderHint({
    required this.name,
    this.url,
    required this.hint,
  });

  factory PublicSiteDnsProviderHint.fromJson(Map<String, dynamic> json) {
    return PublicSiteDnsProviderHint(
      name: _asString(json['name']) ?? '',
      url: _asString(json['url']),
      hint: _asString(json['hint']) ?? '',
    );
  }
}

/// Instruções de DNS — normalização com defaults idêntica à
/// `normalizePublicSiteDnsInstructions` do web (payload parcial tolerado).
///
/// 29/09/2026 (integ-02): o app lia só `cnameTarget` e desenhava "CNAME →
/// sites.intellisysbr.com" fixo. O back mantém `cnameTarget` com o host
/// legado DE PROPÓSITO (compat com front antigo) e hoje pede registro **A**
/// em `www` e em `@` apontando para o IP (`recordType/recordHost/
/// recordValue`). Quem seguia o app configurava errado e o domínio nunca
/// ativava. Agora o tipo, o host e o valor vêm do payload; `cnameTarget` só
/// vale quando o próprio back declara `recordType == 'CNAME'`.
class PublicSiteDnsInstructions {
  static const String defaultSubdomainBase = 'sites.intellisysbr.com';

  /// Fallback quando o back ainda não manda `recordType/recordValue`: registro
  /// A para o IP da origem (mesmo valor do web).
  static const String defaultRecordType = 'A';
  static const String defaultRecordHost = 'www';
  static const String defaultRecordValue = '147.79.120.103';

  /// `'A'` (hoje) ou `'CNAME'` (só com Cloudflare for SaaS).
  final String recordType;
  final String recordHost;
  final String recordValue;
  final String subdomainBase;
  final String ttlRecommendation;
  final String propagationNote;
  final List<PublicSiteDnsStep> steps;
  final List<PublicSiteDnsProviderHint> providerHints;

  const PublicSiteDnsInstructions({
    required this.recordType,
    required this.recordHost,
    required this.recordValue,
    required this.subdomainBase,
    required this.ttlRecommendation,
    required this.propagationNote,
    required this.steps,
    required this.providerHints,
  });

  bool get isARecord => recordType == 'A';

  /// Registro A instrui também a raiz (`@`) com o mesmo IP, criada junto
  /// (steps atuais do back). Se o host já for `@`, é um registro só.
  bool get needsRootRecord => isARecord && recordHost != '@';

  /// "os dois registros A (www e @)" | "o registro CNAME" — para os avisos
  /// da tela, que antes falavam em CNAME fixo.
  String get recordsToCreateLabel => needsRootRecord
      ? 'os dois registros A ($recordHost e @)'
      : 'o registro $recordType';

  /// Compat — use [recordValue].
  String get cnameTarget => recordValue;

  factory PublicSiteDnsInstructions.fromJson(Map<String, dynamic>? json) {
    final raw = json ?? const <String, dynamic>{};
    final rawType = _asString(raw['recordType'])?.trim().toUpperCase();
    final recordType = (rawType == 'A' || rawType == 'CNAME')
        ? rawType!
        : defaultRecordType;

    final rawHost = _asString(raw['recordHost'])?.trim();
    final recordHost =
        (rawHost != null && rawHost.isNotEmpty) ? rawHost : defaultRecordHost;

    // Back antigo manda só `cnameTarget` (= host do storefront). Aproveitar
    // esse valor num registro A produziria instrução inválida, então ele só
    // vale quando o próprio back declara o tipo CNAME.
    String recordValue;
    final rawValue = _asString(raw['recordValue'])?.trim();
    final legacyCname = _asString(raw['cnameTarget'])?.trim();
    if (rawValue != null && rawValue.isNotEmpty) {
      recordValue = rawValue;
    } else if (recordType == 'CNAME' &&
        legacyCname != null &&
        legacyCname.isNotEmpty) {
      recordValue = legacyCname;
    } else {
      recordValue =
          recordType == 'CNAME' ? defaultSubdomainBase : defaultRecordValue;
    }

    final rawBase = _asString(raw['subdomainBase'])?.trim();
    final rawTtl = _asString(raw['ttlRecommendation'])?.trim();
    final rawNote = _asString(raw['propagationNote'])?.trim();

    final rawSteps = raw['steps'];
    final steps = rawSteps is List
        ? rawSteps
            .whereType<Map>()
            .map((e) => PublicSiteDnsStep.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <PublicSiteDnsStep>[];
    final rawHints = raw['providerHints'];
    final hints = rawHints is List
        ? rawHints
            .whereType<Map>()
            .map((e) => PublicSiteDnsProviderHint.fromJson(
                Map<String, dynamic>.from(e)))
            .toList()
        : <PublicSiteDnsProviderHint>[];

    return PublicSiteDnsInstructions(
      recordType: recordType,
      recordHost: recordHost,
      recordValue: recordValue,
      subdomainBase: (rawBase != null && rawBase.isNotEmpty)
          ? rawBase
          : defaultSubdomainBase,
      ttlRecommendation: (rawTtl != null && rawTtl.isNotEmpty)
          ? rawTtl
          : '3600 (1 hora) ou padrão do registrador',
      propagationNote: (rawNote != null && rawNote.isNotEmpty)
          ? rawNote
          : 'Alterações de DNS podem levar de alguns minutos até 48 horas '
              'para propagar globalmente.',
      steps: steps.isNotEmpty
          ? steps
          : _defaultSteps(recordType, recordHost, recordValue),
      providerHints: hints.isNotEmpty
          ? hints
          : _defaultProviderHints(recordType, recordHost),
    );
  }

  /// Passos padrão — espelham `defaultDnsSteps` do web e os steps atuais do
  /// back (registro A em www E em @ para o mesmo IP, criados juntos).
  static List<PublicSiteDnsStep> _defaultSteps(
    String recordType,
    String recordHost,
    String recordValue,
  ) {
    final isA = recordType == 'A';
    return [
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
            'Entre no painel onde o DNS do domínio é gerenciado (Registro.br, '
            'GoDaddy, Hostinger, Cloudflare etc.) e abra a zona DNS. Atenção: '
            'nem sempre é onde o domínio foi comprado.',
      ),
      PublicSiteDnsStep(
        order: 3,
        title: 'Crie o registro $recordType',
        description: isA
            ? 'Adicione um registro A para o host $recordHost apontando para o '
                'IP do servidor Intellisys. Se já existir um registro '
                '"$recordHost" apontando para o site antigo, apague-o antes — '
                'os dois não podem coexistir.'
            : 'Adicione um registro CNAME para o host $recordHost apontando '
                'para o destino Intellisys.',
        recordType: recordType,
        host: recordHost,
        value: recordValue,
      ),
      PublicSiteDnsStep(
        order: 4,
        title: isA ? 'Domínio raiz (crie junto)' : 'Domínio raiz (opcional)',
        description: isA
            ? 'Crie um segundo registro A, agora com host @ (a raiz), '
                'apontando para o mesmo $recordValue. É o que faz '
                'minhaimobiliaria.com.br abrir sem o www. Crie os dois na '
                'mesma visita ao painel: o www e a raiz são liberados juntos '
                'do nosso lado.'
            : 'Muitos registradores não permitem CNAME na raiz (@). Configure '
                'redirecionamento de minhaimobiliaria.com.br para '
                'www.minhaimobiliaria.com.br no painel do provedor ou use o '
                'recurso de forwarding/apex do DNS.',
      ),
      const PublicSiteDnsStep(
        order: 5,
        title: 'Verificação automática',
        description:
            'Salve o domínio e toque em "Verificar DNS". Quando o registro '
            'propagar, o domínio é ativado automaticamente (sem esperar '
            'aprovação manual).',
      ),
    ];
  }

  static List<PublicSiteDnsProviderHint> _defaultProviderHints(
    String recordType,
    String recordHost,
  ) =>
      [
        PublicSiteDnsProviderHint(
          name: 'Registro.br',
          url: 'https://registro.br',
          hint: 'Menu do domínio → DNS → incluir entrada $recordType com nome '
              '$recordHost.',
        ),
        PublicSiteDnsProviderHint(
          name: 'Cloudflare',
          url: 'https://dash.cloudflare.com',
          hint: 'DNS → Add record → Type $recordType, Name $recordHost, valor '
              'conforme indicado acima. IMPORTANTE: deixe como "DNS only" '
              '(nuvem CINZA) — com a nuvem laranja a validação falha.',
        ),
        PublicSiteDnsProviderHint(
          name: 'GoDaddy / Hostinger',
          hint: 'Zona DNS → $recordType → Host $recordHost → aponta para o '
              'valor indicado acima. TTL automático.',
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
