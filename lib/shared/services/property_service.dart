import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import '../../core/constants/api_constants.dart';
import 'secure_storage_service.dart';

/// Tipos de propriedade
enum PropertyType {
  house('house', 'Casa'),
  apartment('apartment', 'Apartamento'),
  commercial('commercial', 'Comercial'),
  land('land', 'Terreno'),
  rural('rural', 'Rural');

  final String value;
  final String label;

  const PropertyType(this.value, this.label);

  static PropertyType? fromString(String? value) {
    if (value == null) return null;
    try {
      return PropertyType.values.firstWhere((e) => e.value == value);
    } catch (e) {
      return null;
    }
  }
}

/// Status de propriedade
enum PropertyStatus {
  draft('draft', 'Rascunho'),
  available('available', 'Disponível'),
  rented('rented', 'Alugado'),
  sold('sold', 'Vendido'),
  maintenance('maintenance', 'Em Manutenção');

  final String value;
  final String label;

  const PropertyStatus(this.value, this.label);

  static PropertyStatus? fromString(String? value) {
    if (value == null) return null;
    try {
      return PropertyStatus.values.firstWhere((e) => e.value == value);
    } catch (e) {
      return null;
    }
  }
}

/// Modelo de Property
class Property {
  final String id;
  final String? code;
  final String title;
  final String description;
  final PropertyType type;
  final PropertyStatus status;
  final String address;
  final String street;
  final String number;
  final String? complement;
  final String city;
  final String state;
  final String zipCode;
  final String neighborhood;
  final double totalArea;
  final double? builtArea;
  final int? bedrooms;
  final int? bathrooms;
  final int? parkingSpaces;
  final double? salePrice;
  final double? rentPrice;
  final double? condominiumFee;
  final double? iptu;
  final List<String> features;
  final bool isActive;
  final bool isFeatured;
  final bool? isAvailableForSite;
  final String companyId;
  final String responsibleUserId;
  final String? capturedById;
  final PropertyCapturedBy? capturedBy;
  final String createdAt;
  final String updatedAt;
  final int? imageCount;
  final List<PropertyImage>? images;
  final PropertyImage? mainImage;
  final List<PropertyClient>? clients;
  final int? clientCount;
  final PropertyOwner? owner;
  final bool? acceptsNegotiation;
  final double? minSalePrice;
  final double? minRentPrice;
  final String? offerBelowMinSaleAction;
  final String? offerBelowMinRentAction;
  final int? totalOffersCount;
  final int? pendingOffersCount;
  final int? acceptedOffersCount;
  final int? rejectedOffersCount;
  final bool? hasPendingOffers;
  // Campos MCMV
  final bool? mcmvEligible;
  final String? mcmvIncomeRange; // 'faixa1' | 'faixa2' | 'faixa3'
  final double? mcmvMaxValue;
  final double? mcmvSubsidy;
  final List<String>? mcmvDocumentation;
  final String? mcmvNotes;

  Property({
    required this.id,
    this.code,
    required this.title,
    required this.description,
    required this.type,
    required this.status,
    required this.address,
    required this.street,
    required this.number,
    this.complement,
    required this.city,
    required this.state,
    required this.zipCode,
    required this.neighborhood,
    required this.totalArea,
    this.builtArea,
    this.bedrooms,
    this.bathrooms,
    this.parkingSpaces,
    this.salePrice,
    this.rentPrice,
    this.condominiumFee,
    this.iptu,
    required this.features,
    required this.isActive,
    required this.isFeatured,
    this.isAvailableForSite,
    required this.companyId,
    required this.responsibleUserId,
    this.capturedById,
    this.capturedBy,
    required this.createdAt,
    required this.updatedAt,
    this.imageCount,
    this.images,
    this.mainImage,
    this.clients,
    this.clientCount,
    this.owner,
    this.acceptsNegotiation,
    this.minSalePrice,
    this.minRentPrice,
    this.offerBelowMinSaleAction,
    this.offerBelowMinRentAction,
    this.totalOffersCount,
    this.pendingOffersCount,
    this.acceptedOffersCount,
    this.rejectedOffersCount,
    this.hasPendingOffers,
    this.mcmvEligible,
    this.mcmvIncomeRange,
    this.mcmvMaxValue,
    this.mcmvSubsidy,
    this.mcmvDocumentation,
    this.mcmvNotes,
  });

  factory Property.fromJson(Map<String, dynamic> json) {
    // Helper para converter valores que podem vir como String ou num
    double? _parseDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      if (value is String) {
        final parsed = double.tryParse(value);
        return parsed;
      }
      return null;
    }

    int? _parseInt(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value);
        return parsed;
      }
      return null;
    }

    return Property(
      id: json['id']?.toString() ?? '',
      code: json['code']?.toString(),
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      type: PropertyType.fromString(json['type']?.toString()) ?? PropertyType.house,
      status: PropertyStatus.fromString(json['status']?.toString()) ?? PropertyStatus.draft,
      address: json['address']?.toString() ?? '',
      street: json['street']?.toString() ?? '',
      number: json['number']?.toString() ?? '',
      complement: json['complement']?.toString(),
      city: json['city']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      zipCode: json['zipCode']?.toString() ?? json['zip_code']?.toString() ?? '',
      neighborhood: json['neighborhood']?.toString() ?? '',
      totalArea: _parseDouble(json['totalArea'] ?? json['total_area']) ?? 0.0,
      builtArea: _parseDouble(json['builtArea'] ?? json['built_area']),
      bedrooms: _parseInt(json['bedrooms']),
      bathrooms: _parseInt(json['bathrooms']),
      parkingSpaces: _parseInt(json['parkingSpaces'] ?? json['parking_spaces']),
      salePrice: _parseDouble(json['salePrice'] ?? json['sale_price']),
      rentPrice: _parseDouble(json['rentPrice'] ?? json['rent_price']),
      condominiumFee: _parseDouble(json['condominiumFee'] ?? json['condominium_fee']),
      iptu: _parseDouble(json['iptu']),
      features: json['features'] != null
          ? List<String>.from((json['features'] as List).map((e) => e.toString()))
          : [],
      isActive: json['isActive'] as bool? ?? json['is_active'] as bool? ?? false,
      isFeatured: json['isFeatured'] as bool? ?? json['is_featured'] as bool? ?? false,
      isAvailableForSite: json['isAvailableForSite'] as bool? ?? json['is_available_for_site'] as bool?,
      companyId: json['companyId']?.toString() ?? json['company_id']?.toString() ?? '',
      responsibleUserId: json['responsibleUserId']?.toString() ?? json['responsible_user_id']?.toString() ?? '',
      capturedById: json['capturedById']?.toString() ?? json['captured_by_id']?.toString(),
      capturedBy: json['capturedBy'] != null
          ? PropertyCapturedBy.fromJson(json['capturedBy'] as Map<String, dynamic>)
          : json['captured_by'] != null
              ? PropertyCapturedBy.fromJson(json['captured_by'] as Map<String, dynamic>)
              : null,
      createdAt: json['createdAt']?.toString() ?? json['created_at']?.toString() ?? '',
      updatedAt: json['updatedAt']?.toString() ?? json['updated_at']?.toString() ?? '',
      imageCount: _parseInt(json['imageCount'] ?? json['image_count']),
      images: json['images'] != null
          ? (json['images'] as List).map((e) => PropertyImage.fromJson(e as Map<String, dynamic>)).toList()
          : null,
      mainImage: json['mainImage'] != null
          ? PropertyImage.fromJson(json['mainImage'] as Map<String, dynamic>)
          : json['main_image'] != null
              ? PropertyImage.fromJson(json['main_image'] as Map<String, dynamic>)
              : null,
      clients: json['clients'] != null
          ? (json['clients'] as List).map((e) => PropertyClient.fromJson(e as Map<String, dynamic>)).toList()
          : null,
      clientCount: _parseInt(json['clientCount'] ?? json['client_count']),
      owner: json['owner'] != null
          ? PropertyOwner.fromJson(json['owner'] as Map<String, dynamic>)
          : null,
      acceptsNegotiation: json['acceptsNegotiation'] as bool? ?? json['accepts_negotiation'] as bool?,
      minSalePrice: _parseDouble(json['minSalePrice'] ?? json['min_sale_price']),
      minRentPrice: _parseDouble(json['minRentPrice'] ?? json['min_rent_price']),
      offerBelowMinSaleAction: json['offerBelowMinSaleAction']?.toString() ?? json['offer_below_min_sale_action']?.toString(),
      offerBelowMinRentAction: json['offerBelowMinRentAction']?.toString() ?? json['offer_below_min_rent_action']?.toString(),
      totalOffersCount: _parseInt(json['totalOffersCount'] ?? json['total_offers_count']),
      pendingOffersCount: _parseInt(json['pendingOffersCount'] ?? json['pending_offers_count']),
      acceptedOffersCount: _parseInt(json['acceptedOffersCount'] ?? json['accepted_offers_count']),
      rejectedOffersCount: _parseInt(json['rejectedOffersCount'] ?? json['rejected_offers_count']),
      hasPendingOffers: json['hasPendingOffers'] as bool? ?? json['has_pending_offers'] as bool?,
      mcmvEligible: json['mcmvEligible'] as bool? ?? json['mcmv_eligible'] as bool?,
      mcmvIncomeRange: json['mcmvIncomeRange']?.toString() ?? json['mcmv_income_range']?.toString(),
      mcmvMaxValue: _parseDouble(json['mcmvMaxValue'] ?? json['mcmv_max_value']),
      mcmvSubsidy: _parseDouble(json['mcmvSubsidy'] ?? json['mcmv_subsidy']),
      mcmvDocumentation: json['mcmvDocumentation'] != null
          ? List<String>.from((json['mcmvDocumentation'] as List).map((e) => e.toString()))
          : json['mcmv_documentation'] != null
              ? List<String>.from((json['mcmv_documentation'] as List).map((e) => e.toString()))
              : null,
      mcmvNotes: json['mcmvNotes']?.toString() ?? json['mcmv_notes']?.toString(),
    );
  }
}

class PropertyCapturedBy {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? avatar;

  PropertyCapturedBy({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.avatar,
  });

  factory PropertyCapturedBy.fromJson(Map<String, dynamic> json) {
    return PropertyCapturedBy(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString(),
      avatar: json['avatar']?.toString(),
    );
  }
}

class PropertyImage {
  final String id;
  final String url;
  final String? thumbnailUrl;
  final String category;
  final bool isMain;
  final String createdAt;

  PropertyImage({
    required this.id,
    required this.url,
    this.thumbnailUrl,
    required this.category,
    required this.isMain,
    required this.createdAt,
  });

  factory PropertyImage.fromJson(Map<String, dynamic> json) {
    return PropertyImage(
      id: json['id']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      thumbnailUrl: json['thumbnailUrl']?.toString() ?? json['thumbnail_url']?.toString(),
      category: json['category']?.toString() ?? 'general',
      isMain: json['isMain'] as bool? ?? json['is_main'] as bool? ?? false,
      createdAt: json['createdAt']?.toString() ?? json['created_at']?.toString() ?? '',
    );
  }
}

class PropertyClient {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String type;
  final String status;
  final String interestType;
  final String? notes;
  final String? contactedAt;
  final String createdAt;
  final String responsibleUserName;

  PropertyClient({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.type,
    required this.status,
    required this.interestType,
    this.notes,
    this.contactedAt,
    required this.createdAt,
    required this.responsibleUserName,
  });

  factory PropertyClient.fromJson(Map<String, dynamic> json) {
    return PropertyClient(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      interestType: json['interestType']?.toString() ?? json['interest_type']?.toString() ?? '',
      notes: json['notes']?.toString(),
      contactedAt: json['contactedAt']?.toString() ?? json['contacted_at']?.toString(),
      createdAt: json['createdAt']?.toString() ?? json['created_at']?.toString() ?? '',
      responsibleUserName: json['responsibleUserName']?.toString() ?? json['responsible_user_name']?.toString() ?? '',
    );
  }
}

class PropertyOwner {
  final String? name;
  final String? email;
  final String? phone;
  final String? document;
  final String? address;

  PropertyOwner({
    this.name,
    this.email,
    this.phone,
    this.document,
    this.address,
  });

  factory PropertyOwner.fromJson(Map<String, dynamic> json) {
    return PropertyOwner(
      name: json['name']?.toString(),
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
      document: json['document']?.toString(),
      address: json['address']?.toString(),
    );
  }
}

/// Resposta de listagem de propriedades
class PropertiesListResponse {
  final List<Property> data;
  final int total;
  final int page;
  final int limit;
  final int totalPages;

  PropertiesListResponse({
    required this.data,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });

  factory PropertiesListResponse.fromJson(Map<String, dynamic> json) {
    final dataList = json['data'] as List<dynamic>? ?? [];
    return PropertiesListResponse(
      data: dataList.map((e) => Property.fromJson(e as Map<String, dynamic>)).toList(),
      total: json['total'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      limit: json['limit'] as int? ?? 50,
      totalPages: json['totalPages'] as int? ?? json['total_pages'] as int? ?? 1,
    );
  }
}

/// Filtros de propriedades
class PropertyFilters {
  final PropertyType? type;
  final PropertyStatus? status;
  final String? city;
  final String? state;
  final String? neighborhood;
  final double? minPrice;
  final double? maxPrice;
  final double? minArea;
  final double? maxArea;
  final int? bedrooms;
  final int? bathrooms;
  final int? parkingSpaces;
  final List<String>? features;
  final bool? isActive;
  final bool? isFeatured;
  final String? companyId;
  final String? responsibleUserId;
  final String? search;
  final bool? onlyMyData;

  PropertyFilters({
    this.type,
    this.status,
    this.city,
    this.state,
    this.neighborhood,
    this.minPrice,
    this.maxPrice,
    this.minArea,
    this.maxArea,
    this.bedrooms,
    this.bathrooms,
    this.parkingSpaces,
    this.features,
    this.isActive,
    this.isFeatured,
    this.companyId,
    this.responsibleUserId,
    this.search,
    this.onlyMyData,
  });

  Map<String, dynamic> toQueryParams() {
    final params = <String, dynamic>{};
    if (type != null) params['type'] = type!.value;
    if (status != null) params['status'] = status!.value;
    if (city != null) params['city'] = city;
    if (state != null) params['state'] = state;
    if (neighborhood != null) params['neighborhood'] = neighborhood;
    if (minPrice != null) params['minPrice'] = minPrice;
    if (maxPrice != null) params['maxPrice'] = maxPrice;
    if (minArea != null) params['minArea'] = minArea;
    if (maxArea != null) params['maxArea'] = maxArea;
    if (bedrooms != null) params['bedrooms'] = bedrooms;
    if (bathrooms != null) params['bathrooms'] = bathrooms;
    if (parkingSpaces != null) params['parkingSpaces'] = parkingSpaces;
    if (features != null && features!.isNotEmpty) params['features'] = features;
    if (isActive != null) params['isActive'] = isActive;
    if (isFeatured != null) params['isFeatured'] = isFeatured;
    if (companyId != null) params['companyId'] = companyId;
    if (responsibleUserId != null) params['responsibleUserId'] = responsibleUserId;
    if (search != null && search!.isNotEmpty) params['search'] = search;
    if (onlyMyData != null) params['onlyMyData'] = onlyMyData;
    return params;
  }

  PropertyFilters copyWith({
    PropertyType? type,
    PropertyStatus? status,
    String? city,
    String? state,
    String? neighborhood,
    double? minPrice,
    double? maxPrice,
    double? minArea,
    double? maxArea,
    int? bedrooms,
    int? bathrooms,
    int? parkingSpaces,
    List<String>? features,
    bool? isActive,
    bool? isFeatured,
    String? companyId,
    String? responsibleUserId,
    String? search,
    bool? onlyMyData,
  }) {
    return PropertyFilters(
      type: type ?? this.type,
      status: status ?? this.status,
      city: city ?? this.city,
      state: state ?? this.state,
      neighborhood: neighborhood ?? this.neighborhood,
      minPrice: minPrice ?? this.minPrice,
      maxPrice: maxPrice ?? this.maxPrice,
      minArea: minArea ?? this.minArea,
      maxArea: maxArea ?? this.maxArea,
      bedrooms: bedrooms ?? this.bedrooms,
      bathrooms: bathrooms ?? this.bathrooms,
      parkingSpaces: parkingSpaces ?? this.parkingSpaces,
      features: features ?? this.features,
      isActive: isActive ?? this.isActive,
      isFeatured: isFeatured ?? this.isFeatured,
      companyId: companyId ?? this.companyId,
      responsibleUserId: responsibleUserId ?? this.responsibleUserId,
      search: search ?? this.search,
      onlyMyData: onlyMyData ?? this.onlyMyData,
    );
  }
}

/// Serviço de Propriedades
class PropertyService {
  PropertyService._();

  static final PropertyService instance = PropertyService._();
  final ApiService _apiService = ApiService.instance;

  /// Lista propriedades com filtros e paginação
  Future<ApiResponse<PropertiesListResponse>> getProperties({
    int page = 1,
    int limit = 50,
    PropertyFilters? filters,
  }) async {
    debugPrint('🏠 [PROPERTY_SERVICE] Listando propriedades');
    debugPrint('   - page: $page');
    debugPrint('   - limit: $limit');

    try {
      final queryParams = <String, dynamic>{
        'page': page.toString(),
        'limit': limit.toString(),
      };

      if (filters != null) {
        queryParams.addAll(filters.toQueryParams());
      }

      final response = await _apiService.get<Map<String, dynamic>>(
        '/properties',
        queryParameters: queryParams.map((k, v) => MapEntry(k, v.toString())),
      );

      if (response.success && response.data != null) {
        try {
          final listResponse = PropertiesListResponse.fromJson(response.data!);
          debugPrint('✅ [PROPERTY_SERVICE] ${listResponse.data.length} propriedades encontradas');
          return ApiResponse.success(
            data: listResponse,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [PROPERTY_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao listar propriedades',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Busca propriedade por ID
  Future<ApiResponse<Property>> getPropertyById(String id) async {
    debugPrint('🏠 [PROPERTY_SERVICE] Buscando propriedade: $id');

    try {
      final response = await _apiService.get<Map<String, dynamic>>('/properties/$id');

      if (response.success && response.data != null) {
        try {
          final property = Property.fromJson(response.data!);
          debugPrint('✅ [PROPERTY_SERVICE] Propriedade encontrada: ${property.title}');
          return ApiResponse.success(
            data: property,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [PROPERTY_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Propriedade não encontrada',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Cria nova propriedade
  Future<ApiResponse<Property>> createProperty(Map<String, dynamic> data) async {
    debugPrint('🏠 [PROPERTY_SERVICE] Criando propriedade');

    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        '/properties',
        body: data,
      );

      if (response.success && response.data != null) {
        try {
          final property = Property.fromJson(response.data!);
          debugPrint('✅ [PROPERTY_SERVICE] Propriedade criada: ${property.id}');
          return ApiResponse.success(
            data: property,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [PROPERTY_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar propriedade',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Atualiza propriedade
  Future<ApiResponse<Property>> updateProperty(String id, Map<String, dynamic> data) async {
    debugPrint('🏠 [PROPERTY_SERVICE] Atualizando propriedade: $id');

    try {
      final response = await _apiService.patch<Map<String, dynamic>>(
        '/properties/$id',
        body: data,
      );

      if (response.success && response.data != null) {
        try {
          final property = Property.fromJson(response.data!);
          debugPrint('✅ [PROPERTY_SERVICE] Propriedade atualizada: ${property.id}');
          return ApiResponse.success(
            data: property,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [PROPERTY_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar propriedade',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Exclui propriedade
  Future<ApiResponse<void>> deleteProperty(String id) async {
    debugPrint('🏠 [PROPERTY_SERVICE] Excluindo propriedade: $id');

    try {
      final response = await _apiService.delete('/properties/$id');

      if (response.success) {
        debugPrint('✅ [PROPERTY_SERVICE] Propriedade excluída: $id');
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao excluir propriedade',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Ativa propriedade
  Future<ApiResponse<Property>> activateProperty(String id) async {
    debugPrint('🏠 [PROPERTY_SERVICE] Ativando propriedade: $id');

    try {
      final response = await _apiService.patch<Map<String, dynamic>>(
        '/properties/$id/activate',
      );

      if (response.success && response.data != null) {
        try {
          final property = Property.fromJson(response.data!);
          debugPrint('✅ [PROPERTY_SERVICE] Propriedade ativada: $id');
          return ApiResponse.success(
            data: property,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [PROPERTY_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao ativar propriedade',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Desativa propriedade
  Future<ApiResponse<Property>> deactivateProperty(String id) async {
    debugPrint('🏠 [PROPERTY_SERVICE] Desativando propriedade: $id');

    try {
      final response = await _apiService.patch<Map<String, dynamic>>(
        '/properties/$id/deactivate',
      );

      if (response.success && response.data != null) {
        try {
          final property = Property.fromJson(response.data!);
          debugPrint('✅ [PROPERTY_SERVICE] Propriedade desativada: $id');
          return ApiResponse.success(
            data: property,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [PROPERTY_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao desativar propriedade',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Marca propriedade como vendida
  Future<ApiResponse<Property>> markAsSold(String id, {String? notes}) async {
    debugPrint('🏠 [PROPERTY_SERVICE] Marcando propriedade como vendida: $id');

    try {
      final response = await _apiService.patch<Map<String, dynamic>>(
        '/properties/$id/mark-as-sold',
        body: notes != null ? {'notes': notes} : null,
      );

      if (response.success && response.data != null) {
        try {
          final property = Property.fromJson(response.data!);
          debugPrint('✅ [PROPERTY_SERVICE] Propriedade marcada como vendida: $id');
          return ApiResponse.success(
            data: property,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [PROPERTY_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao marcar como vendida',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Marca propriedade como alugada
  Future<ApiResponse<Property>> markAsRented(String id, {String? notes}) async {
    debugPrint('🏠 [PROPERTY_SERVICE] Marcando propriedade como alugada: $id');

    try {
      final response = await _apiService.patch<Map<String, dynamic>>(
        '/properties/$id/mark-as-rented',
        body: notes != null ? {'notes': notes} : null,
      );

      if (response.success && response.data != null) {
        try {
          final property = Property.fromJson(response.data!);
          debugPrint('✅ [PROPERTY_SERVICE] Propriedade marcada como alugada: $id');
          return ApiResponse.success(
            data: property,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [PROPERTY_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao marcar como alugada',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Busca inteligente de propriedades
  Future<ApiResponse<IntelligentSearchResponse>> intelligentSearch({
    String? clientId,
    PropertyType? type,
    String? operation, // 'rent' | 'sale'
    String? city,
    String? state,
    String? neighborhood,
    double? minValue,
    double? maxValue,
    int? minBedrooms,
    int? minBathrooms,
    int? minParkingSpaces,
    double? minArea,
    double? maxArea,
    List<String>? features,
    bool? onlyMyProperties,
    bool? searchInGroupCompanies,
    bool? includeOtherBrokers,
    int page = 1,
    int limit = 50,
  }) async {
    debugPrint('🔍 [PROPERTY_SERVICE] Busca inteligente');

    try {
      final queryParams = <String, dynamic>{
        'page': page.toString(),
        'limit': limit.toString(),
      };

      if (clientId != null) queryParams['clientId'] = clientId;
      if (type != null) queryParams['type'] = type.value;
      if (operation != null) queryParams['operation'] = operation;
      if (city != null) queryParams['city'] = city;
      if (state != null) queryParams['state'] = state;
      if (neighborhood != null) queryParams['neighborhood'] = neighborhood;
      if (minValue != null) queryParams['minValue'] = minValue.toString();
      if (maxValue != null) queryParams['maxValue'] = maxValue.toString();
      if (minBedrooms != null) queryParams['minBedrooms'] = minBedrooms.toString();
      if (minBathrooms != null) queryParams['minBathrooms'] = minBathrooms.toString();
      if (minParkingSpaces != null) queryParams['minParkingSpaces'] = minParkingSpaces.toString();
      if (minArea != null) queryParams['minArea'] = minArea.toString();
      if (maxArea != null) queryParams['maxArea'] = maxArea.toString();
      if (features != null && features.isNotEmpty) queryParams['features'] = features;
      if (onlyMyProperties != null) queryParams['onlyMyProperties'] = onlyMyProperties.toString();
      if (searchInGroupCompanies != null) queryParams['searchInGroupCompanies'] = searchInGroupCompanies.toString();
      if (includeOtherBrokers != null) queryParams['includeOtherBrokers'] = includeOtherBrokers.toString();

      final response = await _apiService.get<Map<String, dynamic>>(
        '/properties/search/intelligent',
        queryParameters: queryParams.map((k, v) => MapEntry(k, v.toString())),
      );

      if (response.success && response.data != null) {
        try {
          final searchResponse = IntelligentSearchResponse.fromJson(response.data!);
          debugPrint('✅ [PROPERTY_SERVICE] Busca inteligente: ${searchResponse.results.length} resultados');
          return ApiResponse.success(
            data: searchResponse,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [PROPERTY_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro na busca inteligente',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Busca estatísticas de propriedades
  Future<ApiResponse<PropertyStats>> getPropertyStats() async {
    debugPrint('📊 [PROPERTY_SERVICE] Buscando estatísticas');

    try {
      final response = await _apiService.get<Map<String, dynamic>>('/properties/stats');

      if (response.success && response.data != null) {
        try {
          final stats = PropertyStats.fromJson(response.data!);
          debugPrint('✅ [PROPERTY_SERVICE] Estatísticas carregadas');
          return ApiResponse.success(
            data: stats,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [PROPERTY_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar estatísticas',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Exporta propriedades
  Future<ApiResponse<List<int>>> exportProperties({
    String format = 'xlsx', // 'xlsx' | 'csv'
    String? type,
    String? status,
  }) async {
    debugPrint('📤 [PROPERTY_SERVICE] Exportando propriedades (formato: $format)');

    try {
      final queryParams = <String, String>{
        'format': format,
      };
      if (type != null) queryParams['type'] = type;
      if (status != null) queryParams['status'] = status;

      // Para download de arquivo, precisamos usar http diretamente
      final token = await SecureStorageService.instance.getAccessToken();
      if (token == null || token.isEmpty) {
        return ApiResponse.error(
          message: 'Token de autenticação não encontrado',
          statusCode: 401,
        );
      }

      final uri = Uri.parse('${ApiConstants.baseApiUrl}/properties/export')
          .replace(queryParameters: queryParams);
      
      final httpResponse = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 60));

      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        debugPrint('✅ [PROPERTY_SERVICE] Propriedades exportadas');
        return ApiResponse.success(
          data: httpResponse.bodyBytes.toList(),
          statusCode: httpResponse.statusCode,
        );
      }

      return ApiResponse.error(
        message: 'Erro ao exportar propriedades',
        statusCode: httpResponse.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Importa propriedades
  Future<ApiResponse<PropertyImportResponse>> importProperties({
    required List<int> fileBytes,
    String? fileName,
    String? format,
  }) async {
    debugPrint('📥 [PROPERTY_SERVICE] Importando propriedades');

    try {
      final token = await SecureStorageService.instance.getAccessToken();
      if (token == null || token.isEmpty) {
        return ApiResponse.error(
          message: 'Token de autenticação não encontrado',
          statusCode: 401,
        );
      }

      final uri = Uri.parse('${ApiConstants.baseApiUrl}/properties/import');
      final request = http.MultipartRequest('POST', uri);

      request.headers['Authorization'] = 'Bearer $token';
      
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: fileName ?? 'propriedades.xlsx',
        ),
      );
      
      if (format != null) {
        request.fields['format'] = format;
      }

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 120),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
          final importResponse = PropertyImportResponse.fromJson(jsonData);
          debugPrint('✅ [PROPERTY_SERVICE] Importação concluída: ${importResponse.success} sucessos, ${importResponse.failed} falhas');
          return ApiResponse.success(
            data: importResponse,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [PROPERTY_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar resposta: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: 'Erro ao importar propriedades',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}

/// Resposta de importação de propriedades
class PropertyImportResponse {
  final int total;
  final int success;
  final int failed;
  final List<Property> properties;
  final List<PropertyImportError> errors;
  final bool hasErrorFile;
  final String? errorSpreadsheetBase64;

  PropertyImportResponse({
    required this.total,
    required this.success,
    required this.failed,
    required this.properties,
    required this.errors,
    this.hasErrorFile = false,
    this.errorSpreadsheetBase64,
  });

  factory PropertyImportResponse.fromJson(Map<String, dynamic> json) {
    return PropertyImportResponse(
      total: (json['total'] as num?)?.toInt() ?? 0,
      success: (json['success'] as num?)?.toInt() ?? 0,
      failed: (json['failed'] as num?)?.toInt() ?? 0,
      properties: (json['properties'] as List<dynamic>?)
              ?.map((e) => Property.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      errors: (json['errors'] as List<dynamic>?)
              ?.map((e) => PropertyImportError.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      hasErrorFile: json['hasErrorFile'] as bool? ?? false,
      errorSpreadsheetBase64: json['errorSpreadsheetBase64']?.toString(),
    );
  }
}

class PropertyImportError {
  final int row;
  final String property;
  final List<String> errors;

  PropertyImportError({
    required this.row,
    required this.property,
    required this.errors,
  });

  factory PropertyImportError.fromJson(Map<String, dynamic> json) {
    return PropertyImportError(
      row: (json['row'] as num?)?.toInt() ?? 0,
      property: json['property']?.toString() ?? '',
      errors: (json['errors'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

/// Resposta de busca inteligente
class IntelligentSearchResponse {
  final List<IntelligentSearchResult> results;
  final int total;
  final int page;
  final int limit;
  final int totalPages;
  final IntelligentSearchStats searchStats;

  IntelligentSearchResponse({
    required this.results,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
    required this.searchStats,
  });

  factory IntelligentSearchResponse.fromJson(Map<String, dynamic> json) {
    return IntelligentSearchResponse(
      results: (json['results'] as List<dynamic>?)
              ?.map((e) => IntelligentSearchResult.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      total: json['total'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      limit: json['limit'] as int? ?? 50,
      totalPages: json['totalPages'] as int? ?? json['total_pages'] as int? ?? 1,
      searchStats: IntelligentSearchStats.fromJson(
        json['searchStats'] as Map<String, dynamic>? ?? {},
      ),
    );
  }
}

class IntelligentSearchResult {
  final Property property;
  final double matchScore;
  final List<String> matchReasons;
  final IntelligentSearchBroker responsibleBroker;
  final IntelligentSearchCompany company;

  IntelligentSearchResult({
    required this.property,
    required this.matchScore,
    required this.matchReasons,
    required this.responsibleBroker,
    required this.company,
  });

  factory IntelligentSearchResult.fromJson(Map<String, dynamic> json) {
    return IntelligentSearchResult(
      property: Property.fromJson(json['property'] as Map<String, dynamic>),
      matchScore: (json['matchScore'] as num?)?.toDouble() ?? 0.0,
      matchReasons: (json['matchReasons'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      responsibleBroker: IntelligentSearchBroker.fromJson(
        json['responsibleBroker'] as Map<String, dynamic>,
      ),
      company: IntelligentSearchCompany.fromJson(
        json['company'] as Map<String, dynamic>,
      ),
    );
  }
}

class IntelligentSearchBroker {
  final String id;
  final String name;
  final String email;

  IntelligentSearchBroker({
    required this.id,
    required this.name,
    required this.email,
  });

  factory IntelligentSearchBroker.fromJson(Map<String, dynamic> json) {
    return IntelligentSearchBroker(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
    );
  }
}

class IntelligentSearchCompany {
  final String id;
  final String name;

  IntelligentSearchCompany({
    required this.id,
    required this.name,
  });

  factory IntelligentSearchCompany.fromJson(Map<String, dynamic> json) {
    return IntelligentSearchCompany(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }
}

class IntelligentSearchStats {
  final int totalFound;
  final int fromMyProperties;
  final int fromOtherBrokers;
  final int fromGroupCompanies;

  IntelligentSearchStats({
    required this.totalFound,
    required this.fromMyProperties,
    required this.fromOtherBrokers,
    required this.fromGroupCompanies,
  });

  factory IntelligentSearchStats.fromJson(Map<String, dynamic> json) {
    return IntelligentSearchStats(
      totalFound: json['totalFound'] as int? ?? 0,
      fromMyProperties: json['fromMyProperties'] as int? ?? 0,
      fromOtherBrokers: json['fromOtherBrokers'] as int? ?? 0,
      fromGroupCompanies: json['fromGroupCompanies'] as int? ?? 0,
    );
  }
}

/// Estatísticas de propriedades
class PropertyStats {
  final int total;
  final int available;
  final int rented;
  final int sold;
  final Map<String, int> byType;
  final Map<String, int> byStatus;

  PropertyStats({
    required this.total,
    required this.available,
    required this.rented,
    required this.sold,
    required this.byType,
    required this.byStatus,
  });

  factory PropertyStats.fromJson(Map<String, dynamic> json) {
    return PropertyStats(
      total: json['total'] as int? ?? 0,
      available: json['available'] as int? ?? 0,
      rented: json['rented'] as int? ?? 0,
      sold: json['sold'] as int? ?? 0,
      byType: (json['byType'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as int? ?? 0)) ??
          {},
      byStatus: (json['byStatus'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as int? ?? 0)) ??
          {},
    );
  }
}

