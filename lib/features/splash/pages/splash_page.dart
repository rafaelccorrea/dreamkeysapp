import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../../../../core/routes/app_routes.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../shared/services/auth_service.dart';
import '../../../../shared/services/api_service.dart';
import '../../../../shared/services/biometric_service.dart';
import '../../../../shared/services/secure_storage_service.dart';
import '../../../../shared/services/token_refresh_service.dart';
import '../../../../shared/services/company_service.dart';
import '../../../../shared/services/module_access_service.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();

    // Configurar animações
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    // Animação de fade
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    // Animação de escala
    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
      ),
    );

    // Animação de slide (sutil)
    _slideAnimation = Tween<double>(
      begin: 20.0,
      end: 0.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
      ),
    );

    // Iniciar animação
    _controller.forward();

    // Verificar autenticação e navegar
    _checkAuthenticationAndNavigate();
  }

  /// Verifica autenticação e navega para a tela apropriada
  Future<void> _checkAuthenticationAndNavigate() async {
    try {
      // Aguardar um pouco para a animação aparecer
      await Future.delayed(const Duration(milliseconds: 1500));

      if (!mounted) return;

      // Inicializar ApiService e carregar token salvo
      await ApiService.instance.initialize();
      await AuthService.instance.loadSavedToken();

      // Verificar se está autenticado
      final isAuthenticated = await AuthService.instance.isAuthenticated();

      if (!mounted) return;

      if (isAuthenticated) {
        // Iniciar serviço de refresh periódico em background
        TokenRefreshService.instance.startPeriodicRefresh();
        debugPrint('🔄 [SPLASH] Serviço de refresh periódico iniciado');

        // Garantir que uma empresa esteja selecionada (matrix ou primeira)
        final companyService = CompanyService.instance;
        await companyService.ensureCompanySelected();
        debugPrint('✅ [SPLASH] Empresa garantida (se houver empresas disponíveis)');

        // Inicializar ModuleAccessService
        debugPrint('🔄 [SPLASH] Inicializando ModuleAccessService...');
        await ModuleAccessService.instance.initialize();
        debugPrint('✅ [SPLASH] ModuleAccessService inicializado');

        // Verificar se há credenciais salvas e biometria disponível
        final hasCredentials = await SecureStorageService.instance.hasSavedCredentials();
        final biometricService = BiometricService.instance;
        final hasBiometrics = await biometricService.hasBiometrics();
        
        debugPrint('🔍 [SPLASH] Verificando biometria - Credenciais: $hasCredentials, Biometria: $hasBiometrics');
        
        // Se há credenciais salvas e biometria disponível, solicitar biometria
        if (hasCredentials && hasBiometrics) {
          debugPrint('👆 [SPLASH] Solicitando autenticação biométrica...');
          final biometricType = await biometricService.getBiometricTypeDescription();
          final authenticated = await biometricService.authenticate(
            reason: 'Use $biometricType para acessar o app',
          );
          
          if (!authenticated) {
            debugPrint('❌ [SPLASH] Autenticação biométrica cancelada ou falhou');
            // Se biometria falhar, ir para login
            if (mounted) {
              TokenRefreshService.instance.stopPeriodicRefresh();
              Navigator.of(context).pushReplacementNamed(AppRoutes.login);
            }
            return;
          }
          
          debugPrint('✅ [SPLASH] Autenticação biométrica bem-sucedida');
        }
        
        // Tentar validar o token fazendo uma requisição simples
        // Se falhar, o refresh token será tentado automaticamente
        debugPrint('✅ [SPLASH] Usuário autenticado, redirecionando para home...');
        
        // Navegar para home
        if (mounted) {
          Navigator.of(context).pushReplacementNamed(AppRoutes.home);
        }
      } else {
        debugPrint('ℹ️ [SPLASH] Usuário não autenticado, redirecionando para login...');
        // Navegar para login
        Navigator.of(context).pushReplacementNamed(AppRoutes.login);
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [SPLASH] Erro ao verificar autenticação: $e');
      debugPrint('📚 [SPLASH] StackTrace: $stackTrace');
      
      if (mounted) {
        // Em caso de erro, ir para login
        Navigator.of(context).pushReplacementNamed(AppRoutes.login);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    // Não parar o refresh periódico aqui, pois ele deve continuar rodando
    // mesmo após a splash desaparecer
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF111827)
          : const Color(0xFFFFFFFF),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo com animações
                Opacity(
                  opacity: _fadeAnimation.value,
                  child: Transform.translate(
                    offset: Offset(0, _slideAnimation.value),
                    child: Transform.scale(
                      scale: _scaleAnimation.value,
                      child: Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.primary.withOpacity(0.2),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(30),
                          child: Image.asset(
                            AppAssets.logo,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                // Nome da aplicação com fade
                Opacity(
                  opacity: _fadeAnimation.value,
                  child: Text(
                    'Dream Keys',
                    style: theme.textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 60),
                // Indicador de carregamento sutil
                Opacity(
                  opacity: _fadeAnimation.value,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
