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

/// Item da lista de conversas — **linha flush** (sem card/sombra), mesmo DNA
/// do CommissionCard: avatar tonal, contato + preview no meio, hora + badge
/// de não lidas à direita. Toca para abrir a thread.
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
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final purple =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    final blue = isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;

    final hasUnread = conversation.hasUnread;
    final tone = hasUnread ? green : neutral;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAvatar(context, accent, green, hasUnread, isDark),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            conversation.displayName,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight:
                                  hasUnread ? FontWeight.w900 : FontWeight.w800,
                              color: ThemeHelpers.textColor(context),
                              letterSpacing: -0.2,
                              height: 1.15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _timeLabel(conversation.effectiveLastMessageAt),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: hasUnread ? green : neutral,
                            fontWeight:
                                hasUnread ? FontWeight.w900 : FontWeight.w700,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(child: _buildPreview(context, theme, neutral)),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: green,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              conversation.unreadCount > 99
                                  ? '99+'
                                  : '${conversation.unreadCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 10.5,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    _buildMetaChips(
                        context, theme, tone, blue, purple, green, isDark),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, Color accent, Color green,
      bool hasUnread, bool isDark) {
    final avatarUrl = conversation.lastMessage?.contactAvatarUrl;
    final initial = conversation.displayName.trim().isNotEmpty
        ? conversation.displayName.trim()[0].toUpperCase()
        : '?';
    final ring = hasUnread ? green : Colors.transparent;

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ring.withValues(alpha: 0.65), width: 1.6),
      ),
      child: CircleAvatar(
        radius: 22,
        backgroundColor: accent.withValues(alpha: isDark ? 0.2 : 0.1),
        backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
        child: avatarUrl == null
            ? Text(
                initial,
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildPreview(BuildContext context, ThemeData theme, Color neutral) {
    final last = conversation.lastMessage;
    final hasUnread = conversation.hasUnread;
    final textColor = hasUnread
        ? ThemeHelpers.textColor(context).withValues(alpha: 0.92)
        : neutral;

    if (last == null) {
      return Text(
        conversation.formattedPhone,
        style: theme.textTheme.bodySmall?.copyWith(
          color: neutral,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Row(
      children: [
        if (last.isOutbound) ...[
          Icon(
            last.status == WhatsAppMessageStatus.read ||
                    last.status == WhatsAppMessageStatus.delivered
                ? LucideIcons.checkCheck
                : LucideIcons.check,
            size: 13,
            color: last.status == WhatsAppMessageStatus.read
                ? (Theme.of(context).brightness == Brightness.dark
                    ? AppColors.status.blueDarkMode
                    : AppColors.status.blue)
                : neutral,
          ),
          const SizedBox(width: 4),
        ],
        if (last.messageType.isMedia) ...[
          Icon(whatsAppMessageTypeIcon(last.messageType),
              size: 13, color: neutral),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Text(
            last.preview,
            style: theme.textTheme.bodySmall?.copyWith(
              color: textColor,
              fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
              height: 1.25,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildMetaChips(BuildContext context, ThemeData theme, Color tone,
      Color blue, Color purple, Color green, bool isDark) {
    final last = conversation.lastMessage;
    final chips = <Widget>[];

    // Origem: oficial × QR Code — só quando conhecida.
    final source = last?.integrationSource ?? WhatsAppIntegrationSource.unknown;
    if (source != WhatsAppIntegrationSource.unknown) {
      chips.add(_MetaChip(
        icon: whatsAppSourceIcon(source),
        label: source.label,
        color: source == WhatsAppIntegrationSource.official ? blue : purple,
        isDark: isDark,
      ));
    }

    // SDR responsável.
    final assigned = (last?.assignedToName ?? '').trim();
    if (assigned.isNotEmpty) {
      chips.add(_MetaChip(
        icon: LucideIcons.headset,
        label: _firstName(assigned),
        color: green,
        isDark: isDark,
      ));
    }

    // Pré-atendimento da IA.
    if (last?.isAiResponse == true) {
      chips.add(_MetaChip(
        icon: LucideIcons.bot,
        label: 'IA',
        color: purple,
        isDark: isDark,
      ));
    }

    // Negociação criada no CRM.
    if (conversation.hasTask) {
      chips.add(_MetaChip(
        icon: LucideIcons.clipboardList,
        label: 'Negociação',
        color: ThemeHelpers.textSecondaryColor(context),
        isDark: isDark,
      ));
    }

    if (chips.isEmpty) {
      return Text(
        conversation.formattedPhone,
        style: theme.textTheme.labelSmall?.copyWith(
          color: ThemeHelpers.textSecondaryColor(context)
              .withValues(alpha: 0.85),
          fontWeight: FontWeight.w600,
          fontSize: 10.5,
        ),
      );
    }

    return Wrap(spacing: 6, runSpacing: 4, children: chips);
  }

  static String _firstName(String name) {
    final t = name.trim();
    if (t.isEmpty) return '—';
    final i = t.indexOf(' ');
    return i == -1 ? t : t.substring(0, i);
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
      final wd = DateFormat('EEE', 'pt_BR').format(local);
      return wd.replaceAll('.', '');
    }
    return DateFormat('dd/MM/yy').format(local);
  }
}

/// Chip compacto de metadado — tint + texto na cor (nunca sólido).
class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;

  const _MetaChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: isDark ? 0.35 : 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10.5, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 10,
              height: 1.2,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}
