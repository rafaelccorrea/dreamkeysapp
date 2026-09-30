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
import '../../../shared/utils/error_cause.dart';
import '../../../shared/widgets/app_error_state.dart';
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

class _ChatPageState extends State<ChatPage>
    with SingleTickerProviderStateMixin {
  final ChatApiService _chatApi = ChatApiService.instance;
  final ChatSocketService _chatSocket = ChatSocketService.instance;

  // 29/09/2026 — as duas listas vêm separadas do back (GET /chat/rooms
  // devolve `{ rooms, archivedRooms }`; arquivar é por participante).
  // Antes as arquivadas eram recalculadas filtrando `isArchived` das ativas,
  // e a aba 'Arquivadas' ficava sempre vazia.
  List<ChatRoom> _activeRooms = [];
  List<ChatRoom> _archivedRooms = [];
  ChatRoom? _selectedRoom;
  List<ChatMessage> _messages = [];
  List<CompanyUser> _companyUsers = [];
  String? _currentUserId;
  bool _isLoadingRooms = true;
  bool _isLoadingMessages = false;
  bool _isLoadingUsers = false;
  String? _errorMessage;
  // Guardado junto da mensagem: sem o código HTTP não dá para distinguir
  // "sem permissão" de "servidor fora do ar".
  int _errorStatus = 0;
  ErrorCause? _errorCause;

  int _messageOffset = 0;
  static const int _messagesLimit = 50;
  final ScrollController _messagesScrollController = ScrollController();
  late TabController _tabController;

  List<ChatRoom> get _rooms {
    // Aba 'Arquivadas' = archivedRooms do back; as demais = ativas.
    // Cópia antes de ordenar para não reordenar o estado dentro do getter.
    final rooms = List<ChatRoom>.of(
      _tabController.index == 1 ? _archivedRooms : _activeRooms,
    );
    // Ordenar por data da última mensagem (mais recente primeiro)
    rooms.sort((a, b) {
      final aDate = a.lastMessageAt ?? a.createdAt;
      final bDate = b.lastMessageAt ?? b.createdAt;
      return bDate.compareTo(
        aDate,
      ); // Ordem decrescente (mais recente primeiro)
    });
    return rooms;
  }

  /// Sala conhecida pelo id, esteja ela nas ativas ou nas arquivadas.
  ChatRoom? _findRoom(String roomId) {
    for (final r in _activeRooms) {
      if (r.id == roomId) return r;
    }
    for (final r in _archivedRooms) {
      if (r.id == roomId) return r;
    }
    return null;
  }

  /// Aplica [update] à sala [roomId] na lista em que ela estiver (ativas ou
  /// arquivadas), sem mudá-la de lista. Chamar dentro de setState.
  void _patchRoom(String roomId, ChatRoom Function(ChatRoom room) update) {
    final i = _activeRooms.indexWhere((r) => r.id == roomId);
    if (i != -1) {
      _activeRooms[i] = update(_activeRooms[i]);
      return;
    }
    final j = _archivedRooms.indexWhere((r) => r.id == roomId);
    if (j != -1) {
      _archivedRooms[j] = update(_archivedRooms[j]);
    }
  }

  /// Repassa as duas listas ao badge do chat (arquivada não conta).
  void _syncUnreadBadge() {
    ChatUnreadController.instance.updateFromRooms(
      _activeRooms,
      archivedRooms: _archivedRooms,
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
    ); // Adicionada tab de Colaboradores
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
          _companyUsers = response.data!
              .where((u) => u.id != _currentUserId)
              .toList();
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

  Future<void> _showDeleteChatDialog(
    BuildContext context,
    ChatRoom room,
  ) async {
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
          _activeRooms.removeWhere((r) => r.id == room.id);
          _archivedRooms.removeWhere((r) => r.id == room.id);

          // Se a sala deletada estava selecionada, limpar seleção
          if (_selectedRoom?.id == room.id) {
            _selectedRoom = null;
            _messages = [];
          }
        });

        // Atualizar controller de não lidas
        _syncUnreadBadge();

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
        final fetched = response.data!;
        if (!mounted) return;

        // 29/09/2026: sala já conhecida (ativa OU arquivada) não é duplicada,
        // como no joinRoom do web; conversa nova entra no topo da lista certa.
        if (_findRoom(fetched.id) == null) {
          setState(() {
            if (fetched.isArchived == true) {
              _archivedRooms.insert(0, fetched);
            } else {
              _activeRooms.insert(0, fetched);
            }
          });
        }
        final room = _findRoom(fetched.id) ?? fetched;

        // Selecionar a sala criada/obtida
        await _selectRoom(room);
        if (!mounted) return;

        // Voltar para a aba em que a conversa está ('Todas' ou 'Arquivadas')
        _tabController.animateTo(room.isArchived == true ? 1 : 0);
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
            final userId =
                payload['sub']?.toString() ?? payload['userId']?.toString();
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
      _errorStatus = 0;
      _errorCause = null;
    });

    try {
      final response = await _chatApi.getRooms();
      if (!mounted) return;
      if (response.success && response.data != null) {
        final result = response.data!;

        // 304 (ETag): nada mudou desde a última leitura. Mantém as listas
        // que já estão na tela; as listas vazias do 304 não são "sem
        // conversas" (o web apagava as Arquivadas justamente assim).
        if (result.notModified) {
          setState(() => _isLoadingRooms = false);
          return;
        }

        // 'Todas' = rooms e 'Arquivadas' = archivedRooms, como o back
        // separa. A ordem (mais recente primeiro) é aplicada em [_rooms].
        setState(() {
          _activeRooms = List<ChatRoom>.of(result.rooms);
          _archivedRooms = List<ChatRoom>.of(result.archivedRooms);
          _isLoadingRooms = false;
        });
        // Atualizar controller de não lidas
        _syncUnreadBadge();
      } else {
        setState(() {
          _errorMessage = response.message ?? 'Erro ao carregar conversas';
          _errorStatus = response.statusCode;
          _isLoadingRooms = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorCause = ErrorCause.fromException(e);
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
          // Nome/foto do grupo mudaram: vale para ativa ou arquivada.
          _patchRoom(
            roomId,
            (r) => r.copyWith(name: name, imageUrl: imageUrl),
          );
        });
      }
    });
  }

  void _updateRoomLastMessage(ChatMessage message) {
    if (!mounted) return; // Verificar se o widget ainda está montado

    setState(() {
      // Arquivada também ganha a prévia nova (igual ao web), mas continua
      // na aba Arquivadas: o back não desarquiva com mensagem nova. A
      // reordenação (mais recente no topo) acontece em [_rooms].
      _patchRoom(
        message.roomId,
        (r) => r.copyWith(
          lastMessage: message.content,
          lastMessageAt: message.createdAt,
        ),
      );
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
    if (!mounted) return;

    // Atualizar lista de rooms (remover unread), na lista em que ela está
    setState(() {
      _patchRoom(room.id, (r) => r.copyWith(unreadCount: 0));
    });
  }

  /// Abre a sala pedida pela rota (/chat/:roomId, ex.: toque na notificação).
  ///
  /// 29/09/2026: procura nas ativas e nas arquivadas; se não estiver em
  /// nenhuma, busca a sala no servidor, como o joinRoom do web. Antes, sala
  /// fora da lista abria a PRIMEIRA conversa da lista, e lista vazia lançava
  /// exceção sem tratamento.
  Future<void> _selectRoomById(String roomId) async {
    final ChatRoom room;
    final known = _findRoom(roomId);
    if (known != null) {
      room = known;
    } else {
      final response = await _chatApi.getRoomById(roomId);
      if (!mounted) return;
      final fetched = response.data;
      if (!response.success || fetched == null) {
        // Causa real do back (ex.: 'Você não tem acesso a esta sala de chat').
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response.message ?? 'Não foi possível abrir a conversa',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      room = fetched;
      setState(() {
        if (room.isArchived == true) {
          _archivedRooms.insert(0, room);
        } else {
          _activeRooms.insert(0, room);
        }
      });
    }

    // Conversa arquivada: ao voltar para a lista, a aba certa já está aberta.
    if (room.isArchived == true && _tabController.index != 1) {
      _tabController.animateTo(1);
    }
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
            // Para carregar mais mensagens antigas, inserir no início
            // A API retorna em ordem crescente (mais antigas primeiro)
            _messages.insertAll(0, response.data!);
            _messageOffset += response.data!.length;
          } else {
            // Mensagens em ordem crescente (mais antigas primeiro, mais novas por último)
            _messages = response.data!;
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
    if (_selectedRoom == null || (content.trim().isEmpty && file == null)) {
      return;
    }

    // Criar mensagem temporária para feedback imediato
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final tempMessage = ChatMessage(
      id: tempId,
      roomId: _selectedRoom!.id,
      senderId: _currentUserId ?? '',
      senderName: 'Você',
      content: content.trim().isEmpty
          ? (file != null ? '📎 ${file.path.split('/').last}' : '')
          : content.trim(),
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
    // Lista da aba calculada uma vez por build (o getter copia e ordena).
    final rooms = _rooms;
    final isArchivedTab = _tabController.index == 1;
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
              Tab(
                icon: Icon(Icons.chat_bubble_outline, size: 20),
                text: 'Todas',
              ),
              Tab(
                icon: Icon(Icons.archive_outlined, size: 20),
                text: 'Arquivadas',
              ),
              Tab(
                icon: Icon(Icons.people_outline, size: 20),
                text: 'Colaboradores',
              ),
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
              ? (_errorCause != null
                    ? AppErrorState(
                        cause: _errorCause!,
                        onRetry: _loadRooms,
                      )
                    : AppErrorState.fromApi(
                        message: _errorMessage,
                        statusCode: _errorStatus,
                        onRetry: _loadRooms,
                      ))
              : rooms.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isArchivedTab
                            ? Icons.archive_outlined
                            : Icons.chat_bubble_outline,
                        size: 64,
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isArchivedTab
                            ? 'Nenhuma conversa arquivada'
                            : 'Nenhuma conversa',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: rooms.length,
                  itemBuilder: (context, index) {
                    final room = rooms[index];
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
                        SkeletonText(
                          width: double.infinity,
                          height: 16,
                          margin: const EdgeInsets.only(bottom: 8),
                        ),
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
                        backgroundImage: user.avatar != null
                            ? NetworkImage(user.avatar!)
                            : null,
                        child: user.avatar == null
                            ? Text(
                                user.name.isNotEmpty
                                    ? user.name[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
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
                backgroundImage:
                    _selectedRoom!.getDisplayImage(_currentUserId) != null
                    ? NetworkImage(
                        _selectedRoom!.getDisplayImage(_currentUserId)!,
                      )
                    : null,
                child: _selectedRoom!.getDisplayImage(_currentUserId) == null
                    ? Text(
                        _selectedRoom!
                            .getDisplayName(_currentUserId)[0]
                            .toUpperCase(),
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
        ChatInput(onSend: _handleSendMessage),
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
                SkeletonBox(width: 48, height: 48, borderRadius: 24),
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
                          Expanded(child: SkeletonText(width: 150, height: 14)),
                          SkeletonBox(width: 40, height: 20, borderRadius: 10),
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
        final isOwnMessage =
            index % 3 == 0; // Alternar entre mensagens próprias e outras

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            mainAxisAlignment: isOwnMessage
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isOwnMessage) ...[
                SkeletonBox(width: 32, height: 32, borderRadius: 16),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
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
                SkeletonBox(width: 32, height: 32, borderRadius: 16),
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

        // Se há uma sala selecionada, apenas deselecionar (voltar para lista)
        if (_selectedRoom != null) {
          setState(() {
            _selectedRoom = null;
          });
        } else {
          // Se não há sala selecionada, voltar para o dashboard
          Navigator.of(context).pushNamedAndRemoveUntil(
            AppRoutes.home,
            (route) => route.settings.name == AppRoutes.home,
          );
        }
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
                                  color: ThemeHelpers.textSecondaryColor(
                                    context,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Selecione uma conversa',
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: ThemeHelpers.textSecondaryColor(
                                      context,
                                    ),
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
