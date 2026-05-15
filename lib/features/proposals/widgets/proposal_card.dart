import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/purchase_proposals_service.dart';

/// Card de uma proposta na listagem (mobile).
class ProposalCard extends StatelessWidget {
  const ProposalCard({
    super.key,
    required this.proposal,
    required this.accent,
    this.onTap,
    this.onContinue,
    this.onShowHistorico,
    this.onCancelar,
    this.onExcluir,
  });

  final PurchaseProposal proposal;
  final Color accent;
  final VoidCallback? onTap;
  final VoidCallback? onContinue;
  final VoidCallback? onShowHistorico;
  final VoidCallback? onCancelar;
  final VoidCallback? onExcluir;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final isDark = theme.brightness == Brightness.dark;
    final canUpdate =
        ModuleAccessService.instance.hasPermission('proposal:update');
    final canDelete =
        ModuleAccessService.instance.hasPermission('proposal:delete');

    final statusTone = _statusTone(proposal.status);
    final statusLabel = _statusLabel(proposal.status);
    final etapaLabel = _etapaLabel(proposal.etapa);

    final priceText = proposal.proposedPrice != null
        ? NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(
            proposal.proposedPrice!,
          )
        : '—';

    final maxEtapa = proposal.maxEtapaLiberadaParaEnvio ?? proposal.etapa.number;
    final isProcessing = proposal.status == ProposalStatus.processing &&
        proposal.deletedAt == null;
    final canShowContinue = canUpdate && isProcessing;

    String continueLabel;
    IconData continueIcon;
    if (maxEtapa < 2) {
      continueLabel = 'Enviar para assinatura';
      continueIcon = Icons.draw_rounded;
    } else if (maxEtapa == 2 && proposal.etapa2EnviadaParaAssinatura) {
      continueLabel = 'Assinaturas (Proprietário)';
      continueIcon = Icons.draw_rounded;
    } else {
      continueLabel = 'Continuar preenchimento';
      continueIcon = Icons.arrow_forward_rounded;
    }

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
            ),
            color: isDark
                ? Colors.white.withValues(alpha: 0.02)
                : Colors.white,
            boxShadow: [
              if (!isDark)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatusDot(tone: statusTone),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                proposal.proposalNumber.isEmpty
                                    ? '—'
                                    : proposal.proposalNumber,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w900,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                statusLabel,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: statusTone,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          proposal.proponentName?.trim().isNotEmpty == true
                              ? proposal.proponentName!
                              : 'Comprador não informado',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.2,
                            height: 1.15,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          etapaLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _MoreMenu(
                    canUpdate: canUpdate && isProcessing,
                    canDelete: canDelete && proposal.deletedAt == null,
                    onHistorico: onShowHistorico,
                    onCancelar: onCancelar,
                    onExcluir: onExcluir,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _InfoLine(
                icon: Icons.attach_money_rounded,
                label: 'Valor proposto',
                value: priceText,
              ),
              const SizedBox(height: 4),
              _InfoLine(
                icon: Icons.event_outlined,
                label: 'Validade',
                value: proposal.validityDays != null
                    ? '${proposal.validityDays} dias úteis'
                    : '—',
              ),
              const SizedBox(height: 4),
              _InfoLine(
                icon: Icons.person_outline,
                label: 'Criado por',
                value: proposal.creatorName ?? '—',
              ),
              const SizedBox(height: 4),
              _InfoLine(
                icon: Icons.schedule_outlined,
                label: 'Criado em',
                value: proposal.createdAt != null
                    ? DateFormat('dd/MM/yyyy HH:mm', 'pt_BR')
                        .format(proposal.createdAt!.toLocal())
                    : '—',
              ),
              if (canShowContinue && onContinue != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: onContinue,
                    icon: Icon(continueIcon, size: 18),
                    label: Text(
                      continueLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          const Color(0xFF22C55E).withValues(alpha: 0.16),
                      foregroundColor: const Color(0xFF16A34A),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(ProposalStatus s) {
    switch (s) {
      case ProposalStatus.finalized:
        return 'FINALIZADA';
      case ProposalStatus.canceled:
        return 'CANCELADA';
      case ProposalStatus.processing:
        return 'EM ANDAMENTO';
    }
  }

  Color _statusTone(ProposalStatus s) {
    switch (s) {
      case ProposalStatus.finalized:
        return const Color(0xFF16A34A);
      case ProposalStatus.canceled:
        return const Color(0xFFDC2626);
      case ProposalStatus.processing:
        return const Color(0xFF6366F1);
    }
  }

  String _etapaLabel(ProposalEtapa e) {
    switch (e) {
      case ProposalEtapa.comprador:
        return 'Etapa 1 — Comprador';
      case ProposalEtapa.proprietario:
        return 'Etapa 2 — Proprietário';
      case ProposalEtapa.corretor:
        return 'Etapa 3 — Corretor / Captadores';
    }
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.tone});

  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: tone,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: tone.withValues(alpha: 0.45),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Row(
      children: [
        Icon(icon, size: 15, color: muted),
        const SizedBox(width: 6),
        Text(
          '$label:',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: muted,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({
    required this.canUpdate,
    required this.canDelete,
    this.onHistorico,
    this.onCancelar,
    this.onExcluir,
  });

  final bool canUpdate;
  final bool canDelete;
  final VoidCallback? onHistorico;
  final VoidCallback? onCancelar;
  final VoidCallback? onExcluir;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert_rounded,
        color: ThemeHelpers.textSecondaryColor(context),
      ),
      itemBuilder: (ctx) => [
        if (onHistorico != null)
          const PopupMenuItem(value: 'historico', child: Text('Ver histórico')),
        if (canUpdate && onCancelar != null)
          const PopupMenuItem(
            value: 'cancelar',
            child: Text('Cancelar proposta'),
          ),
        if (canDelete && onExcluir != null)
          const PopupMenuItem(value: 'excluir', child: Text('Excluir')),
      ],
      onSelected: (v) {
        switch (v) {
          case 'historico':
            onHistorico?.call();
            break;
          case 'cancelar':
            onCancelar?.call();
            break;
          case 'excluir':
            onExcluir?.call();
            break;
        }
      },
    );
  }
}
