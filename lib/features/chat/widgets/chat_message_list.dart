import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../whatsapp/widgets/whatsapp_message_bubble.dart'
    show WhatsAppDaySeparator;
import '../models/chat_models.dart';
import 'chat_message_bubble.dart';
import 'chat_visual.dart';

/// Linha do tempo da conversa (30/09/2026): separador de dia ("Hoje",
/// "Ontem", "12 de setembro") como no WhatsApp do app e mensagens seguidas
/// da mesma pessoa agrupadas (cauda e avatar só na última do bloco).
class ChatMessageList extends StatelessWidget {
  final List<ChatMessage> messages;
  final String? currentUserId;
  final ScrollController scrollController;
  final VoidCallback? onLoadMore;

  /// Conversa em grupo: nome e avatar de quem escreveu nas bolhas.
  final bool isGroup;

  /// Nome de quem está do outro lado (conversa direta) — o vazio fala dele.
  final String? peerName;

  const ChatMessageList({
    super.key,
    required this.messages,
    this.currentUserId,
    required this.scrollController,
    this.onLoadMore,
    this.isGroup = false,
    this.peerName,
  });

  static DateTime _day(DateTime d) {
    final l = d.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  /// Chave de autoria para agrupar: aviso do sistema nunca agrupa.
  static String _authorKey(ChatMessage m) =>
      m.isSystemMessage == true ? 'system-${m.id}' : 'u-${m.senderId}';

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) return _buildEmpty(context);

    // Entradas da lista: DateTime = separador de dia; int = índice da
    // mensagem. Montado uma vez por build.
    final entries = <Object>[];
    DateTime? currentDay;
    for (var i = 0; i < messages.length; i++) {
      final day = _day(messages[i].createdAt);
      if (currentDay == null || day != currentDay) {
        currentDay = day;
        entries.add(day);
      }
      entries.add(i);
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        if (entry is DateTime) {
          return WhatsAppDaySeparator(date: entry);
        }
        final i = entry as int;
        final message = messages[i];
        final prev = i > 0 ? messages[i - 1] : null;
        final next = i < messages.length - 1 ? messages[i + 1] : null;
        final day = _day(message.createdAt);

        final isFirst = prev == null ||
            _authorKey(prev) != _authorKey(message) ||
            _day(prev.createdAt) != day;
        final isLast = next == null ||
            _authorKey(next) != _authorKey(message) ||
            _day(next.createdAt) != day;

        return ChatMessageBubble(
          key: ValueKey('chat-msg-${message.id}'),
          message: message,
          isOwnMessage: message.senderId == currentUserId,
          isFirstInGroup: isFirst,
          isLastInGroup: isLast,
          isGroup: isGroup,
        );
      },
    );
  }

  /// Vazio que ensina, rolável (em paisagem com teclado sobra pouca altura).
  Widget _buildEmpty(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final ink = chatInk(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final peer = (peerName ?? '').trim();
    final body = isGroup
        ? 'Escreva no campo abaixo. Todos os participantes do grupo recebem.'
        : peer.isNotEmpty
            ? 'Escreva no campo abaixo para começar a conversa com $peer.'
            : 'Escreva no campo abaixo para começar a conversa.';

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ink.withValues(alpha: isDark ? 0.16 : 0.08),
                    ),
                    child: Icon(
                      LucideIcons.messagesSquare,
                      color: ink,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Nenhuma mensagem ainda',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: ThemeHelpers.textColor(context),
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: secondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
