import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/services/purchase_proposals_service.dart';
import '../../../shared/widgets/file_delivery_sheet.dart';
import '../../sale_forms/widgets/sale_form_row_actions.dart'
    show askSaleFormReason, linkedUsersFromRaw, showFichaPeopleSheet,
        showFichaTextSheet;
import '../../sale_forms/widgets/sale_form_tones.dart';

/// Cor do status da proposta — a mesma família de antes (`AppColors.status`:
/// info, sucesso, erro), agora com o tom de TEXTO legível no claro. Uma
/// fonte só para a linha da lista, o painel de status e a folha de ações.
SaleFormTom proposalStatusTom(BuildContext context, ProposalStatus s) {
  switch (s) {
    case ProposalStatus.finalized:
      return SaleFormTom.sucesso(context);
    case ProposalStatus.canceled:
      return SaleFormTom.erro(context);
    case ProposalStatus.processing:
      return SaleFormTom.info(context);
  }
}

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

Future<void> _openPdf(
  BuildContext context,
  PurchaseProposal p,
  int? etapa,
) async {
  final num = p.proposalNumber.trim().isNotEmpty ? p.proposalNumber : p.id;
  var comAssinado = false;
  // Já passou de alguma etapa (ou finalizada): pode haver assinado no
  // Autentique — pergunta se quer só o PDF ou o PDF + assinado (.zip).
  if (proposalPdfPodeTerAssinado(p)) {
    final escolha = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Só o PDF da proposta'),
              subtitle: const Text('O documento gerado pelo sistema.'),
              onTap: () => Navigator.of(ctx).pop(false),
            ),
            ListTile(
              leading: const Icon(Icons.folder_zip_outlined),
              title: const Text('PDF + assinado (.zip)'),
              subtitle: const Text(
                'Junto com o(s) documento(s) assinado(s) no Autentique.',
              ),
              onTap: () => Navigator.of(ctx).pop(true),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (escolha == null || !context.mounted) return;
    comAssinado = escolha;
  }
  if (!context.mounted) return;
  await showProposalPdfSheet(
    context,
    proposalId: p.id,
    numero: num,
    etapa: etapa,
    incluirAutentique: comAssinado,
  );
}

/// A proposta pode ter documento assinado no Autentique: finalizada ou já
/// além da etapa 1 (a etapa anterior foi concluída).
bool proposalPdfPodeTerAssinado(PurchaseProposal p) =>
    p.status == ProposalStatus.finalized || p.etapa.number > 1;

/// Folha do PDF da proposta nº [numero] (da [etapa], ou consolidado quando
/// nula) — Compartilhar / Salvar no aparelho. Abrir com
/// `launchUrl(Uri.file(...))` não funciona no Android nem no iOS.
///
/// [incluirAutentique] = `true` pede ao back o PDF gerado + o(s) assinado(s)
/// do Autentique num .zip (é o que o download do web entrega —
/// `baixarPdfProposta`, sem `incluirAutentique=false`); sem assinado, o back
/// devolve só o PDF.
Future<void> showProposalPdfSheet(
  BuildContext context, {
  required String proposalId,
  required String numero,
  int? etapa,
  bool incluirAutentique = false,
}) {
  return showFileDeliverySheet(
    context,
    title: incluirAutentique
        ? 'PDF + assinado · proposta nº $numero'
            '${etapa != null ? ' (etapa $etapa)' : ''}'
        : etapa == null
            ? 'PDF da proposta nº $numero'
            : 'PDF da etapa $etapa · proposta nº $numero',
    expectedType: 'PDF',
    generatingTitle: 'Gerando o PDF da proposta…',
    readyTitle: 'PDF pronto',
    readyNote: (file) => file.extension == 'zip'
        ? 'O PDF gerado e o(s) assinado(s) no Autentique vêm juntos num .zip.'
        : incluirAutentique
            ? 'Ainda não há documento assinado no Autentique: veio só o PDF.'
            : null,
    shareSubject: 'Proposta nº $numero',
    saveDialogTitle: 'Salvar PDF da proposta',
    load: () async {
      final res = await PurchaseProposalsService.instance.downloadPdf(
        proposalId,
        etapa: etapa,
        incluirAutentique: incluirAutentique,
      );
      final data = res.data;
      if (!res.success || data == null) {
        return ApiResponse.error(
          message: res.message ?? '',
          statusCode: res.statusCode,
          data: res.error,
        );
      }
      final zip = data.contentType.contains('zip');
      return ApiResponse.success(
        data: DeliverableFile(
          bytes: data.bytes,
          fileName: 'Proposta_$numero'
              '${etapa != null ? '_Etapa$etapa' : ''}.${zip ? 'zip' : 'pdf'}',
          mimeType: zip ? 'application/zip' : 'application/pdf',
        ),
        statusCode: res.statusCode,
      );
    },
  );
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
