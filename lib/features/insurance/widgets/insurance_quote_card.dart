import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/insurance_models.dart';

final NumberFormat _money = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 2,
);

/// Card de resultado de cotação — sem borda lateral, sombra neutra
/// (`ThemeHelpers.cardShadow`), cor da seguradora só como sinal (monograma e
/// filete no rodapé). Seleção marcada pela borda no tom da marca do app.
class InsuranceQuoteCard extends StatelessWidget {
  final InsuranceQuote quote;
  final bool selected;
  final bool isBestPrice;
  final VoidCallback onTap;

  const InsuranceQuoteCard({
    super.key,
    required this.quote,
    required this.selected,
    required this.isBestPrice,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final brand = quote.provider.brandColor;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected
              ? accent.withValues(alpha: isDark ? 0.75 : 0.6)
              : ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
          width: selected ? 1.6 : 1,
        ),
        boxShadow: ThemeHelpers.cardShadow(context,
            strength: selected ? 1.4 : 1),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          splashColor: accent.withValues(alpha: 0.08),
          highlightColor: accent.withValues(alpha: 0.04),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Monograma da seguradora (logo não disponível no app).
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        color: brand.withValues(alpha: isDark ? 0.2 : 0.12),
                        border: Border.all(
                          color: brand.withValues(alpha: 0.35),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        quote.provider.monogram,
                        style: TextStyle(
                          color: brand,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            quote.provider.label,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: textColor,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Seguro fiança locatícia',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: secondary,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isBestPrice)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: green.withValues(alpha: isDark ? 0.18 : 0.1),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: green.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.trendingDown,
                                size: 11, color: green),
                            const SizedBox(width: 4),
                            Text(
                              'MELHOR PREÇO',
                              style: TextStyle(
                                color: green,
                                fontWeight: FontWeight.w900,
                                fontSize: 9,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (selected)
                      Icon(LucideIcons.circleCheckBig,
                          size: 20, color: accent),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PRÊMIO MENSAL',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: secondary,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                              fontSize: 9.5,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    _money.format(quote.monthlyPremium),
                                    style:
                                        theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: textColor,
                                      letterSpacing: -0.5,
                                      height: 1.0,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  '/mês',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: secondary,
                                    fontWeight: FontWeight.w600,
                                    height: 1.0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'COBERTURA',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: secondary,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            fontSize: 9.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _money.format(quote.coverageAmount),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: textColor,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Filete da marca da seguradora — sinal sutil, não banner.
                Container(
                  height: 2.5,
                  width: 26,
                  decoration: BoxDecoration(
                    color: brand.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(2),
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
