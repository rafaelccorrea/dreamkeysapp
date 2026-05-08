import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../navigation/app_navigator.dart';
import '../theme/app_colors.dart';

/// Toasts premium do Intellisys — pill no rodapé com identidade visual
/// forte (accent vertical, glass sutil, ícone gradient).
///
/// **Histórico do design**:
/// 1ª versão: muito carregado — faixa accent + label uppercase pomposa
/// + barra de countdown + ícone gigante quadrado. Ficou "carregado".
/// 2ª versão: minimalista demais — pill sólida lisa, ícone circular,
/// texto pequeno. Ficou "HTML sem CSS" (sem identidade).
/// **Esta versão (3ª)**: meio-termo refinado:
///   - Faixa accent vertical de 4px à esquerda (assinatura visual)
///   - Backdrop blur sutil (glass premium, não pesado)
///   - Ícone circular accent com gradient diagonal
///   - Tipografia robusta (peso 700, fontSize 14.5)
///   - Sombra dupla (preta dropshadow + glow accent)
///   - Borda accent semitransparente para definir o card
///   - Posição rodapé (padrão moderno mobile)
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
    Duration duration = const Duration(milliseconds: 3400),
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
    Duration duration = const Duration(milliseconds: 3400),
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

// ─────────────────────────────────────────────────────────────────────
// Estilo por tipo
// ─────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────
// Layer
// ─────────────────────────────────────────────────────────────────────

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
    duration: const Duration(milliseconds: 420),
    reverseDuration: const Duration(milliseconds: 280),
  );

  late final Animation<double> _slide = CurvedAnimation(
    parent: _controller,
    // Curve com leve overshoot — dá sensação de "snap" premium em vez
    // de slide chato.
    curve: const Cubic(0.34, 1.32, 0.64, 1),
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

    // Glass tonal — semi-transparente com blur por trás. Dá profundidade
    // sem ficar pesado como o glass da v1.
    final bgBase = isDark
        ? const Color(0xFF14141A)
        : Colors.white;
    final bg = bgBase.withValues(alpha: isDark ? 0.86 : 0.94);

    final fg = isDark ? Colors.white : const Color(0xFF0F1216);
    final fgSec = isDark
        ? Colors.white.withValues(alpha: 0.7)
        : const Color(0xFF0F1216).withValues(alpha: 0.66);

    final bottom = media.padding.bottom + 18 - _dragY;

    // OverlayEntry não tem `Material` ancestor por padrão — sem isso
    // o Flutter renderiza um sublinhado duplo amarelo de aviso embaixo
    // de qualquer `Text`. Envolvendo num Material transparente resolve
    // (e ainda permite InkWell funcionar dentro do toast, se um dia
    // precisarmos).
    return Positioned(
      left: 0,
      right: 0,
      bottom: bottom,
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
        top: false,
        child: Center(
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.5),
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
                      _dragY = (_dragY - d.delta.dy).clamp(-160.0, 24.0);
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
                    constraints: const BoxConstraints(maxWidth: 560),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.55 : 0.14,
                          ),
                          blurRadius: 28,
                          offset: const Offset(0, 14),
                          spreadRadius: -10,
                        ),
                        BoxShadow(
                          color: style.accent
                              .withValues(alpha: isDark ? 0.32 : 0.18),
                          blurRadius: 30,
                          offset: const Offset(0, 8),
                          spreadRadius: -12,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BackdropFilter(
                        // Glass leve (sigma 14) — dá premium sem virar
                        // "borrão" como sigma 18+ da v1.
                        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: style.accent
                                  .withValues(alpha: isDark ? 0.28 : 0.22),
                              width: 1,
                            ),
                          ),
                          child: IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Faixa accent vertical — assinatura visual
                                // que diferencia do "card cinza genérico"
                                Container(
                                  width: 4,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        style.accent,
                                        style.accent
                                            .withValues(alpha: 0.65),
                                      ],
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      12,
                                      14,
                                      12,
                                    ),
                                    child: Row(
                                      crossAxisAlignment: widget.subtitle != null
                                          ? CrossAxisAlignment.start
                                          : CrossAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _RoundIcon(
                                          accent: style.accent,
                                          icon: style.icon,
                                          isDark: isDark,
                                        ),
                                        const SizedBox(width: 12),
                                        Flexible(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                widget.message,
                                                style: TextStyle(
                                                  fontSize: 14.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: fg,
                                                  height: 1.25,
                                                  letterSpacing: -0.1,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (widget.subtitle != null) ...[
                                                const SizedBox(height: 3),
                                                Text(
                                                  widget.subtitle!,
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w500,
                                                    color: fgSec,
                                                    height: 1.35,
                                                  ),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
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
          ),
        ),
      ),
      ),
    );
  }
}

/// Ícone circular accent com gradient diagonal e glow sutil.
///
/// É o elemento mais "colorido" do toast — marca claramente o tipo
/// (success/error/warning/info) sem precisar de label uppercase.
class _RoundIcon extends StatelessWidget {
  const _RoundIcon({
    required this.accent,
    required this.icon,
    required this.isDark,
  });

  final Color accent;
  final IconData icon;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent,
            Color.lerp(accent, Colors.black, 0.22) ?? accent,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: isDark ? 0.55 : 0.42),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(
        icon,
        size: 18,
        color: Colors.white,
      ),
    );
  }
}
