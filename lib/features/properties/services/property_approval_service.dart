import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/services/property_service.dart';
import '../models/property_activity_models.dart';
import '../models/property_change_request.dart';

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

/// Retorno de `POST /properties/:id/owner-authorization/send`.
/// `signatureUrl` só vem quando o envio foi "apenas link"
/// (`enviarPorEmail: false`) ou quando o proprietário não tem e-mail.
class OwnerAuthSendResult {
  final String? message;
  final String? signatureUrl;

  const OwnerAuthSendResult({this.message, this.signatureUrl});

  bool get hasLink => (signatureUrl ?? '').isNotEmpty;
}

/// Estado de um job de exportação das filas de aprovação
/// (`GET /properties/approval-export-jobs/:jobId`).
///
/// A exportação é assíncrona: cria-se o job, consulta-se o status até sair de
/// `pending`/`processing`, e só então o CSV é baixado. Os quatro estados são
/// os do `PropertyApprovalExportQueueService` do backend.
class ApprovalExportJob {
  final String jobId;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;
  final int totalRows;
  final String? error;
  final String? fileName;

  const ApprovalExportJob({
    required this.jobId,
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
    this.totalRows = 0,
    this.error,
    this.fileName,
  });

  bool get isPending => status == 'pending';
  bool get isProcessing => status == 'processing';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';

  /// Ainda vale consultar de novo — quem faz polling para aqui quando vira
  /// `false` (concluído ou falhou).
  bool get isRunning => isPending || isProcessing;

  static DateTime? _date(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString())?.toLocal();
  }

  factory ApprovalExportJob.fromJson(Map<String, dynamic> json) {
    return ApprovalExportJob(
      jobId: json['jobId']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      createdAt: _date(json['createdAt']),
      updatedAt: _date(json['updatedAt']),
      completedAt: _date(json['completedAt']),
      totalRows: int.tryParse(json['totalRows']?.toString() ?? '') ?? 0,
      error: json['error']?.toString(),
      fileName: json['fileName']?.toString(),
    );
  }
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

  // ─── Conversa de aprovação (chat aprovador ↔ responsável) ─────────────

  /// `GET /properties/:id/approval-thread` — mensagens da conversa de
  /// aprovação (evento `approval_thread_message` do histórico), ordenadas da
  /// mais antiga para a mais recente. Opcional: filtrar por fila via
  /// `?context=availability|publication`.
  ///
  /// Autorização é server-side (`canParticipateInApprovalThread`): gestão
  /// (master/admin/manager), aprovadores (matriz ou permissão), responsável,
  /// responsáveis adicionais e captadores. Quem está fora leva **403** — o
  /// caller usa `statusCode == 403` para esconder a seção inteira (paridade
  /// com o `PropertyApprovalCommunicationPanel` do web, que retorna `null`).
  ///
  /// Efeito colateral (igual ao web): o backend marca a conversa como vista
  /// para o usuário atual ao listar.
  Future<ApiResponse<List<PropertyHistoryEntry>>> getApprovalThread(
    String propertyId, {
    ApprovalType? context,
  }) async {
    try {
      final response = await _api.get<dynamic>(
        '/properties/$propertyId/approval-thread',
        queryParameters:
            context != null ? {'context': context.value} : null,
      );
      if (response.success) {
        final raw = response.data;
        List<dynamic> list;
        if (raw is List) {
          list = raw;
        } else if (raw is Map && raw['data'] is List) {
          list = raw['data'] as List;
        } else {
          list = const [];
        }
        final parsed = list
            .whereType<Map>()
            .map((e) =>
                PropertyHistoryEntry.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        return ApiResponse.success(
          data: parsed,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar a conversa',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [APPROVAL] approval-thread: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /properties/:id/approval-thread` — envia mensagem na conversa.
  ///
  /// Body real do backend (`AddApprovalThreadBodyDto`):
  /// `{ message, approvalContext: 'availability' | 'publication' }` — a fila
  /// é obrigatória. Backend valida texto não-vazio e máx. 4000 caracteres, e
  /// devolve a entrada criada já com o `user` populado.
  Future<ApiResponse<PropertyHistoryEntry>> postApprovalThreadMessage(
    String propertyId, {
    required String message,
    required ApprovalType queue,
  }) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        '/properties/$propertyId/approval-thread',
        body: {
          'message': message,
          'approvalContext': queue.value,
        },
      );
      if (response.success && response.data != null) {
        final raw = response.data!;
        final map = raw['id'] != null
            ? raw
            : (raw['data'] is Map<String, dynamic>
                ? raw['data'] as Map<String, dynamic>
                : raw);
        return ApiResponse.success(
          data: PropertyHistoryEntry.fromJson(map),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao enviar mensagem',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [APPROVAL] approval-thread send: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  // ─── Notificar responsáveis sobre contato do proprietário ─────────────

  /// `POST /properties/:id/notify-responsibles-owner-contact` — avisa os
  /// responsáveis/captadores que o proprietário precisa ser contatado. Mesmo
  /// cooldown de 1h do lembrete (429 com `retryAfterSeconds`).
  Future<ApiResponse<Map<String, dynamic>>> notifyResponsiblesOwnerContact(
    String propertyId, {
    required ApprovalType approvalType,
  }) {
    return _postMap(
      endpoint: '/properties/$propertyId/notify-responsibles-owner-contact',
      body: {'approvalType': approvalType.value},
      logTag: 'notify-responsibles-owner-contact',
      fallbackError: 'Erro ao notificar responsáveis',
    );
  }

  // ─── Autorização do proprietário ──────────────────────────────────────

  /// `POST /properties/:id/owner-authorization/ignore-signature` — dispensa a
  /// assinatura digital pendente. `reason` é **obrigatório** no backend
  /// (`IgnoreOwnerAuthorizationSignatureBodyDto`).
  Future<ApiResponse<Map<String, dynamic>>> ignoreOwnerAuthorizationSignature(
    String propertyId, {
    required String reason,
  }) {
    return _postMap(
      endpoint: '/properties/$propertyId/owner-authorization/ignore-signature',
      body: {'reason': reason},
      logTag: 'owner-auth ignore-signature',
      fallbackError: 'Erro ao dispensar a assinatura',
    );
  }

  /// `POST /properties/:id/owner-authorization/invalidate` — apaga a
  /// assinatura e os votos, devolvendo o imóvel para "aguardando proprietário".
  Future<ApiResponse<Map<String, dynamic>>> invalidateOwnerAuthorization(
    String propertyId,
  ) {
    return _postMap(
      endpoint: '/properties/$propertyId/owner-authorization/invalidate',
      body: const <String, dynamic>{},
      logTag: 'owner-auth invalidate',
      fallbackError: 'Erro ao invalidar a assinatura',
    );
  }

  /// `POST /properties/:id/owner-authorization/reenviar-email` — reenvia o
  /// link de assinatura para o e-mail do proprietário (Autentique).
  Future<ApiResponse<Map<String, dynamic>>> resendOwnerAuthorizationEmail(
    String propertyId,
  ) {
    return _postMap(
      endpoint: '/properties/$propertyId/owner-authorization/reenviar-email',
      body: const <String, dynamic>{},
      logTag: 'owner-auth reenviar-email',
      fallbackError: 'Erro ao reenviar o e-mail',
    );
  }

  /// `POST /properties/:id/owner-authorization/approve-physical` — valida o
  /// anexo da assinatura física (exige `property:approve_availability`).
  Future<ApiResponse<Map<String, dynamic>>> approveOwnerAuthorizationPhysical(
    String propertyId,
  ) {
    return _postMap(
      endpoint: '/properties/$propertyId/owner-authorization/approve-physical',
      body: const <String, dynamic>{},
      logTag: 'owner-auth approve-physical',
      fallbackError: 'Erro ao validar o anexo',
    );
  }

  /// `POST /properties/:id/owner-authorization/reject-physical` — recusa o
  /// anexo. `reason` é opcional no backend.
  Future<ApiResponse<Map<String, dynamic>>> rejectOwnerAuthorizationPhysical(
    String propertyId, {
    String? reason,
  }) {
    final r = reason?.trim();
    return _postMap(
      endpoint: '/properties/$propertyId/owner-authorization/reject-physical',
      body: r == null || r.isEmpty ? const <String, dynamic>{} : {'reason': r},
      logTag: 'owner-auth reject-physical',
      fallbackError: 'Erro ao recusar o anexo',
    );
  }

  /// `GET /properties/:id/owner-authorization/physical-preview` — URL
  /// temporária para abrir o anexo assinado em papel.
  Future<ApiResponse<String>> getOwnerAuthorizationPhysicalPreviewUrl(
    String propertyId,
  ) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(
        '/properties/$propertyId/owner-authorization/physical-preview',
      );
      if (response.success && response.data != null) {
        final raw = response.data!;
        final body = raw['data'] is Map<String, dynamic>
            ? raw['data'] as Map<String, dynamic>
            : raw;
        final url = body['url']?.toString() ?? '';
        if (url.isEmpty) {
          return ApiResponse.error(
            message: 'O anexo não está disponível para visualização.',
            statusCode: response.statusCode,
          );
        }
        return ApiResponse.success(data: url, statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao abrir o anexo',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [APPROVAL] owner-auth physical-preview: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /properties/:id/owner-authorization/send-history` — quem enviou,
  /// para qual e-mail e quando; mais a assinatura, se já houver.
  Future<ApiResponse<OwnerAuthSendHistory>> getOwnerAuthorizationSendHistory(
    String propertyId,
  ) async {
    try {
      final response = await _api.get<dynamic>(
        '/properties/$propertyId/owner-authorization/send-history',
      );
      if (response.success) {
        final raw = response.data;
        final body = raw is Map && raw['data'] != null ? raw['data'] : raw;
        return ApiResponse.success(
          data: OwnerAuthSendHistory.fromAny(body),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar o histórico de envios',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [APPROVAL] owner-auth send-history: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /properties/:id/owner-authorization/send` — gera o PDF do template
  /// e envia ao Autentique. Devolve `signatureUrl` quando o envio foi só link
  /// (`enviarPorEmail: false`).
  Future<ApiResponse<OwnerAuthSendResult>> sendOwnerAuthorization(
    String propertyId, {
    required String signerName,
    String? signerEmail,
    required bool sendByEmail,
    required bool hasExclusivity,
    int? exclusivityDays,
    required bool exclusivityIndeterminate,
    required bool acceptsPlaca,
    required String operationType,
    String logoSource = 'intellisys',
  }) async {
    final body = <String, dynamic>{
      'signerName': signerName,
      'enviarPorEmail': sendByEmail,
      'hasExclusivity': hasExclusivity,
      'exclusivityDays':
          hasExclusivity && !exclusivityIndeterminate ? exclusivityDays : null,
      'exclusivityIndeterminate': exclusivityIndeterminate,
      'acceptsPlaca': acceptsPlaca,
      'operationType': operationType,
      'logoSource': logoSource,
    };
    final email = signerEmail?.trim();
    if (email != null && email.isNotEmpty) body['signerEmail'] = email;

    final res = await _postMap(
      endpoint: '/properties/$propertyId/owner-authorization/send',
      body: body,
      logTag: 'owner-auth send',
      fallbackError: 'Erro ao enviar para assinatura',
    );
    if (!res.success) {
      return ApiResponse.error(
        message: res.message ?? 'Erro ao enviar para assinatura',
        statusCode: res.statusCode,
        data: res.data,
      );
    }
    final map = res.data ?? const <String, dynamic>{};
    return ApiResponse.success(
      data: OwnerAuthSendResult(
        message: map['message']?.toString(),
        signatureUrl: map['signatureUrl']?.toString(),
      ),
      statusCode: res.statusCode,
    );
  }

  /// `POST /properties/:id/owner-authorization/upload-physical` (multipart) —
  /// anexa o documento assinado em papel para validação do aprovador.
  Future<ApiResponse<Map<String, dynamic>>> uploadOwnerAuthorizationPhysical(
    String propertyId,
    File file,
  ) {
    return _postMultipart(
      endpoint: '/properties/$propertyId/owner-authorization/upload-physical',
      file: file,
      logTag: 'owner-auth upload-physical',
      fallbackError: 'Erro ao enviar o anexo',
    );
  }

  /// `POST /properties/:id/owner-authorization/send-document` (multipart) —
  /// envia um PDF próprio da empresa ao Autentique no lugar do template.
  Future<ApiResponse<Map<String, dynamic>>> sendOwnerAuthorizationWithDocument(
    String propertyId,
    File file, {
    String? signerEmail,
    String? signerName,
    bool sendByEmail = true,
  }) {
    final fields = <String, String>{'enviarPorEmail': '$sendByEmail'};
    final email = signerEmail?.trim();
    final name = signerName?.trim();
    if (email != null && email.isNotEmpty) fields['signerEmail'] = email;
    if (name != null && name.isNotEmpty) fields['signerName'] = name;
    return _postMultipart(
      endpoint: '/properties/$propertyId/owner-authorization/send-document',
      file: file,
      fields: fields,
      logTag: 'owner-auth send-document',
      fallbackError: 'Erro ao enviar o documento',
    );
  }

  // ─── Votação (multi-aprovadores) ──────────────────────────────────────

  /// `GET /properties/:id/voting-status?type=` — quórum, votos e pendentes.
  Future<ApiResponse<ApprovalVotingStatus>> getVotingStatus(
    String propertyId, {
    required ApprovalType type,
  }) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(
        '/properties/$propertyId/voting-status',
        queryParameters: {'type': type.value},
      );
      if (response.success && response.data != null) {
        final raw = response.data!;
        final body = raw['approvers'] == null && raw['data'] is Map
            ? Map<String, dynamic>.from(raw['data'] as Map)
            : raw;
        return ApiResponse.success(
          data: ApprovalVotingStatus.fromJson(body),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar o status de votação',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [APPROVAL] voting-status: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /properties/:id/vote/:voteType` — registra o voto do aprovador.
  /// `decision` aceita `approved` | `rejected` (`ApprovalVoteDecision`).
  Future<ApiResponse<Map<String, dynamic>>> castVote(
    String propertyId, {
    required ApprovalType type,
    required bool approved,
    String? comment,
  }) {
    final body = <String, dynamic>{
      'decision': approved ? 'approved' : 'rejected',
    };
    final c = comment?.trim();
    if (c != null && c.isNotEmpty) body['comment'] = c;
    return _postMap(
      endpoint: '/properties/$propertyId/vote/${type.value}',
      body: body,
      logTag: 'cast-vote',
      fallbackError: 'Erro ao registrar o voto',
    );
  }

  // ─── Solicitações de alteração (campos protegidos) ────────────────────

  /// `GET /property-change-requests` — revisores veem todas da empresa; os
  /// demais só as próprias (escopo aplicado no backend). `canReview` do
  /// envelope é a fonte da verdade para exibir aprovar/recusar.
  Future<ApiResponse<PropertyChangeRequestList>> listChangeRequests({
    PropertyChangeRequestStatus? status,
    bool mine = false,
    String? propertyId,
  }) async {
    try {
      final params = <String, String>{};
      if (status != null) params['status'] = status.value;
      if (mine) params['mine'] = 'true';
      if (propertyId != null && propertyId.isNotEmpty) {
        params['propertyId'] = propertyId;
      }
      final response = await _api.get<Map<String, dynamic>>(
        '/property-change-requests',
        queryParameters: params,
      );
      if (response.success && response.data != null) {
        final raw = response.data!;
        final body = raw['items'] == null && raw['data'] is Map
            ? Map<String, dynamic>.from(raw['data'] as Map)
            : raw;
        return ApiResponse.success(
          data: PropertyChangeRequestList.fromJson(body),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar solicitações',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [APPROVAL] change-requests: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /property-change-requests/pending-count` — badge da aba.
  Future<ApiResponse<int>> getChangeRequestsPendingCount() async {
    try {
      final response = await _api.get<Map<String, dynamic>>(
        '/property-change-requests/pending-count',
      );
      if (response.success && response.data != null) {
        final raw = response.data!;
        final body = raw['count'] == null && raw['data'] is Map
            ? Map<String, dynamic>.from(raw['data'] as Map)
            : raw;
        final v = body['count'];
        final count = v is int
            ? v
            : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
        return ApiResponse.success(
          data: count,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao contar solicitações',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [APPROVAL] change-requests count: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /property-change-requests/:id/approve` — aplica o diff ao imóvel.
  Future<ApiResponse<Map<String, dynamic>>> approveChangeRequest(String id) {
    return _postMap(
      endpoint: '/property-change-requests/$id/approve',
      body: const <String, dynamic>{},
      logTag: 'change-request approve',
      fallbackError: 'Erro ao aprovar a solicitação',
    );
  }

  /// `POST /property-change-requests/:id/reject` — `reason` obrigatório.
  Future<ApiResponse<Map<String, dynamic>>> rejectChangeRequest(
    String id, {
    required String reason,
  }) {
    return _postMap(
      endpoint: '/property-change-requests/$id/reject',
      body: {'reason': reason},
      logTag: 'change-request reject',
      fallbackError: 'Erro ao recusar a solicitação',
    );
  }

  // ─── Exportação das filas (job assíncrono) ─────────────────────────────

  /// `POST /properties/approval-export-jobs` — enfileira a exportação em CSV
  /// da aba pedida e devolve o `jobId`. O backend processa em segundo plano
  /// (mesmo fluxo do web: cria → consulta status → baixa).
  ///
  /// [tab] aceita `mine`, `owner_authorization`, `availability`,
  /// `publication`, `rejected` e `all` — qualquer outro valor o backend
  /// normaliza para `mine`.
  Future<ApiResponse<String>> createApprovalExportJob({
    required String tab,
    ApprovalListFilters filters = ApprovalListFilters.empty,
    bool includeRejectedAvailability = true,
    bool includeRejectedPublication = true,
  }) async {
    final body = <String, dynamic>{
      'tab': tab,
      ...filters.toQueryParams(),
      if (tab == 'rejected' || tab == 'all') ...{
        'includeRejectedAvailability': includeRejectedAvailability,
        'includeRejectedPublication': includeRejectedPublication,
      },
    };
    final res = await _postMap(
      endpoint: '/properties/approval-export-jobs',
      body: body,
      logTag: 'approval-export-job create',
      fallbackError: 'Erro ao enfileirar a exportação',
    );
    if (!res.success) {
      return ApiResponse.error(
        message: res.message ?? 'Erro ao enfileirar a exportação',
        statusCode: res.statusCode,
        data: res.error,
      );
    }
    final raw = res.data ?? const <String, dynamic>{};
    final body2 = raw['data'] is Map<String, dynamic>
        ? raw['data'] as Map<String, dynamic>
        : raw;
    final jobId = body2['jobId']?.toString() ?? '';
    if (jobId.isEmpty) {
      return ApiResponse.error(
        message: 'A exportação não retornou um identificador de job.',
        statusCode: res.statusCode,
      );
    }
    return ApiResponse.success(data: jobId, statusCode: res.statusCode);
  }

  /// `GET /properties/approval-export-jobs/:jobId` — status do job.
  Future<ApiResponse<ApprovalExportJob>> getApprovalExportJobStatus(
    String jobId,
  ) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(
        '/properties/approval-export-jobs/$jobId',
      );
      if (response.success && response.data != null) {
        final raw = response.data!;
        final body = raw['data'] is Map<String, dynamic>
            ? raw['data'] as Map<String, dynamic>
            : raw;
        return ApiResponse.success(
          data: ApprovalExportJob.fromJson(body),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao consultar a exportação',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [APPROVAL] approval-export-job status: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /properties/approval-export-jobs/:jobId/download` — bytes do CSV.
  /// O `ApiService` só fala JSON, então baixamos com `http` cru reusando os
  /// headers da sessão (Authorization + X-Company-ID).
  Future<ApiResponse<List<int>>> downloadApprovalExportJob(
    String jobId,
  ) async {
    const path = '/properties/approval-export-jobs';
    try {
      final uri = Uri.parse(
        '${ApiConstants.baseApiUrl}$path/$jobId/download',
      );
      final headers = await _api.buildOutboundHeaders(endpoint: path);
      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 90));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ApiResponse.success(
          data: response.bodyBytes.toList(),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: _messageFromBody(
          response.body,
          'Não foi possível baixar o arquivo da exportação',
        ),
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [APPROVAL] approval-export-job download: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /properties/:id/owner-authorization/preview` — gera o PDF da
  /// autorização com as opções escolhidas **sem enviar** ao proprietário.
  /// Resposta é binária (application/pdf), por isso usa `http` cru.
  Future<ApiResponse<List<int>>> previewOwnerAuthorization(
    String propertyId, {
    required bool hasExclusivity,
    required bool exclusivityIndeterminate,
    int? exclusivityDays,
    required bool acceptsPlaca,
    required String operationType,
    required String logoSource,
  }) async {
    final endpoint = '/properties/$propertyId/owner-authorization/preview';
    try {
      final uri = Uri.parse('${ApiConstants.baseApiUrl}$endpoint');
      final headers = await _api.buildOutboundHeaders(endpoint: endpoint);
      final response = await http
          .post(
            uri,
            headers: headers,
            body: jsonEncode({
              'hasExclusivity': hasExclusivity,
              'exclusivityIndeterminate': exclusivityIndeterminate,
              'exclusivityDays':
                  hasExclusivity && !exclusivityIndeterminate
                      ? exclusivityDays
                      : null,
              'acceptsPlaca': acceptsPlaca,
              'operationType': operationType,
              'logoSource': logoSource,
            }),
          )
          .timeout(const Duration(seconds: 90));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ApiResponse.success(
          data: response.bodyBytes.toList(),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: _messageFromBody(
          response.body,
          'Não foi possível gerar a pré-visualização',
        ),
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [APPROVAL] owner-auth preview: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────────────

  /// Extrai `message` de um corpo JSON de erro (aceita string ou lista).
  String _messageFromBody(String body, String fallback) {
    if (body.isEmpty) return fallback;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final raw = decoded['message'];
        if (raw is List && raw.isNotEmpty) return raw.first.toString();
        if (raw != null) return raw.toString();
      }
    } catch (_) {
      // Corpo não-JSON (ex.: HTML de proxy) — usa o fallback.
    }
    return fallback;
  }

  /// POST que devolve um envelope livre (`{ message: ... }` na maioria das
  /// rotas de ação). Mantém o `statusCode` para o caller tratar 429/403.
  Future<ApiResponse<Map<String, dynamic>>> _postMap({
    required String endpoint,
    required Map<String, dynamic> body,
    required String logTag,
    required String fallbackError,
  }) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        endpoint,
        body: body,
      );
      if (response.success) {
        return ApiResponse.success(
          data: response.data ?? const <String, dynamic>{},
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? fallbackError,
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

  /// Upload multipart (campo `file`) — o `ApiService` só fala JSON, então
  /// montamos o `MultipartRequest` reaproveitando `buildOutboundHeaders`
  /// (Authorization + X-Company-ID) sem `Content-Type` (o boundary é do http).
  Future<ApiResponse<Map<String, dynamic>>> _postMultipart({
    required String endpoint,
    required File file,
    Map<String, String>? fields,
    required String logTag,
    required String fallbackError,
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseApiUrl}$endpoint');
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(
        await _api.buildOutboundHeaders(
          endpoint: endpoint,
          excludeContentType: true,
        ),
      );
      final length = await file.length();
      request.files.add(
        http.MultipartFile(
          'file',
          http.ByteStream(file.openRead()),
          length,
          filename: file.path.split(RegExp(r'[/\\]')).last,
        ),
      );
      if (fields != null) request.fields.addAll(fields);

      final streamed =
          await request.send().timeout(const Duration(seconds: 120));
      final response = await http.Response.fromStream(streamed);
      Map<String, dynamic> parsed = const {};
      if (response.body.isNotEmpty) {
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map) parsed = Map<String, dynamic>.from(decoded);
        } catch (_) {
          // Corpo não-JSON — segue com o mapa vazio.
        }
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ApiResponse.success(
          data: parsed,
          statusCode: response.statusCode,
        );
      }
      final raw = parsed['message'];
      final message = raw is List && raw.isNotEmpty
          ? raw.first.toString()
          : (raw?.toString() ?? fallbackError);
      return ApiResponse.error(
        message: message,
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [APPROVAL] $logTag: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

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
