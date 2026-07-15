import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../models/pending_domain_model.dart';
import '../models/platform_billing_model.dart';
import '../models/presence_model.dart';

/// Serviço da Plataforma (Master) — consome três controladores do backend,
/// todos protegidos por `@Roles(UserRole.MASTER)`:
///
///   • `/platform-settings/*`            → cobrança do sistema
///   • `/master/presence/*`              → monitoria online
///   • `/public-site-config/admin/*`     → domínios de sites públicos
///
/// Paridade: `platformSettingsService.ts`, `presenceApi.ts` e
/// `publicSiteConfigApi.ts` do imobx-front. Endpoints ficam como constantes
/// privadas aqui (não editamos `api_constants.dart` — fiação é central).
class PlatformAdminService {
  PlatformAdminService._();

  static final PlatformAdminService instance = PlatformAdminService._();
  final ApiService _api = ApiService.instance;

  // ─── Endpoints (privados) ──────────────────────────────────────────────────
  static const String _platformSettings = '/platform-settings';
  static const String _billingEnforcement =
      '/platform-settings/billing-enforcement';
  static const String _accounts = '/platform-settings/accounts';
  static String _accountManagedUntil(String userId) =>
      '/platform-settings/accounts/$userId/managed-until';
  static String _accountBillingRegime(String userId) =>
      '/platform-settings/accounts/$userId/billing-regime';

  static const String _presenceOverview = '/master/presence/overview';
  static const String _presenceOnlineUsers = '/master/presence/online-users';
  static String _presenceForceLogout(String userId) =>
      '/master/presence/force-logout/$userId';

  static const String _pendingDomains =
      '/public-site-config/admin/pending-domains';
  static String _approveDomain(String companyId) =>
      '/public-site-config/admin/approve-domain/$companyId';
  static String _rejectDomain(String companyId) =>
      '/public-site-config/admin/reject-domain/$companyId';

  // ─── Helpers ───────────────────────────────────────────────────────────────

  Map<String, dynamic>? _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  List<Map<String, dynamic>> _asMapList(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  ApiResponse<T> _error<T>(ApiResponse<dynamic> res, String fallback) {
    return ApiResponse.error(
      message: res.message ?? fallback,
      statusCode: res.statusCode,
      data: res.error,
    );
  }

  ApiResponse<T> _connError<T>(Object e) {
    return ApiResponse.error(
      message: 'Erro de conexão: $e',
      statusCode: 0,
    );
  }

  // ─── Cobrança do sistema ───────────────────────────────────────────────────

  /// `GET /platform-settings` — config global (flag + dias de graça).
  Future<ApiResponse<PlatformSettings>> getSettings() async {
    try {
      final res = await _api.get<dynamic>(_platformSettings);
      final map = _asMap(res.data);
      if (res.success && map != null) {
        return ApiResponse.success(
          data: PlatformSettings.fromJson(map),
          statusCode: res.statusCode,
        );
      }
      return _error(res, 'Erro ao carregar a configuração de cobrança');
    } catch (e) {
      debugPrint('❌ [PLATFORM_ADMIN] getSettings: $e');
      return _connError(e);
    }
  }

  /// `PUT /platform-settings/billing-enforcement` — liga/desliga a cobrança
  /// global. `graceDays` persiste os dias de graça junto.
  Future<ApiResponse<PlatformSettings>> setBillingEnforcement(
    bool enabled, {
    int? graceDays,
    int? managedTrialDays,
  }) async {
    try {
      final body = <String, dynamic>{'enabled': enabled};
      if (graceDays != null) body['graceDays'] = graceDays;
      if (managedTrialDays != null) body['managedTrialDays'] = managedTrialDays;
      final res = await _api.put<dynamic>(_billingEnforcement, body: body);
      final map = _asMap(res.data);
      if (res.success && map != null) {
        return ApiResponse.success(
          data: PlatformSettings.fromJson(map),
          statusCode: res.statusCode,
        );
      }
      return _error(res, 'Erro ao atualizar a flag de cobrança');
    } catch (e) {
      debugPrint('❌ [PLATFORM_ADMIN] setBillingEnforcement: $e');
      return _connError(e);
    }
  }

  /// `GET /platform-settings/accounts` — contas titulares (busca opcional).
  Future<ApiResponse<List<OwnerAccount>>> listAccounts({String? search}) async {
    try {
      final term = search?.trim();
      final res = await _api.get<dynamic>(
        _accounts,
        queryParameters:
            term != null && term.isNotEmpty ? {'search': term} : null,
      );
      if (res.success) {
        final list =
            _asMapList(res.data).map(OwnerAccount.fromJson).toList();
        return ApiResponse.success(data: list, statusCode: res.statusCode);
      }
      return _error(res, 'Erro ao listar as contas');
    } catch (e) {
      debugPrint('❌ [PLATFORM_ADMIN] listAccounts: $e');
      return _connError(e);
    }
  }

  /// `PATCH /platform-settings/accounts/:id/managed-until` — flag por conta:
  /// `until = null` → liberada (indefinido); ISO no passado → cobra agora;
  /// ISO futuro → fim do trial agendado.
  Future<ApiResponse<OwnerAccount>> setManagedUntil(
    String userId,
    DateTime? until,
  ) async {
    try {
      final res = await _api.patch<dynamic>(
        _accountManagedUntil(userId),
        body: {'until': until?.toUtc().toIso8601String()},
      );
      final map = _asMap(res.data);
      if (res.success && map != null) {
        return ApiResponse.success(
          data: OwnerAccount.fromJson(map),
          statusCode: res.statusCode,
        );
      }
      return _error(res, 'Erro ao alterar a cobrança da conta');
    } catch (e) {
      debugPrint('❌ [PLATFORM_ADMIN] setManagedUntil: $e');
      return _connError(e);
    }
  }

  /// `PATCH /platform-settings/accounts/:id/billing-regime` — muda o regime
  /// da conta (`managed` | `self_serve`).
  Future<ApiResponse<void>> setAccountBillingRegime(
    String userId,
    BillingRegime regime,
  ) async {
    try {
      final res = await _api.patch<dynamic>(
        _accountBillingRegime(userId),
        body: {'regime': regime.apiValue},
      );
      if (res.success) {
        return ApiResponse.success(statusCode: res.statusCode);
      }
      return _error(res, 'Erro ao alterar o regime da conta');
    } catch (e) {
      debugPrint('❌ [PLATFORM_ADMIN] setAccountBillingRegime: $e');
      return _connError(e);
    }
  }

  // ─── Monitoria online ──────────────────────────────────────────────────────

  /// `GET /master/presence/overview` — números agregados de presença.
  Future<ApiResponse<PresenceOverview>> getPresenceOverview() async {
    try {
      final res = await _api.get<dynamic>(_presenceOverview);
      final map = _asMap(res.data);
      if (res.success && map != null) {
        return ApiResponse.success(
          data: PresenceOverview.fromJson(map),
          statusCode: res.statusCode,
        );
      }
      return _error(res, 'Erro ao carregar a visão geral de presença');
    } catch (e) {
      debugPrint('❌ [PLATFORM_ADMIN] getPresenceOverview: $e');
      return _connError(e);
    }
  }

  /// `GET /master/presence/online-users` — quem está online agora.
  Future<ApiResponse<OnlineUsersResult>> getOnlineUsers({
    int page = 1,
    int limit = 500,
    String? search,
  }) async {
    try {
      final params = <String, String>{'page': '$page', 'limit': '$limit'};
      final term = search?.trim();
      if (term != null && term.isNotEmpty) params['search'] = term;
      final res =
          await _api.get<dynamic>(_presenceOnlineUsers, queryParameters: params);
      final map = _asMap(res.data);
      if (res.success && map != null) {
        return ApiResponse.success(
          data: OnlineUsersResult.fromJson(map),
          statusCode: res.statusCode,
        );
      }
      return _error(res, 'Erro ao listar usuários online');
    } catch (e) {
      debugPrint('❌ [PLATFORM_ADMIN] getOnlineUsers: $e');
      return _connError(e);
    }
  }

  /// `POST /master/presence/force-logout/:userId` — encerra todas as sessões.
  Future<ApiResponse<ForceLogoutResult>> forceLogout(String userId) async {
    try {
      final res = await _api.post<dynamic>(_presenceForceLogout(userId));
      final map = _asMap(res.data);
      if (res.success) {
        return ApiResponse.success(
          data: map != null
              ? ForceLogoutResult.fromJson(map)
              : const ForceLogoutResult(success: true, disconnectedSockets: 0),
          statusCode: res.statusCode,
        );
      }
      return _error(res, 'Não foi possível forçar o logout');
    } catch (e) {
      debugPrint('❌ [PLATFORM_ADMIN] forceLogout: $e');
      return _connError(e);
    }
  }

  // ─── Domínios de sites públicos ────────────────────────────────────────────

  /// `GET /public-site-config/admin/pending-domains` — fila de domínios.
  Future<ApiResponse<List<PendingCustomDomain>>> listPendingDomains() async {
    try {
      final res = await _api.get<dynamic>(_pendingDomains);
      if (res.success) {
        final list =
            _asMapList(res.data).map(PendingCustomDomain.fromJson).toList();
        return ApiResponse.success(data: list, statusCode: res.statusCode);
      }
      return _error(res, 'Erro ao carregar domínios pendentes');
    } catch (e) {
      debugPrint('❌ [PLATFORM_ADMIN] listPendingDomains: $e');
      return _connError(e);
    }
  }

  /// `POST /public-site-config/admin/approve-domain/:companyId`.
  Future<ApiResponse<void>> approveDomain(String companyId) async {
    try {
      final res = await _api.post<dynamic>(_approveDomain(companyId));
      if (res.success) {
        return ApiResponse.success(statusCode: res.statusCode);
      }
      return _error(res, 'Erro ao aprovar o domínio');
    } catch (e) {
      debugPrint('❌ [PLATFORM_ADMIN] approveDomain: $e');
      return _connError(e);
    }
  }

  /// `POST /public-site-config/admin/reject-domain/:companyId`.
  Future<ApiResponse<void>> rejectDomain(String companyId) async {
    try {
      final res = await _api.post<dynamic>(_rejectDomain(companyId));
      if (res.success) {
        return ApiResponse.success(statusCode: res.statusCode);
      }
      return _error(res, 'Erro ao rejeitar o domínio');
    } catch (e) {
      debugPrint('❌ [PLATFORM_ADMIN] rejectDomain: $e');
      return _connError(e);
    }
  }
}
