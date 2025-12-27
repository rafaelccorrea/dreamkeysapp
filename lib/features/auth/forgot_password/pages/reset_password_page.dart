import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/services/auth_service.dart';
import '../../../../shared/widgets/image_curve_clipper.dart';
import '../../../../shared/widgets/loading_overlay.dart';
import '../../../../shared/utils/validators.dart';

class ResetPasswordPage extends StatefulWidget {
  final String? token;

  const ResetPasswordPage({super.key, this.token});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  final _confirmPasswordFocusNode = FocusNode();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    // Se não tiver token, pode ser que venha dos argumentos da rota
    if (widget.token == null || widget.token!.isEmpty) {
      debugPrint('⚠️ [RESET_PASSWORD] Token não fornecido');
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    debugPrint('🔐 [RESET_PASSWORD] Iniciando redefinição de senha...');

    final token = widget.token;
    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Token inválido. Solicite um novo link.'),
          backgroundColor: AppColors.status.error,
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      debugPrint('❌ [RESET_PASSWORD] Validação do formulário falhou');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final authService = AuthService.instance;
      final response = await authService.resetPassword(
        token: token,
        password: _passwordController.text,
        confirmPassword: _confirmPasswordController.text,
      );

      debugPrint(
        '📥 [RESET_PASSWORD] Response - Status: ${response.statusCode}, Success: ${response.success}',
      );

      if (response.success) {
        debugPrint('✅ [RESET_PASSWORD] Senha redefinida com sucesso');

        // Mostrar mensagem de sucesso
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Senha alterada com sucesso!',
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
        }

        // Navegar para login após 2 segundos
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
        }
      } else {
        debugPrint('❌ [RESET_PASSWORD] Falha ao redefinir senha');
        debugPrint('📋 [RESET_PASSWORD] Mensagem: ${response.message}');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      response.message ??
                          'Erro ao redefinir senha. Verifique o token ou tente novamente.',
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
      debugPrint('💥 [RESET_PASSWORD] Exceção capturada');
      debugPrint('❌ [RESET_PASSWORD] Erro: $e');
      debugPrint('📚 [RESET_PASSWORD] StackTrace: $stackTrace');

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
      debugPrint('🏁 [RESET_PASSWORD] Finalizando processo');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String? _validatePassword(String? value) {
    return Validators.password(value);
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Por favor, confirme sua senha';
    }
    if (value != _passwordController.text) {
      return 'As senhas não coincidem';
    }
    return null;
  }

  String _getPasswordStrength(String password) {
    if (password.isEmpty) return '';
    if (password.length < 6) return 'Fraca';
    if (password.length < 8 ||
        !password.contains(RegExp(r'[A-Z]')) ||
        !password.contains(RegExp(r'[0-9]'))) {
      return 'Média';
    }
    return 'Forte';
  }

  Color _getPasswordStrengthColor(String strength) {
    switch (strength) {
      case 'Fraca':
        return AppColors.status.error;
      case 'Média':
        return AppColors.status.warning;
      case 'Forte':
        return AppColors.status.success;
      default:
        return Colors.transparent;
    }
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
                          'Nova',
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w400,
                            color: AppColors.text.text,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          'Senha',
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
                          'Digite sua nova senha para continuar',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.text.textSecondary,
                            letterSpacing: 0.3,
                          ),
                        ),

                        SizedBox(height: screenHeight * 0.025),

                        // Password Field
                        _buildPasswordField(
                          context: context,
                          controller: _passwordController,
                          labelText: 'Nova Senha',
                          focusNode: _passwordFocusNode,
                          obscureText: _obscurePassword,
                          validator: _validatePassword,
                          onChanged: (value) {
                            setState(() {}); // Atualizar indicador de força
                          },
                          suffixIcon: _buildPasswordToggle(
                            () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                            _obscurePassword,
                          ),
                        ),

                        // Indicador de força da senha
                        if (_passwordController.text.isNotEmpty) ...[
                          SizedBox(height: screenHeight * 0.01),
                          _buildPasswordStrengthIndicator(),
                        ],

                        SizedBox(height: screenHeight * 0.02),

                        // Confirm Password Field
                        _buildPasswordField(
                          context: context,
                          controller: _confirmPasswordController,
                          labelText: 'Confirmar Senha',
                          focusNode: _confirmPasswordFocusNode,
                          obscureText: _obscureConfirmPassword,
                          validator: _validateConfirmPassword,
                          suffixIcon: _buildPasswordToggle(
                            () => setState(
                              () => _obscureConfirmPassword =
                                  !_obscureConfirmPassword,
                            ),
                            _obscureConfirmPassword,
                          ),
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

  Widget _buildPasswordField({
    required BuildContext context,
    required TextEditingController controller,
    required String labelText,
    required FocusNode focusNode,
    required bool obscureText,
    required String? Function(String?)? validator,
    required Widget suffixIcon,
    void Function(String)? onChanged,
  }) {
    final theme = Theme.of(context);
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      focusNode: focusNode,
      onFieldSubmitted: (_) {
        if (labelText.contains('Nova')) {
          _confirmPasswordFocusNode.requestFocus();
        } else {
          _handleSubmit();
        }
      },
      onChanged: onChanged,
      textInputAction: labelText.contains('Nova')
          ? TextInputAction.next
          : TextInputAction.done,
      style: theme.textTheme.bodyLarge?.copyWith(color: AppColors.text.text),
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
          child: Icon(
            Icons.lock_outline,
            color: AppColors.primary.primary,
            size: 20,
          ),
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

  Widget _buildPasswordToggle(VoidCallback onTap, bool obscureText) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: IconButton(
        icon: Icon(
          obscureText
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
          color: AppColors.primary.primary,
          size: 20,
        ),
        onPressed: onTap,
      ),
    );
  }

  Widget _buildPasswordStrengthIndicator() {
    final strength = _getPasswordStrength(_passwordController.text);
    if (strength.isEmpty) return const SizedBox.shrink();

    final color = _getPasswordStrengthColor(strength);
    return Row(
      children: [
        Container(
          width: 60,
          height: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Força: $strength',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
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
                        Icons.lock_reset,
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
                  child: Text(_isLoading ? 'Alterando...' : 'Alterar Senha'),
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
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
        },
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_back, color: AppColors.primary.primary, size: 18),
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
