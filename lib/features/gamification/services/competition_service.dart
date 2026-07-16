import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../models/competition_models.dart';

/// Serviço de Competições e Prêmios — consome `/competitions*` (paridade com
/// `competition.service.ts` + `prizesApi.ts` do imobx-front). Backend envolve
/// tudo em `{ success, data }` — sempre desembrulhamos `data`.
class CompetitionService {
  CompetitionService._();

  static final CompetitionService instance = CompetitionService._();
  final ApiService _api = ApiService.instance;

  // Endpoints (paridade `competition.controller.ts` do imobx).
  static const String _competitions = '/competitions';
  static const String _prizesAll = '/competitions/prizes/all';
  static String _competitionById(String id) => '/competitions/$id';
  static String _competitionStatus(String id) => '/competitions/$id/status';
  static String _competitionFinalize(String id) => '/competitions/$id/finalize';
  static String _competitionPrizes(String id) => '/competitions/$id/prizes';
  static String _prizeById(String prizeId) => '/competitions/prizes/$prizeId';
  static String _prizeDeliver(String prizeId) =>
      '/competitions/prizes/$prizeId/deliver';

  // Fontes para o seletor de participantes (mesmas listas usadas no web:
  // `UserMultiSelect` → companyMembersApi.getMembersSimple(),
  // `TeamMultiSelect` → GET /teams).
  static const String _companyMembersSimple = '/users/company-members/simple';
  static const String _teams = '/teams';

  Map<String, dynamic>? _unwrap(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final data = map['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return map;
  }

  List<dynamic> _unwrapList(dynamic raw) {
    if (raw is List) return raw;
    if (raw is Map) {
      final data = raw['data'];
      if (data is List) return data;
    }
    return const [];
  }

  ApiResponse<T> _connError<T>(String tag, Object e) {
    debugPrint('❌ [COMPETITION] $tag: $e');
    return ApiResponse.error(
      message: 'Erro de conexão: ${e.toString()}',
      statusCode: 0,
    );
  }

  // ─── Competições ──────────────────────────────────────────────────────────

  /// `GET /competitions?status=` — lista (backend já traz `prizes`).
  Future<ApiResponse<List<Competition>>> getCompetitions({
    CompetitionStatus? status,
  }) async {
    try {
      final response = await _api.get<dynamic>(
        _competitions,
        queryParameters: status != null ? {'status': status.value} : null,
      );
      if (response.success) {
        final list = _unwrapList(response.data)
            .whereType<Map>()
            .map((e) => Competition.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        return ApiResponse.success(data: list, statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar competições',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      return _connError('getCompetitions', e);
    }
  }

  /// `GET /competitions/:id` — detalhe (com prêmios).
  Future<ApiResponse<Competition>> getById(String id) async {
    try {
      final response = await _api.get<dynamic>(_competitionById(id));
      if (response.success && response.data != null) {
        final body = _unwrap(response.data);
        if (body != null) {
          return ApiResponse.success(
            data: Competition.fromJson(body),
            statusCode: response.statusCode,
          );
        }
      }
      return ApiResponse.error(
        message: response.message ?? 'Competição não encontrada',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      return _connError('getById', e);
    }
  }

  /// `POST /competitions` — cria.
  Future<ApiResponse<Competition>> create(CompetitionPayload payload) async {
    try {
      final response =
          await _api.post<dynamic>(_competitions, body: payload.toJson());
      if (response.success && response.data != null) {
        final body = _unwrap(response.data);
        if (body != null) {
          return ApiResponse.success(
            data: Competition.fromJson(body),
            statusCode: response.statusCode,
          );
        }
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar competição',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      return _connError('create', e);
    }
  }

  /// `PUT /competitions/:id` — atualiza.
  Future<ApiResponse<Competition>> update(
    String id,
    CompetitionPayload payload,
  ) async {
    try {
      final response = await _api.put<dynamic>(
        _competitionById(id),
        body: payload.toJson(),
      );
      if (response.success && response.data != null) {
        final body = _unwrap(response.data);
        if (body != null) {
          return ApiResponse.success(
            data: Competition.fromJson(body),
            statusCode: response.statusCode,
          );
        }
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar competição',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      return _connError('update', e);
    }
  }

  /// `PUT /competitions/:id/status` — muda o status.
  Future<ApiResponse<Competition>> changeStatus(
    String id,
    CompetitionStatus status,
  ) async {
    try {
      final response = await _api.put<dynamic>(
        _competitionStatus(id),
        body: {'status': status.value},
      );
      if (response.success) {
        final body = _unwrap(response.data);
        return ApiResponse.success(
          data: body != null ? Competition.fromJson(body) : null,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar status',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      return _connError('changeStatus', e);
    }
  }

  /// `POST /competitions/:id/finalize` — encerra e apura vencedores.
  Future<ApiResponse<Competition>> finalize(String id) async {
    try {
      final response = await _api.post<dynamic>(_competitionFinalize(id));
      if (response.success) {
        final body = _unwrap(response.data);
        return ApiResponse.success(
          data: body != null ? Competition.fromJson(body) : null,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao finalizar competição',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      return _connError('finalize', e);
    }
  }

  /// `DELETE /competitions/:id` — exclui (só rascunho/agendada).
  Future<ApiResponse<void>> delete(String id) async {
    try {
      final response = await _api.delete<dynamic>(_competitionById(id));
      if (response.success) {
        return ApiResponse.success(statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao excluir competição',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      return _connError('delete', e);
    }
  }

  // ─── Prêmios ──────────────────────────────────────────────────────────────

  /// `GET /competitions/prizes/all` — todos os prêmios da empresa.
  Future<ApiResponse<List<Prize>>> getAllPrizes() async {
    try {
      final response = await _api.get<dynamic>(_prizesAll);
      if (response.success) {
        final list = _unwrapList(response.data)
            .whereType<Map>()
            .map((e) => Prize.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        return ApiResponse.success(data: list, statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar prêmios',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      return _connError('getAllPrizes', e);
    }
  }

  /// `POST /competitions/:id/prizes` — adiciona prêmio à competição.
  Future<ApiResponse<CompetitionPrize>> addPrize(
    String competitionId,
    PrizePayload payload,
  ) async {
    try {
      final response = await _api.post<dynamic>(
        _competitionPrizes(competitionId),
        body: payload.toJson(),
      );
      if (response.success) {
        final body = _unwrap(response.data);
        return ApiResponse.success(
          data: body != null ? CompetitionPrize.fromJson(body) : null,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao adicionar prêmio',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      return _connError('addPrize', e);
    }
  }

  /// `PUT /competitions/prizes/:prizeId` — atualiza prêmio.
  Future<ApiResponse<CompetitionPrize>> updatePrize(
    String prizeId, {
    String? name,
    String? description,
    double? value,
    String? imageUrl,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (description != null) body['description'] = description;
      if (value != null) body['value'] = value;
      if (imageUrl != null) body['imageUrl'] = imageUrl;
      final response = await _api.put<dynamic>(_prizeById(prizeId), body: body);
      if (response.success) {
        final body = _unwrap(response.data);
        return ApiResponse.success(
          data: body != null ? CompetitionPrize.fromJson(body) : null,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar prêmio',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      return _connError('updatePrize', e);
    }
  }

  /// `DELETE /competitions/prizes/:prizeId` — remove prêmio.
  Future<ApiResponse<void>> removePrize(String prizeId) async {
    try {
      final response = await _api.delete<dynamic>(_prizeById(prizeId));
      if (response.success) {
        return ApiResponse.success(statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao remover prêmio',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      return _connError('removePrize', e);
    }
  }

  /// `POST /competitions/prizes/:prizeId/deliver` — marca como entregue.
  Future<ApiResponse<void>> deliverPrize(String prizeId) async {
    try {
      final response = await _api.post<dynamic>(_prizeDeliver(prizeId));
      if (response.success) {
        return ApiResponse.success(statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao marcar prêmio como entregue',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      return _connError('deliverPrize', e);
    }
  }

  // ─── Fontes do seletor de participantes ───────────────────────────────────

  /// `GET /users/company-members/simple` — membros da empresa para o seletor
  /// de participantes (mesma fonte do `UserMultiSelect` do web; acessível a
  /// qualquer usuário autenticado).
  Future<ApiResponse<List<ParticipantUser>>> getSelectableUsers() async {
    try {
      final response = await _api.get<dynamic>(_companyMembersSimple);
      if (response.success) {
        final list = _unwrapList(response.data)
            .whereType<Map>()
            .map((e) => ParticipantUser.fromJson(Map<String, dynamic>.from(e)))
            .where((u) => u.id.isNotEmpty)
            .toList();
        return ApiResponse.success(data: list, statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar corretores',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      return _connError('getSelectableUsers', e);
    }
  }

  /// `GET /teams` — equipes da empresa para o seletor de participantes.
  Future<ApiResponse<List<ParticipantTeam>>> getSelectableTeams() async {
    try {
      final response = await _api.get<dynamic>(_teams);
      if (response.success) {
        final list = _unwrapList(response.data)
            .whereType<Map>()
            .map((e) => ParticipantTeam.fromJson(Map<String, dynamic>.from(e)))
            .where((t) => t.id.isNotEmpty)
            .toList();
        return ApiResponse.success(data: list, statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar equipes',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      return _connError('getSelectableTeams', e);
    }
  }
}
