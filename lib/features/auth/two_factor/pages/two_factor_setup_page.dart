import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/notifications/app_toast.dart';
import '../../../../core/push/app_push_service.dart';
import '../../../../core/session/session_bootstrap.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/auth_service.dart';
import '../../../../shared/services/biometric_service.dart';
import '../../../../shared/services/login_flow_service.dart';
import '../../../../shared/widgets/skeleton_box.dart';
import '../../login/widgets/biometric_enrollment_dialog.dart';
import '../services/two_factor_setup_service.dart';

/// Configuração de 2FA antes do login — paridade com o TwoFactorSetupModal
/// do web. Aberta quando a empresa exige 2FA e o usuário ainda não
/// configurou (check-2fa: requires2FA && !hasTwoFactorConfigured, ou o
/// login devolve 2FA_SETUP_REQUIRED).
///
/// Fluxo (igual ao useAuth.mfaSetup do web):
///   1. POST /auth/2fa/setup {email, password} → QR + segredo;
///   2. POST /auth/2fa/verify-setup {email, password, code} → enabled;
///   3. login de novo → 401 2FA_REQUIRED com tempToken;
///   4. POST /auth/verify-2fa {tempToken, code} → sessão, e segue o fluxo
///      normal pós-login (empresa, permissões, push, biometria).
class TwoFactorSetupPage extends StatefulWidget {
  final String email;
  final String password;
  final bool rememberMe;

  const TwoFactorSetupPage({
    super.key,
    required this.email,
    required this.password,
    this.rememberMe = false,
  });

  @override
  State<TwoFactorSetupPage> createState() => _TwoFactorSetupPageState();
}

class _TwoFactorSetupPageState extends State<TwoFactorSetupPage> {
  final _codeController = TextEditingController();

  bool _loading = true;
  bool _verifying = false;
  bool _copied = false;
  String? _loadError;
  String? _error;
  String _secret = '';
  Uint8List? _qrBytes;

  @override
  void initState() {
    super.initState();
    _codeController.addListener(() => setState(() {}));
    _start();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final res = await TwoFactorSetupService.instance.startSetup(
      email: widget.email,
      password: widget.password,
    );
    if (!mounted) return;
    if (res.success && res.data != null) {
      setState(() {
        _secret = res.data!.secret;
        _qrBytes = _decodeDataUrl(res.data!.qrCodeDataUrl);
        _loading = false;
      });
    } else {
      setState(() {
        _loadError = res.message ?? 'Falha ao iniciar configuração do 2FA.';
        _loading = false;
      });
    }
  }

  /// `data:image/png;base64,XXXX` → bytes. Nulo quando não for data URL.
  Uint8List? _decodeDataUrl(String dataUrl) {
    if (dataUrl.isEmpty) return null;
    final comma = dataUrl.indexOf(',');
    final b64 = comma >= 0 ? dataUrl.substring(comma + 1) : dataUrl;
    try {
      return base64Decode(b64.trim());
    } catch (_) {
      return null;
    }
  }

  Future<void> _copySecret() async {
    if (_secret.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _secret));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _activate() async {
    final code = _codeController.text;
    if (code.length != 6 || _verifying) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _verifying = true;
      _error = null;
    });

    try {
      // 1) Verifica e ativa o 2FA.
      final verify = await TwoFactorSetupService.instance.verifySetup(
        email: widget.email,
        password: widget.password,
        code: code,
      );
      if (!verify.success) {
        _fail(verify.message ?? 'Não foi possível verificar o código.');
        return;
      }
      if (verify.data != true) {
        _fail('Código inválido. Tente novamente.');
        return;
      }

      // 2) Login de novo para obter o tempToken (agora o 2FA é exigido).
      final auth = AuthService.instance;
      final login = await auth.login(
        LoginRequest(email: widget.email, password: widget.password),
      );
      LoginResponse? session;
      if (login.success && login.data != null) {
        session = login.data;
      } else {
        final err = login.error;
        final errorCode = err is Map ? err['errorCode']?.toString() : null;
        final tempToken = err is Map ? err['tempToken']?.toString() ?? '' : '';
        if (errorCode == '2FA_REQUIRED' && tempToken.isNotEmpty) {
          // 3) Mesmo código TOTP conclui o login, como no web.
          final verified = await auth.verify2FA(
            tempToken: tempToken,
            code: code,
          );
          if (verified.success && verified.data != null) {
            session = verified.data;
          } else {
            _fail(verified.message ?? 'Código inválido. Tente novamente.');
            return;
          }
        }
      }
      if (session == null) {
        _fail('Falha ao iniciar verificação 2FA após ativação.');
        return;
      }
      if (!mounted) return;

      // 4) Fluxo normal pós-login.
      final result = await LoginFlowService.instance.executeAfter2FA(
        loginResponse: session,
        rememberMe: widget.rememberMe,
        context: context,
      );
      if (!result.success || result.route == null) {
        _fail(result.message);
        return;
      }

      await SessionBootstrap.instance.ensureReady(
        timeout: const Duration(seconds: 8),
      );
      if (!mounted) return;
      AppToast.success(context, '2FA ativado com sucesso!');

      try {
        await AppPushService.instance
            .syncWithBackendIfAuthenticated()
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('[2FA_SETUP] Falha ao sincronizar permissões push: $e');
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
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(result.route!, (route) => false);
      }
    } catch (e) {
      _fail('Falha ao concluir configuração de 2FA.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _verifying = false;
    });
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final brand = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
    final text = ThemeHelpers.textColor(context);
    final textSec = ThemeHelpers.textSecondaryColor(context);
    final divider = ThemeHelpers.borderLightColor(context);

    return Scaffold(
      backgroundColor: ThemeHelpers.backgroundColor(context),
      appBar: AppBar(
        backgroundColor: ThemeHelpers.backgroundColor(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: text,
        leading: IconButton(
          tooltip: 'Voltar',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _verifying ? null : () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Masthead
              Text(
                'SEGURANÇA DA CONTA',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: brand,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Configurar 2FA',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: text,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Sua empresa exige a verificação em duas etapas. '
                'Ative agora para entrar.',
                style: theme.textTheme.bodyMedium?.copyWith(color: textSec),
              ),
              const SizedBox(height: 20),
              Divider(height: 1, color: divider),
              const SizedBox(height: 20),

              if (_loadError != null)
                _buildLoadError(theme, text, textSec, brand)
              else ...[
                _buildSteps(theme, text, textSec, brand),
                const SizedBox(height: 20),
                _buildQr(theme, text, textSec),
                const SizedBox(height: 20),
                _buildSecret(theme, text, textSec, brand, isDark),
                const SizedBox(height: 20),
                Divider(height: 1, color: divider),
                const SizedBox(height: 20),
                _buildCodeField(theme, text, textSec, brand, isDark),
                const SizedBox(height: 20),
                _buildActions(theme, isDark),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSteps(ThemeData theme, Color text, Color textSec, Color brand) {
    Widget step(String n, String label) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: brand.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Text(
                n,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: brand,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(color: text),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        step(
          '1',
          'Abra seu aplicativo autenticador (Google Authenticator, Authy, '
              'etc.) e adicione a conta escaneando o QR Code.',
        ),
        step(
          '2',
          'Digite abaixo o código de 6 dígitos para concluir a ativação.',
        ),
      ],
    );
  }

  Widget _buildQr(ThemeData theme, Color text, Color textSec) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(theme, 'QR Code', 'Escaneie no seu app autenticador',
            text, textSec),
        const SizedBox(height: 12),
        Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.maxWidth < 220
                  ? constraints.maxWidth
                  : 220.0;
              if (_loading) {
                return SkeletonBox(
                  width: size,
                  height: size,
                  borderRadius: 12,
                );
              }
              // Fundo SEMPRE branco: QR escuro sobre claro, também no
              // dark mode, senão o leitor do autenticador falha.
              return Container(
                width: size,
                height: size,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: ThemeHelpers.borderColor(context),
                  ),
                ),
                child: _qrBytes != null
                    ? Image.memory(
                        _qrBytes!,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        semanticLabel: 'QR Code 2FA',
                      )
                    : Center(
                        child: Text(
                          'QR Code indisponível. Use a chave secreta.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.text.textSecondary,
                          ),
                        ),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSecret(
    ThemeData theme,
    Color text,
    Color textSec,
    Color brand,
    bool isDark,
  ) {
    final fill = isDark
        ? AppColors.background.backgroundSecondaryDarkMode
        : AppColors.background.backgroundSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          theme,
          'Chave secreta',
          'Use se não conseguir escanear o QR Code',
          text,
          textSec,
        ),
        const SizedBox(height: 10),
        if (_loading)
          const SkeletonBox(height: 48, borderRadius: 10)
        else
          Container(
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    _secret,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: text,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                TextButton.icon(
                  onPressed: _secret.isEmpty ? null : _copySecret,
                  style: TextButton.styleFrom(foregroundColor: brand),
                  icon: Icon(
                    _copied ? Icons.check_rounded : Icons.copy_rounded,
                    size: 18,
                  ),
                  label: Text(_copied ? 'Copiado!' : 'Copiar'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCodeField(
    ThemeData theme,
    Color text,
    Color textSec,
    Color brand,
    bool isDark,
  ) {
    final fill = isDark
        ? AppColors.background.backgroundSecondaryDarkMode
        : AppColors.background.backgroundSecondary;
    final errorColor = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(theme, 'Código TOTP', null, text, textSec),
        const SizedBox(height: 10),
        TextField(
          controller: _codeController,
          enabled: !_loading && !_verifying,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (_) => _activate(),
          style: theme.textTheme.titleLarge?.copyWith(
            color: text,
            fontWeight: FontWeight.w800,
            letterSpacing: 8,
          ),
          decoration: InputDecoration(
            hintText: '000000',
            hintStyle: theme.textTheme.titleLarge?.copyWith(
              color: textSec.withValues(alpha: 0.5),
              letterSpacing: 8,
            ),
            counterText: '',
            filled: true,
            fillColor: fill,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: brand, width: 1.5),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: errorColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActions(ThemeData theme, bool isDark) {
    final green = isDark
        ? AppColors.status.successDarkMode
        : AppColors.status.success;
    final canActivate =
        !_loading && !_verifying && _codeController.text.length == 6;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: canActivate ? _activate : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: green,
              foregroundColor: Colors.white,
              disabledBackgroundColor: green.withValues(alpha: 0.35),
              disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _verifying ? 'Ativando e entrando...' : 'Ativar 2FA',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 46,
          child: OutlinedButton(
            onPressed: _verifying ? null : () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: ThemeHelpers.textColor(context),
              side: BorderSide(color: ThemeHelpers.borderColor(context)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Voltar'),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadError(
    ThemeData theme,
    Color text,
    Color textSec,
    Color brand,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Não foi possível gerar o QR Code',
          style: theme.textTheme.titleMedium?.copyWith(
            color: text,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _loadError ?? '',
          style: theme.textTheme.bodyMedium?.copyWith(color: textSec),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ElevatedButton(
              onPressed: _start,
              style: ElevatedButton.styleFrom(
                backgroundColor: brand,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              child: const Text('Tentar novamente'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: ThemeHelpers.textColor(context),
                side: BorderSide(color: ThemeHelpers.borderColor(context)),
              ),
              child: const Text('Voltar'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sectionTitle(
    ThemeData theme,
    String title,
    String? subtitle,
    Color text,
    Color textSec,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: text,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(color: textSec),
          ),
        ],
      ],
    );
  }
}
