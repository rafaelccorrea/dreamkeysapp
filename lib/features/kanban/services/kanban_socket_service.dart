import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/secure_storage_service.dart';

/// Socket do funil em tempo real (namespace `/kanban` do back).
///
/// Até 28/09/2026 o app só abria socket para chat e notificações: um lead
/// novo chegava como aviso no sino, mas o card não entrava na primeira coluna
/// do funil até a pessoa recarregar. O web escuta este mesmo gateway
/// (`task_created`, `task_moved`, `task_updated`, `task_deleted`, por sala
/// `team_<teamId>`); agora o app também.
///
/// Mesmo molde do `NotificationWebSocketService`: token no `auth`, só
/// `websocket`, reconexão manual com recuo exponencial. O controlador do
/// funil chama `joinTeam` quando o quadro carrega e `leaveTeam` ao trocar
/// de equipe.
class KanbanSocketService with WidgetsBindingObserver {
  KanbanSocketService._();

  static final KanbanSocketService instance = KanbanSocketService._();

  bool _observando = false;

  /// Voltou do segundo plano: o sistema derruba o socket lá e o que mudou
  /// no meio se perdeu. Reconecta (zerando o recuo) e avisa quem escuta.
  void Function()? onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _reconnectAttempts = 0;
    final team = _joinedTeamId;
    if (team != null && !_isConnected) {
      _currentToken = null;
      unawaited(joinTeam(team));
    }
    onResumed?.call();
  }

  io.Socket? _socket;
  bool _isConnected = false;
  String? _currentToken;
  String? _joinedTeamId;
  bool _authRejected = false;

  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 8;
  static const int _baseReconnectDelayMs = 1000;
  static const int _maxReconnectDelayMs = 30000;
  Timer? _reconnectTimer;

  void Function(Map<String, dynamic> task)? onTaskCreated;
  void Function(Map<String, dynamic> task)? onTaskMoved;
  void Function(Map<String, dynamic> task)? onTaskUpdated;
  void Function(String taskId)? onTaskDeleted;
  void Function(bool connected)? onConnectionChanged;

  /// Voltou depois de cair: o que aconteceu no meio se perdeu, e quem
  /// escuta recarrega o quadro.
  void Function()? onReconnected;

  bool get isConnected => _isConnected;
  String? get joinedTeamId => _joinedTeamId;

  /// Conecta (ou reconecta) e entra na sala da equipe.
  Future<void> joinTeam(String teamId) async {
    if (teamId.isEmpty) return;
    if (!_observando) {
      _observando = true;
      WidgetsBinding.instance.addObserver(this);
    }
    final trocouDeEquipe = _joinedTeamId != null && _joinedTeamId != teamId;
    if (trocouDeEquipe && _isConnected) {
      _socket?.emit('leave_team', {'teamId': _joinedTeamId});
    }
    _joinedTeamId = teamId;

    final token = await SecureStorageService.instance.getAccessToken();
    if (token == null || token.isEmpty) return;

    if (token != _currentToken) _authRejected = false;
    if (_authRejected) return;

    final mesmoToken = token == _currentToken;
    if (_socket != null && _isConnected && mesmoToken) {
      _socket!.emit('join_team', {'teamId': teamId});
      return;
    }

    _currentToken = token;
    _descartarSocket();

    try {
      _socket = io.io(
        _url(),
        io.OptionBuilder()
            .setTransports(['websocket'])
            .setAuth({'token': token})
            .setTimeout(20000)
            .disableAutoConnect()
            .build(),
      );
      _ligarEventos();
      _socket!.connect();
    } catch (e) {
      debugPrint('[KANBAN_WS] Erro ao conectar: $e');
      _agendarReconexao();
    }
  }

  /// Sai da sala atual (troca de equipe ou saída do funil).
  void leaveTeam() {
    if (_joinedTeamId != null && _isConnected) {
      _socket?.emit('leave_team', {'teamId': _joinedTeamId});
    }
    _joinedTeamId = null;
  }

  Future<void> disconnect() async {
    _joinedTeamId = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _descartarSocket();
  }

  String _url() {
    final base = ApiConstants.baseUrl;
    if (base.startsWith('https://')) {
      return '${base.replaceFirst('https://', 'wss://')}/kanban';
    }
    if (base.startsWith('http://')) {
      return '${base.replaceFirst('http://', 'ws://')}/kanban';
    }
    return '$base/kanban';
  }

  void _descartarSocket() {
    if (_socket == null) return;
    _socket!.disconnect();
    _socket!.dispose();
    _socket = null;
    _isConnected = false;
  }

  void _ligarEventos() {
    final s = _socket;
    if (s == null) return;

    s.onConnect((_) {
      final reconectou = _reconnectAttempts > 0;
      _isConnected = true;
      _reconnectAttempts = 0;
      onConnectionChanged?.call(true);
      if (_joinedTeamId != null) {
        s.emit('join_team', {'teamId': _joinedTeamId});
      }
      if (reconectou) onReconnected?.call();
    });

    s.onDisconnect((_) {
      _isConnected = false;
      onConnectionChanged?.call(false);
      _agendarReconexao();
    });

    s.onConnectError((e) {
      debugPrint('[KANBAN_WS] connect_error: $e');
      _isConnected = false;
      _agendarReconexao();
    });

    s.on('auth_error', (_) {
      // Token recusado: parar de insistir até chegar um token novo.
      _authRejected = true;
      _reconnectTimer?.cancel();
    });

    s.on('task_created', (data) {
      final task = _taskDe(data);
      if (task != null) onTaskCreated?.call(task);
    });
    s.on('task_moved', (data) {
      final task = _taskDe(data);
      if (task != null) onTaskMoved?.call(task);
    });
    s.on('task_updated', (data) {
      final task = _taskDe(data);
      if (task != null) onTaskUpdated?.call(task);
    });
    s.on('task_deleted', (data) {
      final id = data is Map ? data['taskId'] : null;
      if (id is String && id.isNotEmpty) onTaskDeleted?.call(id);
    });
  }

  /// O back manda `{ task: {...}, timestamp }`.
  Map<String, dynamic>? _taskDe(dynamic data) {
    if (data is! Map) return null;
    final task = data['task'];
    if (task is Map) return Map<String, dynamic>.from(task);
    return null;
  }

  void _agendarReconexao() {
    if (_authRejected || _joinedTeamId == null) return;
    if (_reconnectTimer?.isActive ?? false) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) return;
    final atraso = (_baseReconnectDelayMs * (1 << _reconnectAttempts))
        .clamp(_baseReconnectDelayMs, _maxReconnectDelayMs);
    _reconnectAttempts++;
    _reconnectTimer = Timer(Duration(milliseconds: atraso), () {
      _reconnectTimer = null;
      final team = _joinedTeamId;
      if (team != null) {
        // Token pode ter mudado (refresh): joinTeam relê e reconecta.
        _currentToken = null;
        joinTeam(team);
      }
    });
  }
}
