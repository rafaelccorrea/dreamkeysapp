import 'package:flutter/foundation.dart';
import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';
import '../models/appointment_model.dart';

/// Serviço para gerenciar agendamentos
class AppointmentService {
  AppointmentService._();

  static final AppointmentService instance = AppointmentService._();
  final ApiService _apiService = ApiService.instance;

  /// Lista agendamentos com filtros opcionais
  Future<ApiResponse<AppointmentListResponse>> listAppointments({
    String? status,
    String? type,
    String? startDate,
    String? endDate,
    String? propertyId,
    String? clientId,
    int? page,
    int? limit,
    bool? onlyMyData,
  }) async {
    try {
      final params = <String, String>{};
      if (status != null && status.isNotEmpty) params['status'] = status;
      if (type != null && type.isNotEmpty) params['type'] = type;
      if (startDate != null && startDate.isNotEmpty) params['startDate'] = startDate;
      if (endDate != null && endDate.isNotEmpty) params['endDate'] = endDate;
      if (propertyId != null && propertyId.isNotEmpty) params['propertyId'] = propertyId;
      if (clientId != null && clientId.isNotEmpty) params['clientId'] = clientId;
      if (page != null) params['page'] = page.toString();
      if (limit != null) params['limit'] = limit.toString();
      if (onlyMyData != null) params['onlyMyData'] = onlyMyData.toString();

      final response = await _apiService.get(
        ApiConstants.appointments,
        queryParameters: params.isEmpty ? null : params,
      );

      if (response.success && response.data != null) {
        try {
          AppointmentListResponse listResponse;
          
          // Verificar se a resposta é uma lista direta ou um objeto com paginação
          if (response.data is List) {
            // Se for uma lista direta, criar um objeto de resposta com paginação padrão
            final appointments = (response.data as List)
                .map((e) => Appointment.fromJson(e as Map<String, dynamic>))
                .toList();
            
            listResponse = AppointmentListResponse(
              appointments: appointments,
              pagination: PaginationInfo(
                page: page ?? 1,
                limit: limit ?? 20,
                total: appointments.length,
                totalPages: 1,
              ),
            );
          } else if (response.data is Map<String, dynamic>) {
            // Se for um objeto com paginação, fazer parse normal
            listResponse = AppointmentListResponse.fromJson(response.data as Map<String, dynamic>);
          } else {
            throw Exception('Formato de resposta não reconhecido');
          }
          
          return ApiResponse.success(
            data: listResponse,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [APPOINTMENT_SERVICE] Erro ao fazer parse: $e');
          debugPrint('📚 [APPOINTMENT_SERVICE] StackTrace: $stackTrace');
          debugPrint('📦 [APPOINTMENT_SERVICE] Tipo da resposta: ${response.data.runtimeType}');
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao listar agendamentos',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [APPOINTMENT_SERVICE] Exceção ao listar: $e');
      debugPrint('📚 [APPOINTMENT_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro ao listar agendamentos: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Busca um agendamento por ID
  Future<ApiResponse<Appointment>> getAppointmentById(String id) async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConstants.appointmentById(id),
      );

      if (response.success && response.data != null) {
        try {
          final appointment = Appointment.fromJson(response.data!);
          return ApiResponse.success(
            data: appointment,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [APPOINTMENT_SERVICE] Erro ao fazer parse: $e');
          debugPrint('📚 [APPOINTMENT_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar agendamento',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [APPOINTMENT_SERVICE] Exceção ao buscar: $e');
      debugPrint('📚 [APPOINTMENT_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro ao buscar agendamento: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Cria um novo agendamento
  Future<ApiResponse<Appointment>> createAppointment(
    CreateAppointmentData data,
  ) async {
    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConstants.appointments,
        body: data.toJson(),
      );

      if (response.success && response.data != null) {
        try {
          final appointment = Appointment.fromJson(response.data!);
          return ApiResponse.success(
            data: appointment,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [APPOINTMENT_SERVICE] Erro ao fazer parse: $e');
          debugPrint('📚 [APPOINTMENT_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar agendamento',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [APPOINTMENT_SERVICE] Exceção ao criar: $e');
      debugPrint('📚 [APPOINTMENT_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro ao criar agendamento: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Atualiza um agendamento
  Future<ApiResponse<Appointment>> updateAppointment(
    String id,
    UpdateAppointmentData data,
  ) async {
    try {
      final response = await _apiService.patch<Map<String, dynamic>>(
        ApiConstants.appointmentById(id),
        body: data.toJson(),
      );

      if (response.success && response.data != null) {
        try {
          final appointment = Appointment.fromJson(response.data!);
          return ApiResponse.success(
            data: appointment,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [APPOINTMENT_SERVICE] Erro ao fazer parse: $e');
          debugPrint('📚 [APPOINTMENT_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar agendamento',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [APPOINTMENT_SERVICE] Exceção ao atualizar: $e');
      debugPrint('📚 [APPOINTMENT_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro ao atualizar agendamento: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Exclui um agendamento
  Future<ApiResponse<void>> deleteAppointment(String id) async {
    try {
      final response = await _apiService.delete(
        ApiConstants.appointmentById(id),
      );

      if (response.success) {
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao excluir agendamento',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [APPOINTMENT_SERVICE] Exceção ao excluir: $e');
      debugPrint('📚 [APPOINTMENT_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro ao excluir agendamento: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Adiciona um participante ao agendamento
  Future<ApiResponse<Appointment>> addParticipant(
    String appointmentId,
    String userId,
  ) async {
    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConstants.appointmentParticipant(appointmentId, userId),
      );

      if (response.success && response.data != null) {
        try {
          final appointment = Appointment.fromJson(response.data!);
          return ApiResponse.success(
            data: appointment,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [APPOINTMENT_SERVICE] Erro ao fazer parse: $e');
          debugPrint('📚 [APPOINTMENT_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao adicionar participante',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [APPOINTMENT_SERVICE] Exceção ao adicionar participante: $e');
      debugPrint('📚 [APPOINTMENT_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro ao adicionar participante: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Remove um participante do agendamento
  Future<ApiResponse<Appointment>> removeParticipant(
    String appointmentId,
    String userId,
  ) async {
    try {
      final response = await _apiService.delete<Map<String, dynamic>>(
        ApiConstants.appointmentParticipant(appointmentId, userId),
      );

      if (response.success && response.data != null) {
        try {
          final appointment = Appointment.fromJson(response.data!);
          return ApiResponse.success(
            data: appointment,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [APPOINTMENT_SERVICE] Erro ao fazer parse: $e');
          debugPrint('📚 [APPOINTMENT_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao remover participante',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [APPOINTMENT_SERVICE] Exceção ao remover participante: $e');
      debugPrint('📚 [APPOINTMENT_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro ao remover participante: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}

/// Serviço para gerenciar convites de agendamento
class AppointmentInviteService {
  AppointmentInviteService._();

  static final AppointmentInviteService instance = AppointmentInviteService._();
  final ApiService _apiService = ApiService.instance;

  /// Lista meus convites
  Future<ApiResponse<List<AppointmentInvite>>> getMyInvites() async {
    try {
      final response = await _apiService.get<List<dynamic>>(
        ApiConstants.appointmentInvitesMyInvites,
      );

      if (response.success && response.data != null) {
        try {
          final invites = (response.data as List)
              .map((e) => AppointmentInvite.fromJson(e as Map<String, dynamic>))
              .toList();
          return ApiResponse.success(
            data: invites,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [APPOINTMENT_INVITE_SERVICE] Erro ao fazer parse: $e');
          debugPrint('📚 [APPOINTMENT_INVITE_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao listar convites',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [APPOINTMENT_INVITE_SERVICE] Exceção ao listar: $e');
      debugPrint('📚 [APPOINTMENT_INVITE_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro ao listar convites: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Lista convites pendentes
  Future<ApiResponse<List<AppointmentInvite>>> getPendingInvites() async {
    try {
      final response = await _apiService.get<List<dynamic>>(
        ApiConstants.appointmentInvitesPending,
      );

      if (response.success && response.data != null) {
        try {
          final invites = (response.data as List)
              .map((e) => AppointmentInvite.fromJson(e as Map<String, dynamic>))
              .toList();
          return ApiResponse.success(
            data: invites,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [APPOINTMENT_INVITE_SERVICE] Erro ao fazer parse: $e');
          debugPrint('📚 [APPOINTMENT_INVITE_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao listar convites pendentes',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [APPOINTMENT_INVITE_SERVICE] Exceção ao listar pendentes: $e');
      debugPrint('📚 [APPOINTMENT_INVITE_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro ao listar convites pendentes: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Cria um convite
  Future<ApiResponse<AppointmentInvite>> createInvite({
    required String appointmentId,
    required String invitedUserId,
    String? message,
  }) async {
    try {
      final body = <String, dynamic>{
        'appointmentId': appointmentId,
        'invitedUserId': invitedUserId,
      };
      if (message != null && message.isNotEmpty) {
        body['message'] = message;
      }

      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConstants.appointmentInvites,
        body: body,
      );

      if (response.success && response.data != null) {
        try {
          final invite = AppointmentInvite.fromJson(response.data!);
          return ApiResponse.success(
            data: invite,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [APPOINTMENT_INVITE_SERVICE] Erro ao fazer parse: $e');
          debugPrint('📚 [APPOINTMENT_INVITE_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar convite',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [APPOINTMENT_INVITE_SERVICE] Exceção ao criar: $e');
      debugPrint('📚 [APPOINTMENT_INVITE_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro ao criar convite: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Responde a um convite (aceitar ou recusar)
  Future<ApiResponse<AppointmentInvite>> respondToInvite({
    required String inviteId,
    required InviteStatus status,
    String? responseMessage,
  }) async {
    try {
      final body = <String, dynamic>{
        'status': status.value,
      };
      if (responseMessage != null && responseMessage.isNotEmpty) {
        body['responseMessage'] = responseMessage;
      }

      final response = await _apiService.patch<Map<String, dynamic>>(
        ApiConstants.appointmentInviteRespond(inviteId),
        body: body,
      );

      if (response.success && response.data != null) {
        try {
          final invite = AppointmentInvite.fromJson(response.data!);
          return ApiResponse.success(
            data: invite,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [APPOINTMENT_INVITE_SERVICE] Erro ao fazer parse: $e');
          debugPrint('📚 [APPOINTMENT_INVITE_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao responder convite',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [APPOINTMENT_INVITE_SERVICE] Exceção ao responder: $e');
      debugPrint('📚 [APPOINTMENT_INVITE_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro ao responder convite: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Cancela um convite
  Future<ApiResponse<void>> cancelInvite(String inviteId) async {
    try {
      final response = await _apiService.delete(
        ApiConstants.appointmentInviteById(inviteId),
      );

      if (response.success) {
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao cancelar convite',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [APPOINTMENT_INVITE_SERVICE] Exceção ao cancelar: $e');
      debugPrint('📚 [APPOINTMENT_INVITE_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro ao cancelar convite: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}

