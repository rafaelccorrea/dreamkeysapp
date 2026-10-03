/// "Nova ficha a partir da proposta" — o `/fichas-venda/nova?propostaId=X`
/// do web (aviso "proposta finalizada"; `CreateSaleFormPage.tsx`, leitura do
/// `?propostaId=` e escolha do rascunho na entrada). Chamado pelo deep link.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_permissions.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/services/module_access_service.dart';
import 'ficha_draft_store.dart';
import 'pages/create_sale_form_page.dart';
import 'widgets/sale_form_signatures_sheet.dart';
import 'widgets/sale_form_type_modal.dart';

/// O rascunho guardado é da mesma proposta? (web: só continua o rascunho da
/// MESMA proposta; outro rascunho não é restaurado.)
bool saleFormRascunhoDaProposta(Map<String, dynamic>? rascunho, String id) {
  final pid = id.trim();
  if (rascunho == null || pid.isEmpty) return false;
  return (rascunho['propostaId'] ?? '').toString().trim() == pid;
}

/// Permissões ainda carregando (deep link na abertura do app): espera um
/// pouco antes de decidir, para não negar quem tem a permissão.
Future<void> _aguardarPermissoes() async {
  final m = ModuleAccessService.instance;
  if (!m.isLoading && m.userPermissions != null) return;
  final pronto = Completer<void>();
  void ouvir() {
    if (!m.isLoading && m.userPermissions != null && !pronto.isCompleted) {
      pronto.complete();
    }
  }

  m.addListener(ouvir);
  try {
    await pronto.future.timeout(const Duration(seconds: 10), onTimeout: () {});
  } finally {
    m.removeListener(ouvir);
  }
}

void _aviso(BuildContext context, String msg, {bool ok = false}) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: ok ? AppColors.status.success : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
}

/// Abre a criação da ficha de venda já preenchida com a proposta [proposalId]
/// (mesmo fluxo do web):
/// 1. exige `sale_form:create` (web: rota protegida);
/// 2. rascunho da MESMA proposta → retoma o rascunho (a proposta já está
///    aplicada nele); senão começa do zero;
/// 3. sem rascunho: modal de tipo/equipe (cancelar = não abre);
/// 4. o formulário carrega a proposta, preenche e, ao criar, vincula a ficha
///    à proposta;
/// 5. criada → abre as assinaturas da ficha nova, como a criação pela lista.
Future<void> abrirNovaFichaDaProposta(
  BuildContext context,
  String proposalId,
) async {
  final pid = proposalId.trim();
  if (pid.isEmpty) return;
  await _aguardarPermissoes();
  if (!context.mounted) return;
  if (!ModuleAccessService.instance
      .hasPermission(AppPermissions.saleFormCreate)) {
    _aviso(
      context,
      'Criar fichas de venda depende de permissão. Peça ao administrador '
      'da empresa.',
    );
    return;
  }

  final draft = await FichaDraftStore.instance.ler('venda');
  if (!context.mounted) return;
  final rascunho =
      saleFormRascunhoDaProposta(draft?.data, pid) ? draft!.data : null;

  SaleFormTypeChoice? choice;
  if (rascunho == null) {
    choice = await showSaleFormTypeModal(context);
    if (choice == null || !context.mounted) return;
  }

  final created = await Navigator.of(context).push<Object?>(
    MaterialPageRoute(
      builder: (_) => CreateSaleFormPage(
        choice: choice,
        rascunho: rascunho,
        prefillProposalId: pid,
      ),
    ),
  );
  if (!context.mounted || created is! SaleFormCreatedResult) return;
  _aviso(context, 'Ficha de venda criada com sucesso.', ok: true);
  // Web: `navigate('/fichas-venda', { state: { openSignaturesFormId } })`.
  await showSaleFormSignaturesSheet(
    context,
    saleFormId: created.id,
    formNumber: created.formNumber,
  );
}
