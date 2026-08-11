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

/// Desfecho de [CompanyService.resolveAndPersistPreferredCompany].
class CompanySelection {
  /// Empresa resolvida e já gravada no armazenamento seguro.
  final String? companyId;

  /// Servidor confirmou que o utilizador não tem nenhuma empresa.
  final bool userHasNoCompany;

  /// Não deu para concluir (rede/servidor) — tentar de novo depois.
  final bool failed;

  const CompanySelection({
    this.companyId,
    this.userHasNoCompany = false,
    this.failed = false,
  });
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

  /// Carrega `/companies`, escolhe a preferida e **persiste** o ID.
  ///
  /// Fonte ÚNICA da seleção de empresa: usada pelo `LoginFlowService`
  /// (logo após o login) e pelo `SessionBootstrap` (boot, login biométrico,
  /// deep link, recuperação da Home). Antes essa lógica estava duplicada
  /// entre o fluxo de login e o `ensureCompanySelected`, e cada caminho de
  /// entrada no app resolvia — ou esquecia de resolver — a empresa à sua
  /// maneira. Era daí que nascia a corrida do "Company ID não encontrado".
  ///
  /// Distingue os três desfechos, que exigem tratamentos diferentes:
  ///   - empresa resolvida → [CompanySelection.companyId];
  ///   - utilizador sem nenhuma empresa (404 ou lista vazia) → diagnóstico
  ///     REAL, único caso em que a mensagem de erro de empresa é legítima;
  ///   - falha de rede/servidor → não conclui nada e preserva o ID atual.
  Future<CompanySelection> resolveAndPersistPreferredCompany() async {
    try {
      final companiesResponse = await getCompanies();

      if (!companiesResponse.success) {
        if (companiesResponse.statusCode == 404) {
          debugPrint('ℹ️ [COMPANY_SERVICE] Utilizador não tem empresas (404)');
          await SecureStorageService.instance.clearCompanyId();
          return const CompanySelection(userHasNoCompany: true);
        }
        debugPrint(
          '⚠️ [COMPANY_SERVICE] Erro ao carregar empresas: ${companiesResponse.message}',
        );
        // Erro de transporte: mantém o que já estiver gravado em vez de
        // apagar uma seleção válida por causa de uma queda de rede.
        final current = await SecureStorageService.instance.getCompanyId();
        return CompanySelection(companyId: current, failed: true);
      }

      final companies = companiesResponse.data;
      if (companies == null || companies.isEmpty) {
        debugPrint('ℹ️ [COMPANY_SERVICE] Lista de empresas vazia');
        return const CompanySelection(userHasNoCompany: true);
      }

      final preferredCompany = choosePreferredCompany(companies);
      if (preferredCompany == null) {
        return const CompanySelection(userHasNoCompany: true);
      }

      await SecureStorageService.instance.saveCompanyId(preferredCompany.id);
      debugPrint(
        '✅ [COMPANY_SERVICE] Empresa selecionada: ${preferredCompany.id} (${preferredCompany.name})',
      );
      return CompanySelection(companyId: preferredCompany.id);
    } catch (e, stackTrace) {
      debugPrint('❌ [COMPANY_SERVICE] Erro ao resolver empresa: $e');
      debugPrint('📚 [COMPANY_SERVICE] StackTrace: $stackTrace');
      return const CompanySelection(failed: true);
    }
  }

  /// Garante que uma empresa esteja selecionada (seleciona automaticamente se necessário)
  Future<void> ensureCompanySelected() async {
    final currentCompanyId = await SecureStorageService.instance.getCompanyId();
    if (currentCompanyId != null && currentCompanyId.isNotEmpty) {
      debugPrint('ℹ️ [COMPANY_SERVICE] Empresa já selecionada: $currentCompanyId');
      return;
    }

    debugPrint(
      '🔄 [COMPANY_SERVICE] Nenhuma empresa selecionada, buscando empresas...',
    );
    await resolveAndPersistPreferredCompany();
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

