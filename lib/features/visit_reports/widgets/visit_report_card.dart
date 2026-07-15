import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/visit_report_model.dart';

/// Cor semântica do status da assinatura (âmbar = aguardando, verde =
/// assinado, neutro = expirado) — clara/escura conforme o tema.
Color visitStatusColor(BuildContext context, VisitSignatureStatus status) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  switch (status) {
    case VisitSignatureStatus.pending:
      return isDark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;
    case VisitSignatureStatus.signed:
      return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    case VisitSignatureStatus.expired:
    case VisitSignatureStatus.unknown:
      return ThemeHelpers.textSecondaryColor(context);
  }
}

IconData visitStatusIcon(VisitSignatureStatus status) {
  switch (status) {
    case VisitSignatureStatus.pending:
      return LucideIcons.clock3;
    case VisitSignatureStatus.signed:
      return LucideIcons.circleCheck;
    case VisitSignatureStatus.expired:
      return LucideIcons.circleAlert;
    case VisitSignatureStatus.unknown:
      return LucideIcons.clipboardList;
  }
}

/// Item da lista de visitas — **linha flush** (sem card/sombra), mesmo DNA do
/// `CommissionCard`: glyph tonal do status, informação no meio, data à
/// direita e AÇÕES no próprio item (WhatsApp / link / editar / excluir).
class VisitReportCard extends StatelessWidget {
  final VisitReport report;

  /// Mostra o corretor (visão gestão / `scope=all`).
  final bool showBroker;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback? onTap;
  final VoidCallback? onShareWhatsApp;
  final VoidCallback? onCopyLink;
  final VoidCallback? onGenerateLink;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// Uma ação de link está em andamento (mostra progresso no item).
  final bool linkBusy;

  const VisitReportCard({
    super.key,
    required this.report,
    this.showBroker = false,
    this.canEdit = false,
    this.canDelete = false,
    this.onTap,
    this.onShareWhatsApp,
    this.onCopyLink,
    this.onGenerateLink,
    this.onEdit,
    this.onDelete,
    this.linkBusy = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final tone = visitStatusColor(context, report.signatureStatus);
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final blue = isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

    final dateFmt = DateFormat('dd/MM/yy', 'pt_BR');
    final propsCount = report.properties.length;
    final address = report.firstAddress;

    final hasActiveLink = report.hasActiveLink;
    final actions = <Widget>[
      if (!report.isSigned && hasActiveLink && onShareWhatsApp != null)
        _CardAction(
          icon: LucideIcons.messageCircle,
          label: 'WhatsApp',
          color: green,
          busy: linkBusy,
          onTap: onShareWhatsApp!,
        ),
      if (!report.isSigned && hasActiveLink && onCopyLink != null)
        _CardAction(
          icon: LucideIcons.copy,
          label: 'Copiar link',
          color: blue,
          busy: linkBusy,
          onTap: onCopyLink!,
        ),
      if (!report.isSigned && !hasActiveLink && onGenerateLink != null)
        _CardAction(
          icon: LucideIcons.link,
          label: 'Gerar link',
          color: blue,
          busy: linkBusy,
          onTap: onGenerateLink!,
        ),
      if (canEdit && onEdit != null)
        _CardAction(
          icon: LucideIcons.penLine,
          label: 'Editar',
          color: neutral,
          onTap: onEdit!,
        ),
    ];

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Glyph tonal do status da assinatura.
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      color: tone.withValues(alpha: isDark ? 0.16 : 0.1),
                      border: Border.all(color: tone.withValues(alpha: 0.28)),
                    ),
                    child: Icon(visitStatusIcon(report.signatureStatus),
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
                                label: report.signatureStatus.shortLabel,
                                color: tone,
                              ),
                            ),
                            if (hasActiveLink &&
                                report.signatureExpiresAt != null) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'expira ${dateFmt.format(report.signatureExpiresAt!.toLocal())}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: neutral,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          report.clientLabel,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: ThemeHelpers.textColor(context),
                            height: 1.2,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (address != null) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(LucideIcons.mapPin,
                                  size: 12, color: neutral),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  propsCount > 1
                                      ? '$address · +${propsCount - 1} imóve${propsCount - 1 == 1 ? 'l' : 'is'}'
                                      : address,
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
                        if (showBroker &&
                            (report.createdByName ?? '').isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(LucideIcons.userRound,
                                  size: 12, color: neutral),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  report.createdByName!,
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
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Data da visita + contagem de imóveis.
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        report.visitDate != null
                            ? dateFmt.format(report.visitDate!)
                            : '—',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: ThemeHelpers.textColor(context),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$propsCount imóve${propsCount == 1 ? 'l' : 'is'}',
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
              if (actions.isNotEmpty || (canDelete && onDelete != null)) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const SizedBox(width: 56),
                    Expanded(
                      child: Wrap(
                        spacing: 14,
                        runSpacing: 6,
                        children: actions,
                      ),
                    ),
                    if (canDelete && onDelete != null)
                      InkResponse(
                        radius: 18,
                        onTap: onDelete,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(LucideIcons.trash2,
                              size: 16, color: danger.withValues(alpha: 0.85)),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Ação inline do item — ícone + rótulo na cor semântica, sem esconder em menu.
class _CardAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool busy;

  const _CardAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      radius: 22,
      onTap: busy ? null : onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pílula de status — tint da cor + texto na cor (mesma gramática do app).
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
