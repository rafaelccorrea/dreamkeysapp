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
      builder: (context) => _NotificationOverlay(
        offset: Offset(offset.dx, offset.dy + size.height + 8),
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

/// Overlay do painel de notificações
class _NotificationOverlay extends StatelessWidget {
  final Offset offset;
  final VoidCallback onClose;

  const _NotificationOverlay({
    required this.offset,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final padding = MediaQuery.of(context).padding;
    
    // Calcular altura disponível respeitando bottom navigation
    // Bottom nav geralmente tem 56px + padding bottom
    final bottomNavHeight = 56.0 + padding.bottom;
    final availableHeight = screenHeight - offset.dy - bottomNavHeight - 8; // 8px de margem

    // Calcular posição e tamanho - FULL WIDTH
    final width = screenWidth; // Full width
    final left = 0.0; // Começar do início
    final top = offset.dy;
    final maxHeight = availableHeight.clamp(200.0, screenHeight * 0.7); // Mínimo 200px, máximo 70% da tela

    return GestureDetector(
      onTap: onClose,
      behavior: HitTestBehavior.translucent,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // Backdrop
            Positioned.fill(
              child: Container(
                color: Colors.transparent,
              ),
            ),
            // Painel - Full Width
            Positioned(
              left: left,
              top: top,
              right: 0,
              child: GestureDetector(
                onTap: () {}, // Prevenir fechamento ao clicar no painel
                child: Container(
                  width: width,
                  constraints: BoxConstraints(
                    maxHeight: maxHeight,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.background.cardBackgroundDarkMode
                        : AppColors.background.cardBackground,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      _NotificationHeader(onClose: onClose),
                      // Lista
                      Flexible(
                        child: NotificationList(
                          embedded: true,
                          maxHeight: maxHeight - 60,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Header do painel de notificações
class _NotificationHeader extends StatelessWidget {
  final VoidCallback onClose;

  const _NotificationHeader({
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Consumer<NotificationController>(
      builder: (context, controller, child) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? AppColors.border.borderDarkMode
                    : AppColors.border.border,
                width: 1,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Notificações',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (controller.unreadCount > 0)
                    TextButton(
                      onPressed: () async {
                        await controller.markAllAsRead();
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Marcar todas',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: onClose,
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

