import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/property_service.dart';
import 'approval_lazy_thumbnail.dart';

/// Tipo de fila a que o item pertence.
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

/// Item da fila de aprovação — **linha flush** (sem card/sombra): faixa de
/// status à esquerda, thumbnail, info e chevron. Toca para abrir os detalhes,
/// onde ficam as ações de aprovar/reprovar (integradas ao layout).
class ApprovalPropertyCard extends StatelessWidget {
  final Property property;
  final ApprovalQueueKind kind;
  final VoidCallback? onOpenDetails;

  const ApprovalPropertyCard({
    super.key,
    required this.property,
    required this.kind,
    this.onOpenDetails,
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
      _isPublicationFlow && (property.publicationRejectedAt ?? '').isNotEmpty;

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
      return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    }
    switch (_urgencyFor(_waitingSince())) {
      case _Urgency.hot:
        return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
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
        return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
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

  String _priceLabel() {
    final f = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
      decimalDigits: 0,
    );
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
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final statusColor = _statusColor(context);

    final imageUrl = property.mainImage?.thumbnailUrl ??
        property.mainImage?.url ??
        (property.images != null && property.images!.isNotEmpty
            ? (property.images!.first.thumbnailUrl ??
                property.images!.first.url)
            : null);

    final since = _waitingSince();
    final timeLabel = since == null ? '' : _formatRelativeTime(since);
    final price = _priceLabel();
    final address = _addressLabel();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpenDetails,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Faixa de status (identidade da linha) — vermelho/âmbar/verde/roxo.
                Container(width: 3, color: statusColor),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: ApprovalLazyThumbnail(
                            propertyId: property.id,
                            initialUrl: imageUrl,
                            size: 64,
                            radius: 12,
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
                                    child: _StatusPill(
                                      label: _statusLabel(),
                                      color: statusColor,
                                    ),
                                  ),
                                  if (timeLabel.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      timeLabel,
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: neutral,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                property.title.isEmpty
                                    ? 'Sem título'
                                    : property.title,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: ThemeHelpers.textColor(context),
                                  height: 1.2,
                                  letterSpacing: -0.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (address.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Icon(LucideIcons.mapPin,
                                        size: 13, color: neutral),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        address,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
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
                              if (price.isNotEmpty) ...[
                                const SizedBox(height: 5),
                                Text(
                                  price,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: ThemeHelpers.textColor(context),
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              if (property.code != null &&
                                  property.code!.isNotEmpty) ...[
                                const SizedBox(height: 5),
                                Text(
                                  'CÓD ${property.code!}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: neutral,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.1,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            LucideIcons.chevronRight,
                            size: 18,
                            color: neutral.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
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

/// Chip de status — tint da cor + texto na cor (sem preenchimento sólido).
class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.10),
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
