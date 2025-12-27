import 'package:flutter/foundation.dart';
import '../models/appointment_model.dart';
import '../services/appointment_service.dart';

/// Controller para gerenciar estado dos agendamentos
class AppointmentController extends ChangeNotifier {
  AppointmentController._();

  static final AppointmentController instance = AppointmentController._();

  final AppointmentService _appointmentService = AppointmentService.instance;
  final AppointmentInviteService _inviteService = AppointmentInviteService.instance;

  // Estado
  List<Appointment> _appointments = [];
  Appointment? _selectedAppointment;
  List<AppointmentInvite> _invites = [];
  List<AppointmentInvite> _pendingInvites = [];
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  bool _hasMore = true;
  int _currentPage = 1;
  static const int _pageLimit = 20;

  // Filtros
  String? _filterStatus;
  String? _filterType;
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  String? _filterPropertyId;
  String? _filterClientId;
  bool _onlyMyData = false;
  String _searchTerm = '';

  // Getters
  List<Appointment> get appointments => List.unmodifiable(_appointments);
  Appointment? get selectedAppointment => _selectedAppointment;
  List<AppointmentInvite> get invites => List.unmodifiable(_invites);
  List<AppointmentInvite> get pendingInvites => List.unmodifiable(_pendingInvites);
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  String? get error => _error;
  bool get hasMore => _hasMore;
  String? get filterStatus => _filterStatus;
  String? get filterType => _filterType;
  DateTime? get filterStartDate => _filterStartDate;
  DateTime? get filterEndDate => _filterEndDate;
  String? get filterPropertyId => _filterPropertyId;
  String? get filterClientId => _filterClientId;
  bool get onlyMyData => _onlyMyData;
  String get searchTerm => _searchTerm;

  /// Lista de agendamentos filtrados por busca
  List<Appointment> get filteredAppointments {
    if (_searchTerm.isEmpty) return _appointments;
    
    final term = _searchTerm.toLowerCase();
    return _appointments.where((appointment) {
      return appointment.title.toLowerCase().contains(term) ||
          appointment.description?.toLowerCase().contains(term) == true ||
          appointment.location?.toLowerCase().contains(term) == true;
    }).toList();
  }

  /// Carrega lista de agendamentos
  Future<void> loadAppointments({bool reset = false}) async {
    if (reset) {
      _currentPage = 1;
      _appointments.clear();
      _hasMore = true;
    }

    if (_loading || _loadingMore || !_hasMore) return;

    if (reset) {
      _loading = true;
    } else {
      _loadingMore = true;
    }
    _error = null;
    notifyListeners();

    try {
      final response = await _appointmentService.listAppointments(
        status: _filterStatus,
        type: _filterType,
        startDate: _filterStartDate?.toIso8601String(),
        endDate: _filterEndDate?.toIso8601String(),
        propertyId: _filterPropertyId,
        clientId: _filterClientId,
        page: _currentPage,
        limit: _pageLimit,
        onlyMyData: _onlyMyData,
      );

      if (response.success && response.data != null) {
        if (reset) {
          _appointments = response.data!.appointments;
        } else {
          _appointments.addAll(response.data!.appointments);
        }

        _hasMore = response.data!.pagination.page < response.data!.pagination.totalPages;
        _currentPage++;
        _error = null;
      } else {
        _error = response.message ?? 'Erro ao carregar agendamentos';
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [APPOINTMENT_CTRL] Erro ao carregar: $e');
      debugPrint('📚 [APPOINTMENT_CTRL] StackTrace: $stackTrace');
      _error = 'Erro ao carregar agendamentos: ${e.toString()}';
    } finally {
      _loading = false;
      _loadingMore = false;
      notifyListeners();
    }
  }

  /// Busca um agendamento por ID
  Future<void> loadAppointmentById(String id) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _appointmentService.getAppointmentById(id);

      if (response.success && response.data != null) {
        _selectedAppointment = response.data;
        _error = null;
      } else {
        _error = response.message ?? 'Erro ao carregar agendamento';
        _selectedAppointment = null;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [APPOINTMENT_CTRL] Erro ao buscar: $e');
      debugPrint('📚 [APPOINTMENT_CTRL] StackTrace: $stackTrace');
      _error = 'Erro ao buscar agendamento: ${e.toString()}';
      _selectedAppointment = null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Cria um novo agendamento
  Future<bool> createAppointment(CreateAppointmentData data) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _appointmentService.createAppointment(data);

      if (response.success && response.data != null) {
        _appointments.insert(0, response.data!);
        _error = null;
        notifyListeners();
        return true;
      } else {
        _error = response.message ?? 'Erro ao criar agendamento';
        notifyListeners();
        return false;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [APPOINTMENT_CTRL] Erro ao criar: $e');
      debugPrint('📚 [APPOINTMENT_CTRL] StackTrace: $stackTrace');
      _error = 'Erro ao criar agendamento: ${e.toString()}';
      notifyListeners();
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Atualiza um agendamento
  Future<bool> updateAppointment(String id, UpdateAppointmentData data) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _appointmentService.updateAppointment(id, data);

      if (response.success && response.data != null) {
        final index = _appointments.indexWhere((a) => a.id == id);
        if (index != -1) {
          _appointments[index] = response.data!;
        }
        if (_selectedAppointment?.id == id) {
          _selectedAppointment = response.data;
        }
        _error = null;
        notifyListeners();
        return true;
      } else {
        _error = response.message ?? 'Erro ao atualizar agendamento';
        notifyListeners();
        return false;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [APPOINTMENT_CTRL] Erro ao atualizar: $e');
      debugPrint('📚 [APPOINTMENT_CTRL] StackTrace: $stackTrace');
      _error = 'Erro ao atualizar agendamento: ${e.toString()}';
      notifyListeners();
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Exclui um agendamento
  Future<bool> deleteAppointment(String id) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _appointmentService.deleteAppointment(id);

      if (response.success) {
        _appointments.removeWhere((a) => a.id == id);
        if (_selectedAppointment?.id == id) {
          _selectedAppointment = null;
        }
        _error = null;
        notifyListeners();
        return true;
      } else {
        _error = response.message ?? 'Erro ao excluir agendamento';
        notifyListeners();
        return false;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [APPOINTMENT_CTRL] Erro ao excluir: $e');
      debugPrint('📚 [APPOINTMENT_CTRL] StackTrace: $stackTrace');
      _error = 'Erro ao excluir agendamento: ${e.toString()}';
      notifyListeners();
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Adiciona um participante
  Future<bool> addParticipant(String appointmentId, String userId) async {
    try {
      final response = await _appointmentService.addParticipant(appointmentId, userId);

      if (response.success && response.data != null) {
        final index = _appointments.indexWhere((a) => a.id == appointmentId);
        if (index != -1) {
          _appointments[index] = response.data!;
        }
        if (_selectedAppointment?.id == appointmentId) {
          _selectedAppointment = response.data;
        }
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ [APPOINTMENT_CTRL] Erro ao adicionar participante: $e');
      return false;
    }
  }

  /// Remove um participante
  Future<bool> removeParticipant(String appointmentId, String userId) async {
    try {
      final response = await _appointmentService.removeParticipant(appointmentId, userId);

      if (response.success && response.data != null) {
        final index = _appointments.indexWhere((a) => a.id == appointmentId);
        if (index != -1) {
          _appointments[index] = response.data!;
        }
        if (_selectedAppointment?.id == appointmentId) {
          _selectedAppointment = response.data;
        }
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ [APPOINTMENT_CTRL] Erro ao remover participante: $e');
      return false;
    }
  }

  /// Carrega convites
  Future<void> loadInvites() async {
    try {
      final response = await _inviteService.getMyInvites();
      if (response.success && response.data != null) {
        _invites = response.data!;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌ [APPOINTMENT_CTRL] Erro ao carregar convites: $e');
    }
  }

  /// Carrega convites pendentes
  Future<void> loadPendingInvites() async {
    try {
      final response = await _inviteService.getPendingInvites();
      if (response.success && response.data != null) {
        _pendingInvites = response.data!;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌ [APPOINTMENT_CTRL] Erro ao carregar convites pendentes: $e');
    }
  }

  /// Cria um convite
  Future<bool> createInvite({
    required String appointmentId,
    required String invitedUserId,
    String? message,
  }) async {
    try {
      final response = await _inviteService.createInvite(
        appointmentId: appointmentId,
        invitedUserId: invitedUserId,
        message: message,
      );

      if (response.success && response.data != null) {
        await loadInvites();
        await loadAppointmentById(appointmentId);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ [APPOINTMENT_CTRL] Erro ao criar convite: $e');
      return false;
    }
  }

  /// Responde a um convite
  Future<bool> respondToInvite({
    required String inviteId,
    required InviteStatus status,
    String? responseMessage,
  }) async {
    try {
      final response = await _inviteService.respondToInvite(
        inviteId: inviteId,
        status: status,
        responseMessage: responseMessage,
      );

      if (response.success && response.data != null) {
        await loadPendingInvites();
        await loadInvites();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ [APPOINTMENT_CTRL] Erro ao responder convite: $e');
      return false;
    }
  }

  /// Cancela um convite
  Future<bool> cancelInvite(String inviteId) async {
    try {
      final response = await _inviteService.cancelInvite(inviteId);
      if (response.success) {
        await loadInvites();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ [APPOINTMENT_CTRL] Erro ao cancelar convite: $e');
      return false;
    }
  }

  /// Define filtros
  void setFilters({
    String? status,
    String? type,
    DateTime? startDate,
    DateTime? endDate,
    String? propertyId,
    String? clientId,
    bool? onlyMyData,
  }) {
    _filterStatus = status;
    _filterType = type;
    _filterStartDate = startDate;
    _filterEndDate = endDate;
    _filterPropertyId = propertyId;
    _filterClientId = clientId;
    if (onlyMyData != null) {
      _onlyMyData = onlyMyData;
    }
    notifyListeners();
  }

  /// Limpa filtros
  void clearFilters() {
    _filterStatus = null;
    _filterType = null;
    _filterStartDate = null;
    _filterEndDate = null;
    _filterPropertyId = null;
    _filterClientId = null;
    _onlyMyData = false;
    _searchTerm = '';
    notifyListeners();
  }

  /// Define termo de busca
  void setSearchTerm(String term) {
    _searchTerm = term;
    notifyListeners();
  }

  /// Seleciona um agendamento
  void selectAppointment(Appointment? appointment) {
    _selectedAppointment = appointment;
    notifyListeners();
  }

  /// Limpa seleção
  void clearSelection() {
    _selectedAppointment = null;
    notifyListeners();
  }

  /// Limpa estado
  void clear() {
    _appointments.clear();
    _selectedAppointment = null;
    _invites.clear();
    _pendingInvites.clear();
    _error = null;
    _loading = false;
    _loadingMore = false;
    _hasMore = true;
    _currentPage = 1;
    clearFilters();
    notifyListeners();
  }
}

