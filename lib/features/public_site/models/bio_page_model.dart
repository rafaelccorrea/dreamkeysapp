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

/// Um link da página — paridade com `BioPageLink` (`bioPageApi.ts`).
class BioPageLink {
  final String id;
  final String label;
  final String url;
  final int order;
  final bool isActive;
  final String? color;
  final String? color2;

  const BioPageLink({
    required this.id,
    required this.label,
    required this.url,
    required this.order,
    required this.isActive,
    this.color,
    this.color2,
  });

  factory BioPageLink.fromJson(Map<String, dynamic> json) {
    return BioPageLink(
      id: _asString(json['id']) ?? '',
      label: _asString(json['label']) ?? '',
      url: _asString(json['url']) ?? '',
      order: _asInt(json['order']),
      isActive: _asBool(json['isActive'], fallback: true),
      color: _asString(json['color']),
      color2: _asString(json['color2']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'url': url,
        'order': order,
        'isActive': isActive,
        if (color != null) 'color': color,
        if (color2 != null) 'color2': color2,
      };

  BioPageLink copyWith({
    String? label,
    String? url,
    int? order,
    bool? isActive,
  }) {
    return BioPageLink(
      id: id,
      label: label ?? this.label,
      url: url ?? this.url,
      order: order ?? this.order,
      isActive: isActive ?? this.isActive,
      color: color,
      color2: color2,
    );
  }
}

// ─── Página ──────────────────────────────────────────────────────────────────

/// Configuração da página Link in Bio — paridade com `BioPageConfig`.
///
/// `customization` fica como mapa cru: o mobile não edita esses campos
/// (cores/fundo são Premium do web) e devolver o mapa intacto no PATCH evita
/// apagar configurações feitas no painel.
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
