import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/whatsapp_models.dart';
import 'whatsapp_conversation_card.dart' show whatsAppMessageTypeIcon;

/// Bolha de mensagem — estilo **WhatsApp para iPhone**:
/// - enviada em verde suave (verde semântico do tema) com texto de alto
///   contraste; recebida em superfície neutra que destaca do fundo;
/// - cantos contínuos assimétricos com "cauda" só na última bolha do grupo;
/// - horário pequeno dentro da bolha, no canto inferior direito, com ticks
///   de entrega/leitura nas enviadas;
/// - agrupamento de mensagens sequenciais do mesmo remetente (margens
///   menores, autor só na primeira do grupo);
/// - resposta da IA mantém identidade violeta discreta (rótulo), sem sair da
///   gramática de bolha verde de saída.
class WhatsAppMessageBubble extends StatelessWidget {
  final WhatsAppMessage message;

  /// Primeira/última bolha de uma sequência do mesmo remetente — controla
  /// cantos, cauda e o rótulo de autor.
  final bool isFirstInGroup;
  final bool isLastInGroup;

  const WhatsAppMessageBubble({
    super.key,
    required this.message,
    this.isFirstInGroup = true,
    this.isLastInGroup = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isOwn = message.isOutbound;
    final isAi = isOwn && message.isAiResponse;
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final purple =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;

    // Verde suave sólido (sem translucidez empilhada) para a saída; superfície
    // neutra clara acima do fundo para a entrada — contraste alto nos 2 temas.
    final Color bubbleColor;
    final Color borderColor;
    if (isOwn) {
      bubbleColor = isDark
          ? Color.alphaBlend(
              green.withValues(alpha: 0.30),
              AppColors.background.cardBackgroundDarkMode,
            )
          : Color.alphaBlend(green.withValues(alpha: 0.16), Colors.white);
      borderColor = green.withValues(alpha: isDark ? 0.26 : 0.22);
    } else {
      bubbleColor = isDark
          ? Color.alphaBlend(
              Colors.white.withValues(alpha: 0.075),
              AppColors.background.cardBackgroundDarkMode,
            )
          : Colors.white;
      borderColor = isDark
          ? Colors.white.withValues(alpha: 0.07)
          : Colors.black.withValues(alpha: 0.05);
    }
    final textColor = ThemeHelpers.textColor(context);
    final metaColor =
        ThemeHelpers.textSecondaryColor(context).withValues(alpha: 0.85);

    final text = (message.message ?? '').trim();

    // Cantos contínuos: lado do remetente "fecha" entre bolhas do grupo e a
    // cauda (canto de 4) aparece só na última.
    const r = Radius.circular(18);
    const rMid = Radius.circular(7);
    const rTail = Radius.circular(4);
    final radius = isOwn
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

    final showAiLabel = isAi && isFirstInGroup;
    final userName = (message.userName ?? '').trim();
    final showAuthor = !isAi && isOwn && userName.isNotEmpty && isFirstInGroup;

    return Padding(
      padding: EdgeInsets.only(bottom: isLastInGroup ? 10 : 2),
      child: Row(
        mainAxisAlignment:
            isOwn ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isOwn) const SizedBox(width: 52),
          Flexible(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: radius,
                border: Border.all(color: borderColor, width: 0.8),
                boxShadow: isDark
                    ? null
                    : ThemeHelpers.cardShadow(context, strength: 0.35),
              ),
              child: Column(
                // Fim (direita) para o horário assentar no canto da bolha,
                // como no WhatsApp — o bloco de texto continua lido à esquerda.
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showAiLabel)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.bot, size: 12, color: purple),
                          const SizedBox(width: 4),
                          Text(
                            'Assistente IA',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: purple,
                              fontWeight: FontWeight.w800,
                              fontSize: 10.5,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (showAuthor)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        userName,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: green,
                          fontWeight: FontWeight.w800,
                          fontSize: 10.5,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  if (message.messageType.isMedia) ...[
                    _buildMedia(context, theme, metaColor),
                    if (text.isNotEmpty) const SizedBox(height: 6),
                  ],
                  if (text.isNotEmpty)
                    SelectableText(
                      text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: textColor,
                        fontSize: 15,
                        height: 1.35,
                        letterSpacing: -0.1,
                      ),
                    ),
                  const SizedBox(height: 2),
                  _buildMetaRow(context, theme, metaColor, isOwn),
                ],
              ),
            ),
          ),
          if (!isOwn) const SizedBox(width: 52),
        ],
      ),
    );
  }

  Widget _buildMedia(BuildContext context, ThemeData theme, Color metaColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Imagem com URL assinada (válida ~1h) — erro cai num placeholder.
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
    );
  }

  Widget _mediaFallback(
    BuildContext context,
    Color metaColor, {
    required IconData icon,
    required String label,
    required String hint,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = (isDark ? Colors.white : Colors.black)
        .withValues(alpha: isDark ? 0.07 : 0.045);
    final border = (isDark ? Colors.white : Colors.black)
        .withValues(alpha: isDark ? 0.10 : 0.06);

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
          Icon(icon, size: 20, color: metaColor),
          const SizedBox(width: 9),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  hint,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: metaColor,
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

  /// Horário + ticks no canto inferior direito da bolha (como no WhatsApp).
  Widget _buildMetaRow(
      BuildContext context, ThemeData theme, Color metaColor, bool isOwn) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final time = message.createdAt != null
        ? DateFormat('HH:mm').format(message.createdAt!.toLocal())
        : '';
    final failed = message.status == WhatsAppMessageStatus.failed;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final readBlue =
        isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          time,
          style: theme.textTheme.labelSmall?.copyWith(
            color: metaColor,
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            height: 1.2,
          ),
        ),
        if (isOwn) ...[
          const SizedBox(width: 3.5),
          if (failed)
            Icon(LucideIcons.triangleAlert, size: 12, color: danger)
          else
            Icon(
              message.status == WhatsAppMessageStatus.pending
                  ? LucideIcons.clock3
                  : message.status == WhatsAppMessageStatus.sent
                      ? LucideIcons.check
                      : LucideIcons.checkCheck,
              size: 13,
              color: message.status == WhatsAppMessageStatus.read
                  ? readBlue
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

/// Separador de dia na thread — chip central discreto (estilo iOS).
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
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.black.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            _label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w700,
              fontSize: 10.5,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}
