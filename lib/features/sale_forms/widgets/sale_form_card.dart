import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/sale_forms_service.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../sale_form_list_display.dart';
import '../sale_forms_relatorio_export.dart' show saleFormsExportPropertyLine;
import 'sale_form_actions_sheet.dart';
import 'sale_form_row_rules.dart';
import 'sale_form_tones.dart';

/// Uma ficha de venda na lista (01/10/2026) — LINHA FLUSH, como a lista de
/// Imóveis: encostada nas margens, separada por filete, sem cartão. Antes era
/// um cartão com 7 faixas empilhadas (nº, comprador, tipo, imóvel, divisória,
/// valor, assinaturas, rodapé) e a lista ficava "extremamente vertical".
///
/// Três linhas, lidas da esquerda para a direita:
///   1. nº · status (ponto na cor)                 valor da venda
///   2. COMPRADOR (o que a pessoa procura)           comissão
///   3. tipo · imóvel · autor · data     [assinaturas 2/5 → ação]
/// e o botão de ações (folha nova) na ponta.
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

  /// Ações da ficha (mesmas do menu do web, na mesma regra).
  final ValueChanged<SaleFormRowAction>? onAction;

  static final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  static final _moneyCompacto = NumberFormat.compactCurrency(
    locale: 'pt_BR',
    symbol: 'R\$',
    decimalDigits: 1,
  );

  @override
  Widget build(BuildContext context) {
    final f = saleForm;
    final rules = SaleFormRowRules(f);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final text = ThemeHelpers.textColor(context);
    final tom = SaleFormTom.doStatus(context, f.status);
    final excluida = f.deletedAt != null;

    final temValor = f.saleValue != null && f.saleValue! > 0;
    final comissao = f.totalCommission != null && f.totalCommission! > 0
        ? f.totalCommission!
        : null;

    final comprador = f.buyerName?.trim().isNotEmpty == true
        ? f.buyerName!.trim()
        : 'Comprador não informado';

    // Web (`formatSaleFormPropertyLine`): endereço completo ou, em
    // Lançamento/MCMV, incorporadora · empreendimento · unidade.
    final imovelWeb = saleFormsExportPropertyLine(f.raw);
    final imovel = imovelWeb == '—' ? '' : imovelWeb;
    final data = f.createdAt != null
        ? DateFormat('dd/MM/yy', 'pt_BR').format(f.createdAt!.toLocal())
        : null;
    final meta = [
      f.saleFormType.label,
      if (f.creatorName?.trim().isNotEmpty == true) f.creatorName!.trim(),
      ?data,
    ].join(' · ');
    // Web (card mobile e tabela): Vendedor, Unidade e Equipe.
    final vendedor = saleFormSellerListLabel(f);
    final pessoas = [
      if (vendedor != '—') 'Vendedor: $vendedor',
      if (f.saleUnit?.trim().isNotEmpty == true) 'Unidade: ${f.saleUnit!.trim()}',
      if (f.teamName?.trim().isNotEmpty == true) 'Equipe: ${f.teamName!.trim()}',
    ].join(' · ');

    final sigTotal = f.assinaturasTotal;
    final sigDone = f.assinaturasAssinadas;
    final podeAssinaturas = onAction != null && rules.showSignatures;
    final mostraAssinaturas =
        f.status != SaleFormStatus.canceled && (sigTotal > 0 || podeAssinaturas);

    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1 · nº + status  |  valor
                  Row(
                    children: [
                      Flexible(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: f.formNumber.isEmpty
                                    ? 'Ficha'
                                    : 'Nº ${f.formNumber}',
                                style: TextStyle(
                                  color: muted,
                                  fontWeight: FontWeight.w800,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              const TextSpan(text: '   '),
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: excluida
                                        ? SaleFormTom.erro(context).sinal
                                        : tom.sinal,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              TextSpan(
                                text: excluida
                                    ? ' Excluída'
                                    // Pílula do web: rótulo curto.
                                    : ' ${f.statusShortLabel}',
                                style: TextStyle(
                                  color: excluida
                                      ? SaleFormTom.erro(context).texto
                                      : tom.texto,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, height: 1.2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        temValor
                            ? (f.saleValue! >= 10000000
                                  ? _moneyCompacto.format(f.saleValue)
                                  : _money.format(f.saleValue))
                            : 'Sem valor',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                          color: temValor ? text : muted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // 2 · comprador  |  comissão
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          comprador,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.2,
                            height: 1.2,
                            color: text,
                          ),
                        ),
                      ),
                      if (comissao != null) ...[
                        const SizedBox(width: 10),
                        Text(
                          'com. ${_moneyCompacto.format(comissao)}',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: muted,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (pessoas.isNotEmpty) ...[
                    Text(
                      pessoas,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: muted,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  if (imovel.isNotEmpty) ...[
                    Text(
                      imovel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted, height: 1.3),
                    ),
                    const SizedBox(height: 2),
                  ],
                  // 3 · tipo, autor, data
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: muted, height: 1.25),
                  ),
                  // 4 · rastreabilidade (web: "Rastreabilidade" na linha) —
                  // último evento da auditoria, recusa da trava, desativação.
                  const SizedBox(height: 3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1.5),
                        child: Icon(
                          f.ativo || excluida
                              ? LucideIcons.history
                              : LucideIcons.circleAlert,
                          size: 12,
                          color: f.ativo || excluida
                              ? muted
                              : SaleFormTom.aviso(context).texto,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          saleFormRastreioLinha(f),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: muted,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (mostraAssinaturas) ...[
                    const SizedBox(height: 8),
                    _Assinaturas(
                      done: sigDone,
                      total: sigTotal,
                      tom: tom,
                      acao: podeAssinaturas
                          ? (rules.hasActiveSignatures
                                ? 'Ver assinaturas'
                                : 'Enviar para assinar')
                          : null,
                      onAcao: podeAssinaturas
                          ? () => onAction!(SaleFormRowAction.assinaturas)
                          : null,
                    ),
                  ],
                ],
              ),
            ),
            if (onAction != null) ...[
              const SizedBox(width: 4),
              SaleFormActionsMenu(rules: rules, onAction: onAction!),
            ],
          ],
        ),
      ),
    );
  }
}

/// Andamento das assinaturas numa linha: barrinha + "2 de 5 assinaram" e a
/// ação ali mesmo (enviar ou ver), sem abrir a ficha.
class _Assinaturas extends StatelessWidget {
  const _Assinaturas({
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
    final completo = total > 0 && done >= total;
    final cor = completo ? SaleFormTom.sucesso(context) : tom;
    final frase = total == 0
        ? 'Assinaturas não enviadas'
        : completo
        ? 'Todos assinaram'
        : '$done de $total assinaram';
    return Row(
      children: [
        SizedBox(
          width: 44,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 5,
              color: cor.sinal,
              backgroundColor: ThemeHelpers.borderLightColor(context),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            frase,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: total == 0 ? muted : cor.texto,
            ),
          ),
        ),
        if (acao != null && onAcao != null)
          InkWell(
            onTap: onAcao,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    acao!,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Esqueleto fiel à linha: nº+status | valor, comprador | comissão, meta,
/// assinaturas — mesma altura e filete.
class SaleFormCardSkeleton extends StatelessWidget {
  const SaleFormCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SkeletonText(width: 120, height: 11),
              Spacer(),
              SkeletonText(width: 86, height: 13),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: SkeletonText(height: 15)),
              SizedBox(width: 40),
              SkeletonText(width: 70, height: 11),
            ],
          ),
          SizedBox(height: 8),
          SkeletonText(width: 210, height: 11),
          SizedBox(height: 10),
          SkeletonText(width: 150, height: 9),
        ],
      ),
    );
  }
}

/// Botão de ações da ficha (lista e detalhe). Abre a folha de ações
/// (`showSaleFormActionsSheet`) — o antigo menu suspenso ficou para trás.
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
    return Tooltip(
      message: 'Ações da ficha',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          final a = await showSaleFormActionsSheet(
            context,
            rules: rules,
            noDetalhe: noDetalhe,
          );
          if (a != null) onAction(a);
        },
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(LucideIcons.ellipsisVertical, size: 19, color: muted),
        ),
      ),
    );
  }
}
