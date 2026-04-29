import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../../../core/constants/api_constants.dart';
import '../../../shared/services/secure_storage_service.dart';
import '../models/chat_models.dart';

/// Serviço para conexão WebSocket de chat em tempo real
class ChatSocketService {
  ChatSocketService._();

  static final ChatSocketService _instance = ChatSocketService._();

  factory ChatSocketService() => _instance;

  static ChatSocketService get instance => _instance;

  IO.Socket? _socket;
  bool _isConnected = false;
  String? _currentCompanyId;
  final Set<String> _joinedRooms = <String>{};

  // Callbacks
  Function(ChatMessage)? _onMessageReceived;
  Function(String)? _onMessageSent;
  Function(String, String)? _onMessagesRead;
  Function(String, ChatMessageStatus)? _onMessageStatusUpdate;
  Function(String, ChatMessage)? _onMessageEdited;
  Function(String, String)? _onMessageDeleted;
  Function(String)? _onRoomJoined;
  Function(String)? _onRoomLeft;
  Function(String, String, String, String?, String?, String?)? _onParticipantAdded;
  Function(String, String, String, String?, String?, bool)? _onParticipantLeft;
  Function(String, String, String, String, String)? _onParticipantRemoved;
  Function(String, String?, String?)? _onRoomUpdated;
  Function(bool)? _onConnectionStatusChanged;
  Function(String)? _onError;

  // Reconexão
  int _reconnectAttempts = 0;
  static const int _baseReconnectDelay = 5000; // 5 segundos
  static const int _maxReconnectDelay = 30000; // 30 segundos
  static const int _maxReconnectAttempts = 3; // Máximo de 3 tentativas
  Timer? _reconnectTimer;
  bool _isReconnecting = false;

  bool get isConnected => _isConnected;
  Set<String> get joinedRooms => Set.unmodifiable(_joinedRooms);

  /// Conecta ao WebSocket do chat
  Future<void> connect(String companyId) async {
    try {
      // Obter token
      final token = await SecureStorageService.instance.getAccessToken();
      if (token == null || token.isEmpty) {
        debugPrint('⚠️ [CHAT_WS] Token não encontrado, não é possível conectar');
        return;
      }

      _currentCompanyId = companyId;

      // Se já está conectado, desconectar primeiro
      if (_socket != null && _socket!.connected) {
        await disconnect();
      }

      // Construir URL do WebSocket
      final wsUrl = _getWebSocketUrl();
      debugPrint('🔄 [CHAT_WS] Conectando ao WebSocket: $wsUrl');

      // Criar socket
      _socket = IO.io(
        wsUrl,
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .setAuth({'token': token})
            .setExtraHeaders({'X-Company-ID': companyId})
            .setTimeout(20000)
            .build(),
      );

      // Configurar event handlers
      _setupEventHandlers();

      // Conectar manualmente
      _socket!.connect();
    } catch (e, stackTrace) {
      debugPrint('❌ [CHAT_WS] Erro ao conectar: $e');
      debugPrint('📚 [CHAT_WS] StackTrace: $stackTrace');
      _handleReconnect();
    }
  }

  /// Obtém URL do WebSocket
  String _getWebSocketUrl() {
    final baseUrl = ApiConstants.baseUrl;
    if (baseUrl.startsWith('https://')) {
      return '${baseUrl.replaceFirst('https://', 'wss://')}/chat';
    } else if (baseUrl.startsWith('http://')) {
      return '${baseUrl.replaceFirst('http://', 'ws://')}/chat';
    }
    return '$baseUrl/chat';
  }

  /// Configura event handlers do WebSocket
  void _setupEventHandlers() {
    if (_socket == null) return;

    // Conectado
    _socket!.onConnect((_) {
      debugPrint('✅ [CHAT_WS] Conectado ao WebSocket de chat');
      _isConnected = true;
      _reconnectAttempts = 0;
      _isReconnecting = false;
      _onConnectionStatusChanged?.call(true);

      // Se tiver Company ID, definir
      if (_currentCompanyId != null && _currentCompanyId!.isNotEmpty) {
        _socket!.emit('set_company_id', {'companyId': _currentCompanyId});
      }

      // Reconectar em todas as salas que estavam conectadas antes
      for (final roomId in _joinedRooms) {
        joinRoom(roomId);
      }
    });

    // Confirmação de conexão do servidor
    _socket!.on('chat_connected', (data) {
      debugPrint('✅ [CHAT_WS] Confirmação de conexão recebida: $data');
    });

    // Nova mensagem
    _socket!.on('new_message', (data) {
      try {
        debugPrint('📨 [CHAT_WS] Nova mensagem recebida');
        final messageData = data as Map<String, dynamic>;
        final message = ChatMessage.fromJson(
          messageData['message'] as Map<String, dynamic>,
        );
        _onMessageReceived?.call(message);
      } catch (e, stackTrace) {
        debugPrint('❌ [CHAT_WS] Erro ao processar nova mensagem: $e');
        debugPrint('📚 [CHAT_WS] StackTrace: $stackTrace');
      }
    });

    // Confirmação de envio de mensagem
    _socket!.on('message_sent', (data) {
      try {
        final messageId = (data as Map<String, dynamic>)['messageId'] as String?;
        if (messageId != null) {
          debugPrint('✅ [CHAT_WS] Mensagem enviada: $messageId');
          _onMessageSent?.call(messageId);
        }
      } catch (e, stackTrace) {
        debugPrint('❌ [CHAT_WS] Erro ao processar message_sent: $e');
        debugPrint('📚 [CHAT_WS] StackTrace: $stackTrace');
      }
    });

    // Mensagens marcadas como lidas
    _socket!.on('messages_read', (data) {
      try {
        final dataMap = data as Map<String, dynamic>;
        final roomId = dataMap['roomId'] as String?;
        final userId = dataMap['userId'] as String?;
        if (roomId != null && userId != null) {
          debugPrint('✅ [CHAT_WS] Mensagens marcadas como lidas: $roomId');
          _onMessagesRead?.call(roomId, userId);
        }
      } catch (e, stackTrace) {
        debugPrint('❌ [CHAT_WS] Erro ao processar messages_read: $e');
        debugPrint('📚 [CHAT_WS] StackTrace: $stackTrace');
      }
    });

    // Atualização de status de mensagem
    _socket!.on('message_status_update', (data) {
      try {
        final dataMap = data as Map<String, dynamic>;
        final messageId = dataMap['messageId'] as String?;
        final statusStr = dataMap['status'] as String?;
        if (messageId != null && statusStr != null) {
          final status = ChatMessageStatus.fromString(statusStr);
          debugPrint('🔄 [CHAT_WS] Status atualizado: $messageId -> $statusStr');
          _onMessageStatusUpdate?.call(messageId, status);
        }
      } catch (e, stackTrace) {
        debugPrint('❌ [CHAT_WS] Erro ao processar message_status_update: $e');
        debugPrint('📚 [CHAT_WS] StackTrace: $stackTrace');
      }
    });

    // Mensagem editada
    _socket!.on('message_edited', (data) {
      try {
        final dataMap = data as Map<String, dynamic>;
        final roomId = dataMap['roomId'] as String?;
        final newMessageData = dataMap['newMessage'] as Map<String, dynamic>?;
        if (roomId != null && newMessageData != null) {
          final message = ChatMessage.fromJson(newMessageData);
          debugPrint('✏️ [CHAT_WS] Mensagem editada: ${message.id}');
          _onMessageEdited?.call(roomId, message);
        }
      } catch (e, stackTrace) {
        debugPrint('❌ [CHAT_WS] Erro ao processar message_edited: $e');
        debugPrint('📚 [CHAT_WS] StackTrace: $stackTrace');
      }
    });

    // Mensagem deletada
    _socket!.on('message_deleted', (data) {
      try {
        final dataMap = data as Map<String, dynamic>;
        final roomId = dataMap['roomId'] as String?;
        final messageId = dataMap['messageId'] as String?;
        if (roomId != null && messageId != null) {
          debugPrint('🗑️ [CHAT_WS] Mensagem deletada: $messageId');
          _onMessageDeleted?.call(roomId, messageId);
        }
      } catch (e, stackTrace) {
        debugPrint('❌ [CHAT_WS] Erro ao processar message_deleted: $e');
        debugPrint('📚 [CHAT_WS] StackTrace: $stackTrace');
      }
    });

    // Sala foi entrada
    _socket!.on('room_joined', (data) {
      try {
        final roomId = (data as Map<String, dynamic>)['roomId'] as String?;
        if (roomId != null) {
          debugPrint('✅ [CHAT_WS] Entrou na sala: $roomId');
          _joinedRooms.add(roomId);
          _onRoomJoined?.call(roomId);
        }
      } catch (e, stackTrace) {
        debugPrint('❌ [CHAT_WS] Erro ao processar room_joined: $e');
        debugPrint('📚 [CHAT_WS] StackTrace: $stackTrace');
      }
    });

    // Sala foi saída
    _socket!.on('room_left', (data) {
      try {
        final roomId = (data as Map<String, dynamic>)['roomId'] as String?;
        if (roomId != null) {
          debugPrint('👋 [CHAT_WS] Saiu da sala: $roomId');
          _joinedRooms.remove(roomId);
          _onRoomLeft?.call(roomId);
        }
      } catch (e, stackTrace) {
        debugPrint('❌ [CHAT_WS] Erro ao processar room_left: $e');
        debugPrint('📚 [CHAT_WS] StackTrace: $stackTrace');
      }
    });

    // Participante foi adicionado
    _socket!.on('participant_added', (data) {
      try {
        final dataMap = data as Map<String, dynamic>;
        final roomId = dataMap['roomId'] as String?;
        final userId = dataMap['userId'] as String?;
        final userName = dataMap['userName'] as String?;
        final userAvatar = dataMap['userAvatar'] as String?;
        final addedBy = dataMap['addedBy'] as String?;
        final addedByName = dataMap['addedByName'] as String?;
        if (roomId != null && userId != null && userName != null) {
          debugPrint('➕ [CHAT_WS] Participante adicionado: $userName');
          _onParticipantAdded?.call(roomId, userId, userName, userAvatar, addedBy, addedByName);
        }
      } catch (e, stackTrace) {
        debugPrint('❌ [CHAT_WS] Erro ao processar participant_added: $e');
        debugPrint('📚 [CHAT_WS] StackTrace: $stackTrace');
      }
    });

    // Participante saiu
    _socket!.on('participant_left', (data) {
      try {
        final dataMap = data as Map<String, dynamic>;
        final roomId = dataMap['roomId'] as String?;
        final userId = dataMap['userId'] as String?;
        final userName = dataMap['userName'] as String?;
        final removedBy = dataMap['removedBy'] as String?;
        final removedByName = dataMap['removedByName'] as String?;
        final isRemoved = dataMap['isRemoved'] as bool? ?? false;
        if (roomId != null && userId != null && userName != null) {
          debugPrint('👋 [CHAT_WS] Participante saiu: $userName');
          _onParticipantLeft?.call(roomId, userId, userName, removedBy, removedByName, isRemoved);
        }
      } catch (e, stackTrace) {
        debugPrint('❌ [CHAT_WS] Erro ao processar participant_left: $e');
        debugPrint('📚 [CHAT_WS] StackTrace: $stackTrace');
      }
    });

    // Participante foi removido
    _socket!.on('participant_removed', (data) {
      try {
        final dataMap = data as Map<String, dynamic>;
        final roomId = dataMap['roomId'] as String?;
        final userId = dataMap['userId'] as String?;
        final userName = dataMap['userName'] as String?;
        final removedBy = dataMap['removedBy'] as String?;
        final removedByName = dataMap['removedByName'] as String?;
        if (roomId != null && userId != null && userName != null) {
          debugPrint('❌ [CHAT_WS] Participante removido: $userName');
          if (removedBy != null && removedByName != null) {
            _onParticipantRemoved?.call(roomId, userId, userName, removedBy, removedByName);
          }
        }
      } catch (e, stackTrace) {
        debugPrint('❌ [CHAT_WS] Erro ao processar participant_removed: $e');
        debugPrint('📚 [CHAT_WS] StackTrace: $stackTrace');
      }
    });

    // Sala foi atualizada
    _socket!.on('room_updated', (data) {
      try {
        final dataMap = data as Map<String, dynamic>;
        final roomId = dataMap['roomId'] as String?;
        final name = dataMap['name'] as String?;
        final imageUrl = dataMap['imageUrl'] as String?;
        if (roomId != null) {
          debugPrint('🔄 [CHAT_WS] Sala atualizada: $roomId');
          _onRoomUpdated?.call(roomId, name, imageUrl);
        }
      } catch (e, stackTrace) {
        debugPrint('❌ [CHAT_WS] Erro ao processar room_updated: $e');
        debugPrint('📚 [CHAT_WS] StackTrace: $stackTrace');
      }
    });

    // Desconectado
    _socket!.onDisconnect((reason) {
      debugPrint('❌ [CHAT_WS] Desconectado: $reason');
      _isConnected = false;
      _joinedRooms.clear();
      _onConnectionStatusChanged?.call(false);

      // Se foi desconexão intencional do cliente, não tentar reconectar
      if (reason.toString().contains('io client disconnect')) {
        debugPrint('ℹ️ [CHAT_WS] Desconexão intencional do cliente, não tentando reconectar');
        _reconnectAttempts = 0;
        return;
      }

      // Tentar reconectar apenas se não excedeu o limite
      if (_reconnectAttempts < _maxReconnectAttempts) {
        _handleReconnect();
      } else {
        debugPrint('⚠️ [CHAT_WS] Limite de tentativas de reconexão atingido ($_maxReconnectAttempts). Entrando em cooldown de 30s.');
        _isReconnecting = false;
        // Após 30s, permitir novas tentativas
        Future.delayed(const Duration(seconds: 30), () {
          _reconnectAttempts = 0;
        });
      }
    });

    // Erro de conexão
    _socket!.onConnectError((error) {
      debugPrint('❌ [CHAT_WS] Erro de conexão: $error');
      _isConnected = false;
      _onConnectionStatusChanged?.call(false);

      // Tentar reconectar apenas se não excedeu o limite
      if (_reconnectAttempts < _maxReconnectAttempts) {
        _handleReconnect();
      } else {
        debugPrint('⚠️ [CHAT_WS] Limite de tentativas de reconexão atingido ($_maxReconnectAttempts). Entrando em cooldown de 30s.');
        _isReconnecting = false;
        // Após 30s, permitir novas tentativas
        Future.delayed(const Duration(seconds: 30), () {
          _reconnectAttempts = 0;
        });
      }
    });

    // Erro geral
    _socket!.onError((error) {
      debugPrint('❌ [CHAT_WS] Erro: $error');
      _onError?.call(error.toString());
    });
  }

  /// Reconecta ao WebSocket
  void _handleReconnect() {
    if (_isReconnecting) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('⚠️ [CHAT_WS] Máximo de tentativas atingido, não tentando reconectar');
      return;
    }

    _isReconnecting = true;
    _reconnectAttempts++;

    final delay = (_baseReconnectDelay * _reconnectAttempts).clamp(
      _baseReconnectDelay,
      _maxReconnectDelay,
    );

    debugPrint('🔄 [CHAT_WS] Tentando reconectar em ${delay}ms (tentativa $_reconnectAttempts/$_maxReconnectAttempts)');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delay), () {
      if (_currentCompanyId != null) {
        connect(_currentCompanyId!);
      }
    });
  }

  /// Desconecta do WebSocket
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isReconnecting = false;

    if (_socket != null) {
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
    }

    _isConnected = false;
    _joinedRooms.clear();
    debugPrint('🔌 [CHAT_WS] Desconectado');
  }

  /// Reconecta ao WebSocket (reconexão manual - reseta tentativas)
  Future<void> reconnect() async {
    debugPrint('🔄 [CHAT_WS] Reconexão manual solicitada');
    _reconnectAttempts = 0;
    _isReconnecting = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await disconnect();
    await Future.delayed(const Duration(milliseconds: 500));
    if (_currentCompanyId != null) {
      await connect(_currentCompanyId!);
    }
  }

  /// Entra em uma sala
  void joinRoom(String roomId) {
    if (_socket == null || !_socket!.connected) {
      debugPrint('⚠️ [CHAT_WS] Socket não conectado, não é possível entrar na sala');
      _joinedRooms.add(roomId); // Adicionar à lista para reconectar depois
      return;
    }

    if (_currentCompanyId == null) {
      debugPrint('⚠️ [CHAT_WS] Company ID não definido');
      return;
    }

    _socket!.emit('join_room', {
      'roomId': roomId,
      'companyId': _currentCompanyId,
    });
    debugPrint('📤 [CHAT_WS] Entrando na sala: $roomId');
  }

  /// Sai de uma sala
  void leaveRoom(String roomId) {
    if (_socket == null || !_socket!.connected) {
      debugPrint('⚠️ [CHAT_WS] Socket não conectado');
      _joinedRooms.remove(roomId);
      return;
    }

    if (_currentCompanyId == null) {
      debugPrint('⚠️ [CHAT_WS] Company ID não definido');
      return;
    }

    _socket!.emit('leave_room', {
      'roomId': roomId,
      'companyId': _currentCompanyId,
    });
    _joinedRooms.remove(roomId);
    debugPrint('📤 [CHAT_WS] Saindo da sala: $roomId');
  }

  /// Envia mensagem via WebSocket (apenas texto)
  void sendMessage(String roomId, String content) {
    if (_socket == null || !_socket!.connected) {
      debugPrint('⚠️ [CHAT_WS] Socket não conectado, não é possível enviar mensagem');
      return;
    }

    if (_currentCompanyId == null) {
      debugPrint('⚠️ [CHAT_WS] Company ID não definido');
      return;
    }

    _socket!.emit('send_message', {
      'roomId': roomId,
      'content': content,
      'companyId': _currentCompanyId,
    });
    debugPrint('📤 [CHAT_WS] Enviando mensagem para sala: $roomId');
  }

  /// Marca mensagens como lidas
  void markAsRead(String roomId) {
    if (_socket == null || !_socket!.connected) {
      debugPrint('⚠️ [CHAT_WS] Socket não conectado, não é possível marcar como lida');
      return;
    }

    if (_currentCompanyId == null) {
      debugPrint('⚠️ [CHAT_WS] Company ID não definido');
      return;
    }

    _socket!.emit('mark_as_read', {
      'roomId': roomId,
      'companyId': _currentCompanyId,
    });
    debugPrint('📤 [CHAT_WS] Marcando mensagens como lidas: $roomId');
  }

  /// Define callback para mensagens recebidas
  void setOnMessageReceived(Function(ChatMessage) callback) {
    _onMessageReceived = callback;
  }

  /// Define callback para mensagem enviada
  void setOnMessageSent(Function(String) callback) {
    _onMessageSent = callback;
  }

  /// Define callback para mensagens lidas
  void setOnMessagesRead(Function(String, String) callback) {
    _onMessagesRead = callback;
  }

  /// Define callback para atualização de status
  void setOnMessageStatusUpdate(Function(String, ChatMessageStatus) callback) {
    _onMessageStatusUpdate = callback;
  }

  /// Define callback para mensagem editada
  void setOnMessageEdited(Function(String, ChatMessage) callback) {
    _onMessageEdited = callback;
  }

  /// Define callback para mensagem deletada
  void setOnMessageDeleted(Function(String, String) callback) {
    _onMessageDeleted = callback;
  }

  /// Define callback para sala entrada
  void setOnRoomJoined(Function(String) callback) {
    _onRoomJoined = callback;
  }

  /// Define callback para sala saída
  void setOnRoomLeft(Function(String) callback) {
    _onRoomLeft = callback;
  }

  /// Define callback para participante adicionado
  void setOnParticipantAdded(
    Function(String, String, String, String?, String?, String?) callback,
  ) {
    _onParticipantAdded = callback;
  }

  /// Define callback para participante saiu
  void setOnParticipantLeft(
    Function(String, String, String, String?, String?, bool) callback,
  ) {
    _onParticipantLeft = callback;
  }

  /// Define callback para participante removido
  void setOnParticipantRemoved(
    Function(String, String, String, String, String) callback,
  ) {
    _onParticipantRemoved = callback;
  }

  /// Define callback para sala atualizada
  void setOnRoomUpdated(Function(String, String?, String?) callback) {
    _onRoomUpdated = callback;
  }

  /// Define callback para mudança de status de conexão
  void setOnConnectionStatusChanged(Function(bool) callback) {
    _onConnectionStatusChanged = callback;
  }

  /// Define callback para erros
  void setOnError(Function(String) callback) {
    _onError = callback;
  }
}

