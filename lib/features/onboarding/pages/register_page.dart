import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/notifications/app_toast.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/utils/input_formatters.dart';
import '../../../shared/utils/validators.dart';
import '../../../shared/widgets/brand_wordmark_logo.dart';
import '../../../shared/widgets/image_curve_clipper.dart';
import '../../../shared/widgets/loading_overlay.dart';
import '../models/onboarding_models.dart';
import '../onboarding_routes.dart';
import '../services/onboarding_service.dart';
import '../utils/document_input.dart';
import '../widgets/onboarding_text_field.dart';
import '../widgets/password_checklist.dart';

/// Registro de conta — paridade com `RegisterForm.tsx` do `imobx-front`.
///
/// Cria a conta via `POST /auth/register-with-confirmation` e navega para a
/// tela de confirmação de email. Tela de auth: a rota é embrulhada em tema
/// claro pela fiação central (`_authLightTheme`), como o login.
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _documentController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String _passwordValue = '';

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _documentController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      AppToast.warning(context, 'Verifique os campos destacados');
      return;
    }

    setState(() => _isLoading = true);

    final email = _emailController.text.trim().toLowerCase();
    final request = RegisterAccountRequest(
      name: _nameController.text,
      email: email,
      password: _passwordController.text,
      document: _documentController.text,
      phone: _phoneController.text,
    );

    try {
      final response =
          await OnboardingService.instance.registerAccount(request);

      if (!mounted) return;

      if (response.success) {
        final info = response.data;
        Navigator.of(context).pushReplacementNamed(
          OnboardingRoutes.registerConfirm,
          arguments: {
            'email': info?.email.isNotEmpty == true ? info!.email : email,
            'expirationHours': info?.expirationHours ?? 24,
          },
        );
      } else {
        AppToast.error(
          context,
          response.message ?? 'Erro ao criar conta. Tente novamente.',
        );
      }
    } catch (e) {
      debugPrint('💥 [REGISTER] Exceção: $e');
      if (mounted) {
        AppToast.error(
          context,
          'Erro ao conectar com o servidor. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _goToLogin() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacementNamed(AppRoutes.login);
    }
  }

  // ── Validações (espelham o registerSchema do web) ──────────────────────

  String? _validateName(String? value) {
    return Validators.required(value, message: 'Nome é obrigatório');
  }

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Telefone é obrigatório';
    }
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 10 || digits.length > 13) {
      return 'Informe um telefone válido com DDD';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Senha é obrigatória';
    }
    if (!isRegisterPasswordValid(value)) {
      return 'A senha não atende a todos os requisitos';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    return Validators.confirmPassword(
      value,
      _passwordController.text,
      message: value == null || value.isEmpty
          ? 'Confirmação de senha é obrigatória'
          : 'Senhas devem ser iguais',
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final screenWidth = mediaQuery.size.width;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageBg =
        isDark ? AppColors.background.backgroundDarkMode : Colors.white;

    final heroHeight = screenHeight * 0.24;
    final formHorizontal = screenWidth * 0.07;
    final systemBottomInset = mediaQuery.padding.bottom;

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
          body: SafeArea(
            top: false,
            bottom: false,
            child: SingleChildScrollView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                children: [
                  _buildHeroHeader(
                    isDark: isDark,
                    height: heroHeight,
                    statusBarTop: mediaQuery.padding.top,
                  ),
                  Transform.translate(
                    offset: const Offset(0, -24),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: pageBg,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                      ),
                      padding: EdgeInsets.fromLTRB(
                        formHorizontal,
                        18,
                        formHorizontal,
                        24 + systemBottomInset,
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildAccentLine(isDark),
                            const SizedBox(height: 12),
                            _buildTitle(isDark),
                            const SizedBox(height: 6),
                            Text(
                              'Crie sua conta em minutos e comece a vender '
                              'mais com o CRM imobiliário.',
                              style: GoogleFonts.poppins(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w400,
                                color: isDark
                                    ? AppColors.text.textSecondaryDarkMode
                                    : AppColors.text.textSecondary,
                                letterSpacing: 0.2,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 22),
                            OnboardingTextField(
                              controller: _nameController,
                              label: 'Nome completo',
                              prefixIcon: Icons.person_outline_rounded,
                              keyboardType: TextInputType.name,
                              // O web força minúsculas no nome.
                              inputFormatters: [LowercaseInputFormatter()],
                              validator: _validateName,
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 14),
                            OnboardingTextField(
                              controller: _emailController,
                              label: 'E-mail',
                              prefixIcon: Icons.alternate_email_rounded,
                              keyboardType: TextInputType.emailAddress,
                              validator: Validators.requiredEmail,
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 14),
                            OnboardingTextField(
                              controller: _documentController,
                              label: 'CPF / CNPJ',
                              prefixIcon: Icons.badge_outlined,
                              keyboardType: TextInputType.text,
                              maxLength: 18,
                              inputFormatters: [DocumentInputFormatter()],
                              validator:
                                  OnboardingDocumentUtils.validateDocument,
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 14),
                            OnboardingTextField(
                              controller: _phoneController,
                              label: 'Telefone',
                              prefixIcon: Icons.phone_iphone_rounded,
                              keyboardType: TextInputType.phone,
                              maxLength: 15,
                              inputFormatters: [PhoneInputFormatter()],
                              validator: _validatePhone,
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 14),
                            OnboardingTextField(
                              controller: _passwordController,
                              label: 'Senha',
                              prefixIcon: Icons.lock_outline_rounded,
                              obscureText: _obscurePassword,
                              onChanged: (value) {
                                setState(() => _passwordValue = value);
                              },
                              validator: _validatePassword,
                              textInputAction: TextInputAction.next,
                              suffixIcon: _buildVisibilityToggle(
                                isDark: isDark,
                                obscured: _obscurePassword,
                                onTap: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                              ),
                            ),
                            PasswordChecklist(value: _passwordValue),
                            const SizedBox(height: 14),
                            OnboardingTextField(
                              controller: _confirmController,
                              label: 'Confirmar senha',
                              prefixIcon: Icons.lock_outline_rounded,
                              obscureText: _obscureConfirm,
                              validator: _validateConfirmPassword,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _handleRegister(),
                              suffixIcon: _buildVisibilityToggle(
                                isDark: isDark,
                                obscured: _obscureConfirm,
                                onTap: () => setState(
                                  () => _obscureConfirm = !_obscureConfirm,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            _buildSubmitButton(isDark),
                            const SizedBox(height: 18),
                            _buildOrDivider(isDark),
                            const SizedBox(height: 10),
                            _buildLoginLink(isDark),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Cabeçalho com imagem em curva — mesma linguagem do hero do login.
  Widget _buildHeroHeader({
    required bool isDark,
    required double height,
    required double statusBarTop,
  }) {
    final accent = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;

    return SizedBox(
      height: height + 24,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: height,
            width: double.infinity,
            color: isDark
                ? AppColors.background.backgroundSecondaryDarkMode
                : Colors.white,
          ),
          SizedBox(
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
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(
                            alpha: isDark ? 0.04 : 0.18,
                          ),
                          Colors.white.withValues(
                            alpha: isDark ? 0.32 : 0.78,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: statusBarTop + 12,
            left: 12,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildGlassChip(
                  isDark: isDark,
                  child: BrandWordmarkLogo(
                    height: 18,
                    maxWidth: 88,
                    alignment: Alignment.centerLeft,
                    variant: BrandWordmarkVariant.loading,
                  ),
                ),
                _buildGlassChip(
                  isDark: isDark,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 15,
                        color: (isDark ? Colors.white : Colors.black87)
                            .withValues(alpha: isDark ? 0.92 : 0.85),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Conexão segura',
                        style: GoogleFonts.poppins(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: (isDark ? Colors.white : Colors.black87)
                              .withValues(alpha: isDark ? 0.92 : 0.85),
                          letterSpacing: 0.15,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassChip({required bool isDark, required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withValues(
            alpha: isDark ? 0.10 : 0.06,
          ),
          width: 0.8,
        ),
      ),
      child: child,
    );
  }

  Widget _buildAccentLine(bool isDark) {
    final accent = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;

    return Row(
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
    );
  }

  Widget _buildTitle(bool isDark) {
    final theme = Theme.of(context);
    final accent = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Criar',
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w400,
            color: isDark ? AppColors.text.textDarkMode : AppColors.text.text,
            letterSpacing: 0.5,
            height: 1.0,
          ),
        ),
        Text(
          'sua conta',
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: accent,
            letterSpacing: -0.5,
            height: 1.05,
          ),
        ),
      ],
    );
  }

  Widget _buildVisibilityToggle({
    required bool isDark,
    required bool obscured,
    required VoidCallback onTap,
  }) {
    final muted = isDark
        ? AppColors.text.textSecondaryDarkMode
        : AppColors.text.textSecondary;

    return IconButton(
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        foregroundColor: muted,
        minimumSize: const Size(40, 40),
        padding: EdgeInsets.zero,
      ),
      icon: Icon(
        obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: 20,
      ),
      tooltip: obscured ? 'Mostrar senha' : 'Ocultar senha',
      onPressed: onTap,
    );
  }

  Widget _buildSubmitButton(bool isDark) {
    final base = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
    final dark = isDark
        ? AppColors.primary.primaryDarkDarkMode
        : AppColors.primary.primaryDark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
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
        boxShadow: _isLoading
            ? []
            : [
                BoxShadow(
                  color: base.withValues(alpha: isDark ? 0.45 : 0.32),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: dark.withValues(alpha: isDark ? 0.25 : 0.18),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
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
          onTap: _isLoading
              ? null
              : () {
                  FocusScope.of(context).unfocus();
                  _handleRegister();
                },
          child: Center(
            child: _isLoading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Criar conta',
                        style: GoogleFonts.poppins(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildOrDivider(bool isDark) {
    final divider = isDark
        ? AppColors.border.borderDarkMode
        : AppColors.border.border;
    final mutedText = isDark
        ? AppColors.text.textLightDarkMode
        : AppColors.text.textLight;

    return Row(
      children: [
        Expanded(child: Container(height: 1, color: divider)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'ou',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: mutedText,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Expanded(child: Container(height: 1, color: divider)),
      ],
    );
  }

  Widget _buildLoginLink(bool isDark) {
    final accent = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
    final muted = isDark
        ? AppColors.text.textSecondaryDarkMode
        : AppColors.text.textSecondary;

    return Center(
      child: TextButton(
        onPressed: _isLoading ? null : _goToLogin,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        child: RichText(
          text: TextSpan(
            text: 'Já tem uma conta? ',
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: muted,
            ),
            children: [
              TextSpan(
                text: 'Faça login',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
