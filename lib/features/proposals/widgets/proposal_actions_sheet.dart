import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/purchase_proposals_service.dart';
import '../../sale_forms/widgets/sale_form_tones.dart';
import 'proposal_row_actions.dart';

/// Ações de uma ficha de proposta (01/10/2026) — substitui o menu suspenso
/// de "3 pontinhos", no molde da folha das fichas de venda. Sobe do rodapé
/// com a proposta no topo (nº, status, etapa, comprador, valor) e as ações
/// em três blocos, na ordem de uso:
///
///  • atalhos (PDF, assinaturas, editar, histórico) em chapas lado a lado;
///  • gestão (usuários vinculados, motivo registrado) em linhas com a
///    explicação de cada uma;
///  • o que desfaz trabalho (cancelar, excluir) no fim, em vermelho,
///    separado do resto.
///
/// As MESMAS ações e regras do menu de antes (`ProposalRowRules`, espelho do
/// web). Proposta aberta numa conta que não edita: assinaturas e edição
/// aparecem travadas com o motivo — nunca somem.
Future<ProposalRowAction?> showProposalActionsSheet(
  BuildContext context, {
  required ProposalRowRules rules,
}) {
  return showModalBottomSheet<ProposalRowAction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (_) => _ProposalActionsSheet(rules: rules),
  );
}

class _Acao {
  const _Acao({
    required this.value,
    required this.icon,
    required this.label,
    this.detalhe,
    this.bloqueio,
  });
  final ProposalRowAction value;
  final IconData icon;
  final String label;
  final String? detalhe;

  /// Motivo de a ação estar travada (aparece no lugar do detalhe).
  final String? bloqueio;
}

class _ProposalActionsSheet extends StatelessWidget {
  const _ProposalActionsSheet({required this.rules});
  final ProposalRowRules rules;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final p = rules.p;
    final etapa = p.etapa.number;
    final trava = rules.travadaPorPermissao;
    const motivoTrava = ProposalRowRules.motivoDaTrava;

    final atalhos = <_Acao>[
      if (rules.canPdf)
        _Acao(
          value: ProposalRowAction.pdf,
          icon: LucideIcons.fileDown,
          label: rules.finalizada ? 'PDF consolidado' : 'PDF da etapa $etapa',
        ),
      if (rules.canSignatures || trava)
        _Acao(
          value: ProposalRowAction.assinaturas,
          icon: LucideIcons.signature,
          label: 'Assinaturas da etapa $etapa',
          bloqueio: trava ? motivoTrava : null,
        ),
      if (rules.canEdit || trava)
        _Acao(
          value: ProposalRowAction.editar,
          icon: LucideIcons.pencil,
          label: 'Editar',
          bloqueio: trava ? motivoTrava : null,
        ),
      const _Acao(
        value: ProposalRowAction.historico,
        icon: LucideIcons.history,
        label: 'Histórico',
      ),
    ];

    final motivo = rules.auditMotivo;
    final gestao = <_Acao>[
      const _Acao(
        value: ProposalRowAction.usuariosVinculados,
        icon: LucideIcons.users,
        label: 'Usuários vinculados',
        detalhe: 'Quem pode ver esta proposta.',
      ),
      if (motivo != null)
        _Acao(
          value: ProposalRowAction.motivo,
          icon: LucideIcons.messageSquareText,
          label: motivo.title,
          detalhe: 'Ver o que foi registrado.',
        ),
    ];

    final desfazer = <_Acao>[
      if (rules.canCancel)
        const _Acao(
          value: ProposalRowAction.cancelar,
          icon: LucideIcons.ban,
          label: 'Cancelar proposta',
          detalhe: 'Encerra com um motivo; não vai mais para assinatura.',
        ),
      if (rules.canDelete)
        const _Acao(
          value: ProposalRowAction.excluir,
          icon: LucideIcons.trash2,
          label: 'Excluir',
          detalhe: 'Sai da listagem e fica em auditoria. Motivo obrigatório.',
        ),
    ];

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: mq.size.height * 0.88),
      child: Container(
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(
            top: BorderSide(color: ThemeHelpers.borderColor(context)),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: ThemeHelpers.borderColor(context),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            _Cabecalho(proposal: p),
            Divider(height: 1, color: ThemeHelpers.borderLightColor(context)),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  14,
                  16,
                  16 + mq.viewPadding.bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (atalhos.isNotEmpty) _GradeDeAtalhos(acoes: atalhos),
                    if (gestao.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      const _Rotulo('GESTÃO DA PROPOSTA'),
                      const SizedBox(height: 4),
                      for (final a in gestao) _LinhaDeAcao(acao: a),
                    ],
                    if (desfazer.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Divider(
                        height: 1,
                        color: ThemeHelpers.borderLightColor(context),
                      ),
                      const SizedBox(height: 6),
                      for (final a in desfazer)
                        _LinhaDeAcao(acao: a, perigo: true),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A proposta no topo da folha: para a pessoa ter certeza de em qual está
/// mexendo antes de tocar numa ação.
class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.proposal});
  final PurchaseProposal proposal;

  @override
  Widget build(BuildContext context) {
    final p = proposal;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final excluida = p.deletedAt != null;
    final tom = excluida
        ? SaleFormTom.erro(context)
        : proposalStatusTom(context, p.status);
    final money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final valor = p.proposedPrice != null && p.proposedPrice! > 0
        ? money.format(p.proposedPrice)
        : null;
    final comprador = p.proponentName?.trim().isNotEmpty == true
        ? p.proponentName!.trim()
        : 'Comprador não informado';
    final etapa = p.status == ProposalStatus.processing && !excluida
        ? 'Etapa ${p.etapa.number} de 3'
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      p.proposalNumber.isEmpty
                          ? 'Proposta'
                          : 'Nº ${p.proposalNumber}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                        color: muted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: tom.sinal,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          excluida ? 'Excluída' : p.status.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: tom.texto,
                          ),
                        ),
                      ],
                    ),
                    if (etapa != null)
                      Text(
                        etapa,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: muted,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  comprador,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                    height: 1.15,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ],
            ),
          ),
          if (valor != null) ...[
            const SizedBox(width: 12),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topRight,
                child: Text(
                  valor,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Rotulo extends StatelessWidget {
  const _Rotulo(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.3,
        color: ThemeHelpers.textSecondaryColor(context),
      ),
    );
  }
}

/// Atalhos em chapas iguais: 2 por linha no celular, até 4 em tela larga.
/// Altura pelo conteúdo (sem aspect ratio fixo) — rótulo longo quebra em 2
/// linhas sem estourar.
class _GradeDeAtalhos extends StatelessWidget {
  const _GradeDeAtalhos({required this.acoes});
  final List<_Acao> acoes;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 8.0;
        final colunas = c.maxWidth >= 520 ? 4 : 2;
        final w = (c.maxWidth - gap * (colunas - 1)) / colunas;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final a in acoes)
              SizedBox(width: w, child: _ChapaDeAtalho(acao: a)),
          ],
        );
      },
    );
  }
}

/// Toque numa ação travada: diz o porquê, a folha fica aberta.
void _avisarTrava(BuildContext context, String motivo) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(motivo), behavior: SnackBarBehavior.floating),
  );
}

class _ChapaDeAtalho extends StatelessWidget {
  const _ChapaDeAtalho({required this.acao});
  final _Acao acao;

  @override
  Widget build(BuildContext context) {
    final travada = acao.bloqueio != null;
    final brand = Theme.of(context).colorScheme.primary;
    final texto = travada
        ? ThemeHelpers.textSecondaryColor(context)
        : ThemeHelpers.textColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark
          ? AppColors.background.backgroundSecondaryDarkMode
          : AppColors.background.backgroundSecondary,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          if (travada) {
            _avisarTrava(context, acao.bloqueio!);
            return;
          }
          Navigator.of(context).pop(acao.value);
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ThemeHelpers.borderLightColor(context)),
          ),
          child: Row(
            children: [
              Icon(
                travada ? LucideIcons.lock : acao.icon,
                size: 19,
                color: travada ? texto : brand,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  acao.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    color: texto,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinhaDeAcao extends StatelessWidget {
  const _LinhaDeAcao({required this.acao, this.perigo = false});
  final _Acao acao;
  final bool perigo;

  @override
  Widget build(BuildContext context) {
    final travada = acao.bloqueio != null;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final perigoCor = SaleFormTom.erro(context).texto;
    final cor = travada
        ? muted
        : perigo
        ? perigoCor
        : ThemeHelpers.textColor(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        if (travada) {
          _avisarTrava(context, acao.bloqueio!);
          return;
        }
        Navigator.of(context).pop(acao.value);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: (perigo ? perigoCor : muted).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                travada ? LucideIcons.lock : acao.icon,
                size: 18,
                color: perigo ? perigoCor : cor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    acao.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      color: cor,
                    ),
                  ),
                  if ((acao.bloqueio ?? acao.detalhe) != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      acao.bloqueio ?? acao.detalhe!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: muted),
          ],
        ),
      ),
    );
  }
}
