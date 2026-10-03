import 'package:intl/intl.dart';

/// Número do Financeiro: `/repasses/*` manda `number`; `/commission-advances`
/// e `/requests` mandam o `Decimal` do Prisma como STRING ("10200.00").
double financeNum(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().trim()) ?? 0;
}

double? financeNumOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().trim());
}

final NumberFormat _brl = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: r'R$',
  decimalDigits: 2,
);

/// "R$ 1.234,56". Com [hidden], a máscara do web (`mascararValor`): mantém
/// sinal e "R$", e troca os dígitos da parte inteira por `•` (2 a 6).
String formatBrl(double value, {bool hidden = false}) {
  final text = _brl.format(value).replaceAll(' ', ' ');
  if (!hidden) return text;
  final negative = value < 0;
  final inteiro = value.abs().truncate().toString().length.clamp(2, 6);
  return '${negative ? '-' : ''}R\$ ${'•' * inteiro}';
}

/// Data "dd/MM/yy". O back manda datas de calendário à meia-noite UTC —
/// formata em UTC para não voltar um dia no fuso do Brasil.
String formatFinanceDate(String? iso, {String pattern = 'dd/MM/yy'}) {
  if (iso == null || iso.isEmpty) return '—';
  final d = DateTime.tryParse(iso);
  if (d == null) return '—';
  return DateFormat(pattern, 'pt_BR').format(d.toUtc());
}

/// Data/hora local (ISO com hora real, ex.: `createdAt`).
String formatFinanceDateTime(String? iso, {String pattern = 'dd/MM/yy'}) {
  if (iso == null || iso.isEmpty) return '—';
  final d = DateTime.tryParse(iso);
  if (d == null) return '—';
  return DateFormat(pattern, 'pt_BR').format(d.toLocal());
}

/// `YYYY-MM-DD` para as queries `from`/`to`.
String financeQueryDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
