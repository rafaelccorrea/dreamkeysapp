import 'package:flutter/foundation.dart';
import '../services/chat_api_service.dart';
import '../services/chat_socket_service.dart';
import '../../../shared/services/secure_storage_service.dart';
import '../../../shared/utils/jwt_utils.dart';
import '../models/chat_models.dart';

/// Controller para gerenciar contagem de mensagens não lidas do chat
class ChatUnreadController extends ChangeNotifier {
  ChatUnreadController._();

  static final ChatUnreadController _instance = ChatUnreadController._();
  static ChatUnreadController get instance => _instance;
  factory ChatUnreadController() => _instance;

  final ChatApiService _chatApi = ChatApiService.instance;
  final ChatSocketService _chatSocket = ChatSocketService.instance;

  int _totalUnreadCount = 0;
  Map<String, int> _roomUnreadCounts = {};
  String? _currentUserId;
  String? _currentlyOpenRoomId; // ID da sala que está aberta no ChatPage

  int get totalUnreadCount => _totalUnreadCount;
  Map<String, int> get roomUnreadCounts => Map.unmodifiable(_roomUnreadCounts);

  bool _isInitialized = false;

  /// Define qual sala está atualmente aberta no ChatPage
  void setCurrentlyOpenRoom(String? roomId) {
    _currentlyOpenRoomId = roomId;
  }

  /// Inicializa o controller e configura listeners
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadCurrentUserId();
    await _connectWebSocket();
    _setupWebSocketListeners();
    await _loadUnreadCounts();
    _isInitialized = true;
  }

  /// Carrega o ID do usuário atual
  Future<void> _loadCurrentUserId() async {
    try {
      final token = await SecureStorageService.instance.getAccessToken();
      if (token != null) {
        final payload = JwtUtils.decodeToken(token);
        if (payload != null) {
          _currentUserId =
              payload['sub']?.toString() ?? payload['userId']?.toString();
        }
      }
    } catch (e) {
      debugPrint('❌ [CHAT_UNREAD] Erro ao carregar userId: $e');
    }
  }

  /// Conecta ao WebSocket do chat
  Future<void> _connectWebSocket() async {
    try {
      final companyId = await SecureStorageService.instance.getCompanyId();
      if (companyId != null) {
        await _chatSocket.connect(companyId);
      }
    } catch (e) {
      debugPrint('❌ [CHAT_UNREAD] Erro ao conectar WebSocket: $e');
    }
  }

  /// Configura listeners do WebSocket
  void _setupWebSocketListeners() {
    // Quando uma nova mensagem é recebida via WebSocket
    // Este callback será chamado para TODAS as mensagens recebidas
    // Mas quando o ChatPage também chama setOnMessageReceived, este callback é substituído
    // Por isso, criamos um método público onMessageReceived que pode ser chamado externamente
    _chatSocket.setOnMessageReceived((message) {
      onMessageReceived(message);
    });
  }

  /// Método público para ser chamado quando uma mensagem é recebida
  /// Pode ser chamado tanto pelo listener do WebSocket quanto pelo ChatPage
  void onMessageReceived(ChatMessage message) {
    // Não incrementar se:
    // 1. A mensagem é do próprio usuário
    // 2. A sala está aberta no ChatPage (será marcada como lida pelo ChatPage)
    if (_currentUserId != null &&
        message.senderId != _currentUserId &&
        message.roomId != _currentlyOpenRoomId) {
      incrementUnreadCount(message.roomId);
    }
  }

  /// Carrega contagem de mensagens não lidas
  Future<void> _loadUnreadCounts() async {
    try {
      final response = await _chatApi.getRooms();
      if (response.success && response.data != null) {
        _calculateTotalUnread(response.data!);
        notifyListeners();
      } else {
        // Se a resposta não foi bem-sucedida, apenas logar o erro
        // Não falhar completamente para não interromper a inicialização do app
        debugPrint(
          '⚠️ [CHAT_UNREAD] Não foi possível carregar contagem: ${response.message}',
        );
        // Manter contagem como 0 em caso de erro
      }
    } catch (e) {
      debugPrint('❌ [CHAT_UNREAD] Erro ao carregar contagem: $e');
      // Manter contagem como 0 em caso de erro
    }
  }

  /// Calcula total de mensagens não lidas a partir das salas
  void _calculateTotalUnread(List<ChatRoom> rooms) {
    _roomUnreadCounts.clear();
    _totalUnreadCount = 0;

    for (final room in rooms) {
      final unread = room.unreadCount ?? 0;
      if (unread > 0) {
        _roomUnreadCounts[room.id] = unread;
        _totalUnreadCount += unread;
      }
    }
  }

  /// Incrementa contador de não lidas para uma sala (método público para uso externo)
  void incrementUnreadCount(String roomId) {
    _roomUnreadCounts[roomId] = (_roomUnreadCounts[roomId] ?? 0) + 1;
    _totalUnreadCount = _roomUnreadCounts.values.fold(
      0,
      (sum, count) => sum + count,
    );
    notifyListeners();
  }

  /// Marca mensagens como lidas para uma sala
  void markAsRead(String roomId) {
    if (_roomUnreadCounts.containsKey(roomId) &&
        _roomUnreadCounts[roomId]! > 0) {
      final previousCount = _roomUnreadCounts[roomId] ?? 0;
      _roomUnreadCounts[roomId] = 0;
      _totalUnreadCount -= previousCount;
      notifyListeners();
    }
  }

  /// Atualiza contagem baseado na lista de salas atualizada
  void updateFromRooms(List<ChatRoom> rooms) {
    _calculateTotalUnread(rooms);
    notifyListeners();
  }

  /// Obtém contagem para uma sala específica
  int getCountForRoom(String roomId) {
    return _roomUnreadCounts[roomId] ?? 0;
  }

  @override
  void dispose() {
    _isInitialized = false;
    super.dispose();
  }
}
