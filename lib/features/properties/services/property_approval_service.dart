import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../../../shared/services/property_service.dart';

/// Filtros textuais aceitos por todas as listagens da fila.
///
/// Regra do backend (e do web `imobx-front`): se [search] estiver preenchido,
/// os campos granulares são **ignorados** e o backend faz um OR amplo em
/// código, título, proprietário e responsáveis.
class ApprovalListFilters {
  final String? search;
  final String? responsibleName;
  final String? propertyCode;
  final String? propertyTitle;
  final String? ownerName;
  final String? teamId;
  final String? responsibleUserId;

  const ApprovalListFilters({
    this.search,
    this.responsibleName,
    this.propertyCode,
    this.propertyTitle,
    this.ownerName,
    this.teamId,
    this.responsibleUserId,
  });

  static const ApprovalListFilters empty = ApprovalListFilters();

  bool get hasSearch => (search ?? '').trim().isNotEmpty;

  Map<String, String> toQueryParams() {
    final out = <String, String>{};
    final s = search?.trim();
    if (s != null && s.isNotEmpty) {
      // Paridade com `mergePendingTextQuery` do web: se search global tem
      // valor, ignora os granulares e manda só `search`.
      out['search'] = s;
    } else {
      void putIf(String key, String? value) {
        final v = value?.trim();
        if (v != null && v.isNotEmpty) out[key] = v;
      }

      putIf('responsibleName', responsibleName);
      putIf('propertyCode', propertyCode);
      putIf('propertyTitle', propertyTitle);
      putIf('ownerName', ownerName);
    }
    if (teamId != null && teamId!.isNotEmpty) out['teamId'] = teamId!;
    if (responsibleUserId != null && responsibleUserId!.isNotEmpty) {
      out['responsibleUserId'] = responsibleUserId!;
    }
    return out;
  }
}

/// Resposta de `GET /properties/my-pending`.
class MyPendingResponse {
  final List<Property> pendingAvailability;
  final List<Property> pendingOwnerAuthorization;
  final List<Property> pendingPublication;

  const MyPendingResponse({
    required this.pendingAvailability,
    required this.pendingOwnerAuthorization,
    required this.pendingPublication,
  });

  static const MyPendingResponse empty = MyPendingResponse(
    pendingAvailability: [],
    pendingOwnerAuthorization: [],
    pendingPublication: [],
  );

  int get total =>
      pendingAvailability.length +
      pendingOwnerAuthorization.length +
      pendingPublication.length;

  factory MyPendingResponse.fromJson(Map<String, dynamic> json) {
    List<Property> parseList(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => Property.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    return MyPendingResponse(
      pendingAvailability: parseList(json['pendingAvailability']),
      pendingOwnerAuthorization: parseList(json['pendingOwnerAuthorization']),
      pendingPublication: parseList(json['pendingPublication']),
    );
  }
}

/// Resposta paginada de `GET /properties/rejected-availability` e
/// `GET /properties/rejected-publication`.
class RejectedListResponse {
  final List<Property> data;
  final int total;

  const RejectedListResponse({required this.data, required this.total});

  static const RejectedListResponse empty =
      RejectedListResponse(data: [], total: 0);

  factory RejectedListResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['data'];
    final list = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => Property.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <Property>[];
    final total = json['total'];
    return RejectedListResponse(
      data: list,
      total: total is int
          ? total
          : (total is num
              ? total.toInt()
              : int.tryParse(total?.toString() ?? '') ?? list.length),
    );
  }
}

/// Resposta de `GET /properties/rejected-counts`.
class RejectedCounts {
  final int availabilityRejected;
  final int publicationRejected;

  const RejectedCounts({
    required this.availabilityRejected,
    required this.publicationRejected,
  });

  static const RejectedCounts zero =
      RejectedCounts(availabilityRejected: 0, publicationRejected: 0);

  int get total => availabilityRejected + publicationRejected;

  factory RejectedCounts.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    return RejectedCounts(
      availabilityRejected: asInt(json['availabilityRejected']),
      publicationRejected: asInt(json['publicationRejected']),
    );
  }
}

/// Tipo de fila de aprovação — usado por endpoints como
/// `remind-approval-approvers`.
enum ApprovalType {
  availability('availability'),
  publication('publication');

  final String value;
  const ApprovalType(this.value);
}

/// Serviço dedicado às filas de aprovação de imóveis (paridade com
/// `propertyApi.*` do `imobx-front`). Reutiliza o [Property] (e seu
/// `fromJson`) do `property_service.dart` do shared.
class PropertyApprovalService {
  PropertyApprovalService._();

  static final PropertyApprovalService instance = PropertyApprovalService._();
  final ApiService _api = ApiService.instance;

  // ─── Listagens de pendentes ─────────────────────────────────────────────

  /// `GET /properties/my-pending` — três listas: disponibilidade, autorização
  /// do proprietário e publicação no site, todas escopadas ao usuário logado.
  Future<ApiResponse<MyPendingResponse>> getMyPending({
    ApprovalListFilters filters = ApprovalListFilters.empty,
  }) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(
        '/properties/my-pending',
        queryParameters: filters.toQueryParams(),
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: MyPendingResponse.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message:
            response.message ?? 'Erro ao carregar minhas pendências',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [APPROVAL] my-pending: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /properties/pending-approval` — fila de **disponibilidade**.
  ///
  /// Default do backend: `sortBy=updatedAt`, `sortOrder=asc`. Sem paginação
  /// (o backend devolve a lista inteira).
  Future<ApiResponse<List<Property>>> getPendingAvailability({
    ApprovalListFilters filters = ApprovalListFilters.empty,
    String sortBy = 'updatedAt',
    String sortOrder = 'asc',
  }) async {
    return _getPendingList(
      endpoint: '/properties/pending-approval',
      filters: filters,
      sortBy: sortBy,
      sortOrder: sortOrder,
    );
  }

  /// `GET /properties/pending-publication` — fila de **publicação no site**.
  Future<ApiResponse<List<Property>>> getPendingPublication({
    ApprovalListFilters filters = ApprovalListFilters.empty,
    String sortBy = 'updatedAt',
    String sortOrder = 'asc',
  }) async {
    return _getPendingList(
      endpoint: '/properties/pending-publication',
      filters: filters,
      sortBy: sortBy,
      sortOrder: sortOrder,
    );
  }

  /// `GET /properties/pending-owner-authorization` — fila de **assinatura do
  /// proprietário**. Aceita `scope=all|mine`; default `mine` quando o usuário
  /// não tem visão da empresa inteira (regra é aplicada server-side).
  Future<ApiResponse<List<Property>>> getPendingOwnerAuthorization({
    ApprovalListFilters filters = ApprovalListFilters.empty,
    String? scope,
  }) async {
    final params = filters.toQueryParams();
    if (scope != null && scope.isNotEmpty) params['scope'] = scope;
    return _getRawList(
      endpoint: '/properties/pending-owner-authorization',
      queryParams: params,
    );
  }

  Future<ApiResponse<List<Property>>> _getPendingList({
    required String endpoint,
    required ApprovalListFilters filters,
    required String sortBy,
    required String sortOrder,
  }) async {
    final params = <String, String>{
      'sortBy': sortBy,
      'sortOrder': sortOrder,
      ...filters.toQueryParams(),
    };
    return _getRawList(endpoint: endpoint, queryParams: params);
  }

  Future<ApiResponse<List<Property>>> _getRawList({
    required String endpoint,
    required Map<String, String> queryParams,
  }) async {
    try {
      // Para listagens que devolvem array puro, pedimos `dynamic` e tratamos
      // os dois envelopes possíveis (`[ ... ]` ou `{ data: [ ... ] }`).
      final response = await _api.get<dynamic>(
        endpoint,
        queryParameters: queryParams,
      );
      if (response.success) {
        final raw = response.data;
        List<dynamic> list;
        if (raw is List) {
          list = raw;
        } else if (raw is Map<String, dynamic> && raw['data'] is List) {
          list = raw['data'] as List;
        } else if (raw is Map && raw['data'] is List) {
          list = raw['data'] as List;
        } else {
          list = const [];
        }
        final parsed = list
            .whereType<Map>()
            .map((e) => Property.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        return ApiResponse.success(
          data: parsed,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar fila',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [APPROVAL] $endpoint: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  // ─── Listagens de recusados (paginadas) ────────────────────────────────

  /// `GET /properties/rejected-availability`.
  Future<ApiResponse<RejectedListResponse>> getRejectedAvailability({
    ApprovalListFilters filters = ApprovalListFilters.empty,
    int page = 1,
    int limit = 10,
    String sortBy = 'updatedAt',
    String sortOrder = 'desc',
  }) async {
    return _getRejectedList(
      endpoint: '/properties/rejected-availability',
      filters: filters,
      page: page,
      limit: limit,
      sortBy: sortBy,
      sortOrder: sortOrder,
    );
  }

  /// `GET /properties/rejected-publication`.
  Future<ApiResponse<RejectedListResponse>> getRejectedPublication({
    ApprovalListFilters filters = ApprovalListFilters.empty,
    int page = 1,
    int limit = 10,
    String sortBy = 'updatedAt',
    String sortOrder = 'desc',
  }) async {
    return _getRejectedList(
      endpoint: '/properties/rejected-publication',
      filters: filters,
      page: page,
      limit: limit,
      sortBy: sortBy,
      sortOrder: sortOrder,
    );
  }

  Future<ApiResponse<RejectedListResponse>> _getRejectedList({
    required String endpoint,
    required ApprovalListFilters filters,
    required int page,
    required int limit,
    required String sortBy,
    required String sortOrder,
  }) async {
    try {
      final params = <String, String>{
        'page': '$page',
        'limit': '$limit',
        'sortBy': sortBy,
        'sortOrder': sortOrder,
        ...filters.toQueryParams(),
      };
      final response = await _api.get<Map<String, dynamic>>(
        endpoint,
        queryParameters: params,
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: RejectedListResponse.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar recusados',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [APPROVAL] $endpoint: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /properties/rejected-counts` — totais de recusados por fila.
  Future<ApiResponse<RejectedCounts>> getRejectedCounts({
    ApprovalListFilters filters = ApprovalListFilters.empty,
  }) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(
        '/properties/rejected-counts',
        queryParameters: filters.toQueryParams(),
      );
      if (response.success && response.data != null) {
        final raw = response.data!;
        final body = raw['data'] is Map<String, dynamic>
            ? raw['data'] as Map<String, dynamic>
            : raw;
        return ApiResponse.success(
          data: RejectedCounts.fromJson(body),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message:
            response.message ?? 'Erro ao carregar contagem de recusados',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [APPROVAL] rejected-counts: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  // ─── Ações de aprovação / recusa ───────────────────────────────────────

  /// `POST /properties/:id/approve-availability`.
  Future<ApiResponse<Property>> approveAvailability(
    String propertyId, {
    bool? applyWatermark,
  }) async {
    return _postProperty(
      endpoint: '/properties/$propertyId/approve-availability',
      body: applyWatermark != null
          ? {'applyWatermark': applyWatermark}
          : <String, dynamic>{},
      logTag: 'approve-availability',
    );
  }

  /// `POST /properties/:id/reject-availability` — `reason` obrigatório.
  Future<ApiResponse<Property>> rejectAvailability(
    String propertyId, {
    required String reason,
  }) async {
    return _postProperty(
      endpoint: '/properties/$propertyId/reject-availability',
      body: {'reason': reason},
      logTag: 'reject-availability',
    );
  }

  /// `POST /properties/:id/approve-publication`.
  Future<ApiResponse<Property>> approvePublication(
    String propertyId, {
    bool? applyWatermark,
  }) async {
    return _postProperty(
      endpoint: '/properties/$propertyId/approve-publication',
      body: applyWatermark != null
          ? {'applyWatermark': applyWatermark}
          : <String, dynamic>{},
      logTag: 'approve-publication',
    );
  }

  /// `POST /properties/:id/reject-publication` — `reason` obrigatório.
  Future<ApiResponse<Property>> rejectPublication(
    String propertyId, {
    required String reason,
  }) async {
    return _postProperty(
      endpoint: '/properties/$propertyId/reject-publication',
      body: {'reason': reason},
      logTag: 'reject-publication',
    );
  }

  // ─── Reabertura / reenvio ──────────────────────────────────────────────

  /// `POST /properties/:id/request-availability-review` (aprovador reabre).
  Future<ApiResponse<Property>> requestAvailabilityReview(
    String propertyId,
  ) async {
    return _postProperty(
      endpoint: '/properties/$propertyId/request-availability-review',
      body: const <String, dynamic>{},
      logTag: 'request-availability-review',
    );
  }

  /// `POST /properties/:id/request-site-publication-review`.
  Future<ApiResponse<Property>> requestSitePublicationReview(
    String propertyId,
  ) async {
    return _postProperty(
      endpoint: '/properties/$propertyId/request-site-publication-review',
      body: const <String, dynamic>{},
      logTag: 'request-publication-review',
    );
  }

  /// `POST /properties/:id/responsible/reopen-availability-review` (responsável
  /// pede revisão depois de recusa, sem precisar de permissão de aprovador).
  Future<ApiResponse<Property>> requestAvailabilityReviewAsResponsible(
    String propertyId,
  ) async {
    return _postProperty(
      endpoint:
          '/properties/$propertyId/responsible/reopen-availability-review',
      body: const <String, dynamic>{},
      logTag: 'reopen-availability-review (responsável)',
    );
  }

  /// `POST /properties/:id/responsible/reopen-publication-review`.
  Future<ApiResponse<Property>> requestSitePublicationReviewAsResponsible(
    String propertyId,
  ) async {
    return _postProperty(
      endpoint:
          '/properties/$propertyId/responsible/reopen-publication-review',
      body: const <String, dynamic>{},
      logTag: 'reopen-publication-review (responsável)',
    );
  }

  // ─── Notificar / cobrar aprovadores ────────────────────────────────────

  /// `POST /properties/:id/remind-approval-approvers` — manda lembrete aos
  /// aprovadores. Backend aplica cooldown de 1h e responde 429 com
  /// `retryAfterSeconds` quando ainda dentro do cooldown.
  Future<ApiResponse<Map<String, dynamic>>> remindApprovalApprovers(
    String propertyId, {
    required ApprovalType approvalType,
  }) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        '/properties/$propertyId/remind-approval-approvers',
        body: {'approvalType': approvalType.value},
      );
      if (response.success) {
        return ApiResponse.success(
          data: response.data ?? const {},
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao notificar aprovadores',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [APPROVAL] remind-approvers: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────────────

  Future<ApiResponse<Property>> _postProperty({
    required String endpoint,
    required Map<String, dynamic> body,
    required String logTag,
  }) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        endpoint,
        body: body,
      );
      if (response.success && response.data != null) {
        try {
          final raw = response.data!;
          final map = raw['id'] != null
              ? raw
              : (raw['data'] is Map<String, dynamic>
                  ? raw['data'] as Map<String, dynamic>
                  : raw);
          return ApiResponse.success(
            data: Property.fromJson(map),
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [APPROVAL] parse $logTag: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }
      return ApiResponse.error(
        message: response.message ?? 'Falha em $logTag',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [APPROVAL] $logTag: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}
