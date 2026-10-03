import 'finance_me.dart';
import 'finance_visibility.dart';

/// Regras de "quem pode" do Financeiro no app (funções puras, testadas).
///
/// Fontes: WEB `utils/financePermissoes.ts:10`, `routes/domains/
/// financeiro.routes.tsx:129-137,546-569`, `components/layout/Drawer.tsx:
/// 1593-1600,2146-2151`; FIN `packages/shared/src/types/auth.ts:136-187`.

/// Papéis que entram na Central de Aprovações (`APPROVAL_CENTER_ROLES`).
const Set<String> kApprovalCenterRoles = {
  'ADMIN',
  'DIRETOR_FINANCEIRO',
  'GERENTE_FINANCEIRO',
  'DIRETOR',
  'GESTOR',
};

/// Quem aprova/reprova adiantamento por padrão (`ADVANCE_APPROVER_ROLES`).
const Set<String> kAdvanceApproverRoles = {
  'ADMIN',
  'DIRETOR_FINANCEIRO',
  'GERENTE_FINANCEIRO',
};

/// Papéis do "time financeiro" que o `assertFinanceAccess` do upload
/// multipart aceita (`role-filter.util.ts:10-20`).
const Set<String> kFinanceStaffRoles = {
  'ADMIN',
  'DIRETOR_FINANCEIRO',
  'GERENTE_FINANCEIRO',
  'ANALISTA_FINANCEIRO',
  'FINANCEIRO',
};

/// `temPermissao(me, key)` do web: `null` quando o back não mandou a lista
/// (quem decide é o fallback por papel — e, no fim, o back).
bool? financeTemPermissao(FinanceMe? me, String key) {
  if (me == null || !me.hasPermissoesList) return null;
  return me.permissoes.contains(key);
}

/// Crachá do CRM para as telas de GESTÃO do Financeiro (inclui Aprovações):
/// permissão `financial:access`, ou papel master/admin do CRM.
bool financeCrachaOk({String? crmRole, required bool hasFinancialAccess}) {
  final r = (crmRole ?? '').trim().toLowerCase();
  return hasFinancialAccess || r == 'master' || r == 'admin';
}

/// "Para aprovar" aparece? Crachá do CRM **e** a matriz papel × tela
/// (`isFinanceTelaPermitida(me,'aprovacoes')`). Sem `/auth/me` carregado
/// (`me == null`) a matriz não barra — a tela confere de novo ao abrir.
bool canSeeParaAprovar({
  String? crmRole,
  required bool hasFinancialAccess,
  FinanceMe? me,
}) {
  if (!financeCrachaOk(
    crmRole: crmRole,
    hasFinancialAccess: hasFinancialAccess,
  )) {
    return false;
  }
  return isFinanceTelaPermitida(me, FinanceTela.aprovacoes);
}

/// Decide pela Central (`approvals:decide-bulk`; padrão = papéis da Central).
bool canDecideApprovals(FinanceMe? me) {
  final p = financeTemPermissao(me, 'approvals:decide-bulk');
  if (p != null) return p;
  if (me == null || !me.linked) return true; // sem gating: o back decide
  return kApprovalCenterRoles.contains(me.role);
}

/// Aprova adiantamento (com taxa) — `commission-advances:approve`.
bool canApproveAdvance(FinanceMe? me) {
  final p = financeTemPermissao(me, 'commission-advances:approve');
  if (p != null) return p;
  if (me == null || !me.linked) return false;
  return kAdvanceApproverRoles.contains(me.role);
}

/// Anexo de solicitação pelo multipart de 30 MB? Só quem tem
/// `attachments:attach` E é do time financeiro (o service ainda chama
/// `assertFinanceAccess`). Corretor e gestor comercial → base64 de 5 MB.
bool usaUploadMultipart(FinanceMe? me) {
  if (me == null || !me.linked) return false;
  final p = financeTemPermissao(me, 'attachments:attach');
  if (p == false) return false;
  return kFinanceStaffRoles.contains(me.role) && (p ?? true);
}

/// Limite de anexo de solicitação para esta pessoa (bytes).
int limiteAnexoBytes(FinanceMe? me) =>
    usaUploadMultipart(me) ? 30 * 1024 * 1024 : 5 * 1024 * 1024;
