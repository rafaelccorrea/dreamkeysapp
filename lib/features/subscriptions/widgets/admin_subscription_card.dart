import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../models/subscription_models.dart';
import 'subscription_widgets.dart';

final NumberFormat _money = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 2,
);
final DateFormat _date = DateFormat('dd/MM/yyyy', 'pt_BR');

/// Card de assinatura na gestão master — card sem borda lateral, sombra
/// neutra, status como pill e ação (abrir detalhe) no próprio item.
class AdminSubscriptionCard extends StatelessWidget {
  const AdminSubscriptionCard({
    super.key,
    required this.item,
    required this.onTap,
  });

  final AdminSubscriptionItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final tone = subscriptionStatusColor(context, item.status);

    final endInfo = item.nextBillingDate ?? item.endDate;
    final userLine = [
      if (item.userName.trim().isNotEmpty && item.userName != '—')
        item.userName.trim(),
      if (item.userEmail.trim().isNotEmpty) item.userEmail.trim(),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: ThemeHelpers.cardShadow(context),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      color: tone.withValues(alpha: isDark ? 0.18 : 0.1),
                    ),
                    child: Icon(
                      planTypeIcon(item.planType),
                      color: tone,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.planName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: ThemeHelpers.textColor(context),
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SubsStatusPill(status: item.status, compact: true),
                          ],
                        ),
                        if (userLine.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(LucideIcons.userRound,
                                  size: 12, color: secondary),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  userLine,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: secondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            Text(
                              '${_money.format(item.price)}/mês',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: ThemeHelpers.textColor(context),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (endInfo != null) ...[
                              const SizedBox(width: 10),
                              Icon(LucideIcons.calendarClock,
                                  size: 12, color: secondary),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  _date.format(endInfo.toLocal()),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: secondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Icon(
                      LucideIcons.chevronRight,
                      size: 17,
                      color: secondary.withValues(alpha: 0.7),
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
