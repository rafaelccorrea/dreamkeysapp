/// Paths do Financeiro no app — os MESMOS do web (`/financeiro/*`), para
/// deep links e notificações casarem 1:1. Só constantes (sem importar
/// telas), para qualquer arquivo poder navegar sem import circular.
class FinanceRouteNames {
  FinanceRouteNames._();

  static const String index = '/financeiro';
  static const String meuDashboard = '/financeiro/meu-dashboard';
  static const String solicitacoes = '/financeiro/solicitacoes';
  static const String novaSolicitacao = '/financeiro/solicitacoes/nova';
  static const String aprovacoes = '/financeiro/aprovacoes';
  static const String adiantamentos = '/financeiro/adiantamentos';
  static const String pedirAdiantamento = '/financeiro/adiantamentos/novo';
  static const String vendas = '/financeiro/vendas';

  static String solicitacao(String id) =>
      '$solicitacoes/${Uri.encodeComponent(id)}';

  static String editarSolicitacao(String id) =>
      '$solicitacoes/${Uri.encodeComponent(id)}/editar';

  /// Meu Financeiro abrindo a consulta da venda.
  static String venda(String saleId) =>
      '$meuDashboard?venda=${Uri.encodeQueryComponent(saleId)}';
}
