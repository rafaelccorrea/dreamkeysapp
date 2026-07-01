import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/brand_wordmark_logo.dart'
    show
        BrandWordmarkLoadingDimensions,
        BrandWordmarkLogo,
        BrandWordmarkVariant;
import '../../../../shared/services/auth_service.dart';
import '../../../../shared/services/api_service.dart';
import '../../../../shared/services/token_refresh_service.dart';
import '../../../../shared/services/company_service.dart';
import '../../../../shared/services/module_access_service.dart';
import '../../../../shared/services/biometric_service.dart';
import '../../../../shared/services/secure_storage_service.dart';
import '../../../../core/push/app_push_service.dart';
import '../../chat/controllers/chat_unread_controller.dart';
import '../../notifications/controllers/notification_controller.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  // Quando o token ainda é válido E há biometria cadastrada, exigimos a
  // digital ANTES de soltar o usuário em /home. Se cancelar, mantemos o
  // splash e mostramos um botão de "Tentar de novo" — sem nunca expor a
  // home sem autenticação local.
  bool _awaitingBiometric = false;
  bool _biometricFailed = false;
  String _biometricType = 'Biometria';
  bool _biometricInProgress = false;

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

        final companyService = CompanyService.instance;
        await companyService.ensureCompanySelected();
        debugPrint(
          '✅ [SPLASH] Empresa garantida (se houver empresas disponíveis)',
        );

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

        debugPrint(
          '✅ [SPLASH] Bootstrap completo, verificando gate biométrico...',
        );

        // Gate biométrico: se o dispositivo tem biometria cadastrada e o
        // usuário tem credenciais salvas (ou seja: já optou pela
        // biometria neste app), exigimos a digital antes de entrar.
        final biometricRequired = await _isBiometricRequired();
        if (!mounted) return;

        if (biometricRequired) {
          debugPrint('🔐 [SPLASH] Biometria obrigatória — solicitando...');
          await _promptBiometric();
        } else {
          debugPrint('ℹ️ [SPLASH] Biometria não obrigatória — indo pra home');
          if (mounted) {
            Navigator.of(context).pushReplacementNamed(AppRoutes.home);
          }
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

  /// Decide se devemos travar a navegação atrás de biometria. Só
  /// exigimos quando: o dispositivo suporta biometria, há biometria
  /// configurada no SO E o usuário já salvou credenciais no app
  /// (caso contrário forçaríamos um fluxo que ele nunca optou).
  Future<bool> _isBiometricRequired() async {
    try {
      final hasBio = await BiometricService.instance.hasBiometrics();
      if (!hasBio) return false;
      final hasSaved = await SecureStorageService.instance
          .hasSavedCredentials();
      if (!hasSaved) return false;

      _biometricType = await BiometricService.instance
          .getBiometricTypeDescription();
      return true;
    } catch (e) {
      debugPrint('⚠️ [SPLASH] Falha ao avaliar biometria obrigatória: $e');
      return false;
    }
  }

  Future<void> _promptBiometric() async {
    if (_biometricInProgress) {
      debugPrint('⚠️ [SPLASH] Biometria já em progresso — ignorando');
      return;
    }
    _biometricInProgress = true;

    if (mounted) {
      setState(() {
        _awaitingBiometric = true;
        _biometricFailed = false;
      });
    }

    try {
      final ok = await BiometricService.instance.authenticate(
        reason: 'Use $_biometricType para abrir o app',
      );

      if (!mounted) return;

      if (ok) {
        debugPrint('✅ [SPLASH] Biometria OK — indo pra home');
        Navigator.of(context).pushReplacementNamed(AppRoutes.home);
      } else {
        debugPrint('❌ [SPLASH] Biometria falhou/cancelada — aguardando ação');
        setState(() {
          _awaitingBiometric = false;
          _biometricFailed = true;
        });
      }
    } catch (e) {
      debugPrint('💥 [SPLASH] Exceção na biometria: $e');
      if (mounted) {
        setState(() {
          _awaitingBiometric = false;
          _biometricFailed = true;
        });
      }
    } finally {
      _biometricInProgress = false;
    }
  }

  /// Permite ao usuário optar por sair da sessão e voltar pro login
  /// quando, por algum motivo, não conseguir mais autenticar com
  /// biometria (ex.: trocou a digital cadastrada no SO).
  Future<void> _logoutAndGoToLogin() async {
    try {
      await AuthService.instance.logout();
    } catch (e) {
      debugPrint('⚠️ [SPLASH] Falha ao fazer logout: $e');
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(AppRoutes.login);
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
              _buildBottomSlot(context, primaryColor, isDark),
            ],
          ),
        ),
      ),
    );
  }

  /// Slot inferior do splash. Mostra o loader enquanto faz bootstrap;
  /// substitui pelo gate biométrico quando precisa autenticar; mostra
  /// um botão de retry quando a biometria foi cancelada.
  Widget _buildBottomSlot(
    BuildContext context,
    Color primaryColor,
    bool isDark,
  ) {
    if (_awaitingBiometric) {
      return _buildBiometricInProgress(primaryColor, isDark);
    }
    if (_biometricFailed) {
      return _buildBiometricRetry(primaryColor, isDark);
    }
    return _buildModernLoader(context, primaryColor);
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

  Widget _buildBiometricInProgress(Color primaryColor, bool isDark) {
    final isFace = _biometricType.contains('Face');
    final muted = isDark
        ? AppColors.text.textSecondaryDarkMode
        : AppColors.text.textSecondary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: isDark ? 0.22 : 0.12),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(
            isFace ? Icons.face_rounded : Icons.fingerprint_rounded,
            size: 32,
            color: primaryColor,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Aguardando $_biometricType...',
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: muted,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildBiometricRetry(Color primaryColor, bool isDark) {
    final isFace = _biometricType.contains('Face');
    final fg = isDark ? AppColors.text.textDarkMode : AppColors.text.text;
    final muted = isDark
        ? AppColors.text.textSecondaryDarkMode
        : AppColors.text.textSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Autenticação necessária',
            style: GoogleFonts.poppins(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: fg,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Use $_biometricType para abrir o app.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: FontWeight.w400,
              color: muted,
              letterSpacing: 0.15,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _biometricInProgress ? null : _promptBiometric,
              icon: Icon(
                isFace ? Icons.face_rounded : Icons.fingerprint_rounded,
                size: 20,
              ),
              label: Text(
                'Tentar com $_biometricType',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _biometricInProgress ? null : _logoutAndGoToLogin,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Usar e-mail e senha',
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: primaryColor,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
