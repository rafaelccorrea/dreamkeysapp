import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../models/unit_model.dart';

/// Serviço de Unidades (filiais) — consome `/units` (paridade com o
/// `unitsApi` do imobx-front / `UnitsController` do Nest).
///
/// Leitura exige `unit:view`; criar/editar/excluir/definir gestores exigem
/// `unit:manage` (o backend é a autoridade).
class UnitService {
  UnitService._();

  static final UnitService instance = UnitService._();
  final ApiService _api = ApiService.instance;

  // Endpoints privados da feature (fiação central fica fora daqui).
  static const String _units = '/units';
  static String _unitById(String id) => '/units/$id';
  static String _unitManagers(String id) => '/units/$id/managers';
  static const String _companyMembers = '/users/company-members';

  List<OrgUnit> _parseList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => OrgUnit.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  OrgUnit? _parseOne(dynamic raw) {
    if (raw is Map) {
      return OrgUnit.fromJson(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  /// `GET /units` — lista unidades da empresa.
  Future<ApiResponse<List<OrgUnit>>> list({bool activeOnly = false}) async {
    try {
      final response = await _api.get<dynamic>(
        _units,
        queryParameters: activeOnly ? {'activeOnly': 'true'} : null,
      );
      if (response.success) {
        return ApiResponse.success(
          data: _parseList(response.data),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar unidades',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [UNITS] list: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /units` — cria unidade (com gestores opcionais).
  Future<ApiResponse<OrgUnit>> create({
    required String name,
    String? description,
    String? color,
    List<String> managerUserIds = const [],
  }) async {
    try {
      final response = await _api.post<dynamic>(_units, body: {
        'name': name,
        if (description != null && description.isNotEmpty)
          'description': description,
        'color': ?color,
        if (managerUserIds.isNotEmpty) 'managerUserIds': managerUserIds,
      });
      final unit = response.success ? _parseOne(response.data) : null;
      if (unit != null) {
        return ApiResponse.success(data: unit, statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar unidade',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [UNITS] create: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `PUT /units/:id` — edita nome/descrição/cor/ativação.
  Future<ApiResponse<OrgUnit>> update(
    String id, {
    String? name,
    String? description,
    String? color,
    bool? isActive,
  }) async {
    try {
      final response = await _api.put<dynamic>(_unitById(id), body: {
        'name': ?name,
        'description': ?description,
        'color': ?color,
        'isActive': ?isActive,
      });
      final unit = response.success ? _parseOne(response.data) : null;
      if (unit != null) {
        return ApiResponse.success(data: unit, statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar unidade',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [UNITS] update: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `DELETE /units/:id` — desativa/exclui (bloqueia com equipes ativas).
  Future<ApiResponse<bool>> remove(String id) async {
    try {
      final response = await _api.delete<dynamic>(_unitById(id));
      if (response.success) {
        return ApiResponse.success(data: true, statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao excluir unidade',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [UNITS] remove: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `PUT /units/:id/managers` — substitui a lista de gestores.
  Future<ApiResponse<OrgUnit>> setManagers(
    String id,
    List<String> userIds,
  ) async {
    try {
      final response = await _api.put<dynamic>(
        _unitManagers(id),
        body: {'userIds': userIds},
      );
      final unit = response.success ? _parseOne(response.data) : null;
      if (unit != null) {
        return ApiResponse.success(data: unit, statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao definir gestores',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [UNITS] setManagers: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /users/company-members` — todos os membros da empresa (percorre as
  /// páginas; o backend limita a 100 por pedido — paridade `getAllMembers`).
  Future<ApiResponse<List<CompanyMember>>> getAllMembers() async {
    try {
      final merged = <CompanyMember>[];
      var page = 1;
      var totalPages = 1;
      while (page <= totalPages && page <= 10) {
        final response = await _api.get<Map<String, dynamic>>(
          _companyMembers,
          queryParameters: {'page': '$page', 'limit': '100'},
        );
        if (!response.success || response.data == null) {
          if (merged.isNotEmpty) break;
          return ApiResponse.error(
            message: response.message ?? 'Erro ao carregar membros',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
        final body = response.data!;
        final raw = body['data'];
        if (raw is List) {
          merged.addAll(raw.whereType<Map>().map(
              (e) => CompanyMember.fromJson(Map<String, dynamic>.from(e))));
        }
        final tp = body['totalPages'];
        totalPages = tp is num ? tp.toInt() : 1;
        page++;
      }
      return ApiResponse.success(data: merged, statusCode: 200);
    } catch (e) {
      debugPrint('❌ [UNITS] getAllMembers: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}
