import 'package:flutter/material.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/chat_models.dart';
import 'chat_message_bubble.dart';

/// Widget para lista de mensagens
class ChatMessageList extends StatelessWidget {
  final List<ChatMessage> messages;
  final String? currentUserId;
  final ScrollController scrollController;
  final VoidCallback? onLoadMore;

  const ChatMessageList({
    super.key,
    required this.messages,
    this.currentUserId,
    required this.scrollController,
    this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhuma mensagem ainda',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Envie a primeira mensagem!',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      reverse: false,
      padding: const EdgeInsets.all(16),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final isOwnMessage = message.senderId == currentUserId;
        final previousMessage = index > 0 ? messages[index - 1] : null;
        final showAvatar = !isOwnMessage && 
            (previousMessage == null || previousMessage.senderId != message.senderId);
        final showTime = index == messages.length - 1 ||
            (index < messages.length - 1 && 
             messages[index + 1].senderId != message.senderId);

        return ChatMessageBubble(
          message: message,
          isOwnMessage: isOwnMessage,
          showAvatar: showAvatar,
          showTime: showTime,
        );
      },
    );
  }
}

