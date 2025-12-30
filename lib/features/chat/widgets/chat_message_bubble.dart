import 'package:flutter/material.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../core/theme/app_colors.dart';
import '../models/chat_models.dart';

/// Widget para bolha de mensagem
class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isOwnMessage;
  final bool showAvatar;
  final bool showTime;

  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.isOwnMessage,
    this.showAvatar = false,
    this.showTime = true,
  });

  String _formatTime(DateTime dateTime) {
    // Converter para timezone local antes de formatar
    final localTime = dateTime.toLocal();
    return '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (message.isSystemMessage == true) {
      // Mensagem do sistema
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: ThemeHelpers.backgroundColor(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              message.content,
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: isOwnMessage
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isOwnMessage) ...[
            // Avatar (apenas para mensagens de outros)
            if (showAvatar)
              CircleAvatar(
                radius: 16,
                backgroundImage: message.senderAvatar != null
                    ? NetworkImage(message.senderAvatar!)
                    : null,
                child: message.senderAvatar == null
                    ? Text(
                        message.senderName.isNotEmpty
                            ? message.senderName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(fontSize: 12),
                      )
                    : null,
              )
            else
              const SizedBox(width: 32),
            const SizedBox(width: 8),
          ],
          // Bolha de mensagem
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isOwnMessage
                    ? AppColors.primary.primary
                    : ThemeHelpers.cardBackgroundColor(context),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isOwnMessage ? 18 : 4),
                  bottomRight: Radius.circular(isOwnMessage ? 4 : 18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: isOwnMessage
                    ? null
                    : Border.all(
                        color: ThemeHelpers.borderLightColor(context),
                        width: 0.5,
                      ),
              ),
              child: Column(
                crossAxisAlignment: isOwnMessage
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  // Nome do remetente (apenas para mensagens de outros)
                  if (!isOwnMessage && showAvatar)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        message.senderName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary.primary,
                        ),
                      ),
                    ),
                  // Conteúdo da mensagem
                  SelectableText(
                    message.content,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isOwnMessage
                          ? Colors.white
                          : ThemeHelpers.textColor(context),
                      height: 1.4,
                    ),
                  ),
                  // Status e hora
                  if (showTime)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatTime(message.createdAt),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isOwnMessage
                                  ? Colors.white70
                                  : ThemeHelpers.textSecondaryColor(context),
                              fontSize: 11,
                            ),
                          ),
                          if (isOwnMessage) ...[
                            const SizedBox(width: 4),
                            Icon(
                              _getStatusIcon(message.status),
                              size: 12,
                              color: Colors.white70,
                            ),
                          ],
                          if (message.isEdited) ...[
                            const SizedBox(width: 4),
                            Text(
                              'editado',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isOwnMessage
                                    ? Colors.white70
                                    : ThemeHelpers.textSecondaryColor(context),
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (isOwnMessage) ...[
            const SizedBox(width: 8),
            // Espaço para alinhar (mesmo tamanho do avatar)
            const SizedBox(width: 32),
          ],
        ],
      ),
    );
  }

  IconData _getStatusIcon(ChatMessageStatus status) {
    switch (status) {
      case ChatMessageStatus.sending:
        return Icons.access_time;
      case ChatMessageStatus.sent:
        return Icons.check;
      case ChatMessageStatus.delivered:
        return Icons.done_all;
      case ChatMessageStatus.read:
        return Icons.done_all;
    }
  }
}

