import '../core/finance_format.dart';

/// Venda que o corretor pode vincular ao adiantamento
/// (`DrawerAdiantamentoForm.tsx:380-404`).
class VendaOpcao {
  final String saleId;
  final String detalhe;

  /// Soma do `commissionValue` dos repasses PENDING + APPROVED da venda.
  final double aReceber;
  const VendaOpcao(this.saleId, this.detalhe, this.aReceber);
}

/// Agrupa `GET /repasses?brokerId` por venda; só PENDING/APPROVED somam no
/// "a receber". Ordena pelo a receber, maior primeiro.
List<VendaOpcao> vendasParaAdiantamento(List<Map<String, dynamic>> repasses) {
  final por = <String, ({String detalhe, double soma})>{};
  for (final r in repasses) {
    final saleId = r['saleId']?.toString() ?? '';
    if (saleId.isEmpty) continue;
    final sale = r['sale'] is Map
        ? (r['sale'] as Map).map((k, v) => MapEntry(k.toString(), v))
        : const <String, dynamic>{};
    final status = r['status']?.toString() ?? '';
    final soma = (status == 'PENDING' || status == 'APPROVED')
        ? financeNum(r['commissionValue'])
        : 0.0;
    final atual = por[saleId];
    if (atual == null) {
      final partes = <String>[
        if ((sale['fichaVenda']?.toString() ?? '').isNotEmpty)
          'Ficha ${sale['fichaVenda']}',
        if ((sale['propertyAddress']?.toString() ?? '').isNotEmpty)
          sale['propertyAddress'].toString(),
        if ((sale['unit']?.toString() ?? '').isNotEmpty) sale['unit'].toString(),
      ];
      por[saleId] = (
        detalhe: partes.isEmpty ? saleId : partes.join(' · '),
        soma: soma,
      );
    } else {
      por[saleId] = (detalhe: atual.detalhe, soma: atual.soma + soma);
    }
  }
  final out = por.entries
      .map(
        (e) => VendaOpcao(
          e.key,
          e.value.detalhe,
          double.parse(e.value.soma.toStringAsFixed(2)),
        ),
      )
      .toList()
    ..sort((a, b) => b.aReceber.compareTo(a.aReceber));
  return out;
}

/// Validações do formulário (mensagens do web).
Map<String, String> validarAdiantamento({
  String? companyId,
  required String description,
  double? value,
}) {
  final e = <String, String>{};
  if ((companyId ?? '').isEmpty) e['companyId'] = 'Informe a empresa';
  if (description.trim().isEmpty) e['description'] = 'Descreva o adiantamento';
  if (value == null) {
    e['value'] = 'Informe o valor';
  } else if (value < 0.01) {
    e['value'] = 'O valor mínimo é R\$ 0,01';
  }
  return e;
}

/// Corpo do POST /commission-advances do corretor. NUNCA manda
/// `feePercent` nem `capOverrideReason` (sem `:approve`/`override-cap` o
/// back responde 400).
Map<String, dynamic> buildAdiantamentoBody({
  required String companyId,
  required String brokerId,
  required List<String> saleIds,
  required String description,
  required double value,
  String? notes,
}) {
  final n = (notes ?? '').trim();
  return {
    'companyId': companyId,
    'brokerId': brokerId,
    if (saleIds.isNotEmpty) 'saleId': saleIds.first,
    if (saleIds.length > 1) 'saleIds': saleIds,
    'description': description.trim(),
    'value': double.parse(value.toStringAsFixed(2)),
    if (n.isNotEmpty) 'notes': n,
  };
}

/// O back antigo recusou `saleIds`? Reenviar só com `saleId`
/// (`enviarAdiantamento.ts:41-49`).
bool deveReenviarSemSaleIds(Map<String, dynamic> body, String? errorMessage) =>
    body.containsKey('saleIds') &&
    RegExp('saleIds', caseSensitive: false).hasMatch(errorMessage ?? '');
