import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../whatsapp/widgets/whatsapp_conversation_card.dart'
    show WhatsAppAvatar;
import '../models/chat_models.dart';
import 'chat_visual.dart';

/// Bolha de mensagem do chat interno (30/09/2026) — a gramática do WhatsApp
/// do app, no azul do chat interno:
/// - enviada em azul suave com texto de alto contraste; recebida em
///   superfície neutra com filete (antes: vermelho sólido com texto branco e
///   sombra difusa, que o modo claro não usa);
/// - mensagens seguidas da mesma pessoa se juntam (2dp entre elas) e a
///   "cauda" fica só na última do bloco;
/// - em grupo, o nome de quem escreveu na primeira do bloco e o avatar na
///   última; em conversa direta, sem avatar (só há uma outra pessoa);
/// - hora e confirmação de leitura dentro da bolha, no canto de baixo;
/// - figurinha/GIF do web (URL solta do GIPHY) vira imagem, mensagem apagada
///   vira "Mensagem apagada" e aviso do sistema vira faixa central sem
///   itálico.
class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isOwnMessage;

  /// Primeira/última bolha de uma sequência da mesma pessoa.
  final bool isFirstInGroup;
  final bool isLastInGroup;

  /// Conversa em grupo: mostra nome e avatar de quem escreveu.
  final bool isGroup;

  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.isOwnMessage,
    this.isFirstInGroup = true,
    this.isLastInGroup = true,
    this.isGroup = false,
  });

  static const double _avatarSize = 28;

  @override
  Widget build(BuildContext context) {
    if (message.isSystemMessage == true) return _buildSystem(context);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final own = isOwnMessage;
    final ink = chatInk(context);

    final Color bubbleColor;
    final Color borderColor;
    if (own) {
      bubbleColor = isDark
          ? Color.alphaBlend(
              ink.withValues(alpha: 0.26),
              AppColors.background.cardBackgroundDarkMode,
            )
          : Color.alphaBlend(ink.withValues(alpha: 0.12), Colors.white);
      borderColor = ink.withValues(alpha: isDark ? 0.30 : 0.20);
    } else {
      bubbleColor = isDark
          ? Color.alphaBlend(
              Colors.white.withValues(alpha: 0.075),
              AppColors.background.cardBackgroundDarkMode,
            )
          : Colors.white;
      borderColor = ThemeHelpers.borderColor(context);
    }

    const r = Radius.circular(18);
    const rMid = Radius.circular(7);
    const rTail = Radius.circular(4);
    final radius = own
        ? BorderRadius.only(
            topLeft: r,
            bottomLeft: r,
            topRight: isFirstInGroup ? r : rMid,
            bottomRight: isLastInGroup ? rTail : rMid,
          )
        : BorderRadius.only(
            topRight: r,
            bottomRight: r,
            topLeft: isFirstInGroup ? r : rMid,
            bottomLeft: isLastInGroup ? rTail : rMid,
          );

    final gifUrl = message.isDeleted || message.hasAttachment
        ? null
        : chatInlineGifUrl(message.content);
    final stickerUrl =
        gifUrl != null && chatIsSticker(gifUrl) ? gifUrl : null;

    final showAuthor = isGroup && !own && isFirstInGroup;
    final showAvatarSlot = isGroup && !own;

    Widget content;
    if (stickerUrl != null) {
      // Figurinha: sem bolha, como no WhatsApp; a hora vai numa etiqueta.
      content = Column(
        crossAxisAlignment:
            own ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showAuthor) _author(context),
          _gifImage(context, stickerUrl, maxSide: 150, radius: 0),
          const SizedBox(height: 3),
          _meta(context, onMedia: true),
        ],
      );
    } else {
      content = Container(
        padding: gifUrl != null
            ? const EdgeInsets.all(4)
            : const EdgeInsets.fromLTRB(12, 8, 12, 6),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: radius,
          border: Border.all(color: borderColor, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showAuthor)
              Padding(
                padding: gifUrl != null
                    ? const EdgeInsets.fromLTRB(8, 4, 8, 4)
                    : EdgeInsets.zero,
                child: _author(context),
              ),
            if (message.isDeleted)
              _deleted(context)
            else if (gifUrl != null) ...[
              _gifImage(context, gifUrl, maxSide: 220, radius: 14),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 6, 2),
                child: _metaAtEnd(context),
              ),
            ] else ...[
              if (message.hasAttachment) ...[
                _buildAttachment(context),
                const SizedBox(height: 6),
              ],
              _textWithMeta(context),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: isLastInGroup ? 8 : 2),
      child: Row(
        mainAxisAlignment:
            own ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (own) const SizedBox(width: 48),
          if (showAvatarSlot) ...[
            if (isLastInGroup)
              WhatsAppAvatar(
                name: message.senderName,
                imageUrl: message.senderAvatar,
                size: _avatarSize,
              )
            else
              const SizedBox(width: _avatarSize),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Opacity(
              opacity: message.isPending == true ? 0.72 : 1.0,
              child: content,
            ),
          ),
          if (!own) const SizedBox(width: 48),
        ],
      ),
    );
  }

  // ─── Peças ───────────────────────────────────────────────────────────────

  Widget _author(BuildContext context) {
    final name = message.senderName.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Text(
        name.isEmpty ? 'Participante' : name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: ThemeHelpers.textColor(context),
          fontWeight: FontWeight.w800,
          fontSize: 12.5,
          letterSpacing: -0.1,
        ),
      ),
    );
  }

  /// Texto com a hora "flutuando" na última linha: se couber, fica na mesma
  /// linha, à direita; se não, desce para a linha de baixo, à direita.
  Widget _textWithMeta(BuildContext context) {
    final text = message.content.trim();
    if (text.isEmpty) return _metaAtEnd(context);
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 8,
      runSpacing: 2,
      children: [
        SelectableText(
          text,
          style: TextStyle(
            color: ThemeHelpers.textColor(context),
            fontSize: 15,
            fontWeight: FontWeight.w400,
            height: 1.35,
            letterSpacing: -0.1,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 1),
          child: _meta(context),
        ),
      ],
    );
  }

  Widget _deleted(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 2,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.ban, size: 14, color: secondary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Mensagem apagada',
                style: TextStyle(
                  color: secondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        _meta(context),
      ],
    );
  }

  /// Hora no canto de baixo à direita quando não há texto para "flutuar"
  /// junto (anexo ou GIF sem legenda). A bolha já é larga pelo anexo.
  Widget _metaAtEnd(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [_meta(context)],
    );
  }

  /// Hora + confirmação (enviada) + "editada".
  Widget _meta(BuildContext context, {bool onMedia = false}) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final ink = chatInk(context);
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.isEdited && !message.isDeleted) ...[
          Text(
            'editada',
            style: TextStyle(
              color: secondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
        ],
        Text(
          chatBubbleTime(message.createdAt),
          style: TextStyle(
            color: secondary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            height: 1.1,
          ),
        ),
        if (isOwnMessage) ...[
          const SizedBox(width: 3),
          Icon(
            _statusIcon(message.status),
            size: 13,
            color: message.status == ChatMessageStatus.read ? ink : secondary,
          ),
        ],
      ],
    );
    if (!onMedia) return row;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: chatFieldFill(context),
        borderRadius: BorderRadius.circular(999),
      ),
      child: row,
    );
  }

  Widget _gifImage(
    BuildContext context,
    String url, {
    required double maxSide,
    required double radius,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxSide, maxHeight: maxSide),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.network(
          url,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stack) =>
              _mediaUnavailable(context, 'Imagem indisponível'),
        ),
      ),
    );
  }

  Widget _mediaUnavailable(BuildContext context, String label) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: chatFieldFill(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.imageOff, size: 18, color: secondary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: secondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystem(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: chatFieldFill(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            chatPreviewText(message.content),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: secondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(String? url) async {
    if (url == null || url.isEmpty) return;
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('[CHAT_MESSAGE] Erro ao abrir anexo: $e');
    }
  }

  /// Tipo do arquivo em palavra curta ("PDF", "DOCX") — nunca o MIME cru
  /// ("application/vnd.openxmlformats-…").
  String? _fileKind() {
    final name = (message.attachmentName ?? '').trim();
    final dot = name.lastIndexOf('.');
    if (dot > 0 && dot < name.length - 1) {
      final ext = name.substring(dot + 1);
      if (ext.length <= 5) return ext.toUpperCase();
    }
    final mime = (message.documentMimeType ?? message.fileType ?? '').trim();
    final slash = mime.lastIndexOf('/');
    final sub = slash >= 0 ? mime.substring(slash + 1) : mime;
    if (sub.isNotEmpty && sub.length <= 5) return sub.toUpperCase();
    return null;
  }

  Widget _buildAttachment(BuildContext context) {
    final url = message.attachmentUrl;
    final isImage = message.imageUrl != null;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final ink = chatInk(context);

    if (isImage && url != null) {
      // Quadrado que acompanha a largura da bolha (máx. 220): a largura fixa
      // de 200 estourava em grupo a 320dp (avatar + margem + bolha).
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Material(
              color: chatFieldFill(context),
              child: InkWell(
                onTap: () => _open(url),
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) => Center(
                    child: _mediaUnavailable(context, 'Imagem indisponível'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final name = (message.attachmentName ?? '').trim();
    final kind = _fileKind();
    return Material(
      color: chatFieldFill(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _open(url),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.fileText, size: 24, color: ink),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name.isEmpty ? 'Arquivo' : name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ThemeHelpers.textColor(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      kind == null
                          ? 'Toque para abrir'
                          : '$kind · toque para abrir',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: secondary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(LucideIcons.download, size: 18, color: secondary),
            ],
          ),
        ),
      ),
    );
  }

  IconData _statusIcon(ChatMessageStatus status) {
    switch (status) {
      case ChatMessageStatus.sending:
        return LucideIcons.clock3;
      case ChatMessageStatus.sent:
        return LucideIcons.check;
      case ChatMessageStatus.delivered:
      case ChatMessageStatus.read:
        return LucideIcons.checkCheck;
    }
  }
}
