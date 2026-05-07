import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../navigation/app_navigator.dart';
import '../theme/app_colors.dart';

/// Toasts limpos no padrão moderno (estilo Linear/Vercel/Notion):
/// pill compacta no rodapé, sem ruído visual.
///
/// O design anterior tinha **muito** elemento competindo por atenção em
/// cada toast: faixa accent vertical, ícone-plate quadrado de 46px, label
/// uppercase tipo "CONFIRMADO/INTELLISYS", barra de countdown progressiva
/// e ainda um ícone de swipe-down. Para um aviso passageiro de 3 segundos
/// isso é overkill — o toast é justamente algo que não deve dominar a
/// tela. Esta reescrita reduz ao essencial:
///
/// - **Posição**: rodapé (mais discreto que topo, padrão moderno).
/// - **Forma**: pill compacta com fundo escuro/claro adaptativo, borda
///   sutil e sombra leve com tint do accent.
/// - **Conteúdo**: ícone circular compacto (28px) + mensagem em uma linha
///   peso 600 + subtítulo opcional menor.
/// - **Sem ruído**: sem labels uppercase, sem barra de countdown visível,
///   sem hint de swipe — o usuário descobre por instinto que pode tocar
///   ou arrastar pra fechar.
/// - **Animação**: slide-up + fade (entrada) e slide-down + fade (saída).
///
/// API pública mantida igual: `AppToast.success/error/warning/info` e
/// extension `context.showToast(...)`. Quem chamava antes não muda nada.
enum AppToastKind {
  success,
  error,
  warning,
  info,
}

class AppToast {
  AppToast._();

  static OverlayEntry? _entry;

  /// Remove o toast atual, se houver.
  static void dismiss() {
    _entry?.remove();
    _entry = null;
  }

  static void show(
    BuildContext context, {
    required String message,
    AppToastKind kind = AppToastKind.info,
    String? subtitle,
    Duration duration = const Duration(milliseconds: 3200),
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final overlay =
        Overlay.maybeOf(context) ?? appNavigatorKey.currentState?.overlay;
    if (overlay == null) return;

    dismiss();

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _ToastLayer(
        theme: theme,
        message: message,
        subtitle: subtitle,
        kind: kind,
        duration: duration,
        onTap: onTap,
        onDispose: () {
          entry.remove();
          if (_entry == entry) _entry = null;
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  static void success(BuildContext context, String message, {String? subtitle}) =>
      show(context, message: message, kind: AppToastKind.success, subtitle: subtitle);

  static void error(BuildContext context, String message, {String? subtitle}) =>
      show(context, message: message, kind: AppToastKind.error, subtitle: subtitle);

  static void warning(BuildContext context, String message, {String? subtitle}) =>
      show(context, message: message, kind: AppToastKind.warning, subtitle: subtitle);

  static void info(BuildContext context, String message, {String? subtitle}) =>
      show(context, message: message, kind: AppToastKind.info, subtitle: subtitle);
}

extension AppToastBuildContext on BuildContext {
  void showToast(
    String message, {
    AppToastKind kind = AppToastKind.info,
    String? subtitle,
    Duration duration = const Duration(milliseconds: 3200),
  }) {
    AppToast.show(
      this,
      message: message,
      kind: kind,
      subtitle: subtitle,
      duration: duration,
    );
  }
}

// ───────────────────────────────────────────────────────────────────────
// Estilos por tipo. Cada tipo tem **um** accent — a paleta do toast em
// si é neutra (escuro no dark / claro no light) pra não competir com o
// app por atenção. Só o ícone circular reflete a "natureza" do toast.

class _ToastStyle {
  const _ToastStyle({required this.accent, required this.icon});
  final Color accent;
  final IconData icon;
}

_ToastStyle _styleFor(AppToastKind kind, Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  switch (kind) {
    case AppToastKind.success:
      return _ToastStyle(
        accent: isDark ? const Color(0xFF22C55E) : const Color(0xFF16A34A),
        icon: Icons.check_rounded,
      );
    case AppToastKind.error:
      return _ToastStyle(
        accent: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
        icon: Icons.priority_high_rounded,
      );
    case AppToastKind.warning:
      return _ToastStyle(
        accent: isDark ? const Color(0xFFFBBF24) : const Color(0xFFF59E0B),
        icon: Icons.bolt_rounded,
      );
    case AppToastKind.info:
      return _ToastStyle(
        accent: isDark
            ? AppColors.primary.primaryDarkMode
            : AppColors.primary.primary,
        icon: Icons.info_outline_rounded,
      );
  }
}

class _ToastLayer extends StatefulWidget {
  const _ToastLayer({
    required this.theme,
    required this.message,
    required this.subtitle,
    required this.kind,
    required this.duration,
    required this.onTap,
    required this.onDispose,
  });

  final ThemeData theme;
  final String message;
  final String? subtitle;
  final AppToastKind kind;
  final Duration duration;
  final VoidCallback? onTap;
  final VoidCallback onDispose;

  @override
  State<_ToastLayer> createState() => _ToastLayerState();
}

class _ToastLayerState extends State<_ToastLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
    reverseDuration: const Duration(milliseconds: 240),
  );

  late final Animation<double> _slide = CurvedAnimation(
    parent: _controller,
    curve: const Cubic(0.22, 1, 0.36, 1),
    reverseCurve: Curves.easeInCubic,
  );

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.7, curve: Curves.easeOut),
    reverseCurve: Curves.easeIn,
  );

  Timer? _dismissTimer;
  double _dragY = 0;

  @override
  void initState() {
    super.initState();
    HapticFeedback.lightImpact();
    _controller.forward();
    _dismissTimer = Timer(widget.duration, _animateOut);
  }

  void _animateOut() {
    _dismissTimer?.cancel();
    if (!mounted) return;
    _controller.reverse().then((_) {
      if (mounted) widget.onDispose();
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final brightness = widget.theme.brightness;
    final isDark = brightness == Brightness.dark;
    final style = _styleFor(widget.kind, brightness);

    // Fundo da pill: escuro no dark mode, off-white no light. Sólido,
    // sem glass — glass tinha sombra "borrada" demais e ficava lendo
    // como caixa de erro do sistema.
    final bg = isDark
        ? const Color(0xFF1A1A1F)
        : const Color(0xFFFFFFFF);
    final fg = isDark ? Colors.white : const Color(0xFF0F1216);
    final fgSec = isDark
        ? Colors.white.withValues(alpha: 0.62)
        : const Color(0xFF0F1216).withValues(alpha: 0.6);
    final borderCol = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.08);

    final bottom = media.padding.bottom + 18 - _dragY;

    return Positioned(
      left: 0,
      right: 0,
      bottom: bottom,
      child: SafeArea(
        top: false,
        child: Center(
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.4),
              end: Offset.zero,
            ).animate(_slide),
            child: FadeTransition(
              opacity: _fade,
              child: Semantics(
                liveRegion: true,
                label: widget.message,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    widget.onTap?.call();
                    _animateOut();
                  },
                  onVerticalDragUpdate: (d) {
                    setState(() {
                      _dragY = (_dragY - d.delta.dy).clamp(-120.0, 24.0);
                    });
                  },
                  onVerticalDragEnd: (d) {
                    if (d.velocity.pixelsPerSecond.dy > 220 || _dragY < -8) {
                      _animateOut();
                    } else {
                      setState(() => _dragY = 0);
                    }
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    constraints: const BoxConstraints(maxWidth: 540),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: borderCol, width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.42 : 0.10,
                          ),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                          spreadRadius: -8,
                        ),
                        BoxShadow(
                          color: style.accent
                              .withValues(alpha: isDark ? 0.18 : 0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                          spreadRadius: -10,
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
                      child: Row(
                        crossAxisAlignment: widget.subtitle != null
                            ? CrossAxisAlignment.start
                            : CrossAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _RoundIcon(
                            accent: style.accent,
                            icon: style.icon,
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.message,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: fg,
                                    height: 1.3,
                                    letterSpacing: -0.1,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (widget.subtitle != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.subtitle!,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                      color: fgSec,
                                      height: 1.35,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ícone circular compacto à esquerda — único elemento "colorido" do
/// toast, é o que diferencia visualmente success/error/warning/info.
class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.accent, required this.icon});

  final Color accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent,
            Color.lerp(accent, Colors.black, 0.18) ?? accent,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.42),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(
        icon,
        size: 16,
        color: Colors.white,
      ),
    );
  }
}
