import 'dart:io' show Directory, File;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/purchase_proposals_service.dart';
import '../../sale_forms/widgets/sale_form_row_actions.dart'
    show askSaleFormReason, linkedUsersFromRaw, showFichaPeopleSheet,
        showFichaTextSheet;

/// Ações do menu da proposta, na ordem do menu web (`PurchaseProposalsPage`).
enum ProposalRowAction {
  pdf,
  assinaturas,
  editar,
  historico,
  usuariosVinculados,
  motivo,
  cancelar,
  excluir,
}

/// Regras do menu — espelho literal do web (29/09/2026).
class ProposalRowRules {
  ProposalRowRules(this.p)
      : _canUpdate = _has('proposal:update'),
        _canDelete = _has('proposal:delete'),
        _canViewAll = _has('proposal:view_all');

  final PurchaseProposal p;
  final bool _canUpdate;
  final bool _canDelete;
  final bool _canViewAll;

  static bool _has(String x) => ModuleAccessService.instance.hasPermission(x);

  bool get _deleted => p.deletedAt != null;
  bool get _processing => p.status == ProposalStatus.processing;
  bool get finalizada => p.status == ProposalStatus.finalized;
  bool get _canceled => p.status == ProposalStatus.canceled;

  bool get canPdf => !_deleted;
  bool get canSignatures => _canUpdate && !_deleted && _processing;
  bool get canEdit => _canUpdate && !_deleted && !finalizada && !_canceled;
  bool get canCancel => _canUpdate && !_deleted && _processing;
  bool get canDelete => _canDelete && !_deleted;

  /// PDF: consolidado quando finalizada; parcial da etapa atual senão.
  int? get etapaDoPdf => finalizada ? null : p.etapa.number;

  ({String title, String body})? get auditMotivo {
    if (!_canViewAll) return null;
    final del = p.deletionReason?.trim() ?? '';
    if (_deleted && del.isNotEmpty) {
      return (title: 'Motivo da exclusão', body: del);
    }
    final canc = p.cancellationReason?.trim() ?? '';
    if (_canceled && canc.isNotEmpty) {
      return (title: 'Motivo do cancelamento', body: canc);
    }
    return null;
  }
}

/// Menu de ações da proposta (duas linhas por item, como no web).
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
    final text = ThemeHelpers.textColor(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final danger = dark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final info = dark ? AppColors.status.infoDarkMode : AppColors.status.info;
    final ok = dark ? AppColors.status.successDarkMode : AppColors.status.success;
    final motivo = rules.auditMotivo;
    final etapa = rules.p.etapa.number;

    return PopupMenuButton<ProposalRowAction>(
      tooltip: 'Ações',
      padding: EdgeInsets.zero,
      offset: const Offset(0, 10),
      color: ThemeHelpers.cardBackgroundColor(context),
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 300),
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
        final topo = <PopupMenuEntry<ProposalRowAction>>[
          if (rules.canPdf)
            _item(ProposalRowAction.pdf, Icons.description_outlined,
                'Baixar PDF',
                rules.finalizada
                    ? 'documento consolidado'
                    : 'parcial da etapa $etapa',
                info, text, muted),
          if (rules.canSignatures)
            _item(ProposalRowAction.assinaturas, Icons.draw_outlined,
                'Assinaturas', 'enviar e acompanhar a etapa $etapa',
                ok, text, muted),
          if (rules.canEdit)
            _item(ProposalRowAction.editar, Icons.edit_outlined, 'Editar',
                'dados da proposta', muted, text, muted),
          _item(ProposalRowAction.historico, Icons.history_rounded,
              'Histórico', 'etapas e assinaturas', muted, text, muted),
          _item(ProposalRowAction.usuariosVinculados, Icons.group_outlined,
              'Usuários vinculados', 'quem pode ver esta proposta',
              muted, text, muted),
          if (motivo != null)
            _item(ProposalRowAction.motivo, Icons.comment_outlined,
                'Ver motivo', motivo.title.toLowerCase(), muted, text, muted),
        ];
        final fim = <PopupMenuEntry<ProposalRowAction>>[
          if (rules.canCancel)
            _item(ProposalRowAction.cancelar, Icons.close_rounded,
                'Cancelar proposta', 'com motivo registrado',
                danger, danger, muted),
          if (rules.canDelete)
            _item(ProposalRowAction.excluir, Icons.delete_outline_rounded,
                'Excluir', 'sai da listagem · motivo obrigatório',
                danger, danger, muted),
        ];
        return [
          ...topo,
          if (fim.isNotEmpty) const PopupMenuDivider(height: 8),
          ...fim,
        ];
      },
      onSelected: onAction,
    );
  }

  PopupMenuItem<ProposalRowAction> _item(
    ProposalRowAction v,
    IconData icon,
    String title,
    String hint,
    Color iconColor,
    Color textColor,
    Color muted,
  ) {
    return PopupMenuItem<ProposalRowAction>(
      value: v,
      height: 52,
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ações que não navegam (PDF, vinculados, motivo, cancelar, excluir).
/// Devolve `true` quando a lista deve recarregar. Navegação (editar,
/// assinaturas, histórico) fica com a página, que já tem os caminhos.
Future<bool> runProposalRowAction(
  BuildContext context,
  PurchaseProposal p,
  ProposalRowAction a,
) async {
  final rules = ProposalRowRules(p);
  switch (a) {
    case ProposalRowAction.pdf:
      await _openPdf(context, p, rules.etapaDoPdf);
      return false;
    case ProposalRowAction.usuariosVinculados:
      await showFichaPeopleSheet(
        context,
        title: 'Usuários vinculados',
        subtitle: 'Proposta nº ${p.proposalNumber} — quem pode ver esta proposta.',
        emptyText: 'Nenhum usuário vinculado além de quem criou a proposta.',
        load: () async {
          final res = await PurchaseProposalsService.instance.getById(p.id);
          if (!res.success || res.data == null) {
            throw res.message ?? 'Não foi possível carregar os usuários.';
          }
          return linkedUsersFromRaw(res.data!.raw['linkedUsers']);
        },
      );
      return false;
    case ProposalRowAction.motivo:
      final m = rules.auditMotivo;
      if (m != null) await showFichaTextSheet(context, m.title, m.body);
      return false;
    case ProposalRowAction.cancelar:
      final reason = await askSaleFormReason(
        context,
        title: 'Cancelar proposta',
        message:
            'A proposta nº ${p.proposalNumber} não poderá mais ser enviada para assinatura.',
        confirmLabel: 'Cancelar proposta',
      );
      if (reason == null || !context.mounted) return false;
      final res = await PurchaseProposalsService.instance.cancelar(p.id, reason);
      if (!context.mounted) return false;
      _snack(context,
          res.success ? 'Proposta cancelada.' : (res.message ?? 'Falha ao cancelar.'),
          ok: res.success);
      return res.success;
    case ProposalRowAction.excluir:
      final reason = await askSaleFormReason(
        context,
        title: 'Excluir proposta',
        message:
            'A proposta nº ${p.proposalNumber} sai da listagem. Esta ação fica em auditoria.',
        confirmLabel: 'Excluir',
      );
      if (reason == null || !context.mounted) return false;
      final res = await PurchaseProposalsService.instance.excluir(p.id, reason);
      if (!context.mounted) return false;
      _snack(context,
          res.success ? 'Proposta excluída.' : (res.message ?? 'Falha ao excluir.'),
          ok: res.success);
      return res.success;
    case ProposalRowAction.assinaturas:
    case ProposalRowAction.editar:
    case ProposalRowAction.historico:
      return false;
  }
}

Future<void> _openPdf(BuildContext context, PurchaseProposal p, int? etapa) async {
  final res = await PurchaseProposalsService.instance.downloadPdf(
    p.id,
    etapa: etapa,
  );
  if (!context.mounted) return;
  if (!res.success || res.data == null) {
    _snack(context, res.message ?? 'Erro ao carregar o PDF.');
    return;
  }
  try {
    final num = p.proposalNumber.trim().isNotEmpty ? p.proposalNumber : p.id;
    final file = File(
      '${Directory.systemTemp.path}/Proposta_$num${etapa != null ? '_Etapa$etapa' : ''}.pdf',
    );
    await file.writeAsBytes(res.data!.bytes);
    final ok = await launchUrl(
      Uri.file(file.path),
      mode: LaunchMode.externalApplication,
    );
    // Salvou mas não abriu: é informação, não erro (snack neutro).
    if (!ok && context.mounted) {
      _snack(context, 'PDF salvo em ${file.path}', ok: null);
    }
  } catch (_) {
    if (context.mounted) {
      _snack(
        context,
        'Não foi possível abrir o PDF. Confira se há um leitor de PDF no '
        'aparelho.',
      );
    }
  }
}

/// Snack de retorno: verde quando deu certo, vermelho quando falhou e
/// neutro (cor padrão do tema) quando só informa — `ok: null`.
void _snack(BuildContext context, String msg, {bool? ok = false}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final Color? background = ok == null
      ? null
      : ok
          ? (dark ? AppColors.status.successDarkMode : AppColors.status.success)
          : (dark ? AppColors.status.errorDarkMode : AppColors.status.error);
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: background,
      behavior: SnackBarBehavior.floating,
    ),
  );
}
