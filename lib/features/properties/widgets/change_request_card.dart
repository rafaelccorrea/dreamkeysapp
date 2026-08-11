import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/property_change_request.dart';
import 'approval_actions_sheet.dart';

/// Linha **flush** de uma solicitação de alteração de campos protegidos
/// (aba "Edições"). Sem card dentro de card: separação por hairline, diff em
/// linhas "antes → depois" e as ações do revisor no próprio item.
class ChangeRequestCard extends StatefulWidget {
  final PropertyChangeRequest request;

  /// `canReview` do envelope da API — fonte da verdade para aprovar/recusar.
  final bool canReview;
  final VoidCallback? onOpenProperty;

  /// Retornam `true` em sucesso (o item encerra o carregamento).
  final Future<bool> Function()? onApprove;
  final Future<bool> Function()? onReject;

  const ChangeRequestCard({
    super.key,
    required this.request,
    required this.canReview,
    this.onOpenProperty,
    this.onApprove,
    this.onReject,
  });

  @override
  State<ChangeRequestCard> createState() => _ChangeRequestCardState();
}

class _ChangeRequestCardState extends State<ChangeRequestCard> {
  bool _busy = false;
  bool _expanded = false;

  PropertyChangeRequest get req => widget.request;

  Color _statusColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (req.status) {
      case PropertyChangeRequestStatus.approved:
        return kApprovalGreen;
      case PropertyChangeRequestStatus.rejected:
        return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
      case PropertyChangeRequestStatus.pending:
        return isDark
            ? AppColors.status.warningDarkMode
            : AppColors.status.warning;
    }
  }

  Future<void> _run(Future<bool> Function()? action) async {
    if (action == null || _busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _fmt(DateTime? d) => d == null
      ? '—'
      : DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(d.toLocal());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final statusColor = _statusColor(context);
    final title = req.property?.title.isNotEmpty == true
        ? req.property!.title
        : 'Imóvel removido';
    final code = req.property?.code;
    final visibleChanges =
        _expanded ? req.changes : req.changes.take(3).toList();
    final showActions =
        widget.canReview && req.isPending && !(widget.onApprove == null);

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  color: statusColor.withValues(alpha: isDark ? 0.18 : 0.10),
                ),
                child: Icon(
                  LucideIcons.squarePen,
                  size: 16,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(
                                alpha: isDark ? 0.16 : 0.10,
                              ),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: statusColor.withValues(
                                  alpha: isDark ? 0.4 : 0.3,
                                ),
                              ),
                            ),
                            child: Text(
                              req.status.label.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.w900,
                                fontSize: 10,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ),
                        if (req.hasConflict && req.isPending) ...[
                          const SizedBox(width: 8),
                          Icon(
                            LucideIcons.alertTriangle,
                            size: 14,
                            color: danger,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: widget.onOpenProperty,
                      child: Text(
                        code == null || code.isEmpty
                            ? title
                            : '$title ($code)',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: ThemeHelpers.textColor(context),
                          height: 1.2,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Solicitado por ${req.requestedBy?.name ?? '—'} · ${_fmt(req.createdAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.onOpenProperty != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  onPressed: widget.onOpenProperty,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Abrir imóvel',
                  icon: Icon(
                    LucideIcons.chevronRight,
                    size: 18,
                    color: secondary.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          ),
          if (req.changes.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final c in visibleChanges) _diffRow(context, c),
            if (req.changes.length > 3)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  style: TextButton.styleFrom(
                    foregroundColor: secondary,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  child: Text(
                    _expanded
                        ? 'Ver menos'
                        : 'Ver todos os ${req.changes.length} campos',
                  ),
                ),
              ),
          ],
          if (req.hasConflict && req.isPending) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.alertTriangle, size: 13, color: danger),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'O imóvel mudou depois da solicitação — confira o valor atual antes de aprovar.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: danger,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (!req.isPending) ...[
            const SizedBox(height: 8),
            Text(
              [
                'Revisado por ${req.reviewedBy?.name ?? '—'}',
                _fmt(req.reviewedAt),
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(color: secondary),
            ),
            if ((req.rejectionReason ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Motivo: ${req.rejectionReason}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: danger,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
          ],
          if (showActions) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _run(widget.onReject),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: danger,
                      side: BorderSide(color: danger.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    icon: const Icon(LucideIcons.xCircle, size: 16),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Recusar'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _run(widget.onApprove),
                    style: FilledButton.styleFrom(
                      backgroundColor: kApprovalGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(LucideIcons.checkCircle2, size: 16),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Aprovar'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _diffRow(BuildContext context, ChangeRequestFieldDiff c) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final before = c.format(c.oldValue, req.userNames);
    final after = c.format(c.newValue, req.userNames);
    final current = c.format(c.currentValue, req.userNames);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c.label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: secondary,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  before,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondary,
                    decoration: TextDecoration.lineThrough,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Icon(LucideIcons.arrowRight, size: 13, color: secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  after,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: kApprovalGreen,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (c.changedSinceRequest) ...[
            const SizedBox(height: 3),
            Text(
              'Hoje no imóvel: $current',
              style: theme.textTheme.labelSmall?.copyWith(
                color: danger,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
