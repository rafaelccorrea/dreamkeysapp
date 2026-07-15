import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../models/subscription_models.dart';

/// Serviço do domínio **Assinaturas & Planos** — consome os mesmos endpoints
/// que `imobx-front/src/services/subscriptionService.ts` e `pricingService.ts`
/// (backend Nest: `subscriptions.controller.ts` + `plans.controller.ts`).
///
/// Para o `GET /subscriptions/check-access` use o serviço compartilhado
/// `lib/shared/services/subscription_service.dart` (já existente no app).
///
/// Roles (RolesGuard do Nest):
/// - `my-usage` / `my-active-subscription` → **admin | master**
/// - `admin/all-subscriptions` → **admin | master** (admin vê só suas empresas)
/// - `admin/:id/usage`, `admin/:id/extend`, `admin/manage`, `PATCH admin/:id`
///   → **master**
class SubscriptionsService {
  SubscriptionsService._();

  static final SubscriptionsService instance = SubscriptionsService._();
  final ApiService _api = ApiService.instance;

  // Endpoints privados (fiação central em ApiConstants é opcional — ver
  // manifest da feature).
  static const String _myUsage = '/subscriptions/my-usage';
  static const String _myActive = '/subscriptions/my-active-subscription';
  static const String _plans = '/plans';
  static const String _pricingPage = '/plans/pricing-page';
  static const String _adminAll = '/subscriptions/admin/all-subscriptions';
  static const String _adminManage = '/subscriptions/admin/manage';
  static String _adminUsage(String id) => '/subscriptions/admin/$id/usage';
  static String _adminExtend(String id) => '/subscriptions/admin/$id/extend';
  static String _adminUpdate(String id) => '/subscriptions/admin/$id';

  /// Respostas do Nest às vezes vêm embrulhadas em `{ data: ... }`.
  Map<String, dynamic>? _unwrapMap(dynamic raw) {
    final map = asMap(raw);
    if (map == null) return null;
    final inner = asMap(map['data']);
    return inner ?? map;
  }

  // ─── Minha assinatura ──────────────────────────────────────────────────────

  /// `GET /subscriptions/my-usage` — uso e limites da assinatura do titular.
  /// 404 = nenhuma assinatura (o chamador decide o estado vazio).
  Future<ApiResponse<SubscriptionUsage>> getMyUsage() async {
    try {
      final response = await _api.get<Map<String, dynamic>>(_myUsage);
      if (response.success && response.data != null) {
        final body = _unwrapMap(response.data) ?? response.data!;
        return ApiResponse.success(
          data: SubscriptionUsage.fromJson(body),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar uso da assinatura',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [SUBSCRIPTIONS] getMyUsage: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /subscriptions/my-active-subscription` — assinatura ativa
  /// normalizada. `success` com `data == null` significa "sem assinatura"
  /// (a API devolve 200 com `{message}` nesse caso).
  Future<ApiResponse<ActiveSubscription?>> getMyActiveSubscription() async {
    try {
      final response = await _api.get<Map<String, dynamic>>(_myActive);
      if (response.success && response.data != null) {
        final body = _unwrapMap(response.data) ?? response.data!;
        return ApiResponse.success(
          data: ActiveSubscription.fromResponse(body),
          statusCode: response.statusCode,
        );
      }
      if (response.statusCode == 404) {
        return ApiResponse.success(data: null, statusCode: 404);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar assinatura',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [SUBSCRIPTIONS] getMyActiveSubscription: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  // ─── Vitrine de planos ─────────────────────────────────────────────────────

  /// Planos para a vitrine. Primário: `GET /plans/pricing-page` (dados ricos:
  /// features, módulos com nome, limites). Fallback: `GET /plans`.
  /// A lista volta ordenada: basic → professional → custom.
  Future<ApiResponse<List<PricingPlan>>> getPlansShowcase() async {
    try {
      final response = await _api.get<Map<String, dynamic>>(_pricingPage);
      if (response.success && response.data != null) {
        final body = _unwrapMap(response.data) ?? response.data!;
        final plansMap = asMap(body['plans']);
        if (plansMap != null && plansMap.isNotEmpty) {
          final ordered = <PricingPlan>[];
          for (final key in const ['basic', 'professional', 'custom']) {
            final planJson = asMap(plansMap[key]);
            if (planJson != null) {
              ordered.add(PricingPlan.fromPricingJson(key, planJson));
            }
          }
          if (ordered.isNotEmpty) {
            return ApiResponse.success(
              data: ordered,
              statusCode: response.statusCode,
            );
          }
        }
      }
      // Fallback: lista simples de planos ativos.
      return _getPlansFallback();
    } catch (e) {
      debugPrint('❌ [SUBSCRIPTIONS] getPlansShowcase: $e');
      return _getPlansFallback();
    }
  }

  Future<ApiResponse<List<PricingPlan>>> _getPlansFallback() async {
    try {
      final response = await _api.get<dynamic>(_plans);
      if (response.success && response.data != null) {
        final raw = response.data;
        final list = raw is List
            ? raw
            : (raw is Map && raw['data'] is List ? raw['data'] as List : null);
        if (list != null) {
          final plans = list
              .map(asMap)
              .whereType<Map<String, dynamic>>()
              .where((p) => p['isActive'] != false)
              .map(PricingPlan.fromPlanJson)
              .toList();
          return ApiResponse.success(
            data: plans,
            statusCode: response.statusCode,
          );
        }
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar planos',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [SUBSCRIPTIONS] _getPlansFallback: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  // ─── Gestão (master) ───────────────────────────────────────────────────────

  /// `GET /subscriptions/admin/all-subscriptions` — lista paginada com uso.
  /// MASTER vê todo o sistema; ADMIN vê apenas empresas que administra.
  Future<ApiResponse<AdminSubscriptionsResult>> getAllSubscriptions({
    AdminSubscriptionFilters filters = const AdminSubscriptionFilters(),
  }) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(
        _adminAll,
        queryParameters: filters.toQueryParams(),
      );
      if (response.success && response.data != null) {
        final body = _unwrapMap(response.data) ?? response.data!;
        return ApiResponse.success(
          data: AdminSubscriptionsResult.fromJson(body),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar assinaturas',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [SUBSCRIPTIONS] getAllSubscriptions: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /subscriptions/admin/:id/usage` — uso detalhado (apenas MASTER).
  Future<ApiResponse<SubscriptionUsage>> getSubscriptionUsageById(
    String subscriptionId,
  ) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(
        _adminUsage(subscriptionId),
      );
      if (response.success && response.data != null) {
        final body = _unwrapMap(response.data) ?? response.data!;
        return ApiResponse.success(
          data: SubscriptionUsage.fromJson(body),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Assinatura não encontrada',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [SUBSCRIPTIONS] getSubscriptionUsageById: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /subscriptions/admin/:id/extend` — adiciona [days] dias ao término
  /// (apenas MASTER). Body: `{days, reason?}` (AdminExtendSubscriptionDto).
  Future<ApiResponse<bool>> extendSubscription(
    String subscriptionId, {
    required int days,
    String? reason,
  }) async {
    try {
      final response = await _api.post<dynamic>(
        _adminExtend(subscriptionId),
        body: {
          'days': days,
          if (reason != null && reason.trim().isNotEmpty)
            'reason': reason.trim(),
        },
      );
      if (response.success) {
        return ApiResponse.success(
          data: true,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao estender assinatura',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [SUBSCRIPTIONS] extendSubscription: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /subscriptions/admin/manage` — ativa / suspende / cancela
  /// (apenas MASTER). Paridade com `subscriptionService.manageSubscription`
  /// do web (AdminManageSubscriptionDto).
  Future<ApiResponse<bool>> manageSubscription({
    required String subscriptionId,
    required String action, // 'activate' | 'suspend' | 'cancel'
    String? reason,
    String? notes,
    bool notifyUsers = true,
  }) async {
    try {
      final response = await _api.post<dynamic>(
        _adminManage,
        body: {
          'subscriptionId': subscriptionId,
          'action': action,
          if (reason != null && reason.trim().isNotEmpty)
            'reason': reason.trim(),
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
          'notifyUsers': notifyUsers,
        },
      );
      if (response.success) {
        return ApiResponse.success(
          data: true,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao executar ação na assinatura',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [SUBSCRIPTIONS] manageSubscription: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `PATCH /subscriptions/admin/:id` — atualiza notas / término / preço
  /// (apenas MASTER). Campos do AdminUpdateSubscriptionDto.
  Future<ApiResponse<bool>> updateSubscription(
    String subscriptionId, {
    String? notes,
    DateTime? endDate,
    double? price,
  }) async {
    try {
      final response = await _api.patch<dynamic>(
        _adminUpdate(subscriptionId),
        body: {
          if (notes != null) 'notes': notes,
          if (endDate != null) 'endDate': endDate.toUtc().toIso8601String(),
          if (price != null) 'price': price,
        },
      );
      if (response.success) {
        return ApiResponse.success(
          data: true,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar assinatura',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [SUBSCRIPTIONS] updateSubscription: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}
