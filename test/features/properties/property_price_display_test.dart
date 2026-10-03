import 'package:Intellisys/features/properties/utils/property_price_display.dart';
import 'package:flutter_test/flutter_test.dart';

/// O NumberFormat pt_BR usa espaço inseparável depois do "R$".
String _plain(String s) => s.replaceAll(' ', ' ');

void main() {
  group('Preço "0.00" = não se aplica', () {
    test('zero e nulo não valem; positivo vale', () {
      expect(hasApplicablePrice(null), isFalse);
      expect(hasApplicablePrice(0), isFalse);
      expect(hasApplicablePrice(-1), isFalse);
      expect(hasApplicablePrice(0.01), isTrue);
    });

    test('detalhe: zero vira "Não se aplica", nunca "R\$ 0"', () {
      expect(formatPropertyPrice(0), kPriceNotApplicable);
      expect(formatPropertyPrice(null), kPriceNotApplicable);
      expect(_plain(formatPropertyPrice(450000)), 'R\$ 450.000,00');
      expect(
        _plain(formatPropertyPrice(2500, perMonth: true)),
        'R\$ 2.500,00/mês',
      );
    });
  });

  group('Linha de preço do card', () {
    test('venda + locação mostra os dois', () {
      final line =
          propertyListPriceLine(salePrice: 1200000, rentPrice: 4500);
      expect(line.label, 'VENDA E LOCAÇÃO');
      expect(_plain(line.value), 'R\$ 1,2M · R\$ 4,5k/mês');
    });

    test('venda com aluguel 0.00 mostra só a venda', () {
      final line = propertyListPriceLine(salePrice: 350000, rentPrice: 0);
      expect(line.label, 'VALOR DE VENDA');
      expect(_plain(line.value), 'R\$ 350.000,00');
    });

    test('aluguel com venda 0.00 mostra só o aluguel', () {
      final line = propertyListPriceLine(salePrice: 0, rentPrice: 1800);
      expect(line.label, 'VALOR DE ALUGUEL');
      expect(_plain(line.value), 'R\$ 1.800,00/mês');
    });

    test('os dois zerados: "Preço não informado"', () {
      final line = propertyListPriceLine(salePrice: 0, rentPrice: 0);
      expect(line.value, kPriceNotInformed);
      expect(propertyListPriceLine().value, kPriceNotInformed);
    });

    test('formato compacto', () {
      expect(formatCompactPropertyPrice(12000000), 'R\$ 12M');
      expect(formatCompactPropertyPrice(1000000), 'R\$ 1M');
      expect(formatCompactPropertyPrice(250000), 'R\$ 250k');
      expect(_plain(formatCompactPropertyPrice(900)), 'R\$ 900,00');
    });
  });
}
