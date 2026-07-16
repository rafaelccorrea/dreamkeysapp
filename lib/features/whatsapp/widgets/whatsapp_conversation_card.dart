import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/whatsapp_models.dart';

/// Ícone semântico do tipo de mensagem (usado no preview da conversa e nas
/// bolhas de mídia).
IconData whatsAppMessageTypeIcon(WhatsAppMessageType type) {
  switch (type) {
    case WhatsAppMessageType.text:
      return LucideIcons.messageSquareText;
    case WhatsAppMessageType.image:
      return LucideIcons.image;
    case WhatsAppMessageType.video:
      return LucideIcons.video;
    case WhatsAppMessageType.audio:
    case WhatsAppMessageType.voice:
      return LucideIcons.mic;
    case WhatsAppMessageType.document:
      return LucideIcons.fileText;
    case WhatsAppMessageType.location:
      return LucideIcons.mapPin;
    case WhatsAppMessageType.contact:
      return LucideIcons.circleUserRound;
    case WhatsAppMessageType.sticker:
      return LucideIcons.sticker;
    case WhatsAppMessageType.unknown:
      return LucideIcons.messageCircle;
  }
}

/// Ícone da origem de integração — API oficial (Meta) × QR Code (Baileys).
IconData whatsAppSourceIcon(WhatsAppIntegrationSource source) {
  switch (source) {
    case WhatsAppIntegrationSource.official:
      return LucideIcons.badgeCheck;
    case WhatsAppIntegrationSource.unofficial:
      return LucideIcons.qrCode;
    case WhatsAppIntegrationSource.unknown:
      return LucideIcons.messageCircle;
  }
}

// ─── Avatar (foto → iniciais sobre cor derivada do nome) ────────────────────

/// Paleta de avatares — mesma ideia do WhatsApp/Contatos do iOS: cor estável
/// derivada do nome, iniciais brancas. Pares (light, dark).
const List<(Color, Color)> _avatarTones = [
  (Color(0xFF3FA66B), Color(0xFF4FC77D)), // verde
  (Color(0xFF4A90E2), Color(0xFF5C9DE8)), // azul
  (Color(0xFF8B5CF6), Color(0xFFA78BFA)), // violeta
  (Color(0xFFD98E2B), Color(0xFFE0A04A)), // âmbar queimado
  (Color(0xFFD95B84), Color(0xFFE0779A)), // rosa
  (Color(0xFF2BA8A0), Color(0xFF45C4BC)), // teal
  (Color(0xFF5C6BC0), Color(0xFF7986CB)), // índigo
  (Color(0xFF7A8699), Color(0xFF94A3B8)), // ardósia
];

/// Cor estável derivada do nome/telefone do contato.
Color whatsAppAvatarColor(String seed, bool isDark) {
  var hash = 0;
  for (final unit in seed.trim().toLowerCase().codeUnits) {
    hash = (hash * 31 + unit) & 0x7FFFFFFF;
  }
  final tone = _avatarTones[hash % _avatarTones.length];
  return isDark ? tone.$2 : tone.$1;
}

/// Iniciais do contato (até 2 letras) — nomes numéricos (telefone) viram
/// ícone de pessoa no [WhatsAppAvatar].
String _initialsOf(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && RegExp(r'^[a-zA-ZÀ-ÿ]').hasMatch(w))
      .toList();
  if (words.isEmpty) return '';
  if (words.length == 1) return words.first[0].toUpperCase();
  return (words.first[0] + words.last[0]).toUpperCase();
}

/// Avatar circular estilo WhatsApp iOS: FOTO do contato quando existir;
/// fallback em iniciais brancas sobre cor derivada do nome (estável). Se a
/// imagem falhar (URL assinada expirada), cai no fallback sem quebrar.
class WhatsAppAvatar extends StatefulWidget {
  final String? imageUrl;
  final String name;
  final double size;

  const WhatsAppAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 52,
  });

  @override
  State<WhatsAppAvatar> createState() => _WhatsAppAvatarState();
}

class _WhatsAppAvatarState extends State<WhatsAppAvatar> {
  bool _imageFailed = false;

  @override
  void didUpdateWidget(covariant WhatsAppAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) _imageFailed = false;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final url = (widget.imageUrl ?? '').trim();
    final hasImage = url.isNotEmpty && !_imageFailed;
    final tone = whatsAppAvatarColor(
      widget.name.isEmpty ? '?' : widget.name,
      isDark,
    );
    final initials = _initialsOf(widget.name);

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: hasImage
              ? null
              : LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.lerp(tone, Colors.white, 0.12)!,
                    tone,
                  ],
                ),
        ),
        child: hasImage
            ? ClipOval(
                child: Image.network(
                  url,
                  width: widget.size,
                  height: widget.size,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && !_imageFailed) {
                        setState(() => _imageFailed = true);
                      }
                    });
                    return const SizedBox.shrink();
                  },
                ),
              )
            : Center(
                child: initials.isEmpty
                    ? Icon(
                        LucideIcons.user,
                        color: Colors.white,
                        size: widget.size * 0.48,
                      )
                    : Text(
                        initials,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: widget.size * 0.36,
                          letterSpacing: 0.2,
                          height: 1.0,
                        ),
                      ),
              ),
      ),
    );
  }
}

// ─── Linha de conversa (estilo WhatsApp para iPhone) ─────────────────────────

/// Item da lista de conversas — linha estilo **WhatsApp para iPhone**:
/// avatar circular grande com foto (fallback: iniciais sobre cor derivada do
/// nome), nome em alto contraste, prévia da última mensagem em cinza com
/// prefixo "Você:" nas enviadas, hora à direita (verde quando há não lidas) e
/// badge verde circular de não lidas. Separador hairline indentado à esquerda
/// do texto — nunca sob o avatar.
class WhatsAppConversationCard extends StatelessWidget {
  final WhatsAppConversation conversation;
  final VoidCallback? onTap;

  const WhatsAppConversationCard({
    super.key,
    required this.conversation,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hasUnread = conversation.hasUnread;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: WhatsAppAvatar(
                name: conversation.displayName,
                imageUrl: conversation.lastMessage?.contactAvatarUrl,
                size: 52,
              ),
            ),
            // O hairline pertence à coluna de texto: começa depois do avatar.
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: ThemeHelpers.borderLightColor(context),
                      width: 0.8,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            conversation.displayName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: ThemeHelpers.textColor(context),
                              letterSpacing: -0.3,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _timeLabel(conversation.effectiveLastMessageAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: hasUnread ? green : secondary,
                            fontWeight:
                                hasUnread ? FontWeight.w700 : FontWeight.w500,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3.5),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: _buildPreview(context, secondary)),
                        const SizedBox(width: 8),
                        _buildTrailing(context, green, secondary, isDark),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(BuildContext context, Color secondary) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final last = conversation.lastMessage;
    final hasUnread = conversation.hasUnread;
    final previewColor = hasUnread
        ? ThemeHelpers.textColor(context).withValues(alpha: 0.9)
        : secondary;

    if (last == null) {
      return Text(
        conversation.formattedPhone,
        style: TextStyle(
          fontSize: 14,
          color: secondary,
          fontWeight: FontWeight.w500,
          height: 1.3,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final prefix = last.isOutbound ? (last.isAiResponse ? 'IA: ' : 'Você: ') : '';

    return Row(
      children: [
        if (last.isOutbound) ...[
          Icon(
            last.status == WhatsAppMessageStatus.read ||
                    last.status == WhatsAppMessageStatus.delivered
                ? LucideIcons.checkCheck
                : LucideIcons.check,
            size: 14.5,
            color: last.status == WhatsAppMessageStatus.read
                ? (isDark ? AppColors.status.blueDarkMode : AppColors.status.blue)
                : secondary,
          ),
          const SizedBox(width: 3.5),
        ],
        if (last.messageType.isMedia) ...[
          Icon(
            whatsAppMessageTypeIcon(last.messageType),
            size: 13.5,
            color: previewColor,
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Text(
            '$prefix${last.preview}',
            style: TextStyle(
              fontSize: 14,
              color: previewColor,
              fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
              height: 1.3,
              letterSpacing: -0.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// Direita da segunda linha: badge verde de não lidas (números brancos) ou,
  /// sem pendência, sinais discretos (canal, IA, negociação) em cinza.
  Widget _buildTrailing(
      BuildContext context, Color green, Color secondary, bool isDark) {
    if (conversation.hasUnread) {
      return Container(
        constraints: const BoxConstraints(minWidth: 21),
        height: 21,
        padding: const EdgeInsets.symmetric(horizontal: 6.5),
        decoration: BoxDecoration(
          color: green,
          borderRadius: BorderRadius.circular(999),
        ),
        alignment: Alignment.center,
        child: Text(
          conversation.unreadCount > 99 ? '99+' : '${conversation.unreadCount}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 11.5,
            height: 1.0,
          ),
        ),
      );
    }

    final last = conversation.lastMessage;
    final muted = secondary.withValues(alpha: 0.65);
    final purple =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    final icons = <Widget>[];

    final source = last?.integrationSource ?? WhatsAppIntegrationSource.unknown;
    if (source != WhatsAppIntegrationSource.unknown) {
      icons.add(Icon(whatsAppSourceIcon(source), size: 13.5, color: muted));
    }
    if (last?.isAiResponse == true) {
      icons.add(Icon(LucideIcons.bot,
          size: 13.5, color: purple.withValues(alpha: 0.8)));
    }
    if (conversation.hasTask) {
      icons.add(Icon(LucideIcons.clipboardList, size: 13.5, color: muted));
    }
    if (icons.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < icons.length; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          icons[i],
        ],
      ],
    );
  }

  static String _timeLabel(DateTime? date) {
    if (date == null) return '';
    final local = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return DateFormat('HH:mm').format(local);
    if (diff == 1) return 'Ontem';
    if (diff < 7) {
      // "segunda-feira" → "Segunda" (compacto, como o dia por extenso do iOS).
      final wd = DateFormat('EEEE', 'pt_BR').format(local).split('-').first;
      return wd.isEmpty ? '' : wd[0].toUpperCase() + wd.substring(1);
    }
    return DateFormat('dd/MM/yy').format(local);
  }
}
