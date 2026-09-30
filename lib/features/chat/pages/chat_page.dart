import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
import '../../whatsapp/widgets/whatsapp_conversation_card.dart'
    show WhatsAppAvatar;
import '../widgets/chat_room_list_item.dart';
import '../widgets/chat_message_list.dart';
import '../widgets/chat_input.dart';
import '../widgets/chat_visual.dart';

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

  // Colaboradores: a falha na carga virava "Nenhum colaborador encontrado"
  // (30/09/2026) — agora a tela diz a causa e oferece "Tentar de novo".
  String? _usersError;
  int _usersErrorStatus = 0;

  /// Colega cuja conversa está sendo aberta (mostra progresso na linha e
  /// evita o toque duplo criar duas chamadas).
  String? _openingUserId;

  /// Busca local da lista (nome, prévia, e-mail do colega) — não chama a API.
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

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
      _usersError = null;
      _usersErrorStatus = 0;
    });

    try {
      final response = await _chatApi.getCompanyUsers();
      if (!mounted) return;
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
          _usersError =
              response.message ?? 'Não foi possível carregar os colegas.';
          _usersErrorStatus = response.statusCode;
        });
      }
    } catch (e) {
      debugPrint('❌ [CHAT] Erro ao carregar colaboradores: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingUsers = false;
        _usersError = 'Não foi possível carregar os colegas.';
      });
    }
  }

  /// Aviso curto no cartão do tema, com ícone de erro ou de sucesso (o
  /// fundo vermelho/verde saturado com texto branco foi trocado).
  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color tone;
    if (error) {
      tone = isDark
          ? AppColors.message.errorTextDarkMode
          : AppColors.message.errorText;
    } else {
      tone = isDark
          ? AppColors.message.successTextDarkMode
          : AppColors.message.successText;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              error ? LucideIcons.circleAlert : LucideIcons.circleCheck,
              size: 18,
              color: tone,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteChatDialog(
    BuildContext context,
    ChatRoom room,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final name = room.getDisplayName(_currentUserId);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Excluir conversa',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3),
        ),
        content: SingleChildScrollView(
          child: Text(
            room.type == ChatRoomType.group
                ? 'Você sai do grupo "$name" e a conversa some da sua lista. '
                      'Esta ação não pode ser desfeita.'
                : 'A conversa com $name some da sua lista. '
                      'Esta ação não pode ser desfeita.',
            style: const TextStyle(height: 1.4),
          ),
        ),
        actions: [
          // Cancelar NEUTRO: o tema pinta TextButton de vermelho.
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: ThemeHelpers.textSecondaryColor(dialogContext),
            ),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Excluir'),
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

        _toast('Conversa excluída.');
      } else {
        _toast(
          response.message ?? 'Não foi possível excluir a conversa.',
          error: true,
        );
      }
    } catch (e) {
      debugPrint('❌ [CHAT] Erro ao deletar conversa: $e');
      _toast(
        'Não foi possível excluir a conversa. '
        'Confira a conexão e tente de novo.',
        error: true,
      );
    }
  }

  Future<void> _startConversationWithUser(CompanyUser user) async {
    if (_openingUserId != null) return;
    setState(() => _openingUserId = user.id);
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
        _toast(
          response.message ?? 'Não foi possível abrir a conversa.',
          error: true,
        );
      }
    } catch (e) {
      debugPrint('❌ [CHAT] Erro ao iniciar conversa: $e');
      _toast(
        'Não foi possível abrir a conversa. Confira a conexão e tente de novo.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _openingUserId = null);
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
        _toast(
          response.message ?? 'Não foi possível abrir a conversa.',
          error: true,
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
      // Só na bolha provisória, enquanto envia: o nome do arquivo, sem emoji
      // (a interface não usa emoji). O que vai para a API não muda.
      content: content.trim().isEmpty
          ? (file != null ? file.path.split(RegExp(r'[\\/]')).last : '')
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
      _toast(
        response.message ?? 'A mensagem não foi enviada. Tente de novo.',
        error: true,
      );
    }
  }

  // ─── Lista: Todas · Arquivadas · Colaboradores ───────────────────────────

  static String _plural(int n, String one, String many) =>
      n == 1 ? '1 $one' : '$n $many';

  bool _roomMatches(ChatRoom r, String q) {
    if (r.getDisplayName(_currentUserId).toLowerCase().contains(q)) {
      return true;
    }
    return chatPreviewText(r.lastMessage).toLowerCase().contains(q);
  }

  bool _userMatches(CompanyUser u, String q) =>
      u.name.toLowerCase().contains(q) || u.email.toLowerCase().contains(q);

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  /// Lista inteira num scroll só (30/09/2026): o resumo, a busca e as abas
  /// rolam junto com as linhas. Antes o topo era fixo (título + abas com
  /// ícone, ~140dp) sobre um Expanded — em paisagem com o teclado aberto a
  /// lista ficava sem altura. O puxar-para-atualizar vale nas três abas
  /// (ListView direto sob o RefreshIndicator).
  Widget _buildRoomsList(BuildContext context, ThemeData theme) {
    final tab = _tabController.index;
    final top = <Widget>[
      _buildListHeader(context),
      _buildSearchField(context),
      _buildTabs(context),
    ];
    final body = tab == 2 ? _usersBody(context) : _roomsBody(context);
    return RefreshIndicator(
      color: chatInk(context),
      onRefresh: tab == 2 ? _loadCompanyUsers : _loadRooms,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: 32),
        itemCount: top.length + body.length,
        itemBuilder: (context, i) =>
            i < top.length ? top[i] : body[i - top.length],
      ),
    );
  }

  /// "Conversas" + a frase que responde "tem algo para mim?" antes de ler a
  /// lista (quantas com mensagem nova, silenciadas, arquivadas, colegas).
  Widget _buildListHeader(BuildContext context) {
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final tab = _tabController.index;

    var summary = '';
    var summaryColor = secondary;
    var summaryWeight = FontWeight.w500;
    if (tab == 2) {
      if (_isLoadingUsers && _companyUsers.isEmpty) {
        summary = 'Carregando a equipe…';
      } else if (_companyUsers.isEmpty) {
        summary = 'Toque em um colega para conversar.';
      } else {
        final online = _companyUsers.where((u) => u.isOnline).length;
        summary = _plural(_companyUsers.length, 'colega', 'colegas');
        if (online > 0) summary += ' · $online online agora';
        summary += ' · toque para conversar';
      }
    } else if (tab == 1) {
      final archived = _plural(
        _archivedRooms.length,
        'conversa arquivada',
        'conversas arquivadas',
      );
      summary = _archivedRooms.isEmpty
          ? 'Nada arquivado.'
          : '$archived · mensagem nova aqui não acende o aviso';
    } else if (_isLoadingRooms && _activeRooms.isEmpty) {
      summary = 'Carregando suas conversas…';
    } else {
      final unreadRooms =
          _activeRooms.where((r) => (r.unreadCount ?? 0) > 0).length;
      final muted = _activeRooms.where((r) => r.isMuted == true).length;
      if (unreadRooms > 0) {
        summary = unreadRooms == 1
            ? '1 conversa com mensagem nova'
            : '$unreadRooms conversas com mensagem nova';
        summaryColor = chatInk(context);
        summaryWeight = FontWeight.w700;
      } else if (_activeRooms.isEmpty) {
        summary = 'Nenhuma conversa ainda.';
      } else {
        final total = _plural(_activeRooms.length, 'conversa', 'conversas');
        summary = 'Tudo lido · $total';
      }
      if (muted > 0) {
        summary += ' · ${_plural(muted, 'silenciada', 'silenciadas')}';
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 6, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Conversas',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: summaryColor,
                    fontSize: 13,
                    fontWeight: summaryWeight,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: tab == 2 ? _loadCompanyUsers : _loadRooms,
            icon: Icon(LucideIcons.refreshCw, size: 19, color: secondary),
          ),
        ],
      ),
    );
  }

  /// Busca no molde da de Imóveis (campo cheio, lupa, limpar). Filtra a
  /// lista da aba aberta aqui mesmo — não chama a API.
  Widget _buildSearchField(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final tab = _tabController.index;
    final hasText = _searchController.text.isNotEmpty;
    final hint = tab == 2
        ? 'Buscar colega por nome ou e-mail'
        : tab == 1
        ? 'Buscar nas arquivadas'
        : 'Buscar conversa';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        decoration: BoxDecoration(
          color: chatFieldFill(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(LucideIcons.search, size: 18, color: secondary),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                cursorColor: chatInk(context),
                style: TextStyle(
                  color: ThemeHelpers.textColor(context),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  hintText: hint,
                  hintMaxLines: 1,
                  hintStyle: TextStyle(
                    color: secondary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w400,
                  ),
                  // O fill vive no Container (o tema global pintaria outro).
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            if (hasText)
              IconButton(
                tooltip: 'Limpar busca',
                visualDensity: VisualDensity.compact,
                onPressed: _clearSearch,
                icon: Icon(LucideIcons.x, size: 17, color: secondary),
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  /// Abas com sublinhado, só texto + contagem (as de ícone empilhado tinham
  /// ~72dp de altura e "Colaboradores" apagava no fim a 320dp/130%). Roláveis
  /// e alinhadas à esquerda: nenhum rótulo é cortado.
  Widget _buildTabs(BuildContext context) {
    final ink = chatInk(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    Widget tab(String label, int? count) => Tab(
      height: 44,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, maxLines: 1),
          if (count != null && count > 0) ...[
            const SizedBox(width: 5),
            Text(
              count > 99 ? '99+' : '$count',
              maxLines: 1,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(border: Border(bottom: chatHairline(context))),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        labelPadding: const EdgeInsets.symmetric(horizontal: 12),
        labelColor: ink,
        unselectedLabelColor: secondary,
        labelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.1,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
        indicatorColor: ink,
        indicatorSize: TabBarIndicatorSize.label,
        indicatorWeight: 2.5,
        dividerColor: Colors.transparent,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        tabs: [
          tab('Todas', _activeRooms.length),
          tab('Arquivadas', _archivedRooms.length),
          tab(
            'Colaboradores',
            _companyUsers.isEmpty ? null : _companyUsers.length,
          ),
        ],
      ),
    );
  }

  List<Widget> _roomsBody(BuildContext context) {
    final isArchivedTab = _tabController.index == 1;
    final hasAny = _activeRooms.isNotEmpty || _archivedRooms.isNotEmpty;

    // Esqueleto só na primeira carga: recarregar mantém a lista na tela.
    if (_isLoadingRooms && !hasAny) {
      return List.generate(7, (_) => _rowSkeleton(context, avatar: 52));
    }
    if (_errorMessage != null && !hasAny) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: _errorCause != null
              ? AppErrorState(
                  cause: _errorCause!,
                  onRetry: _loadRooms,
                  dense: true,
                )
              : AppErrorState.fromApi(
                  message: _errorMessage,
                  statusCode: _errorStatus,
                  onRetry: _loadRooms,
                  dense: true,
                ),
        ),
      ];
    }

    final q = _query.trim().toLowerCase();
    final all = _rooms;
    final rooms = q.isEmpty
        ? all
        : all.where((r) => _roomMatches(r, q)).toList();

    final out = <Widget>[];
    if (_errorMessage != null) {
      out.add(_refreshFailedStrip(context, onRetry: _loadRooms));
    }
    if (rooms.isEmpty) {
      if (q.isNotEmpty) {
        out.add(_emptySearch(context));
      } else if (isArchivedTab) {
        out.add(
          _emptyState(
            context,
            icon: LucideIcons.archive,
            title: 'Nenhuma conversa arquivada',
            body:
                'Conversa que você arquivar no sistema web sai de Todas e '
                'fica guardada aqui. Mensagem nova nela não acende o aviso '
                'do chat.',
          ),
        );
      } else {
        out.add(
          _emptyState(
            context,
            icon: LucideIcons.messagesSquare,
            title: 'Nenhuma conversa ainda',
            body:
                'Para falar com alguém da equipe, abra Colaboradores e toque '
                'no nome da pessoa.',
            actionLabel: 'Ver colaboradores',
            actionIcon: LucideIcons.usersRound,
            onAction: () => _tabController.animateTo(2),
          ),
        );
      }
      return out;
    }

    for (final room in rooms) {
      out.add(
        ChatRoomListItem(
          key: ValueKey('room-${room.id}'),
          room: room,
          currentUserId: _currentUserId,
          isSelected: _selectedRoom?.id == room.id,
          onTap: () => _selectRoom(room),
        ),
      );
    }
    return out;
  }

  List<Widget> _usersBody(BuildContext context) {
    if (_isLoadingUsers && _companyUsers.isEmpty) {
      return List.generate(8, (_) => _rowSkeleton(context, avatar: 44));
    }
    if (_usersError != null && _companyUsers.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: AppErrorState.fromApi(
            message: _usersError,
            statusCode: _usersErrorStatus,
            onRetry: _loadCompanyUsers,
            dense: true,
          ),
        ),
      ];
    }

    final q = _query.trim().toLowerCase();
    final users = q.isEmpty
        ? _companyUsers
        : _companyUsers.where((u) => _userMatches(u, q)).toList();

    final out = <Widget>[];
    if (_usersError != null) {
      out.add(_refreshFailedStrip(context, onRetry: _loadCompanyUsers));
    }
    if (users.isEmpty) {
      out.add(
        q.isNotEmpty
            ? _emptySearch(context)
            : _emptyState(
                context,
                icon: LucideIcons.usersRound,
                title: 'Nenhum colega encontrado',
                body:
                    'Aparecem aqui as pessoas da sua empresa com acesso ao '
                    'sistema. Se alguém faltar, peça ao administrador para '
                    'liberar o acesso.',
              ),
      );
      return out;
    }
    for (final user in users) {
      out.add(_userRow(context, user));
    }
    return out;
  }

  /// Colega em linha flush (antes: cartão com borda). Ponto verde só quando
  /// o back diz que a pessoa está online; a linha inteira abre a conversa.
  Widget _userRow(BuildContext context, CompanyUser user) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final ink = chatInk(context);
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final name = user.name.trim().isEmpty ? 'Sem nome' : user.name.trim();
    final opening = _openingUserId == user.id;
    final subtitle = [
      if (user.isOnline) 'Online agora',
      if (user.email.trim().isNotEmpty) user.email.trim(),
    ].join(' · ');

    return Semantics(
      button: true,
      label:
          'Conversar com $name${user.isOnline ? ', online agora' : ''}',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openingUserId == null
              ? () => _startConversationWithUser(user)
              : null,
          child: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      WhatsAppAvatar(
                        name: name,
                        imageUrl: user.avatar,
                        size: 44,
                      ),
                      if (user.isOnline)
                        Positioned(
                          right: -1,
                          bottom: -1,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: green,
                              border: Border.all(
                                color: ThemeHelpers.backgroundColor(context),
                                width: 2.5,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(0, 11, 8, 11),
                    decoration: BoxDecoration(
                      border: Border(bottom: chatHairline(context)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                  height: 1.2,
                                ),
                              ),
                              if (subtitle.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: secondary,
                                    fontSize: 13,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: Center(
                            child: opening
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: ink,
                                    ),
                                  )
                                : Icon(
                                    LucideIcons.messageSquarePlus,
                                    size: 20,
                                    color: ink,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Esqueleto fiel à linha (avatar redondo + nome/hora + prévia, filete só
  /// sob o texto).
  Widget _rowSkeleton(BuildContext context, {required double avatar}) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SkeletonBox(
              width: avatar,
              height: avatar,
              borderRadius: 999,
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(0, 15, 16, 15),
              decoration: BoxDecoration(
                border: Border(bottom: chatHairline(context)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SkeletonText(
                          width: 150,
                          height: 15,
                          borderRadius: 999,
                        ),
                      ),
                      SizedBox(width: 8),
                      SkeletonText(width: 36, height: 11, borderRadius: 999),
                    ],
                  ),
                  SizedBox(height: 9),
                  SkeletonText(
                    width: double.infinity,
                    height: 13,
                    borderRadius: 999,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Vazio que ensina: o que aparece aqui e como chegar lá.
  Widget _emptyState(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
    String? actionLabel,
    IconData? actionIcon,
    VoidCallback? onAction,
    bool neutralAction = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = chatInk(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final actionColor = neutralAction ? secondary : ink;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 12),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ink.withValues(alpha: isDark ? 0.16 : 0.08),
            ),
            child: Icon(icon, color: ink, size: 26),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w800,
              fontSize: 16,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(color: secondary, fontSize: 13, height: 1.4),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: Icon(actionIcon ?? LucideIcons.chevronRight, size: 16),
              label: Text(
                actionLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: actionColor,
                side: BorderSide(color: actionColor.withValues(alpha: 0.45)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptySearch(BuildContext context) {
    final isUsers = _tabController.index == 2;
    return _emptyState(
      context,
      icon: LucideIcons.searchX,
      title: 'Nada encontrado para "${_query.trim()}"',
      body: isUsers
          ? 'Busque pelo nome ou pelo e-mail do colega.'
          : 'Busque pelo nome da pessoa, do grupo ou por um trecho da '
                'última mensagem.',
      actionLabel: 'Limpar busca',
      actionIcon: LucideIcons.x,
      onAction: _clearSearch,
      neutralAction: true,
    );
  }

  /// A atualização falhou mas há lista na tela: avisa sem apagar nada.
  Widget _refreshFailedStrip(
    BuildContext context, {
    required Future<void> Function() onRetry,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: isDark ? 0.12 : 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.triangleAlert,
            size: 16,
            color: isDark
                ? AppColors.message.warningTextDarkMode
                : AppColors.message.warningText,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Não deu para atualizar agora. Esta é a última lista carregada.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: textColor),
            child: const Text('Tentar de novo', maxLines: 1),
          ),
        ],
      ),
    );
  }

  // ─── Conversa ────────────────────────────────────────────────────────────

  String _roomSubtitle(ChatRoom room) {
    final parts = <String>[];
    switch (room.type) {
      case ChatRoomType.group:
        final n = room.participants.where((p) => p.isActive).length;
        parts.add(
          n > 0
              ? 'Grupo · ${_plural(n, 'participante', 'participantes')}'
              : 'Grupo',
        );
        break;
      case ChatRoomType.support:
        parts.add('Suporte');
        break;
      case ChatRoomType.direct:
        parts.add('Conversa individual');
        break;
    }
    if (room.isMuted == true) parts.add('silenciada');
    if (room.isArchived == true) parts.add('arquivada');
    return parts.join(' · ');
  }

  /// Cabeçalho da conversa no molde do WhatsApp do app: voltar (celular),
  /// avatar, nome e uma linha de estado (tipo, silenciada, arquivada). A
  /// barra do topo diz só "Chat": antes o nome aparecia duas vezes.
  Widget _buildConversationHeader(
    BuildContext context,
    ChatRoom room,
    bool isSmallScreen,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final name = room.getDisplayName(_currentUserId);

    return Container(
      padding: EdgeInsets.fromLTRB(isSmallScreen ? 4 : 16, 6, 4, 6),
      decoration: BoxDecoration(border: Border(bottom: chatHairline(context))),
      child: Row(
        children: [
          if (isSmallScreen)
            IconButton(
              tooltip: 'Voltar para as conversas',
              onPressed: () => setState(() => _selectedRoom = null),
              icon: Icon(LucideIcons.arrowLeft, size: 21, color: textColor),
            ),
          WhatsAppAvatar(
            name: name,
            imageUrl: room.getDisplayImage(_currentUserId),
            size: 40,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (room.isMuted == true) ...[
                      Icon(LucideIcons.bellOff, size: 12, color: secondary),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        _roomSubtitle(room),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: secondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Mais opções',
            icon: Icon(
              LucideIcons.ellipsisVertical,
              size: 19,
              color: secondary,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            color: ThemeHelpers.cardBackgroundColor(context),
            onSelected: (value) {
              if (value == 'delete') _showDeleteChatDialog(context, room);
            },
            itemBuilder: (ctx) => [
              PopupMenuItem<String>(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(LucideIcons.trash2, size: 16, color: danger),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'Excluir conversa',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Tablet sem conversa aberta: diz o que fazer, não só "selecione".
  Widget _buildNoSelection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = chatInk(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ink.withValues(alpha: isDark ? 0.16 : 0.08),
                      ),
                      child: Icon(
                        LucideIcons.messagesSquare,
                        color: ink,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Escolha uma conversa',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: ThemeHelpers.textColor(context),
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'As mensagens aparecem aqui. Para falar com alguém '
                      'novo, abra Colaboradores na lista ao lado.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: ThemeHelpers.textSecondaryColor(context),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessagesArea(BuildContext context, ThemeData theme) {
    final room = _selectedRoom;
    if (room == null) return _buildNoSelection(context);

    final isSmallScreen = MediaQuery.sizeOf(context).width < 600;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Paisagem com teclado sobra ~130dp: o cabeçalho sai (volta ao
        // fechar o teclado) e o campo fica em até 2 linhas. O campo tem
        // chave e não muda de lugar na árvore — o teclado não fecha.
        final tight = keyboardOpen && constraints.maxHeight < 300;
        final hideHeader = keyboardOpen && constraints.maxHeight < 240;
        // Rede de segurança: com arquivo escolhido + texto longo em tela
        // muito baixa, o campo rola por dentro em vez de estourar a coluna.
        final inputMax = math.max(
          56.0,
          constraints.maxHeight - (hideHeader ? 36.0 : 96.0),
        );

        return Column(
          children: [
            if (!hideHeader)
              KeyedSubtree(
                key: const ValueKey('chat-conversation-header'),
                child: _buildConversationHeader(context, room, isSmallScreen),
              ),
            Expanded(
              key: const ValueKey('chat-conversation-thread'),
              child: _isLoadingMessages
                  ? _buildMessagesShimmer(context)
                  : ChatMessageList(
                      messages: _messages,
                      currentUserId: _currentUserId,
                      scrollController: _messagesScrollController,
                      isGroup: room.type != ChatRoomType.direct,
                      peerName: room.type == ChatRoomType.direct
                          ? room.getDisplayName(_currentUserId)
                          : null,
                      onLoadMore: () {
                        if (!_isLoadingMessages) {
                          _loadMessages(room.id, loadMore: true);
                        }
                      },
                    ),
            ),
            ConstrainedBox(
              key: const ValueKey('chat-conversation-input'),
              constraints: BoxConstraints(maxHeight: inputMax),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: ChatInput(
                  onSend: _handleSendMessage,
                  maxLines: tight ? 2 : 5,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Esqueleto fiel à conversa: bolhas dos dois lados, algumas agrupadas.
  Widget _buildMessagesShimmer(BuildContext context) {
    Widget bubble({
      required bool own,
      required double width,
      bool grouped = false,
      double height = 44,
    }) {
      return Align(
        alignment: own ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.only(bottom: grouped ? 2 : 8),
          child: SkeletonBox(width: width, height: height, borderRadius: 18),
        ),
      );
    }

    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      children: [
        bubble(own: false, width: 210, height: 54),
        bubble(own: true, width: 180, grouped: true),
        bubble(own: true, width: 140),
        bubble(own: false, width: 236, grouped: true, height: 62),
        bubble(own: false, width: 150),
        bubble(own: true, width: 216, height: 54),
        bubble(own: false, width: 190),
      ],
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
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isSmallScreen = width < 600;
    final currentRoute = ModalRoute.of(context)?.settings.name;
    final navIndex = AppBottomNavigation.getIndexForRoute(currentRoute);

    // Notificar controller sobre a sala aberta quando o widget é construído
    ChatUnreadController.instance.setCurrentlyOpenRoom(_selectedRoom?.id);

    // Lista ao lado da conversa (tablet/paisagem larga): nem estreita demais
    // para o nome, nem 350 fixos numa tela de 1200.
    final sidebarWidth = (width * 0.36).clamp(300.0, 380.0).toDouble();

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
        // O nome da conversa fica no cabeçalho dela (com avatar e estado).
        title: 'Chat',
        showDrawer: true,
        showBottomNavigation: true,
        currentBottomNavIndex: navIndex,
        body: isSmallScreen
            ? (_selectedRoom != null
                  ? _buildMessagesArea(context, theme)
                  : _buildRoomsList(context, theme))
            : Row(
                children: [
                  // Lista de conversas (sidebar)
                  Container(
                    width: sidebarWidth,
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
                  Expanded(child: _buildMessagesArea(context, theme)),
                ],
              ),
      ),
    );
  }
}
