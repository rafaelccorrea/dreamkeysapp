import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/property_service.dart';
import 'approval_lazy_thumbnail.dart';

/// Tipo de fila a que o card pertence.
enum ApprovalQueueKind {
  myAvailability,
  myOwnerAuth,
  myPublication,
  pendingAvailability,
  pendingPublication,
  pendingOwnerAuth,
  rejectedAvailability,
  rejectedPublication,
}

enum _Urgency { fresh, warming, hot }

/// Item da fila de aprovação — usa `ShellVisualTokens.inlineTileDecoration`,
/// raio 16, ícone-broche em badge gradiente accent (padrão `_buildSummaryCard`
/// do dashboard) e tipografia da casa (Poppins via tema, eyebrow `labelSmall`
/// `w900` com `letterSpacing`, título `titleSmall` `w900`).
class ApprovalPropertyCard extends StatelessWidget {
  final Property property;
  final ApprovalQueueKind kind;

  final bool canApproveAvailability;
  final bool canRejectAvailability;
  final bool canApprovePublication;
  final bool canRejectPublication;
  final bool isResponsibleForProperty;
  final bool actionInProgress;

  final VoidCallback? onOpenDetails;
  final VoidCallback? onApproveAvailability;
  final VoidCallback? onRejectAvailability;
  final VoidCallback? onApprovePublication;
  final VoidCallback? onRejectPublication;
  final VoidCallback? onResendAvailability;
  final VoidCallback? onResendPublication;

  const ApprovalPropertyCard({
    super.key,
    required this.property,
    required this.kind,
    this.canApproveAvailability = false,
    this.canRejectAvailability = false,
    this.canApprovePublication = false,
    this.canRejectPublication = false,
    this.isResponsibleForProperty = false,
    this.actionInProgress = false,
    this.onOpenDetails,
    this.onApproveAvailability,
    this.onRejectAvailability,
    this.onApprovePublication,
    this.onRejectPublication,
    this.onResendAvailability,
    this.onResendPublication,
  });

  bool get _isAvailabilityFlow =>
      kind == ApprovalQueueKind.pendingAvailability ||
      kind == ApprovalQueueKind.myAvailability ||
      kind == ApprovalQueueKind.rejectedAvailability;

  bool get _isPublicationFlow =>
      kind == ApprovalQueueKind.pendingPublication ||
      kind == ApprovalQueueKind.myPublication ||
      kind == ApprovalQueueKind.rejectedPublication;

  bool get _isOwnerAuthFlow =>
      kind == ApprovalQueueKind.myOwnerAuth ||
      kind == ApprovalQueueKind.pendingOwnerAuth;

  bool get _isRejectedQueue =>
      kind == ApprovalQueueKind.rejectedAvailability ||
      kind == ApprovalQueueKind.rejectedPublication;

  bool get _availabilityRejectedWaitingResend =>
      _isAvailabilityFlow &&
      property.status == PropertyStatus.pendingApproval &&
      (property.availabilityRejectedAt ?? '').isNotEmpty;

  bool get _publicationRejectedWaitingResend =>
      _isPublicationFlow &&
      (property.publicationRejectedAt ?? '').isNotEmpty;

  bool get _isInRejectedState =>
      _isRejectedQueue ||
      _availabilityRejectedWaitingResend ||
      _publicationRejectedWaitingResend;

  DateTime? _waitingSince() {
    final raw = _isPublicationFlow
        ? property.publicationRequestedAt
        : property.updatedAt;
    if (raw == null || raw.isEmpty) return null;
    try {
      return DateTime.parse(raw).toLocal();
    } catch (_) {
      return null;
    }
  }

  String _formatRelativeTime(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inMinutes < 60) return '${diff.inMinutes}min';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 30) return '${diff.inDays}d';
    return DateFormat('dd/MM/yy', 'pt_BR').format(when);
  }

  _Urgency _urgencyFor(DateTime? when) {
    if (when == null || _isInRejectedState) return _Urgency.fresh;
    final diff = DateTime.now().difference(when);
    if (diff.inDays >= 7) return _Urgency.hot;
    if (diff.inHours >= 48) return _Urgency.warming;
    return _Urgency.fresh;
  }

  Color _statusColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_isInRejectedState) {
      return isDark
          ? AppColors.status.errorDarkMode
          : AppColors.status.error;
    }
    final u = _urgencyFor(_waitingSince());
    switch (u) {
      case _Urgency.hot:
        return isDark
            ? AppColors.status.errorDarkMode
            : AppColors.status.error;
      case _Urgency.warming:
        return isDark
            ? AppColors.status.warningDarkMode
            : AppColors.status.warning;
      case _Urgency.fresh:
        if (_isOwnerAuthFlow) {
          return isDark
              ? AppColors.status.purpleDarkMode
              : AppColors.status.purple;
        }
        return isDark
            ? AppColors.status.greenDarkMode
            : AppColors.status.green;
    }
  }

  String _statusLabel() {
    if (_availabilityRejectedWaitingResend) return 'Recusado · reenvie';
    if (_publicationRejectedWaitingResend) return 'Publicação recusada';
    if (_isRejectedQueue) {
      return kind == ApprovalQueueKind.rejectedAvailability
          ? 'Disponibilidade recusada'
          : 'Publicação recusada';
    }
    if (_isOwnerAuthFlow) return 'Aguarda proprietário';
    if (_isAvailabilityFlow) return 'Aguarda disponibilidade';
    if (_isPublicationFlow) return 'Aguarda publicação';
    return 'Pendente';
  }

  IconData _statusIcon() {
    if (_isInRejectedState) return LucideIcons.alertTriangle;
    if (_isOwnerAuthFlow) return LucideIcons.fileSignature;
    if (_isPublicationFlow) return LucideIcons.globe;
    return LucideIcons.shieldCheck;
  }

  String? _rejectionReason() {
    if (_isAvailabilityFlow) {
      final r = property.availabilityRejectionReason?.trim();
      if (r != null && r.isNotEmpty) return r;
    }
    if (_isPublicationFlow) {
      final r = property.publicationRejectionReason?.trim();
      if (r != null && r.isNotEmpty) return r;
    }
    return null;
  }

  String _priceLabel() {
    final f =
        NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 0);
    final parts = <String>[];
    if (property.salePrice != null && property.salePrice! > 0) {
      parts.add('Venda ${f.format(property.salePrice)}');
    }
    if (property.rentPrice != null && property.rentPrice! > 0) {
      parts.add('Aluguel ${f.format(property.rentPrice)}/mês');
    }
    return parts.join(' · ');
  }

  String _addressLabel() {
    final pieces = <String>[];
    if (property.neighborhood.isNotEmpty) pieces.add(property.neighborhood);
    if (property.city.isNotEmpty) pieces.add(property.city);
    return pieces.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
    final ok = isDark
        ? AppColors.status.greenDarkMode
        : AppColors.status.green;
    final danger = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final statusColor = _statusColor(context);

    final imageUrl = property.mainImage?.thumbnailUrl ??
        property.mainImage?.url ??
        (property.images != null && property.images!.isNotEmpty
            ? (property.images!.first.thumbnailUrl ??
                property.images!.first.url)
            : null);

    final reason = _rejectionReason();
    final since = _waitingSince();
    final timeLabel = since == null ? '' : _formatRelativeTime(since);

    final card = Container(
      decoration: _feedItemDecoration(context, statusColor: statusColor),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildThumbnail(context,
                    imageUrl: imageUrl,
                    statusColor: statusColor,
                    neutral: neutral),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (property.code != null &&
                              property.code!.isNotEmpty)
                            Expanded(
                              child: Text(
                                'CÓD ${property.code!}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: neutral,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.4,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            )
                          else
                            const Spacer(),
                          if (timeLabel.isNotEmpty)
                            _TimePill(label: timeLabel, color: statusColor),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        property.title.isEmpty
                            ? 'Sem título'
                            : property.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: ThemeHelpers.textColor(context),
                          height: 1.18,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_addressLabel().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(LucideIcons.mapPin,
                                size: 13, color: neutral),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _addressLabel(),
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
                      if (_priceLabel().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          _priceLabel(),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: ThemeHelpers.textColor(context),
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _StatusPill(
                  label: _statusLabel(),
                  color: statusColor,
                ),
                if (property.bedrooms != null && property.bedrooms! > 0)
                  _MetaPill(
                    icon: LucideIcons.bedDouble,
                    label: '${property.bedrooms}',
                  ),
                if (property.bathrooms != null && property.bathrooms! > 0)
                  _MetaPill(
                    icon: LucideIcons.bath,
                    label: '${property.bathrooms}',
                  ),
                if (property.parkingSpaces != null &&
                    property.parkingSpaces! > 0)
                  _MetaPill(
                    icon: LucideIcons.car,
                    label: '${property.parkingSpaces}',
                  ),
                if (property.totalArea > 0)
                  _MetaPill(
                    icon: LucideIcons.maximize2,
                    label: '${property.totalArea.toStringAsFixed(0)}m²',
                  ),
                if (property.capturedBy != null &&
                    property.capturedBy!.name.isNotEmpty)
                  _AvatarPill(
                    name: property.capturedBy!.name,
                    accent: accent,
                  ),
              ],
            ),
            if (reason != null) ...[
              const SizedBox(height: 10),
              _ReasonBlock(reason: reason, danger: danger),
            ],
            const SizedBox(height: 12),
            _buildActionRow(context, ok: ok, danger: danger, accent: accent),
          ],
        ),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpenDetails,
          splashColor: accent.withValues(alpha: 0.10),
          highlightColor: accent.withValues(alpha: 0.05),
          child: card,
        ),
      ),
    );
  }

  /// Decoração "feed item" — mais leve que `inlineTileDecoration`, sem
  /// gradientes nem sombras duplas. Pensada para conviver direto sobre o
  /// gradiente do shell (sem painel pai), com presença visual sutil e uma
  /// linha discreta na cor do status para identidade.
  BoxDecoration _feedItemDecoration(
    BuildContext context, {
    required Color statusColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      color: ThemeHelpers.cardBackgroundColor(context),
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : ThemeHelpers.borderColor(context).withValues(alpha: 0.32),
        width: 1,
      ),
      boxShadow: isDark
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 14,
                offset: const Offset(0, 6),
                spreadRadius: -4,
              ),
            ]
          : [
              BoxShadow(
                color: statusColor.withValues(alpha: 0.05),
                blurRadius: 14,
                offset: const Offset(0, 6),
                spreadRadius: -6,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 8,
                offset: const Offset(0, 3),
                spreadRadius: -3,
              ),
            ],
    );
  }

  Widget _buildThumbnail(
    BuildContext context, {
    required String? imageUrl,
    required Color statusColor,
    required Color neutral,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ApprovalLazyThumbnail(
          propertyId: property.id,
          initialUrl: imageUrl,
          size: 84,
          radius: 14,
        ),
        Positioned(
          right: -6,
          top: -6,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ThemeHelpers.cardBackgroundColor(context),
              border: Border.all(
                color: statusColor.withValues(alpha: 0.55),
                width: 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.32),
                  blurRadius: 8,
                  spreadRadius: -2,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(_statusIcon(), size: 14, color: statusColor),
          ),
        ),
      ],
    );
  }

  Widget _buildActionRow(
    BuildContext context, {
    required Color ok,
    required Color danger,
    required Color accent,
  }) {
    final theme = Theme.of(context);
    final actions = <Widget>[];

    if (kind == ApprovalQueueKind.pendingAvailability ||
        kind == ApprovalQueueKind.myAvailability) {
      if (_availabilityRejectedWaitingResend) {
        if (canApproveAvailability && onResendAvailability != null) {
          actions.add(_GhostButton(
            label: 'Reabrir análise',
            icon: LucideIcons.rotateCcw,
            color: accent,
            onTap: actionInProgress ? null : onResendAvailability,
          ));
        } else if (isResponsibleForProperty && onResendAvailability != null) {
          actions.add(_GhostButton(
            label: 'Reenviar',
            icon: LucideIcons.send,
            color: accent,
            onTap: actionInProgress ? null : onResendAvailability,
          ));
        }
      } else {
        if (canRejectAvailability && onRejectAvailability != null) {
          actions.add(_GhostButton(
            label: 'Recusar',
            icon: LucideIcons.xCircle,
            color: danger,
            onTap: actionInProgress ? null : onRejectAvailability,
          ));
        }
        if (canApproveAvailability && onApproveAvailability != null) {
          actions.add(_PrimaryButton(
            label: 'Aprovar',
            icon: LucideIcons.checkCircle2,
            color: ok,
            loading: actionInProgress,
            onTap: actionInProgress ? null : onApproveAvailability,
          ));
        }
      }
    } else if (kind == ApprovalQueueKind.pendingPublication ||
        kind == ApprovalQueueKind.myPublication) {
      if (_publicationRejectedWaitingResend) {
        if (canApprovePublication && onResendPublication != null) {
          actions.add(_GhostButton(
            label: 'Reabrir análise',
            icon: LucideIcons.rotateCcw,
            color: accent,
            onTap: actionInProgress ? null : onResendPublication,
          ));
        } else if (isResponsibleForProperty && onResendPublication != null) {
          actions.add(_GhostButton(
            label: 'Reenviar',
            icon: LucideIcons.send,
            color: accent,
            onTap: actionInProgress ? null : onResendPublication,
          ));
        }
      } else {
        if (canRejectPublication && onRejectPublication != null) {
          actions.add(_GhostButton(
            label: 'Recusar',
            icon: LucideIcons.xCircle,
            color: danger,
            onTap: actionInProgress ? null : onRejectPublication,
          ));
        }
        if (canApprovePublication && onApprovePublication != null) {
          actions.add(_PrimaryButton(
            label: 'Aprovar',
            icon: LucideIcons.checkCircle2,
            color: ok,
            loading: actionInProgress,
            onTap: actionInProgress ? null : onApprovePublication,
          ));
        }
      }
    } else if (kind == ApprovalQueueKind.rejectedAvailability) {
      if (canApproveAvailability && onResendAvailability != null) {
        actions.add(_GhostButton(
          label: 'Reabrir análise',
          icon: LucideIcons.rotateCcw,
          color: accent,
          onTap: actionInProgress ? null : onResendAvailability,
        ));
      } else if (isResponsibleForProperty && onResendAvailability != null) {
        actions.add(_GhostButton(
          label: 'Reenviar',
          icon: LucideIcons.send,
          color: accent,
          onTap: actionInProgress ? null : onResendAvailability,
        ));
      }
    } else if (kind == ApprovalQueueKind.rejectedPublication) {
      if (canApprovePublication && onResendPublication != null) {
        actions.add(_GhostButton(
          label: 'Reabrir análise',
          icon: LucideIcons.rotateCcw,
          color: accent,
          onTap: actionInProgress ? null : onResendPublication,
        ));
      } else if (isResponsibleForProperty && onResendPublication != null) {
        actions.add(_GhostButton(
          label: 'Reenviar',
          icon: LucideIcons.send,
          color: accent,
          onTap: actionInProgress ? null : onResendPublication,
        ));
      }
    }

    // Sem ações disponíveis: hint "Toque para abrir" + chevron — o card
    // inteiro é tappable (InkWell no `build`), então o botão dedicado de
    // "Ver detalhes" foi removido para evitar duplicidade e overflow em
    // telas estreitas.
    if (actions.isEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            'Toque para abrir',
            style: theme.textTheme.labelMedium?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            LucideIcons.chevronRight,
            size: 16,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
        ],
      );
    }

    // Wrap permite que botões "respirem" para a linha de baixo em telas
    // muito estreitas em vez de estourar a Row.
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: actions,
    );
  }
}

// ─── Subwidgets ─────────────────────────────────────────────────────────

class _TimePill extends StatelessWidget {
  final String label;
  final Color color;
  const _TimePill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.clock, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
          ),
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final neutral = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.045)
            : Colors.black.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: neutral),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _AvatarPill extends StatelessWidget {
  final String name;
  final Color accent;
  const _AvatarPill({required this.name, required this.accent});

  String get _initial =>
      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

  String _firstName() {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '';
    return parts.first;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(3, 3, 10, 3),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.045)
            : Colors.black.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [accent, const Color(0xFF7C3AED)],
              ),
            ),
            child: Text(
              _initial,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 11,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _firstName(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w700,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _ReasonBlock extends StatelessWidget {
  final String reason;
  final Color danger;
  const _ReasonBlock({required this.reason, required this.danger});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: danger.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: danger.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.alertTriangle, size: 16, color: danger),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textColor(context),
                  height: 1.35,
                ),
                children: [
                  TextSpan(
                    text: 'MOTIVO  ',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: danger,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  TextSpan(text: reason),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool loading;

  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.1,
            ),
      ),
      icon: loading
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _GhostButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: color.withValues(alpha: 0.55)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}
