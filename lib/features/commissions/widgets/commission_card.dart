import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/commission_model.dart';

final NumberFormat _money = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 2,
);

/// Cor semântica do status (clara/escura conforme tema).
Color commissionStatusColor(BuildContext context, CommissionStatus status) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  switch (status) {
    case CommissionStatus.paid:
      return isDark ? AppColors.status.successDarkMode : AppColors.status.success;
    case CommissionStatus.approved:
      return isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    case CommissionStatus.pending:
      return isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    case CommissionStatus.cancelled:
    case CommissionStatus.unknown:
      return ThemeHelpers.textSecondaryColor(context);
  }
}

IconData commissionTypeIcon(CommissionType type) {
  switch (type) {
    case CommissionType.sale:
      return LucideIcons.home;
    case CommissionType.rental:
      return LucideIcons.key;
    case CommissionType.management:
      return LucideIcons.building2;
    case CommissionType.unknown:
      return LucideIcons.receipt;
  }
}

/// Item da lista de comissões — **linha flush** (sem card/sombra), coerente
/// com o DNA do app: glyph tonal do tipo, info no meio e valor líquido à
/// direita. Toca para abrir o detalhe.
class CommissionCard extends StatelessWidget {
  final Commission commission;
  final VoidCallback? onTap;

  const CommissionCard({super.key, required this.commission, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final tone = commissionStatusColor(context, commission.status);

    final title = commission.title.trim().isNotEmpty
        ? commission.title.trim()
        : (commission.clientName?.trim().isNotEmpty == true
            ? commission.clientName!.trim()
            : 'Comissão');
    final property = commission.propertyLabel;
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
              // Glyph tonal do tipo da comissão.
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  color: tone.withValues(alpha: isDark ? 0.16 : 0.1),
                  border: Border.all(color: tone.withValues(alpha: 0.28)),
                ),
                child: Icon(commissionTypeIcon(commission.type),
                    color: tone, size: 21),
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
                            label: commission.status.label,
                            color: tone,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          commission.type.label,
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
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textColor(context),
                        height: 1.2,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (property != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(LucideIcons.mapPin, size: 12, color: neutral),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              commission.propertyCode != null &&
                                      commission.propertyCode!.isNotEmpty
                                  ? '$property · CÓD ${commission.propertyCode}'
                                  : property,
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
                    if (commission.clientName != null &&
                        commission.clientName!.trim().isNotEmpty &&
                        title != commission.clientName!.trim()) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(LucideIcons.user, size: 12, color: neutral),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              commission.clientName!.trim(),
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
                    // Memória de cálculo: base + percentual (líquido fica à
                    // direita). Dá a "matemática" da comissão num relance.
                    if (commission.baseValue > 0 ||
                        commission.percentage > 0) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 3,
                        children: [
                          if (commission.baseValue > 0)
                            _SpecBit(
                              icon: LucideIcons.wallet,
                              text: 'Base ${_money.format(commission.baseValue)}',
                              color: neutral,
                            ),
                          if (commission.percentage > 0)
                            _SpecBit(
                              icon: LucideIcons.percent,
                              text:
                                  '${commission.percentage.toStringAsFixed(commission.percentage % 1 == 0 ? 0 : 2).replaceAll('.', ',')}%',
                              color: neutral,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Valor líquido + data.
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _money.format(commission.netValue),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: commission.isPaid
                          ? tone
                          : ThemeHelpers.textColor(context),
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (dateLabel != null)
                    Text(
                      dateLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: neutral,
                        fontWeight: FontWeight.w700,
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

  String? _dateLabel() {
    final fmt = DateFormat('dd/MM/yy', 'pt_BR');
    if (commission.isPaid && commission.paidAt != null) {
      return 'Pago ${fmt.format(commission.paidAt!.toLocal())}';
    }
    if (commission.expectedPaymentDate != null) {
      return 'Prev. ${fmt.format(commission.expectedPaymentDate!.toLocal())}';
    }
    if (commission.createdAt != null) {
      return fmt.format(commission.createdAt!.toLocal());
    }
    return null;
  }
}

/// Mini-item de metadado (ícone + texto compacto) — base, percentual, etc.
class _SpecBit extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _SpecBit({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: color,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

/// Pílula de status — tint da cor + texto na cor.
class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

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
    );
  }
}
