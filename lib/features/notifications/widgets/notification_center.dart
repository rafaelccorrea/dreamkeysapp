import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/notification_controller.dart';
import 'notification_list.dart';
import '../../../core/theme/app_colors.dart';

/// Componente principal do centro de notificações
/// Exibe badge com contador e painel dropdown com lista
/// Pode ser usado como widget para adicionar em actions do AppBar
class NotificationCenter extends StatefulWidget {
  final bool embedded;

  const NotificationCenter({
    super.key,
    this.embedded = false,
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

        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              key: _buttonKey,
              icon: const Icon(Icons.notifications_outlined),
              onPressed: _toggleOverlay,
              tooltip: 'Notificações',
            ),
            if (unreadCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.status.errorDarkMode
                        : AppColors.status.error,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : unreadCount.toString(),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
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
              Text(
                'Notificações',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
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
                      child: const Text('Marcar todas como lidas'),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: onClose,
                    iconSize: 20,
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

