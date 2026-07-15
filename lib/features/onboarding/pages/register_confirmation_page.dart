import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../onboarding_routes.dart';
import '../services/onboarding_service.dart';

/// Confirmação de email pós-registro.
///
/// Dois modos (paridade com o web):
///   - SEM token → estado "aguardando": instruções do
///     `EmailConfirmationModal.tsx` (verifique a caixa de entrada/spam,
///     clique no link, faça login depois).
///   - COM token (deep link do email) → confirma via
///     `POST /auth/confirm-registration` e mostra carregando/sucesso/erro,
///     como o `EmailConfirmationPage.tsx`.
class RegisterConfirmationPage extends StatefulWidget {
  final String email;
  final int expirationHours;
  final String? token;

  const RegisterConfirmationPage({
    super.key,
    required this.email,
    this.expirationHours = 24,
    this.token,
  });

  @override
  State<RegisterConfirmationPage> createState() =>
      _RegisterConfirmationPageState();
}

enum _ConfirmationStatus { waiting, confirming, confirmed, error }

class _RegisterConfirmationPageState extends State<RegisterConfirmationPage> {
  _ConfirmationStatus _status = _ConfirmationStatus.waiting;
  String _message = '';
  String? _confirmedEmail;

  @override
  void initState() {
    super.initState();
    final token = widget.token;
    if (token != null && token.isNotEmpty) {
      _status = _ConfirmationStatus.confirming;
      // Confirma após o primeiro frame para poder mostrar o loading.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _confirmToken(token);
      });
    }
  }

  Future<void> _confirmToken(String token) async {
    try {
      final response =
          await OnboardingService.instance.confirmRegistration(token);

      if (!mounted) return;

      if (response.success && response.data?.success == true) {
        setState(() {
          _status = _ConfirmationStatus.confirmed;
          _message = response.data!.message.isNotEmpty
              ? response.data!.message
              : 'Conta confirmada com sucesso! Faça login para continuar.';
          _confirmedEmail = response.data!.userEmail ?? widget.email;
        });
        // Paridade com o web: redireciona ao login após alguns segundos.
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && _status == _ConfirmationStatus.confirmed) {
            _goToLogin();
          }
        });
      } else {
        setState(() {
          _status = _ConfirmationStatus.error;
          _message = _friendlyError(response.statusCode, response.message);
        });
      }
    } catch (e) {
      debugPrint('💥 [REGISTER_CONFIRM] Exceção: $e');
      if (mounted) {
        setState(() {
          _status = _ConfirmationStatus.error;
          _message = 'Erro interno do servidor. Tente novamente mais tarde.';
        });
      }
    }
  }

  /// Mapeia os erros como o `EmailConfirmationPage.tsx` do web.
  String _friendlyError(int statusCode, String? message) {
    final msg = message ?? '';
    if (statusCode == 400) {
      if (msg.contains('expirado')) {
        return 'Token de confirmação expirado. Solicite um novo registro.';
      }
      if (msg.contains('inválido') || msg.contains('invalido')) {
        return 'Token de confirmação inválido.';
      }
      return msg.isNotEmpty ? msg : 'Erro ao confirmar registro.';
    }
    if (statusCode == 409) {
      return 'Usuário já foi criado com este email.';
    }
    return msg.isNotEmpty
        ? msg
        : 'Erro interno do servidor. Tente novamente mais tarde.';
  }

  void _goToLogin() {
    Navigator.of(context)
        .pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
  }

  void _goToRegister() {
    Navigator.of(context).pushReplacementNamed(OnboardingRoutes.register);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageBg =
        isDark ? AppColors.background.backgroundDarkMode : Colors.white;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: pageBg,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: pageBg,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: switch (_status) {
                    _ConfirmationStatus.waiting => _buildWaiting(isDark),
                    _ConfirmationStatus.confirming => _buildConfirming(isDark),
                    _ConfirmationStatus.confirmed => _buildConfirmed(isDark),
                    _ConfirmationStatus.error => _buildError(isDark),
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Estado: aguardando confirmação ─────────────────────────────────────

  Widget _buildWaiting(bool isDark) {
    final accent = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;

    return Column(
      key: const ValueKey('waiting'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildIconBadge(
          icon: Icons.mark_email_unread_outlined,
          color: AppColors.status.info,
        ),
        const SizedBox(height: 24),
        _buildTitle('Confirme seu email', isDark),
        const SizedBox(height: 12),
        _buildRichMessage(
          prefix: 'Enviamos um link de confirmação para ',
          highlight: widget.email,
          suffix: '. Clique no link para ativar sua conta.',
          isDark: isDark,
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'O link expira em ${widget.expirationHours}h.',
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? AppColors.text.textLightDarkMode
                  : AppColors.text.textLight,
            ),
          ),
        ),
        const SizedBox(height: 24),
        _buildNextStepsCard(isDark),
        const SizedBox(height: 24),
        _buildPrimaryButton(
          label: 'Ir para o login',
          icon: Icons.login_rounded,
          onTap: _goToLogin,
          isDark: isDark,
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: _goToRegister,
            child: Text(
              'Email errado? Refazer cadastro',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNextStepsCard(bool isDark) {
    final ok = isDark
        ? AppColors.message.successTextDarkMode
        : AppColors.message.successText;
    final cardBg = isDark
        ? AppColors.background.backgroundSecondaryDarkMode
        : AppColors.background.backgroundSecondary;
    final border =
        isDark ? AppColors.border.borderDarkMode : AppColors.border.border;
    final textColor = isDark
        ? AppColors.text.textSecondaryDarkMode
        : AppColors.text.textSecondary;

    const steps = [
      'Verifique sua caixa de entrada',
      'Procure também na pasta de spam/lixo eletrônico',
      'Clique no link de confirmação no email',
      'Faça login após confirmar sua conta',
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline_rounded, size: 16, color: ok),
              const SizedBox(width: 8),
              Text(
                'Próximos passos',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.text.textDarkMode
                      : AppColors.text.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...steps.asMap().entries.map((entry) {
            final isLast = entry.key == steps.length - 1;
            return Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.status.info,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: textColor,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Estado: confirmando (token via deep link) ──────────────────────────

  Widget _buildConfirming(bool isDark) {
    final accent = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;

    return Column(
      key: const ValueKey('confirming'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: accent,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        _buildTitle('Confirmando sua conta...', isDark),
        const SizedBox(height: 12),
        Text(
          'Aguarde enquanto validamos o link de confirmação.',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: isDark
                ? AppColors.text.textSecondaryDarkMode
                : AppColors.text.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  // ── Estado: confirmado ─────────────────────────────────────────────────

  Widget _buildConfirmed(bool isDark) {
    final ok = isDark
        ? AppColors.message.successTextDarkMode
        : AppColors.message.successText;

    return Column(
      key: const ValueKey('confirmed'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildIconBadge(icon: Icons.check_circle_rounded, color: ok),
        const SizedBox(height: 24),
        _buildTitle('Conta confirmada!', isDark),
        const SizedBox(height: 12),
        _buildRichMessage(
          prefix: _message.isNotEmpty
              ? '$_message '
              : 'Sua conta foi ativada com sucesso. ',
          highlight: _confirmedEmail ?? '',
          suffix: '',
          isDark: isDark,
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Você será redirecionado para o login em alguns segundos...',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              color: isDark
                  ? AppColors.text.textLightDarkMode
                  : AppColors.text.textLight,
            ),
          ),
        ),
        const SizedBox(height: 24),
        _buildPrimaryButton(
          label: 'Fazer login agora',
          icon: Icons.login_rounded,
          onTap: _goToLogin,
          isDark: isDark,
        ),
      ],
    );
  }

  // ── Estado: erro ───────────────────────────────────────────────────────

  Widget _buildError(bool isDark) {
    final err =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

    return Column(
      key: const ValueKey('error'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildIconBadge(icon: Icons.cancel_rounded, color: err),
        const SizedBox(height: 24),
        _buildTitle('Erro na confirmação', isDark),
        const SizedBox(height: 12),
        Text(
          _message,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: isDark
                ? AppColors.text.textSecondaryDarkMode
                : AppColors.text.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        _buildPrimaryButton(
          label: 'Ir para o login',
          icon: Icons.login_rounded,
          onTap: _goToLogin,
          isDark: isDark,
        ),
        const SizedBox(height: 10),
        _buildOutlineButton(
          label: 'Novo registro',
          icon: Icons.person_add_alt_1_outlined,
          onTap: _goToRegister,
          isDark: isDark,
        ),
      ],
    );
  }

  // ── Blocos compartilhados ──────────────────────────────────────────────

  Widget _buildIconBadge({required IconData icon, required Color color}) {
    return Center(
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 38, color: color),
      ),
    );
  }

  Widget _buildTitle(String text, bool isDark) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: GoogleFonts.poppins(
        fontSize: 23,
        fontWeight: FontWeight.w700,
        color: isDark ? AppColors.text.textDarkMode : AppColors.text.text,
        height: 1.2,
      ),
    );
  }

  Widget _buildRichMessage({
    required String prefix,
    required String highlight,
    required String suffix,
    required bool isDark,
  }) {
    final base = GoogleFonts.poppins(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: isDark
          ? AppColors.text.textSecondaryDarkMode
          : AppColors.text.textSecondary,
      height: 1.5,
    );

    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        text: prefix,
        style: base,
        children: [
          if (highlight.isNotEmpty)
            TextSpan(
              text: highlight,
              style: base.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.status.info,
              ),
            ),
          if (suffix.isNotEmpty) TextSpan(text: suffix),
        ],
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final base = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
    final dark = isDark
        ? AppColors.primary.primaryDarkDarkMode
        : AppColors.primary.primaryDark;

    return Container(
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, dark],
        ),
        boxShadow: [
          BoxShadow(
            color: base.withValues(alpha: isDark ? 0.45 : 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          splashColor: Colors.white.withValues(alpha: 0.18),
          onTap: onTap,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: Colors.white),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOutlineButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final border =
        isDark ? AppColors.border.borderDarkMode : AppColors.border.border;
    final fg = isDark ? AppColors.text.textDarkMode : AppColors.text.text;

    return SizedBox(
      height: 50,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: fg),
        label: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: border, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
