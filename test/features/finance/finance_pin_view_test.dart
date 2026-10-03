import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Intellisys/features/finance/pin/services/finance_pin_service.dart';
import 'package:Intellisys/features/finance/pin/widgets/finance_pin_view.dart';
import 'package:Intellisys/shared/services/api_service.dart';

import 'finance_pin_controller_test.dart' show FakePinApi;

void main() {
  testWidgets('PIN: teclado próprio cria o PIN em duas etapas', (tester) async {
    final api = FakePinApi()
      ..statusRes = ApiResponse.success(
        data: const FinancePinStatus(configurado: false),
        statusCode: 200,
      );
    var exited = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FinancePinView(api: api, onExit: () => exited = true),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Crie seu PIN do Financeiro'), findsOneWidget);

    for (final d in ['2', '5', '8', '0']) {
      await tester.tap(find.text(d));
      await tester.pump();
    }
    expect(find.text('Confirme o PIN'), findsOneWidget);
    for (final d in ['2', '5', '8', '0']) {
      await tester.tap(find.text(d));
      await tester.pump();
    }
    expect(api.calls, contains('setup:2580'));

    await tester.tap(find.text('Sair do Financeiro'));
    expect(exited, isTrue);

    // Desmonta (cancela o cronômetro do bloqueio).
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('PIN: digitar mostra "Esqueci meu PIN"', (tester) async {
    final api = FakePinApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FinancePinView(api: api)),
      ),
    );
    await tester.pump();
    expect(find.text('Digite seu PIN'), findsOneWidget);
    expect(find.text('Esqueci meu PIN'), findsOneWidget);
    await tester.tap(find.text('Esqueci meu PIN'));
    await tester.pump();
    expect(find.text('Código do e-mail'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
