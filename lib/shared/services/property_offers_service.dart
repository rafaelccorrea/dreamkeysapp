import 'package:flutter/foundation.dart';
import 'api_service.dart';

/// Modelo de oferta de propriedade
class PropertyOffer {
  final String id;
  final String propertyId;
  final String publicUserId;
  final PropertyOfferPublicUser? publicUser;
  final String type; // 'sale' | 'rental'
  final String status; // 'pending' | 'accepted' | 'rejected' | 'withdrawn' | 'expired'
  final double offeredValue;
  final String? message;
  final String? responseMessage;
  final String createdAt;
  final String updatedAt;
  final String? respondedAt;
  final String? respondedByUserId;
  final PropertyOfferProperty? property;

  PropertyOffer({
    required this.id,
    required this.propertyId,
    required this.publicUserId,
    this.publicUser,
    required this.type,
    required this.status,
    required this.offeredValue,
    this.message,
    this.responseMessage,
    required this.createdAt,
    required this.updatedAt,
    this.respondedAt,
    this.respondedByUserId,
    this.property,
  });

  factory PropertyOffer.fromJson(Map<String, dynamic> json) {
    return PropertyOffer(
      id: json['id']?.toString() ?? '',
      propertyId: json['propertyId']?.toString() ?? json['property_id']?.toString() ?? '',
      publicUserId: json['publicUserId']?.toString() ?? json['public_user_id']?.toString() ?? '',
      publicUser: json['publicUser'] != null
          ? PropertyOfferPublicUser.fromJson(json['publicUser'] as Map<String, dynamic>)
          : json['public_user'] != null
              ? PropertyOfferPublicUser.fromJson(json['public_user'] as Map<String, dynamic>)
              : null,
      type: json['type']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      offeredValue: (json['offeredValue'] as num?)?.toDouble() ?? (json['offered_value'] as num?)?.toDouble() ?? 0.0,
      message: json['message']?.toString(),
      responseMessage: json['responseMessage']?.toString() ?? json['response_message']?.toString(),
      createdAt: json['createdAt']?.toString() ?? json['created_at']?.toString() ?? '',
      updatedAt: json['updatedAt']?.toString() ?? json['updated_at']?.toString() ?? '',
      respondedAt: json['respondedAt']?.toString() ?? json['responded_at']?.toString(),
      respondedByUserId: json['respondedByUserId']?.toString() ?? json['responded_by_user_id']?.toString(),
      property: json['property'] != null
          ? PropertyOfferProperty.fromJson(json['property'] as Map<String, dynamic>)
          : null,
    );
  }
}

class PropertyOfferPublicUser {
  final String id;
  final String email;
  final String phone;

  PropertyOfferPublicUser({
    required this.id,
    required this.email,
    required this.phone,
  });

  factory PropertyOfferPublicUser.fromJson(Map<String, dynamic> json) {
    return PropertyOfferPublicUser(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
    );
  }
}

class PropertyOfferProperty {
  final String id;
  final String title;
  final double? salePrice;
  final double? rentPrice;
  final double? minSalePrice;
  final double? minRentPrice;

  PropertyOfferProperty({
    required this.id,
    required this.title,
    this.salePrice,
    this.rentPrice,
    this.minSalePrice,
    this.minRentPrice,
  });

  factory PropertyOfferProperty.fromJson(Map<String, dynamic> json) {
    return PropertyOfferProperty(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      salePrice: (json['salePrice'] as num?)?.toDouble() ?? (json['sale_price'] as num?)?.toDouble(),
      rentPrice: (json['rentPrice'] as num?)?.toDouble() ?? (json['rent_price'] as num?)?.toDouble(),
      minSalePrice: (json['minSalePrice'] as num?)?.toDouble() ?? (json['min_sale_price'] as num?)?.toDouble(),
      minRentPrice: (json['minRentPrice'] as num?)?.toDouble() ?? (json['min_rent_price'] as num?)?.toDouble(),
    );
  }
}

/// Filtros de ofertas
class OfferFilters {
  final String? propertyId;
  final String? status; // 'pending' | 'accepted' | 'rejected' | 'withdrawn' | 'expired'
  final String? type; // 'sale' | 'rental'

  OfferFilters({
    this.propertyId,
    this.status,
    this.type,
  });

  Map<String, dynamic> toQueryParams() {
    final params = <String, dynamic>{};
    if (propertyId != null) params['propertyId'] = propertyId;
    if (status != null) params['status'] = status;
    if (type != null) params['type'] = type;
    return params;
  }
}

/// Serviço de Ofertas de Propriedades
class PropertyOffersService {
  PropertyOffersService._();

  static final PropertyOffersService instance = PropertyOffersService._();
  final ApiService _apiService = ApiService.instance;

  /// Lista todas as ofertas com filtros
  Future<ApiResponse<List<PropertyOffer>>> getAllOffers({OfferFilters? filters}) async {
    debugPrint('💰 [OFFERS_SERVICE] Listando ofertas');

    try {
      final queryParams = filters?.toQueryParams() ?? <String, dynamic>{};

      final response = await _apiService.get<List<dynamic>>(
        '/properties/offers',
        queryParameters: queryParams.map((k, v) => MapEntry(k, v.toString())),
      );

      if (response.success && response.data != null) {
        try {
          final offers = (response.data as List)
              .map((e) => PropertyOffer.fromJson(e as Map<String, dynamic>))
              .toList();
          debugPrint('✅ [OFFERS_SERVICE] ${offers.length} ofertas encontradas');
          return ApiResponse.success(
            data: offers,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [OFFERS_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao listar ofertas',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [OFFERS_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Lista ofertas de uma propriedade específica
  Future<ApiResponse<List<PropertyOffer>>> getPropertyOffers(String propertyId) async {
    debugPrint('💰 [OFFERS_SERVICE] Listando ofertas da propriedade: $propertyId');

    try {
      final response = await _apiService.get<List<dynamic>>(
        '/properties/offers/property/$propertyId',
      );

      if (response.success && response.data != null) {
        try {
          final offers = (response.data as List)
              .map((e) => PropertyOffer.fromJson(e as Map<String, dynamic>))
              .toList();
          debugPrint('✅ [OFFERS_SERVICE] ${offers.length} ofertas encontradas');
          return ApiResponse.success(
            data: offers,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [OFFERS_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao listar ofertas',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [OFFERS_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Busca oferta por ID
  Future<ApiResponse<PropertyOffer>> getOfferById(String offerId) async {
    debugPrint('💰 [OFFERS_SERVICE] Buscando oferta: $offerId');

    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '/properties/offers/detail/$offerId',
      );

      if (response.success && response.data != null) {
        try {
          final offer = PropertyOffer.fromJson(response.data!);
          debugPrint('✅ [OFFERS_SERVICE] Oferta encontrada: $offerId');
          return ApiResponse.success(
            data: offer,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [OFFERS_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Oferta não encontrada',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [OFFERS_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Aceita ou rejeita uma oferta
  Future<ApiResponse<PropertyOffer>> updateOfferStatus({
    required String offerId,
    required String status, // 'accepted' | 'rejected'
    String? responseMessage,
  }) async {
    debugPrint('💰 [OFFERS_SERVICE] Atualizando status da oferta: $offerId -> $status');

    try {
      final data = <String, dynamic>{
        'status': status,
      };
      if (responseMessage != null) {
        data['responseMessage'] = responseMessage;
      }

      final response = await _apiService.put<Map<String, dynamic>>(
        '/properties/offers/detail/$offerId/status',
        body: data,
      );

      if (response.success && response.data != null) {
        try {
          final offer = PropertyOffer.fromJson(response.data!);
          debugPrint('✅ [OFFERS_SERVICE] Oferta atualizada: $offerId');
          return ApiResponse.success(
            data: offer,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [OFFERS_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar oferta',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [OFFERS_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}

