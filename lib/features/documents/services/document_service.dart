import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/services/secure_storage_service.dart';
import '../models/document_model.dart';
import '../models/document_signature_model.dart';
import '../models/upload_token_model.dart';

/// Serviço para gerenciar documentos
class DocumentService {
  DocumentService._();

  static final DocumentService instance = DocumentService._();
  final ApiService _apiService = ApiService.instance;

  // Constantes de validação
  static const int maxFileSize = 50 * 1024 * 1024; // 50MB
  static const int maxPublicFileSize = 10 * 1024 * 1024; // 10MB
  static const List<String> allowedMimeTypes = [
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'image/jpeg',
    'image/jpg',
    'image/png',
    'image/gif',
    'image/webp',
    'text/plain',
  ];

  /// Valida arquivo
  bool validateFile(File file, {bool isPublic = false}) {
    final maxSize = isPublic ? maxPublicFileSize : maxFileSize;
    final fileSize = file.lengthSync();
    
    if (fileSize > maxSize) {
      return false;
    }
    
    // Validação de tipo será feita no servidor
    return true;
  }

  /// Valida vínculo (cliente OU propriedade)
  bool validateBinding(String? clientId, String? propertyId) {
    return (clientId != null && propertyId == null) ||
        (clientId == null && propertyId != null);
  }

  /// Lista documentos com filtros
  Future<ApiResponse<DocumentListResponse>> getDocuments({
    DocumentFilters? filters,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      debugPrint('📄 [DOCUMENT_SERVICE] Buscando documentos...');

      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
      };

      if (filters != null) {
        if (filters.type != null) {
          queryParams['type'] = filters.type!.value;
        }
        if (filters.status != null) {
          queryParams['status'] = filters.status!.value;
        }
        if (filters.clientId != null) {
          queryParams['clientId'] = filters.clientId!;
        }
        if (filters.propertyId != null) {
          queryParams['propertyId'] = filters.propertyId!;
        }
        if (filters.tags != null && filters.tags!.isNotEmpty) {
          queryParams['tags'] = filters.tags!.join(',');
        }
        if (filters.onlyMyDocuments == true) {
          queryParams['onlyMyDocuments'] = 'true';
        }
        if (filters.search != null && filters.search!.isNotEmpty) {
          queryParams['search'] = filters.search!;
        }
        if (filters.sortBy != null) {
          queryParams['sortBy'] = filters.sortBy!;
        }
        if (filters.sortOrder != null) {
          queryParams['sortOrder'] = filters.sortOrder!;
        }
      }

      final response = await _apiService.get<dynamic>(
        ApiConstants.documents,
        queryParameters: queryParams,
      );

      if (response.success && response.data != null) {
        try {
          DocumentListResponse documentList;
          
          if (response.data is List) {
            final dataList = response.data as List<dynamic>;
            documentList = DocumentListResponse(
              data: dataList
                  .map((e) => Document.fromJson(e as Map<String, dynamic>))
                  .toList(),
              pagination: null,
            );
          } else if (response.data is Map<String, dynamic>) {
            documentList = DocumentListResponse.fromJson(
              response.data as Map<String, dynamic>,
            );
          } else {
            throw Exception('Formato de resposta inesperado');
          }

          debugPrint('✅ [DOCUMENT_SERVICE] ${documentList.data.length} documentos carregados');
          
          return ApiResponse.success(
            data: documentList,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [DOCUMENT_SERVICE] Erro ao parsear lista: $e');
          debugPrint('📚 StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar documentos',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [DOCUMENT_SERVICE] Erro: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Busca documento por ID
  Future<ApiResponse<Document>> getDocumentById(String id) async {
    try {
      debugPrint('📄 [DOCUMENT_SERVICE] Buscando documento: $id');

      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConstants.documentById(id),
      );

      if (response.success && response.data != null) {
        try {
          final document = Document.fromJson(response.data!);
          return ApiResponse.success(
            data: document,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [DOCUMENT_SERVICE] Erro ao parsear documento: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar documento',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [DOCUMENT_SERVICE] Erro: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Upload de documento
  Future<ApiResponse<Document>> uploadDocument({
    required File file,
    required DocumentType type,
    String? clientId,
    String? propertyId,
    String? title,
    String? description,
    List<String>? tags,
    String? notes,
    DateTime? expiryDate,
    bool isEncrypted = false,
  }) async {
    try {
      debugPrint('📤 [DOCUMENT_SERVICE] Fazendo upload de documento...');

      // Validações
      if (!validateFile(file)) {
        return ApiResponse.error(
          message: 'Arquivo muito grande! Tamanho máximo: 50MB',
          statusCode: 400,
        );
      }

      if (!validateBinding(clientId, propertyId)) {
        return ApiResponse.error(
          message: 'O documento deve estar vinculado a um cliente OU uma propriedade (não ambos).',
          statusCode: 400,
        );
      }

      final token = await SecureStorageService.instance.getAccessToken();
      if (token == null || token.isEmpty) {
        return ApiResponse.error(
          message: 'Token de autenticação não encontrado',
          statusCode: 401,
        );
      }

      final uri = Uri.parse('${ApiConstants.baseApiUrl}${ApiConstants.documentsUpload}');
      final request = http.MultipartRequest('POST', uri);

      // Headers
      request.headers['Authorization'] = 'Bearer $token';
      
      // Adicionar arquivo
      final fileStream = http.ByteStream(file.openRead());
      final fileLength = await file.length();
      final multipartFile = http.MultipartFile(
        'file',
        fileStream,
        fileLength,
        filename: file.path.split('/').last.split('\\').last,
      );
      request.files.add(multipartFile);

      // Adicionar campos
      request.fields['type'] = type.value;
      if (clientId != null) request.fields['clientId'] = clientId;
      if (propertyId != null) request.fields['propertyId'] = propertyId;
      if (title != null && title.isNotEmpty) {
        request.fields['title'] = title;
      }
      if (description != null && description.isNotEmpty) {
        request.fields['description'] = description;
      }
      if (tags != null && tags.isNotEmpty) {
        request.fields['tags'] = jsonEncode(tags);
      }
      if (notes != null && notes.isNotEmpty) {
        request.fields['notes'] = notes;
      }
      if (expiryDate != null) {
        request.fields['expiryDate'] = expiryDate.toIso8601String();
      }
      request.fields['isEncrypted'] = isEncrypted.toString();

      debugPrint('📤 [DOCUMENT_SERVICE] Enviando arquivo: ${file.path}');
      
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 120),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
          final document = Document.fromJson(jsonData);
          debugPrint('✅ [DOCUMENT_SERVICE] Documento enviado com sucesso: ${document.id}');
          return ApiResponse.success(
            data: document,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [DOCUMENT_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar resposta: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      String errorMessage = 'Erro ao fazer upload do documento';
      try {
        final errorData = jsonDecode(response.body) as Map<String, dynamic>;
        errorMessage = errorData['message']?.toString() ?? errorMessage;
      } catch (_) {}

      return ApiResponse.error(
        message: errorMessage,
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [DOCUMENT_SERVICE] Erro: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Atualiza documento
  Future<ApiResponse<Document>> updateDocument(
    String id, {
    DocumentType? type,
    DocumentStatus? status,
    String? title,
    String? description,
    List<String>? tags,
    String? notes,
    DateTime? expiryDate,
    String? clientId,
    String? propertyId,
    bool? isEncrypted,
  }) async {
    try {
      debugPrint('📝 [DOCUMENT_SERVICE] Atualizando documento: $id');

      final body = <String, dynamic>{};
      if (type != null) body['type'] = type.value;
      if (status != null) body['status'] = status.value;
      if (title != null) body['title'] = title;
      if (description != null) body['description'] = description;
      if (tags != null) body['tags'] = tags;
      if (notes != null) body['notes'] = notes;
      if (expiryDate != null) body['expiryDate'] = expiryDate.toIso8601String();
      if (clientId != null) body['clientId'] = clientId;
      if (propertyId != null) body['propertyId'] = propertyId;
      if (isEncrypted != null) body['isEncrypted'] = isEncrypted;

      // Validar vínculo se ambos forem fornecidos
      if (clientId != null && propertyId != null) {
        return ApiResponse.error(
          message: 'O documento deve estar vinculado a um cliente OU uma propriedade (não ambos).',
          statusCode: 400,
        );
      }

      final response = await _apiService.put<Map<String, dynamic>>(
        ApiConstants.documentUpdate(id),
        body: body,
      );

      if (response.success && response.data != null) {
        try {
          final document = Document.fromJson(response.data!);
          return ApiResponse.success(
            data: document,
            statusCode: response.statusCode,
          );
        } catch (e) {
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar documento',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [DOCUMENT_SERVICE] Erro: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Deleta documentos
  Future<ApiResponse<void>> deleteDocuments(List<String> documentIds) async {
    try {
      debugPrint('🗑️ [DOCUMENT_SERVICE] Deletando ${documentIds.length} documentos...');

      // DELETE com body requer uso direto do http
      final token = await SecureStorageService.instance.getAccessToken();
      if (token == null || token.isEmpty) {
        return ApiResponse.error(
          message: 'Token de autenticação não encontrado',
          statusCode: 401,
        );
      }

      final uri = Uri.parse('${ApiConstants.baseApiUrl}${ApiConstants.documents}');
      final response = await http.delete(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'documentIds': documentIds}),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('✅ [DOCUMENT_SERVICE] Documentos deletados com sucesso');
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }

      String errorMessage = 'Erro ao deletar documentos';
      try {
        final errorData = jsonDecode(response.body) as Map<String, dynamic>;
        errorMessage = errorData['message']?.toString() ?? errorMessage;
      } catch (_) {}

      return ApiResponse.error(
        message: errorMessage,
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [DOCUMENT_SERVICE] Erro: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Aprova ou rejeita documento
  Future<ApiResponse<Document>> approveDocument(
    String id, {
    required DocumentStatus status,
  }) async {
    try {
      debugPrint('✅ [DOCUMENT_SERVICE] Aprovando/rejeitando documento: $id');

      if (status != DocumentStatus.approved &&
          status != DocumentStatus.rejected) {
        return ApiResponse.error(
          message: 'Status inválido. Use "approved" ou "rejected".',
          statusCode: 400,
        );
      }

      final response = await _apiService.put<Map<String, dynamic>>(
        ApiConstants.documentApprove(id),
        body: {'status': status.value},
      );

      if (response.success && response.data != null) {
        try {
          final document = Document.fromJson(response.data!);
          return ApiResponse.success(
            data: document,
            statusCode: response.statusCode,
          );
        } catch (e) {
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao aprovar/rejeitar documento',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [DOCUMENT_SERVICE] Erro: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Lista documentos por cliente
  Future<ApiResponse<List<Document>>> getDocumentsByClient(
    String clientId,
  ) async {
    try {
      final response = await _apiService.get<List<dynamic>>(
        ApiConstants.documentsByClient(clientId),
      );

      if (response.success && response.data != null) {
        try {
          final documents = (response.data as List<dynamic>)
              .map((e) => Document.fromJson(e as Map<String, dynamic>))
              .toList();
          return ApiResponse.success(
            data: documents,
            statusCode: response.statusCode,
          );
        } catch (e) {
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar documentos',
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Lista documentos por propriedade
  Future<ApiResponse<List<Document>>> getDocumentsByProperty(
    String propertyId,
  ) async {
    try {
      final response = await _apiService.get<List<dynamic>>(
        ApiConstants.documentsByProperty(propertyId),
      );

      if (response.success && response.data != null) {
        try {
          final documents = (response.data as List<dynamic>)
              .map((e) => Document.fromJson(e as Map<String, dynamic>))
              .toList();
          return ApiResponse.success(
            data: documents,
            statusCode: response.statusCode,
          );
        } catch (e) {
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar documentos',
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Lista documentos vencendo
  Future<ApiResponse<List<Document>>> getExpiringDocuments(int days) async {
    try {
      final response = await _apiService.get<List<dynamic>>(
        ApiConstants.documentsExpiring(days),
      );

      if (response.success && response.data != null) {
        try {
          final documents = (response.data as List<dynamic>)
              .map((e) => Document.fromJson(e as Map<String, dynamic>))
              .toList();
          return ApiResponse.success(
            data: documents,
            statusCode: response.statusCode,
          );
        } catch (e) {
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar documentos',
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Lista todas as assinaturas
  Future<ApiResponse<SignatureListResponse>> getSignatures({
    DocumentSignatureStatus? status,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      debugPrint('✍️ [DOCUMENT_SERVICE] Buscando assinaturas...');

      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
      };

      if (status != null) {
        queryParams['status'] = status.value;
      }

      final response = await _apiService.get<dynamic>(
        ApiConstants.signatures,
        queryParameters: queryParams,
      );

      if (response.success && response.data != null) {
        try {
          SignatureListResponse signatureList;
          
          if (response.data is List) {
            final dataList = response.data as List<dynamic>;
            signatureList = SignatureListResponse(
              data: dataList
                  .map((e) => DocumentSignature.fromJson(e as Map<String, dynamic>))
                  .toList(),
              pagination: null,
            );
          } else if (response.data is Map<String, dynamic>) {
            signatureList = SignatureListResponse.fromJson(
              response.data as Map<String, dynamic>,
            );
          } else {
            throw Exception('Formato de resposta inesperado');
          }

          debugPrint('✅ [DOCUMENT_SERVICE] ${signatureList.data.length} assinaturas carregadas');
          
          return ApiResponse.success(
            data: signatureList,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [DOCUMENT_SERVICE] Erro ao parsear lista de assinaturas: $e');
          debugPrint('📚 StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar assinaturas',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [DOCUMENT_SERVICE] Erro: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Busca assinatura pendente do usuário
  Future<ApiResponse<SignatureListResponse>> getPendingSignatures({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      debugPrint('✍️ [DOCUMENT_SERVICE] Buscando assinaturas pendentes...');

      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
      };

      final response = await _apiService.get<dynamic>(
        ApiConstants.signaturesPending,
        queryParameters: queryParams,
      );

      if (response.success && response.data != null) {
        try {
          SignatureListResponse signatureList;
          
          if (response.data is List) {
            final dataList = response.data as List<dynamic>;
            signatureList = SignatureListResponse(
              data: dataList
                  .map((e) => DocumentSignature.fromJson(e as Map<String, dynamic>))
                  .toList(),
              pagination: null,
            );
          } else if (response.data is Map<String, dynamic>) {
            signatureList = SignatureListResponse.fromJson(
              response.data as Map<String, dynamic>,
            );
          } else {
            throw Exception('Formato de resposta inesperado');
          }

          debugPrint('✅ [DOCUMENT_SERVICE] ${signatureList.data.length} assinaturas pendentes carregadas');
          
          return ApiResponse.success(
            data: signatureList,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [DOCUMENT_SERVICE] Erro ao parsear lista: $e');
          debugPrint('📚 StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar assinaturas pendentes',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [DOCUMENT_SERVICE] Erro: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}

/// Resposta de Lista de Assinaturas
class SignatureListResponse {
  final List<DocumentSignature> data;
  final DocumentPagination? pagination;

  SignatureListResponse({
    required this.data,
    this.pagination,
  });

  factory SignatureListResponse.fromJson(Map<String, dynamic> json) {
    return SignatureListResponse(
      data: (json['data'] as List<dynamic>?)
              ?.map((e) => DocumentSignature.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      pagination: json['pagination'] != null
          ? DocumentPagination.fromJson(json['pagination'])
          : null,
    );
  }
}

/// Filtros de Documentos
class DocumentFilters {
  final DocumentType? type;
  final DocumentStatus? status;
  final String? clientId;
  final String? propertyId;
  final List<String>? tags;
  final bool? onlyMyDocuments;
  final String? search;
  final String? sortBy;
  final String? sortOrder;

  DocumentFilters({
    this.type,
    this.status,
    this.clientId,
    this.propertyId,
    this.tags,
    this.onlyMyDocuments,
    this.search,
    this.sortBy,
    this.sortOrder,
  });

  DocumentFilters copyWith({
    DocumentType? type,
    DocumentStatus? status,
    String? clientId,
    String? propertyId,
    List<String>? tags,
    bool? onlyMyDocuments,
    String? search,
    String? sortBy,
    String? sortOrder,
  }) {
    return DocumentFilters(
      type: type ?? this.type,
      status: status ?? this.status,
      clientId: clientId ?? this.clientId,
      propertyId: propertyId ?? this.propertyId,
      tags: tags ?? this.tags,
      onlyMyDocuments: onlyMyDocuments ?? this.onlyMyDocuments,
      search: search ?? this.search,
      sortBy: sortBy ?? this.sortBy,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

/// Resposta de Lista de Documentos
class DocumentListResponse {
  final List<Document> data;
  final DocumentPagination? pagination;

  DocumentListResponse({
    required this.data,
    this.pagination,
  });

  factory DocumentListResponse.fromJson(Map<String, dynamic> json) {
    // A API retorna 'documents' ao invés de 'data'
    final documentsList = json['documents'] as List<dynamic>? ?? 
                         json['data'] as List<dynamic>?;
    
    return DocumentListResponse(
      data: documentsList
              ?.map((e) => Document.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      pagination: json['pagination'] != null
          ? DocumentPagination.fromJson(json['pagination'])
          : (json['page'] != null || json['total'] != null)
              ? DocumentPagination(
                  currentPage: json['page'] ?? 1,
                  totalPages: _calculateTotalPages(
                    json['total'] ?? 0,
                    json['limit'] ?? 20,
                  ),
                  totalItems: json['total'] ?? 0,
                  itemsPerPage: json['limit'] ?? 20,
                )
              : null,
    );
  }

  static int _calculateTotalPages(int total, int limit) {
    if (limit <= 0) return 1;
    return (total / limit).ceil();
  }
}

/// Paginação de Documentos
class DocumentPagination {
  final int currentPage;
  final int totalPages;
  final int totalItems;
  final int itemsPerPage;

  DocumentPagination({
    required this.currentPage,
    required this.totalPages,
    required this.totalItems,
    required this.itemsPerPage,
  });

  factory DocumentPagination.fromJson(Map<String, dynamic> json) {
    final total = json['totalItems'] ?? json['total'] ?? 0;
    final limit = json['itemsPerPage'] ?? json['limit'] ?? 20;
    
    return DocumentPagination(
      currentPage: json['currentPage'] ?? json['page'] ?? 1,
      totalPages: json['totalPages'] ?? 
                  (limit > 0 ? (total / limit).ceil() : 1),
      totalItems: total,
      itemsPerPage: limit,
    );
  }
}

/// Métodos para Upload Tokens (Links Públicos)
extension UploadTokenMethods on DocumentService {
  /// Cria um token de upload
  Future<ApiResponse<UploadToken>> createUploadToken({
    required String clientId,
    int expirationDays = 3,
    String? notes,
  }) async {
    try {
      // Validar clientId
      if (clientId.isEmpty || clientId.trim().isEmpty) {
        debugPrint('❌ [DOCUMENT_SERVICE] clientId está vazio');
        return ApiResponse.error(
          message: 'ID do cliente é obrigatório',
          statusCode: 400,
        );
      }

      debugPrint('🔗 [DOCUMENT_SERVICE] Criando token de upload...');
      debugPrint('   - clientId: $clientId');
      debugPrint('   - expirationDays: $expirationDays');

      final body = {
        'clientId': clientId.trim(),
        'expirationDays': expirationDays,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      };

      debugPrint('🔗 [DOCUMENT_SERVICE] Enviando requisição POST para: ${ApiConstants.uploadTokens}');
      debugPrint('🔗 [DOCUMENT_SERVICE] Body enviado: $body');
      
      final response = await _apiService.post<dynamic>(
        ApiConstants.uploadTokens,
        body: body,
      );

      debugPrint('🔗 [DOCUMENT_SERVICE] ════════════════════════════════════');
      debugPrint('🔗 [DOCUMENT_SERVICE] RESPOSTA DA API - createUploadToken');
      debugPrint('🔗 [DOCUMENT_SERVICE] ════════════════════════════════════');
      debugPrint('   - success: ${response.success}');
      debugPrint('   - statusCode: ${response.statusCode}');
      debugPrint('   - message: ${response.message}');
      debugPrint('   - data type: ${response.data?.runtimeType}');
      debugPrint('   - data: ${response.data}');
      
      if (response.data != null) {
        if (response.data is Map) {
          final dataMap = response.data as Map<String, dynamic>;
          debugPrint('   - data keys: ${dataMap.keys.toList()}');
          if (dataMap.containsKey('clientId')) {
            debugPrint('   - clientId no response: ${dataMap['clientId']}');
            debugPrint('   - clientId type: ${dataMap['clientId']?.runtimeType}');
          }
        }
      }
      debugPrint('🔗 [DOCUMENT_SERVICE] ════════════════════════════════════');

      if (response.success && response.data != null) {
        try {
          debugPrint('🔗 [DOCUMENT_SERVICE] Tentando parsear token...');
          final token = UploadToken.fromJson(response.data as Map<String, dynamic>);
          debugPrint('✅ [DOCUMENT_SERVICE] Token criado com sucesso:');
          debugPrint('   - token.id: ${token.id}');
          debugPrint('   - token.clientId: ${token.clientId}');
          debugPrint('   - token.token: ${token.token}');
          return ApiResponse.success(
            data: token,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [DOCUMENT_SERVICE] Erro ao parsear token: $e');
          debugPrint('❌ [DOCUMENT_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta do servidor: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      debugPrint('❌ [DOCUMENT_SERVICE] Resposta não foi bem-sucedida');
      debugPrint('   - response.success: ${response.success}');
      debugPrint('   - response.data: ${response.data}');
      debugPrint('   - response.message: ${response.message}');
      
      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar token de upload',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [DOCUMENT_SERVICE] Erro ao criar token: $e');
      return ApiResponse.error(
        message: 'Erro ao criar token de upload: ${e.toString()}',
        statusCode: 500,
      );
    }
  }

  /// Lista tokens de upload
  Future<ApiResponse<List<UploadToken>>> getUploadTokens({
    String? clientId,
  }) async {
    try {
      debugPrint('🔗 [DOCUMENT_SERVICE] Buscando tokens de upload...');
      if (clientId != null) {
        debugPrint('   - Filtrando por clientId: $clientId');
      }

      final body = <String, dynamic>{};
      if (clientId != null) {
        body['clientId'] = clientId;
      }

      final response = await _apiService.post<dynamic>(
        ApiConstants.uploadTokens,
        body: body.isNotEmpty ? body : null,
      );

      debugPrint('🔗 [DOCUMENT_SERVICE] Resposta getUploadTokens:');
      debugPrint('   - success: ${response.success}');
      debugPrint('   - statusCode: ${response.statusCode}');
      debugPrint('   - message: ${response.message}');
      debugPrint('   - data type: ${response.data?.runtimeType}');
      debugPrint('   - data: ${response.data}');

      if (response.success && response.data != null) {
        try {
          List<UploadToken> tokens = [];
          
          if (response.data is List) {
            final dataList = response.data as List<dynamic>;
            tokens = dataList
                .map((e) => UploadToken.fromJson(e as Map<String, dynamic>))
                .toList();
          } else if (response.data is Map<String, dynamic>) {
            final dataMap = response.data as Map<String, dynamic>;
            if (dataMap['data'] is List) {
              final dataList = dataMap['data'] as List<dynamic>;
              tokens = dataList
                  .map((e) => UploadToken.fromJson(e as Map<String, dynamic>))
                  .toList();
            }
          }

          debugPrint('✅ [DOCUMENT_SERVICE] ${tokens.length} tokens encontrados');
          return ApiResponse.success(
            data: tokens,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [DOCUMENT_SERVICE] Erro ao parsear tokens: $e');
          return ApiResponse.error(
            message: 'Erro ao processar resposta do servidor',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar tokens',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [DOCUMENT_SERVICE] Erro ao buscar tokens: $e');
      return ApiResponse.error(
        message: 'Erro ao buscar tokens: ${e.toString()}',
        statusCode: 500,
      );
    }
  }

  /// Envia link por email
  Future<ApiResponse<void>> sendUploadTokenEmail(String tokenId) async {
    try {
      debugPrint('📧 [DOCUMENT_SERVICE] Enviando email do token $tokenId...');

      final response = await _apiService.post<dynamic>(
        ApiConstants.uploadTokenSendEmail(tokenId),
      );

      if (response.success) {
        debugPrint('✅ [DOCUMENT_SERVICE] Email enviado com sucesso');
        return ApiResponse.success(statusCode: response.statusCode);
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao enviar email',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [DOCUMENT_SERVICE] Erro ao enviar email: $e');
      return ApiResponse.error(
        message: 'Erro ao enviar email: ${e.toString()}',
        statusCode: 500,
      );
    }
  }

  /// Revoga um token
  Future<ApiResponse<void>> revokeUploadToken(String tokenId) async {
    try {
      debugPrint('🔒 [DOCUMENT_SERVICE] Revogando token $tokenId...');

      final response = await _apiService.put<dynamic>(
        ApiConstants.uploadTokenRevoke(tokenId),
      );

      if (response.success) {
        debugPrint('✅ [DOCUMENT_SERVICE] Token revogado com sucesso');
        return ApiResponse.success(statusCode: response.statusCode);
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao revogar token',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [DOCUMENT_SERVICE] Erro ao revogar token: $e');
      return ApiResponse.error(
        message: 'Erro ao revogar token: ${e.toString()}',
        statusCode: 500,
      );
    }
  }
}

