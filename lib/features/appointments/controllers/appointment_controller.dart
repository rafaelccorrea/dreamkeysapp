import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/utils/error_cause.dart';
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
  // Guardados ao lado da mensagem: só o código HTTP (ou a exceção crua)
  // permite dizer se foi permissão, sessão expirada ou servidor fora do ar.
  int _errorStatus = 0;
  Object? _errorRaw;
  bool _hasMore = true;

  // Filtros
  String? _filterStatus;
  String? _filterType;
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  String? _filterPropertyId;
  String? _filterClientId;
  bool _onlyMyData = false;
  String _searchTerm = '';

  // ── Novo modelo da agenda ──────────────────────────────────────────────────
  // Escopo de pessoas (mutuamente exclusivo, prioridade empresa > seleção >
  // meus) — persistido em SharedPreferences como no web (calendar:scope).
  List<String> _scopeUserIds = [];
  bool _scopeAllCompany = false;

  // Janela de fetch derivada da navegação do calendário: do dia 1 do mês
  // anterior até o fim de +2 meses; ao navegar pra fora ela CRESCE (nunca
  // encolhe) — evita refetch a cada passo (paridade com o web).
  DateTime? _windowStart;
  DateTime? _windowEnd;

  static const String _scopePrefsKey = 'calendar:scope';

  // Getters
  List<Appointment> get appointments => List.unmodifiable(_appointments);
  Appointment? get selectedAppointment => _selectedAppointment;
  List<AppointmentInvite> get invites => List.unmodifiable(_invites);
  List<AppointmentInvite> get pendingInvites => List.unmodifiable(_pendingInvites);
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  String? get error => _error;
  int get errorStatus => _errorStatus;
  Object? get errorRaw => _errorRaw;

  /// Diagnóstico pronto da última falha. Quando não houve resposta HTTP (o
  /// pedido morreu antes), classifica pela exceção; caso contrário, pelo
  /// código devolvido pelo servidor.
  ErrorCause? get errorCause {
    if (_error == null) return null;
    if (_errorStatus == 0 && _errorRaw != null) {
      return ErrorCause.fromException(_errorRaw!);
    }
    return ErrorCause.fromApi(
      message: _error,
      statusCode: _errorStatus,
      error: _errorRaw,
    );
  }

  void _clearError() {
    _error = null;
    _errorStatus = 0;
    _errorRaw = null;
  }

  void _setApiError(String message, int statusCode, Object? raw) {
    _error = message;
    _errorStatus = statusCode;
    _errorRaw = raw;
  }

  /// A exceção crua não entra na mensagem: ela vai para o detalhe técnico,
  /// que fica recolhido, em vez de despejar um SocketException na tela.
  void _setThrownError(String message, Object e) {
    _error = message;
    _errorStatus = 0;
    _errorRaw = e;
  }

  bool get hasMore => _hasMore;
  String? get filterStatus => _filterStatus;
  String? get filterType => _filterType;
  DateTime? get filterStartDate => _filterStartDate;
  DateTime? get filterEndDate => _filterEndDate;
  String? get filterPropertyId => _filterPropertyId;
  String? get filterClientId => _filterClientId;
  bool get onlyMyData => _onlyMyData;
  String get searchTerm => _searchTerm;
  List<String> get scopeUserIds => List.unmodifiable(_scopeUserIds);
  bool get scopeAllCompany => _scopeAllCompany;

  /// Escopo diferente de "meus agendamentos"?
  bool get hasCustomScope => _scopeAllCompany || _scopeUserIds.isNotEmpty;

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

  /// Restaura o escopo persistido (chamar uma vez, antes do primeiro load).
  Future<void> restoreScope() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_scopePrefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _scopeUserIds = (decoded['userIds'] as List? ?? const [])
            .map((e) => e.toString())
            .toList();
        _scopeAllCompany = decoded['allCompany'] == true;
        notifyListeners();
      }
    } catch (_) {
      // JSON corrompido → ignora e segue no default "meus" (paridade web).
    }
  }

  /// Define o escopo de pessoas e persiste.
  Future<void> setScope({
    required List<String> userIds,
    required bool allCompany,
  }) async {
    _scopeUserIds = List.of(userIds);
    _scopeAllCompany = allCompany;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _scopePrefsKey,
        jsonEncode({'userIds': _scopeUserIds, 'allCompany': _scopeAllCompany}),
      );
    } catch (_) {}
  }

  /// Garante que a janela de fetch cobre o mês visível (mês−1 .. mês+2).
  /// Só cresce. Retorna `true` quando mudou — o chamador decide recarregar.
  bool ensureWindowCovers(DateTime visibleMonth) {
    final start = DateTime(visibleMonth.year, visibleMonth.month - 1, 1);
    final end =
        DateTime(visibleMonth.year, visibleMonth.month + 3, 0, 23, 59, 59);
    var changed = false;
    if (_windowStart == null || start.isBefore(_windowStart!)) {
      _windowStart = start;
      changed = true;
    }
    if (_windowEnd == null || end.isAfter(_windowEnd!)) {
      _windowEnd = end;
      changed = true;
    }
    return changed;
  }

  /// Carrega os agendamentos da JANELA (novo modelo: range query, sem
  /// paginação de 20 — a agenda precisa do período inteiro).
  Future<void> loadAppointments({bool reset = false}) async {
    if (_loading) return;
    // Janela default caso ninguém tenha chamado ensureWindowCovers ainda.
    ensureWindowCovers(DateTime.now());

    _loading = true;
    _clearError();
    notifyListeners();

    try {
      final response = await _appointmentService.listAppointments(
        status: _filterStatus,
        type: _filterType,
        startDate: _windowStart?.toIso8601String(),
        endDate: _windowEnd?.toIso8601String(),
        propertyId: _filterPropertyId,
        clientId: _filterClientId,
        // Escopo exclusivo: empresa > seleção > meus (default do modelo).
        viewAllCompany: _scopeAllCompany,
        targetUserIds: _scopeUserIds,
        onlyMyData: true,
      );

      if (response.success && response.data != null) {
        _appointments = response.data!.appointments;
        _hasMore = false;
        _clearError();
      } else {
        _setApiError(response.message ?? 'Erro ao carregar agendamentos',
            response.statusCode, response.error);
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [APPOINTMENT_CTRL] Erro ao carregar: $e');
      debugPrint('📚 [APPOINTMENT_CTRL] StackTrace: $stackTrace');
      _setThrownError('Erro ao carregar agendamentos', e);
    } finally {
      _loading = false;
      _loadingMore = false;
      notifyListeners();
    }
  }

  /// Busca um agendamento por ID
  Future<void> loadAppointmentById(String id) async {
    _loading = true;
    _clearError();
    notifyListeners();

    try {
      final response = await _appointmentService.getAppointmentById(id);

      if (response.success && response.data != null) {
        _selectedAppointment = response.data;
        _clearError();
      } else {
        _setApiError(response.message ?? 'Erro ao carregar agendamento',
            response.statusCode, response.error);
        _selectedAppointment = null;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [APPOINTMENT_CTRL] Erro ao buscar: $e');
      debugPrint('📚 [APPOINTMENT_CTRL] StackTrace: $stackTrace');
      _setThrownError('Erro ao buscar agendamento', e);
      _selectedAppointment = null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Cria um novo agendamento
  Future<bool> createAppointment(CreateAppointmentData data) async {
    _loading = true;
    _clearError();
    notifyListeners();

    try {
      final response = await _appointmentService.createAppointment(data);

      if (response.success && response.data != null) {
        _appointments.insert(0, response.data!);
        _clearError();
        notifyListeners();
        return true;
      } else {
        _setApiError(response.message ?? 'Erro ao criar agendamento',
            response.statusCode, response.error);
        notifyListeners();
        return false;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [APPOINTMENT_CTRL] Erro ao criar: $e');
      debugPrint('📚 [APPOINTMENT_CTRL] StackTrace: $stackTrace');
      _setThrownError('Erro ao criar agendamento', e);
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
    _clearError();
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
        _clearError();
        notifyListeners();
        return true;
      } else {
        _setApiError(response.message ?? 'Erro ao atualizar agendamento',
            response.statusCode, response.error);
        notifyListeners();
        return false;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [APPOINTMENT_CTRL] Erro ao atualizar: $e');
      debugPrint('📚 [APPOINTMENT_CTRL] StackTrace: $stackTrace');
      _setThrownError('Erro ao atualizar agendamento', e);
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
    _clearError();
    notifyListeners();

    try {
      final response = await _appointmentService.deleteAppointment(id);

      if (response.success) {
        _appointments.removeWhere((a) => a.id == id);
        if (_selectedAppointment?.id == id) {
          _selectedAppointment = null;
        }
        _clearError();
        notifyListeners();
        return true;
      } else {
        _setApiError(response.message ?? 'Erro ao excluir agendamento',
            response.statusCode, response.error);
        notifyListeners();
        return false;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [APPOINTMENT_CTRL] Erro ao excluir: $e');
      debugPrint('📚 [APPOINTMENT_CTRL] StackTrace: $stackTrace');
      _setThrownError('Erro ao excluir agendamento', e);
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
    _clearError();
    _loading = false;
    _loadingMore = false;
    _hasMore = true;
    _windowStart = null;
    _windowEnd = null;
    clearFilters();
    notifyListeners();
  }
}


