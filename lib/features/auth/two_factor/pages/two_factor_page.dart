import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../shared/services/auth_service.dart';
import '../../../../shared/services/login_flow_service.dart';
import '../../../../shared/services/biometric_service.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/layout/handheld_layout.dart';
import '../../../../core/notifications/app_toast.dart';
import '../../../../core/push/app_push_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/widgets/brand_wordmark_logo.dart';
import '../../../../shared/widgets/image_curve_clipper.dart';
import '../../../../shared/widgets/loading_overlay.dart';
import '../../login/widgets/biometric_enrollment_dialog.dart';
import '../widgets/two_factor_code_input.dart';

/// Código do autenticador no login (empresa exige 2FA e a conta já tem).
///
/// Continuação visual do login: mesmo hero com foto e curva, folha branca por
/// cima, e o CTA com a cara do "Entrar". Com o teclado aberto o hero encolhe
/// para as caixas e o botão ficarem à vista em tela baixa/landscape.
class TwoFactorPage extends StatefulWidget {
  final String email;
  final String password;
  final String tempToken;

  const TwoFactorPage({
    super.key,
    required this.email,
    required this.password,
    required this.tempToken,
  });

  @override
  State<TwoFactorPage> createState() => _TwoFactorPageState();
}

class _TwoFactorPageState extends State<TwoFactorPage> {
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _codeFocus = FocusNode();
  bool _isLoading = false;
  bool _codeError = false;

  @override
  void initState() {
    super.initState();
    // Erro some assim que a pessoa volta a digitar.
    _codeController.addListener(() {
      if (_codeError && _codeController.text.isNotEmpty && mounted) {
        setState(() => _codeError = false);
      }
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  Future<void> _pasteCode() async {
    final code = await lerCodigoDaAreaDeTransferencia();
    if (!mounted) return;
    if (code == null) {
      AppToast.warning(
        context,
        'Nenhum código de 6 dígitos na área de transferência',
      );
      return;
    }
    _codeController.value = TextEditingValue(
      text: code,
      selection: TextSelection.collapsed(offset: code.length),
    );
  }

  Future<void> _verifyCode() async {
    if (_isLoading) return;

    final code = _codeController.text;
    if (code.length != 6) {
      AppToast.warning(context, 'Preencha todos os dígitos');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    var refocus = false;

    try {
      final authService = AuthService.instance;
      final response = await authService.verify2FA(
        tempToken: widget.tempToken,
        code: code,
      );

      if (response.success && response.data != null) {
        // Login bem-sucedido - continuar com fluxo de inicialização
        await _handleAuthSuccess(response.data!, code);
      } else {
        if (mounted) {
          AppToast.error(
            context,
            response.message ?? 'Código inválido. Tente novamente.',
          );
          _codeController.clear();
          setState(() => _codeError = true);
          refocus = true;
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Erro ao verificar código: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        // O campo fica desabilitado durante a verificação: o foco volta
        // depois do quadro em que ele é reabilitado.
        if (refocus) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _codeFocus.requestFocus();
          });
        }
      }
    }
  }

  Future<void> _handleAuthSuccess(LoginResponse loginResponse, String code) async {
    try {
      // Continuar com o fluxo completo de inicialização
      final loginFlowService = LoginFlowService.instance;
      final result = await loginFlowService.executeAfter2FA(
        loginResponse: loginResponse,
        rememberMe: false,
        context: context,
      );

      if (result.success && result.route != null) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
        if (!mounted) return;

        // Permissões nativas (notificação + token FCM) PRIMEIRO — para
        // não sobrepor o popup nativo de biometria que dispararemos a
        // seguir caso o usuário aceite a oferta de enrollment.
        try {
          // Mesmo teto do login: o popup nativo é rápido, a espera do
          // token APNs não — e ela não precisa segurar a tela.
          await AppPushService.instance
              .syncWithBackendIfAuthenticated()
              .timeout(const Duration(seconds: 5));
        } catch (e) {
          debugPrint('⚠️ [2FA] Falha ao sincronizar permissões push: $e');
        }
        if (!mounted) return;

        final bio = BiometricService.instance;
        final hasBio = await bio.hasBiometrics();
        final biometricLabel = await bio.getBiometricTypeDescription();
        if (!mounted) return;
        await showBiometricEnrollmentOffer(
          context,
          email: widget.email,
          password: widget.password,
          biometricHardwareAvailable: hasBio,
          biometricTypeLabel: biometricLabel,
        );

        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil(
            result.route!,
            (route) => false,
          );
        }
      } else {
        if (mounted) {
          AppToast.error(context, result.message);
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Erro ao processar login: ${e.toString()}');
      }
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final screenWidth = mediaQuery.size.width;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final keyboardOpen = mediaQuery.viewInsets.bottom > 0;

    // Hero um pouco menor que o do login (aqui a folha tem mais conteúdo);
    // com teclado aberto vira só a faixa da marca.
    final fullHero =
        screenHeight * HandheldLayout.loginHeroHeightFraction(screenHeight) * 0.82;
    // Piso: a faixa da marca (selo de vidro) inteira acima da folha, que
    // sobe 28 por cima do hero.
    final compactHero = mediaQuery.padding.top + 78;
    final heroHeight = keyboardOpen
        ? compactHero
        : fullHero.clamp(compactHero, 280.0);
    final sheetTop = heroHeight - 28;
    final pageBg = ThemeHelpers.backgroundColor(context);
    final formHorizontal =
        HandheldLayout.loginFormHorizontalPadding(screenWidth).clamp(16.0, 32.0);

    return LoadingOverlay(
      isLoading: _isLoading,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: pageBg,
          systemNavigationBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: pageBg,
          resizeToAvoidBottomInset: true,
          body: Stack(
            fit: StackFit.expand,
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: _TwoFactorHero(
                  height: heroHeight,
                  statusBarTop: mediaQuery.padding.top,
                  isDark: isDark,
                  compact: keyboardOpen,
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                left: 0,
                right: 0,
                top: sheetTop,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: pageBg,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      formHorizontal,
                      22,
                      formHorizontal,
                      24 + mediaQuery.padding.bottom,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        // Tablet: a folha não estica em 1000dp.
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: _buildSheetContent(context, isDark),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSheetContent(BuildContext context, bool isDark) {
    final theme = Theme.of(context);
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final text = ThemeHelpers.textColor(context);
    final textSec = ThemeHelpers.textSecondaryColor(context);
    final email = widget.email.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mesmo traço de acento do login.
        Row(
          children: [
            Container(
              width: 28,
              height: 3,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 6,
              height: 3,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Confirme que é você',
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: text,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            style: theme.textTheme.bodyMedium?.copyWith(
              color: textSec,
              height: 1.4,
            ),
            children: [
              const TextSpan(
                text: 'Abra o seu aplicativo autenticador e digite o código '
                    'de 6 dígitos',
              ),
              if (email.isNotEmpty) ...[
                const TextSpan(text: ' da conta '),
                TextSpan(
                  text: email,
                  style: TextStyle(
                    color: text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const TextSpan(text: '.'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        TwoFactorCodeInput(
          controller: _codeController,
          focusNode: _codeFocus,
          autofocus: true,
          enabled: !_isLoading,
          hasError: _codeError,
          onCompleted: (_) => _verifyCode(),
          onSubmitted: (_) => _verifyCode(),
        ),
        const SizedBox(height: 12),
        // Dica + colar: o código muda a cada 30 s e quase sempre vem copiado.
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.schedule_rounded, size: 16, color: textSec),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'O código muda a cada 30 segundos.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: textSec),
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _isLoading ? null : _pasteCode,
              style: TextButton.styleFrom(
                foregroundColor: accent,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.content_paste_rounded, size: 16),
              label: const Text(
                'Colar',
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildVerifyButton(isDark),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: textSec),
            child: const Text(
              'Voltar para o login',
              maxLines: 1,
              softWrap: false,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.shield_outlined,
                size: 13,
                color: textSec.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Verificação em duas etapas ativa nesta conta',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: textSec.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// CTA com a mesma cara do "Entrar" do login (é o mesmo passo do fluxo);
  /// sombra só crisp, como pede o modo claro.
  Widget _buildVerifyButton(bool isDark) {
    final base =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final dark = isDark
        ? AppColors.primary.primaryDarkDarkMode
        : AppColors.primary.primaryDark;

    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _isLoading
              ? [base.withValues(alpha: 0.7), dark.withValues(alpha: 0.7)]
              : [base, dark],
        ),
        boxShadow: [
          BoxShadow(
            color: dark.withValues(alpha: 0.18),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          splashColor: Colors.white.withValues(alpha: 0.18),
          highlightColor: Colors.white.withValues(alpha: 0.08),
          onTap: _isLoading ? null : _verifyCode,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Verificar e entrar',
                      maxLines: 1,
                      softWrap: false,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hero com a foto do login, curva e selo — encolhe para a faixa da marca
/// quando o teclado abre.
class _TwoFactorHero extends StatelessWidget {
  final double height;
  final double statusBarTop;
  final bool isDark;
  final bool compact;

  const _TwoFactorHero({
    required this.height,
    required this.statusBarTop,
    required this.isDark,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final glass = (isDark ? Colors.black : Colors.white).withValues(alpha: 0.55);
    final glassBorder = (isDark ? Colors.white : Colors.black).withValues(
      alpha: isDark ? 0.10 : 0.06,
    );
    final chipFg = (isDark ? Colors.white : Colors.black87).withValues(
      alpha: isDark ? 0.92 : 0.85,
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      height: height,
      width: double.infinity,
      child: ClipPath(
        clipper: ImageCurveClipper(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: const AssetImage(AppAssets.backgroundLogin),
                  fit: BoxFit.cover,
                  colorFilter: isDark
                      ? ColorFilter.mode(
                          Colors.black.withValues(alpha: 0.55),
                          BlendMode.darken,
                        )
                      : null,
                ),
              ),
            ),
            // Mesmas camadas tonais do hero do login.
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                          accent.withValues(alpha: 0.18),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.35),
                        ]
                      : [
                          accent.withValues(alpha: 0.10),
                          Colors.transparent,
                          Colors.white.withValues(alpha: 0.55),
                        ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
            Positioned(
              top: statusBarTop + (HandheldLayout.isIosPhone ? 8 : 14),
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(8, 7, 10, 7),
                    decoration: BoxDecoration(
                      color: glass,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: glassBorder, width: 0.8),
                    ),
                    child: BrandWordmarkLogo(
                      height: 18,
                      maxWidth: 88,
                      alignment: Alignment.centerLeft,
                      variant: BrandWordmarkVariant.loading,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: glass,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: glassBorder, width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_outline_rounded, size: 15, color: chipFg),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Verificação em 2 etapas',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                                color: chipFg,
                                letterSpacing: 0.15,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!compact && height >= 170)
              // Selo grande do passo — some com o teclado aberto e em hero
              // baixo (landscape), onde encostaria na faixa da marca.
              Positioned(
                left: 0,
                right: 0,
                bottom: 44,
                child: Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: glass,
                      shape: BoxShape.circle,
                      border: Border.all(color: glassBorder, width: 0.8),
                    ),
                    child: Icon(
                      Icons.verified_user_outlined,
                      size: 30,
                      color: accent,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
