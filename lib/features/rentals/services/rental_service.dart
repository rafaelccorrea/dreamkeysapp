import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../models/rental_models.dart';

/// Serviço de Locações — consome o `RentalController` do backend (mesmos
/// endpoints do `rental.service.ts` + `rentalDashboardService.ts` do
/// imobx-front). O `ApiService` cuida de token + `X-Company-ID`.
class RentalService {
  RentalService._();

  static final RentalService instance = RentalService._();
  final ApiService _api = ApiService.instance;

  // Endpoints (privados — a fiação central pode promovê-los a ApiConstants).
  static const String _rentals = '/rental';
  static const String _rentalSettings = '/rental/settings';
  static const String _checkAvailability = '/rental/check-availability';
  static const String _dashboardStats = '/rental/dashboard/stats';
  static String _rentalById(String id) => '/rental/$id';
  static String _rentalStatus(String id) => '/rental/$id/status';
  static String _rentalApprove(String id) => '/rental/$id/approve';
  static String _rentalReject(String id) => '/rental/$id/reject';
  static String _rentalHistory(String id) => '/rental/$id/history';
  static String _rentalComments(String id) => '/rental/$id/comments';
  static String _rentalPayments(String id) => '/rental/$id/payments';
  static String _rentalPaymentsGenerate(String id) =>
      '/rental/$id/payments/generate';
  static String _rentalPayment(String id, String paymentId) =>
      '/rental/$id/payments/$paymentId';

  Map<String, dynamic>? _mapBody(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  ApiResponse<T> _fail<T>(ApiResponse<dynamic> response, String fallback) {
    return ApiResponse.error(
      message: response.message ?? fallback,
      statusCode: response.statusCode,
      data: response.error,
    );
  }

  ApiResponse<T> _exception<T>(String tag, Object e) {
    debugPrint('❌ [RENTAL] $tag: $e');
    return ApiResponse.error(
      message: 'Erro de conexão: $e',
      statusCode: 0,
    );
  }

  /// `GET /rental` — lista paginada com filtros.
  Future<ApiResponse<RentalListResult>> getRentals({
    RentalFilters filters = const RentalFilters(),
  }) async {
    try {
      final response = await _api.get<dynamic>(
        _rentals,
        queryParameters: filters.toQueryParams(),
      );
      if (response.success && response.data != null) {
        final body = _mapBody(response.data);
        final result = body != null
            ? RentalListResult.fromJson(body)
            : RentalListResult.empty;
        return ApiResponse.success(
          data: result,
          statusCode: response.statusCode,
        );
      }
      return _fail(response, 'Erro ao carregar locações');
    } catch (e) {
      return _exception('getRentals', e);
    }
  }

  /// `GET /rental/:id` — detalhe da locação (com property + payments).
  Future<ApiResponse<Rental>> getById(String id) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(_rentalById(id));
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: Rental.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return _fail(response, 'Locação não encontrada');
    } catch (e) {
      return _exception('getById', e);
    }
  }

  /// `POST /rental` — cria contrato de locação.
  Future<ApiResponse<Rental>> create(RentalPayload payload) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        _rentals,
        body: payload.toJson(),
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: Rental.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return _fail(response, 'Erro ao criar locação');
    } catch (e) {
      return _exception('create', e);
    }
  }

  /// `PUT /rental/:id` — atualiza contrato.
  Future<ApiResponse<Rental>> update(String id, RentalPayload payload) async {
    try {
      final response = await _api.put<Map<String, dynamic>>(
        _rentalById(id),
        body: payload.toJson(),
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: Rental.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return _fail(response, 'Erro ao atualizar locação');
    } catch (e) {
      return _exception('update', e);
    }
  }

  /// `DELETE /rental/:id` — exclui a locação (e cancela cobranças pendentes).
  Future<ApiResponse<void>> delete(String id) async {
    try {
      final response = await _api.delete<dynamic>(_rentalById(id));
      if (response.success) {
        return ApiResponse.success(statusCode: response.statusCode);
      }
      return _fail(response, 'Erro ao excluir locação');
    } catch (e) {
      return _exception('delete', e);
    }
  }

  /// `GET /rental/check-availability` — imóvel disponível no período?
  Future<ApiResponse<bool>> checkAvailability({
    required String propertyId,
    required String startDate,
    required String endDate,
    String? excludeRentalId,
  }) async {
    try {
      final params = <String, String>{
        'propertyId': propertyId,
        'startDate': startDate,
        'endDate': endDate,
      };
      if ((excludeRentalId ?? '').isNotEmpty) {
        params['excludeRentalId'] = excludeRentalId!;
      }
      final response = await _api.get<Map<String, dynamic>>(
        _checkAvailability,
        queryParameters: params,
      );
      if (response.success && response.data != null) {
        final available = response.data!['available'];
        return ApiResponse.success(
          data: available == true || available?.toString() == 'true',
          statusCode: response.statusCode,
        );
      }
      return _fail(response, 'Erro ao verificar disponibilidade');
    } catch (e) {
      return _exception('checkAvailability', e);
    }
  }

  /// `PUT /rental/:id/status` — altera o status do contrato.
  Future<ApiResponse<Rental>> updateStatus(
      String id, RentalStatus status) async {
    try {
      final response = await _api.put<Map<String, dynamic>>(
        _rentalStatus(id),
        body: {'status': status.apiValue},
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: Rental.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return _fail(response, 'Erro ao alterar status');
    } catch (e) {
      return _exception('updateStatus', e);
    }
  }

  /// `POST /rental/:id/approve` — aprova locação pendente
  /// (permissão `rental:manage_workflows`).
  Future<ApiResponse<Rental>> approve(String id) async {
    try {
      final response =
          await _api.post<Map<String, dynamic>>(_rentalApprove(id));
      if (response.success) {
        return ApiResponse.success(
          data: response.data != null ? Rental.fromJson(response.data!) : null,
          statusCode: response.statusCode,
        );
      }
      return _fail(response, 'Erro ao aprovar locação');
    } catch (e) {
      return _exception('approve', e);
    }
  }

  /// `POST /rental/:id/reject` — rejeita locação pendente.
  Future<ApiResponse<Rental>> reject(String id) async {
    try {
      final response =
          await _api.post<Map<String, dynamic>>(_rentalReject(id));
      if (response.success) {
        return ApiResponse.success(
          data: response.data != null ? Rental.fromJson(response.data!) : null,
          statusCode: response.statusCode,
        );
      }
      return _fail(response, 'Erro ao rejeitar locação');
    } catch (e) {
      return _exception('reject', e);
    }
  }

  /// `GET /rental/settings` — ex.: exigir aprovação para criar aluguel.
  Future<ApiResponse<bool>> getRequireApprovalToCreate() async {
    try {
      final response =
          await _api.get<Map<String, dynamic>>(_rentalSettings);
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: response.data!['requireApprovalToCreateRental'] == true,
          statusCode: response.statusCode,
        );
      }
      return _fail(response, 'Erro ao carregar configurações');
    } catch (e) {
      return _exception('getRequireApprovalToCreate', e);
    }
  }

  /// `GET /rental/:id/history` — histórico paginado de ações.
  Future<ApiResponse<RentalPagedResult<RentalHistoryEntry>>> getHistory(
    String rentalId, {
    int page = 1,
    int limit = 10,
  }) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(
        _rentalHistory(rentalId),
        queryParameters: {'page': '$page', 'limit': '$limit'},
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: RentalPagedResult.fromJson(
              response.data!, RentalHistoryEntry.fromJson),
          statusCode: response.statusCode,
        );
      }
      return _fail(response, 'Erro ao carregar histórico');
    } catch (e) {
      return _exception('getHistory', e);
    }
  }

  /// `GET /rental/:id/comments` — comentários paginados.
  Future<ApiResponse<RentalPagedResult<RentalCommentEntry>>> getComments(
    String rentalId, {
    int page = 1,
    int limit = 10,
  }) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(
        _rentalComments(rentalId),
        queryParameters: {'page': '$page', 'limit': '$limit'},
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: RentalPagedResult.fromJson(
              response.data!, RentalCommentEntry.fromJson),
          statusCode: response.statusCode,
        );
      }
      return _fail(response, 'Erro ao carregar comentários');
    } catch (e) {
      return _exception('getComments', e);
    }
  }

  /// `POST /rental/:id/comments` — adiciona comentário.
  Future<ApiResponse<RentalCommentEntry>> addComment(
      String rentalId, String content) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        _rentalComments(rentalId),
        body: {'content': content},
      );
      if (response.success) {
        return ApiResponse.success(
          data: response.data != null
              ? RentalCommentEntry.fromJson(response.data!)
              : null,
          statusCode: response.statusCode,
        );
      }
      return _fail(response, 'Erro ao adicionar comentário');
    } catch (e) {
      return _exception('addComment', e);
    }
  }

  /// `GET /rental/:id/payments` — parcelas da locação.
  Future<ApiResponse<List<RentalPayment>>> getPayments(String rentalId) async {
    try {
      final response = await _api.get<dynamic>(_rentalPayments(rentalId));
      if (response.success && response.data != null) {
        final raw = response.data;
        final list = raw is List
            ? raw
                .map((e) => e is Map
                    ? RentalPayment.fromJson(Map<String, dynamic>.from(e))
                    : null)
                .whereType<RentalPayment>()
                .toList()
            : <RentalPayment>[];
        // Ordena por vencimento crescente (paridade com a tabela do web).
        list.sort((a, b) {
          final da = a.dueDate, db = b.dueDate;
          if (da == null && db == null) return 0;
          if (da == null) return 1;
          if (db == null) return -1;
          return da.compareTo(db);
        });
        return ApiResponse.success(
          data: list,
          statusCode: response.statusCode,
        );
      }
      return _fail(response, 'Erro ao carregar pagamentos');
    } catch (e) {
      return _exception('getPayments', e);
    }
  }

  /// `POST /rental/:id/payments/generate` — gera as parcelas do contrato
  /// (permissão `rental:manage_payments`).
  Future<ApiResponse<void>> generatePayments(String rentalId) async {
    try {
      final response =
          await _api.post<dynamic>(_rentalPaymentsGenerate(rentalId));
      if (response.success) {
        return ApiResponse.success(statusCode: response.statusCode);
      }
      return _fail(response, 'Erro ao gerar pagamentos');
    } catch (e) {
      return _exception('generatePayments', e);
    }
  }

  /// `POST /rental/:id/payments` — adiciona uma parcela avulsa.
  Future<ApiResponse<void>> addPayment(
    String rentalId, {
    required String dueDate,
    required double value,
    required String referenceMonth,
    String? observations,
  }) async {
    try {
      final body = <String, dynamic>{
        'dueDate': dueDate,
        'value': value,
        'referenceMonth': referenceMonth,
      };
      if ((observations ?? '').trim().isNotEmpty) {
        body['observations'] = observations!.trim();
      }
      final response = await _api.post<dynamic>(
        _rentalPayments(rentalId),
        body: body,
      );
      if (response.success) {
        return ApiResponse.success(statusCode: response.statusCode);
      }
      return _fail(response, 'Erro ao adicionar pagamento');
    } catch (e) {
      return _exception('addPayment', e);
    }
  }

  /// `PUT /rental/:id/payments/:paymentId` — atualiza a parcela
  /// (usado para marcar como paga, editar observações, etc.).
  Future<ApiResponse<void>> updatePayment(
    String rentalId,
    String paymentId,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _api.put<dynamic>(
        _rentalPayment(rentalId, paymentId),
        body: data,
      );
      if (response.success) {
        return ApiResponse.success(statusCode: response.statusCode);
      }
      return _fail(response, 'Erro ao atualizar pagamento');
    } catch (e) {
      return _exception('updatePayment', e);
    }
  }

  /// Marca a parcela como paga — mesmo payload do web
  /// (`status: paid` + data + valor + método).
  Future<ApiResponse<void>> markPaymentAsPaid(
    String rentalId,
    RentalPayment payment, {
    DateTime? paymentDate,
    RentalPaymentMethod method = RentalPaymentMethod.other,
  }) {
    final date = paymentDate ?? DateTime.now();
    final iso =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return updatePayment(rentalId, payment.id, {
      'status': RentalPaymentStatus.paid.apiValue,
      'paymentDate': iso,
      'paidValue': payment.value,
      'paymentMethod': method.apiValue,
    });
  }

  /// `DELETE /rental/:id/payments/:paymentId` — remove parcela.
  Future<ApiResponse<void>> deletePayment(
      String rentalId, String paymentId) async {
    try {
      final response =
          await _api.delete<dynamic>(_rentalPayment(rentalId, paymentId));
      if (response.success) {
        return ApiResponse.success(statusCode: response.statusCode);
      }
      return _fail(response, 'Erro ao excluir pagamento');
    } catch (e) {
      return _exception('deletePayment', e);
    }
  }

  /// `GET /rental/dashboard/stats` — KPIs do dashboard de locações.
  Future<ApiResponse<RentalDashboardData>> getDashboard({
    int? periodMonths,
    RentalStatus? status,
    String? propertyId,
  }) async {
    try {
      final params = <String, String>{};
      if (periodMonths == 6 || periodMonths == 12) {
        params['periodMonths'] = '$periodMonths';
      }
      if (status != null &&
          status != RentalStatus.unknown &&
          status != RentalStatus.pendingApproval) {
        params['status'] = status.apiValue;
      }
      if ((propertyId ?? '').isNotEmpty) params['propertyId'] = propertyId!;
      final response = await _api.get<Map<String, dynamic>>(
        _dashboardStats,
        queryParameters: params.isEmpty ? null : params,
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: RentalDashboardData.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return _fail(response, 'Erro ao carregar dashboard de locações');
    } catch (e) {
      return _exception('getDashboard', e);
    }
  }
}
