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

/// Item da fila de aprovação — **linha flush** (sem card/sombra e sem faixa
/// lateral): thumbnail grande com o código logo abaixo, info à direita e, para
/// quem tem permissão nas filas de disponibilidade/publicação, os botões de
/// **Aprovar/Recusar** no próprio item. Tocar no corpo abre os detalhes.
///
/// O botão de **3 pontinhos** ([onMore]) abre o menu de "mais ações" da fila
/// (histórico, cobrar, notificar, autorização do proprietário…), espelhando o
/// `PendingApprovalPortalActionsMenu` do web.
class ApprovalPropertyCard extends StatefulWidget {
  final Property property;
  final ApprovalQueueKind kind;
  final VoidCallback? onOpenDetails;

  /// Gating de UI: só renderiza o botão quando há permissão.
  final bool canApprove;
  final bool canReject;

  /// Callbacks que executam a ação e retornam `true` em sucesso. Quando `null`,
  /// o botão correspondente não é exibido.
  final Future<bool> Function()? onApprove;
  final Future<bool> Function()? onReject;

  /// Reenvio após recusa (responsável corrige e devolve para a fila). Quando
  /// `null` o botão não aparece.
  final Future<bool> Function()? onResend;

  /// Voto na fila quando o multi-aprovadores está ligado — substitui o
  /// aprovar/recusar direto, igual ao web.
  final Future<bool> Function()? onVote;

  /// Abre o menu de mais ações (3 pontinhos).
  final VoidCallback? onMore;

  /// Rótulo curto do estado da autorização do proprietário, exibido abaixo do
  /// título nas filas de proprietário (paridade com `renderBelowTitle`).
  final String? ownerAuthNote;

  const ApprovalPropertyCard({
    super.key,
    required this.property,
    required this.kind,
    this.onOpenDetails,
    this.canApprove = false,
    this.canReject = false,
    this.onApprove,
    this.onReject,
    this.onResend,
    this.onVote,
    this.onMore,
    this.ownerAuthNote,
  });

  @override
  State<ApprovalPropertyCard> createState() => _ApprovalPropertyCardState();
}

class _ApprovalPropertyCardState extends State<ApprovalPropertyCard> {
  bool _approving = false;
  bool _rejecting = false;
  bool _resending = false;
  bool _voting = false;

  Property get property => widget.property;
  ApprovalQueueKind get kind => widget.kind;

  bool get _busy => _approving || _rejecting || _resending || _voting;

  bool get _showApprove => widget.canApprove && widget.onApprove != null;
  bool get _showReject => widget.canReject && widget.onReject != null;
  bool get _showResend => widget.onResend != null;
  bool get _showVote => widget.onVote != null;
  bool get _showActions =>
      _showApprove || _showReject || _showResend || _showVote;

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

  Future<void> _runApprove() async {
    if (widget.onApprove == null || _busy) return;
    setState(() => _approving = true);
    try {
      await widget.onApprove!();
    } finally {
      if (mounted) setState(() => _approving = false);
    }
  }

  Future<void> _runReject() async {
    if (widget.onReject == null || _busy) return;
    setState(() => _rejecting = true);
    try {
      await widget.onReject!();
    } finally {
      if (mounted) setState(() => _rejecting = false);
    }
  }

  Future<void> _runResend() async {
    if (widget.onResend == null || _busy) return;
    setState(() => _resending = true);
    try {
      await widget.onResend!();
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _runVote() async {
    if (widget.onVote == null || _busy) return;
    setState(() => _voting = true);
    try {
      await widget.onVote!();
    } finally {
      if (mounted) setState(() => _voting = false);
    }
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
    final code = property.code;
    final hasCode = code != null && code.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onOpenDetails,
        child: Container(
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
                  // Coluna da esquerda: thumbnail grande + código logo abaixo.
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: ApprovalLazyThumbnail(
                          propertyId: property.id,
                          initialUrl: imageUrl,
                          size: 72,
                          radius: 14,
                        ),
                      ),
                      if (hasCode) ...[
                        const SizedBox(height: 7),
                        _CodeChip(code: code),
                      ],
                    ],
                  ),
                  const SizedBox(width: 14),
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
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(LucideIcons.mapPin, size: 13, color: neutral),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  address,
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
                        if (price.isNotEmpty) ...[
                          const SizedBox(height: 6),
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
                        if ((widget.ownerAuthNote ?? '').isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            widget.ownerAuthNote!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: neutral,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 2),
                  // 3 pontinhos = "mais ações" da fila (mesmo papel do menu
                  // portal do web). Sem ele, sobra a seta de "abrir ficha".
                  if (widget.onMore != null)
                    IconButton(
                      onPressed: widget.onMore,
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Mais ações',
                      icon: Icon(
                        LucideIcons.moreVertical,
                        size: 18,
                        color: neutral,
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 2, left: 2),
                      child: Icon(
                        LucideIcons.chevronRight,
                        size: 18,
                        color: neutral.withValues(alpha: 0.7),
                      ),
                    ),
                ],
              ),
              if (_showActions) ...[
                const SizedBox(height: 14),
                _buildActions(context),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ok =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

    Widget spinner(Color c) => SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: c),
        );

    final rejectBtn = OutlinedButton.icon(
      onPressed: _busy ? null : _runReject,
      style: OutlinedButton.styleFrom(
        foregroundColor: danger,
        side: BorderSide(color: danger.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(vertical: 11),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
      ),
      icon: _rejecting
          ? spinner(danger)
          : const Icon(LucideIcons.xCircle, size: 16),
      label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Recusar')),
    );

    final approveBtn = FilledButton.icon(
      onPressed: _busy ? null : _runApprove,
      style: FilledButton.styleFrom(
        backgroundColor: ok,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 11),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
      ),
      icon: _approving
          ? spinner(Colors.white)
          : const Icon(LucideIcons.checkCircle2, size: 16),
      label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Aprovar')),
    );

    // Reenviar depois de recusa: ação neutra (não é aprovação nem destruição),
    // por isso sai em contorno na cor de texto secundária.
    final resendBtn = OutlinedButton.icon(
      onPressed: _busy ? null : _runResend,
      style: OutlinedButton.styleFrom(
        foregroundColor: ThemeHelpers.textColor(context),
        side: BorderSide(color: ThemeHelpers.borderColor(context)),
        padding: const EdgeInsets.symmetric(vertical: 11),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
      ),
      icon: _resending
          ? spinner(ThemeHelpers.textColor(context))
          : const Icon(LucideIcons.refreshCw, size: 16),
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(_resending ? 'Reenviando…' : 'Reenviar'),
      ),
    );

    final voteBtn = FilledButton.icon(
      onPressed: _busy ? null : _runVote,
      style: FilledButton.styleFrom(
        backgroundColor: ok,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 11),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
      ),
      icon: _voting
          ? spinner(Colors.white)
          : const Icon(LucideIcons.vote, size: 16),
      label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Votar')),
    );

    final buttons = <Widget>[
      if (_showResend) resendBtn,
      if (_showReject) rejectBtn,
      if (_showVote) voteBtn,
      if (_showApprove) approveBtn,
    ];

    return Row(
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: buttons[i]),
        ],
      ],
    );
  }
}

/// Código do imóvel — chip discreto exibido abaixo da miniatura.
class _CodeChip extends StatelessWidget {
  final String code;

  const _CodeChip({required this.code});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    return Container(
      constraints: const BoxConstraints(maxWidth: 72),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        'CÓD $code',
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: ThemeHelpers.textSecondaryColor(context),
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          fontSize: 9.5,
          height: 1,
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
