import 'package:flutter/foundation.dart';
import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';
import '../models/notification_model.dart';

/// Serviço para gerenciar notificações
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();
  final ApiService _apiService = ApiService.instance;

  /// Lista notificações com filtros opcionais
  Future<ApiResponse<NotificationListResponse>> listNotifications({
    bool? read,
    String? type,
    String? companyId,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final params = NotificationQueryParams(
        read: read,
        type: type,
        companyId: companyId,
        page: page,
        limit: limit,
      ).toQueryMap();

      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConstants.notifications,
        queryParameters: params,
      );

      if (response.success && response.data != null) {
        try {
          final listResponse =
              NotificationListResponse.fromJson(response.data!);
          return ApiResponse.success(
            data: listResponse,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [NOTIFICATION_SERVICE] Erro ao fazer parse: $e');
          debugPrint('📚 [NOTIFICATION_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao listar notificações',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [NOTIFICATION_SERVICE] Exceção ao listar: $e');
      debugPrint('📚 [NOTIFICATION_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro ao listar notificações: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Lista apenas notificações não lidas
  Future<ApiResponse<NotificationListResponse>> listUnreadNotifications({
    String? companyId,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final params = <String, String>{};
      if (companyId != null && companyId.isNotEmpty) {
        params['companyId'] = companyId;
      }
      if (page > 1) {
        params['page'] = page.toString();
      }
      if (limit != 20) {
        params['limit'] = limit.toString();
      }

      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConstants.notificationsUnreadList,
        queryParameters: params.isEmpty ? null : params,
      );

      if (response.success && response.data != null) {
        try {
          final listResponse =
              NotificationListResponse.fromJson(response.data!);
          return ApiResponse.success(
            data: listResponse,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [NOTIFICATION_SERVICE] Erro ao fazer parse: $e');
          debugPrint('📚 [NOTIFICATION_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao listar notificações não lidas',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [NOTIFICATION_SERVICE] Exceção ao listar não lidas: $e');
      debugPrint('📚 [NOTIFICATION_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro ao listar notificações não lidas: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Busca uma notificação por ID
  Future<ApiResponse<NotificationModel>> getNotificationById(String id) async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConstants.notificationById(id),
      );

      if (response.success && response.data != null) {
        try {
          final notification = NotificationModel.fromJson(response.data!);
          return ApiResponse.success(
            data: notification,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [NOTIFICATION_SERVICE] Erro ao fazer parse: $e');
          debugPrint('📚 [NOTIFICATION_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar notificação',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [NOTIFICATION_SERVICE] Exceção ao buscar: $e');
      debugPrint('📚 [NOTIFICATION_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro ao buscar notificação: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Obtém contador de não lidas
  Future<ApiResponse<UnreadCountResponse>> getUnreadCount({
    String? companyId,
  }) async {
    try {
      final params = <String, String>{};
      if (companyId != null && companyId.isNotEmpty) {
        params['companyId'] = companyId;
      }

      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConstants.notificationsUnreadCount,
        queryParameters: params.isEmpty ? null : params,
      );

      if (response.success && response.data != null) {
        try {
          final countResponse = UnreadCountResponse.fromJson(response.data!);
          return ApiResponse.success(
            data: countResponse,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [NOTIFICATION_SERVICE] Erro ao fazer parse: $e');
          debugPrint('📚 [NOTIFICATION_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao obter contador',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [NOTIFICATION_SERVICE] Exceção ao obter contador: $e');
      debugPrint('📚 [NOTIFICATION_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro ao obter contador: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Obtém contador por empresa
  Future<ApiResponse<UnreadCountByCompanyResponse>>
      getUnreadCountByCompany() async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConstants.notificationsUnreadCountByCompany,
      );

      if (response.success && response.data != null) {
        try {
          final countResponse =
              UnreadCountByCompanyResponse.fromJson(response.data!);
          return ApiResponse.success(
            data: countResponse,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [NOTIFICATION_SERVICE] Erro ao fazer parse: $e');
          debugPrint('📚 [NOTIFICATION_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao obter contador por empresa',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint(
          '❌ [NOTIFICATION_SERVICE] Exceção ao obter contador por empresa: $e');
      debugPrint('📚 [NOTIFICATION_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro ao obter contador por empresa: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Marca notificação como lida
  Future<ApiResponse<NotificationModel>> markAsRead(String id) async {
    try {
      final response = await _apiService.patch<Map<String, dynamic>>(
        ApiConstants.markNotificationRead(id),
      );

      if (response.success && response.data != null) {
        try {
          final notification = NotificationModel.fromJson(response.data!);
          return ApiResponse.success(
            data: notification,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [NOTIFICATION_SERVICE] Erro ao fazer parse: $e');
          debugPrint('📚 [NOTIFICATION_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao marcar como lida',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [NOTIFICATION_SERVICE] Exceção ao marcar como lida: $e');
      debugPrint('📚 [NOTIFICATION_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro ao marcar como lida: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Marca notificação como não lida
  Future<ApiResponse<NotificationModel>> markAsUnread(String id) async {
    try {
      final response = await _apiService.patch<Map<String, dynamic>>(
        ApiConstants.markNotificationUnread(id),
      );

      if (response.success && response.data != null) {
        try {
          final notification = NotificationModel.fromJson(response.data!);
          return ApiResponse.success(
            data: notification,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [NOTIFICATION_SERVICE] Erro ao fazer parse: $e');
          debugPrint('📚 [NOTIFICATION_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao marcar como não lida',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint(
          '❌ [NOTIFICATION_SERVICE] Exceção ao marcar como não lida: $e');
      debugPrint('📚 [NOTIFICATION_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro ao marcar como não lida: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Marca múltiplas notificações como lidas
  Future<ApiResponse<BulkReadResponse>> markMultipleAsRead(
      List<String> notificationIds) async {
    try {
      final response = await _apiService.patch<Map<String, dynamic>>(
        ApiConstants.markNotificationsReadBulk,
        body: {
          'notificationIds': notificationIds,
        },
      );

      if (response.success && response.data != null) {
        try {
          final bulkResponse = BulkReadResponse.fromJson(response.data!);
          return ApiResponse.success(
            data: bulkResponse,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [NOTIFICATION_SERVICE] Erro ao fazer parse: $e');
          debugPrint('📚 [NOTIFICATION_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao marcar múltiplas como lidas',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint(
          '❌ [NOTIFICATION_SERVICE] Exceção ao marcar múltiplas: $e');
      debugPrint('📚 [NOTIFICATION_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro ao marcar múltiplas como lidas: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Marca todas as notificações como lidas
  Future<ApiResponse<BulkReadResponse>> markAllAsRead({
    String? companyId,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (companyId != null && companyId.isNotEmpty) {
        body['companyId'] = companyId;
      }

      final response = await _apiService.patch<Map<String, dynamic>>(
        ApiConstants.markNotificationsReadAll,
        body: body.isEmpty ? null : body,
      );

      if (response.success && response.data != null) {
        try {
          final bulkResponse = BulkReadResponse.fromJson(response.data!);
          return ApiResponse.success(
            data: bulkResponse,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [NOTIFICATION_SERVICE] Erro ao fazer parse: $e');
          debugPrint('📚 [NOTIFICATION_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao marcar todas como lidas',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [NOTIFICATION_SERVICE] Exceção ao marcar todas: $e');
      debugPrint('📚 [NOTIFICATION_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro ao marcar todas como lidas: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Exclui uma notificação
  Future<ApiResponse<void>> deleteNotification(String id) async {
    try {
      final response = await _apiService.delete<void>(
        ApiConstants.notificationById(id),
      );

      if (response.success) {
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao excluir notificação',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [NOTIFICATION_SERVICE] Exceção ao excluir: $e');
      debugPrint('📚 [NOTIFICATION_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro ao excluir notificação: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}


