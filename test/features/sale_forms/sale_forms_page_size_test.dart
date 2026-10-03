import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:Intellisys/features/sale_forms/sale_forms_filters_storage.dart';
import 'package:Intellisys/shared/services/sale_forms_service.dart';

/// V-L9: "itens por página" 10/20/30/50 (web), salvo por empresa junto dos
/// filtros e usado como `limit` nas chamadas.
void main() {
  final agora = DateTime.utc(2026, 10, 3, 12);

  group('sanitizeSaleFormsPageSize', () {
    test('aceita só 10/20/30/50 (padrão 20, igual ao web)', () {
      expect(kSaleFormsPageSizes, [10, 20, 30, 50]);
      expect(kSaleFormsPageSizePadrao, 20);
      for (final n in kSaleFormsPageSizes) {
        expect(sanitizeSaleFormsPageSize(n), n);
      }
      expect(sanitizeSaleFormsPageSize(100), 20);
      expect(sanitizeSaleFormsPageSize(0), 20);
      expect(sanitizeSaleFormsPageSize('30'), 20);
      expect(sanitizeSaleFormsPageSize(null), 20);
      expect(sanitizeSaleFormsPageSize(7, fallback: 50), 50);
      expect(sanitizeSaleFormsPageSize(7, fallback: 99), 20);
    });
  });

  group('persistência do limit', () {
    test('ida e volta mantém o tamanho escolhido', () {
      for (final n in kSaleFormsPageSizes) {
        final raw = encodeSaleFormsFilters(
          SaleFormFilters(limit: n),
          showDeletedOnly: false,
          savedAt: agora,
        );
        expect(jsonDecode(raw)['limit'], n);
        final out = decodeSaleFormsFilters(raw, now: agora)!;
        expect(out.filters.limit, n);
        expect(out.filters.toQuery()['limit'], '$n');
      }
    });

    test('limit ausente ou inválido cai no padrão recebido', () {
      final semLimit = jsonEncode({
        'v': kSaleFormsFiltersVersao,
        'savedAt': agora.toIso8601String(),
      });
      expect(decodeSaleFormsFilters(semLimit, now: agora)!.filters.limit, 20);
      expect(
        decodeSaleFormsFilters(semLimit, now: agora, limit: 30)!.filters.limit,
        30,
      );
      final invalido = jsonEncode({
        'v': kSaleFormsFiltersVersao,
        'savedAt': agora.toIso8601String(),
        'limit': 500,
      });
      expect(decodeSaleFormsFilters(invalido, now: agora)!.filters.limit, 20);
    });

    test('gravar um limit fora das opções grava o padrão', () {
      final raw = encodeSaleFormsFilters(
        const SaleFormFilters(limit: 77),
        showDeletedOnly: false,
        savedAt: agora,
      );
      expect(jsonDecode(raw)['limit'], 20);
    });
  });
}
