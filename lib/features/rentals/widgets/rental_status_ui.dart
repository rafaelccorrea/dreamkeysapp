import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/rental_models.dart';

/// Cor semântica do status da locação (verde = ativo, âmbar = pendente /
/// aguardando aprovação, vermelho = expirado, cinza = cancelado) — mesma
/// tabela de `RentalStatusColors` do web, adaptada à paleta do app.
Color rentalStatusColor(BuildContext context, RentalStatus status) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  switch (status) {
    case RentalStatus.active:
      return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    case RentalStatus.pending:
    case RentalStatus.pendingApproval:
      return isDark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;
    case RentalStatus.expired:
      return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    case RentalStatus.cancelled:
    case RentalStatus.unknown:
      return ThemeHelpers.textSecondaryColor(context);
  }
}

IconData rentalStatusIcon(RentalStatus status) {
  switch (status) {
    case RentalStatus.active:
      return LucideIcons.circleCheckBig;
    case RentalStatus.pending:
      return LucideIcons.clock3;
    case RentalStatus.pendingApproval:
      return LucideIcons.hourglass;
    case RentalStatus.expired:
      return LucideIcons.calendarX;
    case RentalStatus.cancelled:
      return LucideIcons.ban;
    case RentalStatus.unknown:
      return LucideIcons.fileText;
  }
}

/// Cor semântica do status da parcela — verde = pago, âmbar = pendente /
/// parcial, vermelho = atrasado, cinza = cancelado.
Color rentalPaymentStatusColor(
    BuildContext context, RentalPaymentStatus status) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  switch (status) {
    case RentalPaymentStatus.paid:
      return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    case RentalPaymentStatus.pending:
      return isDark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;
    case RentalPaymentStatus.partial:
      return isDark
          ? AppColors.status.purpleDarkMode
          : AppColors.status.purple;
    case RentalPaymentStatus.overdue:
      return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    case RentalPaymentStatus.cancelled:
    case RentalPaymentStatus.unknown:
      return ThemeHelpers.textSecondaryColor(context);
  }
}

IconData rentalPaymentStatusIcon(RentalPaymentStatus status) {
  switch (status) {
    case RentalPaymentStatus.paid:
      return LucideIcons.circleCheckBig;
    case RentalPaymentStatus.pending:
      return LucideIcons.clock3;
    case RentalPaymentStatus.partial:
      return LucideIcons.circleDollarSign;
    case RentalPaymentStatus.overdue:
      return LucideIcons.triangleAlert;
    case RentalPaymentStatus.cancelled:
      return LucideIcons.ban;
    case RentalPaymentStatus.unknown:
      return LucideIcons.receipt;
  }
}

/// Pílula de status — tint da cor + texto na cor (mesma gramática do app).
class RentalStatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const RentalStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
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
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
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
