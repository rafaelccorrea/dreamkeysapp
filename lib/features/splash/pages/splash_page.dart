import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import '../../../../core/routes/app_routes.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/services/auth_service.dart';
import '../../../../shared/services/api_service.dart';
import '../../../../shared/services/token_refresh_service.dart';
import '../../../../shared/services/company_service.dart';
import '../../../../shared/services/module_access_service.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _shimmerController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _slideAnimation;
  late Animation<double> _shimmerAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // Controlador principal para fade, scale e slide
    _mainController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );

    // Controlador para efeito shimmer no logo
    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();

    // Controlador para pulsação do logo
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    // Animação de fade
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
      ),
    );

    // Animação de escala com bounce
    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.7, curve: Curves.elasticOut),
      ),
    );

    // Animação de slide
    _slideAnimation = Tween<double>(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic),
      ),
    );

    // Animação shimmer
    _shimmerAnimation = Tween<double>(begin: -2.0, end: 2.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );

    // Animação de pulsação sutil
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Iniciar animação principal
    _mainController.forward();

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
        debugPrint(
          '✅ [SPLASH] Empresa garantida (se houver empresas disponíveis)',
        );

        // Inicializar ModuleAccessService
        debugPrint('🔄 [SPLASH] Inicializando ModuleAccessService...');
        await ModuleAccessService.instance.initialize();
        debugPrint('✅ [SPLASH] ModuleAccessService inicializado');

        // NOTA: Biometria não é solicitada aqui porque o usuário já está autenticado.
        // A biometria deve ser usada apenas no login, não toda vez que o app abre.
        // Se o token for válido, o usuário pode acessar o app diretamente.

        // Tentar validar o token fazendo uma requisição simples
        // Se falhar, o refresh token será tentado automaticamente
        debugPrint(
          '✅ [SPLASH] Usuário autenticado, redirecionando para home...',
        );

        // Navegar para home
        if (mounted) {
          Navigator.of(context).pushReplacementNamed(AppRoutes.home);
        }
      } else {
        debugPrint(
          'ℹ️ [SPLASH] Usuário não autenticado, redirecionando para login...',
        );
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
    _mainController.dispose();
    _shimmerController.dispose();
    _pulseController.dispose();
    // Não parar o refresh periódico aqui, pois ele deve continuar rodando
    // mesmo após a splash desaparecer
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
    final primaryLight = isDark
        ? AppColors.primary.primaryLightDarkMode
        : AppColors.primary.primaryLight;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    const Color(0xFF0F172A),
                    const Color(0xFF1E293B),
                    const Color(0xFF111827),
                  ]
                : [
                    const Color(0xFFFFFFFF),
                    const Color(0xFFF8FAFC),
                    const Color(0xFFF1F5F9),
                  ],
          ),
        ),
        child: Stack(
          children: [
            // Círculos decorativos animados
            ..._buildAnimatedCircles(context, isDark),

            // Conteúdo principal
            AnimatedBuilder(
              animation: Listenable.merge([
                _mainController,
                _shimmerController,
                _pulseController,
              ]),
              builder: (context, child) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo com animações e efeitos
                      _buildAnimatedLogo(
                        context,
                        theme,
                        primaryColor,
                        primaryLight,
                        isDark,
                      ),
                      const SizedBox(height: 32),

                      // Nome da aplicação com fade e slide
                      Opacity(
                        opacity: _fadeAnimation.value,
                        child: Transform.translate(
                          offset: Offset(0, _slideAnimation.value * 0.5),
                          child: ShaderMask(
                            shaderCallback: (bounds) => LinearGradient(
                              colors: [primaryColor, primaryLight],
                            ).createShader(bounds),
                            child: Text(
                              'Dream Keys',
                              style: GoogleFonts.poppins(
                                fontSize: 48,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.5,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Subtítulo sutil
                      Opacity(
                        opacity: _fadeAnimation.value * 0.7,
                        child: Text(
                          'Sistema Imobiliário',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? AppColors.text.textSecondaryDarkMode
                                      .withOpacity(0.7)
                                : AppColors.text.textSecondary.withOpacity(0.7),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 64),

                      // Indicador de carregamento moderno
                      Opacity(
                        opacity: _fadeAnimation.value,
                        child: _buildModernLoader(context, primaryColor),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Constrói o logo com animações e efeitos visuais
  Widget _buildAnimatedLogo(
    BuildContext context,
    ThemeData theme,
    Color primaryColor,
    Color primaryLight,
    bool isDark,
  ) {
    return Opacity(
      opacity: _fadeAnimation.value,
      child: Transform.translate(
        offset: Offset(0, _slideAnimation.value),
        child: Transform.scale(
          scale: _scaleAnimation.value * _pulseAnimation.value,
          child: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: primaryColor.withOpacity(0.3),
                  blurRadius: 40,
                  spreadRadius: 8,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: primaryColor.withOpacity(0.1),
                  blurRadius: 60,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Stack(
              children: [
                // Container com gradiente
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        primaryColor.withOpacity(0.1),
                        primaryLight.withOpacity(0.05),
                      ],
                    ),
                  ),
                ),

                // Logo
                ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: Image.asset(
                    AppAssets.logo,
                    fit: BoxFit.contain,
                    width: 140,
                    height: 140,
                  ),
                ),

                // Efeito shimmer
                AnimatedBuilder(
                  animation: _shimmerAnimation,
                  builder: (context, child) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(32),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment(_shimmerAnimation.value - 1, 0),
                            end: Alignment(_shimmerAnimation.value, 0),
                            colors: [
                              Colors.transparent,
                              primaryColor.withOpacity(0.2),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Constrói círculos decorativos animados
  List<Widget> _buildAnimatedCircles(BuildContext context, bool isDark) {
    return [
      // Círculo 1 - Superior esquerdo
      Positioned(
        top: -100,
        left: -100,
        child: AnimatedBuilder(
          animation: _mainController,
          builder: (context, child) {
            return Transform.scale(
              scale: _fadeAnimation.value,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      (isDark
                              ? AppColors.primary.primaryDarkMode
                              : AppColors.primary.primary)
                          .withOpacity(0.1),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),

      // Círculo 2 - Inferior direito
      Positioned(
        bottom: -150,
        right: -150,
        child: AnimatedBuilder(
          animation: _mainController,
          builder: (context, child) {
            return Transform.scale(
              scale: _fadeAnimation.value * 0.8,
              child: Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      (isDark
                              ? AppColors.primary.primaryLightDarkMode
                              : AppColors.primary.primaryLight)
                          .withOpacity(0.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ];
  }

  /// Constrói um loader moderno
  Widget _buildModernLoader(BuildContext context, Color primaryColor) {
    return SizedBox(
      width: 50,
      height: 50,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Círculo de fundo
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: primaryColor.withOpacity(0.2),
                width: 3,
              ),
            ),
          ),

          // Indicador de progresso circular
          SizedBox(
            width: 50,
            height: 50,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              backgroundColor: Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }
}
