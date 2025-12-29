import 'package:flutter/material.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/services/auth_service.dart';
import '../../../../shared/widgets/image_curve_clipper.dart';

class ForgotPasswordConfirmationPage extends StatefulWidget {
  final String? email;

  const ForgotPasswordConfirmationPage({
    super.key,
    this.email,
  });

  @override
  State<ForgotPasswordConfirmationPage> createState() =>
      _ForgotPasswordConfirmationPageState();
}

class _ForgotPasswordConfirmationPageState
    extends State<ForgotPasswordConfirmationPage> {
  bool _isResending = false;

  Future<void> _handleResend() async {
    if (widget.email == null || widget.email!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Email não disponível para reenvio'),
          backgroundColor: AppColors.status.error,
        ),
      );
      return;
    }

    setState(() {
      _isResending = true;
    });

    try {
      final authService = AuthService.instance;
      final response = await authService.forgotPassword(widget.email!);

      if (response.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Email reenviado com sucesso!',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.status.success,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response.message ?? 'Erro ao reenviar email',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            backgroundColor: AppColors.status.error,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Erro ao reenviar email. Tente novamente.',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          backgroundColor: AppColors.status.error,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // PARTE SUPERIOR com background.jpg
              Stack(
                children: [
                  Container(
                    height: screenHeight * 0.35,
                    width: double.infinity,
                    color: Colors.white,
                  ),
                  SizedBox(
                    height: screenHeight * 0.35,
                    width: double.infinity,
                    child: ClipPath(
                      clipper: ImageCurveClipper(),
                      child: Container(
                        decoration: const BoxDecoration(
                          image: DecorationImage(
                            image: AssetImage('assets/images/background.jpg'),
                            fit: BoxFit.cover,
                          ),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withOpacity(0.2),
                                Colors.white.withOpacity(0.7),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // PARTE INFERIOR com conteúdo
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(color: Colors.white),
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.08,
                  vertical: screenHeight * 0.04,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Ícone de email
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: AppColors.primary.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.email_outlined,
                        size: 50,
                        color: AppColors.primary.primary,
                      ),
                    ),

                    SizedBox(height: screenHeight * 0.04),

                    // Título
                    Text(
                      'Email Enviado!',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary.primary,
                        letterSpacing: -0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    SizedBox(height: screenHeight * 0.02),

                    // Mensagem
                    Text(
                      'Enviamos um link de recuperação para',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: AppColors.text.textSecondary,
                        letterSpacing: 0.3,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    if (widget.email != null) ...[
                      SizedBox(height: screenHeight * 0.01),
                      Text(
                        widget.email!,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: AppColors.primary.primary,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],

                    SizedBox(height: screenHeight * 0.03),

                    // Instruções
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primary.primary.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.primary.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: AppColors.primary.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Verifique sua caixa de entrada e siga as instruções para redefinir sua senha.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: AppColors.text.textSecondary,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.warning_amber_outlined,
                                color: AppColors.status.warning,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Não esqueça de verificar a pasta de spam ou lixo eletrônico.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: AppColors.status.warning,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: screenHeight * 0.04),

                    // Botão Reenviar Email
                    if (widget.email != null)
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: OutlinedButton(
                          onPressed: _isResending ? null : _handleResend,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: AppColors.primary.primary,
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: _isResending
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(Colors.blue),
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.refresh,
                                      color: AppColors.primary.primary,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Reenviar Email',
                                      style: TextStyle(
                                        color: AppColors.primary.primary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),

                    SizedBox(height: screenHeight * 0.02),

                    // Link para voltar ao login
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pushNamedAndRemoveUntil(
                          AppRoutes.login,
                          (route) => false,
                        );
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 0,
                          vertical: 12,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.arrow_back,
                            color: AppColors.primary.primary,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Voltar ao Login',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.primary.primary,
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
        ),
      ),
    );
  }
}











