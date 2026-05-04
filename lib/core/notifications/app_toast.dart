import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../navigation/app_navigator.dart';
import '../theme/app_colors.dart';

/// Toasts estilo Intellisys — painel em vidro, faixa de accent, ícone, label tipográfica
/// e barra de tempo; entra por cima com blur local (não usa SnackBar nativo).
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
    final overlay = Overlay.maybeOf(context) ?? appNavigatorKey.currentState?.overlay;
    if (overlay == null) return;

    dismiss();

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => Stack(
        fit: StackFit.expand,
        children: [
          _IntellisysToastLayer(
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
        ],
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
    AppToast.show(this, message: message, kind: kind, subtitle: subtitle, duration: duration);
  }
}

class _ToastStyle {
  const _ToastStyle({
    required this.accent,
    required this.icon,
    required this.label,
  });

  final Color accent;
  final IconData icon;
  final String label;
}

_ToastStyle _styleFor(AppToastKind kind, Brightness brightness) {
  switch (kind) {
    case AppToastKind.success:
      return _ToastStyle(
        accent: brightness == Brightness.dark
            ? AppColors.status.successDarkMode
            : AppColors.status.success,
        icon: Icons.check_rounded,
        label: 'CONFIRMADO',
      );
    case AppToastKind.error:
      return _ToastStyle(
        accent: brightness == Brightness.dark
            ? AppColors.status.errorDarkMode
            : AppColors.status.error,
        icon: Icons.error_outline_rounded,
        label: 'ATENÇÃO',
      );
    case AppToastKind.warning:
      return const _ToastStyle(
        accent: Color(0xFFF59E0B),
        icon: Icons.flash_on_rounded,
        label: 'ALERTA',
      );
    case AppToastKind.info:
      return _ToastStyle(
        accent:
            brightness == Brightness.dark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary,
        icon: Icons.auto_awesome_rounded,
        label: 'INTELLISYS',
      );
  }
}

class _IntellisysToastLayer extends StatefulWidget {
  const _IntellisysToastLayer({
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
  State<_IntellisysToastLayer> createState() => _IntellisysToastLayerState();
}

class _IntellisysToastLayerState extends State<_IntellisysToastLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    reverseDuration: const Duration(milliseconds: 320),
  );
  late final Animation<double> _slide = CurvedAnimation(
    parent: _controller,
    curve: const Cubic(0.22, 1, 0.36, 1),
    reverseCurve: Curves.easeInCubic,
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
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
    final top = media.padding.top + 10;
    final brightness = widget.theme.brightness;
    final isDark = brightness == Brightness.dark;
    final style = _styleFor(widget.kind, brightness);

    final fg = isDark ? AppColors.text.textDarkMode : AppColors.text.text;
    final fgSec = isDark ? AppColors.text.textSecondaryDarkMode : AppColors.text.textSecondary;
    final glassTop = isDark ? const Color(0xFF1A1924).withValues(alpha: 0.82) : Colors.white.withValues(alpha: 0.86);
    final glassBot = isDark ? const Color(0xFF12111A).withValues(alpha: 0.88) : const Color(0xFFF1F5F9).withValues(alpha: 0.92);
    final borderCol = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : AppColors.border.border.withValues(alpha: 0.55);

    return Positioned(
      top: top + _dragY,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -1.1), end: Offset.zero).animate(_slide),
        child: FadeTransition(
          opacity: _fade,
          child: Semantics(
            liveRegion: true,
            label: '${style.label}. ${widget.message}',
            child: GestureDetector(
              onTap: () {
                widget.onTap?.call();
                _animateOut();
              },
              onVerticalDragUpdate: (d) {
                setState(() {
                  _dragY = (_dragY + d.delta.dy).clamp(-24.0, 120.0);
                });
              },
              onVerticalDragEnd: (d) {
                if (d.velocity.pixelsPerSecond.dy < -220 || _dragY < -8) {
                  _animateOut();
                } else {
                  setState(() => _dragY = 0);
                }
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: style.accent.withValues(alpha: isDark ? 0.22 : 0.14),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                      spreadRadius: -8,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [glassTop, glassBot],
                        ),
                        border: Border.all(color: borderCol, width: 1),
                      ),
                      child: Stack(
                      children: [
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: 5,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  style.accent.withValues(alpha: 0.95),
                                  style.accent.withValues(alpha: 0.45),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 16, 18),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _IconPulse(
                                accent: style.accent,
                                icon: style.icon,
                                isDark: isDark,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      style.label,
                                      style: GoogleFonts.poppins(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.35,
                                        color: style.accent.withValues(alpha: 0.95),
                                        height: 1,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      widget.message,
                                      style: GoogleFonts.poppins(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w700,
                                        height: 1.25,
                                        letterSpacing: -0.2,
                                        color: fg,
                                      ),
                                    ),
                                    if (widget.subtitle != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        widget.subtitle!,
                                        style: GoogleFonts.poppins(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w500,
                                          height: 1.2,
                                          color: fgSec,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.swipe_vertical_rounded,
                                size: 18,
                                color: fgSec.withValues(alpha: 0.45),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 20,
                          right: 16,
                          bottom: 6,
                          child: _ToastCountdownBar(
                            accent: style.accent,
                            duration: widget.duration,
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

class _IconPulse extends StatefulWidget {
  const _IconPulse({required this.accent, required this.icon, required this.isDark});

  final Color accent;
  final IconData icon;
  final bool isDark;

  @override
  State<_IconPulse> createState() => _IconPulseState();
}

class _IconPulseState extends State<_IconPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 680),
  );

  @override
  void initState() {
    super.initState();
    _a.forward();
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.82, end: 1).animate(CurvedAnimation(parent: _a, curve: Curves.easeOutCubic)),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              widget.accent.withValues(alpha: widget.isDark ? 0.45 : 0.35),
              widget.accent.withValues(alpha: widget.isDark ? 0.2 : 0.14),
            ],
          ),
          border: Border.all(color: widget.accent.withValues(alpha: 0.55)),
          boxShadow: [
            BoxShadow(
              color: widget.accent.withValues(alpha: widget.isDark ? 0.35 : 0.22),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(widget.icon, color: Colors.white.withValues(alpha: 0.95), size: 24),
      ),
    );
  }
}

class _ToastCountdownBar extends StatefulWidget {
  const _ToastCountdownBar({
    required this.accent,
    required this.duration,
  });

  final Color accent;
  final Duration duration;

  @override
  State<_ToastCountdownBar> createState() => _ToastCountdownBarState();
}

class _ToastCountdownBarState extends State<_ToastCountdownBar> with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
    _progress.forward();
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, _) {
        final remaining = 1.0 - _progress.value;
        return ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: widget.accent.withValues(alpha: 0.12),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: remaining.clamp(0.0, 1.0),
                    alignment: Alignment.centerLeft,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            widget.accent.withValues(alpha: 0.95),
                            widget.accent.withValues(alpha: 0.4),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
