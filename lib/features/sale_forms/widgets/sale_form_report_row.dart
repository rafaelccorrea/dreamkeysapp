import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/sale_forms_service.dart';
import '../pages/sale_form_audit_page.dart';
import '../sale_form_list_display.dart';
import '../sale_forms_relatorio_export.dart' show saleFormsExportPropertyLine;
import 'sale_form_tones.dart';

/// Linha do modo "Relatório fichas" (V-L4, 03/10/2026) — as colunas da
/// tabela de relatório da web (`SaleFormsPage.tsx`, `listViewMode ===
/// 'relatorio'`): Nº, data da compra, endereço, valor da venda, comissão
/// total, gestor, status e rastreabilidade com "Raio-X completo".
class SaleFormReportRow extends StatelessWidget {
  const SaleFormReportRow({super.key, required this.saleForm, this.onTap});

  final SaleForm saleForm;
  final VoidCallback? onTap;

  static final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  String _dinheiro(double? v) => v == null || v <= 0 ? '—' : _money.format(v);

  @override
  Widget build(BuildContext context) {
    final f = saleForm;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final text = ThemeHelpers.textColor(context);
    final tom = SaleFormTom.doStatus(context, f.status);
    final endereco = saleFormsExportPropertyLine(f.raw);
    final rastreio = saleFormRastreioLinha(f);

    Widget campo(String rotulo, String valor, {bool forte = false}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rotulo,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: muted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            valor,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: forte ? FontWeight.w800 : FontWeight.w600,
              color: text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  f.formNumber.isEmpty ? 'Ficha' : 'Nº ${f.formNumber}',
                  style: TextStyle(fontWeight: FontWeight.w800, color: text),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: tom.sinal,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    f.statusShortLabel,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: tom.sinal,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  saleFormSaleDateLabel(f),
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              endereco,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: muted, height: 1.3),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                campo('Valor venda', _dinheiro(f.saleValue), forte: true),
                campo('Comissão total', _dinheiro(f.totalCommission)),
                campo(
                  'Gestor',
                  f.managerName?.trim().isNotEmpty == true
                      ? f.managerName!.trim()
                      : '—',
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    rastreio,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: muted),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SaleFormAuditPage(
                        saleFormId: f.id,
                        formNumber: f.formNumber,
                      ),
                    ),
                  ),
                  child: const Text('Raio-X completo'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
