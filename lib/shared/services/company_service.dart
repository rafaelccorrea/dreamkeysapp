import 'package:flutter/foundation.dart';
import '../../core/constants/api_constants.dart';
import 'api_service.dart';
import 'secure_storage_service.dart';

/// Modelo de Company
class Company {
  final String id;
  final String name;
  final bool isMatrix;
  final List<String> availableModules;

  Company({
    required this.id,
    required this.name,
    required this.isMatrix,
    required this.availableModules,
  });

  factory Company.fromJson(Map<String, dynamic> json) {
    return Company(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      isMatrix: json['isMatrix'] as bool? ?? false,
      availableModules: json['availableModules'] != null
          ? List<String>.from((json['availableModules'] as List).map((e) => e.toString()))
          : [],
    );
  }
}

/// Serviço para gerenciar empresas
class CompanyService {
  CompanyService._();

  static final CompanyService instance = CompanyService._();
  final ApiService _apiService = ApiService.instance;

  /// Busca todas as empresas do usuário
  Future<ApiResponse<List<Company>>> getCompanies() async {
    try {
      final response = await _apiService.get<List<dynamic>>(
        ApiConstants.companies,
      );

      if (response.success && response.data != null) {
        final companies = (response.data as List)
            .map((json) => Company.fromJson(json as Map<String, dynamic>))
            .toList();
        
        debugPrint('✅ [COMPANY_SERVICE] ${companies.length} empresas carregadas');
        return ApiResponse.success(
          data: companies,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar empresas',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [COMPANY_SERVICE] Erro ao carregar empresas: $e');
      debugPrint('📚 [COMPANY_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro ao carregar empresas: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Busca uma empresa por ID
  Future<ApiResponse<Company>> getCompanyById(String companyId) async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '${ApiConstants.companies}/$companyId',
      );

      if (response.success && response.data != null) {
        final company = Company.fromJson(response.data!);
        debugPrint('✅ [COMPANY_SERVICE] Empresa carregada: ${company.name}');
        return ApiResponse.success(
          data: company,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar empresa',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [COMPANY_SERVICE] Erro ao carregar empresa: $e');
      debugPrint('📚 [COMPANY_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro ao carregar empresa: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Seleciona a empresa preferida (prioriza isMatrix, senão primeira)
  static Company? choosePreferredCompany(List<Company> companies) {
    if (companies.isEmpty) return null;

    // Prioridade 1: Empresa com isMatrix === true
    try {
      final matrixCompany = companies.firstWhere(
        (c) => c.isMatrix == true,
      );
      debugPrint('✅ [COMPANY_SERVICE] Empresa Matrix encontrada: ${matrixCompany.name}');
      return matrixCompany;
    } catch (e) {
      // Se não encontrou matrix, retornar primeira
      debugPrint('ℹ️ [COMPANY_SERVICE] Nenhuma empresa Matrix encontrada, usando primeira: ${companies.first.name}');
      return companies.first;
    }
  }

  /// Garante que uma empresa esteja selecionada (seleciona automaticamente se necessário)
  Future<void> ensureCompanySelected() async {
    try {
      // Verificar se já tem uma empresa selecionada
      final currentCompanyId = await SecureStorageService.instance.getCompanyId();
      if (currentCompanyId != null && currentCompanyId.isNotEmpty) {
        debugPrint('ℹ️ [COMPANY_SERVICE] Empresa já selecionada: $currentCompanyId');
        return;
      }

      // Se não tem empresa selecionada, buscar e selecionar
      debugPrint('🔄 [COMPANY_SERVICE] Nenhuma empresa selecionada, buscando empresas...');
      final companiesResponse = await getCompanies();

      if (companiesResponse.success &&
          companiesResponse.data != null &&
          companiesResponse.data!.isNotEmpty) {
        final preferredCompany = choosePreferredCompany(companiesResponse.data!);
        if (preferredCompany != null) {
          await SecureStorageService.instance.saveCompanyId(preferredCompany.id);
          debugPrint('✅ [COMPANY_SERVICE] Empresa selecionada automaticamente: ${preferredCompany.name}');
        }
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [COMPANY_SERVICE] Erro ao garantir seleção de empresa: $e');
      debugPrint('📚 [COMPANY_SERVICE] StackTrace: $stackTrace');
    }
  }

  /// Busca a empresa atualmente selecionada
  Future<ApiResponse<Company?>> getSelectedCompany() async {
    try {
      final companyId = await SecureStorageService.instance.getCompanyId();
      
      if (companyId == null || companyId.isEmpty) {
        debugPrint('ℹ️ [COMPANY_SERVICE] Nenhuma empresa selecionada');
        return ApiResponse.success(data: null, statusCode: 200);
      }

      final response = await getCompanyById(companyId);
      return ApiResponse.success(
        data: response.success ? response.data : null,
        statusCode: response.statusCode,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [COMPANY_SERVICE] Erro ao buscar empresa selecionada: $e');
      debugPrint('📚 [COMPANY_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro ao buscar empresa selecionada: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Define a empresa ativa (`X-Company-ID`). Usado por utilizadores Master ao mudar de contexto.
  Future<ApiResponse<void>> setSelectedCompany(String companyId) async {
    if (companyId.isEmpty) {
      return ApiResponse.error(
        message: 'Empresa inválida',
        statusCode: 0,
      );
    }

    try {
      final accessible = await isCompanyAccessible(companyId);
      if (!accessible) {
        debugPrint(
          '⚠️ [COMPANY_SERVICE] ID $companyId não está na lista de empresas do utilizador',
        );
        return ApiResponse.error(
          message: 'Sem acesso a esta empresa',
          statusCode: 403,
        );
      }

      await SecureStorageService.instance.saveCompanyId(companyId);
      debugPrint('✅ [COMPANY_SERVICE] Empresa ativa atualizada: $companyId');
      return ApiResponse.success(data: null, statusCode: 200);
    } catch (e, stackTrace) {
      debugPrint('❌ [COMPANY_SERVICE] Erro ao selecionar empresa: $e');
      debugPrint('📚 [COMPANY_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro ao trocar de empresa',
        statusCode: 0,
      );
    }
  }

  /// Indica se o utilizador pode aceder ao ID na lista atual de `/companies`.
  Future<bool> isCompanyAccessible(String companyId) async {
    final r = await getCompanies();
    if (!r.success || r.data == null) return false;
    return r.data!.any((c) => c.id == companyId);
  }
}

