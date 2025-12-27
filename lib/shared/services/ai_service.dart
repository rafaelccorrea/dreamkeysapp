import 'package:flutter/foundation.dart';
import 'api_service.dart';

/// Requisição para geração de descrição
class GenerateDescriptionRequest {
  final String type; // 'apartment' | 'house' | 'commercial' | 'land' | 'rural'
  final String city;
  final String? neighborhood;
  final double totalArea;
  final double? builtArea;
  final int? bedrooms;
  final int? bathrooms;
  final int? parkingSpaces;
  final double? salePrice;
  final double? rentPrice;
  final double? condominiumFee;
  final double? iptu;
  final List<String>? features;
  final String? additionalInfo;
  final bool? mcmvEligible;
  final String? mcmvIncomeRange; // 'faixa1' | 'faixa2' | 'faixa3'
  final double? mcmvMaxValue;
  final double? mcmvSubsidy;
  final String? mcmvNotes;

  GenerateDescriptionRequest({
    required this.type,
    required this.city,
    this.neighborhood,
    required this.totalArea,
    this.builtArea,
    this.bedrooms,
    this.bathrooms,
    this.parkingSpaces,
    this.salePrice,
    this.rentPrice,
    this.condominiumFee,
    this.iptu,
    this.features,
    this.additionalInfo,
    this.mcmvEligible,
    this.mcmvIncomeRange,
    this.mcmvMaxValue,
    this.mcmvSubsidy,
    this.mcmvNotes,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'type': type,
      'city': city,
      'totalArea': totalArea,
    };
    if (neighborhood != null) map['neighborhood'] = neighborhood;
    if (builtArea != null) map['builtArea'] = builtArea;
    if (bedrooms != null) map['bedrooms'] = bedrooms;
    if (bathrooms != null) map['bathrooms'] = bathrooms;
    if (parkingSpaces != null) map['parkingSpaces'] = parkingSpaces;
    if (salePrice != null) map['salePrice'] = salePrice;
    if (rentPrice != null) map['rentPrice'] = rentPrice;
    if (condominiumFee != null) map['condominiumFee'] = condominiumFee;
    if (iptu != null) map['iptu'] = iptu;
    if (features != null && features!.isNotEmpty) map['features'] = features;
    if (additionalInfo != null) map['additionalInfo'] = additionalInfo;
    if (mcmvEligible != null) map['mcmvEligible'] = mcmvEligible;
    if (mcmvIncomeRange != null) map['mcmvIncomeRange'] = mcmvIncomeRange;
    if (mcmvMaxValue != null) map['mcmvMaxValue'] = mcmvMaxValue;
    if (mcmvSubsidy != null) map['mcmvSubsidy'] = mcmvSubsidy;
    if (mcmvNotes != null) map['mcmvNotes'] = mcmvNotes;
    return map;
  }
}

/// Resposta de geração de descrição
class GeneratedDescription {
  final String title;
  final String description;
  final List<String> highlights;

  GeneratedDescription({
    required this.title,
    required this.description,
    required this.highlights,
  });

  factory GeneratedDescription.fromJson(Map<String, dynamic> json) {
    return GeneratedDescription(
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      highlights: (json['highlights'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

/// Requisição de otimização de portfólio
class PortfolioOptimizationRequest {
  final String focus; // 'sales_speed' | 'profitability' | 'market_coverage' | 'balanced'
  final String? propertyId;

  PortfolioOptimizationRequest({
    required this.focus,
    this.propertyId,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'focus': focus};
    if (propertyId != null) map['propertyId'] = propertyId;
    return map;
  }
}

/// Resposta de otimização de portfólio
class PortfolioOptimizationResponse {
  final String propertyId;
  final String propertyTitle;
  final double priorityScore;
  final String currentStatus;
  final List<String> recommendedActions;
  final double currentPrice;
  final double? suggestedPrice;
  final String? expectedImpact;
  final int estimatedSaleTime;
  final String prioritizationReason;
  final String riskLevel; // 'low' | 'medium' | 'high'

  PortfolioOptimizationResponse({
    required this.propertyId,
    required this.propertyTitle,
    required this.priorityScore,
    required this.currentStatus,
    required this.recommendedActions,
    required this.currentPrice,
    this.suggestedPrice,
    this.expectedImpact,
    required this.estimatedSaleTime,
    required this.prioritizationReason,
    required this.riskLevel,
  });

  factory PortfolioOptimizationResponse.fromJson(Map<String, dynamic> json) {
    return PortfolioOptimizationResponse(
      propertyId: json['propertyId']?.toString() ?? '',
      propertyTitle: json['propertyTitle']?.toString() ?? '',
      priorityScore: (json['priorityScore'] as num?)?.toDouble() ?? 0.0,
      currentStatus: json['currentStatus']?.toString() ?? '',
      recommendedActions: (json['recommendedActions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      currentPrice: (json['currentPrice'] as num?)?.toDouble() ?? 0.0,
      suggestedPrice: (json['suggestedPrice'] as num?)?.toDouble(),
      expectedImpact: json['expectedImpact']?.toString(),
      estimatedSaleTime: (json['estimatedSaleTime'] as num?)?.toInt() ?? 0,
      prioritizationReason: json['prioritizationReason']?.toString() ?? '',
      riskLevel: json['riskLevel']?.toString() ?? 'medium',
    );
  }
}

/// Requisição de análise preditiva
class PredictiveSalesRequest {
  final String? propertyId;
  final String? analysisType; // 'single' | 'bulk'

  PredictiveSalesRequest({
    this.propertyId,
    this.analysisType,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (propertyId != null) map['propertyId'] = propertyId;
    if (analysisType != null) map['analysisType'] = analysisType;
    return map;
  }
}

/// Resposta de análise preditiva
class PredictiveSalesResponse {
  final String propertyId;
  final String propertyTitle;
  final int estimatedDaysToSale;
  final double probability30Days;
  final double probability60Days;
  final double probability90Days;
  final double? suggestedPrice;
  final String? priceImpact;
  final List<String> influencingFactors;
  final List<String> recommendations;

  PredictiveSalesResponse({
    required this.propertyId,
    required this.propertyTitle,
    required this.estimatedDaysToSale,
    required this.probability30Days,
    required this.probability60Days,
    required this.probability90Days,
    this.suggestedPrice,
    this.priceImpact,
    required this.influencingFactors,
    required this.recommendations,
  });

  factory PredictiveSalesResponse.fromJson(Map<String, dynamic> json) {
    return PredictiveSalesResponse(
      propertyId: json['propertyId']?.toString() ?? '',
      propertyTitle: json['propertyTitle']?.toString() ?? '',
      estimatedDaysToSale: (json['estimatedDaysToSale'] as num?)?.toInt() ?? 0,
      probability30Days: (json['probability30Days'] as num?)?.toDouble() ?? 0.0,
      probability60Days: (json['probability60Days'] as num?)?.toDouble() ?? 0.0,
      probability90Days: (json['probability90Days'] as num?)?.toDouble() ?? 0.0,
      suggestedPrice: (json['suggestedPrice'] as num?)?.toDouble(),
      priceImpact: json['priceImpact']?.toString(),
      influencingFactors: (json['influencingFactors'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      recommendations: (json['recommendations'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

/// Serviço de IA
class AiService {
  AiService._();

  static final AiService instance = AiService._();
  final ApiService _apiService = ApiService.instance;

  /// Gera descrição de propriedade com IA
  Future<ApiResponse<GeneratedDescription>> generatePropertyDescription(
    GenerateDescriptionRequest request,
  ) async {
    debugPrint('🤖 [AI_SERVICE] Gerando descrição de propriedade');

    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        '/api/ai/generate-property-description',
        body: request.toJson(),
      );

      if (response.success && response.data != null) {
        try {
          final description = GeneratedDescription.fromJson(response.data!);
          debugPrint('✅ [AI_SERVICE] Descrição gerada com sucesso');
          return ApiResponse.success(
            data: description,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [AI_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao gerar descrição',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [AI_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Otimiza portfólio
  Future<ApiResponse<dynamic>> optimizePortfolio(
    PortfolioOptimizationRequest request,
  ) async {
    debugPrint('🤖 [AI_SERVICE] Otimizando portfólio');

    try {
      final response = await _apiService.post<dynamic>(
        '/ai-assistant/analytics/portfolio-optimization',
        body: request.toJson(),
      );

      if (response.success && response.data != null) {
        try {
          // Pode retornar um único resultado ou uma lista
          if (response.data is List) {
            final results = (response.data as List)
                .map((e) => PortfolioOptimizationResponse.fromJson(e as Map<String, dynamic>))
                .toList();
            debugPrint('✅ [AI_SERVICE] Portfólio otimizado: ${results.length} propriedades');
            return ApiResponse.success(
              data: results,
              statusCode: response.statusCode,
            );
          } else {
            final result = PortfolioOptimizationResponse.fromJson(
              response.data as Map<String, dynamic>,
            );
            debugPrint('✅ [AI_SERVICE] Propriedade otimizada');
            return ApiResponse.success(
              data: result,
              statusCode: response.statusCode,
            );
          }
        } catch (e) {
          debugPrint('❌ [AI_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao otimizar portfólio',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [AI_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Análise preditiva de vendas
  Future<ApiResponse<dynamic>> predictiveSalesAnalysis(
    PredictiveSalesRequest request,
  ) async {
    debugPrint('🤖 [AI_SERVICE] Análise preditiva de vendas');

    try {
      final response = await _apiService.post<dynamic>(
        '/ai-assistant/predictive/sales',
        body: request.toJson(),
      );

      if (response.success && response.data != null) {
        try {
          // Pode retornar um único resultado ou uma lista
          if (response.data is List) {
            final results = (response.data as List)
                .map((e) => PredictiveSalesResponse.fromJson(e as Map<String, dynamic>))
                .toList();
            debugPrint('✅ [AI_SERVICE] Análise preditiva: ${results.length} propriedades');
            return ApiResponse.success(
              data: results,
              statusCode: response.statusCode,
            );
          } else {
            final result = PredictiveSalesResponse.fromJson(
              response.data as Map<String, dynamic>,
            );
            debugPrint('✅ [AI_SERVICE] Análise preditiva concluída');
            return ApiResponse.success(
              data: result,
              statusCode: response.statusCode,
            );
          }
        } catch (e) {
          debugPrint('❌ [AI_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro na análise preditiva',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [AI_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}


