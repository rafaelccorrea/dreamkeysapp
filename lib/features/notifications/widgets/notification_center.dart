import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../controllers/notification_controller.dart';
import 'notification_list.dart';

/// Componente principal do centro de notificações
/// Exibe badge com contador e painel dropdown com lista
/// Pode ser usado como widget para adicionar em actions do AppBar
class NotificationCenter extends StatefulWidget {
  final bool embedded;

  /// Tamanho reduzido para a cápsula do [MinimalBodyChrome].
  final bool compactToolbar;

  const NotificationCenter({
    super.key,
    this.embedded = false,
    this.compactToolbar = false,
  });

  @override
  State<NotificationCenter> createState() => _NotificationCenterState();
}

class _NotificationCenterState extends State<NotificationCenter> {
  final GlobalKey _buttonKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

  @override
  void dispose() {
    _closeOverlay();
    super.dispose();
  }

  void _closeOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
      _isOpen = false;
    }
  }

  void _toggleOverlay() {
    if (_isOpen) {
      _closeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _showOverlay() {
    final RenderBox? renderBox =
        _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    _overlayEntry = OverlayEntry(
      builder: (context) => _NotificationOverlayPanel(
        anchorTop: offset.dy + size.height + 8,
        onClose: _closeOverlay,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    _isOpen = true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Consumer<NotificationController>(
      builder: (context, controller, child) {
        final unreadCount = controller.unreadCount;

        final compact = widget.compactToolbar;
        final dim = compact ? 40.0 : 46.0;
        final iconSize = compact ? 20.0 : 22.0;

        final hasUnread = unreadCount > 0;
        const accentRed = Color(0xFFEF4444);

        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Tooltip(
              message: 'Notificações',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: _buttonKey,
                  onTap: _toggleOverlay,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: dim,
                    height: dim,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.07)
                          : theme.colorScheme.surfaceContainerHighest.withValues(
                              alpha: 0.65,
                            ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        width: 1.5,
                        color: hasUnread
                            ? accentRed.withValues(alpha: 0.5)
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.12)
                                : AppColors.border.border),
                      ),
                      boxShadow: [
                        if (hasUnread) ...[
                          BoxShadow(
                            color: accentRed.withValues(alpha: 0.12),
                            blurRadius: 8,
                            spreadRadius: 0,
                            offset: const Offset(0, 2),
                          ),
                        ] else
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.2 : 0.04,
                            ),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                      ],
                    ),
                    child: Icon(
                      hasUnread
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_outlined,
                      size: iconSize,
                      color: hasUnread
                          ? accentRed
                          : ThemeHelpers.textColor(context),
                    ),
                  ),
                ),
              ),
            ),
            if (unreadCount > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark
                          ? AppColors.background.backgroundDarkMode
                          : theme.scaffoldBackgroundColor,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accentRed.withValues(alpha: 0.45),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : unreadCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Altura reservada do cabeçalho + listagem (lista usa o restante).
const double _kNotificationPanelHeaderBlock = 108;

/// Painel dropdown de notificações — overlay animado com blur, profundidade e detalhes de marca.
class _NotificationOverlayPanel extends StatefulWidget {
  final double anchorTop;
  final VoidCallback onClose;

  const _NotificationOverlayPanel({
    required this.anchorTop,
    required this.onClose,
  });

  @override
  State<_NotificationOverlayPanel> createState() =>
      _NotificationOverlayPanelState();
}

class _NotificationOverlayPanelState extends State<_NotificationOverlayPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _open;
  late Animation<double> _fade;
  late Animation<double> _scale;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _open = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _fade = CurvedAnimation(parent: _open, curve: Curves.easeOutCubic);
    _scale = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(parent: _open, curve: Curves.easeOutBack),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.035),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _open, curve: Curves.easeOutCubic));
    _open.forward();
  }

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final padding = MediaQuery.paddingOf(context);
    final bottomNavHeight = 56.0 + padding.bottom;
    final availableHeight =
        screenHeight - widget.anchorTop - bottomNavHeight - 8;
    final maxHeight = availableHeight.clamp(220.0, screenHeight * 0.72);
    final primary = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
    final secondary = isDark
        ? AppColors.secondary.secondaryDarkMode
        : AppColors.secondary.secondary;

    return GestureDetector(
      onTap: widget.onClose,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Camada escurecida + blur (toque fora fecha)
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: isDark ? 0.52 : 0.28),
                        Colors.black.withValues(alpha: isDark ? 0.38 : 0.16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: widget.anchorTop,
            child: GestureDetector(
              onTap: () {},
              child: AnimatedBuilder(
                animation: _open,
                builder: (context, child) {
                  return FadeTransition(
                    opacity: _fade,
                    child: SlideTransition(
                      position: _slide,
                      child: ScaleTransition(
                        scale: _scale,
                        alignment: Alignment.topCenter,
                        child: child,
                      ),
                    ),
                  );
                },
                child: _NotificationPanelChrome(
                  maxHeight: maxHeight,
                  primary: primary,
                  secondary: secondary,
                  onClose: widget.onClose,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Corpo visual do painel (bordas, sombras, brilho interno).
class _NotificationPanelChrome extends StatelessWidget {
  final double maxHeight;
  final Color primary;
  final Color secondary;
  final VoidCallback onClose;

  const _NotificationPanelChrome({
    required this.maxHeight,
    required this.primary,
    required this.secondary,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final innerBg = isDark
        ? AppColors.background.cardBackgroundDarkMode
        : AppColors.background.cardBackground;

    const panelShape = BorderRadius.only(
      bottomLeft: Radius.circular(26),
      bottomRight: Radius.circular(26),
    );
    const innerRadii = BorderRadius.only(
      bottomLeft: Radius.circular(24.65),
      bottomRight: Radius.circular(24.65),
    );

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        borderRadius: panelShape,
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: isDark ? 0.22 : 0.18),
            blurRadius: 32,
            spreadRadius: -4,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.12),
            blurRadius: 40,
            offset: const Offset(0, 24),
          ),
          BoxShadow(
            color: secondary.withValues(alpha: 0.08),
            blurRadius: 60,
            spreadRadius: -8,
            offset: const Offset(0, 36),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: panelShape,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color.lerp(innerBg, primary, isDark ? 0.09 : 0.04)!,
                innerBg,
                Color.lerp(innerBg, secondary, isDark ? 0.06 : 0.03)!,
              ],
              stops: const [0.0, 0.38, 1.0],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(1.35),
            child: ClipRRect(
              borderRadius: innerRadii,
              child: Container(
                decoration: BoxDecoration(
                  color: innerBg,
                  borderRadius: innerRadii,
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : primary.withValues(alpha: 0.12),
                  ),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Brilho difuso superior (vidro / profundidade)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 132,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              primary.withValues(alpha: isDark ? 0.14 : 0.10),
                              primary.withValues(alpha: 0.02),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.45, 1.0],
                          ),
                        ),
                      ),
                    ),
                    // Traço decorativo no topo
                    Positioned(
                      top: 10,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(99),
                            gradient: LinearGradient(
                              colors: [
                                primary.withValues(alpha: 0.35),
                                secondary.withValues(alpha: 0.55),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: primary.withValues(alpha: 0.35),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Raster sutil no fundo
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _DotTexturePainter(
                            color: ThemeHelpers.textColor(context).withValues(
                              alpha: isDark ? 0.035 : 0.04,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _NotificationPanelHeader(onClose: onClose),
                        Flexible(
                          child: ClipRect(
                            child: NotificationList(
                              embedded: true,
                              maxHeight: maxHeight - _kNotificationPanelHeaderBlock,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Textura de pontos muito suave atrás da lista.
class _DotTexturePainter extends CustomPainter {
  final Color color;

  _DotTexturePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    const step = 18.0;
    var row = 0;
    for (var y = 0.0; y < size.height; y += step, row++) {
      final stagger = row.isOdd ? step * 0.5 : 0.0;
      for (var x = stagger; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.1, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotTexturePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _NotificationPanelHeader extends StatelessWidget {
  final VoidCallback onClose;

  const _NotificationPanelHeader({required this.onClose});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
    final secondary = isDark
        ? AppColors.secondary.secondaryDarkMode
        : AppColors.secondary.secondary;

    return Consumer<NotificationController>(
      builder: (context, controller, _) {
        final unread = controller.unreadCount;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 22, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HeaderIconOrb(primary: primary, hasUnread: unread > 0),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (bounds) {
                            return LinearGradient(
                              colors: [
                                primary,
                                AppColors.primary.primaryLight,
                                isDark
                                    ? AppColors.secondary.secondaryDarkMode
                                    : AppColors.secondary.secondary,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ).createShader(
                              Rect.fromLTWH(0, 0, bounds.width, bounds.height),
                            );
                          },
                          child: Text(
                            'Notificações',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.6,
                              height: 1.05,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          unread > 0
                              ? '$unread não lida${unread == 1 ? '' : 's'} · Toque num item para abrir'
                              : 'Tudo em dia · alertas e atualizações em tempo real',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _ChromeCloseButton(onPressed: onClose),
                      if (unread > 0) ...[
                        const SizedBox(height: 10),
                        _MarkAllChip(
                          onPressed: () async {
                            await controller.markAllAsRead();
                          },
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      primary.withValues(alpha: 0.45),
                      secondary.withValues(alpha: 0.35),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
        );
      },
    );
  }
}

class _HeaderIconOrb extends StatelessWidget {
  final Color primary;
  final bool hasUnread;

  const _HeaderIconOrb({
    required this.primary,
    required this.hasUnread,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primary.withValues(alpha: 0.28),
            primary.withValues(alpha: 0.08),
          ],
        ),
        border: Border.all(
          color: primary.withValues(alpha: hasUnread ? 0.55 : 0.28),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: hasUnread ? 0.35 : 0.15),
            blurRadius: hasUnread ? 16 : 10,
            spreadRadius: hasUnread ? 1 : 0,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            hasUnread
                ? Icons.notifications_active_rounded
                : Icons.notifications_none_rounded,
            color: primary,
            size: 26,
          ),
          if (hasUnread)
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF22C55E),
                  border: Border.all(
                    color: isDark
                        ? AppColors.background.cardBackgroundDarkMode
                        : Colors.white,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.6),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChromeCloseButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _ChromeCloseButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : AppColors.background.backgroundTertiary.withValues(alpha: 0.9),
            border: Border.all(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            Icons.close_rounded,
            size: 22,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
        ),
      ),
    );
  }
}

class _MarkAllChip extends StatelessWidget {
  final VoidCallback onPressed;

  const _MarkAllChip({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [
                primary.withValues(alpha: 0.14),
                primary.withValues(alpha: 0.06),
              ],
            ),
            border: Border.all(color: primary.withValues(alpha: 0.38)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.done_all_rounded, size: 16, color: primary),
                const SizedBox(width: 6),
                Text(
                  'Marcar lidas',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: primary,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
