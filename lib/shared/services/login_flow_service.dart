import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'initialization_service.dart';
import 'subscription_service.dart';
import 'company_service.dart';
import 'secure_storage_service.dart';
import '../../core/routes/app_routes.dart';

/// Serviço para gerenciar o fluxo completo de login
class LoginFlowService {
  LoginFlowService._();

  static final LoginFlowService instance = LoginFlowService._();

  /// Executa o fluxo completo de login conforme a documentação
  Future<LoginFlowResult> executeLoginFlow({
    required String email,
    required String password,
    required bool rememberMe,
    required BuildContext context,
  }) async {
    try {
      debugPrint('🚀 [LOGIN_FLOW] Iniciando fluxo de login...');

      // ETAPA 1: Verificar se requer 2FA (opcional - se falhar, continuar com login normal)
      debugPrint('🔍 [LOGIN_FLOW] Verificando status de 2FA...');
      final authService = AuthService.instance;
      
      bool requires2FA = false;
      bool hasTwoFactorConfigured = false;
      
      try {
        final check2FAResponse = await authService.check2FA(email);

        if (check2FAResponse.success && check2FAResponse.data != null) {
          final check2FA = check2FAResponse.data!;
          requires2FA = check2FA.requires2FA && check2FA.emailExists;
          hasTwoFactorConfigured = check2FA.hasTwoFactorConfigured;
          debugPrint('📋 [LOGIN_FLOW] 2FA - Requer: $requires2FA, Configurado: $hasTwoFactorConfigured');
        } else {
          debugPrint('⚠️ [LOGIN_FLOW] Não foi possível verificar 2FA, continuando com login normal');
          debugPrint('   Status: ${check2FAResponse.statusCode}, Mensagem: ${check2FAResponse.message}');
          // Continuar com login normal - o backend decidirá se precisa de 2FA
        }
      } catch (e) {
        debugPrint('⚠️ [LOGIN_FLOW] Erro ao verificar 2FA: $e');
        debugPrint('   Continuando com login normal...');
        // Continuar com login normal - o backend decidirá se precisa de 2FA
      }

      // Se requer 2FA e usuário configurou, retornar para abrir modal/tela de 2FA
      if (requires2FA && hasTwoFactorConfigured) {
        debugPrint('🔐 [LOGIN_FLOW] 2FA requerido - fazendo login para obter tempToken');
        
        // Fazer login para obter tempToken
        final loginRequest = LoginRequest(email: email, password: password);
        final loginResponse = await authService.login(loginRequest);

        if (!loginResponse.success || loginResponse.data == null) {
          // Verificar códigos de erro específicos do endpoint de broker
          if (loginResponse.statusCode == 401 && loginResponse.error != null) {
            final errorCode = loginResponse.error['errorCode']?.toString();
            final details = loginResponse.error['details'];
            
            // 2FA_REQUIRED - Requer verificação de 2FA
            if (errorCode == '2FA_REQUIRED') {
              final tempToken = loginResponse.error['tempToken']?.toString() ?? '';
              if (tempToken.isNotEmpty) {
                return LoginFlowResult.requires2FA(
                  tempToken: tempToken,
                  email: email,
                  password: password,
                  rememberMe: rememberMe,
                );
              }
            }
            
            // 2FA_SETUP_REQUIRED - 2FA obrigatório mas não configurado
            if (errorCode == '2FA_SETUP_REQUIRED') {
              final suggestion = details?['suggestion']?.toString() ?? 
                  'Configure o 2FA através das configurações antes de fazer login';
              return LoginFlowResult.error(
                message: 'Autenticação de dois fatores é obrigatória para sua empresa. $suggestion',
              );
            }
            
            // INVALID_USER_ROLE - Usuário não é corretor
            if (errorCode == 'INVALID_USER_ROLE') {
              final suggestion = details?['suggestion']?.toString() ?? 
                  'Use a rota de login padrão';
              return LoginFlowResult.error(
                message: 'Esta rota é exclusiva para corretores. $suggestion',
              );
            }
            
            // NO_COMPANY_ASSOCIATION - Usuário sem empresa associada
            if (errorCode == 'NO_COMPANY_ASSOCIATION') {
              final suggestion = details?['suggestion']?.toString() ?? 
                  'Entre em contato com o administrador para associar seu usuário a uma empresa';
              return LoginFlowResult.error(
                message: 'Usuário não está associado a nenhuma empresa. $suggestion',
              );
            }
            
            // INVALID_CREDENTIALS - Credenciais inválidas
            if (errorCode == 'INVALID_CREDENTIALS') {
              final suggestion = details?['suggestion']?.toString() ?? 
                  'Verifique suas credenciais e tente novamente';
              return LoginFlowResult.error(
                message: 'Email ou senha incorretos. $suggestion',
              );
            }
          }
          
          return LoginFlowResult.error(
            message: loginResponse.message ?? 'Erro ao fazer login',
          );
        }
      }

      // Se requer 2FA mas usuário não configurou, retornar erro
      if (requires2FA && !hasTwoFactorConfigured) {
        return LoginFlowResult.error(
          message: 'Autenticação de dois fatores requerida mas não configurada',
        );
      }

      // ETAPA 2: Login direto (sem 2FA)
      debugPrint('🔑 [LOGIN_FLOW] Fazendo login direto...');
      final loginRequest = LoginRequest(email: email, password: password);
      final loginResponse = await authService.login(loginRequest);

      if (!loginResponse.success || loginResponse.data == null) {
        // Verificar códigos de erro específicos do endpoint de broker
        if (loginResponse.statusCode == 401 && loginResponse.error != null) {
          final errorCode = loginResponse.error['errorCode']?.toString();
          final details = loginResponse.error['details'];
          
          // 2FA_REQUIRED - Requer verificação de 2FA
          if (errorCode == '2FA_REQUIRED') {
            final tempToken = loginResponse.error['tempToken']?.toString() ?? '';
            if (tempToken.isNotEmpty) {
              return LoginFlowResult.requires2FA(
                tempToken: tempToken,
                email: email,
                password: password,
                rememberMe: rememberMe,
              );
            }
          }
          
          // 2FA_SETUP_REQUIRED - 2FA obrigatório mas não configurado
          if (errorCode == '2FA_SETUP_REQUIRED') {
            final suggestion = details?['suggestion']?.toString() ?? 
                'Configure o 2FA através das configurações antes de fazer login';
            return LoginFlowResult.error(
              message: 'Autenticação de dois fatores é obrigatória para sua empresa. $suggestion',
            );
          }
          
          // INVALID_USER_ROLE - Usuário não é corretor
          if (errorCode == 'INVALID_USER_ROLE') {
            final suggestion = details?['suggestion']?.toString() ?? 
                'Use a rota de login padrão';
            return LoginFlowResult.error(
              message: 'Esta rota é exclusiva para corretores. $suggestion',
            );
          }
          
          // NO_COMPANY_ASSOCIATION - Usuário sem empresa associada
          if (errorCode == 'NO_COMPANY_ASSOCIATION') {
            final suggestion = details?['suggestion']?.toString() ?? 
                'Entre em contato com o administrador para associar seu usuário a uma empresa';
            return LoginFlowResult.error(
              message: 'Usuário não está associado a nenhuma empresa. $suggestion',
            );
          }
          
          // INVALID_CREDENTIALS - Credenciais inválidas
          if (errorCode == 'INVALID_CREDENTIALS') {
            final suggestion = details?['suggestion']?.toString() ?? 
                'Verifique suas credenciais e tente novamente';
            return LoginFlowResult.error(
              message: 'Email ou senha incorretos. $suggestion',
            );
          }
        }

        // Erro genérico
        return LoginFlowResult.error(
          message: loginResponse.message ?? 'Erro ao realizar login',
        );
      }

      // ETAPA 3: handleAuthSuccess - Inicialização
      debugPrint('✅ [LOGIN_FLOW] Login bem-sucedido, iniciando inicialização...');
      return await _handleAuthSuccess(
        loginResponse: loginResponse.data!,
        user: loginResponse.data!.user,
        rememberMe: rememberMe,
        context: context,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [LOGIN_FLOW] Erro no fluxo de login: $e');
      debugPrint('📚 [LOGIN_FLOW] StackTrace: $stackTrace');
      return LoginFlowResult.error(
        message: 'Erro ao realizar login: ${e.toString()}',
      );
    }
  }

  /// Executa o fluxo após verificação de 2FA
  Future<LoginFlowResult> executeAfter2FA({
    required LoginResponse loginResponse,
    required bool rememberMe,
    required BuildContext context,
  }) async {
    debugPrint('✅ [LOGIN_FLOW] 2FA verificado, continuando fluxo...');
    return await _handleAuthSuccess(
      loginResponse: loginResponse,
      user: loginResponse.user,
      rememberMe: rememberMe,
      context: context,
    );
  }

  /// Gerencia o sucesso da autenticação e inicialização
  Future<LoginFlowResult> _handleAuthSuccess({
    required LoginResponse loginResponse,
    required User user,
    required bool rememberMe,
    required BuildContext context,
  }) async {
    try {
      // Verificar tipo de usuário
      final isOwnerUser = user.owner == true;
      final isMasterOrAdmin = user.role == 'master' || user.role == 'admin';
      final shouldCheckSubscriptionFirst = isMasterOrAdmin && isOwnerUser;

      debugPrint('🔍 [LOGIN_FLOW] Tipo de usuário - Owner: $isOwnerUser, Role: ${user.role}');

      // FLUXO ESPECIAL: MASTER/ADMIN com owner=true
      if (shouldCheckSubscriptionFirst) {
        debugPrint('👑 [LOGIN_FLOW] Fluxo especial: Owner MASTER/ADMIN');

        // ETAPA 1: Verificar assinatura
        final subscriptionService = SubscriptionService.instance;
        final accessResponse = await subscriptionService.checkSubscriptionAccess();

        if (!accessResponse.success || accessResponse.data == null) {
          debugPrint('❌ [LOGIN_FLOW] Erro ao verificar assinatura');
          return LoginFlowResult.error(
            message: 'Erro ao verificar acesso à assinatura',
          );
        }

        final accessInfo = accessResponse.data!;
        debugPrint('📋 [LOGIN_FLOW] Status da assinatura: ${accessInfo.status}');

        if (!accessInfo.hasAccess) {
          if (accessInfo.status == 'none') {
            return LoginFlowResult.redirect(
              route: '/subscription-plans', // TODO: Criar rota
              message: 'Nenhuma assinatura encontrada',
            );
          } else {
            return LoginFlowResult.redirect(
              route: '/subscription-management', // TODO: Criar rota
              message: 'Assinatura expirada ou suspensa',
            );
          }
        }

        debugPrint('✅ [LOGIN_FLOW] Assinatura válida, continuando...');
      }

      // ETAPA 2: Carregar companies
      debugPrint('🏢 [LOGIN_FLOW] Carregando empresas...');
      final companyService = CompanyService.instance;
      final companiesResponse = await companyService.getCompanies();

      String? selectedCompanyId;

      if (!companiesResponse.success) {
        // Se erro 404, usuário não tem empresas
        if (companiesResponse.statusCode == 404) {
          debugPrint('ℹ️ [LOGIN_FLOW] Usuário não tem empresas (404)');
          await SecureStorageService.instance.clearCompanyId();
          
          // Se é master/admin, redirecionar para criar empresa
          if (isMasterOrAdmin) {
            return LoginFlowResult.redirect(
              route: '/create-first-company', // TODO: Criar rota
              message: 'Nenhuma empresa encontrada',
            );
          }
        } else {
          debugPrint('⚠️ [LOGIN_FLOW] Erro ao carregar empresas: ${companiesResponse.message}');
          // Tentar continuar com Company ID existente se houver
          selectedCompanyId = await SecureStorageService.instance.getCompanyId();
        }
      } else if (companiesResponse.data != null && companiesResponse.data!.isNotEmpty) {
        // Selecionar empresa preferida (matrix ou primeira)
        final preferredCompany = CompanyService.choosePreferredCompany(companiesResponse.data!);
        if (preferredCompany != null) {
          selectedCompanyId = preferredCompany.id;
          await SecureStorageService.instance.saveCompanyId(selectedCompanyId);
          debugPrint('✅ [LOGIN_FLOW] Company ID selecionado: $selectedCompanyId (${preferredCompany.name})');
        }
      } else {
        // Garantir que uma empresa esteja selecionada (se houver empresas disponíveis)
        await companyService.ensureCompanySelected();
        selectedCompanyId = await SecureStorageService.instance.getCompanyId();
      }

      // Se é master/admin e tem empresas, redirecionar direto para dashboard
      if (isMasterOrAdmin && selectedCompanyId != null) {
        debugPrint('👑 [LOGIN_FLOW] Master/Admin com empresa - redirecionando para dashboard');
        return LoginFlowResult.success(
          route: AppRoutes.home,
          message: 'Login bem-sucedido',
        );
      }

      // ETAPA 3: Inicializar sistema (carregar permissões)
      debugPrint('🔐 [LOGIN_FLOW] Inicializando sistema...');
      final initializationService = InitializationService.instance;
      final initialized = await initializationService.initialize(
        user: user,
        rememberMe: rememberMe,
      );

      if (!initialized) {
        debugPrint('❌ [LOGIN_FLOW] Falha na inicialização');
        return LoginFlowResult.error(
          message: 'Erro ao inicializar sistema',
        );
      }

      // ETAPA 4: Redirecionar
      debugPrint('✅ [LOGIN_FLOW] Fluxo concluído com sucesso');
      return LoginFlowResult.success(
        route: AppRoutes.home,
        message: 'Login bem-sucedido',
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [LOGIN_FLOW] Erro em handleAuthSuccess: $e');
      debugPrint('📚 [LOGIN_FLOW] StackTrace: $stackTrace');
      return LoginFlowResult.error(
        message: 'Erro ao processar login: ${e.toString()}',
      );
    }
  }
}

/// Resultado do fluxo de login
class LoginFlowResult {
  final bool success;
  final String? route;
  final String message;
  final bool requires2FA;
  final String? tempToken;
  final String? email;
  final String? password;
  final bool? rememberMe;

  LoginFlowResult({
    required this.success,
    this.route,
    required this.message,
    this.requires2FA = false,
    this.tempToken,
    this.email,
    this.password,
    this.rememberMe,
  });

  factory LoginFlowResult.success({
    required String route,
    required String message,
  }) {
    return LoginFlowResult(
      success: true,
      route: route,
      message: message,
    );
  }

  factory LoginFlowResult.error({
    required String message,
  }) {
    return LoginFlowResult(
      success: false,
      message: message,
    );
  }

  factory LoginFlowResult.requires2FA({
    required String tempToken,
    required String email,
    required String password,
    required bool rememberMe,
  }) {
    return LoginFlowResult(
      success: false,
      message: 'Autenticação de dois fatores requerida',
      requires2FA: true,
      tempToken: tempToken,
      email: email,
      password: password,
      rememberMe: rememberMe,
    );
  }

  factory LoginFlowResult.redirect({
    required String route,
    required String message,
  }) {
    return LoginFlowResult(
      success: true,
      route: route,
      message: message,
    );
  }
}

