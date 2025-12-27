import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/notification_controller.dart';
import '../widgets/notification_list.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_scaffold.dart';

/// Página completa de notificações
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  @override
  void initState() {
    super.initState();
    // Carregar notificações ao inicializar
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = Provider.of<NotificationController>(context, listen: false);
      controller.loadNotifications(reset: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AppScaffold(
      title: 'Notificações',
      body: Consumer<NotificationController>(
        builder: (context, controller, child) {
          return Column(
            children: [
              // Filtros
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.background.backgroundSecondaryDarkMode
                      : AppColors.background.backgroundSecondary,
                  border: Border(
                    bottom: BorderSide(
                      color: isDark
                          ? AppColors.border.borderDarkMode
                          : AppColors.border.border,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _FilterChip(
                        label: 'Todas',
                        selected: controller.notifications.isNotEmpty,
                        onTap: () {
                          controller.clearFilters();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _FilterChip(
                        label: 'Não lidas',
                        selected: false,
                        onTap: () {
                          controller.setFilters(read: false);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _FilterChip(
                        label: 'Lidas',
                        selected: false,
                        onTap: () {
                          controller.setFilters(read: true);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              // Lista
              Expanded(
                child: NotificationList(
                  embedded: false,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Chip de filtro
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? (isDark
                  ? AppColors.primary.primaryDarkMode
                  : AppColors.primary.primary)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? (isDark
                    ? AppColors.primary.primaryDarkMode
                    : AppColors.primary.primary)
                : (isDark
                    ? AppColors.border.borderDarkMode
                    : AppColors.border.border),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: selected
                  ? Colors.white
                  : (isDark
                      ? AppColors.text.textDarkMode
                      : AppColors.text.text),
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

