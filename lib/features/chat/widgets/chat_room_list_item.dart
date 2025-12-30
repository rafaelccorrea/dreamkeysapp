import 'package:flutter/material.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../core/theme/app_colors.dart';
import '../models/chat_models.dart';

/// Widget para item da lista de conversas
class ChatRoomListItem extends StatelessWidget {
  final ChatRoom room;
  final String? currentUserId;
  final bool isSelected;
  final VoidCallback onTap;

  const ChatRoomListItem({
    super.key,
    required this.room,
    this.currentUserId,
    required this.isSelected,
    required this.onTap,
  });

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return '';

    // Converter para timezone local antes de formatar
    final localTime = dateTime.toLocal();
    final now = DateTime.now();
    final difference = now.difference(localTime);

    if (difference.inDays == 0) {
      // Hoje - mostrar apenas hora
      return '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Ontem';
    } else if (difference.inDays < 7) {
      // Esta semana - mostrar dia da semana
      final days = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
      return days[localTime.weekday % 7];
    } else {
      // Mais antigo - mostrar data
      return '${localTime.day}/${localTime.month}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = room.getDisplayName(currentUserId);
    final displayImage = room.getDisplayImage(currentUserId);

    return Card(
      margin: const EdgeInsets.only(bottom: 8, left: 12, right: 12, top: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? AppColors.primary.primary
              : ThemeHelpers.borderLightColor(context),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      color: isSelected
          ? AppColors.primary.primary.withOpacity(0.05)
          : ThemeHelpers.cardBackgroundColor(context),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Avatar
              Stack(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundImage: displayImage != null
                        ? NetworkImage(displayImage)
                        : null,
                    child: displayImage == null
                        ? Text(
                            displayName.isNotEmpty
                                ? displayName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          )
                        : null,
                  ),
                  // Indicador de status online (para conversas diretas)
                  if (room.type == ChatRoomType.direct)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: ThemeHelpers.backgroundColor(context),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              // Conteúdo
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? AppColors.primary.primary
                                  : ThemeHelpers.textColor(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (room.lastMessageAt != null)
                          Text(
                            _formatDateTime(room.lastMessageAt),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: ThemeHelpers.textSecondaryColor(context),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            room.lastMessage ?? 'Nenhuma mensagem',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: ThemeHelpers.textSecondaryColor(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (room.unreadCount != null && room.unreadCount! > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              room.unreadCount! > 99
                                  ? '99+'
                                  : '${room.unreadCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
