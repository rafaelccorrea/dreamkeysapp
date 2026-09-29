import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/sale_forms_service.dart';
import '../../../shared/widgets/skeleton_box.dart';
import 'sale_form_row_rules.dart';

/// Card de uma ficha de venda na listagem (mobile).
///
/// Sem borda tingida (limitava a leitura): o status vem de uma **faixa de acento
/// na lateral esquerda**, deixando o card flush e com espaço para informação
/// rica — comprador, contexto do imóvel, valor + comissão, progresso de
/// assinatura e rodapé (autoria, data, equipe).
class SaleFormCard extends StatelessWidget {
  const SaleFormCard({
    super.key,
    required this.saleForm,
    required this.accent,
    this.onTap,
    this.onAction,
  });

  final SaleForm saleForm;
  final Color accent;
  final VoidCallback? onTap;

  /// Ações do menu (mesmas do menu da listagem web, na mesma ordem).
  final ValueChanged<SaleFormRowAction>? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final isDark = theme.brightness == Brightness.dark;

    final rules = SaleFormRowRules(saleForm);

    final statusTone = _statusTone(context, saleForm.status);
    final isCanceled = saleForm.status == SaleFormStatus.canceled;

    final money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final priceText = saleForm.saleValue != null && saleForm.saleValue! > 0
        ? money.format(saleForm.saleValue!)
        : '—';
    final commission = saleForm.totalCommission;
    final commissionText = commission != null && commission > 0
        ? money.format(commission)
        : null;

    // Contexto do imóvel.
    final propCode = saleForm.propertyCode?.trim();
    final propLoc = [
      saleForm.propertyNeighborhood?.trim(),
      saleForm.propertyCity?.trim(),
    ].where((e) => e != null && e.isNotEmpty).join(' · ');
    final hasPropertyContext =
        (propCode != null && propCode.isNotEmpty) || propLoc.isNotEmpty;

    final sellerName = saleForm.sellerName?.trim();
    final saleUnit = saleForm.saleUnit?.trim();
    final teamName = saleForm.teamName?.trim();
    final teamColor = _parseHex(saleForm.teamColor);

    final sigTotal = saleForm.assinaturasTotal;
    final sigDone = saleForm.assinaturasAssinadas;
    final showSig = sigTotal > 0 && !isCanceled;


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
              ).withValues(alpha: isDark ? 0.9 : 0.8),
            ),
            boxShadow: [
              if (!isDark)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                  spreadRadius: -8,
                ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(15, 14, 8, 15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Cabeçalho ──────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _NumberBadge(
                                accent: accent,
                                number: saleForm.formNumber,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: _StatusPill(
                                  tone: statusTone,
                                  label: saleForm.status.label.toUpperCase(),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            saleForm.buyerName?.trim().isNotEmpty == true
                                ? saleForm.buyerName!
                                : 'Comprador não informado',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.2,
                              height: 1.15,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 5),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _TypeBadge(label: saleForm.saleFormType.label),
                              if (sellerName != null && sellerName.isNotEmpty)
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 210,
                                  ),
                                  child: Text(
                                    'Vendedor: $sellerName',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: muted,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (onAction != null)
                      SaleFormActionsMenu(
                        rules: rules,
                        onAction: onAction!,
                      ),
                  ],
                ),

                if (hasPropertyContext) ...[
                  const SizedBox(height: 10),
                  _PropertyContextLine(code: propCode, location: propLoc),
                ],

                const SizedBox(height: 12),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: ThemeHelpers.borderLightColor(
                    context,
                  ).withValues(alpha: 0.7),
                ),
                const SizedBox(height: 12),

                // ── Métricas: valor + comissão ─────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: _Metric(
                        label: 'VALOR DA VENDA',
                        value: priceText,
                        emphasis: true,
                      ),
                    ),
                    if (commissionText != null) ...[
                      const SizedBox(width: 12),
                      _Metric(
                        label: 'COMISSÃO',
                        value: commissionText,
                        alignEnd: true,
                      ),
                    ],
                  ],
                ),

                // ── Progresso de assinatura ────────────────────
                if (showSig) ...[
                  const SizedBox(height: 13),
                  _SignatureProgress(
                    done: sigDone,
                    total: sigTotal,
                    tone: statusTone,
                  ),
                ],

                // ── Rodapé: autoria, data, unidade, equipe ─────
                const SizedBox(height: 13),
                _FooterMeta(
                  creatorName: saleForm.creatorName,
                  createdAt: saleForm.createdAt,
                  saleUnit: saleUnit,
                  teamName: teamName,
                  teamColor: teamColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _statusTone(BuildContext context, SaleFormStatus s) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    switch (s) {
      case SaleFormStatus.finalized:
        return dark
            ? AppColors.status.successDarkMode
            : AppColors.status.success;
      case SaleFormStatus.canceled:
        return dark ? AppColors.status.errorDarkMode : AppColors.status.error;
      case SaleFormStatus.processing:
        return dark ? AppColors.status.infoDarkMode : AppColors.status.info;
      case SaleFormStatus.waitingForSignature:
        return dark
            ? AppColors.status.warningDarkMode
            : AppColors.status.warning;
    }
  }

  static Color? _parseHex(String? c) {
    if (c == null) return null;
    var s = c.trim();
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 6) {
      final v = int.tryParse(s, radix: 16);
      if (v != null) return Color(0xFF000000 | v);
    }
    return null;
  }
}

/// Placeholder de carregamento — **fiel** ao `SaleFormCard` (mesmo container e
/// posições: cabeçalho Nº+status, comprador, tipo/vendedor, divisória, métricas
/// valor+comissão e rodapé). Usado na listagem enquanto `_loading`.
class SaleFormCardSkeleton extends StatelessWidget {
  const SaleFormCardSkeleton({super.key});

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
          ).withValues(alpha: isDark ? 0.9 : 0.8),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 5),
              spreadRadius: -8,
            ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabeçalho: Nº + status pill
          Row(
            children: const [
              SkeletonBox(width: 58, height: 20, borderRadius: 6),
              SizedBox(width: 8),
              SkeletonBox(width: 92, height: 20, borderRadius: 999),
            ],
          ),
          const SizedBox(height: 13),
          // Comprador (título)
          Row(
            children: const [
              Expanded(flex: 7, child: SkeletonText(height: 18)),
              Spacer(flex: 3),
            ],
          ),
          const SizedBox(height: 10),
          // Tipo + vendedor
          Row(
            children: const [
              SkeletonBox(width: 64, height: 15, borderRadius: 6),
              SizedBox(width: 8),
              Expanded(flex: 4, child: SkeletonText(height: 12)),
              Spacer(flex: 4),
            ],
          ),
          const SizedBox(height: 14),
          const SkeletonBox(width: double.infinity, height: 1),
          const SizedBox(height: 14),
          // Métricas: valor + comissão
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: const [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonText(width: 78, height: 9),
                    SizedBox(height: 7),
                    SkeletonBox(width: 138, height: 22, borderRadius: 6),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SkeletonText(width: 52, height: 9),
                    SizedBox(height: 7),
                    SkeletonBox(width: 84, height: 18, borderRadius: 6),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Rodapé
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
        number.isEmpty ? '—' : 'Nº $number',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: accent,
          fontWeight: FontWeight.w900,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

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

/// Badge do tipo da ficha (Terceiros / Lançamento / Casa Minha Vida).
class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: muted,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
          fontSize: 9.5,
        ),
      ),
    );
  }
}

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
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: ThemeHelpers.borderLightColor(
                context,
              ).withValues(alpha: 0.8),
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

/// Métrica destacada (rótulo pequeno + valor forte).
class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.emphasis = false,
    this.alignEnd = false,
  });
  final String label;
  final String value;
  final bool emphasis;
  final bool alignEnd;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: muted,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            fontSize: 9.5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: emphasis
              ? theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                  height: 1.0,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )
              : theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                  height: 1.0,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
        ),
      ],
    );
  }
}

/// Progresso de assinatura — barra fina + contagem (done/total).
class _SignatureProgress extends StatelessWidget {
  const _SignatureProgress({
    required this.done,
    required this.total,
    required this.tone,
  });
  final int done;
  final int total;
  final Color tone;
  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final frac = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    final complete = total > 0 && done >= total;
    final color = complete
        ? (isDark ? AppColors.status.successDarkMode : AppColors.status.success)
        : tone;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              complete ? Icons.verified_rounded : Icons.draw_outlined,
              size: 13,
              color: color,
            ),
            const SizedBox(width: 6),
            Text(
              complete ? 'ASSINATURAS CONCLUÍDAS' : 'ASSINATURAS',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
                color: muted,
                letterSpacing: 1.0,
              ),
            ),
            const Spacer(),
            Text(
              '$done/$total',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: frac,
            minHeight: 5,
            backgroundColor: ThemeHelpers.borderLightColor(
              context,
            ).withValues(alpha: 0.9),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

class _FooterMeta extends StatelessWidget {
  const _FooterMeta({
    required this.creatorName,
    required this.createdAt,
    this.saleUnit,
    this.teamName,
    this.teamColor,
  });
  final String? creatorName;
  final DateTime? createdAt;
  final String? saleUnit;
  final String? teamName;
  final Color? teamColor;
  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final dateStr = createdAt != null
        ? DateFormat('dd/MM/yyyy', 'pt_BR').format(createdAt!.toLocal())
        : null;
    final creator = creatorName?.trim().isNotEmpty == true
        ? creatorName!
        : null;

    return Wrap(
      spacing: 12,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (creator != null)
          _MetaItem(
            leading: Icon(Icons.person_outline, size: 14, color: muted),
            text: creator,
          ),
        if (dateStr != null)
          _MetaItem(
            leading: Icon(Icons.schedule_outlined, size: 13, color: muted),
            text: dateStr,
          ),
        if (saleUnit != null && saleUnit!.isNotEmpty)
          _MetaItem(
            leading: Icon(Icons.storefront_outlined, size: 13, color: muted),
            text: saleUnit!,
          ),
        if (teamName != null && teamName!.isNotEmpty)
          _MetaItem(
            leading: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: teamColor ?? muted.withValues(alpha: 0.5),
              ),
            ),
            text: teamName!,
          ),
      ],
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.leading, required this.text});
  final Widget leading;
  final String text;
  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        leading,
        const SizedBox(width: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: muted,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ],
    );
  }
}

/// Menu de ações da ficha — o mesmo do web, na mesma ordem (lista e detalhe).
class SaleFormActionsMenu extends StatelessWidget {
  const SaleFormActionsMenu({
    super.key,
    required this.rules,
    required this.onAction,
    this.noDetalhe = false,
  });
  final SaleFormRowRules rules;
  final ValueChanged<SaleFormRowAction> onAction;

  /// Dentro do detalhe: sem "Ver" (já está vendo) e sem "Editar" (o detalhe
  /// tem o botão próprio).
  final bool noDetalhe;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final textColor = ThemeHelpers.textColor(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final danger =
        dark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final warn =
        dark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final info = dark ? AppColors.status.infoDarkMode : AppColors.status.info;
    final ok =
        dark ? AppColors.status.successDarkMode : AppColors.status.success;
    final role = ModuleAccessService.instance.userRole;
    final deleted = rules.form.deletedAt != null;
    final motivo = rules.auditMotivo;

    return PopupMenuButton<SaleFormRowAction>(
      tooltip: 'Ações',
      padding: EdgeInsets.zero,
      splashRadius: 20,
      offset: const Offset(0, 10),
      color: ThemeHelpers.cardBackgroundColor(context),
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      constraints: const BoxConstraints(minWidth: 236, maxWidth: 300),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.7),
        ),
      ),
      icon: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.more_horiz_rounded, size: 19, color: muted),
      ),
      itemBuilder: (ctx) {
        final items = <PopupMenuEntry<SaleFormRowAction>>[
          if (!noDetalhe)
            _item(SaleFormRowAction.ver, Icons.visibility_outlined,
                'Ver (somente leitura)', muted, textColor),
          _item(SaleFormRowAction.usuariosVinculados, Icons.group_outlined,
              'Ver usuários vinculados', muted, textColor),
          if (rules.canChangeTeam)
            _item(SaleFormRowAction.trocarEquipe, Icons.swap_horiz_rounded,
                'Trocar equipe', muted, textColor),
          if (motivo != null)
            _item(SaleFormRowAction.motivo, Icons.comment_outlined,
                'Ver motivo', muted, textColor),
        ];
        if (!deleted) {
          final acoes = <PopupMenuEntry<SaleFormRowAction>>[
            if (rules.canPdf) ...[
              _item(SaleFormRowAction.pdfSistema,
                  Icons.picture_as_pdf_outlined, 'PDF (sem assinatura)',
                  info, textColor),
              _item(SaleFormRowAction.pdfAssinaturas,
                  Icons.picture_as_pdf_rounded, 'PDF (com assinaturas)',
                  info, textColor),
            ],
            if (rules.canTransfer(role: role))
              _item(SaleFormRowAction.transferir,
                  Icons.swap_horiz_rounded, 'Transferir responsabilidade',
                  muted, textColor),
            if (rules.canDistrato)
              _item(SaleFormRowAction.distrato, Icons.cancel_outlined,
                  'Distratar (cancelar venda)', warn, textColor),
            if (rules.showSignatures)
              _item(
                SaleFormRowAction.assinaturas,
                rules.hasActiveSignatures
                    ? Icons.assignment_outlined
                    : Icons.draw_outlined,
                rules.signaturesLabel,
                ok,
                textColor,
              ),
            if (rules.canCancelSignaturesForResend)
              _item(SaleFormRowAction.cancelarAssinaturas,
                  Icons.remove_done_rounded, 'Cancelar assinaturas (reenvio)',
                  danger, danger),
            if (rules.showEdit && !noDetalhe)
              rules.canEdit
                  ? _item(SaleFormRowAction.editar, Icons.edit_outlined,
                      'Editar', muted, textColor)
                  : _item(SaleFormRowAction.editar, Icons.lock_outline_rounded,
                      'Editar', muted, muted, hint: 'bloqueada'),
            if (rules.canCancelFicha)
              _item(SaleFormRowAction.cancelarFicha, Icons.block_rounded,
                  'Cancelar ficha', warn, textColor),
          ];
          if (acoes.isNotEmpty) {
            items
              ..add(const PopupMenuDivider(height: 8))
              ..addAll(acoes);
          }
        }
        if (rules.canExclude) {
          items
            ..add(const PopupMenuDivider(height: 8))
            ..add(_item(SaleFormRowAction.excluir,
                Icons.delete_outline_rounded, 'Excluir', danger, danger));
        }
        return items;
      },
      onSelected: onAction,
    );
  }

  PopupMenuItem<SaleFormRowAction> _item(
    SaleFormRowAction value,
    IconData icon,
    String label,
    Color iconColor,
    Color textColor, {
    String? hint,
  }) {
    return PopupMenuItem<SaleFormRowAction>(
      value: value,
      height: 44,
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w700, color: textColor),
            ),
          ),
          if (hint != null) ...[
            const SizedBox(width: 8),
            Text(
              hint,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
