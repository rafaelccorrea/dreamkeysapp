import 'package:flutter/widgets.dart';

import 'adiantamento/pedir_adiantamento_page.dart';
import 'aprovacoes/para_aprovar_page.dart';
import 'core/finance_deep_link.dart';
import 'core/finance_route_names.dart';
import 'core/widgets/finance_web_only_page.dart';
import 'meu_financeiro/pages/meu_financeiro_page.dart';
import 'pin/widgets/finance_pin_gate.dart';
import 'solicitacoes/pages/solicitacao_detalhe_page.dart';
import 'solicitacoes/pages/solicitacao_form_page.dart';
import 'solicitacoes/pages/solicitacoes_page.dart';

/// Rotas do Financeiro no app — mesmos paths do web (`/financeiro/*`), para
/// os deep links casarem 1:1. Toda tela passa pelo [FinancePinGate].
class FinanceRoutes {
  FinanceRoutes._();

  static const String index = FinanceRouteNames.index;
  static const String meuDashboard = FinanceRouteNames.meuDashboard;

  /// A rota é do Financeiro?
  static bool owns(String? route) =>
      route != null && (route == index || route.startsWith('$index/'));

  /// Tela da rota (já com o portão). [route] pode trazer query
  /// (`/financeiro/meu-dashboard?venda=…`). O que só existe no web abre um
  /// aviso claro.
  static Widget pageFor(String route) {
    final m = matchFinanceRoute(route);
    final Widget page = switch (m.kind) {
      FinanceRouteKind.meuDashboard => MeuFinanceiroPage(
        initialSaleId: m.saleId,
      ),
      FinanceRouteKind.solicitacoes => const SolicitacoesPage(),
      FinanceRouteKind.novaSolicitacao => const SolicitacaoFormPage(),
      FinanceRouteKind.solicitacao => SolicitacaoDetalhePage(
        requestId: m.id!,
      ),
      FinanceRouteKind.editarSolicitacao => SolicitacaoFormPage(editId: m.id),
      FinanceRouteKind.aprovacoes => const ParaAprovarPage(),
      FinanceRouteKind.pedirAdiantamento => const PedirAdiantamentoPage(),
      FinanceRouteKind.webOnly => FinanceWebOnlyPage(label: m.webLabel),
    };
    return FinancePinGate(child: page);
  }
}
