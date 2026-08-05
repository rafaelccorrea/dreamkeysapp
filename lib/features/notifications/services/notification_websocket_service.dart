import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../../../core/constants/api_constants.dart';
import '../../../shared/services/secure_storage_service.dart';
import '../models/notification_model.dart';

/// Serviço para conexão WebSocket de notificações em tempo real
class NotificationWebSocketService {
  NotificationWebSocketService._();

  static final NotificationWebSocketService _instance =
      NotificationWebSocketService._();

  factory NotificationWebSocketService() => _instance;

  static NotificationWebSocketService get instance => _instance;

  IO.Socket? _socket;
  bool _isConnected = false;
  String? _currentToken;
  String? _currentUserId;
  String? _currentCompanyId;

  // Callbacks
  Function(NotificationModel)? _onNotificationReceived;
  Function(int)? _onBadgeUpdate;
  Function(String)? _onNotificationRead;
  Function(bool)? _onConnectionStatusChanged;
  Function(String)? _onAuthError;

  /// Token recusado pelo gateway: para a fila de reconexão até haver token novo.
  /// Sem isso a reconexão contínua vira loop infinito com token expirado.
  bool _authRejected = false;
  Function(String)? _onCompanySubscribed;
  Function(String)? _onCompanyUnsubscribed;

  // Reconexão: contínua para manter sempre conectado
  int _reconnectAttempts = 0;
  static const int _baseReconnectDelay = 1000; // 1 segundo
  static const int _maxReconnectDelay = 30000; // 30 segundos
  Timer? _reconnectTimer;
  bool _isReconnecting = false;

  // Heartbeat: verifica conexão a cada intervalo e reconecta se estiver desconectado
  Timer? _heartbeatTimer;
  static const int _heartbeatIntervalSeconds = 25;

  bool get isConnected => _isConnected;

  /// Conecta ao WebSocket
  Future<void> connect([String? userId]) async {
    try {
      // Obter token
      final token = await SecureStorageService.instance.getAccessToken();
      if (token == null || token.isEmpty) {
        debugPrint('⚠️ [WS] Token não encontrado, não é possível conectar');
        return;
      }

      // Token novo (refresh/login) destrava a reconexão suspensa por auth_error.
      if (token != _currentToken) {
        _authRejected = false;
      }

      _currentToken = token;
      _currentUserId = userId;

      // Sempre limpar socket anterior (conectado ou não) para evitar conexões órfãs
      if (_socket != null) {
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        _stopHeartbeat();
        _socket!.disconnect();
        _socket!.dispose();
        _socket = null;
        _isConnected = false;
      }

      // Construir URL do WebSocket
      final wsUrl = _getWebSocketUrl();
      debugPrint('🔄 [WS] Conectando ao WebSocket: $wsUrl');

      // Criar socket
      _socket = IO.io(
        wsUrl,
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .setAuth({'token': token})
            .setTimeout(20000)
            .build(),
      );

      // Configurar event handlers
      _setupEventHandlers();

      // Conectar manualmente (reconexão será gerenciada manualmente)
      _socket!.connect();
    } catch (e, stackTrace) {
      debugPrint('❌ [WS] Erro ao conectar: $e');
      debugPrint('📚 [WS] StackTrace: $stackTrace');
      _handleReconnect();
    }
  }

  /// Obtém URL do WebSocket
  String _getWebSocketUrl() {
    // Converter https:// para ws:// ou wss://
    final baseUrl = ApiConstants.baseUrl;
    if (baseUrl.startsWith('https://')) {
      return '${baseUrl.replaceFirst('https://', 'wss://')}/notifications';
    } else if (baseUrl.startsWith('http://')) {
      return '${baseUrl.replaceFirst('http://', 'ws://')}/notifications';
    }
    return '$baseUrl/notifications';
  }

  /// Configura event handlers do WebSocket
  void _setupEventHandlers() {
    if (_socket == null) return;

    // Conectado
    _socket!.onConnect((_) {
      debugPrint('✅ [WS] Conectado ao WebSocket de notificações');
      _isConnected = true;
      _reconnectAttempts = 0; // Resetar tentativas ao conectar com sucesso
      _isReconnecting = false;
      _onConnectionStatusChanged?.call(true);

      // Iniciar heartbeat para manter conexão viva e detectar desconexão
      _startHeartbeat();

      // Emitir 'join' com userId
      if (_currentUserId != null && _currentUserId!.isNotEmpty) {
        _socket!.emit('join', _currentUserId);
        debugPrint('📤 [WS] Enviado evento "join" com userId: $_currentUserId');
      }

      // Se tiver empresa selecionada, inscrever
      if (_currentCompanyId != null && _currentCompanyId!.isNotEmpty) {
        subscribeCompany(_currentCompanyId!);
      }
    });

    // Confirmação de conexão do servidor
    _socket!.on('notifications_connected', (data) {
      debugPrint('✅ [WS] Confirmação de conexão recebida: $data');
    });

    // Nova notificação (backend emite 'new_notification' com { notification, timestamp })
    _socket!.on('new_notification', (data) {
      try {
        debugPrint('📨 [WS] Nova notificação recebida');
        final payload = data as Map<String, dynamic>?;
        final notificationData = payload?['notification'];
        if (notificationData != null) {
          final notification = NotificationModel.fromJson(
            notificationData as Map<String, dynamic>,
          );
          _onNotificationReceived?.call(notification);
        }
      } catch (e, stackTrace) {
        debugPrint('❌ [WS] Erro ao processar notificação: $e');
        debugPrint('📚 [WS] StackTrace: $stackTrace');
      }
    });

    // Atualização de badge (contador total)
    _socket!.on('badge_update', (data) {
      try {
        final unreadCount = (data as Map<String, dynamic>)['unreadCount'] as int? ?? 0;
        debugPrint('🔔 [WS] Badge atualizado: $unreadCount');
        _onBadgeUpdate?.call(unreadCount);
      } catch (e, stackTrace) {
        debugPrint('❌ [WS] Erro ao processar badge_update: $e');
        debugPrint('📚 [WS] StackTrace: $stackTrace');
      }
    });

    // Notificação marcada como lida
    _socket!.on('notification_read', (data) {
      try {
        final notificationId = (data as Map<String, dynamic>)['notificationId'] as String?;
        if (notificationId != null) {
          debugPrint('✅ [WS] Notificação marcada como lida: $notificationId');
          _onNotificationRead?.call(notificationId);
        }
      } catch (e, stackTrace) {
        debugPrint('❌ [WS] Erro ao processar notification_read: $e');
        debugPrint('📚 [WS] StackTrace: $stackTrace');
      }
    });

    // Desconectado
    _socket!.onDisconnect((reason) {
      debugPrint('❌ [WS] Desconectado: $reason');
      _isConnected = false;
      _stopHeartbeat();
      _onConnectionStatusChanged?.call(false);

      // Se foi desconexão intencional do cliente (io client disconnect), não tentar reconectar
      if (reason.toString().contains('io client disconnect')) {
        debugPrint('ℹ️ [WS] Desconexão intencional do cliente, não tentando reconectar');
        _reconnectAttempts = 0;
        return;
      }

      // Manter sempre tentando reconectar (sem limite)
      _handleReconnect();
    });

    // Erro de conexão
    _socket!.onConnectError((error) {
      debugPrint('❌ [WS] Erro de conexão: $error');
      _isConnected = false;
      _onConnectionStatusChanged?.call(false);

      // Manter sempre tentando reconectar (sem limite)
      _handleReconnect();
    });

    // Token recusado pelo gateway — não adianta reconectar com o mesmo token.
    _socket!.on('auth_error', (data) {
      final reason = data is Map
          ? (data['error']?.toString() ?? 'token_invalid')
          : 'token_invalid';
      final message = data is Map ? data['message']?.toString() : null;
      debugPrint('🔒 [WS] Token recusado ($reason): ${message ?? '-'}');

      _authRejected = true;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _isReconnecting = false;
      _stopHeartbeat();

      _onAuthError?.call(reason);
    });

    // Erro geral
    _socket!.onError((error) {
      debugPrint('❌ [WS] Erro: $error');
    });
  }

  /// Reconexão automática com exponential backoff (sem limite de tentativas)
  void _handleReconnect() {
    if (_currentToken == null || _currentToken!.isEmpty) {
      debugPrint('⚠️ [WS] Sem token, não é possível reconectar');
      _isReconnecting = false;
      return;
    }

    if (_authRejected) {
      debugPrint('🔒 [WS] Token recusado — reconexão suspensa até novo login/refresh');
      _isReconnecting = false;
      return;
    }

    if (_reconnectTimer != null && _reconnectTimer!.isActive) {
      return;
    }

    if (_isReconnecting) {
      return;
    }

    _isReconnecting = true;
    _reconnectAttempts++;

    // Exponential backoff: 1s, 2s, 4s, 8s, ... até 30s (cap)
    final exponentialDelay = _baseReconnectDelay * (1 << (_reconnectAttempts - 1));
    final delay = exponentialDelay > _maxReconnectDelay
        ? _maxReconnectDelay
        : exponentialDelay;

    debugPrint('🔄 [WS] Reconectando em ${delay}ms (tentativa $_reconnectAttempts)');

    _reconnectTimer = Timer(Duration(milliseconds: delay), () {
      _reconnectTimer = null;
      _isReconnecting = false;
      if (_currentToken != null) {
        connect(_currentUserId);
      }
    });
  }

  /// Inicia heartbeat: verifica periodicamente se está conectado e reconecta se necessário
  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: _heartbeatIntervalSeconds),
      (_) {
        if (_socket == null) return;
        final connected = _socket!.connected;
        if (!connected && _currentToken != null) {
          debugPrint('🔄 [WS] Heartbeat: conexão perdida, reconectando...');
          _isConnected = false;
          _onConnectionStatusChanged?.call(false);
          _handleReconnect();
          return;
        }
        if (connected) {
        }
      },
    );
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Desconecta do WebSocket
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isReconnecting = false;
    _stopHeartbeat();

    if (_socket != null) {
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
    }

    _isConnected = false;
    _onConnectionStatusChanged?.call(false);
    debugPrint('🔌 [WS] Desconectado');
  }

  /// Reconecta ao WebSocket (reconexão manual - reseta tentativas)
  Future<void> reconnect() async {
    debugPrint('🔄 [WS] Reconexão manual solicitada');
    _reconnectAttempts = 0; // Resetar tentativas ao reconectar manualmente
    _isReconnecting = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await disconnect();
    await Future.delayed(const Duration(milliseconds: 500));
    await connect(_currentUserId);
  }

  /// Inscreve-se em notificações de uma empresa
  Future<void> subscribeCompany(String companyId) async {
    if (_socket == null || !_socket!.connected) {
      debugPrint('⚠️ [WS] Socket não conectado, aguardando conexão...');
      _currentCompanyId = companyId;
      return;
    }

    _currentCompanyId = companyId;
    _socket!.emit('subscribe_company', {'companyId': companyId});
    debugPrint('📤 [WS] Inscrito na empresa: $companyId');
    _onCompanySubscribed?.call(companyId);
  }

  /// Desinscreve-se de notificações de uma empresa
  Future<void> unsubscribeCompany(String companyId) async {
    if (_socket == null || !_socket!.connected) {
      return;
    }

    _socket!.emit('unsubscribe_company', {'companyId': companyId});
    debugPrint('📤 [WS] Desinscrito da empresa: $companyId');
    _onCompanyUnsubscribed?.call(companyId);

    if (_currentCompanyId == companyId) {
      _currentCompanyId = null;
    }
  }

  /// Define callback para notificações recebidas
  void setOnNotificationReceived(Function(NotificationModel) callback) {
    _onNotificationReceived = callback;
  }

  /// Define callback para atualização de badge
  void setOnBadgeUpdate(Function(int) callback) {
    _onBadgeUpdate = callback;
  }

  /// Define callback para notificação lida
  void setOnNotificationRead(Function(String) callback) {
    _onNotificationRead = callback;
  }

  /// Define callback para mudança de status de conexão
  void setOnConnectionStatusChanged(Function(bool) callback) {
    _onConnectionStatusChanged = callback;
  }

  /// Define callback para token recusado pelo gateway (`auth_error`).
  /// Recebe `'token_invalid'` ou `'token_expired'` — o app deve disparar
  /// refresh de token ou mandar para o login.
  void setOnAuthError(Function(String) callback) {
    _onAuthError = callback;
  }

  /// Define callback para empresa inscrita
  void setOnCompanySubscribed(Function(String) callback) {
    _onCompanySubscribed = callback;
  }

  /// Define callback para empresa desinscrita
  void setOnCompanyUnsubscribed(Function(String) callback) {
    _onCompanyUnsubscribed = callback;
  }

  /// Limpa callbacks
  void clearCallbacks() {
    _onNotificationReceived = null;
    _onBadgeUpdate = null;
    _onNotificationRead = null;
    _onConnectionStatusChanged = null;
    _onCompanySubscribed = null;
    _onCompanyUnsubscribed = null;
  }
}
