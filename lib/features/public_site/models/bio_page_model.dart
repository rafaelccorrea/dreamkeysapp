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

double _asDoubleOr(dynamic v, double fallback) {
  if (v is num) return v.toDouble();
  if (v is String) {
    return double.tryParse(v.replaceAll(',', '.').trim()) ?? fallback;
  }
  return fallback;
}

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '.').trim());
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

/// Base pública da página — paridade com `BIO_PUBLIC_BASE` do `bioPageApi.ts`.
const String kBioPublicBase = 'bio.intellisysbr.com';

/// Preço do add-on Premium — paridade com `BIO_PREMIUM_TEMPLATE_PRICE`.
const double kBioPremiumTemplatePrice = 49.9;

/// Monta a URL pública (`https://bio.intellisysbr.com/{slug}`).
String? buildBioPublicUrl(String? slug) {
  final s = slug?.trim();
  if (s == null || s.isEmpty) return null;
  return 'https://$kBioPublicBase/$s';
}

// ─── Link ────────────────────────────────────────────────────────────────────

/// Tipo do botão: `link` abre a URL; `lead_form` é o **botão de captação**
/// (abre o formulário de lead no site público e vira card no Kanban).
const String kBioLinkKindLink = 'link';
const String kBioLinkKindLeadForm = 'lead_form';

/// Ícones aceitos pelo back (`BIO_LINK_ICONS`) — paridade com
/// `BIO_LINK_ICON_OPTIONS` do `bioPageApi.ts`. `''` = automático (pela URL).
const List<({String id, String label})> kBioLinkIconOptions = [
  (id: '', label: 'Automático (pela URL)'),
  (id: 'whatsapp', label: 'WhatsApp'),
  (id: 'instagram', label: 'Instagram'),
  (id: 'facebook', label: 'Facebook'),
  (id: 'youtube', label: 'YouTube'),
  (id: 'tiktok', label: 'TikTok'),
  (id: 'x', label: 'X (Twitter)'),
  (id: 'linkedin', label: 'LinkedIn'),
  (id: 'telegram', label: 'Telegram'),
  (id: 'pinterest', label: 'Pinterest'),
  (id: 'spotify', label: 'Spotify'),
  (id: 'email', label: 'E-mail'),
  (id: 'phone', label: 'Telefone'),
  (id: 'maps', label: 'Mapa / localização'),
  (id: 'site', label: 'Site / genérico'),
];

/// Sentinela do `copyWith` para distinguir "não mexer" de "limpar (null)".
const Object _keep = Object();

/// Um link da página — paridade com `BioPageLink` (`bioPageApi.ts`).
///
/// 29/09/2026 (integ-01): antes o app só serializava id/label/url/order/
/// isActive/color/color2. O back (`sanitizeLinks`) recebia o link sem `kind`
/// e descartava o botão de captação (url vazia), além de zerar ícone e
/// subtítulo — um "Salvar links" no app destruía a personalização Premium
/// feita no web. Agora `kind`, `icon` e `subtitle` fazem a ida e a volta, e
/// qualquer campo que o back mandar e o app ainda não conheça fica em
/// [extras] e volta intacto no `toJson`.
class BioPageLink {
  final String id;
  final String label;
  final String url;
  final int order;
  final bool isActive;
  final String? color;
  final String? color2;

  /// `'link'` (ou null = link comum) | `'lead_form'` (botão de captação).
  final String? kind;

  /// Ícone escolhido à mão (Premium); null/vazio = detectado pela URL.
  final String? icon;

  /// Segunda linha do botão (Premium), até 60 caracteres.
  final String? subtitle;

  /// Campos desconhecidos do payload — devolvidos como vieram.
  final Map<String, dynamic> extras;

  const BioPageLink({
    required this.id,
    required this.label,
    required this.url,
    required this.order,
    required this.isActive,
    this.color,
    this.color2,
    this.kind,
    this.icon,
    this.subtitle,
    this.extras = const {},
  });

  bool get isLeadForm => kind == kBioLinkKindLeadForm;

  static const Set<String> _knownKeys = {
    'id',
    'label',
    'url',
    'order',
    'isActive',
    'color',
    'color2',
    'kind',
    'icon',
    'subtitle',
  };

  factory BioPageLink.fromJson(Map<String, dynamic> json) {
    final extras = <String, dynamic>{
      for (final e in json.entries)
        if (!_knownKeys.contains(e.key)) e.key: e.value,
    };
    final rawKind = _asString(json['kind'])?.trim();
    return BioPageLink(
      id: _asString(json['id']) ?? '',
      label: _asString(json['label']) ?? '',
      url: _asString(json['url']) ?? '',
      order: _asInt(json['order']),
      isActive: _asBool(json['isActive'], fallback: true),
      color: _asString(json['color']),
      color2: _asString(json['color2']),
      kind: (rawKind == null || rawKind.isEmpty) ? null : rawKind,
      icon: _asString(json['icon']),
      subtitle: _asString(json['subtitle']),
      extras: extras,
    );
  }

  /// Botão de captação vai SEMPRE com `url: ''` (paridade com o save do
  /// `BioLinkConfigPage.tsx`) — o back aceita url vazia só nesse tipo.
  Map<String, dynamic> toJson() {
    final trimmedIcon = icon?.trim();
    final trimmedSubtitle = subtitle?.trim();
    return {
      ...extras,
      'id': id,
      'label': label,
      'url': isLeadForm ? '' : url,
      'order': order,
      'isActive': isActive,
      if (kind != null) 'kind': kind,
      // null explícito limpa no back; ausente também vira null no sanitize.
      'color': color,
      'color2': color2,
      'icon': (trimmedIcon == null || trimmedIcon.isEmpty) ? null : trimmedIcon,
      'subtitle': (trimmedSubtitle == null || trimmedSubtitle.isEmpty)
          ? null
          : trimmedSubtitle,
    };
  }

  BioPageLink copyWith({
    String? label,
    String? url,
    int? order,
    bool? isActive,
    Object? color = _keep,
    Object? color2 = _keep,
    Object? kind = _keep,
    Object? icon = _keep,
    Object? subtitle = _keep,
  }) {
    return BioPageLink(
      id: id,
      label: label ?? this.label,
      url: url ?? this.url,
      order: order ?? this.order,
      isActive: isActive ?? this.isActive,
      color: identical(color, _keep) ? this.color : color as String?,
      color2: identical(color2, _keep) ? this.color2 : color2 as String?,
      kind: identical(kind, _keep) ? this.kind : kind as String?,
      icon: identical(icon, _keep) ? this.icon : icon as String?,
      subtitle:
          identical(subtitle, _keep) ? this.subtitle : subtitle as String?,
      extras: extras,
    );
  }
}

// ─── Página ──────────────────────────────────────────────────────────────────

/// Configuração da página Link in Bio — paridade com `BioPageConfig`.
///
/// `customization` fica como mapa cru: o app ainda não edita aparência
/// (cores/fundo/fonte são do painel web) e nenhum save do app manda essa
/// chave, então o que o web configurou fica intacto.
///
/// 29/09/2026: `subscriptionId` e o funil dos leads (`leadKanban*`) são só
/// lidos por enquanto — o seletor de funil é do integ-30 (P1), e os PATCHs
/// do app não mandam essas chaves (o back só mexe no funil quando elas vêm).
class BioPageConfig {
  final String id;
  final String companyId;
  final String? slug;
  final String templateId;
  final String? title;
  final String? bio;
  final String? avatarUrl;
  final String? instagramHandle;
  final List<BioPageLink> links;
  final Map<String, dynamic> customization;
  final bool isPublished;
  final DateTime? publishedAt;
  final String? publicUrl;
  final bool premiumTemplateUnlocked;
  final double? subscriptionMonthlyTotal;
  final double? premiumAddonMonthlyPrice;
  final String? subscriptionId;

  /// Funil de destino dos leads do botão de captação (null = fallback do
  /// back: funil padrão do WhatsApp, depois o primeiro funil ativo).
  final String? leadKanbanProjectId;

  /// Coluna de entrada no funil acima (null = primeira coluna ativa).
  final String? leadKanbanColumnId;
  final DateTime? updatedAt;

  const BioPageConfig({
    required this.id,
    required this.companyId,
    this.slug,
    required this.templateId,
    this.title,
    this.bio,
    this.avatarUrl,
    this.instagramHandle,
    this.links = const [],
    this.customization = const {},
    required this.isPublished,
    this.publishedAt,
    this.publicUrl,
    this.premiumTemplateUnlocked = false,
    this.subscriptionMonthlyTotal,
    this.premiumAddonMonthlyPrice,
    this.subscriptionId,
    this.leadKanbanProjectId,
    this.leadKanbanColumnId,
    this.updatedAt,
  });

  factory BioPageConfig.fromJson(Map<String, dynamic> json) {
    final rawLinks = json['links'];
    final links = rawLinks is List
        ? rawLinks
            .whereType<Map>()
            .map((e) => BioPageLink.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <BioPageLink>[];
    links.sort((a, b) => a.order.compareTo(b.order));
    return BioPageConfig(
      id: _asString(json['id']) ?? '',
      companyId: _asString(json['companyId']) ?? '',
      slug: _asString(json['slug']),
      templateId: _asString(json['templateId']) ?? 'minimal',
      title: _asString(json['title']),
      bio: _asString(json['bio']),
      avatarUrl: _asString(json['avatarUrl']),
      instagramHandle: _asString(json['instagramHandle']),
      links: links,
      customization: _asMap(json['customization']),
      isPublished: _asBool(json['isPublished']),
      publishedAt: _asDate(json['publishedAt']),
      publicUrl: _asString(json['publicUrl']),
      premiumTemplateUnlocked: _asBool(json['premiumTemplateUnlocked']),
      subscriptionMonthlyTotal: _asDouble(json['subscriptionMonthlyTotal']),
      premiumAddonMonthlyPrice: _asDouble(json['premiumAddonMonthlyPrice']),
      subscriptionId: _asString(json['subscriptionId']),
      leadKanbanProjectId: _asString(json['leadKanbanProjectId']),
      leadKanbanColumnId: _asString(json['leadKanbanColumnId']),
      updatedAt: _asDate(json['updatedAt']),
    );
  }

  /// URL pública "melhor esforço" — `publicUrl` do backend ou montada do slug.
  String? get bestPublicUrl {
    final direct = publicUrl?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    return buildBioPublicUrl(slug);
  }

  int get activeLinkCount => links.where((l) => l.isActive).length;

  /// Paridade com `temBotaoDeCaptacao` do web (usado pelo seletor de funil).
  bool get hasActiveLeadFormButton =>
      links.any((l) => l.isActive && l.isLeadForm);
}

// ─── Templates ───────────────────────────────────────────────────────────────

class BioPageTemplateInfo {
  final String id;
  final String name;
  final String description;
  final bool isPremium;
  final double? monthlyPrice;
  final bool isUnlocked;

  const BioPageTemplateInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.isPremium,
    this.monthlyPrice,
    required this.isUnlocked,
  });

  factory BioPageTemplateInfo.fromJson(Map<String, dynamic> json) {
    final id = _asString(json['id']) ?? '';
    final isPremium = json['isPremium'] != null
        ? _asBool(json['isPremium'])
        : id == 'premium';
    return BioPageTemplateInfo(
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

// ─── Analytics ───────────────────────────────────────────────────────────────

class BioPageLinkAnalytics {
  final String linkId;
  final String label;
  final int clicks;

  const BioPageLinkAnalytics({
    required this.linkId,
    required this.label,
    required this.clicks,
  });

  factory BioPageLinkAnalytics.fromJson(Map<String, dynamic> json) {
    return BioPageLinkAnalytics(
      linkId: _asString(json['linkId']) ?? '',
      label: _asString(json['label']) ?? '',
      clicks: _asInt(json['clicks']),
    );
  }
}

class BioPageDailyAnalytics {
  final String date;
  final int views;
  final int clicks;

  const BioPageDailyAnalytics({
    required this.date,
    required this.views,
    required this.clicks,
  });

  factory BioPageDailyAnalytics.fromJson(Map<String, dynamic> json) {
    return BioPageDailyAnalytics(
      date: _asString(json['date']) ?? '',
      views: _asInt(json['views']),
      clicks: _asInt(json['clicks']),
    );
  }
}

class BioPageAnalytics {
  final int periodDays;
  final int pageViews;
  final int linkClicks;
  final int instagramClicks;
  final double clickThroughRate;
  final List<BioPageLinkAnalytics> links;
  final List<BioPageDailyAnalytics> viewsByDay;

  const BioPageAnalytics({
    required this.periodDays,
    required this.pageViews,
    required this.linkClicks,
    required this.instagramClicks,
    required this.clickThroughRate,
    this.links = const [],
    this.viewsByDay = const [],
  });

  static const BioPageAnalytics empty = BioPageAnalytics(
    periodDays: 30,
    pageViews: 0,
    linkClicks: 0,
    instagramClicks: 0,
    clickThroughRate: 0,
  );

  factory BioPageAnalytics.fromJson(Map<String, dynamic> json) {
    final rawLinks = json['links'];
    final rawDays = json['viewsByDay'];
    return BioPageAnalytics(
      periodDays: _asInt(json['periodDays'], fallback: 30),
      pageViews: _asInt(json['pageViews']),
      linkClicks: _asInt(json['linkClicks']),
      instagramClicks: _asInt(json['instagramClicks']),
      clickThroughRate: _asDoubleOr(json['clickThroughRate'], 0),
      links: rawLinks is List
          ? rawLinks
              .whereType<Map>()
              .map((e) =>
                  BioPageLinkAnalytics.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      viewsByDay: rawDays is List
          ? rawDays
              .whereType<Map>()
              .map((e) =>
                  BioPageDailyAnalytics.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}
