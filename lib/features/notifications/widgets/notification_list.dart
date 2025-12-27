import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/notification_controller.dart';
import '../utils/notification_navigation.dart';
import 'notification_item.dart';
import '../../../core/theme/app_colors.dart';

/// Lista de notificações com scroll infinito
class NotificationList extends StatefulWidget {
  final bool embedded;
  final double? maxHeight;

  const NotificationList({
    super.key,
    this.embedded = false,
    this.maxHeight,
  });

  @override
  State<NotificationList> createState() => _NotificationListState();
}

class _NotificationListState extends State<NotificationList> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    
    // Carregar notificações ao inicializar
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = Provider.of<NotificationController>(context, listen: false);
      controller.loadNotifications(reset: true);
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      final controller = Provider.of<NotificationController>(context, listen: false);
      if (!controller.loadingMore && controller.hasMore) {
        controller.loadMore();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Consumer<NotificationController>(
      builder: (context, controller, child) {
        if (controller.loading && controller.notifications.isEmpty) {
          return SizedBox(
            height: widget.maxHeight ?? 300,
            child: Center(
              child: CircularProgressIndicator(
                color: isDark
                    ? AppColors.primary.primaryDarkMode
                    : AppColors.primary.primary,
              ),
            ),
          );
        }

        if (controller.error != null && controller.notifications.isEmpty) {
          return SizedBox(
            height: widget.maxHeight ?? 300,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: isDark
                        ? AppColors.status.errorDarkMode
                        : AppColors.status.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    controller.error!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isDark
                          ? AppColors.text.textDarkMode
                          : AppColors.text.text,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => controller.loadNotifications(reset: true),
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
          );
        }

        if (controller.notifications.isEmpty) {
          return SizedBox(
            height: widget.maxHeight ?? 300,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 48,
                    color: isDark
                        ? AppColors.text.textLightDarkMode
                        : AppColors.text.textLight,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhuma notificação',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: isDark
                          ? AppColors.text.textSecondaryDarkMode
                          : AppColors.text.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Container(
          constraints: widget.maxHeight != null
              ? BoxConstraints(maxHeight: widget.maxHeight!)
              : null,
          child: RefreshIndicator(
            onRefresh: () => controller.refresh(),
            child: ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.zero,
              itemCount: controller.notifications.length +
                  (controller.loadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= controller.notifications.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                  final notification = controller.notifications[index];
                return NotificationItem(
                  notification: notification,
                  onTap: () async {
                    // Marcar como lida se não estiver lida
                    if (!notification.read) {
                      await controller.markAsRead(notification.id);
                    }

                    // Navegar se tiver URL
                    final url = NotificationNavigation.getNotificationNavigationUrl(
                      notification,
                    );
                    if (url != null && context.mounted) {
                      Navigator.of(context).pushNamed(url);
                    }
                  },
                  onDelete: () async {
                    await controller.deleteNotification(notification.id);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}

