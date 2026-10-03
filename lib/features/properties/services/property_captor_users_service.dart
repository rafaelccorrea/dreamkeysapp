import 'package:flutter/foundation.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';
import '../../workspace/models/admin_user_model.dart';

/// Pessoa selecionável como captador/responsável no cadastro do imóvel.
class CaptorUserOption {
  final String id;
  final String name;
  final String? email;

  const CaptorUserOption({required this.id, required this.name, this.email});
}

/// Lista da empresa para captador(es)/responsável(eis) — mesma chamada do
/// web (`CreatePropertyPage.tsx` ~1580): `GET /admin/users?allCompanyUsers=
/// true&compact=true&limit=500`, varrendo as páginas para não truncar.
///
/// Sem permissão (403) devolve erro com `statusCode` 403; a tela cai no
/// usuário logado e mostra o aviso do web.
class PropertyCaptorUsersService {
  PropertyCaptorUsersService._();
  static final PropertyCaptorUsersService instance =
      PropertyCaptorUsersService._();
  final ApiService _api = ApiService.instance;

  static const int _pageSize = 500;

  Future<ApiResponse<List<CaptorUserOption>>> listCompanyUsers() async {
    try {
      final byId = <String, CaptorUserOption>{};
      var page = 1;
      var totalPages = 1;
      do {
        final res = await _api.get<Map<String, dynamic>>(
          ApiConstants.adminUsers,
          queryParameters: {
            'page': '$page',
            'limit': '$_pageSize',
            'allCompanyUsers': 'true',
            'compact': 'true',
          },
        );
        if (!res.success || res.data == null) {
          return ApiResponse.error(
            message: res.message ?? 'Erro ao listar usuários',
            statusCode: res.statusCode,
          );
        }
        final parsed = AdminUsersPage.fromJson(res.data!, page);
        for (final u in parsed.users) {
          if (u.id.isEmpty) continue;
          byId[u.id] = CaptorUserOption(
            id: u.id,
            name: u.name.trim().isNotEmpty ? u.name.trim() : u.email,
            email: u.email.trim().isEmpty ? null : u.email.trim(),
          );
        }
        totalPages = parsed.totalPages > 0
            ? parsed.totalPages
            : (parsed.total / _pageSize).ceil().clamp(1, 1000);
        page += 1;
      } while (page <= totalPages && page <= 50);
      return ApiResponse.success(data: byId.values.toList(), statusCode: 200);
    } catch (e) {
      debugPrint('❌ [PROPERTY_CAPTOR_USERS] listCompanyUsers: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }
}
