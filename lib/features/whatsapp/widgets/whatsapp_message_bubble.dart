import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/whatsapp_models.dart';
import 'whatsapp_conversation_card.dart' show whatsAppMessageTypeIcon;

/// Bolha de mensagem do WhatsApp — mesma gramática visual do chat interno
/// (bolha 18/4, enviada na cor da marca com texto branco, recebida em card),
/// com as particularidades do WhatsApp: mídia (imagem/áudio/documento),
/// ticks de status, origem (oficial/QR) e marcação de resposta da IA.
class WhatsAppMessageBubble extends StatelessWidget {
  final WhatsAppMessage message;

  const WhatsAppMessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isOwn = message.isOutbound;
    final isAi = isOwn && message.isAiResponse;
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final purple =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;

    // IA responde "pelo sistema", mas com identidade própria (tint violeta,
    // texto normal) para o SDR distinguir num relance o que foi automático.
    final Color bubbleColor;
    final Color textColor;
    final Color metaColor;
    if (isAi) {
      bubbleColor = purple.withValues(alpha: isDark ? 0.16 : 0.1);
      textColor = ThemeHelpers.textColor(context);
      metaColor = ThemeHelpers.textSecondaryColor(context);
    } else if (isOwn) {
      bubbleColor = accent;
      textColor = Colors.white;
      metaColor = Colors.white70;
    } else {
      bubbleColor = ThemeHelpers.cardBackgroundColor(context);
      textColor = ThemeHelpers.textColor(context);
      metaColor = ThemeHelpers.textSecondaryColor(context);
    }

    final text = (message.message ?? '').trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            isOwn ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isOwn) const SizedBox(width: 48),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isOwn ? 18 : 4),
                  bottomRight: Radius.circular(isOwn ? 4 : 18),
                ),
                boxShadow: ThemeHelpers.cardShadow(context, strength: 0.5),
                border: isOwn && !isAi
                    ? null
                    : Border.all(
                        color: isAi
                            ? purple.withValues(alpha: isDark ? 0.4 : 0.28)
                            : ThemeHelpers.borderLightColor(context),
                        width: 0.8,
                      ),
              ),
              child: Column(
                crossAxisAlignment:
                    isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Autor: IA (bot) ou usuário do sistema que enviou.
                  if (isAi)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.bot, size: 12, color: purple),
                          const SizedBox(width: 4),
                          Text(
                            'Assistente IA',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: purple,
                              fontWeight: FontWeight.w900,
                              fontSize: 10.5,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (isOwn && (message.userName ?? '').trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        message.userName!.trim(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white70,
                          fontWeight: FontWeight.w800,
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                  if (message.messageType.isMedia) ...[
                    _buildMedia(context, theme, isOwn, isAi, metaColor),
                    if (text.isNotEmpty) const SizedBox(height: 7),
                  ],
                  if (text.isNotEmpty)
                    SelectableText(
                      text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: textColor,
                        height: 1.38,
                      ),
                    ),
                  const SizedBox(height: 4),
                  _buildMetaRow(context, theme, metaColor, isOwn),
                ],
              ),
            ),
          ),
          if (!isOwn) const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildMedia(BuildContext context, ThemeData theme, bool isOwn,
      bool isAi, Color metaColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Imagem com URL assinada (válida ~1h) — preview clicável não é
    // necessário aqui; erro cai num placeholder discreto.
    if (message.messageType == WhatsAppMessageType.image &&
        message.mediaUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 230, maxHeight: 260),
          child: Image.network(
            message.mediaUrl!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => _mediaFallback(
              context,
              metaColor,
              icon: LucideIcons.image,
              label: 'Imagem indisponível',
              hint: 'O link desta mídia expirou.',
              isOwn: isOwn,
              isAi: isAi,
            ),
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Container(
                width: 210,
                height: 150,
                color: (isDark ? Colors.white : Colors.black)
                    .withValues(alpha: 0.06),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: metaColor,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    // Demais mídias: chip com ícone do tipo + nome do arquivo (quando houver).
    final fileName = (message.mediaFileName ?? '').trim();
    return _mediaFallback(
      context,
      metaColor,
      icon: whatsAppMessageTypeIcon(message.messageType),
      label: message.messageType.label,
      hint: fileName.isNotEmpty ? fileName : 'Abra no painel para visualizar.',
      isOwn: isOwn,
      isAi: isAi,
    );
  }

  Widget _mediaFallback(
    BuildContext context,
    Color metaColor, {
    required IconData icon,
    required String label,
    required String hint,
    required bool isOwn,
    required bool isAi,
  }) {
    final theme = Theme.of(context);
    final solidOwn = isOwn && !isAi;
    final bg = solidOwn
        ? Colors.white.withValues(alpha: 0.16)
        : ThemeHelpers.backgroundColor(context);
    final border = solidOwn
        ? Colors.white.withValues(alpha: 0.28)
        : ThemeHelpers.borderLightColor(context);
    final fg = solidOwn ? Colors.white : ThemeHelpers.textColor(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: solidOwn ? Colors.white : metaColor),
          const SizedBox(width: 9),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  hint,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: solidOwn ? Colors.white70 : metaColor,
                    fontWeight: FontWeight.w500,
                    fontSize: 10.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaRow(
      BuildContext context, ThemeData theme, Color metaColor, bool isOwn) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final time = message.createdAt != null
        ? DateFormat('HH:mm').format(message.createdAt!.toLocal())
        : '';
    final failed = message.status == WhatsAppMessageStatus.failed;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Origem da mensagem (oficial × QR) — sinal minúsculo, só quando vem.
        if (message.integrationSource != WhatsAppIntegrationSource.unknown) ...[
          Icon(
            message.integrationSource == WhatsAppIntegrationSource.official
                ? LucideIcons.badgeCheck
                : LucideIcons.qrCode,
            size: 10.5,
            color: metaColor,
          ),
          const SizedBox(width: 4),
        ],
        Text(
          time,
          style: theme.textTheme.labelSmall?.copyWith(
            color: metaColor,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (isOwn) ...[
          const SizedBox(width: 4),
          if (failed)
            Icon(LucideIcons.triangleAlert, size: 12, color: danger)
          else
            Icon(
              message.status == WhatsAppMessageStatus.pending
                  ? LucideIcons.clock3
                  : message.status == WhatsAppMessageStatus.sent
                      ? LucideIcons.check
                      : LucideIcons.checkCheck,
              size: 12.5,
              color: message.status == WhatsAppMessageStatus.read
                  ? (isDark
                      ? AppColors.status.blueDarkMode
                      : const Color(0xFF7EC8FF))
                  : metaColor,
            ),
        ],
        if (failed) ...[
          const SizedBox(width: 4),
          Text(
            'Falhou',
            style: theme.textTheme.labelSmall?.copyWith(
              color: danger,
              fontWeight: FontWeight.w800,
              fontSize: 10,
            ),
          ),
        ],
      ],
    );
  }
}

/// Separador de dia na thread — chip central discreto.
class WhatsAppDaySeparator extends StatelessWidget {
  final DateTime date;

  const WhatsAppDaySeparator({super.key, required this.date});

  String get _label {
    final local = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Hoje';
    if (diff == 1) return 'Ontem';
    return DateFormat("d 'de' MMMM", 'pt_BR').format(local);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context)
                .withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: ThemeHelpers.borderLightColor(context)),
          ),
          child: Text(
            _label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w800,
              fontSize: 10.5,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}
