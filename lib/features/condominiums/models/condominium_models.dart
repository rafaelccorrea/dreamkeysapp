// Modelos do módulo Condomínios & Empreendimentos — espelham
// `types/condominium.ts` do imobx-front e as entities do backend
// (`condominiums` / `empreendimentos` no imobx). Parse defensivo: campos
// podem vir null / string / number.

/// `double` defensivo.
double parseEstateDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

/// `int` defensivo.
int parseEstateInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? fallback;
}

/// `bool` defensivo (`true`/`'true'`/`1`).
bool parseEstateBool(dynamic v, {bool fallback = false}) {
  if (v == null) return fallback;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().toLowerCase().trim();
  if (s == 'true' || s == '1') return true;
  if (s == 'false' || s == '0') return false;
  return fallback;
}

DateTime? parseEstateDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

String? _optString(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// Imagem de condomínio/empreendimento (mesma shape nos dois módulos).
class EstateImage {
  final String id;
  final String originalName;
  final String fileUrl;
  final String mimeType;
  final String status;
  final bool isMain;
  final int displayOrder;

  const EstateImage({
    required this.id,
    required this.originalName,
    required this.fileUrl,
    required this.mimeType,
    required this.status,
    required this.isMain,
    required this.displayOrder,
  });

  /// Paridade com o web: imagens com soft delete ainda podem vir do backend.
  bool get isActive => status.toLowerCase() == 'active';

  factory EstateImage.fromJson(Map<String, dynamic> json) {
    return EstateImage(
      id: json['id']?.toString() ?? '',
      originalName: json['originalName']?.toString() ?? '',
      fileUrl: json['fileUrl']?.toString() ?? '',
      mimeType: json['mimeType']?.toString() ?? '',
      status: json['status']?.toString() ?? 'active',
      isMain: parseEstateBool(json['isMain']),
      displayOrder: parseEstateInt(json['displayOrder']),
    );
  }

  static List<EstateImage> listFromJson(dynamic raw) {
    if (raw is! List) return const [];
    final list = raw
        .whereType<Map>()
        .map((e) => EstateImage.fromJson(Map<String, dynamic>.from(e)))
        .where((img) => img.status.toLowerCase() != 'deleted')
        .toList();
    list.sort((a, b) {
      if (a.isMain != b.isMain) return a.isMain ? -1 : 1;
      return a.displayOrder.compareTo(b.displayOrder);
    });
    return list;
  }
}

/// Condomínio (1:1 com `Condominium` do imobx-front).
class Condominium {
  final String id;
  final String name;
  final String? description;
  final String address;
  final String street;
  final String number;
  final String? complement;
  final String neighborhood;
  final String city;
  final String state;
  final String zipCode;
  final String? phone;
  final String? email;
  final String? cnpj;
  final String? website;
  final bool isActive;
  final List<EstateImage> images;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Condominium({
    required this.id,
    required this.name,
    this.description,
    required this.address,
    required this.street,
    required this.number,
    this.complement,
    required this.neighborhood,
    required this.city,
    required this.state,
    required this.zipCode,
    this.phone,
    this.email,
    this.cnpj,
    this.website,
    required this.isActive,
    required this.images,
    this.createdAt,
    this.updatedAt,
  });

  factory Condominium.fromJson(Map<String, dynamic> json) {
    return Condominium(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: _optString(json['description']),
      address: json['address']?.toString() ?? '',
      street: json['street']?.toString() ?? '',
      number: json['number']?.toString() ?? '',
      complement: _optString(json['complement']),
      neighborhood: json['neighborhood']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      zipCode: json['zipCode']?.toString() ?? json['zip_code']?.toString() ?? '',
      phone: _optString(json['phone']),
      email: _optString(json['email']),
      cnpj: _optString(json['cnpj']),
      website: _optString(json['website']),
      isActive: parseEstateBool(json['isActive'] ?? json['is_active'],
          fallback: true),
      images: EstateImage.listFromJson(json['images']),
      createdAt: parseEstateDate(json['createdAt'] ?? json['created_at']),
      updatedAt: parseEstateDate(json['updatedAt'] ?? json['updated_at']),
    );
  }

  List<EstateImage> get activeImages =>
      images.where((i) => i.isActive).toList();

  String? get mainImageUrl {
    final active = activeImages;
    if (active.isEmpty) return null;
    final url = active.first.fileUrl.trim();
    return url.isEmpty ? null : url;
  }

  /// "Cidade, UF" (só o que existir).
  String get cityState =>
      [city, state].where((s) => s.trim().isNotEmpty).join(', ');

  /// Rua, número · complemento · bairro (fallback: address).
  String get fullAddressLine {
    final line = [
      [street, number].where((s) => s.trim().isNotEmpty).join(', '),
      complement ?? '',
      neighborhood,
    ].where((s) => s.trim().isNotEmpty).join(' · ');
    return line.isNotEmpty ? line : address;
  }

  /// Completude do cadastro (0–100) — mesmos 12 campos do web.
  int get completenessPct {
    final fields = <bool>[
      name.trim().isNotEmpty,
      address.trim().isNotEmpty,
      neighborhood.trim().isNotEmpty,
      city.trim().isNotEmpty,
      state.trim().isNotEmpty,
      zipCode.trim().isNotEmpty,
      (phone ?? '').trim().isNotEmpty,
      (email ?? '').trim().isNotEmpty,
      (cnpj ?? '').trim().isNotEmpty,
      (website ?? '').trim().isNotEmpty,
      (description ?? '').trim().isNotEmpty,
      activeImages.isNotEmpty,
    ];
    final filled = fields.where((f) => f).length;
    return ((filled / fields.length) * 100).round();
  }
}

/// Resposta paginada de `GET /condominiums`.
class CondominiumListResult {
  final List<Condominium> items;
  final int total;
  final int page;
  final int limit;
  final int totalPages;

  const CondominiumListResult({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });

  static const empty = CondominiumListResult(
    items: [],
    total: 0,
    page: 1,
    limit: 30,
    totalPages: 1,
  );

  bool get hasMore => page < totalPages;

  factory CondominiumListResult.fromRaw(dynamic raw) {
    if (raw is List) {
      final items = raw
          .whereType<Map>()
          .map((e) => Condominium.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      return CondominiumListResult(
        items: items,
        total: items.length,
        page: 1,
        limit: items.length,
        totalPages: 1,
      );
    }
    if (raw is Map) {
      final json = Map<String, dynamic>.from(raw);
      final data = json['data'];
      final items = data is List
          ? data
              .whereType<Map>()
              .map((e) => Condominium.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : <Condominium>[];
      return CondominiumListResult(
        items: items,
        total: parseEstateInt(json['total'], items.length),
        page: parseEstateInt(json['page'], 1),
        limit: parseEstateInt(json['limit'], items.length),
        totalPages: parseEstateInt(json['totalPages'], 1),
      );
    }
    return CondominiumListResult.empty;
  }
}

/// Campo de ordenação aceito pelo backend (`sortBy`).
enum EstateSortBy {
  name,
  city,
  createdAt,
  updatedAt;

  String get label {
    switch (this) {
      case EstateSortBy.name:
        return 'Nome';
      case EstateSortBy.city:
        return 'Cidade';
      case EstateSortBy.createdAt:
        return 'Criação';
      case EstateSortBy.updatedAt:
        return 'Atualização';
    }
  }
}

/// Filtros de `GET /condominiums` e `GET /empreendimentos` (mesma query).
class EstateListFilters {
  final String? search;
  final String? city;
  final String? state;
  final String? neighborhood;
  final bool? isActive;
  final int page;
  final int limit;
  final EstateSortBy sortBy;
  final bool ascending;

  const EstateListFilters({
    this.search,
    this.city,
    this.state,
    this.neighborhood,
    this.isActive,
    this.page = 1,
    this.limit = 30,
    this.sortBy = EstateSortBy.name,
    this.ascending = true,
  });

  /// Quantos filtros "extras" (do modal) estão ativos — para o badge.
  int get activeCount {
    var n = 0;
    if ((city ?? '').trim().isNotEmpty) n++;
    if ((state ?? '').trim().isNotEmpty) n++;
    if ((neighborhood ?? '').trim().isNotEmpty) n++;
    if (sortBy != EstateSortBy.name || !ascending) n++;
    return n;
  }

  EstateListFilters copyWith({
    String? search,
    String? city,
    String? state,
    String? neighborhood,
    bool? isActive,
    int? page,
    int? limit,
    EstateSortBy? sortBy,
    bool? ascending,
    bool clearIsActive = false,
    bool clearLocation = false,
  }) {
    return EstateListFilters(
      search: search ?? this.search,
      city: clearLocation ? null : (city ?? this.city),
      state: clearLocation ? null : (state ?? this.state),
      neighborhood: clearLocation ? null : (neighborhood ?? this.neighborhood),
      isActive: clearIsActive ? null : (isActive ?? this.isActive),
      page: page ?? this.page,
      limit: limit ?? this.limit,
      sortBy: sortBy ?? this.sortBy,
      ascending: ascending ?? this.ascending,
    );
  }

  Map<String, String> toQueryParams() {
    final out = <String, String>{
      'page': '$page',
      'limit': '$limit',
      'sortBy': sortBy.name,
      'sortOrder': ascending ? 'ASC' : 'DESC',
    };
    void put(String key, String? value) {
      final v = value?.trim();
      if (v != null && v.isNotEmpty) out[key] = v;
    }

    put('search', search);
    put('city', city);
    put('state', state);
    put('neighborhood', neighborhood);
    if (isActive != null) out['isActive'] = isActive! ? 'true' : 'false';
    return out;
  }
}

/// Cadastro parecido encontrado pelo `check-similarity`.
class SimilarEstate {
  final String id;
  final String name;
  final String address;
  final String city;
  final String state;
  final double similarityScore;
  final bool isActive;

  const SimilarEstate({
    required this.id,
    required this.name,
    required this.address,
    required this.city,
    required this.state,
    required this.similarityScore,
    required this.isActive,
  });

  factory SimilarEstate.fromJson(Map<String, dynamic> json) {
    return SimilarEstate(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      similarityScore: parseEstateDouble(json['similarityScore']),
      isActive: parseEstateBool(json['isActive'], fallback: true),
    );
  }
}

/// Resposta de `GET .../check-similarity?name=` — o web usa chaves diferentes
/// por módulo (`similarCondominiums` / `similarEmpreendimentos`).
class SimilarityResult {
  final bool hasSimilar;
  final List<SimilarEstate> similar;

  const SimilarityResult({required this.hasSimilar, required this.similar});

  static const none = SimilarityResult(hasSimilar: false, similar: []);

  factory SimilarityResult.fromJson(Map<String, dynamic> json) {
    final raw = json['similarCondominiums'] ?? json['similarEmpreendimentos'];
    final list = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => SimilarEstate.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <SimilarEstate>[];
    return SimilarityResult(
      hasSimilar: parseEstateBool(json['hasSimilar']) || list.isNotEmpty,
      similar: list,
    );
  }
}
