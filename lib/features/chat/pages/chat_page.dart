import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/app_bottom_navigation.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/routes/app_routes.dart';
import '../../../shared/services/secure_storage_service.dart';
import '../../../shared/services/profile_service.dart';
import '../../../shared/utils/jwt_utils.dart';
import '../models/chat_models.dart';
import '../services/chat_api_service.dart';
import '../services/chat_socket_service.dart';
import '../controllers/chat_unread_controller.dart';
import '../widgets/chat_room_list_item.dart';
import '../widgets/chat_message_list.dart';
import '../widgets/chat_input.dart';

/// Página principal do chat
class ChatPage extends StatefulWidget {
  final String? roomId;

  const ChatPage({super.key, this.roomId});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with SingleTickerProviderStateMixin {
  final ChatApiService _chatApi = ChatApiService.instance;
  final ChatSocketService _chatSocket = ChatSocketService.instance;
  
  List<ChatRoom> _allRooms = [];
  List<ChatRoom> _archivedRooms = [];
  ChatRoom? _selectedRoom;
  List<ChatMessage> _messages = [];
  List<CompanyUser> _companyUsers = [];
  String? _currentUserId;
  bool _isLoadingRooms = true;
  bool _isLoadingMessages = false;
  bool _isLoadingUsers = false;
  String? _errorMessage;
  
  int _messageOffset = 0;
  static const int _messagesLimit = 50;
  final ScrollController _messagesScrollController = ScrollController();
  late TabController _tabController;

  List<ChatRoom> get _rooms {
    List<ChatRoom> rooms;
    switch (_tabController.index) {
      case 0: // Todas
        rooms = _allRooms.where((r) => r.isArchived != true).toList();
        break;
      case 1: // Arquivadas
        rooms = _archivedRooms;
        break;
      default:
        rooms = _allRooms.where((r) => r.isArchived != true).toList();
    }
    // Ordenar por data da última mensagem (mais recente primeiro)
    rooms.sort((a, b) {
      final aDate = a.lastMessageAt ?? a.createdAt;
      final bDate = b.lastMessageAt ?? b.createdAt;
      return bDate.compareTo(aDate); // Ordem decrescente (mais recente primeiro)
    });
    return rooms;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this); // Adicionada tab de Colaboradores
    _tabController.addListener(_onTabChanged);
    _initialize();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    
    // Se mudou para a tab de colaboradores, carregar lista de usuários
    if (_tabController.index == 2 && _companyUsers.isEmpty) {
      _loadCompanyUsers();
    }
    
    setState(() {}); // Atualizar lista baseado na tab
  }
  
  Future<void> _loadCompanyUsers() async {
    setState(() {
      _isLoadingUsers = true;
    });
    
    try {
      final response = await _chatApi.getCompanyUsers();
      if (response.success && response.data != null) {
        setState(() {
          // Filtrar o usuário atual da lista
          _companyUsers = response.data!.where((u) => u.id != _currentUserId).toList();
          // Ordenar por nome
          _companyUsers.sort((a, b) => a.name.compareTo(b.name));
          _isLoadingUsers = false;
        });
      } else {
        setState(() {
          _isLoadingUsers = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoadingUsers = false;
      });
      debugPrint('❌ [CHAT] Erro ao carregar colaboradores: $e');
    }
  }
  
  Future<void> _showDeleteChatDialog(BuildContext context, ChatRoom room) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Deletar conversa'),
        content: Text(
          'Tem certeza que deseja deletar esta conversa? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Deletar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteRoom(room);
    }
  }

  Future<void> _deleteRoom(ChatRoom room) async {
    try {
      // Usar leaveRoom para sair/deletar a conversa (deixa a sala)
      final response = await _chatApi.leaveRoom(room.id);

      if (response.success) {
        // Remover da lista
        setState(() {
          _allRooms.removeWhere((r) => r.id == room.id);
          _archivedRooms.removeWhere((r) => r.id == room.id);
          
          // Se a sala deletada estava selecionada, limpar seleção
          if (_selectedRoom?.id == room.id) {
            _selectedRoom = null;
            _messages = [];
          }
        });

        // Atualizar controller de não lidas
        ChatUnreadController.instance.updateFromRooms(_allRooms);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Conversa deletada com sucesso'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao deletar conversa'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ [CHAT] Erro ao deletar conversa: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao deletar conversa: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _startConversationWithUser(CompanyUser user) async {
    try {
      // Criar ou obter sala de conversa direta com o usuário
      final response = await _chatApi.createOrGetRoom(
        type: ChatRoomType.direct,
        userId: user.id,
      );
      
      if (response.success && response.data != null) {
        // Selecionar a sala criada/obtida
        await _selectRoom(response.data!);
        
        // Se não estava na lista, adicionar
        if (!_allRooms.any((r) => r.id == response.data!.id)) {
          setState(() {
            _allRooms.insert(0, response.data!);
            _archivedRooms = _allRooms.where((r) => r.isArchived == true).toList();
          });
        }
        
        // Voltar para a tab "Todas" para ver a conversa
        _tabController.animateTo(0);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao iniciar conversa'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ [CHAT] Erro ao iniciar conversa: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao iniciar conversa: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _initialize() async {
    await _loadCurrentUser();
    await _loadCompanyId();
    await _loadRooms();
    _setupWebSocket();
    
    // Carregar colaboradores se estiver na tab de colaboradores
    if (_tabController.index == 2) {
      await _loadCompanyUsers();
    }
    
    // Se roomId foi fornecido, selecionar automaticamente
    if (widget.roomId != null && mounted) {
      _selectRoomById(widget.roomId!);
    }
  }

  Future<void> _loadCurrentUser() async {
    try {
      final profileResponse = await ProfileService.instance.getProfile();
      if (profileResponse.success && profileResponse.data != null) {
        setState(() {
          _currentUserId = profileResponse.data!.id;
        });
      } else {
        // Fallback: tentar obter do token
        final token = await SecureStorageService.instance.getAccessToken();
        if (token != null) {
          final payload = JwtUtils.decodeToken(token);
          if (payload != null) {
            final userId = payload['sub']?.toString() ?? payload['userId']?.toString();
            setState(() {
              _currentUserId = userId;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('❌ [CHAT] Erro ao carregar usuário: $e');
    }
  }

  Future<void> _loadCompanyId() async {
    try {
      final companyId = await SecureStorageService.instance.getCompanyId();
      
      // Conectar WebSocket se tiver companyId
      if (companyId != null) {
        _chatSocket.connect(companyId);
      }
    } catch (e) {
      debugPrint('❌ [CHAT] Erro ao carregar companyId: $e');
    }
  }

  Future<void> _loadRooms() async {
    setState(() {
      _isLoadingRooms = true;
      _errorMessage = null;
    });

    try {
      final response = await _chatApi.getRooms();
      if (response.success && response.data != null) {
        // Ordenar conversas por data da última mensagem (mais recente primeiro)
        final sortedRooms = List<ChatRoom>.from(response.data!);
        sortedRooms.sort((a, b) {
          final aDate = a.lastMessageAt ?? a.createdAt;
          final bDate = b.lastMessageAt ?? b.createdAt;
          return bDate.compareTo(aDate); // Ordem decrescente (mais recente primeiro)
        });

        setState(() {
          _allRooms = sortedRooms;
          _archivedRooms = _allRooms.where((r) => r.isArchived == true).toList();
          _isLoadingRooms = false;
        });
        // Atualizar controller de não lidas
        ChatUnreadController.instance.updateFromRooms(response.data!);
      } else {
        setState(() {
          _errorMessage = response.message ?? 'Erro ao carregar conversas';
          _isLoadingRooms = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erro ao carregar conversas: ${e.toString()}';
        _isLoadingRooms = false;
      });
    }
  }

  void _setupWebSocket() {
    // Notificar o controller sobre a sala atualmente aberta
    ChatUnreadController.instance.setCurrentlyOpenRoom(_selectedRoom?.id);
    
    // Quando o ChatPage chama setOnMessageReceived, ele substitui o callback do controller
    // Por isso, precisamos também chamar o método do controller aqui
    _chatSocket.setOnMessageReceived((message) {
      // Notificar o controller sobre a mensagem (ele decide se incrementa baseado na sala aberta)
      ChatUnreadController.instance.onMessageReceived(message);
      
      // Se a sala está aberta, atualizar UI e marcar como lida
      if (mounted && message.roomId == _selectedRoom?.id) {
        setState(() {
          // Verificar se a mensagem já existe (evitar duplicação)
          final exists = _messages.any((m) => m.id == message.id);
          if (!exists) {
            _messages.add(message);
            _scrollToBottom();
          }
        });
        // Se a sala está aberta, marcar como lida (remove do contador)
        ChatUnreadController.instance.markAsRead(message.roomId);
      }
      // Atualizar última mensagem na lista de rooms
      _updateRoomLastMessage(message);
    });

    _chatSocket.setOnRoomUpdated((roomId, name, imageUrl) {
      if (mounted) {
        setState(() {
          final index = _allRooms.indexWhere((r) => r.id == roomId);
          if (index != -1) {
            _allRooms[index] = ChatRoom(
              id: _allRooms[index].id,
              companyId: _allRooms[index].companyId,
              type: _allRooms[index].type,
              name: name ?? _allRooms[index].name,
              createdBy: _allRooms[index].createdBy,
              imageUrl: imageUrl ?? _allRooms[index].imageUrl,
              lastMessage: _allRooms[index].lastMessage,
              lastMessageAt: _allRooms[index].lastMessageAt,
              participants: _allRooms[index].participants,
              createdAt: _allRooms[index].createdAt,
              updatedAt: _allRooms[index].updatedAt,
              isArchived: _allRooms[index].isArchived,
              unreadCount: _allRooms[index].unreadCount,
            );
            _archivedRooms = _allRooms.where((r) => r.isArchived == true).toList();
          }
        });
      }
    });
  }

  void _updateRoomLastMessage(ChatMessage message) {
    if (!mounted) return; // Verificar se o widget ainda está montado
    
    setState(() {
      final index = _allRooms.indexWhere((r) => r.id == message.roomId);
      if (index != -1) {
        _allRooms[index] = ChatRoom(
          id: _allRooms[index].id,
          companyId: _allRooms[index].companyId,
          type: _allRooms[index].type,
          name: _allRooms[index].name,
          createdBy: _allRooms[index].createdBy,
          imageUrl: _allRooms[index].imageUrl,
          lastMessage: message.content,
          lastMessageAt: message.createdAt,
          participants: _allRooms[index].participants,
          createdAt: _allRooms[index].createdAt,
          updatedAt: _allRooms[index].updatedAt,
          isArchived: _allRooms[index].isArchived,
          unreadCount: _allRooms[index].unreadCount,
        );
        // Reordenar após atualizar a última mensagem (mover para o topo)
        _allRooms.sort((a, b) {
          final aDate = a.lastMessageAt ?? a.createdAt;
          final bDate = b.lastMessageAt ?? b.createdAt;
          return bDate.compareTo(aDate); // Ordem decrescente (mais recente primeiro)
        });
        _archivedRooms = _allRooms.where((r) => r.isArchived == true).toList();
      }
    });
  }

  Future<void> _selectRoom(ChatRoom room) async {
    if (_selectedRoom?.id == room.id) return;

    setState(() {
      _selectedRoom = room;
      _messages = [];
      _messageOffset = 0;
      _isLoadingMessages = true;
    });

    // Notificar o controller sobre a sala aberta
    ChatUnreadController.instance.setCurrentlyOpenRoom(room.id);

    // Entrar na sala via WebSocket
    _chatSocket.joinRoom(room.id);

    // Marcar como lida
    await _chatApi.markAsRead(room.id);
    // Atualizar controller de não lidas
    ChatUnreadController.instance.markAsRead(room.id);

    // Carregar mensagens
    await _loadMessages(room.id);

    // Atualizar lista de rooms (remover unread)
    setState(() {
      final index = _allRooms.indexWhere((r) => r.id == room.id);
      if (index != -1) {
        _allRooms[index] = ChatRoom(
          id: _allRooms[index].id,
          companyId: _allRooms[index].companyId,
          type: _allRooms[index].type,
          name: _allRooms[index].name,
          createdBy: _allRooms[index].createdBy,
          imageUrl: _allRooms[index].imageUrl,
          lastMessage: _allRooms[index].lastMessage,
          lastMessageAt: _allRooms[index].lastMessageAt,
          participants: _allRooms[index].participants,
          createdAt: _allRooms[index].createdAt,
          updatedAt: _allRooms[index].updatedAt,
          isArchived: _allRooms[index].isArchived,
          unreadCount: 0,
        );
        _archivedRooms = _allRooms.where((r) => r.isArchived == true).toList();
      }
    });
  }

  Future<void> _selectRoomById(String roomId) async {
    final room = _allRooms.firstWhere(
      (r) => r.id == roomId,
      orElse: () => _allRooms.isNotEmpty ? _allRooms.first : throw Exception('Room not found'),
    );
    await _selectRoom(room);
  }

  Future<void> _loadMessages(String roomId, {bool loadMore = false}) async {
    if (!loadMore) {
      setState(() {
        _isLoadingMessages = true;
        _messageOffset = 0;
      });
    }

    try {
      final response = await _chatApi.getMessages(
        roomId: roomId,
        limit: _messagesLimit,
        offset: _messageOffset,
      );

      if (response.success && response.data != null) {
        setState(() {
          if (loadMore) {
            _messages.insertAll(0, response.data!.reversed);
            _messageOffset += response.data!.length;
          } else {
            _messages = response.data!.reversed.toList();
            _messageOffset = response.data!.length;
          }
          _isLoadingMessages = false;
        });

        if (!loadMore) {
          _scrollToBottom();
        }
      } else {
        setState(() {
          _isLoadingMessages = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoadingMessages = false;
      });
    }
  }

  void _scrollToBottom() {
    if (_messagesScrollController.hasClients) {
      _messagesScrollController.animateTo(
        _messagesScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _handleSendMessage(String content, {File? file}) async {
    if (_selectedRoom == null || (content.trim().isEmpty && file == null)) return;

    // Criar mensagem temporária para feedback imediato
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final tempMessage = ChatMessage(
      id: tempId,
      roomId: _selectedRoom!.id,
      senderId: _currentUserId ?? '',
      senderName: 'Você',
      content: content.trim().isEmpty ? (file != null ? '📎 ${file.path.split('/').last}' : '') : content.trim(),
      status: ChatMessageStatus.sending,
      isEdited: false,
      isDeleted: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isPending: true,
    );

    // Adicionar mensagem temporária
    setState(() {
      _messages.add(tempMessage);
      _scrollToBottom();
    });

    // Enviar mensagem com ou sem arquivo
    final response = await _chatApi.sendMessage(
      roomId: _selectedRoom!.id,
      content: content.trim(),
      file: file,
    );

    if (response.success && response.data != null) {
      setState(() {
        // Remover mensagem temporária e adicionar a real
        _messages.removeWhere((m) => m.id == tempId);
        // Verificar se já não existe (pode ter chegado via WebSocket)
        final exists = _messages.any((m) => m.id == response.data!.id);
        if (!exists) {
          _messages.add(response.data!);
        }
      });
      _scrollToBottom();
    } else {
      // Remover mensagem temporária em caso de erro
      setState(() {
        _messages.removeWhere((m) => m.id == tempId);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.message ?? 'Erro ao enviar mensagem'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildRoomsList(BuildContext context, ThemeData theme) {
    return Column(
      children: [
        // Header da lista
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Conversas',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadRooms,
                tooltip: 'Atualizar',
              ),
            ],
          ),
        ),
        // Tabs
        Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: ThemeHelpers.borderColor(context),
                width: 1,
              ),
            ),
          ),
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.primary.primary,
            unselectedLabelColor: ThemeHelpers.textSecondaryColor(context),
            indicatorColor: AppColors.primary.primary,
            dividerColor: Colors.transparent,
            overlayColor: WidgetStateProperty.all(Colors.transparent),
            tabs: const [
              Tab(icon: Icon(Icons.chat_bubble_outline, size: 20), text: 'Todas'),
              Tab(icon: Icon(Icons.archive_outlined, size: 20), text: 'Arquivadas'),
              Tab(icon: Icon(Icons.people_outline, size: 20), text: 'Colaboradores'),
            ],
          ),
        ),
        // Lista de conversas ou colaboradores
        Expanded(
          child: _tabController.index == 2
              ? _buildUsersList(context, theme)
              : _isLoadingRooms
              ? _buildRoomsShimmer(context)
              : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadRooms,
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                )
              : _rooms.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 64,
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Nenhuma conversa',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _rooms.length,
                  itemBuilder: (context, index) {
                    final room = _rooms[index];
                    final isSelected = _selectedRoom?.id == room.id;
                    return ChatRoomListItem(
                      room: room,
                      currentUserId: _currentUserId,
                      isSelected: isSelected,
                      onTap: () => _selectRoom(room),
                    );
                  },
                ),
        ),
      ],
    );
  }
  
  Widget _buildUsersList(BuildContext context, ThemeData theme) {
    if (_isLoadingUsers) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: 8,
        itemBuilder: (context, index) {
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  SkeletonBox(width: 48, height: 48, borderRadius: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonText(width: double.infinity, height: 16, margin: const EdgeInsets.only(bottom: 8)),
                        SkeletonText(width: 150, height: 14),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
    
    if (_companyUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhum colaborador encontrado',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _companyUsers.length,
      itemBuilder: (context, index) {
        final user = _companyUsers[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: ThemeHelpers.borderLightColor(context),
              width: 1,
            ),
          ),
          child: InkWell(
            onTap: () => _startConversationWithUser(user),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Avatar
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundImage: user.avatar != null ? NetworkImage(user.avatar!) : null,
                        child: user.avatar == null
                            ? Text(
                                user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              )
                            : null,
                      ),
                      // Indicador online
                      if (user.isOnline)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: ThemeHelpers.backgroundColor(context),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  // Nome e email
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          user.name,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user.email,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Ícone de chat
                  Icon(
                    Icons.chat_bubble_outline,
                    color: ThemeHelpers.textSecondaryColor(context),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessagesArea(BuildContext context, ThemeData theme) {
    if (_selectedRoom == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
            const SizedBox(height: 16),
            Text(
              'Selecione uma conversa',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
          ],
        ),
      );
    }

    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    return Column(
      children: [
        // Header da conversa
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: ThemeHelpers.borderColor(context),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              if (isSmallScreen)
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    setState(() {
                      _selectedRoom = null;
                    });
                  },
                ),
              CircleAvatar(
                backgroundImage: _selectedRoom!.getDisplayImage(_currentUserId) != null
                    ? NetworkImage(_selectedRoom!.getDisplayImage(_currentUserId)!)
                    : null,
                child: _selectedRoom!.getDisplayImage(_currentUserId) == null
                    ? Text(
                        _selectedRoom!.getDisplayName(_currentUserId)[0].toUpperCase(),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _selectedRoom!.getDisplayName(_currentUserId),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // Menu de opções
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  if (value == 'delete') {
                    _showDeleteChatDialog(context, _selectedRoom!);
                  }
                },
                itemBuilder: (BuildContext context) => [
                  const PopupMenuItem<String>(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: Colors.red, size: 20),
                        SizedBox(width: 8),
                        Text('Deletar conversa'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Lista de mensagens
        Expanded(
          child: _isLoadingMessages
              ? _buildMessagesShimmer(context)
              : ChatMessageList(
                  messages: _messages,
                  currentUserId: _currentUserId,
                  scrollController: _messagesScrollController,
                  onLoadMore: () {
                    if (!_isLoadingMessages) {
                      _loadMessages(_selectedRoom!.id, loadMore: true);
                    }
                  },
                ),
        ),
        // Input de mensagem
        ChatInput(
          onSend: _handleSendMessage,
        ),
      ],
    );
  }

  Widget _buildRoomsShimmer(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: 8,
      itemBuilder: (context, index) {
        return Card(
          margin: const EdgeInsets.only(bottom: 8, left: 12, right: 12, top: 8),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: ThemeHelpers.borderLightColor(context),
              width: 1,
            ),
          ),
          color: ThemeHelpers.cardBackgroundColor(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Avatar skeleton
                SkeletonBox(
                  width: 48,
                  height: 48,
                  borderRadius: 24,
                ),
                const SizedBox(width: 12),
                // Conteúdo skeleton
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonText(
                        width: double.infinity,
                        height: 16,
                        margin: const EdgeInsets.only(bottom: 8),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: SkeletonText(
                              width: 150,
                              height: 14,
                            ),
                          ),
                          SkeletonBox(
                            width: 40,
                            height: 20,
                            borderRadius: 10,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessagesShimmer(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 10,
      itemBuilder: (context, index) {
        final isOwnMessage = index % 3 == 0; // Alternar entre mensagens próprias e outras
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            mainAxisAlignment: isOwnMessage
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isOwnMessage) ...[
                SkeletonBox(
                  width: 32,
                  height: 32,
                  borderRadius: 16,
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isOwnMessage
                        ? AppColors.primary.primary.withOpacity(0.1)
                        : ThemeHelpers.cardBackgroundColor(context),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isOwnMessage ? 18 : 4),
                      bottomRight: Radius.circular(isOwnMessage ? 4 : 18),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: isOwnMessage
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      SkeletonText(
                        width: index % 2 == 0 ? 200 : 150,
                        height: 16,
                        margin: EdgeInsets.zero,
                      ),
                      if (index % 2 == 0) ...[
                        const SizedBox(height: 4),
                        SkeletonText(
                          width: 100,
                          height: 16,
                          margin: EdgeInsets.zero,
                        ),
                      ],
                      const SizedBox(height: 8),
                      SkeletonText(
                        width: 60,
                        height: 12,
                        margin: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
              if (isOwnMessage) ...[
                const SizedBox(width: 8),
                SkeletonBox(
                  width: 32,
                  height: 32,
                  borderRadius: 16,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    // Limpar sala aberta quando a página é destruída
    ChatUnreadController.instance.setCurrentlyOpenRoom(null);
    
    // Restaurar callback do controller (ele precisa do callback para atualizar contadores)
    // O controller tem seu próprio método onMessageReceived que será chamado
    _chatSocket.setOnMessageReceived((message) {
      ChatUnreadController.instance.onMessageReceived(message);
    });
    
    // Limpar callback de atualização de sala (não é crítico para o controller)
    _chatSocket.setOnRoomUpdated((_, __, ___) {});
    
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _messagesScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSmallScreen = MediaQuery.of(context).size.width < 600;
    final currentRoute = ModalRoute.of(context)?.settings.name;
    final navIndex = AppBottomNavigation.getIndexForRoute(currentRoute);

    // Notificar controller sobre a sala aberta quando o widget é construído
    ChatUnreadController.instance.setCurrentlyOpenRoom(_selectedRoom?.id);

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        // Sempre redirecionar para o dashboard ao pressionar voltar
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.home,
          (route) => route.settings.name == AppRoutes.home,
        );
      },
      child: AppScaffold(
        title: _selectedRoom != null
            ? _selectedRoom!.getDisplayName(_currentUserId)
            : 'Chat',
        showDrawer: true,
        showBottomNavigation: true,
        currentBottomNavIndex: navIndex,
        body: isSmallScreen && _selectedRoom != null
            ? _buildMessagesArea(context, theme)
            : isSmallScreen && _selectedRoom == null
            ? _buildRoomsList(context, theme)
            : Row(
              children: [
                // Lista de conversas (sidebar)
                Container(
                  width: 350,
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(
                        color: ThemeHelpers.borderColor(context),
                        width: 1,
                      ),
                    ),
                  ),
                  child: _buildRoomsList(context, theme),
                ),
                // Área de mensagens (apenas em telas grandes ou quando há sala selecionada)
                Expanded(
                  child: _selectedRoom == null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 64,
                                color: ThemeHelpers.textSecondaryColor(context),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Selecione uma conversa',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: ThemeHelpers.textSecondaryColor(context),
                                ),
                              ),
                            ],
                          ),
                        )
                      : _buildMessagesArea(context, theme),
                ),
              ],
            ),
      ),
    );
  }
}
