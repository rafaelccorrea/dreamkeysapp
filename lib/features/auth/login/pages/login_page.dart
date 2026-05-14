import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/layout/handheld_layout.dart';
import '../../../../core/notifications/app_toast.dart';
import '../../../../core/push/app_push_service.dart';
import '../../../../shared/services/auth_service.dart';
import '../../../../shared/services/biometric_service.dart';
import '../../../../shared/services/secure_storage_service.dart';
import '../../../../shared/services/login_flow_service.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../shared/widgets/brand_wordmark_logo.dart';
import '../../../../shared/widgets/image_curve_clipper.dart';
import '../../../../shared/widgets/loading_overlay.dart';
import '../../../../shared/utils/validators.dart';
import '../widgets/biometric_enrollment_dialog.dart';

/// Permite scroll apenas quando há overflow real (biometria, teclado, telas baixas).
class _LoginViewportScrollPhysics extends ScrollPhysics {
  const _LoginViewportScrollPhysics({super.parent});

  @override
  _LoginViewportScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _LoginViewportScrollPhysics(parent: buildParent(ancestor));

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) {
    return position.maxScrollExtent > 0 || position.minScrollExtent < 0;
  }
}

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
    _emailFocusNode.addListener(_onFocusChange);
    _passwordFocusNode.addListener(_onFocusChange);
    _initializeBiometrics();
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
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
    _emailFocusNode.removeListener(_onFocusChange);
    _passwordFocusNode.removeListener(_onFocusChange);
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
      AppToast.warning(
        context,
        'Preencha todos os campos corretamente',
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

        // ────────────────────────────────────────────────────────────────
        // Permissões do sistema PRIMEIRO (notificações + token FCM).
        //
        // Antes isso só rodava no splash — então em produção, no PRIMEIRO
        // login da vida do app, nenhum popup de permissão aparecia: o
        // usuário precisaria reabrir o app pra ver o prompt. Agora pedimos
        // imediatamente após login, antes de qualquer outro popup nosso,
        // pra não sobrepor o popup nativo do SO.
        try {
          await AppPushService.instance.syncWithBackendIfAuthenticated();
        } catch (e) {
          debugPrint('⚠️ [LOGIN] Falha ao sincronizar permissões push: $e');
        }
        if (!mounted) return;

        // Oferta de biometria (UI nossa) só DEPOIS que os popups nativos
        // de permissão foram resolvidos.
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
          AppToast.error(context, result.message);
        }
      }
    } catch (e, stackTrace) {
      debugPrint('💥 [LOGIN] Exceção capturada durante login');
      debugPrint('❌ [LOGIN] Erro: $e');
      debugPrint('📚 [LOGIN] StackTrace: $stackTrace');

      if (mounted) {
        AppToast.error(
          context,
          'Erro ao conectar com o servidor. Tente novamente.',
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
          AppToast.error(context, 'Biometria não disponível no momento');
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
          AppToast.error(
            context,
            response.message ??
                'Credenciais inválidas. Faça login novamente.',
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
        AppToast.error(context, 'Erro ao autenticar com $_biometricType');
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
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final screenWidth = mediaQuery.size.width;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final headerHeight =
        screenHeight * HandheldLayout.loginHeroHeightFraction(screenHeight);
    final heroTotalHeight = headerHeight + 24;
    final formSheetTop = heroTotalHeight - 32;
    final pageBg =
        isDark ? AppColors.background.backgroundDarkMode : Colors.white;

    // Inset do sistema (barra de gestos ou 3 botões). Como o SafeArea está
    // com bottom:false (pra a sheet arrematar visualmente até a borda),
    // somamos o inset no padding inferior do conteúdo pra o footer
    // "Powered by Intellisys" não ficar por baixo da nav system em
    // celulares maiores com botões de navegação.
    final systemBottomInset = mediaQuery.padding.bottom;

    final formHorizontal = HandheldLayout.loginFormHorizontalPadding(screenWidth);

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
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            children: [
              _buildHeroHeader(
                isDark: isDark,
                height: headerHeight,
                statusBarTop: mediaQuery.padding.top,
              ),
              Positioned(
                left: 0,
                right: 0,
                top: formSheetTop,
                bottom: 0,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: _LoginViewportScrollPhysics(
                        parent: ClampingScrollPhysics(),
                      ),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
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
                            screenHeight * 0.035 + systemBottomInset,
                          ),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildAccentLine(isDark),
                                const SizedBox(height: 12),
                                _buildWelcomeTitle(context, isDark),
                                SizedBox(height: screenHeight * 0.008),
                                Text(
                                  'Entre na sua conta para continuar',
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
                                  prefixIcon: Icons.alternate_email_rounded,
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
                                  prefixIcon: Icons.lock_outline_rounded,
                                  obscureText: _obscureText,
                                  focusNode: _passwordFocusNode,
                                  validator: _validatePassword,
                                  onSubmitted: (_) {
                                    _handleLogin();
                                  },
                                  suffixIcon: _buildPasswordToggle(isDark),
                                ),
                                const SizedBox(height: 6),
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
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
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
                                SizedBox(height: screenHeight * 0.022),
                                _buildLoginButton(screenHeight, isDark),
                                // Só mostra o caminho de biometria quando há
                                // credenciais salvas (botão grande + divider
                                // "ou"). Sem credenciais, não polui a UI: o
                                // enrollment é oferecido após o primeiro
                                // login bem-sucedido.
                                if (_biometricAvailable &&
                                    _hasSavedCredentials &&
                                    !_isLoading) ...[
                                  const SizedBox(height: 18),
                                  _buildOrDivider(isDark),
                                  const SizedBox(height: 14),
                                  _buildBiometricButton(isDark),
                                ],
                                SizedBox(height: screenHeight * 0.025),
                                _buildFooter(isDark),
                                SizedBox(height: screenHeight * 0.015),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  /// Cabeçalho com imagem, gradiente tonal e brand mark.
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
            top: statusBarTop +
                (HandheldLayout.isIosPhone ? 8 : 18),
            left: HandheldLayout.isIosPhone ? 12 : 16,
            right: HandheldLayout.isIosPhone ? 16 : 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildBrandMark(isDark),
                _buildHeaderChip(isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrandMark(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 7, 10, 7),
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
      child: BrandWordmarkLogo(
        height: 18,
        maxWidth: 88,
        alignment: Alignment.centerLeft,
        variant: BrandWordmarkVariant.loading,
      ),
    );
  }

  /// Selo discreto no hero — mesmo vocabulário visual do chip da marca (vidro
  /// fosco), sem bolinha colorida nem borda forte no accent.
  Widget _buildHeaderChip(bool isDark) {
    final fg = (isDark ? Colors.white : Colors.black87).withValues(
      alpha: isDark ? 0.92 : 0.85,
    );

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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shield_outlined,
            size: 15,
            color: fg,
          ),
          const SizedBox(width: 6),
          Text(
            'Conexão segura',
            style: GoogleFonts.poppins(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: fg,
              letterSpacing: 0.15,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  /// Título "Bem-vindo ao [logo Intellisys]" — usa o wordmark do tema claro
  /// recortado (variante `loading`) para neutralizar o range vazio do PNG.
  Widget _buildWelcomeTitle(BuildContext context, bool isDark) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Bem-vindo ao',
          style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w400,
                color: isDark
                    ? AppColors.text.textDarkMode
                    : AppColors.text.text,
                letterSpacing: 0.5,
                height: 1.0,
              ) ??
              GoogleFonts.poppins(
                fontSize: 28,
                fontWeight: FontWeight.w400,
                color: isDark
                    ? AppColors.text.textDarkMode
                    : AppColors.text.text,
                height: 1.0,
              ),
        ),
        const SizedBox(height: 6),
        Transform.translate(
          offset: const Offset(-14, 0),
          child: BrandWordmarkLogo(
            height: 44,
            maxWidth: 200,
            alignment: Alignment.centerLeft,
            variant: BrandWordmarkVariant.loading,
          ),
        ),
      ],
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

  Widget _buildFooter(bool isDark) {
    final muted = isDark
        ? AppColors.text.textLightDarkMode
        : AppColors.text.textLight;

    // Largura total + centro na tela; leve padding à esquerda compensa o
    // translate do PNG do logo (layout não acompanha o paint).
    return SizedBox(
      width: double.infinity,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.only(left: 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 13,
                    color: muted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Conexão criptografada',
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: muted,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Powered by',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: muted,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Transform.translate(
                    offset: const Offset(-10, 0),
                    child: BrandWordmarkLogo(
                      height: 16,
                      maxWidth: 56,
                      alignment: Alignment.centerLeft,
                      variant: BrandWordmarkVariant.loading,
                    ),
                  ),
                ],
              ),
            ],
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
    IconData? prefixIcon,
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
        : const Color(0xFFF6F7FB);
    final borderColor = isDark
        ? AppColors.border.borderDarkMode.withValues(alpha: 0.9)
        : AppColors.border.border;
    final labelMuted =
        isDark ? AppColors.text.textLightDarkMode : AppColors.text.textLight;

    Widget? prefix;
    if (prefixIcon != null) {
      final isFocused = focusNode?.hasFocus ?? false;
      prefix = Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isFocused
                ? accent.withValues(alpha: isDark ? 0.22 : 0.12)
                : (isDark
                      ? AppColors.background.backgroundDarkMode
                            .withValues(alpha: 0.5)
                      : Colors.white),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isFocused
                  ? accent.withValues(alpha: isDark ? 0.55 : 0.35)
                  : borderColor.withValues(alpha: isDark ? 0.6 : 0.8),
              width: 1,
            ),
          ),
          child: Icon(
            prefixIcon,
            size: 18,
            color: isFocused ? accent : labelMuted,
          ),
        ),
      );
    }

    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      focusNode: focusNode,
      onFieldSubmitted: onSubmitted,
      textInputAction: textInputAction ??
          (onSubmitted != null ? TextInputAction.next : TextInputAction.done),
      style: GoogleFonts.poppins(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: isDark ? AppColors.text.textDarkMode : AppColors.text.text,
        height: 1.25,
      ),
      cursorColor: accent,
      cursorWidth: 1.5,
      cursorRadius: const Radius.circular(2),
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
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        prefixIcon: prefix,
        prefixIconConstraints: const BoxConstraints(
          minWidth: 56,
          minHeight: 36,
        ),
        suffixIcon: suffixIcon,
        suffixIconConstraints: const BoxConstraints(
          minWidth: 44,
          minHeight: 40,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: AppColors.status.error.withValues(alpha: 0.7),
            width: 1,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
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
        contentPadding: const EdgeInsets.fromLTRB(4, 18, 12, 18),
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
              ? [
                  base.withValues(alpha: 0.7),
                  dark.withValues(alpha: 0.7),
                ]
              : [base, dark],
        ),
        boxShadow: _isLoading
            ? []
            : [
                BoxShadow(
                  color: base.withValues(alpha: isDark ? 0.45 : 0.32),
                  blurRadius: 22,
                  spreadRadius: 0,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: dark.withValues(alpha: isDark ? 0.25 : 0.18),
                  blurRadius: 6,
                  spreadRadius: 0,
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
                  _handleLogin();
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
                        'Entrar',
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

  Widget _buildBiometricButton(bool isDark) {
    final accent = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
    final borderColor = isDark
        ? AppColors.border.borderDarkMode
        : AppColors.border.border;
    final fg = isDark ? AppColors.text.textDarkMode : AppColors.text.text;
    final isFace = _biometricType.contains('Face');

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed:
            _isLoading ? null : () => _handleBiometricLogin(isManual: true),
        style: OutlinedButton.styleFrom(
          elevation: 0,
          foregroundColor: fg,
          backgroundColor: isDark
              ? AppColors.background.backgroundTertiaryDarkMode
                    .withValues(alpha: 0.4)
              : Colors.white,
          side: BorderSide(color: borderColor, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: isDark ? 0.22 : 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                isFace ? Icons.face_rounded : Icons.fingerprint_rounded,
                size: 20,
                color: accent,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Entrar com $_biometricType',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: fg,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

}
