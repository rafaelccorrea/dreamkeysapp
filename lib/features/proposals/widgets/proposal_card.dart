import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/purchase_proposals_service.dart';
import '../../../shared/widgets/skeleton_box.dart';
import 'proposal_row_actions.dart';

/// Card de uma proposta na listagem (mobile).
///
/// Gramática aprovada do card de fichas: card flush simples (fundo de card +
/// filete neutro + sombra crisp no claro), status na pílula e menu de 3
/// pontos — sem borda tingida, sem faixa lateral, sem ponto luminoso. A
/// personalidade da proposta fica no **trilho de etapas** (Comprador →
/// Proprietário → Corretor) e na ação da etapa, no próprio card.
class ProposalCard extends StatelessWidget {
  const ProposalCard({
    super.key,
    required this.proposal,
    required this.accent,
    this.onTap,
    this.onContinue,
    this.onShowHistorico,
    this.onAction,
  });

  final PurchaseProposal proposal;
  final Color accent;
  final VoidCallback? onTap;
  final VoidCallback? onContinue;
  final VoidCallback? onShowHistorico;

  /// Menu da linha — mesmas ações e regras do web.
  final ValueChanged<ProposalRowAction>? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final isDark = theme.brightness == Brightness.dark;
    final canUpdate = ModuleAccessService.instance.hasPermission(
      'proposal:update',
    );

    final statusTone = _statusTone(context, proposal.status);
    final statusLabel = _statusLabel(proposal.status);
    final deleted = proposal.deletedAt != null;
    final danger = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;

    final priceText = proposal.proposedPrice != null
        ? NumberFormat.currency(
            locale: 'pt_BR',
            symbol: 'R\$',
          ).format(proposal.proposedPrice!)
        : '—';

    // Contexto do imóvel (código + localização) — só renderiza se houver algo.
    final propCode = proposal.propertyCode?.trim();
    final propLoc = [
      proposal.propertyNeighborhood?.trim(),
      proposal.propertyCity?.trim(),
    ].where((e) => e != null && e.isNotEmpty).join(' · ');
    final hasPropertyContext =
        (propCode != null && propCode.isNotEmpty) || propLoc.isNotEmpty;

    // Condições da proposta numa linha que QUEBRA (nunca corta em 320dp).
    final terms = <String>[];
    if (proposal.downPayment != null && proposal.downPayment! > 0) {
      terms.add(
        'Entrada ${NumberFormat.compactCurrency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 0).format(proposal.downPayment!)}',
      );
    }
    if (proposal.commissionPercentage != null &&
        proposal.commissionPercentage! > 0) {
      terms.add('Comissão ${_trimNum(proposal.commissionPercentage!)}%');
    }
    final validity = proposal.validityDays;
    if (validity != null) {
      terms.add(
        'Validade $validity ${validity == 1 ? 'dia útil' : 'dias úteis'}',
      );
    }

    final maxEtapa =
        proposal.maxEtapaLiberadaParaEnvio ?? proposal.etapa.number;
    final isProcessing =
        proposal.status == ProposalStatus.processing && !deleted;
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
    final success = isDark
        ? AppColors.status.successDarkMode
        : AppColors.status.success;
    final successInk = isDark
        ? AppColors.message.successTextDarkMode
        : AppColors.message.successText;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: ThemeHelpers.cardBackgroundColor(context),
            border: Border.all(
              color: ThemeHelpers.borderLightColor(
                context,
              ).withValues(alpha: isDark ? 0.9 : 1),
            ),
            boxShadow: isDark ? null : ThemeHelpers.cardShadow(context),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(15, 14, 8, 15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Cabeçalho: Nº + status · menu ───────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _NumberBadge(
                                accent: accent,
                                number: proposal.proposalNumber,
                              ),
                              _StatusPill(tone: statusTone, label: statusLabel),
                              if (deleted)
                                _StatusPill(tone: danger, label: 'EXCLUÍDA'),
                            ],
                          ),
                          const SizedBox(height: 8),
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
                    if (onAction != null)
                      ProposalActionsMenu(
                        rules: ProposalRowRules(proposal),
                        onAction: onAction!,
                      ),
                  ],
                ),

                // ── Corpo (margem direita igual à esquerda) ─────────────
                Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (hasPropertyContext) ...[
                        const SizedBox(height: 10),
                        _PropertyContextLine(code: propCode, location: propLoc),
                      ],
                      const SizedBox(height: 12),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: ThemeHelpers.borderLightColor(context),
                      ),
                      const SizedBox(height: 12),

                      // ── Valor em destaque (encolhe, nunca corta) ──────
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
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          priceText,
                          maxLines: 1,
                          softWrap: false,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.8,
                            height: 1.0,
                          ),
                        ),
                      ),
                      if (terms.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          terms.join('  ·  '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                      ],

                      // ── Trilho de etapas ──────────────────────────────
                      const SizedBox(height: 14),
                      _StageTracker(
                        current: proposal.etapa.number,
                        finalized: isFinalized,
                        canceled: isCanceled || deleted,
                        accent: accent,
                      ),

                      // ── Rodapé: autoria + data ────────────────────────
                      const SizedBox(height: 13),
                      _FooterMeta(
                        creatorName: proposal.creatorName,
                        createdAt: proposal.createdAt,
                      ),

                      // ── Ação da etapa, no próprio card ─────────────────
                      if (canShowContinue && onContinue != null) ...[
                        const SizedBox(height: 13),
                        FilledButton.tonalIcon(
                          onPressed: onContinue,
                          icon: Icon(continueIcon, size: 18),
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              continueLabel,
                              maxLines: 1,
                              softWrap: false,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: success.withValues(
                              alpha: isDark ? 0.18 : 0.12,
                            ),
                            foregroundColor: successInk,
                            minimumSize: const Size.fromHeight(46),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ] else if (isProcessing && !canUpdate) ...[
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Icon(
                                Icons.lock_outline_rounded,
                                size: 14,
                                color: muted,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Envio para assinatura travado: sua conta '
                                'não edita propostas.',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: muted,
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
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

  /// Mesmas cores dos filtros rápidos da lista (`AppColors.status`).
  Color _statusTone(BuildContext context, ProposalStatus s) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    switch (s) {
      case ProposalStatus.finalized:
        return dark
            ? AppColors.status.successDarkMode
            : AppColors.status.success;
      case ProposalStatus.canceled:
        return dark ? AppColors.status.errorDarkMode : AppColors.status.error;
      case ProposalStatus.processing:
        return dark ? AppColors.status.infoDarkMode : AppColors.status.info;
    }
  }

  /// Formata percentual sem casas decimais redundantes (5.0 → "5", 5.5 → "5,5").
  static String _trimNum(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString().replaceAll('.', ',');
  }
}

/// Placeholder de carregamento — **fiel** ao `ProposalCard` (mesmo container e
/// posições: Nº+status, comprador, contexto, filete, valor + condições,
/// trilho de etapas e rodapé). Usado na listagem e na próxima página.
class ProposalCardSkeleton extends StatelessWidget {
  const ProposalCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border.all(
          color: ThemeHelpers.borderLightColor(
            context,
          ).withValues(alpha: isDark ? 0.9 : 1),
        ),
        boxShadow: isDark ? null : ThemeHelpers.cardShadow(context),
      ),
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              SkeletonBox(width: 56, height: 20, borderRadius: 6),
              SizedBox(width: 8),
              SkeletonBox(width: 90, height: 20, borderRadius: 999),
              Spacer(),
              SkeletonBox(width: 34, height: 34, borderRadius: 10),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: const [
              Expanded(flex: 7, child: SkeletonText(height: 18)),
              Spacer(flex: 3),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: const [
              SkeletonBox(width: 60, height: 15, borderRadius: 6),
              SizedBox(width: 8),
              Expanded(flex: 4, child: SkeletonText(height: 12)),
              Spacer(flex: 4),
            ],
          ),
          const SizedBox(height: 14),
          const SkeletonBox(width: double.infinity, height: 1),
          const SizedBox(height: 14),
          // Valor + condições
          const SkeletonText(width: 70, height: 9),
          const SizedBox(height: 7),
          const SkeletonBox(width: 150, height: 24, borderRadius: 6),
          const SizedBox(height: 8),
          const SkeletonText(width: 200, height: 11),
          const SizedBox(height: 16),
          // Trilho de etapas (3 nós)
          Row(
            children: const [
              SkeletonBox(width: 22, height: 22, borderRadius: 11),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: SkeletonBox(
                    width: double.infinity,
                    height: 3,
                    borderRadius: 2,
                  ),
                ),
              ),
              SkeletonBox(width: 22, height: 22, borderRadius: 11),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: SkeletonBox(
                    width: double.infinity,
                    height: 3,
                    borderRadius: 2,
                  ),
                ),
              ),
              SkeletonBox(width: 22, height: 22, borderRadius: 11),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: const [
              SkeletonBox(width: 108, height: 12, borderRadius: 6),
              SizedBox(width: 12),
              SkeletonBox(width: 70, height: 12, borderRadius: 6),
            ],
          ),
        ],
      ),
    );
  }
}

class _NumberBadge extends StatelessWidget {
  const _NumberBadge({required this.accent, required this.number});

  final Color accent;
  final String number;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        number.isEmpty ? 'Sem número' : 'Nº $number',
        maxLines: 1,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: accent,
          fontWeight: FontWeight.w900,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
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
  const _PropertyContextLine({required this.code, required this.location});

  final String? code;
  final String location;

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
            constraints: const BoxConstraints(maxWidth: 130),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: ThemeHelpers.borderLightColor(context),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              'CÓD $code',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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

/// Trilho horizontal das 3 etapas da ficha (Comprador → Proprietário →
/// Corretor). Nós concluídos recebem check; o atual fica em destaque; os
/// futuros ficam apagados. Em proposta finalizada, todas concluídas; em
/// cancelada/excluída, fica neutralizado.
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

  static const _labels = ['Comprador', 'Proprietário', 'Corretor'];

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
                color: filled ? tone.withValues(alpha: 0.55) : border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
      }
      nodes.add(
        _StageNode(
          step: step,
          done: isDone(step),
          active: isActive(step),
          tone: tone,
          border: border,
          muted: muted,
        ),
      );
    }

    final estado = finalized
        ? 'todas as etapas concluídas'
        : canceled
        ? 'etapas interrompidas'
        : 'etapa $current de 3, ${_labels[(current - 1).clamp(0, 2).toInt()]}';

    return Semantics(
      label: 'Assinaturas: $estado',
      child: Column(
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
                      fontWeight: isActive(i + 1)
                          ? FontWeight.w900
                          : FontWeight.w700,
                      fontSize: 10,
                      letterSpacing: 0.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ],
      ),
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
        color: done
            ? tone
            : (active ? tone.withValues(alpha: 0.14) : Colors.transparent),
        border: Border.all(
          color: filled ? tone : border,
          width: active ? 2 : 1.4,
        ),
      ),
      alignment: Alignment.center,
      child: done
          ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
          : Text(
              '$step',
              textScaler: TextScaler.noScaling,
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

/// Rodapé com autoria e data — denso e calmo; quebra de linha em vez de
/// cortar quando a fonte é grande.
class _FooterMeta extends StatelessWidget {
  const _FooterMeta({required this.creatorName, required this.createdAt});

  final String? creatorName;
  final DateTime? createdAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final dateStr = createdAt != null
        ? DateFormat('dd/MM/yyyy', 'pt_BR').format(createdAt!.toLocal())
        : null;
    final creator = creatorName?.trim().isNotEmpty == true
        ? creatorName!.trim()
        : 'Autor não informado';
    final style = theme.textTheme.labelSmall?.copyWith(
      color: muted,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.1,
    );

    return Wrap(
      spacing: 12,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_outline, size: 14, color: muted),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 190),
              child: Text(
                creator,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ],
        ),
        if (dateStr != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule_outlined, size: 13, color: muted),
              const SizedBox(width: 5),
              Text(
                'criada em $dateStr',
                maxLines: 1,
                style: style?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
      ],
    );
  }
}
