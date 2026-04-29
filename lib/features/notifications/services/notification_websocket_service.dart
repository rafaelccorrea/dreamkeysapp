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
  Function(String)? _onCompanySubscribed;
  Function(String)? _onCompanyUnsubscribed;

  // Reconexão
  int _reconnectAttempts = 0;
  static const int _baseReconnectDelay = 1000; // 1 segundo
  static const int _maxReconnectDelay = 30000; // 30 segundos
  static const int _maxReconnectAttempts = 5; // Máximo de 5 tentativas
  Timer? _reconnectTimer;
  bool _isReconnecting = false;

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

      _currentToken = token;
      _currentUserId = userId;

      // Se já está conectado, desconectar primeiro
      if (_socket != null && _socket!.connected) {
        await disconnect();
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

    // Nova notificação
    _socket!.on('notification', (data) {
      try {
        debugPrint('📨 [WS] Nova notificação recebida');
        final notification = NotificationModel.fromJson(
          data as Map<String, dynamic>,
        );
        _onNotificationReceived?.call(notification);
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
      _onConnectionStatusChanged?.call(false);
      
      // Se foi desconexão intencional do cliente (io client disconnect), não tentar reconectar
      if (reason.toString().contains('io client disconnect')) {
        debugPrint('ℹ️ [WS] Desconexão intencional do cliente, não tentando reconectar');
        _reconnectAttempts = 0; // Resetar tentativas
        return;
      }
      
      // Tentar reconectar apenas se não excedeu o limite
      if (_reconnectAttempts < _maxReconnectAttempts) {
        _handleReconnect();
      } else {
        debugPrint('⚠️ [WS] Limite de tentativas de reconexão atingido ($_maxReconnectAttempts). Parando tentativas automáticas.');
        _isReconnecting = false;
      }
    });

    // Erro de conexão
    _socket!.onConnectError((error) {
      debugPrint('❌ [WS] Erro de conexão: $error');
      _isConnected = false;
      _onConnectionStatusChanged?.call(false);
      
      // Tentar reconectar apenas se não excedeu o limite
      if (_reconnectAttempts < _maxReconnectAttempts) {
        _handleReconnect();
      } else {
        debugPrint('⚠️ [WS] Limite de tentativas de reconexão atingido ($_maxReconnectAttempts). Parando tentativas automáticas.');
        _isReconnecting = false;
      }
    });

    // Erro geral
    _socket!.onError((error) {
      debugPrint('❌ [WS] Erro: $error');
    });
  }

  /// Reconexão automática com exponential backoff
  void _handleReconnect() {
    // Verificar se já excedeu o limite de tentativas
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('⚠️ [WS] Limite de tentativas de reconexão atingido. Parando tentativas automáticas.');
      _isReconnecting = false;
      return;
    }

    // Verificar se já está tentando reconectar
    if (_reconnectTimer != null && _reconnectTimer!.isActive) {
      return; // Já está tentando reconectar
    }

    if (_isReconnecting) {
      return; // Já está em processo de reconexão
    }

    _isReconnecting = true;
    _reconnectAttempts++;

    // Exponential backoff: 1s, 2s, 4s, 8s, ... até 30s
    final exponentialDelay = _baseReconnectDelay * (1 << (_reconnectAttempts - 1));
    final delay = exponentialDelay > _maxReconnectDelay
        ? _maxReconnectDelay
        : exponentialDelay;

    debugPrint('🔄 [WS] Tentando reconectar em ${delay}ms (tentativa $_reconnectAttempts/$_maxReconnectAttempts)');

    _reconnectTimer = Timer(Duration(milliseconds: delay), () {
      _reconnectTimer = null;
      if (_currentToken != null && _reconnectAttempts <= _maxReconnectAttempts) {
        connect(_currentUserId);
      } else {
        _isReconnecting = false;
        debugPrint('⚠️ [WS] Não é possível reconectar: token ausente ou limite atingido');
      }
    });
  }

  /// Desconecta do WebSocket
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isReconnecting = false;
    // Não resetar _reconnectAttempts aqui para manter o histórico de tentativas

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
