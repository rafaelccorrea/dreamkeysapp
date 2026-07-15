import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../models/reward_model.dart';

/// Serviço de **Prêmios & Resgates** — consome `/rewards/*` (paridade com
/// `rewardsApi` do imobx-front / `rewards.controller.ts` do backend) e o
/// saldo de pontos em `/gamification/my-score`.
///
/// Permissões (batidas no backend; aqui só gating de UI):
///   catálogo/resgatar → `reward:redeem` · aprovar → `reward:approve` ·
///   gerenciar → `reward:view` · criar → `reward:create` ·
///   editar → `reward:update` · excluir → `reward:delete` ·
///   entregar → `reward:deliver`.
class RewardsService {
  RewardsService._();

  static final RewardsService instance = RewardsService._();
  final ApiService _api = ApiService.instance;

  // Endpoints (constantes privadas — a fiação central fica em ApiConstants).
  static const String _rewards = '/rewards';
  static const String _rewardsAvailable = '/rewards/available';
  static const String _rewardsRedeem = '/rewards/redeem';
  static const String _myRedemptions = '/rewards/redemptions/my';
  static const String _pendingRedemptions = '/rewards/redemptions/pending';
  static const String _redemptionStats = '/rewards/stats/redemptions';
  static String _rewardById(String id) => '/rewards/$id';
  static String _redemptionReview(String id) => '/rewards/redemptions/$id/review';
  static String _redemptionDeliver(String id) =>
      '/rewards/redemptions/$id/deliver';
  static const String _myScore = '/gamification/my-score';

  // ─── Helpers ───────────────────────────────────────────────────────────────

  /// Extrai `data` (Map) do envelope `{ success, data, ... }`.
  Map<String, dynamic>? _unwrapMap(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final data = map['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return map;
  }

  /// Extrai `data` (List) do envelope `{ success, data: [...] }`.
  List<Map<String, dynamic>> _unwrapList(dynamic raw) {
    dynamic data = raw;
    if (raw is Map) data = raw['data'];
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  ApiResponse<T> _err<T>(ApiResponse<dynamic> res, String fallback) {
    return ApiResponse.error(
      message: res.message ?? fallback,
      statusCode: res.statusCode,
      data: res.error,
    );
  }

  // ─── Catálogo / pontos ─────────────────────────────────────────────────────

  /// `GET /rewards/available` — prêmios ativos disponíveis para resgate.
  Future<ApiResponse<List<Reward>>> getAvailableRewards() async {
    try {
      final res = await _api.get<Map<String, dynamic>>(_rewardsAvailable);
      if (res.success && res.data != null) {
        final list =
            _unwrapList(res.data).map(Reward.fromJson).toList(growable: false);
        return ApiResponse.success(data: list, statusCode: res.statusCode);
      }
      return _err(res, 'Erro ao carregar o catálogo de prêmios');
    } catch (e) {
      debugPrint('❌ [REWARDS] getAvailableRewards: $e');
      return ApiResponse.error(
          message: 'Erro de conexão: ${e.toString()}', statusCode: 0);
    }
  }

  /// `GET /gamification/my-score?period=all_time` — pontos do usuário
  /// (paridade com o header do catálogo no web: `totalPoints` acumulado).
  Future<ApiResponse<int>> getMyPoints() async {
    try {
      final res = await _api.get<Map<String, dynamic>>(
        _myScore,
        queryParameters: const {'period': 'all_time'},
      );
      if (res.success && res.data != null) {
        final data = _unwrapMap(res.data);
        final raw = data?['totalPoints'] ?? data?['total_points'];
        final points = raw is num
            ? raw.toInt()
            : int.tryParse(raw?.toString() ?? '') ?? 0;
        return ApiResponse.success(data: points, statusCode: res.statusCode);
      }
      return _err(res, 'Erro ao carregar seus pontos');
    } catch (e) {
      debugPrint('❌ [REWARDS] getMyPoints: $e');
      return ApiResponse.error(
          message: 'Erro de conexão: ${e.toString()}', statusCode: 0);
    }
  }

  /// `POST /rewards/redeem` — solicita o resgate (pontos só são debitados
  /// na aprovação do gestor).
  Future<ApiResponse<RewardRedemption>> redeemReward({
    required String rewardId,
    String? userNotes,
  }) async {
    try {
      final body = <String, dynamic>{'rewardId': rewardId};
      final notes = userNotes?.trim();
      if (notes != null && notes.isNotEmpty) body['userNotes'] = notes;

      final res = await _api.post<Map<String, dynamic>>(
        _rewardsRedeem,
        body: body,
      );
      if (res.success && res.data != null) {
        final data = _unwrapMap(res.data);
        return ApiResponse.success(
          data: data != null ? RewardRedemption.fromJson(data) : null,
          statusCode: res.statusCode,
        );
      }
      return _err(res, 'Erro ao solicitar o resgate');
    } catch (e) {
      debugPrint('❌ [REWARDS] redeemReward: $e');
      return ApiResponse.error(
          message: 'Erro de conexão: ${e.toString()}', statusCode: 0);
    }
  }

  // ─── Meus resgates ─────────────────────────────────────────────────────────

  /// `GET /rewards/redemptions/my` — todas as minhas solicitações.
  Future<ApiResponse<List<RewardRedemption>>> getMyRedemptions() async {
    try {
      final res = await _api.get<Map<String, dynamic>>(_myRedemptions);
      if (res.success && res.data != null) {
        final list = _unwrapList(res.data)
            .map(RewardRedemption.fromJson)
            .toList(growable: false);
        return ApiResponse.success(data: list, statusCode: res.statusCode);
      }
      return _err(res, 'Erro ao carregar seus resgates');
    } catch (e) {
      debugPrint('❌ [REWARDS] getMyRedemptions: $e');
      return ApiResponse.error(
          message: 'Erro de conexão: ${e.toString()}', statusCode: 0);
    }
  }

  // ─── Aprovação (gestor) ────────────────────────────────────────────────────

  /// `GET /rewards/redemptions/pending` — solicitações da empresa
  /// (filtro opcional por status; sem status retorna todas).
  Future<ApiResponse<RedemptionListResult>> getPendingRedemptions({
    RedemptionStatus? status,
    int page = 1,
    int limit = 100,
  }) async {
    try {
      final params = <String, String>{'page': '$page', 'limit': '$limit'};
      if (status != null && status != RedemptionStatus.unknown) {
        params['status'] = status.raw;
      }
      final res = await _api.get<Map<String, dynamic>>(
        _pendingRedemptions,
        queryParameters: params,
      );
      if (res.success && res.data != null) {
        final list = _unwrapList(res.data)
            .map(RewardRedemption.fromJson)
            .toList(growable: false);
        final rawTotal = res.data!['total'];
        final total = rawTotal is num
            ? rawTotal.toInt()
            : int.tryParse(rawTotal?.toString() ?? '') ?? list.length;
        return ApiResponse.success(
          data: RedemptionListResult(redemptions: list, total: total),
          statusCode: res.statusCode,
        );
      }
      return _err(res, 'Erro ao carregar as solicitações');
    } catch (e) {
      debugPrint('❌ [REWARDS] getPendingRedemptions: $e');
      return ApiResponse.error(
          message: 'Erro de conexão: ${e.toString()}', statusCode: 0);
    }
  }

  /// `POST /rewards/redemptions/:id/review` — aprova (`approved`, debita os
  /// pontos) ou rejeita (`rejected`) uma solicitação.
  Future<ApiResponse<RewardRedemption>> reviewRedemption({
    required String id,
    required bool approve,
    String? reviewNotes,
  }) async {
    try {
      final body = <String, dynamic>{
        'status': approve ? 'approved' : 'rejected',
      };
      final notes = reviewNotes?.trim();
      if (notes != null && notes.isNotEmpty) body['reviewNotes'] = notes;

      final res = await _api.post<Map<String, dynamic>>(
        _redemptionReview(id),
        body: body,
      );
      if (res.success && res.data != null) {
        final data = _unwrapMap(res.data);
        return ApiResponse.success(
          data: data != null ? RewardRedemption.fromJson(data) : null,
          statusCode: res.statusCode,
        );
      }
      return _err(res, 'Erro ao processar a solicitação');
    } catch (e) {
      debugPrint('❌ [REWARDS] reviewRedemption: $e');
      return ApiResponse.error(
          message: 'Erro de conexão: ${e.toString()}', statusCode: 0);
    }
  }

  /// `POST /rewards/redemptions/:id/deliver` — marca como entregue.
  Future<ApiResponse<RewardRedemption>> deliverRedemption({
    required String id,
    String? notes,
  }) async {
    try {
      final body = <String, dynamic>{};
      final n = notes?.trim();
      if (n != null && n.isNotEmpty) body['reviewNotes'] = n;

      final res = await _api.post<Map<String, dynamic>>(
        _redemptionDeliver(id),
        body: body,
      );
      if (res.success && res.data != null) {
        final data = _unwrapMap(res.data);
        return ApiResponse.success(
          data: data != null ? RewardRedemption.fromJson(data) : null,
          statusCode: res.statusCode,
        );
      }
      return _err(res, 'Erro ao marcar como entregue');
    } catch (e) {
      debugPrint('❌ [REWARDS] deliverRedemption: $e');
      return ApiResponse.error(
          message: 'Erro de conexão: ${e.toString()}', statusCode: 0);
    }
  }

  // ─── Gestão de prêmios (admin) ─────────────────────────────────────────────

  /// `GET /rewards?includeInactive=` — todos os prêmios (admin).
  Future<ApiResponse<List<Reward>>> getAllRewards({
    bool includeInactive = false,
  }) async {
    try {
      final res = await _api.get<Map<String, dynamic>>(
        _rewards,
        queryParameters: {'includeInactive': includeInactive ? 'true' : 'false'},
      );
      if (res.success && res.data != null) {
        final list =
            _unwrapList(res.data).map(Reward.fromJson).toList(growable: false);
        return ApiResponse.success(data: list, statusCode: res.statusCode);
      }
      return _err(res, 'Erro ao carregar os prêmios');
    } catch (e) {
      debugPrint('❌ [REWARDS] getAllRewards: $e');
      return ApiResponse.error(
          message: 'Erro de conexão: ${e.toString()}', statusCode: 0);
    }
  }

  /// `GET /rewards/:id` — detalhe de um prêmio (prefill da edição).
  Future<ApiResponse<Reward>> getRewardById(String id) async {
    try {
      final res = await _api.get<Map<String, dynamic>>(_rewardById(id));
      if (res.success && res.data != null) {
        final data = _unwrapMap(res.data);
        if (data != null) {
          return ApiResponse.success(
            data: Reward.fromJson(data),
            statusCode: res.statusCode,
          );
        }
      }
      return _err(res, 'Prêmio não encontrado');
    } catch (e) {
      debugPrint('❌ [REWARDS] getRewardById: $e');
      return ApiResponse.error(
          message: 'Erro de conexão: ${e.toString()}', statusCode: 0);
    }
  }

  /// `POST /rewards` — cria prêmio.
  Future<ApiResponse<Reward>> createReward(RewardPayload payload) async {
    try {
      final res =
          await _api.post<Map<String, dynamic>>(_rewards, body: payload.toJson());
      if (res.success && res.data != null) {
        final data = _unwrapMap(res.data);
        return ApiResponse.success(
          data: data != null ? Reward.fromJson(data) : null,
          statusCode: res.statusCode,
        );
      }
      return _err(res, 'Erro ao criar o prêmio');
    } catch (e) {
      debugPrint('❌ [REWARDS] createReward: $e');
      return ApiResponse.error(
          message: 'Erro de conexão: ${e.toString()}', statusCode: 0);
    }
  }

  /// `PUT /rewards/:id` — atualiza prêmio (inclui ativar/desativar).
  Future<ApiResponse<Reward>> updateReward(
    String id,
    Map<String, dynamic> changes,
  ) async {
    try {
      final res = await _api.put<Map<String, dynamic>>(
        _rewardById(id),
        body: changes,
      );
      if (res.success && res.data != null) {
        final data = _unwrapMap(res.data);
        return ApiResponse.success(
          data: data != null ? Reward.fromJson(data) : null,
          statusCode: res.statusCode,
        );
      }
      return _err(res, 'Erro ao atualizar o prêmio');
    } catch (e) {
      debugPrint('❌ [REWARDS] updateReward: $e');
      return ApiResponse.error(
          message: 'Erro de conexão: ${e.toString()}', statusCode: 0);
    }
  }

  /// `DELETE /rewards/:id` — exclui prêmio.
  Future<ApiResponse<void>> deleteReward(String id) async {
    try {
      final res = await _api.delete<Map<String, dynamic>>(_rewardById(id));
      if (res.success) {
        return ApiResponse.success(statusCode: res.statusCode);
      }
      return _err(res, 'Erro ao excluir o prêmio');
    } catch (e) {
      debugPrint('❌ [REWARDS] deleteReward: $e');
      return ApiResponse.error(
          message: 'Erro de conexão: ${e.toString()}', statusCode: 0);
    }
  }

  /// `GET /rewards/stats/redemptions` — estatísticas de resgates (admin).
  Future<ApiResponse<RewardStats>> getRedemptionStats() async {
    try {
      final res = await _api.get<Map<String, dynamic>>(_redemptionStats);
      if (res.success && res.data != null) {
        final data = _unwrapMap(res.data);
        return ApiResponse.success(
          data: data != null ? RewardStats.fromJson(data) : RewardStats.zero,
          statusCode: res.statusCode,
        );
      }
      return _err(res, 'Erro ao carregar as estatísticas');
    } catch (e) {
      debugPrint('❌ [REWARDS] getRedemptionStats: $e');
      return ApiResponse.error(
          message: 'Erro de conexão: ${e.toString()}', statusCode: 0);
    }
  }
}
