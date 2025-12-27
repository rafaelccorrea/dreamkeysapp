import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../shared/services/auth_service.dart';
import '../../../../../shared/services/login_flow_service.dart';
import '../../../../../shared/services/secure_storage_service.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../shared/widgets/image_curve_clipper.dart';
import '../../../../../shared/widgets/loading_overlay.dart';

class TwoFactorPage extends StatefulWidget {
  final String email;
  final String password;
  final String tempToken;
  final bool rememberMe;

  const TwoFactorPage({
    super.key,
    required this.email,
    required this.password,
    required this.tempToken,
    required this.rememberMe,
  });

  @override
  State<TwoFactorPage> createState() => _TwoFactorPageState();
}

class _TwoFactorPageState extends State<TwoFactorPage> {
  final _formKey = GlobalKey<FormState>();
  final List<TextEditingController> _codeControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _isLoading = false;

  @override
  void dispose() {
    for (var controller in _codeControllers) {
      controller.dispose();
    }
    for (var focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  void _onCodeChanged(int index, String value) {
    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }

    // Verificar se todos os campos estão preenchidos
    final allFilled = _codeControllers.every((c) => c.text.isNotEmpty);
    if (allFilled) {
      _verifyCode();
    }
  }

  Future<void> _verifyCode() async {
    if (!_formKey.currentState!.validate()) return;

    final code = _codeControllers.map((c) => c.text).join();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Por favor, preencha todos os dígitos'),
          backgroundColor: AppColors.status.error,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                response.message ?? 'Código inválido. Tente novamente.',
              ),
              backgroundColor: AppColors.status.error,
            ),
          );
          // Limpar campos
          for (var controller in _codeControllers) {
            controller.clear();
          }
          _focusNodes[0].requestFocus();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao verificar código: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleAuthSuccess(LoginResponse loginResponse, String code) async {
    try {
      // Continuar com o fluxo completo de inicialização
      final loginFlowService = LoginFlowService.instance;
      final result = await loginFlowService.executeAfter2FA(
        loginResponse: loginResponse,
        rememberMe: widget.rememberMe,
        context: context,
      );

      if (result.success && result.route != null) {
        // Salvar credenciais se solicitado
        if (widget.rememberMe) {
          await SecureStorageService.instance.saveCredentials(
            email: widget.email,
            password: widget.password,
          );
        }

        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil(
            result.route!,
            (route) => false,
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.message),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao processar login: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: _isLoading,
      child: Scaffold(
        backgroundColor: AppColors.background.background,
        body: SafeArea(
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  // Header com curva
                  ClipPath(
                    clipper: ImageCurveClipper(),
                    child: Container(
                      height: 200,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.primary.primary,
                            AppColors.primary.primary.withOpacity(0.8),
                          ],
                        ),
                      ),
                      child: Center(
                      child: const Icon(
                        Icons.security,
                        size: 64,
                        color: Colors.white,
                      ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Título
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Autenticação de Dois Fatores',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.text.text,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Descrição
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Digite o código de 6 dígitos do seu aplicativo autenticador',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.text.textSecondary,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Campos de código
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(6, (index) {
                        return SizedBox(
                          width: 45,
                          child: TextFormField(
                            controller: _codeControllers[index],
                            focusNode: _focusNodes[index],
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            maxLength: 1,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.text.text,
                                ),
                            decoration: InputDecoration(
                              counterText: '',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: AppColors.border.border,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: AppColors.border.border,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: AppColors.primary.primary,
                                  width: 2,
                                ),
                              ),
                              filled: true,
                              fillColor: AppColors.background.backgroundSecondary,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            onChanged: (value) => _onCodeChanged(index, value),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return '';
                              }
                              return null;
                            },
                          ),
                        );
                      }),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Botão de verificar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _verifyCode,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Verificar',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Botão de voltar
                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(
                      'Voltar',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.primary.primary,
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
}

