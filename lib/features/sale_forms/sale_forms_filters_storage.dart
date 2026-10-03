/// Filtros da lista de fichas de venda guardados no aparelho — espelha
/// `utils/saleFormsFiltersStorage.ts` do web: busca, status, criadores,
/// equipes, unidade, datas, ordenação e "Apenas excluídas" sobrevivem a
/// sair da tela e voltar (por empresa; vencem em 30 dias).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/services/module_access_service.dart';
import '../../shared/services/sale_forms_service.dart';

const int kSaleFormsFiltersVersao = 1;
const Duration kSaleFormsFiltersMaxIdade = Duration(days: 30);

const Set<String> _kSortByValidos = {
  'createdAt',
  'formNumber',
  'buyerName',
  'sellerName',
  'saleUnit',
  'status',
  'saleFormType',
  'creatorName',
};

/// "Itens por página" (web `[10, 20, 30, 50]`, padrão 20). O back aceita
/// até 100 (`ListSaleFormsQueryDto.limit` `@Max(100)`).
const List<int> kSaleFormsPageSizes = [10, 20, 30, 50];
const int kSaleFormsPageSizePadrao = 20;

/// Tamanho de página válido: fora das opções do web cai em [fallback]
/// (ou no padrão 20, se o próprio fallback também for inválido).
int sanitizeSaleFormsPageSize(Object? v, {int fallback = kSaleFormsPageSizePadrao}) {
  if (v is int && kSaleFormsPageSizes.contains(v)) return v;
  return kSaleFormsPageSizes.contains(fallback)
      ? fallback
      : kSaleFormsPageSizePadrao;
}

final RegExp _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// Estado da lista que vale guardar.
class SaleFormsListaSalva {
  const SaleFormsListaSalva({
    required this.filters,
    required this.showDeletedOnly,
  });
  final SaleFormFilters filters;
  final bool showDeletedOnly;
}

/// Chave por empresa (`storageKey` do web).
String saleFormsFiltersKey(String? companyId) {
  final c = (companyId ?? '').trim();
  return c.isEmpty
      ? 'imobx_sale_forms_filters'
      : 'imobx_sale_forms_filters:$c';
}

String? _ymd(DateTime? d) => d == null
    ? null
    : '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

DateTime? _data(Object? v) {
  if (v is! String || v.trim().isEmpty) return null;
  final d = DateTime.tryParse(v.trim());
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

List<String> _uuids(Object? v) => v is List
    ? v
        .whereType<String>()
        .map((e) => e.trim())
        .where(_uuid.hasMatch)
        .toList()
    : const [];

/// JSON gravado. A página não é guardada (o app rola infinito e sempre
/// recomeça da 1ª); o "itens por página" (`limit`) é, como no web.
String encodeSaleFormsFilters(
  SaleFormFilters f, {
  required bool showDeletedOnly,
  required DateTime savedAt,
}) {
  final search = f.search?.trim();
  return jsonEncode({
    'v': kSaleFormsFiltersVersao,
    'savedAt': savedAt.toUtc().toIso8601String(),
    if (search != null && search.isNotEmpty) 'search': search,
    'statuses': [for (final s in f.effectiveStatuses) s.apiValue],
    'userIds': f.userIds,
    'teamIds': f.teamIds,
    if (f.saleUnit?.trim().isNotEmpty ?? false) 'saleUnit': f.saleUnit!.trim(),
    'dateFrom': _ymd(f.dateFrom),
    'dateTo': _ymd(f.dateTo),
    'saleDateFrom': _ymd(f.saleDateFrom),
    'saleDateTo': _ymd(f.saleDateTo),
    'sortBy': f.sortBy,
    'sortOrder': f.sortOrder,
    'showDeletedOnly': showDeletedOnly,
    'limit': sanitizeSaleFormsPageSize(f.limit),
  });
}

/// `null` quando vazio, ilegível, de outra versão ou com mais de 30 dias.
/// Valores fora do esperado são descartados um a um (`sanitize*` do web).
SaleFormsListaSalva? decodeSaleFormsFilters(
  String? raw, {
  required DateTime now,
  int limit = 20,
}) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final m = jsonDecode(raw);
    if (m is! Map || m['v'] != kSaleFormsFiltersVersao) return null;
    final at = DateTime.tryParse((m['savedAt'] ?? '').toString());
    if (at == null || now.difference(at) > kSaleFormsFiltersMaxIdade) {
      return null;
    }
    final statuses = <SaleFormStatus>[];
    final rawSts = m['statuses'];
    if (rawSts is List) {
      for (final s in SaleFormStatus.values) {
        if (rawSts.contains(s.apiValue)) statuses.add(s);
      }
    }
    final sortBy = m['sortBy'] is String && _kSortByValidos.contains(m['sortBy'])
        ? m['sortBy'] as String
        : 'createdAt';
    final search = m['search'] is String ? (m['search'] as String).trim() : '';
    final saleUnit =
        m['saleUnit'] is String ? (m['saleUnit'] as String).trim() : '';
    return SaleFormsListaSalva(
      filters: SaleFormFilters(
        search: search.isEmpty ? null : search,
        statuses: statuses,
        userIds: _uuids(m['userIds']),
        teamIds: _uuids(m['teamIds']),
        saleUnit: saleUnit.isEmpty ? null : saleUnit,
        dateFrom: _data(m['dateFrom']),
        dateTo: _data(m['dateTo']),
        saleDateFrom: _data(m['saleDateFrom']),
        saleDateTo: _data(m['saleDateTo']),
        limit: sanitizeSaleFormsPageSize(m['limit'], fallback: limit),
        sortBy: sortBy,
        sortOrder: m['sortOrder'] == 'ASC' ? 'ASC' : 'DESC',
      ),
      showDeletedOnly: m['showDeletedOnly'] == true,
    );
  } catch (_) {
    return null;
  }
}

/// Leitura e gravação no aparelho (`shared_preferences`).
class SaleFormsFiltersStore {
  SaleFormsFiltersStore._();
  static final SaleFormsFiltersStore instance = SaleFormsFiltersStore._();

  String get _key =>
      saleFormsFiltersKey(ModuleAccessService.instance.selectedCompany?.id);

  Future<SaleFormsListaSalva?> ler({int limit = 20}) async {
    try {
      final p = await SharedPreferences.getInstance();
      final out = decodeSaleFormsFilters(
        p.getString(_key),
        now: DateTime.now(),
        limit: limit,
      );
      if (out == null && p.containsKey(_key)) await p.remove(_key);
      return out;
    } catch (e) {
      debugPrint('[FICHAS_FILTROS] ler: $e');
      return null;
    }
  }

  Future<void> salvar(SaleFormFilters f, {required bool showDeletedOnly}) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _key,
        encodeSaleFormsFilters(
          f,
          showDeletedOnly: showDeletedOnly,
          savedAt: DateTime.now(),
        ),
      );
    } catch (e) {
      debugPrint('[FICHAS_FILTROS] salvar: $e');
    }
  }
}
