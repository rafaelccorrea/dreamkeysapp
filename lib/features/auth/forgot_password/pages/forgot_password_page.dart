import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/services/auth_service.dart';
import '../../../../shared/widgets/image_curve_clipper.dart';
import '../../../../shared/widgets/loading_overlay.dart';
import '../../../../shared/utils/validators.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _emailFocusNode = FocusNode();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _emailFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    debugPrint('📧 [FORGOT_PASSWORD] Iniciando solicitação de reset...');

    FocusScope.of(context).unfocus();

    final email = _emailController.text.trim().toLowerCase();
    debugPrint('📧 [FORGOT_PASSWORD] Email: $email');

    if (!_formKey.currentState!.validate()) {
      debugPrint('❌ [FORGOT_PASSWORD] Validação do formulário falhou');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final authService = AuthService.instance;
      final response = await authService.forgotPassword(email);

      debugPrint(
        '📥 [FORGOT_PASSWORD] Response - Status: ${response.statusCode}, Success: ${response.success}',
      );

      if (response.success) {
        debugPrint('✅ [FORGOT_PASSWORD] Email de recuperação enviado com sucesso');

        // Navegar para página de confirmação após 2 segundos
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.of(context).pushReplacementNamed(
            AppRoutes.forgotPasswordConfirmation,
            arguments: email,
          );
        }
      } else {
        debugPrint('❌ [FORGOT_PASSWORD] Falha ao enviar email');
        debugPrint('📋 [FORGOT_PASSWORD] Mensagem: ${response.message}');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      response.message ??
                          'Erro ao enviar email de recuperação. Tente novamente.',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                ],
              ),
              backgroundColor: AppColors.status.error,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      debugPrint('💥 [FORGOT_PASSWORD] Exceção capturada');
      debugPrint('❌ [FORGOT_PASSWORD] Erro: $e');
      debugPrint('📚 [FORGOT_PASSWORD] StackTrace: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Erro ao conectar com o servidor. Tente novamente.',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.status.error,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      debugPrint('🏁 [FORGOT_PASSWORD] Finalizando processo');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String? _validateEmail(String? value) {
    return Validators.requiredEmail(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return LoadingOverlay(
      isLoading: _isLoading,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                // PARTE SUPERIOR com background.jpg - REDUZIDA e COM CURVA
                Stack(
                  children: [
                    // Fundo branco completo
                    Container(
                      height: screenHeight * 0.35,
                      width: double.infinity,
                      color: Colors.white,
                    ),
                    // Imagem cortada pela curva
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

                // PARTE INFERIOR com formulário
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(color: Colors.white),
                  padding: EdgeInsets.symmetric(
                    horizontal: screenWidth * 0.08,
                    vertical: screenHeight * 0.04,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Título
                        Text(
                          'Esqueceu',
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w400,
                            color: AppColors.text.text,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          'sua senha?',
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary.primary,
                            letterSpacing: -0.5,
                            height: 0.9,
                          ),
                        ),

                        SizedBox(height: screenHeight * 0.01),
                        // Subtítulo
                        Text(
                          'Digite seu email e enviaremos um link para redefinir sua senha',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.text.textSecondary,
                            letterSpacing: 0.3,
                          ),
                        ),

                        SizedBox(height: screenHeight * 0.025),

                        // Email Field
                        _buildTextField(
                          context: context,
                          controller: _emailController,
                          labelText: 'Email',
                          prefixIcon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          focusNode: _emailFocusNode,
                          validator: _validateEmail,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) {
                            _handleSubmit();
                          },
                        ),

                        SizedBox(height: screenHeight * 0.03),
                        // Submit Button
                        _buildSubmitButton(screenHeight),

                        SizedBox(height: screenHeight * 0.03),
                        // Link para voltar ao login
                        _buildBackToLoginLink(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required BuildContext context,
    required TextEditingController controller,
    required String labelText,
    required IconData prefixIcon,
    TextInputType? keyboardType,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    FocusNode? focusNode,
    void Function(String)? onSubmitted,
    TextInputAction? textInputAction,
  }) {
    final theme = Theme.of(context);
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      focusNode: focusNode,
      onFieldSubmitted: onSubmitted,
      textInputAction: textInputAction ?? TextInputAction.done,
      style: theme.textTheme.bodyLarge?.copyWith(
        color: AppColors.text.text,
      ),
      decoration: InputDecoration(
        labelText: labelText,
        labelStyle: TextStyle(
          color: AppColors.primary.primary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primary.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(prefixIcon, color: AppColors.primary.primary, size: 20),
        ),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.border.borderLight, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.border.borderLight, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.primary.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: AppColors.status.error.withOpacity(0.6),
            width: 1,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.status.error, width: 1.5),
        ),
        errorStyle: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.status.error,
          fontSize: 11,
          height: 1.2,
        ),
        errorMaxLines: 1,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      validator: validator,
    );
  }

  Widget _buildSubmitButton(double screenHeight) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: _isLoading
            ? AppColors.primary.primaryDarkMode
            : AppColors.primary.primary,
        boxShadow: _isLoading
            ? [
                BoxShadow(
                  color: AppColors.primary.primary.withOpacity(0.2),
                  blurRadius: 15,
                  spreadRadius: 0,
                  offset: const Offset(0, 6),
                ),
              ]
            : [
                BoxShadow(
                  color: AppColors.primary.primary.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 0,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : _handleSubmit,
          borderRadius: BorderRadius.circular(16),
          splashColor: Colors.white.withOpacity(0.2),
          highlightColor: Colors.white.withOpacity(0.1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isLoading)
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  )
                else
                  AnimatedOpacity(
                    opacity: _isLoading ? 0.5 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.email_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                const SizedBox(width: 12),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: _isLoading ? 15 : 16,
                    letterSpacing: 0.5,
                  ),
                  child: Text(_isLoading ? 'Enviando...' : 'Enviar Link'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackToLoginLink() {
    return Center(
      child: TextButton(
        onPressed: () {
          Navigator.of(context).pop();
        },
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
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
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.primary.primary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

