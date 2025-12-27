import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import '../../../core/constants/api_constants.dart';
import '../../../shared/services/secure_storage_service.dart';
import '../models/notification_model.dart';

/// Callbacks para eventos do WebSocket
typedef NotificationReceivedCallback = void Function(NotificationModel notification);
typedef BadgeUpdateCallback = void Function(int unreadCount);
typedef NotificationReadCallback = void Function(String notificationId);
typedef CompanySubscribedCallback = void Function(String companyId);
typedef CompanyUnsubscribedCallback = void Function(String companyId);
typedef ConnectionStatusCallback = void Function(bool connected);

/// Serviço WebSocket para notificações em tempo real
class NotificationWebSocketService {
  NotificationWebSocketService._();

  static final NotificationWebSocketService instance =
      NotificationWebSocketService._();

  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _reconnectDisabled = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  int _serverErrorCount = 0;
  static const int _maxReconnectAttempts = 5;
  static const int _maxServerErrors = 3;
  static const Duration _initialReconnectDelay = Duration(seconds: 2);
  static const Duration _maxReconnectDelay = Duration(seconds: 30);
  String? _userId;
  final List<String> _subscribedCompanies = [];

  // Callbacks
  NotificationReceivedCallback? _onNotificationReceived;
  BadgeUpdateCallback? _onBadgeUpdate;
  NotificationReadCallback? _onNotificationRead;
  CompanySubscribedCallback? _onCompanySubscribed;
  CompanyUnsubscribedCallback? _onCompanyUnsubscribed;
  ConnectionStatusCallback? _onConnectionStatusChanged;

  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;

  /// Define callback para quando uma notificação é recebida
  void setOnNotificationReceived(NotificationReceivedCallback? callback) {
    _onNotificationReceived = callback;
  }

  /// Define callback para atualização do badge
  void setOnBadgeUpdate(BadgeUpdateCallback? callback) {
    _onBadgeUpdate = callback;
  }

  /// Define callback para notificação lida
  void setOnNotificationRead(NotificationReadCallback? callback) {
    _onNotificationRead = callback;
  }

  /// Define callback para empresa inscrita
  void setOnCompanySubscribed(CompanySubscribedCallback? callback) {
    _onCompanySubscribed = callback;
  }

  /// Define callback para empresa desinscrita
  void setOnCompanyUnsubscribed(CompanyUnsubscribedCallback? callback) {
    _onCompanyUnsubscribed = callback;
  }

  /// Define callback para mudança de status de conexão
  void setOnConnectionStatusChanged(ConnectionStatusCallback? callback) {
    _onConnectionStatusChanged = callback;
  }

  /// Conecta ao WebSocket
  Future<void> connect(String userId) async {
    if (_isConnecting || _isConnected || _reconnectDisabled) {
      return;
    }

    _userId = userId;
    _isConnecting = true;
    _reconnectAttempts = 0;

    await runZonedGuarded(() async {
      try {
        final token = await SecureStorageService.instance.getAccessToken();
        if (token == null || token.isEmpty) {
          _isConnecting = false;
          return;
        }

        // Construir URI do WebSocket explicitamente
        final baseUri = Uri.parse(ApiConstants.baseUrl);
        final wsUri = Uri(
          scheme: baseUri.scheme == 'https' ? 'wss' : 'ws',
          host: baseUri.host,
          port: baseUri.hasPort && baseUri.port != 443 && baseUri.port != 80 
              ? baseUri.port 
              : null,
          path: '/notifications',
        );

        _channel = IOWebSocketChannel.connect(
          wsUri,
          headers: {'Authorization': 'Bearer $token'},
        );

        _channel!.stream.listen(
          _handleMessage,
          onError: (error) {
            _handleError(error);
          },
          onDone: () {
            _handleDone();
          },
          cancelOnError: false,
        );

        await Future.delayed(const Duration(milliseconds: 500));

        if (_channel == null) {
          throw Exception('Conexão WebSocket falhou');
        }

        _sendJoin(userId);
        _isConnected = true;
        _isConnecting = false;
        _reconnectAttempts = 0;
        _serverErrorCount = 0;
        _onConnectionStatusChanged?.call(true);
      } catch (e) {
        _handleConnectionError(e);
      }
    }, (error, stack) {
      _handleConnectionError(error);
    });
  }

  /// Trata erros de conexão
  void _handleConnectionError(dynamic error) {
    _isConnecting = false;
    _isConnected = false;
    _onConnectionStatusChanged?.call(false);
    
    final errorStr = error.toString();
    // Verificar se é erro de servidor e desabilitar imediatamente
    if (errorStr.contains('502') || 
        errorStr.contains('503') ||
        errorStr.contains('Bad Gateway') ||
        errorStr.contains('Service Unavailable')) {
      _serverErrorCount++;
      if (_serverErrorCount >= _maxServerErrors) {
        _reconnectDisabled = true;
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        return;
      }
    }
    
    if (!_reconnectDisabled) {
      _scheduleReconnect();
    }
  }

  /// Desconecta do WebSocket
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    _reconnectDisabled = false;
    _serverErrorCount = 0;

    try {
      await _channel?.sink.close();
    } catch (e) {
      // Ignorar erros ao fechar
    }

    _channel = null;
    _isConnected = false;
    _isConnecting = false;
    _onConnectionStatusChanged?.call(false);
    _subscribedCompanies.clear();
  }

  /// Inscreve-se para notificações de uma empresa
  void subscribeCompany(String companyId) {
    if (!_isConnected || _channel == null || _subscribedCompanies.contains(companyId)) {
      return;
    }

    try {
      _sendEvent('subscribe_company', {'companyId': companyId});
      _subscribedCompanies.add(companyId);
    } catch (e) {
      // Ignorar erros
    }
  }

  /// Cancela inscrição de notificações de uma empresa
  void unsubscribeCompany(String companyId) {
    if (!_isConnected || _channel == null || !_subscribedCompanies.contains(companyId)) {
      return;
    }

    try {
      _sendEvent('unsubscribe_company', {'companyId': companyId});
      _subscribedCompanies.remove(companyId);
    } catch (e) {
      // Ignorar erros
    }
  }

  /// Envia evento de join
  void _sendJoin(String userId) {
    _sendEvent('join', userId);
  }

  /// Envia um evento
  void _sendEvent(String event, dynamic data) {
    if (!_isConnected || _channel == null) {
      return;
    }

    try {
      _channel!.sink.add(jsonEncode({
        'event': event,
        'data': data,
      }));
    } catch (e) {
      // Ignorar erros
    }
  }

  /// Trata mensagens recebidas
  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message.toString());
      final event = data['event']?.toString() ?? data['type']?.toString();

      if (event == null) return;

      switch (event) {
        case 'notifications_connected':
          _handleConnected(data);
          break;
        case 'notification':
          _handleNotification(data);
          break;
        case 'badge_update':
          _handleBadgeUpdate(data);
          break;
        case 'notification_read':
          _handleNotificationRead(data);
          break;
        case 'company_subscribed':
          _handleCompanySubscribed(data);
          break;
        case 'company_unsubscribed':
          _handleCompanyUnsubscribed(data);
          break;
      }
    } catch (e) {
      // Ignorar erros de parsing
    }
  }

  /// Trata evento de conexão estabelecida
  void _handleConnected(dynamic data) {
    // Conexão confirmada
  }

  /// Trata nova notificação
  void _handleNotification(dynamic data) {
    try {
      final notificationData = data['data'] ?? data;
      final notification = NotificationModel.fromJson(
        notificationData is Map<String, dynamic>
            ? notificationData
            : jsonDecode(notificationData.toString()),
      );
      _onNotificationReceived?.call(notification);
    } catch (e) {
      // Ignorar erros
    }
  }

  /// Trata atualização de badge
  void _handleBadgeUpdate(dynamic data) {
    try {
      final badgeData = data['data'] ?? data;
      final unreadCount = (badgeData is Map<String, dynamic>
              ? badgeData['unreadCount']
              : badgeData) as int? ??
          0;
      _onBadgeUpdate?.call(unreadCount);
    } catch (e) {
      // Ignorar erros
    }
  }

  /// Trata notificação lida
  void _handleNotificationRead(dynamic data) {
    try {
      final readData = data['data'] ?? data;
      final notificationId = (readData is Map<String, dynamic>
              ? readData['notificationId']
              : readData) as String? ??
          '';
      _onNotificationRead?.call(notificationId);
    } catch (e) {
      // Ignorar erros
    }
  }

  /// Trata empresa inscrita
  void _handleCompanySubscribed(dynamic data) {
    try {
      final subData = data['data'] ?? data;
      final companyId = (subData is Map<String, dynamic>
              ? subData['companyId']
              : subData) as String? ??
          '';
      _onCompanySubscribed?.call(companyId);
    } catch (e) {
      // Ignorar erros
    }
  }

  /// Trata empresa desinscrita
  void _handleCompanyUnsubscribed(dynamic data) {
    try {
      final unsubData = data['data'] ?? data;
      final companyId = (unsubData is Map<String, dynamic>
              ? unsubData['companyId']
              : unsubData) as String? ??
          '';
      _onCompanyUnsubscribed?.call(companyId);
    } catch (e) {
      // Ignorar erros
    }
  }

  /// Trata erros
  void _handleError(dynamic error) {
    _isConnected = false;
    _isConnecting = false;
    _onConnectionStatusChanged?.call(false);
    
    // Verificar se é erro de servidor (502, 503, etc)
    final errorStr = error.toString();
    if (errorStr.contains('502') || 
        errorStr.contains('503') || 
        errorStr.contains('Bad Gateway') ||
        errorStr.contains('Service Unavailable')) {
      _serverErrorCount++;
      
      // Desabilitar reconexão após muitos erros de servidor
      if (_serverErrorCount >= _maxServerErrors) {
        _reconnectDisabled = true;
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        return;
      }
    }
    
    if (!_reconnectDisabled) {
      _scheduleReconnect();
    }
  }

  /// Trata desconexão
  void _handleDone() {
    _isConnected = false;
    _onConnectionStatusChanged?.call(false);
    
    if (!_reconnectDisabled) {
      _scheduleReconnect();
    }
  }

  /// Agenda reconexão com exponential backoff
  void _scheduleReconnect() {
    if (_reconnectDisabled || _reconnectAttempts >= _maxReconnectAttempts) {
      if (_reconnectAttempts >= _maxReconnectAttempts) {
        _reconnectDisabled = true;
      }
      return;
    }

    _reconnectTimer?.cancel();

    final delay = Duration(
      milliseconds: (_initialReconnectDelay.inMilliseconds *
              (1 << _reconnectAttempts))
          .clamp(
            _initialReconnectDelay.inMilliseconds,
            _maxReconnectDelay.inMilliseconds,
          ),
    );

    _reconnectAttempts++;
    _reconnectTimer = Timer(delay, () {
      if (_userId != null && !_reconnectDisabled && !_isConnecting) {
        connect(_userId!);
      }
    });
  }

  /// Reconecta manualmente
  Future<void> reconnect() async {
    _reconnectDisabled = false;
    _serverErrorCount = 0;
    _reconnectAttempts = 0;
    if (_userId != null) {
      await disconnect();
      await connect(_userId!);
    }
  }
}


