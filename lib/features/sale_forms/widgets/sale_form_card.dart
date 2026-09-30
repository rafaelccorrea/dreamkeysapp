import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/sale_forms_service.dart';
import '../../../shared/widgets/skeleton_box.dart';
import 'sale_form_row_rules.dart';
import 'sale_form_tones.dart';

/// Card de uma ficha de venda na listagem (mobile).
///
/// Card flush simples (sem faixa lateral de status — o status vive na
/// pílula), com a informação que evita abrir a ficha: comprador, tipo e
/// vendedor, contexto do imóvel, valor + comissão, assinaturas (com a ação
/// principal ali mesmo: enviar ou revisar) e rodapé (autoria, data, equipe).
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

    final tom = SaleFormTom.doStatus(context, saleForm.status);
    final isCanceled = saleForm.status == SaleFormStatus.canceled;
    final excluida = saleForm.deletedAt != null;

    final money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final temValor = saleForm.saleValue != null && saleForm.saleValue! > 0;
    final priceText =
        temValor ? money.format(saleForm.saleValue!) : 'Não informado';
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
    // Ação principal no próprio item: a mesma "Assinaturas" do menu, com a
    // mesma regra (update + não finalizada/cancelada/excluída).
    final podeAssinaturas = onAction != null && rules.showSignatures;
    final showSig = (sigTotal > 0 && !isCanceled) || podeAssinaturas;

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
            // Modo claro: só o crisp de 1px — quem separa é a borda.
            boxShadow: isDark ? null : ThemeHelpers.cardShadow(context),
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
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _NumberBadge(
                                accent: accent,
                                number: saleForm.formNumber,
                              ),
                              _StatusPill(
                                tom: tom,
                                label: saleForm.statusLabel.toUpperCase(),
                              ),
                              if (excluida)
                                _StatusPill(
                                  tom: SaleFormTom.erro(context),
                                  label: 'EXCLUÍDA',
                                  icon: Icons.delete_outline_rounded,
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
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              _TypeBadge(label: saleForm.saleFormType.label),
                              if (sellerName != null &&
                                  sellerName.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Flexible(
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
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: _PropertyContextLine(
                      code: propCode,
                      location: propLoc,
                    ),
                  ),
                ],

                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: ThemeHelpers.borderLightColor(
                      context,
                    ).withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Métricas: valor + comissão ─────────────────
                Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        flex: 3,
                        child: _Metric(
                          label: 'VALOR DA VENDA',
                          value: priceText,
                          emphasis: true,
                          vazio: !temValor,
                        ),
                      ),
                      if (commissionText != null) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: _Metric(
                            label: 'COMISSÃO',
                            value: commissionText,
                            alignEnd: true,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // ── Assinaturas (estado + ação principal) ──────
                if (showSig) ...[
                  const SizedBox(height: 13),
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: _AssinaturasFaixa(
                      done: sigDone,
                      total: sigTotal,
                      tom: tom,
                      acao: podeAssinaturas
                          ? (rules.hasActiveSignatures ? 'Revisar' : 'Enviar')
                          : null,
                      onAcao: podeAssinaturas
                          ? () => onAction!(SaleFormRowAction.assinaturas)
                          : null,
                    ),
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
/// posições: Nº+status, comprador, tipo/vendedor, imóvel, divisória, valor +
/// comissão, faixa de assinaturas e rodapé). Usado na listagem enquanto
/// carrega e no fim da lista ao buscar a próxima página.
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
        boxShadow: isDark ? null : ThemeHelpers.cardShadow(context),
      ),
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabeçalho: Nº + status pill + menu
          Row(
            children: const [
              SkeletonBox(width: 58, height: 20, borderRadius: 6),
              SizedBox(width: 6),
              SkeletonBox(width: 92, height: 20, borderRadius: 999),
              Spacer(),
              SkeletonBox(width: 34, height: 34, borderRadius: 10),
            ],
          ),
          const SizedBox(height: 8),
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
          const SizedBox(height: 12),
          // Imóvel
          Row(
            children: const [
              SkeletonBox(width: 14, height: 14, borderRadius: 4),
              SizedBox(width: 6),
              SkeletonBox(width: 60, height: 14, borderRadius: 5),
              SizedBox(width: 8),
              Expanded(flex: 5, child: SkeletonText(height: 12)),
              Spacer(flex: 2),
            ],
          ),
          const SizedBox(height: 13),
          const SkeletonBox(width: double.infinity, height: 1),
          const SizedBox(height: 13),
          // Métricas: valor + comissão
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: const [
              Expanded(
                flex: 3,
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
                flex: 2,
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
          const SizedBox(height: 14),
          // Faixa de assinaturas
          Row(
            children: const [
              SkeletonBox(width: 120, height: 12, borderRadius: 6),
              Spacer(),
              SkeletonBox(width: 70, height: 26, borderRadius: 10),
            ],
          ),
          const SizedBox(height: 8),
          const SkeletonBox(width: double.infinity, height: 5, borderRadius: 3),
          const SizedBox(height: 15),
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
        number.isEmpty ? 'Sem nº' : 'Nº $number',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
  const _StatusPill({required this.tom, required this.label, this.icon});
  final SaleFormTom tom;
  final String label;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tom.sinal.withValues(alpha: isDark ? 0.16 : 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: tom.sinal.withValues(alpha: isDark ? 0.4 : 0.45),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: tom.texto),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: tom.texto,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
                fontSize: 10,
              ),
            ),
          ),
        ],
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
        maxLines: 1,
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
          // Código longo não empurra a localização para fora do card.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: ThemeHelpers.borderLightColor(
                  context,
                ).withValues(alpha: 0.8),
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

/// Métrica destacada (rótulo pequeno + valor forte). O valor nunca vira
/// reticências: em tela estreita ou fonte grande ele encolhe para caber.
class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.emphasis = false,
    this.alignEnd = false,
    this.vazio = false,
  });
  final String label;
  final String value;
  final bool emphasis;
  final bool alignEnd;
  final bool vazio;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final TextStyle? style;
    if (vazio) {
      style = theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: muted,
        height: 1.0,
      );
    } else if (emphasis) {
      style = theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w900,
        letterSpacing: -0.8,
        height: 1.0,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
    } else {
      style = theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w900,
        letterSpacing: -0.3,
        height: 1.0,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
    }
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: muted,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            fontSize: 9.5,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(value, maxLines: 1, softWrap: false, style: style),
        ),
      ],
    );
  }
}

/// Faixa de assinaturas: quantas assinaram (barra + contagem) e a ação
/// principal da ficha no próprio card — "Enviar" (nada enviado ainda) ou
/// "Revisar" (acompanhar/reenviar).
class _AssinaturasFaixa extends StatelessWidget {
  const _AssinaturasFaixa({
    required this.done,
    required this.total,
    required this.tom,
    this.acao,
    this.onAcao,
  });
  final int done;
  final int total;
  final SaleFormTom tom;
  final String? acao;
  final VoidCallback? onAcao;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final text = ThemeHelpers.textColor(context);
    final ok = SaleFormTom.sucesso(context);
    final semEnvio = total == 0;
    final complete = total > 0 && done >= total;
    final cor = complete ? ok : tom;
    final frac = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    final rotulo = semEnvio
        ? 'Ainda não enviada para assinatura'
        : complete
        ? 'Assinaturas concluídas'
        : 'Assinaturas';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              complete ? Icons.verified_rounded : Icons.draw_outlined,
              size: 14,
              color: semEnvio ? muted : cor.texto,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: rotulo),
                    if (!semEnvio)
                      TextSpan(
                        text: '  $done/$total',
                        style: TextStyle(
                          color: cor.texto,
                          fontWeight: FontWeight.w900,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
                // Duas linhas: ao lado do botão, em 320dp, o rótulo quebra
                // em vez de virar reticências.
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                  color: semEnvio ? muted : text,
                ),
              ),
            ),
            if (acao != null && onAcao != null) ...[
              const SizedBox(width: 8),
              _AcaoCompacta(label: acao!, tom: ok, onTap: onAcao!),
            ],
          ],
        ),
        if (!semEnvio) ...[
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 5,
              backgroundColor: ThemeHelpers.borderLightColor(
                context,
              ).withValues(alpha: 0.9),
              valueColor: AlwaysStoppedAnimation(cor.sinal),
            ),
          ),
        ],
      ],
    );
  }
}

/// Botão tonal curto dentro do card (não compete com o toque do card).
class _AcaoCompacta extends StatelessWidget {
  const _AcaoCompacta({
    required this.label,
    required this.tom,
    required this.onTap,
  });
  final String label;
  final SaleFormTom tom;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: tom.sinal.withValues(alpha: isDark ? 0.18 : 0.12),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.draw_outlined, size: 14, color: tom.texto),
              const SizedBox(width: 5),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: tom.texto,
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 16, color: tom.texto),
            ],
          ),
        ),
      ),
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
    final danger = SaleFormTom.erro(context).texto;
    final warn = SaleFormTom.aviso(context).texto;
    final info = SaleFormTom.info(context).texto;
    final ok = SaleFormTom.sucesso(context).texto;
    final role = ModuleAccessService.instance.userRole;
    final deleted = rules.form.deletedAt != null;
    final motivo = rules.auditMotivo;

    return PopupMenuButton<SaleFormRowAction>(
      tooltip: 'Ações da ficha',
      padding: EdgeInsets.zero,
      splashRadius: 20,
      offset: const Offset(0, 10),
      color: ThemeHelpers.cardBackgroundColor(context),
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      // Largo o bastante para "Cancelar assinaturas (reenvio)" inteiro; o
      // overlay do menu já se limita à largura da tela. Rótulo que ainda
      // assim não couber (fonte grande) quebra em 2 linhas.
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 320),
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: textColor,
                height: 1.2,
              ),
            ),
          ),
          if (hint != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: textColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                hint,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
