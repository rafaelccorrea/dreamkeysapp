import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../meu_financeiro/widgets/meu_financeiro_widgets.dart';
import '../finance_route_names.dart';

/// Destino `/financeiro/*` que o app não tem (contas a pagar, pipeline…):
/// aviso claro, sem "página não encontrada".
class FinanceWebOnlyPage extends StatelessWidget {
  final String? label;
  const FinanceWebOnlyPage({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    final accent = financeAccent(context);
    return AppScaffold(
      title: 'Financeiro',
      showDrawer: false,
      showBottomNavigation: false,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(28, 48, 28, 28),
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(LucideIcons.monitor, color: accent, size: 32),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '${label ?? 'Esta tela do Financeiro'} fica no computador',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'No app estão o Meu Financeiro, as Solicitações, o pedido de '
            'adiantamento e a fila "Para aprovar". O restante do Financeiro '
            '(contas a pagar e a receber, vendas, pipeline, relatórios) é '
            'usado pelo navegador.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
          const SizedBox(height: 22),
          Center(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: accent),
              onPressed: () => Navigator.of(
                context,
              ).pushReplacementNamed(FinanceRouteNames.meuDashboard),
              icon: const Icon(LucideIcons.wallet, size: 18),
              label: const Text('Abrir o Meu Financeiro'),
            ),
          ),
        ],
      ),
    );
  }
}
