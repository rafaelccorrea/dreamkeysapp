import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:Intellisys/features/finance/meu_financeiro/models/meu_financeiro_models.dart';
import 'package:Intellisys/features/finance/meu_financeiro/widgets/meu_financeiro_widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  testWidgets('cartões do Meu Financeiro cabem num celular de 360 px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const totals = EarningsTotals(
      recebido: 12345.67,
      retido: 2000,
      aReceber: 98765.43,
      travado: 1500,
      bonificacao: 300,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FinanceHeroCard(
                label: 'A receber',
                value: totals.aReceber,
                hidden: false,
                liquido: 'líquido de adiantamento R\$ 90.000,00',
                tag: '+ R\$ 1.500,00 travado · sem assinatura',
                onTap: () {},
              ),
              SizedBox(
                height: 150,
                child: Row(
                  children: [
                    Expanded(
                      child: FinanceKpiTile(
                        label: 'Adiantamentos aprovados',
                        value: 'R\$ 1.234.567,89',
                        hint: '3 adiantamentos · a descontar',
                        icon: LucideIcons.handCoins,
                        tone: FinanceTones.violet,
                        onTap: () {},
                      ),
                    ),
                  ],
                ),
              ),
              const FinanceCompositionBar(totals: totals, hidden: true),
              const FinanceMonthlyChart(
                mensal: [
                  MonthlyEarning(month: '2026-08', recebido: 100, retido: 20),
                  MonthlyEarning(month: '2026-09', recebido: 300, previsto: 50),
                  MonthlyEarning(month: '2026-10', previsto: 400),
                ],
                hidden: false,
              ),
              const FinanceRow(
                title: 'Residencial Jardim das Flores · Apto 1203 Torre B',
                subtitle: 'Ficha 2026/0042 · Cliente com nome comprido',
                meta: 'Previsto 05/10/26',
                value: 'R\$ 12.345,67',
                pill: FinancePill(
                  label: 'Aguard. assinatura',
                  color: Colors.amber,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('A RECEBER'), findsOneWidget);
  });
}
