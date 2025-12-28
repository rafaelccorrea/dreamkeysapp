import 'package:flutter/material.dart';

Map<String, dynamic> _convertToMap(dynamic value) {
  if (value == null) return <String, dynamic>{};
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

/// Modelos de dados para Matches

/// Status do Match
enum MatchStatus {
  pending('pending', 'Pendente'),
  viewed('viewed', 'Visualizado'),
  accepted('accepted', 'Aceito'),
  contacted('contacted', 'Contatado'),
  scheduled('scheduled', 'Agendado'),
  ignored('ignored', 'Ignorado'),
  notInterested('not_interested', 'Não Interessado'),
  completed('completed', 'Concluído'),
  expired('expired', 'Expirado');

  final String value;
  final String label;

  const MatchStatus(this.value, this.label);

  static MatchStatus fromString(String? value) {
    if (value == null) return pending;
    try {
      return MatchStatus.values.firstWhere(
        (e) => e.value == value.toLowerCase(),
        orElse: () => pending,
      );
    } catch (e) {
      return pending;
    }
  }
}

/// Motivo de Ignorar Match
enum IgnoreReason {
  priceTooHigh('price_too_high', 'Preço muito alto'),
  priceTooLow('price_too_low', 'Preço muito baixo'),
  locationBad('location_bad', 'Localização ruim'),
  alreadyShown('already_shown', 'Já mostrado ao cliente'),
  clientNotInterested('client_not_interested', 'Cliente não se interessou'),
  propertySold('property_sold', 'Imóvel já vendido'),
  other('other', 'Outro');

  final String value;
  final String label;

  const IgnoreReason(this.value, this.label);

  static IgnoreReason fromString(String? value) {
    if (value == null) return other;
    try {
      return IgnoreReason.values.firstWhere(
        (e) => e.value == value.toLowerCase(),
        orElse: () => other,
      );
    } catch (e) {
      return other;
    }
  }
}

/// Resumo da Propriedade
class PropertySummary {
  final String id;
  final String title;
  final String? code;
  final double? salePrice;
  final double? rentPrice;
  final String? address;
  final String? city;
  final String? neighborhood;
  final String? type;
  final int? bedrooms;
  final int? bathrooms;
  final int? parkingSpaces;
  final double? builtArea;
  final double? area;
  final List<PropertyImage>? images;
  final PropertyImage? mainImage;

  PropertySummary({
    required this.id,
    required this.title,
    this.code,
    this.salePrice,
    this.rentPrice,
    this.address,
    this.city,
    this.neighborhood,
    this.type,
    this.bedrooms,
    this.bathrooms,
    this.parkingSpaces,
    this.builtArea,
    this.area,
    this.images,
    this.mainImage,
  });

  factory PropertySummary.fromJson(Map<String, dynamic> json) {
    return PropertySummary(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      code: json['code']?.toString(),
      salePrice: _parseDouble(json['salePrice'] ?? json['sale_price']),
      rentPrice: _parseDouble(json['rentPrice'] ?? json['rent_price']),
      address: json['address']?.toString(),
      city: json['city']?.toString(),
      neighborhood: json['neighborhood']?.toString(),
      type: json['type']?.toString(),
      bedrooms: _parseInt(json['bedrooms']),
      bathrooms: _parseInt(json['bathrooms']),
      parkingSpaces: _parseInt(json['parkingSpaces'] ?? json['parking_spaces']),
      builtArea: _parseDouble(json['builtArea'] ?? json['built_area']),
      area: _parseDouble(json['area']),
      images: json['images'] != null
          ? (json['images'] as List)
                .map((e) => PropertyImage.fromJson(_convertToMap(e)))
                .toList()
          : null,
      mainImage: json['mainImage'] != null
          ? PropertyImage.fromJson(_convertToMap(json['mainImage']))
          : null,
    );
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      final cleaned = value
          .replaceAll(RegExp(r'[^\d,.]'), '')
          .replaceAll(',', '.');
      return double.tryParse(cleaned);
    }
    return null;
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      return int.tryParse(value.replaceAll(RegExp(r'[^\d]'), ''));
    }
    return null;
  }
}

/// Imagem da Propriedade
class PropertyImage {
  final String? id;
  final String url;
  final String? thumbnailUrl;
  final bool? isMain;
  final String? category;

  PropertyImage({
    this.id,
    required this.url,
    this.thumbnailUrl,
    this.isMain,
    this.category,
  });

  factory PropertyImage.fromJson(Map<String, dynamic> json) {
    return PropertyImage(
      id: json['id']?.toString(),
      url: json['url']?.toString() ?? '',
      thumbnailUrl:
          json['thumbnailUrl']?.toString() ?? json['thumbnail_url']?.toString(),
      isMain: json['isMain'] ?? json['is_main'] ?? false,
      category: json['category']?.toString(),
    );
  }
}

/// Resumo do Cliente
class ClientSummary {
  final String id;
  final String name;
  final String? phone;
  final String? email;
  final String? avatar;
  final String? cpf;
  final String? type;

  ClientSummary({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.avatar,
    this.cpf,
    this.type,
  });

  factory ClientSummary.fromJson(Map<String, dynamic> json) {
    return ClientSummary(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString(),
      email: json['email']?.toString(),
      avatar: json['avatar']?.toString(),
      cpf: json['cpf']?.toString(),
      type: json['type']?.toString(),
    );
  }
}

/// Detalhes da Compatibilidade
class MatchDetails {
  final bool priceMatch;
  final double pricePercentage;
  final bool locationMatch;
  final bool typeMatch;
  final bool sizeMatch;
  final bool bedroomsMatch;
  final bool bathroomsMatch;
  final List<String> reasons;

  MatchDetails({
    required this.priceMatch,
    required this.pricePercentage,
    required this.locationMatch,
    required this.typeMatch,
    required this.sizeMatch,
    required this.bedroomsMatch,
    required this.bathroomsMatch,
    required this.reasons,
  });

  factory MatchDetails.fromJson(Map<String, dynamic> json) {
    return MatchDetails(
      priceMatch: json['priceMatch'] ?? json['price_match'] ?? false,
      pricePercentage:
          (json['pricePercentage'] ?? json['price_percentage'] ?? 0).toDouble(),
      locationMatch: json['locationMatch'] ?? json['location_match'] ?? false,
      typeMatch: json['typeMatch'] ?? json['type_match'] ?? false,
      sizeMatch: json['sizeMatch'] ?? json['size_match'] ?? false,
      bedroomsMatch: json['bedroomsMatch'] ?? json['bedrooms_match'] ?? false,
      bathroomsMatch:
          json['bathroomsMatch'] ?? json['bathrooms_match'] ?? false,
      reasons: json['reasons'] != null
          ? (json['reasons'] as List).map((e) => e.toString()).toList()
          : [],
    );
  }
}

/// Modelo de Match
class Match {
  final String id;
  final int matchScore;
  final MatchStatus status;
  final PropertySummary property;
  final ClientSummary client;
  final MatchDetails matchDetails;
  final bool taskCreated;
  final bool appointmentCreated;
  final bool emailSent;
  final bool notificationSent;
  final String createdAt;
  final String? viewedAt;
  final String? actionTakenAt;
  final IgnoreReason? ignoreReason;
  final String? notes;

  Match({
    required this.id,
    required this.matchScore,
    required this.status,
    required this.property,
    required this.client,
    required this.matchDetails,
    this.taskCreated = false,
    this.appointmentCreated = false,
    this.emailSent = false,
    this.notificationSent = false,
    required this.createdAt,
    this.viewedAt,
    this.actionTakenAt,
    this.ignoreReason,
    this.notes,
  });

  factory Match.fromJson(Map<String, dynamic> json) {
    return Match(
      id: json['id']?.toString() ?? '',
      matchScore: json['matchScore'] ?? json['match_score'] ?? 0,
      status: MatchStatus.fromString(json['status']?.toString()),
      property: PropertySummary.fromJson(
        json['property'] is Map<String, dynamic>
            ? json['property'] as Map<String, dynamic>
            : json['property'] is Map
            ? Map<String, dynamic>.from(json['property'] as Map)
            : <String, dynamic>{},
      ),
      client: ClientSummary.fromJson(
        json['client'] is Map ? json['client'] : {},
      ),
      matchDetails: MatchDetails.fromJson(
        json['matchDetails'] ?? json['match_details'] ?? {},
      ),
      taskCreated: json['taskCreated'] ?? json['task_created'] ?? false,
      appointmentCreated:
          json['appointmentCreated'] ?? json['appointment_created'] ?? false,
      emailSent: json['emailSent'] ?? json['email_sent'] ?? false,
      notificationSent:
          json['notificationSent'] ?? json['notification_sent'] ?? false,
      createdAt:
          json['createdAt']?.toString() ?? json['created_at']?.toString() ?? '',
      viewedAt: json['viewedAt']?.toString() ?? json['viewed_at']?.toString(),
      actionTakenAt:
          json['actionTakenAt']?.toString() ??
          json['action_taken_at']?.toString(),
      ignoreReason:
          json['ignoreReason'] != null || json['ignore_reason'] != null
          ? IgnoreReason.fromString(
              json['ignoreReason']?.toString() ??
                  json['ignore_reason']?.toString(),
            )
          : null,
      notes: json['notes']?.toString(),
    );
  }

  /// Retorna a cor baseada no score
  Color getScoreColor() {
    if (matchScore >= 90) return const Color(0xFF2E7D32); // Verde escuro
    if (matchScore >= 80) return const Color(0xFF4CAF50); // Verde
    if (matchScore >= 70) return const Color(0xFFFFC107); // Amarelo
    if (matchScore >= 50) return const Color(0xFFFF9800); // Laranja
    if (matchScore >= 25) return const Color(0xFFE57373); // Vermelho claro
    if (matchScore >= 1) return const Color(0xFFD32F2F); // Vermelho escuro
    return const Color(0xFF9E9E9E); // Cinza
  }

  /// Retorna o label baseado no score
  String getScoreLabel() {
    if (matchScore >= 90) return 'Match Perfeito!';
    if (matchScore >= 80) return 'Ótimo Match';
    if (matchScore >= 70) return 'Bom Match';
    if (matchScore >= 50) return 'Match Moderado';
    if (matchScore >= 25) return 'Match Baixo';
    if (matchScore >= 1) return 'Match Muito Baixo';
    return 'Sem Compatibilidade';
  }
}

/// Resposta de Lista de Matches
class MatchListResponse {
  final List<Match> matches;
  final int total;
  final int page;
  final int totalPages;

  MatchListResponse({
    required this.matches,
    required this.total,
    required this.page,
    required this.totalPages,
  });

  factory MatchListResponse.fromJson(Map<String, dynamic> json) {
    final matchesList = json['matches'] ?? json['data'] ?? [];
    return MatchListResponse(
      matches: matchesList is List
          ? matchesList.map((e) => Match.fromJson(_convertToMap(e))).toList()
          : [],
      total: json['total'] ?? 0,
      page: json['page'] ?? 1,
      totalPages: json['totalPages'] ?? json['total_pages'] ?? 1,
    );
  }
}

/// Resumo de Matches
class MatchSummary {
  final int total;
  final int pending;
  final int accepted;
  final int ignored;
  final int highScore;

  MatchSummary({
    required this.total,
    required this.pending,
    required this.accepted,
    required this.ignored,
    required this.highScore,
  });

  factory MatchSummary.fromJson(Map<String, dynamic> json) {
    return MatchSummary(
      total: json['total'] ?? 0,
      pending: json['pending'] ?? 0,
      accepted: json['accepted'] ?? 0,
      ignored: json['ignored'] ?? 0,
      highScore: json['highScore'] ?? json['high_score'] ?? 0,
    );
  }
}

/// Resumo com Matches Recentes
class MatchSummaryWithRecent extends MatchSummary {
  final List<Match> recent;

  MatchSummaryWithRecent({
    required super.total,
    required super.pending,
    required super.accepted,
    required super.ignored,
    required super.highScore,
    required this.recent,
  });

  factory MatchSummaryWithRecent.fromJson(Map<String, dynamic> json) {
    return MatchSummaryWithRecent(
      total: json['total'] ?? 0,
      pending: json['pending'] ?? 0,
      accepted: json['accepted'] ?? 0,
      ignored: json['ignored'] ?? 0,
      highScore: json['highScore'] ?? json['high_score'] ?? 0,
      recent: json['recent'] != null
          ? (json['recent'] as List)
                .map((e) => Match.fromJson(_convertToMap(e)))
                .toList()
          : [],
    );
  }
}

/// Resposta de Aceitar Match
class AcceptMatchResponse {
  final String message;
  final Match match;

  AcceptMatchResponse({required this.message, required this.match});

  factory AcceptMatchResponse.fromJson(Map<String, dynamic> json) {
    return AcceptMatchResponse(
      message: json['message']?.toString() ?? '',
      match: Match.fromJson(_convertToMap(json['match'])),
    );
  }
}

/// Request para Ignorar Match
class IgnoreMatchRequest {
  final IgnoreReason reason;
  final String? notes;

  IgnoreMatchRequest({required this.reason, this.notes});

  Map<String, dynamic> toJson() {
    return {
      'reason': reason.value,
      if (notes != null && notes!.isNotEmpty) 'notes': notes,
    };
  }
}

/// Resposta de Ignorar Match
class IgnoreMatchResponse {
  final String message;
  final Match match;

  IgnoreMatchResponse({required this.message, required this.match});

  factory IgnoreMatchResponse.fromJson(Map<String, dynamic> json) {
    return IgnoreMatchResponse(
      message: json['message']?.toString() ?? '',
      match: Match.fromJson(_convertToMap(json['match'])),
    );
  }
}
