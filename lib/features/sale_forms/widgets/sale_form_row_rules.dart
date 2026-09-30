import '../../../core/constants/app_permissions.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/sale_forms_service.dart';

/// Regras das ações de uma ficha de venda — espelho literal do menu da
/// listagem web (`SaleFormsPage.tsx`, `SaleFormActionsMenu`). Uma fonte só
/// para a lista, o card e o detalhe do app (29/09/2026, paridade web ↔ app).
class SaleFormRowRules {
  SaleFormRowRules(this.form)
      : _canUpdate = _has(AppPermissions.saleFormUpdate),
        _canDelete = _has(AppPermissions.saleFormDelete),
        _canExport = _has(AppPermissions.saleFormExport),
        _canViewAll = _has(AppPermissions.saleFormViewAll);

  final SaleForm form;
  final bool _canUpdate;
  final bool _canDelete;
  final bool _canExport;
  final bool _canViewAll;

  static bool _has(String p) => ModuleAccessService.instance.hasPermission(p);

  bool get _deleted => form.deletedAt != null;
  bool get _finalized => form.status == SaleFormStatus.finalized;
  bool get _canceled => form.status == SaleFormStatus.canceled;
  bool get _processing => form.status == SaleFormStatus.processing;

  /// Web: `hasActiveSignatures = assinaturasTotal > 0`.
  bool get hasActiveSignatures => form.assinaturasTotal > 0;

  bool get canUpdate => _canUpdate;

  /// Web: não esconde o Editar — bloqueia e informa o motivo.
  String? get editBlockReason {
    if (_finalized) {
      return 'Ficha finalizada: todos os signatários já assinaram, então ela não pode mais ser editada.';
    }
    if (_canceled) return 'Ficha cancelada: não pode mais ser editada.';
    if (hasActiveSignatures || _processing) {
      return 'Esta ficha já possui assinatura(s) em andamento. Para editar, invalide as assinaturas primeiro (opção "Cancelar assinaturas (reenvio)").';
    }
    return null;
  }

  /// Editar aparece para quem tem `sale_form:update` (liberado ou bloqueado),
  /// nunca em ficha excluída.
  bool get showEdit => _canUpdate && !_deleted;
  bool get canEdit => showEdit && editBlockReason == null;

  /// Enviar/revisar assinaturas: update + não finalizada/cancelada.
  bool get showSignatures =>
      _canUpdate && !_deleted && !_finalized && !_canceled;

  String get signaturesLabel => hasActiveSignatures
      ? 'Revisar assinaturas (${form.assinaturasAssinadas}/${form.assinaturasTotal})'
      : 'Enviar para assinatura';

  /// Web: `canInvalidateSignatures === true` vem do back na linha.
  bool get _backAllowsInvalidate =>
      form.raw['canInvalidateSignatures'] == true;

  bool get canCancelSignaturesForResend =>
      _canUpdate &&
      !_deleted &&
      !_canceled &&
      _backAllowsInvalidate &&
      hasActiveSignatures &&
      (_processing ||
          form.status == SaleFormStatus.waitingForSignature ||
          _finalized);

  /// PDF: `sale_form:export` + finalizada (sistema e com assinaturas).
  bool get canPdf => _canExport && _finalized && !_deleted;

  /// Distrato: update + finalizada + sem distrato aberto (mesma regra do web).
  ///
  /// Religado em 30/09/2026: o core ganhou `PATCH /sistema/fichas-venda/:id/
  /// distrato` (cancela a ficha, marca `distratoAbertoEm` e avisa o
  /// Financeiro com `distrato: true`). Até 29/09 a rota não existia e dava 404
  /// no web e no app. Só funciona depois do deploy desse back.
  bool get canDistrato =>
      _canUpdate &&
      _finalized &&
      !_deleted &&
      (form.raw['distratoAbertoEm'] == null ||
          form.raw['distratoAbertoEm'].toString().isEmpty);

  /// Transferir responsabilidade: update + (view_all | admin | master),
  /// só finalizada.
  bool canTransfer({required String? role}) {
    final r = (role ?? '').toLowerCase();
    return _canUpdate &&
        (_canViewAll || r == 'admin' || r == 'master') &&
        _finalized &&
        !_deleted;
  }

  /// "Cancelar ficha" existe só no app (o web cancela por distrato na
  /// finalizada); mantido para quem já usa, nunca em ficha finalizada.
  bool get canCancelFicha =>
      _canUpdate && !_deleted && !_canceled && !_finalized;

  /// Trocar equipe (provisório no web): update + não excluída.
  bool get canChangeTeam => _canUpdate && !_deleted;

  /// Excluir: delete + não excluída + não cancelada + `ativo !== false`.
  bool get canExclude =>
      _canDelete && !_deleted && !_canceled && form.raw['ativo'] != false;

  /// "Ver motivo": só quem vê tudo, e só quando há motivo registrado.
  ({String title, String body})? get auditMotivo {
    if (!_canViewAll) return null;
    final del = form.raw['deletionReason']?.toString().trim() ?? '';
    if (_deleted && del.isNotEmpty) {
      return (title: 'Motivo da exclusão', body: del);
    }
    final canc = form.raw['cancellationReason']?.toString().trim() ?? '';
    if (_canceled && canc.isNotEmpty) {
      final distrato = form.raw['distratoAbertoEm'] != null;
      return (
        title: distrato ? 'Motivo do distrato' : 'Motivo do cancelamento',
        body: canc,
      );
    }
    return null;
  }
}

/// Ações do menu da ficha, na ordem do menu web.
enum SaleFormRowAction {
  ver,
  usuariosVinculados,
  trocarEquipe,
  motivo,
  pdfSistema,
  pdfAssinaturas,
  transferir,
  distrato,
  assinaturas,
  cancelarAssinaturas,
  editar,
  cancelarFicha,
  excluir,
}
