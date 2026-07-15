// Linha de ranking (a partir do 4º lugar, ou lista completa) — flush, ação e
// destaque no próprio item. "Você" ganha realce no tom da marca.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/theme_helpers.dart';
import 'gamification_ui.dart';

final NumberFormat _pts = NumberFormat.decimalPattern('pt_BR');

class GamRankingTile extends StatelessWidget {
  final int position;
  final String title;
  final String subtitle;
  final int points;

  /// Métricas compactas exibidas sob o nome (ex.: "3 vendas · 5 clientes").
  final String? metrics;
  final bool isMe;

  const GamRankingTile({
    super.key,
    required this.position,
    required this.title,
    required this.subtitle,
    required this.points,
    this.metrics,
    this.isMe = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = gamAccentColor(context);
    final rankTone = gamRankColor(context, position);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final isTop3 = position >= 1 && position <= 3;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: ThemeHelpers.cardShadow(context),
        border: isMe
            ? Border.all(color: accent.withValues(alpha: isDark ? 0.5 : 0.38))
            : null,
      ),
      child: Row(
        children: [
          // Posição
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isTop3
                  ? rankTone.withValues(alpha: isDark ? 0.2 : 0.13)
                  : ThemeHelpers.borderLightColor(context)
                      .withValues(alpha: 0.7),
            ),
            alignment: Alignment.center,
            child: Text(
              '$position',
              style: TextStyle(
                color: isTop3 ? rankTone : secondary,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: textColor,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      GamMiniPill(label: 'Você', color: accent),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  metrics ?? subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondary,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _pts.format(points),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: isMe ? accent : textColor,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
              Text(
                'pontos',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: secondary,
                  fontSize: 9.5,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
