// Modelos de Empreendimentos — espelham `types/empreendimento.ts` do
// imobx-front (entity `empreendimentos` no backend). O empreendimento é a
// mesma shape do condomínio + material da equipe (playbook/playbookKit).

import 'condominium_models.dart';

/// Link do material da equipe (`PlaybookKitLink`).
class PlaybookLink {
  final String id;
  final String label;
  final String url;

  const PlaybookLink({required this.id, required this.label, required this.url});

  factory PlaybookLink.fromJson(Map<String, dynamic> json) {
    return PlaybookLink(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'url': url};
}

/// Arquivo do material da equipe (`PlaybookKitFile`).
class PlaybookFile {
  final String id;
  final String originalName;
  final String fileUrl;
  final String mimeType;
  final int fileSize;

  const PlaybookFile({
    required this.id,
    required this.originalName,
    required this.fileUrl,
    required this.mimeType,
    required this.fileSize,
  });

  factory PlaybookFile.fromJson(Map<String, dynamic> json) {
    return PlaybookFile(
      id: json['id']?.toString() ?? '',
      originalName: json['originalName']?.toString() ?? '',
      fileUrl: json['fileUrl']?.toString() ?? '',
      mimeType: json['mimeType']?.toString() ?? '',
      fileSize: parseEstateInt(json['fileSize']),
    );
  }
}

/// Kit de material da equipe (`PlaybookKit`): notas + links + arquivos.
class PlaybookKit {
  final String? notes;
  final List<PlaybookLink> links;
  final List<PlaybookFile> files;

  const PlaybookKit({this.notes, required this.links, required this.files});

  static const empty = PlaybookKit(notes: null, links: [], files: []);

  factory PlaybookKit.fromJson(Map<String, dynamic> json) {
    final rawLinks = json['links'];
    final rawFiles = json['files'];
    return PlaybookKit(
      notes: json['notes']?.toString(),
      links: rawLinks is List
          ? rawLinks
              .whereType<Map>()
              .map((e) => PlaybookLink.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      files: rawFiles is List
          ? rawFiles
              .whereType<Map>()
              .map((e) => PlaybookFile.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}

/// Empreendimento (1:1 com `Empreendimento` do imobx-front).
class Development {
  final String id;
  final String name;
  final String? description;
  final String? playbook;
  final PlaybookKit playbookKit;
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

  const Development({
    required this.id,
    required this.name,
    this.description,
    this.playbook,
    required this.playbookKit,
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

  factory Development.fromJson(Map<String, dynamic> json) {
    final rawKit = json['playbookKit'] ?? json['playbook_kit'];
    return Development(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: _opt(json['description']),
      playbook: _opt(json['playbook']),
      playbookKit: rawKit is Map
          ? PlaybookKit.fromJson(Map<String, dynamic>.from(rawKit))
          : PlaybookKit.empty,
      address: json['address']?.toString() ?? '',
      street: json['street']?.toString() ?? '',
      number: json['number']?.toString() ?? '',
      complement: _opt(json['complement']),
      neighborhood: json['neighborhood']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      zipCode: json['zipCode']?.toString() ?? json['zip_code']?.toString() ?? '',
      phone: _opt(json['phone']),
      email: _opt(json['email']),
      cnpj: _opt(json['cnpj']),
      website: _opt(json['website']),
      isActive: parseEstateBool(json['isActive'] ?? json['is_active'],
          fallback: true),
      images: EstateImage.listFromJson(json['images']),
      createdAt: parseEstateDate(json['createdAt'] ?? json['created_at']),
      updatedAt: parseEstateDate(json['updatedAt'] ?? json['updated_at']),
    );
  }

  static String? _opt(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  List<EstateImage> get activeImages =>
      images.where((i) => i.isActive).toList();

  String? get mainImageUrl {
    final active = activeImages;
    if (active.isEmpty) return null;
    final url = active.first.fileUrl.trim();
    return url.isEmpty ? null : url;
  }

  String get cityState =>
      [city, state].where((s) => s.trim().isNotEmpty).join(', ');

  String get fullAddressLine {
    final line = [
      [street, number].where((s) => s.trim().isNotEmpty).join(', '),
      complement ?? '',
      neighborhood,
    ].where((s) => s.trim().isNotEmpty).join(' · ');
    return line.isNotEmpty ? line : address;
  }

  /// Notas do material (kit tem prioridade — paridade com o web).
  String get materialNotes =>
      (playbookKit.notes ?? playbook ?? '').trim();

  /// Paridade com `hasEmpreendimentoMaterial` do web.
  bool get hasMaterial =>
      materialNotes.isNotEmpty ||
      playbookKit.links.isNotEmpty ||
      playbookKit.files.isNotEmpty;
}

/// Resposta paginada de `GET /empreendimentos`.
class DevelopmentListResult {
  final List<Development> items;
  final int total;
  final int page;
  final int limit;
  final int totalPages;

  const DevelopmentListResult({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });

  static const empty = DevelopmentListResult(
    items: [],
    total: 0,
    page: 1,
    limit: 30,
    totalPages: 1,
  );

  bool get hasMore => page < totalPages;

  factory DevelopmentListResult.fromRaw(dynamic raw) {
    if (raw is List) {
      final items = raw
          .whereType<Map>()
          .map((e) => Development.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      return DevelopmentListResult(
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
              .map((e) => Development.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : <Development>[];
      return DevelopmentListResult(
        items: items,
        total: parseEstateInt(json['total'], items.length),
        page: parseEstateInt(json['page'], 1),
        limit: parseEstateInt(json['limit'], items.length),
        totalPages: parseEstateInt(json['totalPages'], 1),
      );
    }
    return DevelopmentListResult.empty;
  }
}
