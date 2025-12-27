import 'package:flutter/foundation.dart';
import 'api_service.dart';

/// Modelo de oferta de propriedade
class PropertyOffer {
  final String id;
  final String propertyId;
  final String publicUserId;
  final PropertyOfferPublicUser? publicUser;
  final String type; // 'sale' | 'rental'
  final String
  status; // 'pending' | 'accepted' | 'rejected' | 'withdrawn' | 'expired'
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
    try {
      debugPrint('💰 [PROPERTY_OFFER] Iniciando fromJson');
      debugPrint('💰 [PROPERTY_OFFER] JSON recebido: $json');
      debugPrint('💰 [PROPERTY_OFFER] Chaves do JSON: ${json.keys.toList()}');

      final id = json['id']?.toString() ?? '';
      debugPrint('💰 [PROPERTY_OFFER] id: $id');

      final propertyId =
          json['propertyId']?.toString() ??
          json['property_id']?.toString() ??
          '';
      debugPrint('💰 [PROPERTY_OFFER] propertyId: $propertyId');

      final publicUserId =
          json['publicUserId']?.toString() ??
          json['public_user_id']?.toString() ??
          '';
      debugPrint('💰 [PROPERTY_OFFER] publicUserId: $publicUserId');

      PropertyOfferPublicUser? publicUser;
      if (json['publicUser'] != null) {
        debugPrint(
          '💰 [PROPERTY_OFFER] publicUser encontrado (camelCase), type: ${json['publicUser'].runtimeType}',
        );
        try {
          if (json['publicUser'] is Map<String, dynamic>) {
            publicUser = PropertyOfferPublicUser.fromJson(
              json['publicUser'] as Map<String, dynamic>,
            );
            debugPrint('💰 [PROPERTY_OFFER] publicUser parseado com sucesso');
          } else {
            debugPrint(
              '❌ [PROPERTY_OFFER] publicUser não é Map: ${json['publicUser'].runtimeType}, valor: ${json['publicUser']}',
            );
          }
        } catch (e, stackTrace) {
          debugPrint('❌ [PROPERTY_OFFER] Erro ao parsear publicUser: $e');
          debugPrint('📚 [PROPERTY_OFFER] StackTrace: $stackTrace');
        }
      } else if (json['public_user'] != null) {
        debugPrint(
          '💰 [PROPERTY_OFFER] public_user encontrado (snake_case), type: ${json['public_user'].runtimeType}',
        );
        try {
          if (json['public_user'] is Map<String, dynamic>) {
            publicUser = PropertyOfferPublicUser.fromJson(
              json['public_user'] as Map<String, dynamic>,
            );
            debugPrint('💰 [PROPERTY_OFFER] public_user parseado com sucesso');
          } else {
            debugPrint(
              '❌ [PROPERTY_OFFER] public_user não é Map: ${json['public_user'].runtimeType}, valor: ${json['public_user']}',
            );
          }
        } catch (e, stackTrace) {
          debugPrint('❌ [PROPERTY_OFFER] Erro ao parsear public_user: $e');
          debugPrint('📚 [PROPERTY_OFFER] StackTrace: $stackTrace');
        }
      }

      final type = json['type']?.toString() ?? '';
      debugPrint('💰 [PROPERTY_OFFER] type: $type');

      final status = json['status']?.toString() ?? '';
      debugPrint('💰 [PROPERTY_OFFER] status: $status');

      final offeredValue =
          (json['offeredValue'] as num?)?.toDouble() ??
          (json['offered_value'] as num?)?.toDouble() ??
          0.0;
      debugPrint('💰 [PROPERTY_OFFER] offeredValue: $offeredValue');

      PropertyOfferProperty? property;
      if (json['property'] != null) {
        debugPrint(
          '💰 [PROPERTY_OFFER] property encontrado, type: ${json['property'].runtimeType}',
        );
        try {
          if (json['property'] is Map<String, dynamic>) {
            property = PropertyOfferProperty.fromJson(
              json['property'] as Map<String, dynamic>,
            );
            debugPrint('💰 [PROPERTY_OFFER] property parseado com sucesso');
          } else {
            debugPrint(
              '❌ [PROPERTY_OFFER] property não é Map: ${json['property'].runtimeType}, valor: ${json['property']}',
            );
          }
        } catch (e, stackTrace) {
          debugPrint('❌ [PROPERTY_OFFER] Erro ao parsear property: $e');
          debugPrint('📚 [PROPERTY_OFFER] StackTrace: $stackTrace');
        }
      }

      final offer = PropertyOffer(
        id: id,
        propertyId: propertyId,
        publicUserId: publicUserId,
        publicUser: publicUser,
        type: type,
        status: status,
        offeredValue: offeredValue,
        message: json['message']?.toString(),
        responseMessage:
            json['responseMessage']?.toString() ??
            json['response_message']?.toString(),
        createdAt:
            json['createdAt']?.toString() ??
            json['created_at']?.toString() ??
            '',
        updatedAt:
            json['updatedAt']?.toString() ??
            json['updated_at']?.toString() ??
            '',
        respondedAt:
            json['respondedAt']?.toString() ?? json['responded_at']?.toString(),
        respondedByUserId:
            json['respondedByUserId']?.toString() ??
            json['responded_by_user_id']?.toString(),
        property: property,
      );

      debugPrint(
        '✅ [PROPERTY_OFFER] PropertyOffer criado com sucesso: ${offer.id}',
      );
      return offer;
    } catch (e, stackTrace) {
      debugPrint('❌ [PROPERTY_OFFER] Erro ao fazer fromJson: $e');
      debugPrint('📚 [PROPERTY_OFFER] StackTrace: $stackTrace');
      debugPrint('📋 [PROPERTY_OFFER] JSON que causou erro: $json');
      rethrow;
    }
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
      salePrice:
          (json['salePrice'] as num?)?.toDouble() ??
          (json['sale_price'] as num?)?.toDouble(),
      rentPrice:
          (json['rentPrice'] as num?)?.toDouble() ??
          (json['rent_price'] as num?)?.toDouble(),
      minSalePrice:
          (json['minSalePrice'] as num?)?.toDouble() ??
          (json['min_sale_price'] as num?)?.toDouble(),
      minRentPrice:
          (json['minRentPrice'] as num?)?.toDouble() ??
          (json['min_rent_price'] as num?)?.toDouble(),
    );
  }
}

/// Filtros de ofertas
class OfferFilters {
  final String? propertyId;
  final String?
  status; // 'pending' | 'accepted' | 'rejected' | 'withdrawn' | 'expired'
  final String? type; // 'sale' | 'rental'

  OfferFilters({this.propertyId, this.status, this.type});

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
  Future<ApiResponse<List<PropertyOffer>>> getAllOffers({
    OfferFilters? filters,
  }) async {
    debugPrint('💰 [OFFERS_SERVICE] Listando ofertas');
    debugPrint('💰 [OFFERS_SERVICE] Filtros: ${filters?.toQueryParams()}');

    try {
      final queryParams = filters?.toQueryParams() ?? <String, dynamic>{};

      debugPrint(
        '💰 [OFFERS_SERVICE] Fazendo requisição GET para /properties/offers',
      );
      debugPrint('💰 [OFFERS_SERVICE] Query params: $queryParams');

      final response = await _apiService.get<dynamic>(
        '/properties/offers',
        queryParameters: queryParams.map((k, v) => MapEntry(k, v.toString())),
      );

      debugPrint('💰 [OFFERS_SERVICE] Resposta recebida:');
      debugPrint('   - success: ${response.success}');
      debugPrint('   - statusCode: ${response.statusCode}');
      debugPrint('   - message: ${response.message}');
      debugPrint('   - data type: ${response.data?.runtimeType}');
      debugPrint('   - data is null: ${response.data == null}');

      if (response.success && response.data != null) {
        try {
          debugPrint('💰 [OFFERS_SERVICE] Iniciando parsing dos dados...');
          debugPrint(
            '💰 [OFFERS_SERVICE] response.data completo: ${response.data}',
          );

          // Verificar se os dados estão dentro de um objeto 'data' ou 'results'
          dynamic dataToParse = response.data;
          debugPrint(
            '💰 [OFFERS_SERVICE] dataToParse inicial type: ${dataToParse.runtimeType}',
          );

          // Se for um Map, tentar extrair 'data' ou 'results'
          if (dataToParse is Map<String, dynamic>) {
            debugPrint(
              '💰 [OFFERS_SERVICE] dataToParse é um Map, tentando extrair data/results',
            );
            debugPrint(
              '💰 [OFFERS_SERVICE] Chaves do Map: ${dataToParse.keys.toList()}',
            );
            dataToParse =
                dataToParse['data'] ?? dataToParse['results'] ?? dataToParse;
            debugPrint(
              '💰 [OFFERS_SERVICE] dataToParse após extração type: ${dataToParse.runtimeType}',
            );
          }

          // Garantir que é uma lista
          if (dataToParse is! List) {
            debugPrint(
              '❌ [OFFERS_SERVICE] Resposta não é uma lista: ${dataToParse.runtimeType}',
            );
            debugPrint('📋 [OFFERS_SERVICE] Dados recebidos: $dataToParse');
            return ApiResponse.error(
              message:
                  'Formato de resposta inválido: esperado List, recebido ${dataToParse.runtimeType}',
              statusCode: response.statusCode,
              data: response.error,
            );
          }

          final dataList = dataToParse;
          debugPrint(
            '💰 [OFFERS_SERVICE] dataToParse é uma List com ${dataList.length} itens',
          );

          final offers = <PropertyOffer>[];
          for (var i = 0; i < dataList.length; i++) {
            final e = dataList[i];
            debugPrint('💰 [OFFERS_SERVICE] Processando item $i:');
            debugPrint('   - type: ${e.runtimeType}');
            debugPrint('   - value: $e');

            // Verificar se cada item é um Map
            if (e is! Map<String, dynamic>) {
              debugPrint(
                '❌ [OFFERS_SERVICE] Item $i da lista não é Map: ${e.runtimeType}, valor: $e',
              );
              throw Exception(
                'Item $i da lista não é um Map<String, dynamic>, é ${e.runtimeType}',
              );
            }

            debugPrint(
              '💰 [OFFERS_SERVICE] Item $i é um Map, fazendo fromJson...',
            );
            try {
              final offer = PropertyOffer.fromJson(e);
              offers.add(offer);
              debugPrint(
                '✅ [OFFERS_SERVICE] Item $i parseado com sucesso: ${offer.id}',
              );
            } catch (parseError, parseStackTrace) {
              debugPrint(
                '❌ [OFFERS_SERVICE] Erro ao fazer fromJson do item $i: $parseError',
              );
              debugPrint('📚 [OFFERS_SERVICE] StackTrace: $parseStackTrace');
              debugPrint('📋 [OFFERS_SERVICE] JSON do item: $e');
              rethrow;
            }
          }

          debugPrint(
            '✅ [OFFERS_SERVICE] ${offers.length} ofertas encontradas e parseadas com sucesso',
          );
          return ApiResponse.success(
            data: offers,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [OFFERS_SERVICE] Erro ao parsear resposta: $e');
          debugPrint('📚 [OFFERS_SERVICE] StackTrace: $stackTrace');
          debugPrint(
            '📋 [OFFERS_SERVICE] Tipo de response.data: ${response.data?.runtimeType}',
          );
          debugPrint('📋 [OFFERS_SERVICE] Dados recebidos: ${response.data}');
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
  Future<ApiResponse<List<PropertyOffer>>> getPropertyOffers(
    String propertyId,
  ) async {
    debugPrint(
      '💰 [OFFERS_SERVICE] Listando ofertas da propriedade: $propertyId',
    );

    try {
      debugPrint(
        '💰 [OFFERS_SERVICE] Fazendo requisição GET para /properties/offers/property/$propertyId',
      );

      final response = await _apiService.get<dynamic>(
        '/properties/offers/property/$propertyId',
      );

      debugPrint('💰 [OFFERS_SERVICE] Resposta recebida:');
      debugPrint('   - success: ${response.success}');
      debugPrint('   - statusCode: ${response.statusCode}');
      debugPrint('   - message: ${response.message}');
      debugPrint('   - data type: ${response.data?.runtimeType}');
      debugPrint('   - data is null: ${response.data == null}');

      if (response.success && response.data != null) {
        try {
          debugPrint('💰 [OFFERS_SERVICE] Iniciando parsing dos dados...');
          debugPrint(
            '💰 [OFFERS_SERVICE] response.data completo: ${response.data}',
          );

          // Verificar se os dados estão dentro de um objeto 'data' ou 'results'
          dynamic dataToParse = response.data;
          debugPrint(
            '💰 [OFFERS_SERVICE] dataToParse inicial type: ${dataToParse.runtimeType}',
          );

          // Se for um Map, tentar extrair 'data' ou 'results'
          if (dataToParse is Map<String, dynamic>) {
            debugPrint(
              '💰 [OFFERS_SERVICE] dataToParse é um Map, tentando extrair data/results',
            );
            debugPrint(
              '💰 [OFFERS_SERVICE] Chaves do Map: ${dataToParse.keys.toList()}',
            );
            dataToParse =
                dataToParse['data'] ?? dataToParse['results'] ?? dataToParse;
            debugPrint(
              '💰 [OFFERS_SERVICE] dataToParse após extração type: ${dataToParse.runtimeType}',
            );
          }

          // Garantir que é uma lista
          if (dataToParse is! List) {
            debugPrint(
              '❌ [OFFERS_SERVICE] Resposta não é uma lista: ${dataToParse.runtimeType}',
            );
            debugPrint('📋 [OFFERS_SERVICE] Dados recebidos: $dataToParse');
            return ApiResponse.error(
              message:
                  'Formato de resposta inválido: esperado List, recebido ${dataToParse.runtimeType}',
              statusCode: response.statusCode,
              data: response.error,
            );
          }

          final dataList = dataToParse;
          debugPrint(
            '💰 [OFFERS_SERVICE] dataToParse é uma List com ${dataList.length} itens',
          );

          final offers = <PropertyOffer>[];
          for (var i = 0; i < dataList.length; i++) {
            final e = dataList[i];
            debugPrint('💰 [OFFERS_SERVICE] Processando item $i:');
            debugPrint('   - type: ${e.runtimeType}');
            debugPrint('   - value: $e');

            // Verificar se cada item é um Map
            if (e is! Map<String, dynamic>) {
              debugPrint(
                '❌ [OFFERS_SERVICE] Item $i da lista não é Map: ${e.runtimeType}, valor: $e',
              );
              throw Exception(
                'Item $i da lista não é um Map<String, dynamic>, é ${e.runtimeType}',
              );
            }

            debugPrint(
              '💰 [OFFERS_SERVICE] Item $i é um Map, fazendo fromJson...',
            );
            try {
              final offer = PropertyOffer.fromJson(e);
              offers.add(offer);
              debugPrint(
                '✅ [OFFERS_SERVICE] Item $i parseado com sucesso: ${offer.id}',
              );
            } catch (parseError, parseStackTrace) {
              debugPrint(
                '❌ [OFFERS_SERVICE] Erro ao fazer fromJson do item $i: $parseError',
              );
              debugPrint('📚 [OFFERS_SERVICE] StackTrace: $parseStackTrace');
              debugPrint('📋 [OFFERS_SERVICE] JSON do item: $e');
              rethrow;
            }
          }

          debugPrint(
            '✅ [OFFERS_SERVICE] ${offers.length} ofertas encontradas e parseadas com sucesso',
          );
          return ApiResponse.success(
            data: offers,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [OFFERS_SERVICE] Erro ao parsear resposta: $e');
          debugPrint('📚 [OFFERS_SERVICE] StackTrace: $stackTrace');
          debugPrint(
            '📋 [OFFERS_SERVICE] Tipo de response.data: ${response.data?.runtimeType}',
          );
          debugPrint('📋 [OFFERS_SERVICE] Dados recebidos: ${response.data}');
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
      final response = await _apiService.get<dynamic>(
        '/properties/offers/detail/$offerId',
      );

      debugPrint('💰 [OFFERS_SERVICE] Resposta recebida:');
      debugPrint('   - success: ${response.success}');
      debugPrint('   - statusCode: ${response.statusCode}');
      debugPrint('   - message: ${response.message}');
      debugPrint('   - data type: ${response.data?.runtimeType}');
      debugPrint('   - data is null: ${response.data == null}');

      if (response.success && response.data != null) {
        try {
          debugPrint('💰 [OFFERS_SERVICE] Iniciando parsing da oferta...');
          debugPrint(
            '💰 [OFFERS_SERVICE] response.data completo: ${response.data}',
          );

          // Verificar se os dados estão dentro de um objeto 'data'
          dynamic dataToParse = response.data;
          debugPrint(
            '💰 [OFFERS_SERVICE] dataToParse inicial type: ${dataToParse.runtimeType}',
          );

          // Se for um Map, tentar extrair 'data'
          if (dataToParse is Map<String, dynamic>) {
            debugPrint(
              '💰 [OFFERS_SERVICE] dataToParse é um Map, tentando extrair data',
            );
            debugPrint(
              '💰 [OFFERS_SERVICE] Chaves do Map: ${dataToParse.keys.toList()}',
            );
            dataToParse = dataToParse['data'] ?? dataToParse;
            debugPrint(
              '💰 [OFFERS_SERVICE] dataToParse após extração type: ${dataToParse.runtimeType}',
            );
          }

          // Garantir que é um Map
          if (dataToParse is! Map<String, dynamic>) {
            debugPrint(
              '❌ [OFFERS_SERVICE] Resposta não é um Map: ${dataToParse.runtimeType}',
            );
            debugPrint('📋 [OFFERS_SERVICE] Dados recebidos: $dataToParse');
            return ApiResponse.error(
              message:
                  'Formato de resposta inválido: esperado Map<String, dynamic>, recebido ${dataToParse.runtimeType}',
              statusCode: response.statusCode,
              data: response.error,
            );
          }

          debugPrint('💰 [OFFERS_SERVICE] Fazendo fromJson...');
          final offer = PropertyOffer.fromJson(dataToParse);
          debugPrint('✅ [OFFERS_SERVICE] Oferta encontrada: $offerId');
          return ApiResponse.success(
            data: offer,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [OFFERS_SERVICE] Erro ao parsear resposta: $e');
          debugPrint('📚 [OFFERS_SERVICE] StackTrace: $stackTrace');
          debugPrint('📋 [OFFERS_SERVICE] Dados recebidos: ${response.data}');
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
    } catch (e, stackTrace) {
      debugPrint('❌ [OFFERS_SERVICE] Erro de conexão: $e');
      debugPrint('📚 [OFFERS_SERVICE] StackTrace: $stackTrace');
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
    debugPrint(
      '💰 [OFFERS_SERVICE] Atualizando status da oferta: $offerId -> $status',
    );

    try {
      final data = <String, dynamic>{'status': status};
      if (responseMessage != null) {
        data['responseMessage'] = responseMessage;
      }

      final response = await _apiService.put<dynamic>(
        '/properties/offers/detail/$offerId/status',
        body: data,
      );

      debugPrint('💰 [OFFERS_SERVICE] Resposta recebida:');
      debugPrint('   - success: ${response.success}');
      debugPrint('   - statusCode: ${response.statusCode}');
      debugPrint('   - message: ${response.message}');
      debugPrint('   - data type: ${response.data?.runtimeType}');

      if (response.success && response.data != null) {
        try {
          debugPrint(
            '💰 [OFFERS_SERVICE] Iniciando parsing da oferta atualizada...',
          );
          debugPrint(
            '💰 [OFFERS_SERVICE] response.data completo: ${response.data}',
          );

          // Verificar se os dados estão dentro de um objeto 'data'
          dynamic dataToParse = response.data;
          debugPrint(
            '💰 [OFFERS_SERVICE] dataToParse inicial type: ${dataToParse.runtimeType}',
          );

          // Se for um Map, tentar extrair 'data'
          if (dataToParse is Map<String, dynamic>) {
            debugPrint(
              '💰 [OFFERS_SERVICE] dataToParse é um Map, tentando extrair data',
            );
            debugPrint(
              '💰 [OFFERS_SERVICE] Chaves do Map: ${dataToParse.keys.toList()}',
            );
            dataToParse = dataToParse['data'] ?? dataToParse;
            debugPrint(
              '💰 [OFFERS_SERVICE] dataToParse após extração type: ${dataToParse.runtimeType}',
            );
          }

          // Garantir que é um Map
          if (dataToParse is! Map<String, dynamic>) {
            debugPrint(
              '❌ [OFFERS_SERVICE] Resposta não é um Map: ${dataToParse.runtimeType}',
            );
            debugPrint('📋 [OFFERS_SERVICE] Dados recebidos: $dataToParse');
            return ApiResponse.error(
              message:
                  'Formato de resposta inválido: esperado Map<String, dynamic>, recebido ${dataToParse.runtimeType}',
              statusCode: response.statusCode,
              data: response.error,
            );
          }

          debugPrint('💰 [OFFERS_SERVICE] Fazendo fromJson...');
          final offer = PropertyOffer.fromJson(dataToParse);
          debugPrint('✅ [OFFERS_SERVICE] Oferta atualizada: $offerId');
          return ApiResponse.success(
            data: offer,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [OFFERS_SERVICE] Erro ao parsear resposta: $e');
          debugPrint('📚 [OFFERS_SERVICE] StackTrace: $stackTrace');
          debugPrint('📋 [OFFERS_SERVICE] Dados recebidos: ${response.data}');
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
    } catch (e, stackTrace) {
      debugPrint('❌ [OFFERS_SERVICE] Erro de conexão: $e');
      debugPrint('📚 [OFFERS_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}
