import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';

/// Membros da empresa (id → nome) para dar nome a quem está na comissão da
/// ficha. Mesma fonte do web na edição (`companyMembersApi.getMembers` →
/// `GET /users/company-members`). O back devolve no máximo 100 por página:
/// percorre as páginas (até 10). Falha = mapa vazio (a tela usa o nome
/// gravado ou "Participante").
class SaleFormMembersService {
  SaleFormMembersService._();
  static final SaleFormMembersService instance = SaleFormMembersService._();

  final ApiService _api = ApiService.instance;

  Future<Map<String, String>> nomesPorId() async {
    final out = <String, String>{};
    try {
      var page = 1;
      var totalPages = 1;
      while (page <= totalPages && page <= 10) {
        final res = await _api.get<Map<String, dynamic>>(
          '/users/company-members',
          queryParameters: {'page': '$page', 'limit': '100'},
        );
        if (!res.success || res.data == null) break;
        final raw = res.data!['data'];
        if (raw is List) {
          for (final m in raw.whereType<Map>()) {
            final id = (m['id'] ?? '').toString().trim();
            final name = (m['name'] ?? '').toString().trim();
            if (id.isEmpty || name.isEmpty) continue;
            out[id] = name;
          }
        }
        final tp = res.data!['totalPages'];
        totalPages = tp is num ? tp.toInt() : 1;
        page++;
      }
    } catch (e) {
      debugPrint('[SALE_FORM_MEMBERS] nomesPorId: $e');
    }
    return out;
  }
}
