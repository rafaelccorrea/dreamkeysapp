import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../shared/services/auth_service.dart';
import '../../../../shared/services/biometric_service.dart';
import '../../../../shared/services/secure_storage_service.dart';
import '../../../../shared/services/login_flow_service.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../shared/widgets/image_curve_clipper.dart';
import '../../../../shared/widgets/loading_overlay.dart';
import '../../../../shared/utils/validators.dart';
import '../widgets/biometric_enrollment_dialog.dart';

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
  bool _biometricLoginAttempted = false; // Flag para evitar múltiplas tentativas
  bool _isBiometricLoginInProgress = false; // Flag para evitar chamadas simultâneas

  @override
  void initState() {
    super.initState();
    _initializeBiometrics();
  }

  /// Inicializa verificação de biometria e credenciais salvas
  Future<void> _initializeBiometrics() async {
    // Verificar biometria primeiro e aguardar conclusão
    await _checkBiometricAvailability();

    // Aguardar um pouco para garantir que o estado foi atualizado
    await Future.delayed(const Duration(milliseconds: 100));

    // Depois verificar credenciais (precisa saber se biometria está disponível)
    await _checkSavedCredentials();
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

    debugPrint('⏳ [LOGIN] Iniciando fluxo completo de login...');

    try {
      final loginFlowService = LoginFlowService.instance;
      final result = await loginFlowService.executeLoginFlow(
        email: email,
        password: _passwordController.text,
        rememberMe: false,
        context: context,
      );

      if (result.requires2FA) {
        debugPrint('🔐 [LOGIN] Navegando para tela de 2FA');
        if (mounted) {
          Navigator.of(context).pushNamed(
            AppRoutes.twoFactor,
            arguments: {
              'email': result.email ?? email,
              'password': result.password ?? _passwordController.text,
              'tempToken': result.tempToken ?? '',
            },
          );
        }
        return;
      }

      if (result.success && result.route != null) {
        debugPrint('✅ [LOGIN] Login bem-sucedido!');
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        if (!mounted) return;

        final savedBio = await showBiometricEnrollmentOffer(
          context,
          email: email,
          password: _passwordController.text,
          biometricHardwareAvailable: _biometricAvailable,
          biometricTypeLabel: _biometricType,
        );
        if (savedBio && mounted) {
          setState(() {
            _hasSavedCredentials = true;
          });
        }

        if (mounted) {
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil(result.route!, (route) => false);
        }
      } else {
        debugPrint('❌ [LOGIN] Login falhou: ${result.message}');
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
                      result.message,
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
    try {
      debugPrint('🔍 [BIOMETRIA] Verificando disponibilidade de biometria...');
      final biometricService = BiometricService.instance;

      final isSupported = await biometricService.isDeviceSupported();
      debugPrint('📱 [BIOMETRIA] Dispositivo suporta: $isSupported');

      final canCheck = await biometricService.canCheckBiometrics();
      debugPrint('✅ [BIOMETRIA] Pode verificar: $canCheck');

      final availableBiometrics = await biometricService
          .getAvailableBiometrics();
      debugPrint('👆 [BIOMETRIA] Biometrias disponíveis: $availableBiometrics');

      final hasBiometrics = await biometricService.hasBiometrics();
      final biometricType = await biometricService
          .getBiometricTypeDescription();

      debugPrint(
        '🔍 [BIOMETRIA] Disponível: $hasBiometrics, Tipo: $biometricType',
      );

      if (mounted) {
        setState(() {
          _biometricAvailable = hasBiometrics;
          _biometricType = biometricType;
        });
        debugPrint(
          '🔄 [BIOMETRIA] Estado atualizado - Disponível: $_biometricAvailable',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [BIOMETRIA] Erro ao verificar biometria: $e');
      debugPrint('📚 [BIOMETRIA] StackTrace: $stackTrace');
      if (mounted) {
        setState(() {
          _biometricAvailable = false;
        });
      }
    }
  }

  /// Verifica se existem credenciais salvas
  Future<void> _checkSavedCredentials() async {
    try {
      debugPrint('💾 [CREDENCIAIS] Verificando credenciais salvas...');
      final hasCredentials = await SecureStorageService.instance
          .hasSavedCredentials();
      debugPrint('💾 [CREDENCIAIS] Credenciais encontradas: $hasCredentials');

      if (mounted) {
        setState(() {
          _hasSavedCredentials = hasCredentials;
        });

        // Se há credenciais salvas E biometria está disponível, tentar login automático
        // Mas apenas se ainda não tentou (evita múltiplas tentativas)
        if (hasCredentials && 
            _biometricAvailable && 
            mounted && 
            !_biometricLoginAttempted && 
            !_isBiometricLoginInProgress) {
          debugPrint(
            '🚀 [BIOMETRIA] Iniciando login automático com biometria...',
          );
          debugPrint(
            '🔍 [BIOMETRIA] Biometria: $_biometricAvailable, Credenciais: $hasCredentials',
          );
          // Aguardar um pouco para a UI carregar completamente
          await Future.delayed(const Duration(milliseconds: 800));

          // Verificar novamente se ainda está montado e as condições ainda são válidas
          // E se não há outra tentativa em progresso
          if (mounted && 
              _biometricAvailable && 
              _hasSavedCredentials && 
              !_biometricLoginAttempted && 
              !_isBiometricLoginInProgress) {
            _handleBiometricLogin(isManual: false);
          } else {
            debugPrint(
              '⚠️ [BIOMETRIA] Condições mudaram durante o delay - não iniciando login automático',
            );
          }
        } else {
          debugPrint(
            'ℹ️ [BIOMETRIA] Login automático não iniciado - Biometria: $_biometricAvailable, Credenciais: $hasCredentials, Já tentado: $_biometricLoginAttempted, Em progresso: $_isBiometricLoginInProgress',
          );
        }
      }
    } catch (e) {
      debugPrint('⚠️ [CREDENCIAIS] Erro ao verificar credenciais: $e');
      // Continuar mesmo com erro - não impede o uso do app
      if (mounted) {
        setState(() {
          _hasSavedCredentials = false;
        });
      }
    }
  }

  /// Realiza login com biometria
  Future<void> _handleBiometricLogin({bool isManual = false}) async {
    debugPrint('🔐 [BIOMETRIA] Iniciando processo de login com biometria...');
    debugPrint('🔐 [BIOMETRIA] Modo: ${isManual ? "Manual" : "Automático"}');

    // Proteção contra chamadas simultâneas
    if (_isBiometricLoginInProgress) {
      debugPrint('⚠️ [BIOMETRIA] Login biométrico já está em progresso, ignorando nova chamada');
      return;
    }

    if (!_biometricAvailable || !_hasSavedCredentials || _isLoading) {
      debugPrint(
        '⚠️ [BIOMETRIA] Condições não atendidas - Biometria: $_biometricAvailable, Credenciais: $_hasSavedCredentials, Loading: $_isLoading',
      );
      return;
    }

    // Se já tentou automaticamente e não é manual, não tentar novamente
    if (!isManual && _biometricLoginAttempted) {
      debugPrint('⚠️ [BIOMETRIA] Login automático já foi tentado, aguardando ação manual do usuário');
      return;
    }

    // Marcar como em progresso
    _isBiometricLoginInProgress = true;
    
    if (!isManual) {
      _biometricLoginAttempted = true; // Marcar como tentado apenas se for automático
    }

    // NÃO setar _isLoading antes de chamar authenticate, pois isso pode causar o "piscar"
    // O LoadingOverlay será ativado apenas após a autenticação bem-sucedida

    try {
      // Autenticar com biometria
      debugPrint('👆 [BIOMETRIA] Solicitando autenticação biométrica...');
      debugPrint('👆 [BIOMETRIA] Reason: Use $_biometricType para fazer login');
      final biometricService = BiometricService.instance;
      
      // Verificar novamente antes de chamar authenticate
      final hasBiometrics = await biometricService.hasBiometrics();
      debugPrint('👆 [BIOMETRIA] Verificação final - hasBiometrics: $hasBiometrics');
      
      if (!hasBiometrics) {
        debugPrint('❌ [BIOMETRIA] Biometria não disponível na verificação final');
        _isBiometricLoginInProgress = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Biometria não disponível no momento'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
        return;
      }
      
      final authenticated = await biometricService.authenticate(
        reason: 'Use $_biometricType para fazer login',
      );
      
      debugPrint('👆 [BIOMETRIA] Resultado da autenticação: $authenticated');

      if (!authenticated) {
        debugPrint('❌ [BIOMETRIA] Autenticação biométrica cancelada ou falhou');
        _isBiometricLoginInProgress = false; // Liberar flag
        // Não precisa setar _isLoading pois não foi setado antes
        // Se foi cancelado manualmente, permitir nova tentativa
        if (isManual) {
          debugPrint('ℹ️ [BIOMETRIA] Cancelamento manual - usuário pode tentar novamente');
        } else {
          debugPrint('ℹ️ [BIOMETRIA] Cancelamento automático - aguardando ação do usuário');
        }
        return;
      }

      debugPrint('✅ [BIOMETRIA] Autenticação biométrica bem-sucedida');
      
      // Agora sim, ativar o loading para o processo de login
      if (mounted) {
        setState(() {
          _isLoading = true;
        });
      }

      // Buscar credenciais salvas
      debugPrint('💾 [BIOMETRIA] Buscando credenciais salvas...');
      final email = await SecureStorageService.instance.getSavedEmail();
      final password = await SecureStorageService.instance.getSavedPassword();

      if (email == null || password == null) {
        debugPrint('❌ [BIOMETRIA] Credenciais não encontradas');
        _isBiometricLoginInProgress = false; // Liberar flag
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
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
          // Navegar para o dashboard
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
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
      _isBiometricLoginInProgress = false; // Sempre liberar flag no finally
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
    final isDark = theme.brightness == Brightness.dark;

    return LoadingOverlay(
      isLoading: _isLoading,
      child: Scaffold(
        backgroundColor:
            isDark ? AppColors.background.backgroundDarkMode : Colors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  children: [
                    Container(
                      height: screenHeight * 0.35,
                      width: double.infinity,
                      color: isDark
                          ? AppColors.background.backgroundSecondaryDarkMode
                          : Colors.white,
                    ),
                    SizedBox(
                      height: screenHeight * 0.35,
                      width: double.infinity,
                      child: ClipPath(
                        clipper: ImageCurveClipper(),
                        child: Container(
                          decoration: BoxDecoration(
                            image: DecorationImage(
                              image: const AssetImage(AppAssets.backgroundLogin),
                              fit: BoxFit.cover,
                              colorFilter: isDark
                                  ? ColorFilter.mode(
                                      Colors.black.withValues(alpha: 0.5),
                                      BlendMode.darken,
                                    )
                                  : null,
                            ),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.white.withValues(
                                    alpha: isDark ? 0.08 : 0.2,
                                  ),
                                  Colors.white.withValues(
                                    alpha: isDark ? 0.35 : 0.72,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Container(
                  width: double.infinity,
                  color: isDark
                      ? AppColors.background.backgroundDarkMode
                      : Colors.white,
                  padding: EdgeInsets.symmetric(
                    horizontal: screenWidth * 0.08,
                    vertical: screenHeight * 0.035,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bem-vindo',
                          style: theme.textTheme.displaySmall?.copyWith(
                                fontWeight: FontWeight.w400,
                                color: isDark
                                    ? AppColors.text.textDarkMode
                                    : AppColors.text.text,
                                letterSpacing: 0.5,
                              ) ??
                              GoogleFonts.poppins(
                                fontSize: 28,
                                fontWeight: FontWeight.w400,
                                color: isDark
                                    ? AppColors.text.textDarkMode
                                    : AppColors.text.text,
                              ),
                        ),
                        Text(
                          'de volta!',
                          style: theme.textTheme.displaySmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? AppColors.primary.primaryDarkMode
                                    : AppColors.primary.primary,
                                letterSpacing: -0.5,
                                height: 0.95,
                              ) ??
                              GoogleFonts.poppins(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? AppColors.primary.primaryDarkMode
                                    : AppColors.primary.primary,
                                height: 0.95,
                              ),
                        ),
                        SizedBox(height: screenHeight * 0.012),
                        Text(
                          'Entre na sua conta',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: isDark
                                ? AppColors.text.textSecondaryDarkMode
                                : AppColors.text.textSecondary,
                            letterSpacing: 0.2,
                          ),
                        ),
                        SizedBox(height: screenHeight * 0.028),
                        _buildTextField(
                          context: context,
                          isDark: isDark,
                          controller: _emailController,
                          labelText: 'E-mail',
                          keyboardType: TextInputType.emailAddress,
                          focusNode: _emailFocusNode,
                          validator: _validateEmail,
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) {
                            _passwordFocusNode.requestFocus();
                          },
                        ),
                        SizedBox(height: screenHeight * 0.018),
                        _buildTextField(
                          context: context,
                          isDark: isDark,
                          controller: _passwordController,
                          labelText: 'Senha',
                          obscureText: _obscureText,
                          focusNode: _passwordFocusNode,
                          validator: _validatePassword,
                          onSubmitted: (_) {
                            _handleLogin();
                          },
                          suffixIcon: _buildPasswordToggle(isDark),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {
                              Navigator.of(context).pushNamed(
                                AppRoutes.forgotPassword,
                              );
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Esqueceu a senha?',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppColors.primary.primaryDarkMode
                                    : AppColors.primary.primary,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: screenHeight * 0.02),
                        _buildLoginButton(screenHeight, isDark),
                        if (_biometricAvailable &&
                            _hasSavedCredentials &&
                            !_isLoading) ...[
                          const SizedBox(height: 14),
                          _buildBiometricButton(isDark),
                        ],
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
    required bool isDark,
    required TextEditingController controller,
    required String labelText,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    FocusNode? focusNode,
    void Function(String)? onSubmitted,
    TextInputAction? textInputAction,
  }) {
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final fillColor = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : const Color(0xFFF3F4F6);
    final borderColor = isDark
        ? AppColors.border.borderDarkMode.withValues(alpha: 0.9)
        : AppColors.border.border;
    final labelMuted =
        isDark ? AppColors.text.textLightDarkMode : AppColors.text.textLight;

    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      focusNode: focusNode,
      onFieldSubmitted: onSubmitted,
      textInputAction:
          textInputAction ??
          (onSubmitted != null ? TextInputAction.next : TextInputAction.done),
      style: GoogleFonts.poppins(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: isDark ? AppColors.text.textDarkMode : AppColors.text.text,
        height: 1.25,
      ),
      decoration: InputDecoration(
        isDense: true,
        labelText: labelText,
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        labelStyle: GoogleFonts.poppins(
          color: labelMuted,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        floatingLabelStyle: GoogleFonts.poppins(
          color: accent,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        suffixIcon: suffixIcon,
        suffixIconConstraints: const BoxConstraints(
          minWidth: 40,
          minHeight: 40,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: borderColor, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: borderColor, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: AppColors.status.error.withValues(alpha: 0.7),
            width: 1,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.status.error, width: 1.25),
        ),
        errorStyle: GoogleFonts.poppins(
          color: AppColors.status.error,
          fontSize: 11,
          height: 1.2,
        ),
        errorMaxLines: 2,
        filled: true,
        fillColor: fillColor,
        contentPadding: const EdgeInsets.fromLTRB(16, 18, 12, 18),
      ),
      validator: validator,
    );
  }

  Widget _buildPasswordToggle(bool isDark) {
    final muted = isDark
        ? AppColors.text.textSecondaryDarkMode
        : AppColors.text.textSecondary;

    return IconButton(
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        foregroundColor: muted,
        hoverColor: muted.withValues(alpha: 0.08),
        minimumSize: const Size(40, 40),
        padding: EdgeInsets.zero,
      ),
      icon: Icon(
        _obscureText
            ? Icons.visibility_outlined
            : Icons.visibility_off_outlined,
        size: 20,
      ),
      tooltip: _obscureText ? 'Mostrar senha' : 'Ocultar senha',
      onPressed: () {
        setState(() {
          _obscureText = !_obscureText;
        });
      },
    );
  }

  Widget _buildLoginButton(double screenHeight, bool isDark) {
    final base = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;

    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton(
        onPressed: _isLoading
            ? null
            : () {
                FocusScope.of(context).unfocus();
                _handleLogin();
              },
        style: FilledButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
          backgroundColor: base,
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
          disabledBackgroundColor: base.withValues(alpha: 0.55),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
            : const Text('Entrar'),
      ),
    );
  }

  Widget _buildBiometricButton(bool isDark) {
    final borderColor = isDark
        ? AppColors.border.borderDarkMode
        : AppColors.border.border;
    final fg = isDark
        ? AppColors.text.textDarkMode
        : AppColors.text.text;

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: _isLoading ? null : () => _handleBiometricLogin(isManual: true),
        style: OutlinedButton.styleFrom(
          elevation: 0,
          foregroundColor: fg,
          side: BorderSide(color: borderColor, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _biometricType.contains('Face')
                  ? Icons.face_outlined
                  : Icons.fingerprint_outlined,
              size: 20,
              color: fg.withValues(alpha: 0.85),
            ),
            const SizedBox(width: 10),
            Text('Entrar com $_biometricType'),
          ],
        ),
      ),
    );
  }

}
