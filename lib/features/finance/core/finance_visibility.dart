import 'finance_config.dart';
import 'finance_me.dart';

/// Telas do Financeiro que o app tem (subconjunto de `financeVisibility.ts`).
enum FinanceTela { meuDashboard, solicitacoes, adiantamentos, aprovacoes }

/// Chave de permissão de cada tela (`PERMISSAO_DA_TELA`, `financeVisibility.ts:295`).
const Map<FinanceTela, String> kFinancePermissaoDaTela = {
  FinanceTela.meuDashboard: 'repasses:view-own',
  FinanceTela.solicitacoes: 'requests:view',
  FinanceTela.adiantamentos: 'commission-advances:view',
  FinanceTela.aprovacoes: 'approvals:view',
};

const Set<String> _todosMenosPendente = {
  'ADMIN',
  'DIRETOR_FINANCEIRO',
  'GERENTE_FINANCEIRO',
  'ANALISTA_FINANCEIRO',
  'FINANCEIRO',
  'RH',
  'GESTOR_MARKETING',
  'DIRETOR',
  'GESTOR',
  'CORRETOR',
};

/// Matriz papel × tela (`financeVisibility.ts:163-204`), só as telas do app.
const Map<FinanceTela, Set<String>> kFinanceMatriz = {
  FinanceTela.meuDashboard: _todosMenosPendente,
  FinanceTela.solicitacoes: _todosMenosPendente,
  FinanceTela.adiantamentos: {..._todosMenosPendente, 'PENDENTE'},
  // Aprovações: gestão comercial (GESTOR/DIRETOR) + gestão financeira.
  // ANALISTA_FINANCEIRO não aprova.
  FinanceTela.aprovacoes: {
    'ADMIN',
    'DIRETOR_FINANCEIRO',
    'GERENTE_FINANCEIRO',
    'DIRETOR',
    'GESTOR',
  },
};

/// A tela está liberada para esta identidade? (`isFinanceTelaPermitida`,
/// `financeVisibility.ts:477-499`).
///
/// - `me == null` (back antigo, 404) ou `linked:false` → sem gating (o back
///   continua barrando com 403);
/// - revogada para a pessoa → não; concedida → sim;
/// - senão, a matriz do papel.
///
/// Simplificação consciente: a exceção por CARGO do web compara
/// `permissoesDoCargo` com o preset do papel; aqui só a concessão do cargo
/// (chave presente em `permissoesDoCargo`) é considerada.
bool isFinanceTelaPermitida(FinanceMe? me, FinanceTela tela) {
  if (me == null || !me.linked) return true;
  final key = kFinancePermissaoDaTela[tela];
  if (key != null) {
    if (me.revogadas.contains(key)) return false;
    if (me.concedidas.contains(key)) return true;
    if (me.permissoesDoCargo.contains(key)) return true;
  }
  final role = me.role.trim().toUpperCase();
  if (role.isEmpty) return false;
  return kFinanceMatriz[tela]?.contains(role) ?? false;
}

/// Gate de MÓDULO: a empresa precisa ter `financial_management`, **sem
/// bypass** de papel — nem admin/master (`financeiro.routes.tsx:249-260`).
/// Lista nula = empresa ainda não carregou → `null` (indefinido).
bool? companyHasFinanceModule(Iterable<String>? modules) {
  if (modules == null) return null;
  return modules
      .map((m) => m.trim().toLowerCase())
      .contains(FinanceConfig.moduleCode);
}
