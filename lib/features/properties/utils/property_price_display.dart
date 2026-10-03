import 'package:intl/intl.dart' show NumberFormat;

/// Rótulo de preço que não vale para o imóvel — o back grava "0.00" no lado
/// que a finalidade não anuncia (ou que ficou vazio), e isso NÃO é "R$ 0".
const String kPriceNotApplicable = 'Não se aplica';

/// Rótulo quando nenhum dos dois preços vale (mesmo texto do web).
const String kPriceNotInformed = 'Preço não informado';

final NumberFormat _brl = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: r'R$',
  decimalDigits: 2,
);

/// Preço que vale: presente e maior que zero (regra `> 0` do web,
/// `getPropertyPricing` em `PropertiesPage.tsx`).
bool hasApplicablePrice(double? value) => value != null && value > 0;

/// "R$ 1.250.000,00" — ou [kPriceNotApplicable] quando o valor é nulo/zero.
String formatPropertyPrice(double? value, {bool perMonth = false}) {
  if (!hasApplicablePrice(value)) return kPriceNotApplicable;
  final s = _brl.format(value);
  return perMonth ? '$s/mês' : s;
}

/// "R$ 1,2M" / "R$ 850k" / "R$ 900,00" — para a linha curta do card.
String formatCompactPropertyPrice(double value) {
  if (value >= 1000000) {
    final compact = value / 1000000;
    return 'R\$ ${_trimZero(compact.toStringAsFixed(compact >= 10 ? 0 : 1))}M';
  }
  if (value >= 1000) {
    final compact = value / 1000;
    return 'R\$ ${_trimZero(compact.toStringAsFixed(compact >= 100 ? 0 : 1))}k';
  }
  return _brl.format(value);
}

String _trimZero(String s) =>
    (s.endsWith('.0') ? s.substring(0, s.length - 2) : s).replaceAll('.', ',');

/// Linha de preço do card da listagem: venda e locação aparecem juntos
/// quando os DOIS valem; com um só, só ele; sem nenhum, "Preço não
/// informado". Preço zero nunca vira "R$ 0".
({String label, String value}) propertyListPriceLine({
  double? salePrice,
  double? rentPrice,
}) {
  final sale = hasApplicablePrice(salePrice);
  final rent = hasApplicablePrice(rentPrice);
  if (sale && rent) {
    return (
      label: 'VENDA E LOCAÇÃO',
      value: '${formatCompactPropertyPrice(salePrice!)} · '
          '${formatCompactPropertyPrice(rentPrice!)}/mês',
    );
  }
  if (sale) {
    return (label: 'VALOR DE VENDA', value: _brl.format(salePrice));
  }
  if (rent) {
    return (label: 'VALOR DE ALUGUEL', value: '${_brl.format(rentPrice)}/mês');
  }
  return (label: 'VALOR', value: kPriceNotInformed);
}
