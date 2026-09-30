import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../whatsapp/widgets/whatsapp_conversation_card.dart'
    show WhatsAppAvatar;
import '../models/chat_models.dart';
import 'chat_visual.dart';

/// Linha da lista de conversas do chat interno (30/09/2026) — a gramática do
/// WhatsApp do app: linha flush sem cartão, avatar com foto ou iniciais,
/// nome em alto contraste, hora curta à direita, prévia da última mensagem e
/// selo de não lidas. O filete começa depois do avatar, nunca embaixo dele.
///
/// Sinais que evitam um toque a mais: ícone de grupo antes do nome, sino
/// cortado quando a conversa está silenciada (mensagem nova ali não acende o
/// aviso do chat), hora e prévia em destaque quando há não lidas. Antes era
/// um cartão com borda e um ponto verde de "online" fixo em toda conversa
/// direta — que não dizia nada (não havia dado de presença por trás).
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

  @override
  Widget build(BuildContext context) {
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final ink = chatInk(context);

    final displayName = room.getDisplayName(currentUserId);
    final displayImage = room.getDisplayImage(currentUserId);
    final unread = room.unreadCount ?? 0;
    final hasUnread = unread > 0;
    final isMuted = room.isMuted == true;
    final isGroup = room.type == ChatRoomType.group;
    final isSupport = room.type == ChatRoomType.support;

    final preview = chatPreviewText(room.lastMessage);
    final time = chatShortTime(room.lastMessageAt);

    final semantics = StringBuffer(
      isGroup ? 'Grupo $displayName' : 'Conversa com $displayName',
    );
    if (hasUnread) {
      semantics.write(
        unread == 1 ? ', 1 mensagem não lida' : ', $unread mensagens não lidas',
      );
    }
    if (isMuted) semantics.write(', silenciada');

    return Semantics(
      button: true,
      selected: isSelected,
      label: semantics.toString(),
      excludeSemantics: true,
      child: Material(
        color: isSelected ? chatSelectedFill(context) : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: WhatsAppAvatar(
                    name: displayName,
                    imageUrl: displayImage,
                    size: 52,
                  ),
                ),
                // O filete pertence à coluna de texto: começa depois do avatar
                // e vai até a borda direita.
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(0, 13, 16, 13),
                    decoration: BoxDecoration(
                      border: Border(bottom: chatHairline(context)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (isGroup || isSupport) ...[
                              Icon(
                                isGroup
                                    ? LucideIcons.usersRound
                                    : LucideIcons.lifeBuoy,
                                size: 14,
                                color: secondary,
                              ),
                              const SizedBox(width: 5),
                            ],
                            Expanded(
                              child: Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: hasUnread
                                      ? FontWeight.w800
                                      : FontWeight.w700,
                                  color: textColor,
                                  letterSpacing: -0.3,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            if (time.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text(
                                time,
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: hasUnread ? ink : secondary,
                                  fontWeight: hasUnread
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                preview.isNotEmpty
                                    ? preview
                                    : 'Nenhuma mensagem ainda',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: hasUnread ? textColor : secondary,
                                  fontWeight: hasUnread
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  height: 1.3,
                                  letterSpacing: -0.1,
                                ),
                              ),
                            ),
                            if (isMuted) ...[
                              const SizedBox(width: 6),
                              Tooltip(
                                message: 'Silenciada: não acende o aviso',
                                child: Icon(
                                  LucideIcons.bellOff,
                                  size: 15,
                                  color: secondary,
                                ),
                              ),
                            ],
                            if (hasUnread) ...[
                              const SizedBox(width: 8),
                              ChatUnreadBadge(count: unread),
                            ],
                          ],
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
    );
  }
}
