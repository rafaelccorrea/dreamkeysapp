import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_service.dart';
import '../../core/constants/api_constants.dart';
import 'secure_storage_service.dart';

/// Modelo de imagem da galeria
class GalleryImage {
  final String id;
  final String propertyId;
  final String url;
  final String? thumbnailUrl;
  final String? alt;
  final String category;
  final bool isMain;
  final int order;
  final String createdAt;
  final String updatedAt;

  GalleryImage({
    required this.id,
    required this.propertyId,
    required this.url,
    this.thumbnailUrl,
    this.alt,
    required this.category,
    required this.isMain,
    required this.order,
    required this.createdAt,
    required this.updatedAt,
  });

  factory GalleryImage.fromJson(Map<String, dynamic> json) {
    return GalleryImage(
      id: json['id']?.toString() ?? '',
      propertyId: json['propertyId']?.toString() ?? json['property_id']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      thumbnailUrl: json['thumbnailUrl']?.toString() ?? json['thumbnail_url']?.toString(),
      alt: json['alt']?.toString(),
      category: json['category']?.toString() ?? 'general',
      isMain: json['isMain'] as bool? ?? json['is_main'] as bool? ?? false,
      order: (json['order'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt']?.toString() ?? json['created_at']?.toString() ?? '',
      updatedAt: json['updatedAt']?.toString() ?? json['updated_at']?.toString() ?? '',
    );
  }
}

/// Serviço de Galeria de Imagens
class GalleryService {
  GalleryService._();

  static final GalleryService instance = GalleryService._();
  final ApiService _apiService = ApiService.instance;

  /// Lista imagens de uma propriedade
  Future<ApiResponse<List<GalleryImage>>> getPropertyImages(String propertyId) async {
    debugPrint('🖼️ [GALLERY_SERVICE] Listando imagens da propriedade: $propertyId');

    try {
      final response = await _apiService.get<List<dynamic>>(
        '/gallery/property/$propertyId',
      );

      if (response.success && response.data != null) {
        try {
          final images = (response.data as List)
              .map((e) => GalleryImage.fromJson(e as Map<String, dynamic>))
              .toList();
          debugPrint('✅ [GALLERY_SERVICE] ${images.length} imagens encontradas');
          return ApiResponse.success(
            data: images,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [GALLERY_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao listar imagens',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [GALLERY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Upload de múltiplas imagens
  Future<ApiResponse<List<GalleryImage>>> uploadImages({
    required String propertyId,
    required List<File> files,
    String category = 'general',
    String? altText,
    String? description,
    List<String>? tags,
    bool isPublic = true,
  }) async {
    debugPrint('🖼️ [GALLERY_SERVICE] Fazendo upload de ${files.length} imagens');

    try {
      final token = await SecureStorageService.instance.getAccessToken();
      if (token == null || token.isEmpty) {
        return ApiResponse.error(
          message: 'Token de autenticação não encontrado',
          statusCode: 401,
        );
      }

      final uri = Uri.parse('${ApiConstants.baseApiUrl}/gallery/upload');
      final request = http.MultipartRequest('POST', uri);

      // Headers
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Content-Type'] = 'multipart/form-data';

      // Adicionar arquivos
      for (var file in files) {
        final fileStream = http.ByteStream(file.openRead());
        final fileLength = await file.length();
        final multipartFile = http.MultipartFile(
          'images',
          fileStream,
          fileLength,
          filename: file.path.split('/').last,
        );
        request.files.add(multipartFile);
      }

      // Adicionar campos
      request.fields['propertyId'] = propertyId;
      request.fields['category'] = category;
      if (altText != null) request.fields['altText'] = altText;
      if (description != null) request.fields['description'] = description;
      if (tags != null && tags.isNotEmpty) {
        request.fields['tags'] = jsonEncode(tags);
      }
      request.fields['isPublic'] = isPublic.toString();

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 60),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
          final imagesList = jsonData['data'] as List<dynamic>? ?? jsonData['images'] as List<dynamic>? ?? [];
          final images = imagesList
              .map((e) => GalleryImage.fromJson(e as Map<String, dynamic>))
              .toList();
          debugPrint('✅ [GALLERY_SERVICE] ${images.length} imagens enviadas com sucesso');
          return ApiResponse.success(
            data: images,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [GALLERY_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar resposta: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      } else {
        final errorMessage = _parseErrorResponse(response.body);
        return ApiResponse.error(
          message: errorMessage,
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      debugPrint('❌ [GALLERY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Atualiza uma imagem
  Future<ApiResponse<GalleryImage>> updateImage({
    required String imageId,
    String? url,
    String? alt,
    bool? isMain,
    int? order,
  }) async {
    debugPrint('🖼️ [GALLERY_SERVICE] Atualizando imagem: $imageId');

    try {
      final data = <String, dynamic>{};
      if (url != null) data['url'] = url;
      if (alt != null) data['alt'] = alt;
      if (isMain != null) data['isMain'] = isMain;
      if (order != null) data['order'] = order;

      final response = await _apiService.patch<Map<String, dynamic>>(
        '/gallery/$imageId',
        body: data,
      );

      if (response.success && response.data != null) {
        try {
          final image = GalleryImage.fromJson(response.data!);
          debugPrint('✅ [GALLERY_SERVICE] Imagem atualizada: $imageId');
          return ApiResponse.success(
            data: image,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [GALLERY_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar imagem',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [GALLERY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Deleta uma imagem
  Future<ApiResponse<void>> deleteImage(String imageId) async {
    debugPrint('🖼️ [GALLERY_SERVICE] Deletando imagem: $imageId');

    try {
      final response = await _apiService.delete('/gallery/$imageId');

      if (response.success) {
        debugPrint('✅ [GALLERY_SERVICE] Imagem deletada: $imageId');
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao deletar imagem',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [GALLERY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Define imagem principal
  Future<ApiResponse<GalleryImage>> setMainImage(String imageId) async {
    debugPrint('🖼️ [GALLERY_SERVICE] Definindo imagem principal: $imageId');

    try {
      final response = await _apiService.patch<Map<String, dynamic>>(
        '/gallery/$imageId/set-main',
      );

      if (response.success && response.data != null) {
        try {
          final image = GalleryImage.fromJson(response.data!);
          debugPrint('✅ [GALLERY_SERVICE] Imagem principal definida: $imageId');
          return ApiResponse.success(
            data: image,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [GALLERY_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao definir imagem principal',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [GALLERY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Reordena imagens
  Future<ApiResponse<void>> reorderImages(List<String> imageIds) async {
    debugPrint('🖼️ [GALLERY_SERVICE] Reordenando ${imageIds.length} imagens');

    try {
      final response = await _apiService.patch<Map<String, dynamic>>(
        '/gallery/reorder',
        body: {'imageIds': imageIds},
      );

      if (response.success) {
        debugPrint('✅ [GALLERY_SERVICE] Imagens reordenadas');
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao reordenar imagens',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [GALLERY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  String _parseErrorResponse(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return json['message']?.toString() ?? json['error']?.toString() ?? 'Erro desconhecido';
    } catch (e) {
      return 'Erro ao processar resposta do servidor';
    }
  }
}




