import 'package:flutter/foundation.dart';
import 'company_service.dart';
import 'permission_service.dart';
import 'subscription_service.dart';
import 'secure_storage_service.dart';
import 'auth_service.dart';

/// Serviço de inicialização pós-login
class InitializationService {
  InitializationService._();

  static final InitializationService instance = InitializationService._();

  /// Resultado da inicialização
  bool _isInitialized = false;
  MyPermissionsResponse? _userPermissions;

  /// Verifica se está inicializado
  bool get isInitialized => _isInitialized;

  /// Obtém permissões do usuário
  MyPermissionsResponse? get userPermissions => _userPermissions;

  /// Inicializa o sistema após login
  /// Retorna true se inicialização foi bem-sucedida
  Future<bool> initialize({
    required User user,
    required bool rememberMe,
  }) async {
    try {
      debugPrint('🚀 [INIT_SERVICE] Iniciando processo de inicialização...');

      // Verificar tipo de usuário
      final isOwnerUser = user.owner == true;
      final isMasterOrAdmin = user.role == 'master' || user.role == 'admin';
      final shouldCheckSubscriptionFirst = isMasterOrAdmin && isOwnerUser;

      debugPrint('🔍 [INIT_SERVICE] Tipo de usuário - Owner: $isOwnerUser, Role: ${user.role}');

      // FLUXO ESPECIAL: MASTER/ADMIN com owner=true
      if (shouldCheckSubscriptionFirst) {
        debugPrint('👑 [INIT_SERVICE] Fluxo especial: Owner MASTER/ADMIN');

        // ETAPA 1: Verificar assinatura
        final subscriptionService = SubscriptionService.instance;
        final accessResponse = await subscriptionService.checkSubscriptionAccess();

        if (!accessResponse.success || accessResponse.data == null) {
          debugPrint('❌ [INIT_SERVICE] Erro ao verificar assinatura');
          return false;
        }

        final accessInfo = accessResponse.data!;
        debugPrint('📋 [INIT_SERVICE] Status da assinatura: ${accessInfo.status}');

        if (!accessInfo.hasAccess) {
          debugPrint('⚠️ [INIT_SERVICE] Usuário não tem acesso à assinatura');
          // O redirecionamento será feito pelo fluxo de login
          return false;
        }

        debugPrint('✅ [INIT_SERVICE] Assinatura válida, continuando...');
      }

      // ETAPA 2: Carregar companies
      debugPrint('🏢 [INIT_SERVICE] Carregando empresas...');
      final companyService = CompanyService.instance;
      final companiesResponse = await companyService.getCompanies();

      if (!companiesResponse.success) {
        // Se erro 404, usuário não tem empresas
        if (companiesResponse.statusCode == 404) {
          debugPrint('ℹ️ [INIT_SERVICE] Usuário não tem empresas (404)');
          await SecureStorageService.instance.clearCompanyId();
          // Continuar sem empresa para carregar permissões básicas
        } else {
          debugPrint('❌ [INIT_SERVICE] Erro ao carregar empresas: ${companiesResponse.message}');
          // Em caso de erro, tentar continuar com Company ID existente se houver
        }
      } else if (companiesResponse.data != null && companiesResponse.data!.isNotEmpty) {
        // Selecionar empresa preferida (matrix ou primeira)
        final preferredCompany = CompanyService.choosePreferredCompany(companiesResponse.data!);
        if (preferredCompany != null) {
          await SecureStorageService.instance.saveCompanyId(preferredCompany.id);
          debugPrint('✅ [INIT_SERVICE] Company ID selecionado: ${preferredCompany.id} (${preferredCompany.name})');
        }
      } else {
        // Garantir que uma empresa esteja selecionada (se houver empresas disponíveis)
        await companyService.ensureCompanySelected();
      }

      // ETAPA 3: Carregar permissões
      debugPrint('🔐 [INIT_SERVICE] Carregando permissões...');
      final companyId = await SecureStorageService.instance.getCompanyId();
      
      // Verificar cache primeiro
      final permissionService = PermissionService.instance;
      final cacheValid = await permissionService.isCacheValid(
        currentCompanyId: companyId,
        currentUserId: user.id,
      );

      if (cacheValid) {
        debugPrint('💾 [INIT_SERVICE] Usando cache de permissões');
        final cache = await permissionService.getPermissionsCache();
        if (cache != null) {
          _userPermissions = MyPermissionsResponse(
            userId: user.id,
            userName: user.name,
            userEmail: user.email,
            permissions: [],
            permissionNames: List<String>.from(cache['permissions'] as List? ?? []),
          );
        }
      }

      // Se não tem cache válido, carregar da API
      if (_userPermissions == null) {
        debugPrint('📡 [INIT_SERVICE] Carregando permissões da API...');
        final permissionsResponse = await permissionService.getMyPermissions();

        if (permissionsResponse.success && permissionsResponse.data != null) {
          _userPermissions = permissionsResponse.data!;
          
          // Salvar no cache
          await permissionService.savePermissionsCache(
            permissions: _userPermissions!.permissionNames,
            role: user.role,
            companyId: companyId,
            userId: user.id,
          );
          debugPrint('✅ [INIT_SERVICE] Permissões carregadas e salvas no cache');
        } else {
          debugPrint('❌ [INIT_SERVICE] Erro ao carregar permissões: ${permissionsResponse.message}');
          return false;
        }
      }

      _isInitialized = true;
      debugPrint('✅ [INIT_SERVICE] Inicialização concluída com sucesso');
      return true;
    } catch (e, stackTrace) {
      debugPrint('❌ [INIT_SERVICE] Erro durante inicialização: $e');
      debugPrint('📚 [INIT_SERVICE] StackTrace: $stackTrace');
      return false;
    }
  }

  /// Limpa dados de inicialização
  void clear() {
    _isInitialized = false;
    _userPermissions = null;
    debugPrint('🧹 [INIT_SERVICE] Dados de inicialização limpos');
  }

  /// Verifica se usuário tem uma permissão específica
  bool hasPermission(String permissionName) {
    if (_userPermissions == null) return false;
    return _userPermissions!.permissionNames.contains(permissionName);
  }

  /// Verifica se usuário tem permissões válidas
  bool hasValidPermissions() {
    if (_userPermissions == null) return false;
    return _userPermissions!.permissionNames.isNotEmpty;
  }
}

