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
import '../widgets/two_factor_code_input.dart';

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
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          child: Center(
            child: ConstrainedBox(
              // Tablet: o roteiro não estica em 1000dp.
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildMasthead(theme, text, textSec, brand, isDark),
                  const SizedBox(height: 20),
                  Divider(height: 1, color: divider),
                  const SizedBox(height: 20),
                  if (_loadError != null)
                    _buildLoadError(theme, text, textSec, brand, isDark)
                  else ...[
                    _buildStep(
                      theme: theme,
                      number: '1',
                      title: 'Adicione a conta no autenticador',
                      subtitle: 'No Google Authenticator, Authy ou outro app '
                          'autenticador, escaneie o QR Code.',
                      brand: brand,
                      text: text,
                      textSec: textSec,
                      divider: divider,
                      done: false,
                      last: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildQr(theme, textSec),
                          const SizedBox(height: 16),
                          _buildSecret(theme, text, textSec, brand, isDark),
                        ],
                      ),
                    ),
                    _buildStep(
                      theme: theme,
                      number: '2',
                      title: 'Digite o código gerado',
                      subtitle: 'O app mostra 6 dígitos que mudam a cada '
                          '30 segundos.',
                      brand: brand,
                      text: text,
                      textSec: textSec,
                      divider: divider,
                      done: _codeController.text.length == 6,
                      last: true,
                      child: _buildCodeField(theme, textSec, brand, isDark),
                    ),
                    const SizedBox(height: 24),
                    _buildActions(theme, isDark),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Abertura: selo de segurança + o porquê (empresa exige) + a conta.
  Widget _buildMasthead(
    ThemeData theme,
    Color text,
    Color textSec,
    Color brand,
    bool isDark,
  ) {
    final email = widget.email.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: brand.withValues(alpha: isDark ? 0.18 : 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.verified_user_outlined, color: brand, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Ative a verificação em duas etapas',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: text,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Sua empresa exige esta proteção para entrar. Leva menos de um '
          'minuto: escaneie o QR Code e confirme com o código.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: textSec,
            height: 1.4,
          ),
        ),
        if (email.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.person_outline_rounded, size: 16, color: textSec),
              const SizedBox(width: 6),
              Text(
                'Conta ',
                style: theme.textTheme.bodySmall?.copyWith(color: textSec),
              ),
              Expanded(
                child: Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Passo numerado com trilho à esquerda ligando ao próximo — o conteúdo
  /// (QR, chave, código) mora DENTRO do passo que ele resolve.
  Widget _buildStep({
    required ThemeData theme,
    required String number,
    required String title,
    required String subtitle,
    required Color brand,
    required Color text,
    required Color textSec,
    required Color divider,
    required bool done,
    required bool last,
    required Widget child,
  }) {
    final green = theme.brightness == Brightness.dark
        ? AppColors.status.successDarkMode
        : AppColors.status.success;
    final badgeColor = done ? green : brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.14),
                shape: BoxShape.circle,
                border: Border.all(color: badgeColor, width: 1.2),
              ),
              child: done
                  ? Icon(Icons.check_rounded, size: 15, color: badgeColor)
                  : Text(
                      number,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: badgeColor,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: text,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: textSec,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Container(
          // Trilho alinhado ao centro do número (26/2 - 1).
          margin: const EdgeInsets.only(left: 12),
          padding: EdgeInsets.fromLTRB(24, 14, 0, last ? 0 : 24),
          decoration: BoxDecoration(
            border: last
                ? null
                : Border(left: BorderSide(color: divider, width: 2)),
          ),
          child: child,
        ),
      ],
    );
  }

  Widget _buildQr(ThemeData theme, Color textSec) {
    return Center(
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
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        'QR Code indisponível. Use a chave abaixo.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          // Fundo branco fixo: texto do tema claro.
                          color: AppColors.text.textSecondary,
                        ),
                      ),
                    ),
                  ),
          );
        },
      ),
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
        Text(
          'Não consegue escanear? Digite esta chave no app:',
          style: theme.textTheme.bodySmall?.copyWith(
            color: textSec,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        if (_loading)
          const SkeletonBox(height: 48, borderRadius: 10)
        else
          Container(
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ThemeHelpers.borderLightColor(context)),
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
                  style: TextButton.styleFrom(
                    foregroundColor: _copied
                        ? (isDark
                              ? AppColors.status.successDarkMode
                              : AppColors.status.success)
                        : brand,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 40),
                  ),
                  icon: Icon(
                    _copied ? Icons.check_rounded : Icons.copy_rounded,
                    size: 18,
                  ),
                  label: Text(
                    _copied ? 'Copiada' : 'Copiar',
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCodeField(
    ThemeData theme,
    Color textSec,
    Color brand,
    bool isDark,
  ) {
    final errorColor = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TwoFactorCodeInput(
          controller: _codeController,
          enabled: !_loading && !_verifying,
          hasError: _error != null,
          onSubmitted: (_) => _activate(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline_rounded, size: 16, color: errorColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: errorColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
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
          child: ElevatedButton.icon(
            onPressed: canActivate ? _activate : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: green,
              foregroundColor: Colors.white,
              disabledBackgroundColor: green.withValues(alpha: 0.35),
              disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: _verifying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.lock_open_rounded, size: 20),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _verifying ? 'Ativando e entrando...' : 'Ativar e entrar',
                maxLines: 1,
                softWrap: false,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        if (!canActivate && !_verifying && !_loading) ...[
          const SizedBox(height: 8),
          Text(
            'Digite os 6 dígitos para liberar a ativação.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          height: 46,
          child: OutlinedButton(
            onPressed: _verifying ? null : () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: ThemeHelpers.textColor(context),
              side: BorderSide(color: ThemeHelpers.borderColor(context)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Voltar para o login'),
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
    bool isDark,
  ) {
    final errorColor = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, color: errorColor, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Não foi possível gerar o QR Code',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: text,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 32),
          child: Text(
            _loadError ?? '',
            style: theme.textTheme.bodyMedium?.copyWith(color: textSec),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ElevatedButton.icon(
              onPressed: _start,
              style: ElevatedButton.styleFrom(
                backgroundColor: brand,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Tentar de novo'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: ThemeHelpers.textColor(context),
                side: BorderSide(color: ThemeHelpers.borderColor(context)),
              ),
              child: const Text('Voltar para o login'),
            ),
          ],
        ),
      ],
    );
  }
}
