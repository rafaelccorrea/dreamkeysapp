import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/sale_forms_service.dart';
import 'sale_form_row_rules.dart';
import 'sale_form_tones.dart';

/// Ações de uma ficha de venda (01/10/2026) — substitui o menu suspenso de
/// "3 pontinhos". Folha que sobe do rodapé com a ficha no topo (nº, status,
/// comprador, valor) e as ações em três blocos, na ordem de uso:
///
///  • atalhos (Ver, Assinaturas, PDF, Editar) em chapas lado a lado;
///  • gestão (vinculados, trocar equipe, transferir, motivo, distrato)
///    em linhas com a explicação de cada uma;
///  • o que desfaz trabalho (cancelar assinaturas, cancelar, excluir) no fim,
///    em vermelho, separado do resto.
///
/// As MESMAS ações e regras do menu do web (`SaleFormRowRules`). O que a
/// pessoa não pode fazer aparece travado com o motivo — nunca some.
Future<SaleFormRowAction?> showSaleFormActionsSheet(
  BuildContext context, {
  required SaleFormRowRules rules,
  bool noDetalhe = false,
}) {
  return showModalBottomSheet<SaleFormRowAction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (_) => _SaleFormActionsSheet(rules: rules, noDetalhe: noDetalhe),
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
  final SaleFormRowAction value;
  final IconData icon;
  final String label;
  final String? detalhe;

  /// Motivo de a ação estar travada (aparece no lugar do detalhe).
  final String? bloqueio;
}

class _SaleFormActionsSheet extends StatelessWidget {
  const _SaleFormActionsSheet({required this.rules, required this.noDetalhe});
  final SaleFormRowRules rules;
  final bool noDetalhe;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final f = rules.form;
    final deleted = f.deletedAt != null;
    final role = ModuleAccessService.instance.userRole;

    final atalhos = <_Acao>[
      if (!noDetalhe)
        const _Acao(
          value: SaleFormRowAction.ver,
          icon: LucideIcons.eye,
          label: 'Ver ficha',
        ),
      if (!deleted && rules.showSignatures)
        _Acao(
          value: SaleFormRowAction.assinaturas,
          icon: rules.hasActiveSignatures
              ? LucideIcons.signature
              : LucideIcons.send,
          label: rules.hasActiveSignatures ? 'Assinaturas' : 'Enviar p/ assinar',
        ),
      if (!deleted && rules.canPdf) ...[
        const _Acao(
          value: SaleFormRowAction.pdfSistema,
          icon: LucideIcons.fileText,
          label: 'PDF da ficha',
        ),
        const _Acao(
          value: SaleFormRowAction.pdfAssinaturas,
          icon: LucideIcons.fileCheck,
          label: 'PDF assinado',
        ),
      ],
      if (!deleted && rules.showEdit && !noDetalhe)
        _Acao(
          value: SaleFormRowAction.editar,
          icon: LucideIcons.pencil,
          label: 'Editar',
          bloqueio: rules.canEdit ? null : rules.editBlockReason,
        ),
    ];

    final motivo = rules.auditMotivo;
    final gestao = <_Acao>[
      const _Acao(
        value: SaleFormRowAction.usuariosVinculados,
        icon: LucideIcons.users,
        label: 'Usuários vinculados',
        detalhe: 'Quem participa desta ficha e vê o andamento.',
      ),
      if (rules.canChangeTeam)
        const _Acao(
          value: SaleFormRowAction.trocarEquipe,
          icon: LucideIcons.arrowLeftRight,
          label: 'Trocar equipe',
          detalhe: 'Muda a equipe dona da ficha (entra nos números dela).',
        ),
      if (!deleted && rules.canTransfer(role: role))
        const _Acao(
          value: SaleFormRowAction.transferir,
          icon: LucideIcons.userRoundCog,
          label: 'Transferir responsabilidade',
          detalhe: 'Passa a ficha para outro corretor cuidar.',
        ),
      if (motivo != null)
        _Acao(
          value: SaleFormRowAction.motivo,
          icon: LucideIcons.messageSquareText,
          label: motivo.title,
          detalhe: 'Ver o que foi registrado.',
        ),
      if (!deleted && rules.canDistrato)
        const _Acao(
          value: SaleFormRowAction.distrato,
          icon: LucideIcons.fileX2,
          label: 'Distratar (cancelar venda)',
          detalhe: 'A venda cai e o Financeiro pede a prova do distrato.',
        ),
    ];

    final desfazer = <_Acao>[
      if (!deleted && rules.canCancelSignaturesForResend)
        const _Acao(
          value: SaleFormRowAction.cancelarAssinaturas,
          icon: LucideIcons.rotateCcw,
          label: 'Cancelar assinaturas',
          detalhe: 'Invalida os links para corrigir e reenviar.',
        ),
      if (!deleted && rules.canCancelFicha)
        const _Acao(
          value: SaleFormRowAction.cancelarFicha,
          icon: LucideIcons.ban,
          label: 'Cancelar ficha',
          detalhe: 'Encerra a ficha com um motivo.',
        ),
      if (rules.canExclude)
        const _Acao(
          value: SaleFormRowAction.excluir,
          icon: LucideIcons.trash2,
          label: 'Excluir',
          detalhe: 'Some da lista; fica guardada para auditoria.',
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
            _Cabecalho(form: f),
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
                      const _Rotulo('GESTÃO DA FICHA'),
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

/// A ficha no topo da folha: para a pessoa ter certeza de em qual está
/// mexendo antes de tocar numa ação.
class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.form});
  final SaleForm form;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final tom = SaleFormTom.doStatus(context, form.status);
    final money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final valor = form.saleValue != null && form.saleValue! > 0
        ? money.format(form.saleValue)
        : null;
    final comprador = form.buyerName?.trim().isNotEmpty == true
        ? form.buyerName!.trim()
        : 'Comprador não informado';
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
                      form.formNumber.isEmpty ? 'Ficha' : 'Nº ${form.formNumber}',
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
                          form.statusLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: tom.texto,
                          ),
                        ),
                      ],
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(acao.bloqueio!),
                behavior: SnackBarBehavior.floating,
              ),
            );
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(acao.bloqueio!),
              behavior: SnackBarBehavior.floating,
            ),
          );
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
