import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/navigation/app_navigator.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../controllers/finance_pin_controller.dart';
import '../services/finance_biometric_service.dart';
import '../services/finance_pin_service.dart';

/// Tela do PIN do Financeiro — criar, digitar, esqueci/código/novo PIN —
/// com teclado numérico próprio (o PIN nunca passa pelo teclado do sistema
/// nem vai para log) e biometria opcional.
///
/// Usada em tela cheia (entrada no módulo) e por cima da tela (expirou ou
/// voltou do segundo plano), sem desmontar o que está embaixo.
class FinancePinView extends StatefulWidget {
  /// Chamado ao sair sem destravar ("Sair do Financeiro").
  final VoidCallback? onExit;

  /// API do PIN (fake nos testes de widget).
  final FinancePinApi? api;

  /// Tenta a biometria sozinha ao abrir na fase "digitar" (se ligada).
  final bool autoBiometric;

  const FinancePinView({
    super.key,
    this.onExit,
    this.api,
    this.autoBiometric = true,
  });

  @override
  State<FinancePinView> createState() => _FinancePinViewState();
}

class _FinancePinViewState extends State<FinancePinView>
    with SingleTickerProviderStateMixin {
  late final FinancePinController _c;
  late final AnimationController _shake;
  Timer? _ticker;
  int _lastErrorTick = 0;
  bool _bioEnabled = false;
  String _bioLabel = 'biometria';
  bool _bioTried = false;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _c = FinancePinController(
      api: widget.api ?? FinancePinService.instance,
      onUnlocked: _onUnlocked,
      onBiometricPinRejected: () {
        unawaited(FinanceBiometricService.instance.disable());
        if (mounted) setState(() => _bioEnabled = false);
      },
    )..addListener(_onChange);
    unawaited(_c.start());
    unawaited(_loadBiometric());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_c.phase == FinancePinPhase.blocked) {
        _c.blockExpired();
        setState(() {});
      }
    });
  }

  Future<void> _loadBiometric() async {
    if (widget.api != null) return; // teste: sem plugin
    final bio = FinanceBiometricService.instance;
    final enabled = await bio.isEnabled() && await bio.isSupported();
    final label = enabled ? await bio.label() : 'biometria';
    if (!mounted) return;
    setState(() {
      _bioEnabled = enabled;
      _bioLabel = label;
    });
    _maybeAutoBiometric();
  }

  void _onChange() {
    if (!mounted) return;
    if (_c.errorTick != _lastErrorTick) {
      _lastErrorTick = _c.errorTick;
      HapticFeedback.heavyImpact();
      _shake.forward(from: 0);
    }
    setState(() {});
    _maybeAutoBiometric();
  }

  void _maybeAutoBiometric() {
    if (!widget.autoBiometric || _bioTried || !_bioEnabled) return;
    if (_c.phase != FinancePinPhase.enter || _c.busy) return;
    _bioTried = true;
    unawaited(_useBiometric());
  }

  Future<void> _useBiometric() async {
    final pin = await FinanceBiometricService.instance.unlockPin();
    if (pin == null || !mounted) return;
    await _c.submitBiometricPin(pin);
  }

  /// Destravou (o token já está no store e o portão vai trocar de tela):
  /// oferta/atualização da biometria pelo navigator raiz.
  void _onUnlocked(String pin, FinanceUnlockMethod method) {
    if (widget.api != null || method == FinanceUnlockMethod.biometric) return;
    unawaited(_afterUnlock(pin, method));
  }

  static Future<void> _afterUnlock(
    String pin,
    FinanceUnlockMethod method,
  ) async {
    final bio = FinanceBiometricService.instance;
    if (await bio.isEnabled()) {
      // Redefiniu o PIN: o guardado tem de acompanhar.
      if (method == FinanceUnlockMethod.reset) await bio.updateIfEnabled(pin);
      return;
    }
    if (await bio.wasDeclined() || !await bio.isSupported()) return;
    final label = await bio.label();
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final aceitou = await offerFinanceBiometric(ctx, label: label);
    if (aceitou == true) {
      final ok = await bio.enable(pin);
      final c = appNavigatorKey.currentContext;
      if (c != null && c.mounted) {
        ScaffoldMessenger.of(c).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              ok
                  ? 'Pronto: da próxima vez, destrave com $label.'
                  : 'Não deu para ligar a biometria agora.',
            ),
          ),
        );
      }
    } else if (aceitou == false) {
      await bio.setDeclined();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _c.removeListener(_onChange);
    _c.dispose();
    _shake.dispose();
    super.dispose();
  }

  // ─── Textos por fase ────────────────────────────────────────────────────

  String get _title {
    switch (_c.phase) {
      case FinancePinPhase.loading:
        return 'Abrindo o Financeiro';
      case FinancePinPhase.loadError:
        return 'Não deu para abrir o Financeiro';
      case FinancePinPhase.create:
        return 'Crie seu PIN do Financeiro';
      case FinancePinPhase.confirmCreate:
        return 'Confirme o PIN';
      case FinancePinPhase.enter:
        return 'Digite seu PIN';
      case FinancePinPhase.blocked:
        return 'PIN bloqueado';
      case FinancePinPhase.code:
        return 'Código do e-mail';
      case FinancePinPhase.newPin:
        return 'Crie o novo PIN';
      case FinancePinPhase.confirmNewPin:
        return 'Confirme o novo PIN';
    }
  }

  String get _subtitle {
    switch (_c.phase) {
      case FinancePinPhase.loading:
        return 'Conferindo seu acesso…';
      case FinancePinPhase.loadError:
        return _c.error ?? 'Verifique a internet e tente de novo.';
      case FinancePinPhase.create:
        return '4 números só seus. Ele protege seus valores e é pedido sempre '
            'que você volta ao app.';
      case FinancePinPhase.confirmCreate:
        return 'Digite o mesmo PIN mais uma vez.';
      case FinancePinPhase.enter:
        return 'Seus valores ficam protegidos por um PIN pessoal.';
      case FinancePinPhase.blocked:
        final r = _c.blockedRemaining;
        final mm = r.inMinutes.toString().padLeft(2, '0');
        final ss = (r.inSeconds % 60).toString().padLeft(2, '0');
        return 'Muitas tentativas erradas. Tente de novo em $mm:$ss, ou '
            'redefina pelo e-mail.';
      case FinancePinPhase.code:
        return 'Digite os 6 números que enviamos para '
            '${_c.enviadoPara ?? 'seu e-mail'}.';
      case FinancePinPhase.newPin:
        return 'Evite sequências (1234) e números repetidos (1111).';
      case FinancePinPhase.confirmNewPin:
        return 'Digite o novo PIN mais uma vez.';
    }
  }

  IconData get _icon {
    switch (_c.phase) {
      case FinancePinPhase.blocked:
        return LucideIcons.timer;
      case FinancePinPhase.code:
        return LucideIcons.mailCheck;
      case FinancePinPhase.loadError:
        return LucideIcons.cloudOff;
      case FinancePinPhase.create:
      case FinancePinPhase.confirmCreate:
      case FinancePinPhase.newPin:
      case FinancePinPhase.confirmNewPin:
        return LucideIcons.keyRound;
      case FinancePinPhase.loading:
      case FinancePinPhase.enter:
        return LucideIcons.lock;
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
    final text = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final showKeypad = _c.acceptsDigits || _c.busy;

    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: ThemeHelpers.shellBackgroundDecoration(context),
        child: Stack(
          children: [
            Positioned(
              top: -140,
              right: -110,
              child: _Glow(color: accent.withValues(alpha: 0.16), size: 340),
            ),
            Positioned(
              bottom: -160,
              left: -120,
              child: _Glow(color: accent.withValues(alpha: 0.08), size: 320),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, box) {
                  final compact = box.maxHeight < 640;
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          children: [
                            _topBar(context, secondary),
                            Expanded(
                              child: SingleChildScrollView(
                                physics: const ClampingScrollPhysics(),
                                child: Column(
                                  children: [
                                    SizedBox(height: compact ? 4 : 18),
                                    _badge(accent, compact),
                                    SizedBox(height: compact ? 14 : 22),
                                    Text(
                                      _title,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.4,
                                        color: text,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _subtitle,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 14,
                                        height: 1.4,
                                        color: secondary,
                                      ),
                                    ),
                                    SizedBox(height: compact ? 18 : 28),
                                    if (_c.phase == FinancePinPhase.loading)
                                      Padding(
                                        padding: const EdgeInsets.all(24),
                                        child: CircularProgressIndicator(
                                          color: accent,
                                          strokeWidth: 2.6,
                                        ),
                                      )
                                    else if (_c.phase ==
                                        FinancePinPhase.loadError)
                                      FilledButton.icon(
                                        onPressed: () => _c.start(),
                                        icon: const Icon(
                                          LucideIcons.refreshCw,
                                          size: 18,
                                        ),
                                        label: const Text('Tentar de novo'),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: accent,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 22,
                                            vertical: 14,
                                          ),
                                        ),
                                      )
                                    else if (_c.phase !=
                                        FinancePinPhase.blocked)
                                      _dots(accent, text),
                                    const SizedBox(height: 14),
                                    _messages(accent),
                                  ],
                                ),
                              ),
                            ),
                            if (showKeypad) ...[
                              _Keypad(
                                compact: compact,
                                enabled: _c.acceptsDigits,
                                accent: accent,
                                biometricIcon:
                                    _bioEnabled &&
                                        _c.phase == FinancePinPhase.enter
                                    ? (_bioLabel == 'Face ID'
                                          ? LucideIcons.scanFace
                                          : LucideIcons.fingerprint)
                                    : null,
                                biometricLabel: 'Destravar com $_bioLabel',
                                onBiometric: _useBiometric,
                                onDigit: (d) {
                                  HapticFeedback.selectionClick();
                                  _c.addDigit(d);
                                },
                                onBackspace: () {
                                  HapticFeedback.selectionClick();
                                  _c.backspace();
                                },
                              ),
                            ],
                            _bottomLinks(accent, secondary),
                            SizedBox(height: compact ? 6 : 14),
                          ],
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
    );
  }

  Widget _topBar(BuildContext context, Color secondary) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          if (widget.onExit != null)
            Flexible(
              child: TextButton.icon(
                onPressed: _c.busy ? null : widget.onExit,
                icon: Icon(LucideIcons.arrowLeft, size: 18, color: secondary),
                label: Text(
                  'Sair do Financeiro',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          const Spacer(),
          if (MediaQuery.sizeOf(context).width >= 340)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: ThemeHelpers.borderLightColor(context),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.shieldCheck, size: 14, color: secondary),
                  const SizedBox(width: 6),
                  Text(
                    'Área protegida',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: secondary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _badge(Color accent, bool compact) {
    final size = compact ? 64.0 : 78.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, Color.lerp(accent, Colors.black, 0.35)!],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.32),
            blurRadius: 26,
            offset: const Offset(0, 12),
            spreadRadius: -6,
          ),
        ],
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: Icon(
          _icon,
          key: ValueKey(_icon),
          color: Colors.white,
          size: size * 0.42,
        ),
      ),
    );
  }

  Widget _dots(Color accent, Color text) {
    final n = _c.length;
    final filled = _c.buffer.length;
    final error = _c.error != null;
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        final t = _shake.value;
        final dx = math.sin(t * math.pi * 6) * 10 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < n; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              margin: EdgeInsets.symmetric(horizontal: n > 4 ? 7 : 11),
              width: i < filled ? 18 : 16,
              height: i < filled ? 18 : 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < filled
                    ? (error ? AppColors.status.error : accent)
                    : Colors.transparent,
                border: Border.all(
                  width: 2,
                  color: error
                      ? AppColors.status.error
                      : (i < filled ? accent : text.withValues(alpha: 0.28)),
                ),
              ),
            ),
          if (_c.busy) ...[
            const SizedBox(width: 6),
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: accent),
            ),
          ],
        ],
      ),
    );
  }

  Widget _messages(Color accent) {
    final error = _c.error;
    final info = _c.info;
    if (_c.phase == FinancePinPhase.loadError) return const SizedBox.shrink();
    final text = error ?? info;
    if (text == null) return const SizedBox(height: 20);
    final color = error != null ? AppColors.status.error : accent;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Container(
        key: ValueKey(text),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              error != null ? LucideIcons.circleAlert : LucideIcons.info,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomLinks(Color accent, Color secondary) {
    final phase = _c.phase;
    final emEsqueci =
        phase == FinancePinPhase.code ||
        phase == FinancePinPhase.newPin ||
        phase == FinancePinPhase.confirmNewPin;
    if (phase == FinancePinPhase.enter || phase == FinancePinPhase.blocked) {
      return TextButton(
        onPressed: _c.busy ? null : _c.forgot,
        child: Text(
          'Esqueci meu PIN',
          style: TextStyle(color: accent, fontWeight: FontWeight.w700),
        ),
      );
    }
    if (emEsqueci) {
      return Wrap(
        alignment: WrapAlignment.center,
        children: [
          if (phase == FinancePinPhase.code)
            TextButton(
              onPressed: _c.busy ? null : _c.forgot,
              child: Text(
                'Reenviar código',
                style: TextStyle(color: accent, fontWeight: FontWeight.w700),
              ),
            ),
          TextButton(
            onPressed: _c.busy ? null : _c.backToEnter,
            child: Text(
              'Lembrei o PIN',
              style: TextStyle(color: secondary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    }
    return const SizedBox(height: 48);
  }
}

/// Convite para ligar a biometria (opt-in). `true` = ligar, `false` =
/// agora não (não pergunta de novo), `null` = fechou.
Future<bool?> offerFinanceBiometric(
  BuildContext context, {
  required String label,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final accent = isDark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;
  return showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    backgroundColor: ThemeHelpers.cardBackgroundColor(context),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                label == 'Face ID'
                    ? LucideIcons.scanFace
                    : LucideIcons.fingerprint,
                color: accent,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Destravar o Financeiro com $label?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: ThemeHelpers.textColor(ctx),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Seu PIN fica guardado com segurança neste aparelho e a $label '
              'só o libera. Dá para desligar quando quiser no seu perfil.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: ThemeHelpers.textSecondaryColor(ctx),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text('Usar $label'),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Agora não'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Keypad extends StatelessWidget {
  final bool compact;
  final bool enabled;
  final Color accent;
  final IconData? biometricIcon;
  final String biometricLabel;
  final VoidCallback onBiometric;
  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;

  const _Keypad({
    required this.compact,
    required this.enabled,
    required this.accent,
    required this.biometricIcon,
    required this.biometricLabel,
    required this.onBiometric,
    required this.onDigit,
    required this.onBackspace,
  });

  @override
  Widget build(BuildContext context) {
    final rows = const [
      [1, 2, 3],
      [4, 5, 6],
      [7, 8, 9],
    ];
    final gap = compact ? 10.0 : 14.0;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in rows) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final d in row) ...[
                  _Key(
                    compact: compact,
                    label: '$d',
                    onTap: enabled ? () => onDigit(d) : null,
                  ),
                  if (d != row.last) SizedBox(width: gap * 1.8),
                ],
              ],
            ),
            SizedBox(height: gap),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              biometricIcon == null
                  ? _Key.blank(compact: compact)
                  : _Key(
                      compact: compact,
                      icon: biometricIcon,
                      iconColor: accent,
                      semantics: biometricLabel,
                      onTap: enabled ? onBiometric : null,
                      ghost: true,
                    ),
              SizedBox(width: gap * 1.8),
              _Key(
                compact: compact,
                label: '0',
                onTap: enabled ? () => onDigit(0) : null,
              ),
              SizedBox(width: gap * 1.8),
              _Key(
                compact: compact,
                icon: LucideIcons.delete,
                semantics: 'Apagar',
                onTap: enabled ? onBackspace : null,
                ghost: true,
              ),
            ],
          ),
          SizedBox(height: gap * 0.6),
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  final bool compact;
  final String? label;
  final IconData? icon;
  final Color? iconColor;
  final String? semantics;
  final VoidCallback? onTap;
  final bool ghost;
  final bool blank;

  const _Key({
    required this.compact,
    this.label,
    this.icon,
    this.iconColor,
    this.semantics,
    this.onTap,
    this.ghost = false,
  }) : blank = false;

  const _Key.blank({required this.compact})
    : label = null,
      icon = null,
      iconColor = null,
      semantics = null,
      onTap = null,
      ghost = true,
      blank = true;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 62.0 : 72.0;
    if (blank) return SizedBox(width: size, height: size);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = ThemeHelpers.textColor(context);
    final fill = ghost
        ? Colors.transparent
        : (isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFF2F4F7));
    return Semantics(
      button: true,
      label: semantics ?? label,
      child: Material(
        color: fill,
        shape: CircleBorder(
          side: ghost
              ? BorderSide.none
              : BorderSide(
                  color: ThemeHelpers.borderLightColor(
                    context,
                  ).withValues(alpha: isDark ? 0.9 : 0.7),
                ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: label != null
                  ? Text(
                      label!,
                      style: TextStyle(
                        fontSize: compact ? 24 : 27,
                        fontWeight: FontWeight.w600,
                        color: text,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    )
                  : Icon(icon, size: 26, color: iconColor ?? text),
            ),
          ),
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  final Color color;
  final double size;

  const _Glow({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}
