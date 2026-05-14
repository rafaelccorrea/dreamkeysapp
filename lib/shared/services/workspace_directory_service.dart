import 'package:flutter/foundation.dart';

import '../../core/constants/api_constants.dart';
import 'api_service.dart';

class CompanyUserRow {
  final String id;
  final String name;
  final String email;
  final String role;
  final bool isActiveInCompany;

  CompanyUserRow({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.isActiveInCompany,
  });

  factory CompanyUserRow.fromJson(Map<String, dynamic> j) {
    return CompanyUserRow(
      id: j['id']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
      email: j['email']?.toString() ?? '',
      role: j['role']?.toString() ?? '',
      isActiveInCompany: j['isActiveInCompany'] != false,
    );
  }
}

class AdminUsersListResult {
  final List<CompanyUserRow> users;
  final int total;
  final int page;
  final int totalPages;

  AdminUsersListResult({
    required this.users,
    required this.total,
    required this.page,
    required this.totalPages,
  });
}

/// Listagem de utilizadores da empresa — `GET /admin/users`.
class AdminUsersService {
  AdminUsersService._();
  static final AdminUsersService instance = AdminUsersService._();
  final ApiService _api = ApiService.instance;

  Future<ApiResponse<AdminUsersListResult>> listUsers({
    int page = 1,
    int limit = 40,
    bool compact = true,
  }) async {
    try {
      final res = await _api.get<Map<String, dynamic>>(
        ApiConstants.adminUsers,
        queryParameters: {
          'page': '$page',
          'limit': '$limit',
          'compact': '$compact',
        },
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao listar utilizadores',
          statusCode: res.statusCode,
        );
      }
      final m = res.data!;
      final raw = m['data'];
      if (raw is! List) {
        return ApiResponse.error(
          message: 'Resposta inválida',
          statusCode: res.statusCode,
        );
      }
      final users = raw
          .map(
            (e) => CompanyUserRow.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
      return ApiResponse.success(
        data: AdminUsersListResult(
          users: users,
          total: int.tryParse(m['total']?.toString() ?? '') ?? users.length,
          page: int.tryParse(m['page']?.toString() ?? '') ?? page,
          totalPages: int.tryParse(m['totalPages']?.toString() ?? '') ?? 1,
        ),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [ADMIN_USERS] $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }
}

/// Assinatura ativa — `GET /subscriptions/my-active-subscription`.
class SubscriptionInfoService {
  SubscriptionInfoService._();
  static final SubscriptionInfoService instance = SubscriptionInfoService._();
  final ApiService _api = ApiService.instance;

  Future<ApiResponse<Map<String, dynamic>>> getMyActiveSubscription() async {
    try {
      final res = await _api.get<Map<String, dynamic>>(
        ApiConstants.subscriptionsMyActive,
      );
      if (res.success && res.data != null) {
        return ApiResponse.success(
          data: res.data!,
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.error(
        message: res.message ?? 'Sem dados de assinatura',
        statusCode: res.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }
}
