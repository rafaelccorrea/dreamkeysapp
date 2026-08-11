import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../core/session/session_bootstrap.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/brand_wordmark_logo.dart'
    show
        BrandWordmarkLoadingDimensions,
        BrandWordmarkLogo,
        BrandWordmarkVariant;
import '../../../../shared/services/auth_service.dart';
import '../../../../shared/services/api_service.dart';
import '../../../../shared/services/token_refresh_service.dart';
import '../../../../shared/services/module_access_service.dart';
import '../../../../core/push/app_push_service.dart';
import '../../chat/controllers/chat_unread_controller.dart';
import '../../notifications/controllers/notification_controller.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  // Aqui NÃO existe gate biométrico. O splash antes exigia Face ID/digital
  // sozinho sempre que havia token válido + credenciais salvas — era o
  // "do nada ele lê meu FaceID" relatado. Pior: quando a biometria
  // concluía, o splash empurrava /home de novo e o estado se "consertava"
  // sozinho, mascarando a corrida do companyId. Sessão válida entra
  // direto; sessão ausente cai no login, onde a biometria é um BOTÃO.
  @override
  void initState() {
    super.initState();
    _checkAuthenticationAndNavigate();
  }

  /// Verifica autenticação e navega para a tela apropriada
  Future<void> _checkAuthenticationAndNavigate() async {
    try {
      await Future.delayed(const Duration(milliseconds: 1500));

      if (!mounted) return;

      await ApiService.instance.initialize();
      await AuthService.instance.loadSavedToken();

      final isAuthenticated = await AuthService.instance.isAuthenticated();

      if (!mounted) return;

      if (isAuthenticated) {
        TokenRefreshService.instance.startPeriodicRefresh();
        debugPrint('🔄 [SPLASH] Serviço de refresh periódico iniciado');

        // SESSÃO PRONTA antes de qualquer coisa: é aqui que a empresa é
        // resolvida e gravada. Todo o resto do bootstrap (módulos,
        // permissões, chat, notificações) bate em rotas protegidas que
        // exigem `X-Company-ID` — rodar antes disso era pedir corrida.
        final sessionReady = await SessionBootstrap.instance.ensureReady(
          timeout: const Duration(seconds: 10),
        );
        debugPrint('✅ [SPLASH] Sessão pronta: $sessionReady');

        debugPrint('🔄 [SPLASH] Inicializando ModuleAccessService...');
        await ModuleAccessService.instance.initialize();
        debugPrint('✅ [SPLASH] ModuleAccessService inicializado');

        // Permissões AUTORITATIVAS (API) antes de abrir a home. O `initialize`
        // acima é cache-first e pode vir defasado (ex.: permissão de aprovar
        // imóveis concedida há pouco). Sem isso, a bottom nav abre em "Agenda"
        // e só troca pra "Aprovações" quando o drawer refresca em background —
        // exatamente o "flip" que o usuário via. Refrescando aqui, o primeiro
        // frame da nav já sai correto. Tolerante a falha/offline (não lança).
        debugPrint('🔄 [SPLASH] Refrescando permissões (autoritativo)...');
        // Timeout curto: se a rede estiver lenta/offline, não trava o splash —
        // cai no que o `initialize` já carregou (cache) e o drawer refresca
        // depois. `onTimeout` retorna void, então nunca joga o usuário no login.
        await ModuleAccessService.instance.refreshPermissions().timeout(
          const Duration(seconds: 6),
          onTimeout: () {},
        );
        debugPrint('✅ [SPLASH] Permissões autoritativas carregadas');

        debugPrint('🔄 [SPLASH] Inicializando ChatUnreadController...');
        await ChatUnreadController.instance.initialize();
        debugPrint('✅ [SPLASH] ChatUnreadController inicializado');

        debugPrint('🔄 [SPLASH] Inicializando NotificationController...');
        await NotificationController.instance.initialize().catchError((e) {
          debugPrint('⚠️ [SPLASH] Erro ao iniciar NotificationController: $e');
        });
        await AppPushService.instance
            .syncWithBackendIfAuthenticated()
            .catchError((e) => debugPrint('⚠️ [SPLASH] Push/sync: $e'));

        debugPrint('✅ [SPLASH] Bootstrap completo — indo pra home');
        if (mounted) {
          Navigator.of(context).pushReplacementNamed(AppRoutes.home);
        }
      } else {
        debugPrint(
          'ℹ️ [SPLASH] Usuário não autenticado, redirecionando para login...',
        );
        Navigator.of(context).pushReplacementNamed(AppRoutes.login);
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [SPLASH] Erro ao verificar autenticação: $e');
      debugPrint('📚 [SPLASH] StackTrace: $stackTrace');

      if (mounted) {
        Navigator.of(context).pushReplacementNamed(AppRoutes.login);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFF5F6F8),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildStaticLogo(context),
              const SizedBox(height: 28),
              Text(
                'Sistema Imobiliário',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? AppColors.text.textSecondaryDarkMode.withValues(
                          alpha: 0.75,
                        )
                      : AppColors.text.textSecondary.withValues(alpha: 0.75),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 64),
              _buildModernLoader(context, primaryColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStaticLogo(BuildContext context) {
    final maxW = BrandWordmarkLoadingDimensions.splashMaxWidth(context);
    final stackH = BrandWordmarkLoadingDimensions.splashStackHeight(context);
    final logoH = BrandWordmarkLoadingDimensions.splashLogoHeight(context);

    return SizedBox(
      width: maxW,
      height: stackH,
      child: Center(
        child: BrandWordmarkLogo(
          variant: BrandWordmarkVariant.loading,
          height: logoH,
          maxWidth: maxW,
          alignment: Alignment.center,
        ),
      ),
    );
  }

  Widget _buildModernLoader(BuildContext context, Color primaryColor) {
    return SizedBox(
      width: 50,
      height: 50,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: primaryColor.withValues(alpha: 0.2),
                width: 3,
              ),
            ),
          ),
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
