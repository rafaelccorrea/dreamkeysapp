import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/rental_models.dart';
import 'rental_status_ui.dart';

final NumberFormat _money = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 2,
);

/// Ações disponíveis no menu do item da lista.
enum RentalCardAction { details, payments, edit, approve, reject, delete }

/// Item da lista de locações — **linha flush** (sem card/sombra), coerente com
/// o DNA do app: thumb do imóvel (ou glyph tonal), inquilino + imóvel +
/// período no meio, valor mensal à direita e ações no próprio item.
class RentalCard extends StatelessWidget {
  final Rental rental;
  final VoidCallback? onTap;
  final void Function(RentalCardAction action)? onAction;
  final bool canManageWorkflows;
  final bool canManagePayments;
  final bool canUpdate;
  final bool canDelete;

  const RentalCard({
    super.key,
    required this.rental,
    this.onTap,
    this.onAction,
    this.canManageWorkflows = false,
    this.canManagePayments = false,
    this.canUpdate = false,
    this.canDelete = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final tone = rentalStatusColor(context, rental.status);
    final fmt = DateFormat('dd/MM/yy', 'pt_BR');

    final propertyTitle =
        rental.property?.title.trim().isNotEmpty == true
            ? rental.property!.title.trim()
            : 'Imóvel não especificado';
    final period = rental.startDate != null && rental.endDate != null
        ? '${fmt.format(rental.startDate!.toLocal())} → ${fmt.format(rental.endDate!.toLocal())}'
        : null;

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
              _buildThumb(context, tone, isDark),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: RentalStatusPill(
                            label: rental.status.label,
                            color: tone,
                            icon: rentalStatusIcon(rental.status),
                          ),
                        ),
                        if (rental.isExpiringSoon) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: RentalStatusPill(
                              label: 'Vence em breve',
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? AppColors.status.warningDarkMode
                                  : AppColors.status.warning,
                              icon: LucideIcons.calendarClock,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      rental.tenantName.trim().isNotEmpty
                          ? rental.tenantName.trim()
                          : 'Inquilino não especificado',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textColor(context),
                        height: 1.2,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(LucideIcons.house, size: 12, color: neutral),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            rental.property?.code != null &&
                                    rental.property!.code!.isNotEmpty
                                ? '$propertyTitle · CÓD ${rental.property!.code}'
                                : propertyTitle,
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
                    if (period != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(LucideIcons.calendarRange,
                              size: 12, color: neutral),
                          const SizedBox(width: 4),
                          Text(
                            period,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: neutral,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(LucideIcons.calendarDays,
                              size: 12, color: neutral),
                          const SizedBox(width: 4),
                          Text(
                            'Venc. dia ${rental.dueDay}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: neutral,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _money.format(rental.monthlyValue),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: rental.status == RentalStatus.active
                          ? tone
                          : ThemeHelpers.textColor(context),
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    '/mês',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: neutral,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                  if (onAction != null) _buildMenu(context, neutral),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumb(BuildContext context, Color tone, bool isDark) {
    final url = rental.property?.mainImageUrl;
    if (url != null && url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Image.network(
          url,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _glyph(tone, isDark),
        ),
      );
    }
    return _glyph(tone, isDark);
  }

  Widget _glyph(Color tone, bool isDark) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        color: tone.withValues(alpha: isDark ? 0.16 : 0.1),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
      ),
      child: Icon(LucideIcons.keyRound, color: tone, size: 21),
    );
  }

  Widget _buildMenu(BuildContext context, Color neutral) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final showApproval = rental.isPendingApproval && canManageWorkflows;

    return PopupMenuButton<RentalCardAction>(
      tooltip: 'Ações',
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      color: ThemeHelpers.cardBackgroundColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: ThemeHelpers.borderLightColor(context)),
      ),
      icon: Icon(LucideIcons.ellipsisVertical, size: 18, color: neutral),
      onSelected: (a) => onAction?.call(a),
      itemBuilder: (ctx) => [
        if (showApproval) ...[
          _item(ctx, RentalCardAction.approve, LucideIcons.check, 'Aprovar',
              color: green),
          _item(ctx, RentalCardAction.reject, LucideIcons.x, 'Rejeitar',
              color: danger),
        ],
        _item(ctx, RentalCardAction.details, LucideIcons.eye, 'Ver detalhes'),
        if (canManagePayments)
          _item(ctx, RentalCardAction.payments, LucideIcons.wallet,
              'Pagamentos'),
        if (canUpdate)
          _item(ctx, RentalCardAction.edit, LucideIcons.pencil, 'Editar'),
        if (canDelete)
          _item(ctx, RentalCardAction.delete, LucideIcons.trash2, 'Excluir',
              color: danger),
      ],
    );
  }

  PopupMenuItem<RentalCardAction> _item(
    BuildContext context,
    RentalCardAction action,
    IconData icon,
    String label, {
    Color? color,
  }) {
    final fg = color ?? ThemeHelpers.textColor(context);
    return PopupMenuItem<RentalCardAction>(
      value: action,
      height: 42,
      child: Row(
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    );
  }
}
