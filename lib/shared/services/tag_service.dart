import 'package:flutter/foundation.dart';
import 'api_service.dart';

/// Modelo de Tag
class Tag {
  final String id;
  final String name;
  final String? description;
  final String? color;
  final String? icon;
  final String createdAt;
  final String updatedAt;

  Tag({
    required this.id,
    required this.name,
    this.description,
    this.color,
    this.icon,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Tag.fromJson(Map<String, dynamic> json) {
    return Tag(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      color: json['color']?.toString(),
      icon: json['icon']?.toString(),
      createdAt: json['createdAt']?.toString() ?? json['created_at']?.toString() ?? '',
      updatedAt: json['updatedAt']?.toString() ?? json['updated_at']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'color': color,
      'icon': icon,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}

/// Serviço de Tags
class TagService {
  TagService._();

  static final TagService instance = TagService._();
  final ApiService _apiService = ApiService.instance;

  /// Lista todas as tags disponíveis
  Future<ApiResponse<List<Tag>>> getTags() async {
    try {
      final response = await _apiService.get<dynamic>(
        '/tags',
      );

      if (response.success && response.data != null) {
        try {
          dynamic dataToParse = response.data;
          
          // Se for um Map, tentar extrair 'data' ou 'results'
          if (dataToParse is Map<String, dynamic>) {
            dataToParse = dataToParse['data'] ?? dataToParse['results'] ?? dataToParse;
          }

          // Garantir que é uma lista
          if (dataToParse is List) {
            final tags = dataToParse
                .map((e) => Tag.fromJson(e as Map<String, dynamic>))
                .toList();
            
            return ApiResponse.success(
              data: tags,
              statusCode: response.statusCode,
            );
          }

          return ApiResponse.error(
            message: 'Formato de resposta inválido',
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [TAG_SERVICE] Erro ao parsear tags: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar tags',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [TAG_SERVICE] Erro ao buscar tags: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Busca tags de um usuário específico
  Future<ApiResponse<List<Tag>>> getUserTags(String userId) async {
    try {
      final response = await _apiService.get<dynamic>(
        '/users/$userId/tags',
      );

      if (response.success && response.data != null) {
        try {
          dynamic dataToParse = response.data;
          
          if (dataToParse is Map<String, dynamic>) {
            dataToParse = dataToParse['data'] ?? dataToParse['results'] ?? dataToParse;
          }

          if (dataToParse is List) {
            final tags = (dataToParse as List)
                .map((e) => Tag.fromJson(e as Map<String, dynamic>))
                .toList();
            
            return ApiResponse.success(
              data: tags,
              statusCode: response.statusCode,
            );
          }

          return ApiResponse.error(
            message: 'Formato de resposta inválido',
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [TAG_SERVICE] Erro ao parsear tags do usuário: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar tags do usuário',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [TAG_SERVICE] Erro ao buscar tags do usuário: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}

