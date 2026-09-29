import 'package:flutter/foundation.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';

/// Pessoa simples (id + nome + e-mail) para os seletores da ficha.
class SaleFormPessoa {
  const SaleFormPessoa({required this.id, required this.name, this.email = ''});
  final String id;
  final String name;
  final String email;
}

/// Consultas auxiliares do formulário da ficha de venda — as mesmas do web:
/// gestores do select "Nome do Gerente" (`getMembersByRole('manager')`) e as
/// unidades compartilhadas de uma ficha (`getSharedUnitIds`).
class SaleFormLookupService {
  SaleFormLookupService._();
  static final SaleFormLookupService instance = SaleFormLookupService._();

  final ApiService _api = ApiService.instance;

  /// `GET /users/company-members?role=manager` (percorre as páginas; o back
  /// limita a 100 por pedido).
  Future<List<SaleFormPessoa>> gestores() async {
    final out = <SaleFormPessoa>[];
    try {
      var page = 1;
      var totalPages = 1;
      while (page <= totalPages && page <= 10) {
        final res = await _api.get<Map<String, dynamic>>(
          '/users/company-members',
          queryParameters: {'role': 'manager', 'page': '$page', 'limit': '100'},
        );
        if (!res.success || res.data == null) break;
        final raw = res.data!['data'];
        if (raw is List) {
          for (final m in raw.whereType<Map>()) {
            final id = (m['id'] ?? '').toString();
            final name = (m['name'] ?? '').toString().trim();
            if (id.isEmpty || name.isEmpty) continue;
            out.add(SaleFormPessoa(
              id: id,
              name: name,
              email: (m['email'] ?? '').toString(),
            ));
          }
        }
        final tp = res.data!['totalPages'];
        totalPages = tp is num ? tp.toInt() : 1;
        page++;
      }
    } catch (e) {
      debugPrint('[SALE_FORM_LOOKUP] gestores: $e');
    }
    return out;
  }

  /// `GET /sistema/fichas-venda/:id/unidades-compartilhadas` → `{unitIds}`.
  /// `null` quando falha (quem chama NÃO deve enviar `sharedUnitIds`, para não
  /// apagar o compartilhamento gravado).
  Future<List<String>?> unidadesCompartilhadas(String saleFormId) async {
    try {
      final res = await _api.get<dynamic>(
        '${ApiConstants.saleFormById(saleFormId)}/unidades-compartilhadas',
      );
      if (!res.success) return null;
      final data = res.data;
      final ids = data is Map ? data['unitIds'] : null;
      if (ids is! List) return const [];
      return ids.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    } catch (e) {
      debugPrint('[SALE_FORM_LOOKUP] unidadesCompartilhadas: $e');
      return null;
    }
  }
}
