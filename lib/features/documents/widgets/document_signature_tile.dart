import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/document_signature_model.dart';

/// Cor e ícone de cada status de assinatura (mesma leitura do web:
/// aguardando = âmbar, visualizado = azul, assinado = verde, rejeitado =
/// vermelho, expirado/cancelado = neutro).
Color signatureStatusColor(BuildContext context, DocumentSignatureStatus s) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  switch (s) {
    case DocumentSignatureStatus.pending:
      return dark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    case DocumentSignatureStatus.viewed:
      return dark ? AppColors.status.infoDarkMode : AppColors.status.info;
    case DocumentSignatureStatus.signed:
      return dark ? AppColors.status.successDarkMode : AppColors.status.success;
    case DocumentSignatureStatus.rejected:
      return dark ? AppColors.status.errorDarkMode : AppColors.status.error;
    case DocumentSignatureStatus.expired:
    case DocumentSignatureStatus.cancelled:
      return ThemeHelpers.textSecondaryColor(context);
  }
}

IconData signatureStatusIcon(DocumentSignatureStatus s) {
  switch (s) {
    case DocumentSignatureStatus.pending:
      return Icons.schedule_rounded;
    case DocumentSignatureStatus.viewed:
      return Icons.visibility_outlined;
    case DocumentSignatureStatus.signed:
      return Icons.check_circle_outline_rounded;
    case DocumentSignatureStatus.rejected:
      return Icons.cancel_outlined;
    case DocumentSignatureStatus.expired:
      return Icons.timer_off_outlined;
    case DocumentSignatureStatus.cancelled:
      return Icons.block_outlined;
  }
}

/// Linha flush de uma assinatura: status, signatário, datas e ações
/// (abrir para assinar, copiar link, enviar e reenviar e-mail). As ações só
/// aparecem quando o chamador passa o callback — cada tela decide a regra do
/// web que aplica.
class DocumentSignatureTile extends StatelessWidget {
  final DocumentSignature signature;

  /// Título opcional acima do signatário (nome do documento na lista geral).
  final String? documentTitle;
  final VoidCallback? onTap;

  /// Abre o `signatureUrl` (Autentique) fora do app para assinar.
  final VoidCallback? onOpenLink;
  final VoidCallback? onCopyLink;
  final VoidCallback? onSendEmail;
  final VoidCallback? onResendEmail;
  final bool busy;

  const DocumentSignatureTile({
    super.key,
    required this.signature,
    this.documentTitle,
    this.onTap,
    this.onOpenLink,
    this.onCopyLink,
    this.onSendEmail,
    this.onResendEmail,
    this.busy = false,
  });

  static final DateFormat _fmt = DateFormat('dd/MM/yyyy HH:mm');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = signatureStatusColor(context, signature.status);
    final muted = ThemeHelpers.textSecondaryColor(context);

    final meta = <String>[];
    if (signature.signedAt != null) {
      meta.add('Assinado ${_fmt.format(signature.signedAt!.toLocal())}');
    } else if (signature.rejectedAt != null) {
      meta.add('Rejeitado ${_fmt.format(signature.rejectedAt!.toLocal())}');
    } else if (signature.viewedAt != null) {
      meta.add('Visto ${_fmt.format(signature.viewedAt!.toLocal())}');
    }
    if (signature.expiresAt != null &&
        signature.status != DocumentSignatureStatus.signed) {
      meta.add('Expira ${_fmt.format(signature.expiresAt!.toLocal())}');
    }

    final hasActions = onOpenLink != null ||
        onCopyLink != null ||
        onSendEmail != null ||
        onResendEmail != null;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    signatureStatusIcon(signature.status),
                    color: color,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (documentTitle != null &&
                          documentTitle!.trim().isNotEmpty) ...[
                        Text(
                          documentTitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: ThemeHelpers.textColor(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                      ],
                      Text(
                        signature.signerName.isEmpty
                            ? 'Signatário'
                            : signature.signerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: (documentTitle != null
                                ? theme.textTheme.bodyMedium
                                : theme.textTheme.titleSmall)
                            ?.copyWith(
                          fontWeight: documentTitle != null
                              ? FontWeight.w500
                              : FontWeight.w700,
                          color: documentTitle != null
                              ? muted
                              : ThemeHelpers.textColor(context),
                        ),
                      ),
                      if (signature.signerEmail.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          signature.signerEmail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: muted),
                        ),
                      ],
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          meta.join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: muted, fontSize: 11.5),
                        ),
                      ],
                      if (signature.rejectionReason != null &&
                          signature.rejectionReason!.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Motivo: ${signature.rejectionReason}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: signatureStatusColor(
                              context,
                              DocumentSignatureStatus.rejected,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      signature.status.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (hasActions) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 48),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (onOpenLink != null)
                      _ActionChip(
                        icon: Icons.open_in_new_rounded,
                        label: 'Abrir para assinar',
                        onTap: busy ? null : onOpenLink,
                      ),
                    if (onCopyLink != null)
                      _ActionChip(
                        icon: Icons.link_rounded,
                        label: 'Copiar link',
                        onTap: busy ? null : onCopyLink,
                      ),
                    if (onSendEmail != null)
                      _ActionChip(
                        icon: Icons.mail_outline_rounded,
                        label: 'Enviar e-mail',
                        onTap: busy ? null : onSendEmail,
                      ),
                    if (onResendEmail != null)
                      _ActionChip(
                        icon: Icons.refresh_rounded,
                        label: 'Reenviar',
                        onTap: busy ? null : onResendEmail,
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ActionChip({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final fg = onTap == null
        ? ThemeHelpers.textSecondaryColor(context).withValues(alpha: 0.5)
        : ThemeHelpers.textColor(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: ThemeHelpers.borderColor(context)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
