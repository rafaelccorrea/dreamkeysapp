import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/purchase_proposals_service.dart';

/// Card de uma proposta na listagem (mobile).
///
/// Layout editorial e denso: cabeçalho (status + nº), proponente em destaque,
/// linha de contexto do imóvel, bloco de valor em evidência, **tracker de
/// etapas** (Comprador → Proprietário → Corretor) e rodapé de autoria. A borda
/// é levemente tingida pelo status para leitura rápida na lista.
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

    // Contexto do imóvel (código + localização) — só renderiza se houver algo.
    final propCode = proposal.propertyCode?.trim();
    final propLoc = [
      proposal.propertyNeighborhood?.trim(),
      proposal.propertyCity?.trim(),
    ].where((e) => e != null && e.isNotEmpty).join(' · ');
    final hasPropertyContext =
        (propCode != null && propCode.isNotEmpty) || propLoc.isNotEmpty;

    // Sub-linha do valor: entrada e/ou comissão, quando informadas.
    final valueExtras = <String>[];
    if (proposal.downPayment != null && proposal.downPayment! > 0) {
      valueExtras.add(
        'Entrada ${NumberFormat.compactCurrency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 0).format(proposal.downPayment!)}',
      );
    }
    if (proposal.commissionPercentage != null &&
        proposal.commissionPercentage! > 0) {
      valueExtras.add(
        'Comissão ${_trimNum(proposal.commissionPercentage!)}%',
      );
    }

    final maxEtapa = proposal.maxEtapaLiberadaParaEnvio ?? proposal.etapa.number;
    final isProcessing = proposal.status == ProposalStatus.processing &&
        proposal.deletedAt == null;
    final isFinalized = proposal.status == ProposalStatus.finalized;
    final isCanceled = proposal.status == ProposalStatus.canceled;
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
              color: statusTone.withValues(alpha: isDark ? 0.34 : 0.24),
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
                  spreadRadius: -6,
                ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(14, 13, 10, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Cabeçalho: dot + nº + status + menu ────────────────────
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
                                    : 'Nº ${proposal.proposalNumber}',
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
                            Flexible(child: _StatusPill(tone: statusTone, label: statusLabel)),
                          ],
                        ),
                        const SizedBox(height: 7),
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

              // ── Contexto do imóvel ─────────────────────────────────────
              if (hasPropertyContext) ...[
                const SizedBox(height: 9),
                _PropertyContextLine(
                  code: propCode,
                  location: propLoc,
                  accent: accent,
                ),
              ],

              const SizedBox(height: 12),
              Divider(
                height: 1,
                thickness: 1,
                color: ThemeHelpers.borderLightColor(context)
                    .withValues(alpha: 0.7),
              ),
              const SizedBox(height: 12),

              // ── Bloco de valor em destaque ─────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'VALOR PROPOSTO',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: muted,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            fontSize: 9.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          priceText,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.8,
                            height: 1.0,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (proposal.validityDays != null) ...[
                    const SizedBox(width: 10),
                    _MetaPill(
                      icon: Icons.event_available_outlined,
                      label: '${proposal.validityDays} dias úteis',
                      tone: muted,
                    ),
                  ],
                ],
              ),
              if (valueExtras.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  valueExtras.join('   ·   '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              // ── Tracker de etapas ──────────────────────────────────────
              const SizedBox(height: 14),
              _StageTracker(
                current: proposal.etapa.number,
                finalized: isFinalized,
                canceled: isCanceled,
                accent: accent,
              ),

              // ── Rodapé: autoria + data ─────────────────────────────────
              const SizedBox(height: 13),
              _FooterMeta(
                creatorName: proposal.creatorName,
                createdAt: proposal.createdAt,
                etapaLabel: etapaLabel,
              ),

              if (canShowContinue && onContinue != null) ...[
                const SizedBox(height: 13),
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

  /// Formata percentual sem casas decimais redundantes (5.0 → "5", 5.5 → "5,5").
  static String _trimNum(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString().replaceAll('.', ',');
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

/// Pill de status — tint da cor + texto na cor (sem preenchimento sólido).
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.tone, required this.label});

  final Color tone;
  final String label;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: isDark ? 0.4 : 0.28)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: tone,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              fontSize: 10,
            ),
      ),
    );
  }
}

/// Linha de contexto do imóvel — chip de código + localização.
class _PropertyContextLine extends StatelessWidget {
  const _PropertyContextLine({
    required this.code,
    required this.location,
    required this.accent,
  });

  final String? code;
  final String location;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final hasCode = code != null && code!.isNotEmpty;
    return Row(
      children: [
        Icon(Icons.home_work_outlined, size: 14, color: muted),
        const SizedBox(width: 6),
        if (hasCode) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: ThemeHelpers.borderLightColor(context)
                  .withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              'CÓD $code',
              style: theme.textTheme.labelSmall?.copyWith(
                color: muted,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.4,
                fontSize: 9.5,
              ),
            ),
          ),
          if (location.isNotEmpty) const SizedBox(width: 8),
        ],
        if (location.isNotEmpty)
          Expanded(
            child: Text(
              location,
              style: theme.textTheme.bodySmall?.copyWith(
                color: muted,
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

/// Pill compacto de metadado (ícone + label) com borda fina tonal.
class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.icon,
    required this.label,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: tone),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w800,
                  fontSize: 10.5,
                ),
          ),
        ],
      ),
    );
  }
}

/// Tracker horizontal das 3 etapas da ficha (Comprador → Proprietário →
/// Corretor). Nós concluídos recebem check; o atual fica em destaque; os
/// futuros ficam apagados. Em proposta finalizada, todas concluídas; em
/// cancelada, fica neutralizado.
class _StageTracker extends StatelessWidget {
  const _StageTracker({
    required this.current,
    required this.finalized,
    required this.canceled,
    required this.accent,
  });

  final int current; // 1..3
  final bool finalized;
  final bool canceled;
  final Color accent;

  static const _labels = ['Comprador', 'Propriet.', 'Corretor'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final border = ThemeHelpers.borderColor(context);
    final tone = canceled ? muted : accent;

    bool isDone(int step) => finalized || step < current;
    bool isActive(int step) => !finalized && !canceled && step == current;

    final nodes = <Widget>[];
    for (var i = 0; i < 3; i++) {
      final step = i + 1;
      if (i > 0) {
        // Conector — colorido se a etapa anterior já foi concluída.
        final filled = !canceled && (finalized || step <= current);
        nodes.add(
          Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: filled
                    ? tone.withValues(alpha: 0.55)
                    : border.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
      }
      nodes.add(_StageNode(
        step: step,
        done: isDone(step),
        active: isActive(step),
        tone: tone,
        border: border,
        muted: muted,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: nodes),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < 3; i++)
              Expanded(
                child: Text(
                  _labels[i],
                  textAlign: i == 0
                      ? TextAlign.start
                      : (i == 2 ? TextAlign.end : TextAlign.center),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isActive(i + 1) ? tone : muted,
                    fontWeight:
                        isActive(i + 1) ? FontWeight.w900 : FontWeight.w700,
                    fontSize: 9.5,
                    letterSpacing: 0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _StageNode extends StatelessWidget {
  const _StageNode({
    required this.step,
    required this.done,
    required this.active,
    required this.tone,
    required this.border,
    required this.muted,
  });

  final int step;
  final bool done;
  final bool active;
  final Color tone;
  final Color border;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final filled = done || active;
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? tone : (active ? tone.withValues(alpha: 0.14) : Colors.transparent),
        border: Border.all(
          color: filled ? tone : border.withValues(alpha: 0.7),
          width: active ? 2 : 1.4,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: tone.withValues(alpha: 0.3),
                  blurRadius: 8,
                  spreadRadius: -1,
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: done
          ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
          : Text(
              '$step',
              style: TextStyle(
                color: active ? tone : muted,
                fontWeight: FontWeight.w900,
                fontSize: 11,
                height: 1,
              ),
            ),
    );
  }
}

/// Rodapé com autoria, data e etapa textual — denso e calmo.
class _FooterMeta extends StatelessWidget {
  const _FooterMeta({
    required this.creatorName,
    required this.createdAt,
    required this.etapaLabel,
  });

  final String? creatorName;
  final DateTime? createdAt;
  final String etapaLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final dateStr = createdAt != null
        ? DateFormat('dd/MM/yyyy', 'pt_BR').format(createdAt!.toLocal())
        : null;

    return Row(
      children: [
        Icon(Icons.person_outline, size: 14, color: muted),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            creatorName?.trim().isNotEmpty == true ? creatorName! : '—',
            style: theme.textTheme.labelSmall?.copyWith(
              color: muted,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (dateStr != null) ...[
          const SizedBox(width: 8),
          Container(
            width: 3,
            height: 3,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: muted.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.schedule_outlined, size: 13, color: muted),
          const SizedBox(width: 5),
          Text(
            dateStr,
            style: theme.textTheme.labelSmall?.copyWith(
              color: muted,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
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
