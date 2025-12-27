import 'package:flutter/material.dart';
import '../../../../shared/services/auth_service.dart';
import '../../../../shared/services/biometric_service.dart';
import '../../../../shared/services/secure_storage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/image_curve_clipper.dart';
import '../../../../shared/widgets/loading_overlay.dart';
import '../../../../shared/utils/validators.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  bool _isLoading = false;
  bool _obscureText = true;
  bool _biometricAvailable = false;
  bool _hasSavedCredentials = false;
  String _biometricType = 'Biometria';
  bool _saveCredentials = false;

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailability();
    _checkSavedCredentials();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    debugPrint('🔐 [LOGIN] Iniciando processo de login...');

    // Fechar teclado primeiro
    FocusScope.of(context).unfocus();

    final email = _emailController.text.trim().toLowerCase();
    debugPrint('📧 [LOGIN] Email: $email');
    debugPrint(
      '🔑 [LOGIN] Senha: ${_passwordController.text.isNotEmpty ? "***" : "(vazia)"}',
    );

    // Validar formulário
    if (!_formKey.currentState!.validate()) {
      debugPrint('❌ [LOGIN] Validação do formulário falhou');
      // Feedback de validação via SnackBar ao invés de quebrar layout
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Por favor, preencha todos os campos corretamente',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.status.warning,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    debugPrint('⏳ [LOGIN] Enviando requisição de login para a API...');

    try {
      final authService = AuthService.instance;
      final loginRequest = LoginRequest(
        email: email,
        password: _passwordController.text,
      );

      debugPrint('📤 [LOGIN] Request: ${loginRequest.toJson()}');

      final response = await authService.login(loginRequest);

      debugPrint(
        '📥 [LOGIN] Response recebida - Status: ${response.statusCode}, Success: ${response.success}',
      );

      if (response.success && response.data != null) {
        debugPrint('✅ [LOGIN] Login bem-sucedido!');
        debugPrint(
          '👤 [LOGIN] Usuário: ${response.data?.user.name} (${response.data?.user.email})',
        );
        final token = response.data?.token ?? '';
        if (token.isNotEmpty) {
          final tokenPreview = token.length > 20
              ? '${token.substring(0, 20)}...'
              : token;
          debugPrint('🎫 [LOGIN] Token: $tokenPreview');
        } else {
          debugPrint('⚠️ [LOGIN] Token está vazio');
        }
        // Login bem-sucedido - salvar credenciais se solicitado
        if (_saveCredentials && _biometricAvailable) {
          debugPrint('💾 [LOGIN] Salvando credenciais para biometria...');
          await SecureStorageService.instance.saveCredentials(
            email: email,
            password: _passwordController.text,
          );
          setState(() {
            _hasSavedCredentials = true;
          });
          debugPrint('✅ [LOGIN] Credenciais salvas com sucesso');
        }

        if (mounted) {
          // TODO: Navegar para a tela principal do app
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Login realizado com sucesso!'),
              backgroundColor: Color(0xFF10B981),
            ),
          );
        }
      } else {
        debugPrint('❌ [LOGIN] Login falhou');
        debugPrint('📊 [LOGIN] Status Code: ${response.statusCode}');
        debugPrint('📋 [LOGIN] Mensagem: ${response.message}');
        debugPrint('🔍 [LOGIN] Error: ${response.error}');

        // Verificar se requer 2FA
        if (response.statusCode == 401 &&
            response.error != null &&
            response.error['errorCode'] == '2FA_REQUIRED') {
          debugPrint('🔐 [LOGIN] Autenticação 2FA requerida');
          // TODO: Navegar para tela de 2FA
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Autenticação de dois fatores requerida'),
                backgroundColor: Color(0xFFF59E0B),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        response.message ??
                            'Email ou senha incorretos. Tente novamente.',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
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
      }
    } catch (e, stackTrace) {
      debugPrint('💥 [LOGIN] Exceção capturada durante login');
      debugPrint('❌ [LOGIN] Erro: $e');
      debugPrint('📚 [LOGIN] StackTrace: $stackTrace');

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
      debugPrint('🏁 [LOGIN] Finalizando processo de login');
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

  String? _validatePassword(String? value) {
    return Validators.password(value);
  }

  /// Verifica se a biometria está disponível no dispositivo
  Future<void> _checkBiometricAvailability() async {
    debugPrint('🔍 [BIOMETRIA] Verificando disponibilidade de biometria...');
    final biometricService = BiometricService.instance;
    final hasBiometrics = await biometricService.hasBiometrics();
    final biometricType = await biometricService.getBiometricTypeDescription();

    debugPrint(
      '🔍 [BIOMETRIA] Disponível: $hasBiometrics, Tipo: $biometricType',
    );

    if (mounted) {
      setState(() {
        _biometricAvailable = hasBiometrics;
        _biometricType = biometricType;
      });
    }
  }

  /// Verifica se existem credenciais salvas
  Future<void> _checkSavedCredentials() async {
    debugPrint('💾 [CREDENCIAIS] Verificando credenciais salvas...');
    final hasCredentials = await SecureStorageService.instance
        .hasSavedCredentials();
    debugPrint('💾 [CREDENCIAIS] Credenciais encontradas: $hasCredentials');

    if (mounted) {
      setState(() {
        _hasSavedCredentials = hasCredentials;
      });

      // Se há credenciais salvas, tentar login automático com biometria
      if (hasCredentials && _biometricAvailable) {
        debugPrint(
          '🚀 [BIOMETRIA] Iniciando login automático com biometria...',
        );
        // Aguardar um pouco para a UI carregar
        await Future.delayed(const Duration(milliseconds: 500));
        _handleBiometricLogin();
      }
    }
  }

  /// Realiza login com biometria
  Future<void> _handleBiometricLogin() async {
    debugPrint('🔐 [BIOMETRIA] Iniciando processo de login com biometria...');

    if (!_biometricAvailable || !_hasSavedCredentials || _isLoading) {
      debugPrint(
        '⚠️ [BIOMETRIA] Condições não atendidas - Biometria: $_biometricAvailable, Credenciais: $_hasSavedCredentials, Loading: $_isLoading',
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Autenticar com biometria
      debugPrint('👆 [BIOMETRIA] Solicitando autenticação biométrica...');
      final biometricService = BiometricService.instance;
      final authenticated = await biometricService.authenticate(
        reason: 'Use $_biometricType para fazer login',
      );

      if (!authenticated) {
        debugPrint('❌ [BIOMETRIA] Autenticação biométrica cancelada ou falhou');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      debugPrint('✅ [BIOMETRIA] Autenticação biométrica bem-sucedida');

      // Buscar credenciais salvas
      debugPrint('💾 [BIOMETRIA] Buscando credenciais salvas...');
      final email = await SecureStorageService.instance.getSavedEmail();
      final password = await SecureStorageService.instance.getSavedPassword();

      if (email == null || password == null) {
        debugPrint('❌ [BIOMETRIA] Credenciais não encontradas');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      debugPrint('📧 [BIOMETRIA] Email recuperado: $email');

      // Preencher campos
      _emailController.text = email;
      _passwordController.text = password;

      // Realizar login
      debugPrint('⏳ [BIOMETRIA] Enviando requisição de login para a API...');
      final authService = AuthService.instance;
      final loginRequest = LoginRequest(email: email, password: password);

      debugPrint('📤 [BIOMETRIA] Request: ${loginRequest.toJson()}');

      final response = await authService.login(loginRequest);

      debugPrint(
        '📥 [BIOMETRIA] Response recebida - Status: ${response.statusCode}, Success: ${response.success}',
      );

      if (response.success && response.data != null) {
        debugPrint('✅ [BIOMETRIA] Login bem-sucedido!');
        debugPrint(
          '👤 [BIOMETRIA] Usuário: ${response.data?.user.name} (${response.data?.user.email})',
        );
        if (mounted) {
          // TODO: Navegar para a tela principal do app
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Login realizado com $_biometricType!',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        debugPrint('❌ [BIOMETRIA] Login falhou');
        debugPrint('📊 [BIOMETRIA] Status Code: ${response.statusCode}');
        debugPrint('📋 [BIOMETRIA] Mensagem: ${response.message}');
        debugPrint('🔍 [BIOMETRIA] Error: ${response.error}');

        // Se o login falhar, limpar credenciais salvas
        debugPrint('🗑️ [BIOMETRIA] Limpando credenciais inválidas...');
        await SecureStorageService.instance.clearCredentials();
        if (mounted) {
          setState(() {
            _hasSavedCredentials = false;
          });
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
                          'Credenciais inválidas. Faça login novamente.',
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
      debugPrint(
        '💥 [BIOMETRIA] Exceção capturada durante login com biometria',
      );
      debugPrint('❌ [BIOMETRIA] Erro: $e');
      debugPrint('📚 [BIOMETRIA] StackTrace: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Erro ao autenticar com $_biometricType',
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
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      debugPrint('🏁 [BIOMETRIA] Finalizando processo de login com biometria');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
                // PARTE SUPERIOR com background.jpg - REDUZIDA e COM CURVA
                Stack(
                  children: [
                    // Fundo branco completo (aparece na área cortada pela curva)
                    Container(
                      height: screenHeight * 0.35,
                      width: double.infinity,
                      color: Colors.white,
                    ),
                    // Imagem cortada pela curva (a área cortada mostra o branco de fundo)
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
                        // Título "Bem-vindo de volta"
                        Text(
                          'Bem-vindo',
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w400,
                            color: AppColors.text.text,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          'de volta!',
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
                          'Entre na sua conta',
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
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) {
                            _passwordFocusNode.requestFocus();
                          },
                        ),

                        SizedBox(height: screenHeight * 0.02),
                        // Password Field
                        _buildTextField(
                          context: context,
                          controller: _passwordController,
                          labelText: 'Senha',
                          prefixIcon: Icons.lock_outline,
                          obscureText: _obscureText,
                          focusNode: _passwordFocusNode,
                          validator: _validatePassword,
                          onSubmitted: (_) {
                            _handleLogin();
                          },
                          suffixIcon: _buildPasswordToggle(),
                        ),

                        SizedBox(height: screenHeight * 0.03),
                        // Login Button
                        _buildLoginButton(screenHeight),

                        // Botão de Biometria (se disponível e há credenciais salvas)
                        if (_biometricAvailable && _hasSavedCredentials) ...[
                          SizedBox(height: screenHeight * 0.02),
                          _buildBiometricButton(),
                        ],

                        // Checkbox para salvar credenciais (se biometria disponível)
                        if (_biometricAvailable && !_hasSavedCredentials) ...[
                          SizedBox(height: screenHeight * 0.02),
                          _buildSaveCredentialsCheckbox(),
                        ],

                        SizedBox(height: screenHeight * 0.03),
                        // Links de Ajuda
                        _buildHelpLinks(),

                        SizedBox(height: screenHeight * 0.02),
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
    bool obscureText = false,
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
      obscureText: obscureText,
      focusNode: focusNode,
      onFieldSubmitted: onSubmitted,
      textInputAction:
          textInputAction ??
          (onSubmitted != null ? TextInputAction.next : TextInputAction.done),
      style: theme.textTheme.bodyLarge?.copyWith(
        color:
            AppColors.text.text, // Sempre cor de texto do light mode no input
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

  Widget _buildPasswordToggle() {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: IconButton(
        icon: Icon(
          _obscureText
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
          color: AppColors.primary.primary,
          size: 20,
        ),
        onPressed: () {
          setState(() {
            _obscureText = !_obscureText;
          });
        },
      ),
    );
  }

  Widget _buildLoginButton(double screenHeight) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: _isLoading
            ? AppColors.primary.primaryDark
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
          onTap: _isLoading
              ? null
              : () {
                  // Feedback haptic (se disponível)
                  FocusScope.of(context).unfocus();
                  _handleLogin();
                },
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
                        Icons.login_rounded,
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
                  child: Text(_isLoading ? 'Entrando...' : 'Entrar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBiometricButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.primary.withOpacity(0.3),
          width: 1.5,
        ),
        color: Colors.transparent,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : _handleBiometricLogin,
          borderRadius: BorderRadius.circular(16),
          splashColor: AppColors.primary.primary.withOpacity(0.1),
          highlightColor: AppColors.primary.primary.withOpacity(0.05),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _biometricType.contains('Face')
                      ? Icons.face_outlined
                      : Icons.fingerprint_outlined,
                  color: AppColors.primary.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Entrar com $_biometricType',
                  style: TextStyle(
                    color: AppColors.primary.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
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

  Widget _buildSaveCredentialsCheckbox() {
    return Row(
      children: [
        SizedBox(
          height: 24,
          width: 24,
          child: Checkbox(
            value: _saveCredentials,
            onChanged: (value) {
              setState(() {
                _saveCredentials = value ?? false;
              });
            },
            activeColor: AppColors.primary.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                _saveCredentials = !_saveCredentials;
              });
            },
            child: Text(
              'Salvar credenciais para $_biometricType',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.text.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHelpLinks() {
    return Column(
      children: [
        // Esqueceu a senha - Alinhado à esquerda
        Row(
          children: [
            TextButton(
              onPressed: () {
                // TODO: Implementar recuperação de senha
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Funcionalidade em breve')),
                );
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 0,
                  vertical: 12,
                ),
              ),
              child: Text(
                'Esqueceu a senha?',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.primary.primary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
