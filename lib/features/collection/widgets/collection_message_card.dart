import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/collection_models.dart';

/// Cor semântica do canal — email = azul, WhatsApp = verde, SMS = roxo.
Color collectionChannelColor(BuildContext context, CollectionChannel channel) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  switch (channel) {
    case CollectionChannel.email:
      return isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    case CollectionChannel.whatsapp:
      return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    case CollectionChannel.sms:
      return isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    case CollectionChannel.unknown:
      return ThemeHelpers.textSecondaryColor(context);
  }
}

IconData collectionChannelIcon(CollectionChannel channel) {
  switch (channel) {
    case CollectionChannel.email:
      return LucideIcons.mail;
    case CollectionChannel.whatsapp:
      return LucideIcons.messageCircle;
    case CollectionChannel.sms:
      return LucideIcons.messageSquareText;
    case CollectionChannel.unknown:
      return LucideIcons.send;
  }
}

/// Cor semântica do status da mensagem — verde = chegou, âmbar = aguardando,
/// vermelho = falhou, azul = enviada (a caminho).
Color collectionStatusColor(
    BuildContext context, CollectionMessageStatus status) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  switch (status) {
    case CollectionMessageStatus.delivered:
    case CollectionMessageStatus.read:
      return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    case CollectionMessageStatus.sent:
      return isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    case CollectionMessageStatus.pending:
    case CollectionMessageStatus.queued:
      return isDark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;
    case CollectionMessageStatus.failed:
    case CollectionMessageStatus.bounced:
      return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    case CollectionMessageStatus.unknown:
      return ThemeHelpers.textSecondaryColor(context);
  }
}

IconData collectionStatusIcon(CollectionMessageStatus status) {
  switch (status) {
    case CollectionMessageStatus.pending:
      return LucideIcons.clock3;
    case CollectionMessageStatus.queued:
      return LucideIcons.hourglass;
    case CollectionMessageStatus.sent:
      return LucideIcons.send;
    case CollectionMessageStatus.delivered:
      return LucideIcons.check;
    case CollectionMessageStatus.read:
      return LucideIcons.checkCheck;
    case CollectionMessageStatus.failed:
      return LucideIcons.circleAlert;
    case CollectionMessageStatus.bounced:
      return LucideIcons.mailX;
    case CollectionMessageStatus.unknown:
      return LucideIcons.circleHelp;
  }
}

/// Item da lista de cobranças — **linha flush** (sem card/sombra), mesmo DNA
/// do CommissionCard: glyph tonal do canal, destinatário + prévia no meio,
/// status + data à direita. Toca para abrir o detalhe.
class CollectionMessageCard extends StatelessWidget {
  final CollectionMessage message;
  final VoidCallback? onTap;

  const CollectionMessageCard({super.key, required this.message, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final channelTone = collectionChannelColor(context, message.channel);
    final statusTone = collectionStatusColor(context, message.status);

    final name = message.recipientName.trim().isNotEmpty
        ? message.recipientName.trim()
        : 'Destinatário';
    final contact = message.contact;
    final preview = (message.subject?.trim().isNotEmpty ?? false)
        ? message.subject!.trim()
        : message.message.trim();
    final dateLabel = _dateLabel();

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
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Glyph tonal do canal.
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  color: channelTone.withValues(alpha: isDark ? 0.16 : 0.1),
                  border:
                      Border.all(color: channelTone.withValues(alpha: 0.28)),
                ),
                child: Icon(collectionChannelIcon(message.channel),
                    color: channelTone, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: _StatusPill(
                            label: message.status.label,
                            icon: collectionStatusIcon(message.status),
                            color: statusTone,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          message.channel.label,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: neutral,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textColor(context),
                        height: 1.2,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (contact != null && contact.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            message.channel == CollectionChannel.email
                                ? LucideIcons.atSign
                                : LucideIcons.phone,
                            size: 12,
                            color: neutral,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              contact,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: neutral,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        preview,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: neutral.withValues(alpha: 0.9),
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (message.status.isFailure &&
                        (message.errorMessage?.trim().isNotEmpty ??
                            false)) ...[
                      const SizedBox(height: 5),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(LucideIcons.circleAlert,
                              size: 12, color: statusTone),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              message.errorMessage!.trim(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: statusTone,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                                height: 1.25,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (dateLabel != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      dateLabel.$1,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: ThemeHelpers.textColor(context),
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      dateLabel.$2,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: neutral,
                        fontWeight: FontWeight.w600,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// (data, hora) da melhor data disponível.
  (String, String)? _dateLabel() {
    final d = message.bestDate?.toLocal();
    if (d == null) return null;
    return (
      DateFormat('dd/MM/yy', 'pt_BR').format(d),
      DateFormat('HH:mm', 'pt_BR').format(d),
    );
  }
}

/// Pílula de status — tint da cor + ícone + texto na cor.
class _StatusPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _StatusPill({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: isDark ? 0.4 : 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 11,
                letterSpacing: -0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
