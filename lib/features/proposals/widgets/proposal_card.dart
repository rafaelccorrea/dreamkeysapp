import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/purchase_proposals_service.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../../sale_forms/widgets/sale_form_tones.dart';
import '../utils/proposal_edit_rules.dart';
import 'proposal_actions_sheet.dart';
import 'proposal_row_actions.dart';

/// Uma ficha de proposta na lista (01/10/2026) — LINHA FLUSH, no molde da
/// lista de fichas de venda: encostada nas margens, separada por filete, sem
/// cartão. Antes era um cartão com 8 faixas empilhadas (nº, comprador,
/// imóvel, divisória, valor, condições, trilho, rodapé, botão) e a lista
/// ficava "extremamente vertical".
///
/// Três linhas, lidas da esquerda para a direita:
///   1. nº · status (ponto na cor)                 valor proposto
///   2. COMPRADOR (o que a pessoa procura)     entrada (ou comissão)
///   3. imóvel · autor · data
/// e a faixa das etapas de assinatura (1 de 3 · Comprador → ação ali
/// mesmo), com o botão de ações (folha) na ponta.
class ProposalCard extends StatelessWidget {
  const ProposalCard({
    super.key,
    required this.proposal,
    required this.accent,
    this.atalho,
    this.onTap,
    this.onContinue,
    this.onShowHistorico,
    this.onAction,
  });

  final PurchaseProposal proposal;
  final Color accent;
  final VoidCallback? onTap;

  /// Atalho da linha ([proposalAtalhoDaLinha], mesmas condições do web).
  final ProposalAtalho? atalho;

  /// Ação do [atalho] (enviar para assinar / assinaturas / continuar).
  final VoidCallback? onContinue;

  /// Proposta finalizada: a faixa leva ao histórico das assinaturas.
  final VoidCallback? onShowHistorico;

  /// Ações da proposta — mesmas ações e regras do web.
  final ValueChanged<ProposalRowAction>? onAction;

  static final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  static final _moneyCompacto = NumberFormat.compactCurrency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  /// Percentual sem casas redundantes (5.0 → "5", 5.5 → "5,5").
  static String _pct(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString().replaceAll('.', ',');
  }

  @override
  Widget build(BuildContext context) {
    final p = proposal;
    final rules = ProposalRowRules(p);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final text = ThemeHelpers.textColor(context);
    final excluida = p.deletedAt != null;
    final tom = excluida
        ? SaleFormTom.erro(context)
        : proposalStatusTom(context, p.status);

    final valor = p.proposedPrice;
    final temValor = valor != null && valor > 0;

    // Segundo valor da linha 2: a entrada (o que mais pesa numa proposta de
    // compra); sem entrada, a comissão combinada.
    final entrada = p.downPayment != null && p.downPayment! > 0
        ? p.downPayment!
        : null;
    final comissao =
        p.commissionPercentage != null && p.commissionPercentage! > 0
        ? p.commissionPercentage!
        : null;
    final secundario = entrada != null
        ? 'entrada ${_moneyCompacto.format(entrada)}'
        : comissao != null
        ? 'com. ${_pct(comissao)}%'
        : null;

    final comprador = p.proponentName?.trim().isNotEmpty == true
        ? p.proponentName!.trim()
        : 'Comprador não informado';

    final codigo = p.propertyCode?.trim() ?? '';
    final bairro = p.propertyNeighborhood?.trim() ?? '';
    final cidade = p.propertyCity?.trim() ?? '';
    final autor = p.creatorName?.trim() ?? '';
    final data = p.createdAt != null
        ? DateFormat('dd/MM/yy', 'pt_BR').format(p.createdAt!.toLocal())
        : null;
    final meta = [
      if (codigo.isNotEmpty) 'Cód. $codigo',
      if (bairro.isNotEmpty) bairro else if (cidade.isNotEmpty) cidade,
      if (autor.isNotEmpty) autor,
      ?data,
    ].join(' · ');

    // Faixa das etapas: some só na cancelada (lá não há o que acompanhar;
    // o motivo fica na folha de ações).
    final mostraEtapas = p.status != ProposalStatus.canceled;
    final finalizada = p.status == ProposalStatus.finalized;
    _AcaoDaEtapa? acao;
    final at = atalho;
    if (at != null && onContinue != null) {
      // Rótulos do botão da linha do web.
      acao = switch (at.tipo) {
        ProposalAtalhoTipo.enviar => _AcaoDaEtapa(
          'Enviar para assinatura',
          'Enviar',
          onContinue!,
        ),
        ProposalAtalhoTipo.assinaturasProprietario => _AcaoDaEtapa(
          'Assinaturas (Proprietário)',
          'Assinaturas',
          onContinue!,
        ),
        ProposalAtalhoTipo.continuar => _AcaoDaEtapa(
          'Continuar',
          'Continuar',
          onContinue!,
        ),
      };
    } else if (finalizada && !excluida && onShowHistorico != null) {
      acao = _AcaoDaEtapa('Ver histórico', 'Histórico', onShowHistorico!);
    }

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
                  // 1 · nº + status  |  valor proposto
                  Row(
                    children: [
                      Flexible(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: p.proposalNumber.isEmpty
                                    ? 'Proposta'
                                    : 'Nº ${p.proposalNumber}',
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
                                    color: tom.sinal,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              TextSpan(
                                text: excluida
                                    ? ' Excluída'
                                    : ' ${p.status.label}',
                                style: TextStyle(
                                  color: tom.texto,
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
                            ? (valor >= 10000000
                                  ? _moneyCompacto.format(valor)
                                  : _money.format(valor))
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
                  // 2 · comprador  |  entrada ou comissão
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
                      if (secundario != null) ...[
                        const SizedBox(width: 10),
                        Text(
                          secundario,
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
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    // 3 · imóvel, autor, data
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: muted,
                        height: 1.25,
                      ),
                    ),
                  ],
                  if (mostraEtapas) ...[
                    const SizedBox(height: 8),
                    _EtapasDaAssinatura(
                      etapa: p.etapa.number,
                      finalizada: finalizada,
                      excluida: excluida,
                      tom: tom,
                      acao: acao,
                    ),
                  ],
                ],
              ),
            ),
            if (onAction != null) ...[
              const SizedBox(width: 4),
              ProposalActionsMenu(rules: rules, onAction: onAction!),
            ],
          ],
        ),
      ),
    );
  }
}

/// Ação da faixa das etapas: rótulo inteiro e a versão curta (tela estreita
/// ou texto grande — nunca estoura).
class _AcaoDaEtapa {
  const _AcaoDaEtapa(this.rotulo, this.curto, this.onTap);
  final String rotulo;
  final String curto;
  final VoidCallback onTap;
}

/// As 3 etapas da assinatura numa linha (Comprador → Proprietário →
/// Corretor): três traços + "Etapa 2 de 3 · Proprietário" e a ação ali mesmo
/// (enviar, ver assinaturas, continuar), sem abrir a ficha. Conta que não
/// edita propostas não vê a ação (como no web).
class _EtapasDaAssinatura extends StatelessWidget {
  const _EtapasDaAssinatura({
    required this.etapa,
    required this.finalizada,
    required this.excluida,
    required this.tom,
    required this.acao,
  });

  final int etapa; // 1..3
  final bool finalizada;
  final bool excluida;
  final SaleFormTom tom;
  final _AcaoDaEtapa? acao;

  static const _nomes = ['Comprador', 'Proprietário', 'Corretor'];

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final hair = ThemeHelpers.borderLightColor(context);
    final atual = etapa.clamp(1, 3).toInt();
    final aberta = !finalizada && !excluida;
    final cor = excluida ? SaleFormTom(muted, muted) : tom;
    final frase = finalizada
        ? 'Três etapas assinadas'
        : excluida
        ? 'Parou na etapa $atual de 3'
        : 'Etapa $atual de 3 · ${_nomes[atual - 1]}';
    final brand = Theme.of(context).colorScheme.primary;

    Color traco(int i) {
      if (finalizada || i < atual) {
        return excluida ? muted.withValues(alpha: 0.5) : cor.sinal;
      }
      if (aberta && i == atual) return cor.sinal.withValues(alpha: 0.38);
      return hair;
    }

    return Semantics(
      label: 'Assinaturas: $frase',
      child: LayoutBuilder(
        builder: (context, c) {
          final escala = MediaQuery.textScalerOf(context).scale(1);
          final curto = c.maxWidth < 280 * escala;
          return Row(
            children: [
              for (var i = 1; i <= 3; i++)
                Container(
                  width: 10,
                  height: 5,
                  margin: EdgeInsets.only(left: i > 1 ? 3 : 0),
                  decoration: BoxDecoration(
                    color: traco(i),
                    borderRadius: BorderRadius.circular(99),
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
                    color: cor.texto,
                  ),
                ),
              ),
              if (acao != null)
                InkWell(
                  onTap: acao!.onTap,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          curto ? acao!.curto : acao!.rotulo,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: brand,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: brand,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Esqueleto fiel à linha: nº+status | valor, comprador | entrada, meta,
/// etapas — mesma altura e filete.
class ProposalCardSkeleton extends StatelessWidget {
  const ProposalCardSkeleton({super.key});

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

/// Botão de ações da proposta. Abre a folha de ações
/// (`showProposalActionsSheet`) — o antigo menu suspenso ficou para trás.
class ProposalActionsMenu extends StatelessWidget {
  const ProposalActionsMenu({
    super.key,
    required this.rules,
    required this.onAction,
  });
  final ProposalRowRules rules;
  final ValueChanged<ProposalRowAction> onAction;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Tooltip(
      message: 'Ações da proposta',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          final a = await showProposalActionsSheet(context, rules: rules);
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
