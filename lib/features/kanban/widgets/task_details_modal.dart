import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/minimal_body_chrome.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/services/secure_storage_service.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/kanban_analytics_service.dart';
import '../../../shared/utils/jwt_utils.dart';
import '../../../shared/utils/masks.dart';
import '../../appointments/models/appointment_model.dart';
import '../../appointments/services/appointment_service.dart';
import '../models/kanban_models.dart';
import '../services/kanban_service.dart';
import '../controllers/kanban_controller.dart';
import 'subtask_manager.dart';
import 'mark_task_result_sheet.dart';
import 'task_edit_sheets.dart';
import 'transfer_task_sheet.dart';

// ─── Paleta da aba Detalhes — cor por seção (coerência ≠ uniformidade) ───────
// O vermelho da marca fica reservado pra identidade (hero/tabs) e estados
// críticos (atrasada, perdido, destrutivo). Cada seção fala na sua família.
const Color _kBriefingTone = Color(0xFF6366F1); // indigo — texto editorial
const Color _kDossierTone = Color(0xFF0891B2); // cyan — ficha técnica/dados
const Color _kContactTone = Color(0xFF059669); // emerald — contato/lead
const Color _kPeopleTone = Color(0xFF8B5CF6); // violet — pessoas/equipe
const Color _kTagsTone = Color(0xFFD97706); // amber — categorias
const Color _kAuditTone = Color(0xFF64748B); // slate — auditoria/tempo
const Color _kChatTone = Color(0xFF3B82F6); // blue — comunicação
const Color _kInternalTone = Color(0xFFE6B84C); // âmbar queimado — nota interna
const Color _kLinksTone = Color(0xFF0EA5E9); // sky — vínculos (cliente/imóvel)

/// Cyan — mesma família do RAIO-X: dado e documento são a mesma natureza
/// (o que está registrado sobre a negociação).
const Color _kFilesTone = Color(0xFF0891B2);

/// Magenta — agenda. Era a única família livre e legível ao lado do violeta
/// de PESSOAS: compromisso é hora marcada, não gente.
const Color _kAgendaTone = Color(0xFFDB2777);

/// Indigo profundo — rotas/transferências. É o MESMO tom do sheet de
/// transferência (`_routeInk`), então o histórico e a ação falam igual.
const Color _kRouteTone = Color(0xFF4F46E5);

/// Destaque da menção dentro do texto do comentário. Fica na família da
/// conversa (azul), nunca no vermelho da marca.
const Color _kMentionTone = Color(0xFF2563EB);

/// Teal — pessoas ENVOLVIDAS (quem acompanha o card sem ser o dono). Não
/// repete o violeta de EQUIPE de propósito: responsável/criador é autoria,
/// envolvido é a rede em volta — duas coisas diferentes na mesma aba.
const Color _kInvolvedTone = Color(0xFF14B8A6);

/// Verde de confirmar/salvar da casa (o mesmo dos sheets de edição).
const Color _kConfirmGreen = kTaskEditGreen;

/// Vermelho de ação destrutiva (excluir) — nunca usado para cancelar.
const Color _kDangerRed = Color(0xFFDC2626);

/// Cor estável derivada do nome — cada pessoa tem a sua (mesma mecânica do
/// `_tagColor`). Sem nome → slate. Substitui o avatar vermelho uniforme.
Color _personColor(String? name) {
  if (name == null || name.trim().isEmpty) return const Color(0xFF64748B);
  const palette = [
    Color(0xFF0EA5E9),
    Color(0xFF14B8A6),
    Color(0xFF6366F1),
    Color(0xFFF97316),
    Color(0xFF22C55E),
    Color(0xFFEC4899),
    Color(0xFFA855F7),
    Color(0xFF0891B2),
  ];
  var h = 0;
  for (final c in name.trim().toLowerCase().codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return palette[h % palette.length];
}

/// **TELA** completa de detalhes do card (negociação do funil).
///
/// > **Nome do arquivo é histórico.** Isto nasceu como bottom sheet
/// > (`TaskDetailsModal`) e virou tela quando o conteúdo passou do que um
/// > sheet aguenta — "informações demais para um modal". O arquivo continua
/// > `task_details_modal.dart` de propósito: mover ~4.7k linhas muito
/// > refinadas seria risco sem ganho. A classe é [TaskDetailsPage] e a
/// > navegação é por rota (`adaptivePageRoute`), nunca `showModalBottomSheet`.
///
/// Conceito **editorial**: hierarquia tipográfica forte, sem sombras pesadas
/// nem gradientes coloridos no fundo dos blocos. Estados (em dia, vence hoje,
/// atrasada, concluída) são sinalizados pelas pílulas de meta-status do hero.
/// A intenção é que a tela pareça um documento estruturado, não uma sopa de
/// cards coloridos — mais legível no modo claro e ainda elegante no escuro.
///
/// Anatomia: `AppScaffold` (back + título do lead + copiar ID na barra) e o
/// corpo em `Column` → hero · abas coloridas · `TabBarView`. Sem grabber, sem
/// altura calculada e sem "modo digitação": o `Scaffold` já reage ao teclado.
class TaskDetailsPage extends StatefulWidget {
  final KanbanTask task;

  const TaskDetailsPage({super.key, required this.task});

  @override
  State<TaskDetailsPage> createState() => _TaskDetailsPageState();
}

class _TaskDetailsPageState extends State<TaskDetailsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final KanbanService _kanbanService = KanbanService.instance;

  // Comentários
  List<KanbanTaskComment> _comments = [];
  bool _loadingComments = false;
  String? _commentsError;
  int _commentsErrorStatus = 0;
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocus = FocusNode();
  final List<File> _selectedFiles = [];
  bool _submittingComment = false;
  int _commentLength = 0;

  // ─── MENÇÕES E RESPOSTA ───────────────────────────────────────────────────
  // O `@` abre o autocomplete DENTRO do composer (painel acima do campo, nunca
  // um overlay que o teclado empurra para fora). A lista de membros é a MESMA
  // fonte do web (`/users/company-members/simple`) e serve também aos
  // envolvidos e aos convidados da agenda — uma requisição para as três.
  List<KanbanUser> _members = const [];
  bool _loadingMembers = false;
  bool _didLoadMembers = false;

  /// Trecho `@…` sendo digitado agora: início do `@` no texto e o termo.
  int? _mentionAnchor;
  String _mentionQuery = '';

  /// Quem já foi escolhido no autocomplete desta mensagem (vira
  /// `mentionedUserIds` no POST — o backend também aceita `@[uuid]` no texto,
  /// mas o campo explícito é o caminho limpo).
  final List<KanbanUser> _pendingMentions = [];

  /// Comentário sendo respondido (`parentCommentId`). A lista do backend é
  /// plana; quem monta a thread é a tela.
  KanbanTaskComment? _replyTo;

  // Histórico
  List<HistoryEntry> _history = [];
  bool _loadingHistory = false;
  String? _historyError;
  int _historyErrorStatus = 0;

  String? _currentUserId;

  /// Campos completos do card (inclui cliente com telefone) carregados via
  /// `GET /kanban/tasks/:id/fields`. A listagem das colunas não traz telefone.
  KanbanTask? _detailedTask;

  /// Payload CRU do mesmo `GET /kanban/tasks/:id/fields`. O modelo
  /// `KanbanTask` não carrega `internalNotes` nem o imóvel vinculado, e a
  /// tela precisa dos dois para editar — então o mapa original fica guardado
  /// junto do card já parseado (uma requisição só serve aos dois).
  Map<String, dynamic>? _rawFields;

  /// Movimentação de etapa em curso — trava toques repetidos no trilho.
  bool _movingStage = false;

  // ─── EDIÇÃO INLINE ────────────────────────────────────────────────────────
  // Título e briefing viram campo na própria tela (sem sheet): quem está
  // lendo a ficha corrige o que está errado onde o erro aparece.
  final TextEditingController _titleCtrl = TextEditingController();
  bool _editingTitle = false;
  bool _savingTitle = false;


  final TextEditingController _notesCtrl = TextEditingController();
  bool _editingNotes = false;
  bool _savingNotes = false;

  /// Campo do RAIO-X / vínculos gravando agora — o spinner nasce na própria
  /// célula tocada (nunca um overlay na tela inteira).
  String? _savingField;

  /// Última ligação registrada NESTA sessão — base da confirmação
  /// anti-duplicata (< 2 min pergunta antes de registrar outra).
  DateTime? _lastCallAt;
  bool _registeringCall = false;

  /// Imóvel escolhido nesta sessão. A API do card não devolve o imóvel
  /// vinculado de forma garantida, então o rótulo recém-escolhido fica aqui
  /// para a linha de vínculo não voltar a dizer "Não vinculado".
  String? _linkedPropertyLabel;

  bool _deleting = false;

  /// Coluna destino enquanto o movimento está em voo — o trilho pinta o
  /// alvo com spinner, então o feedback nasce onde o dedo tocou.
  String? _movingToColumnId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
    _tabController.addListener(_onTabChanged);
    _commentController.addListener(_onCommentTextChanged);
    _commentFocus.addListener(() => setState(() {}));
    _loadCurrentUserId();
    _loadComments();
    _loadTaskFields();
    _ensureMembers();
  }

  /// Reavalia o texto do composer a cada tecla: contador + detecção do `@`.
  ///
  /// A âncora é o `@` mais recente ANTES do cursor que ainda não virou frase
  /// (sem quebra de linha e com no máximo duas palavras depois dele — nomes
  /// compostos precisam de fôlego). Fora disso o painel fecha.
  void _onCommentTextChanged() {
    if (!mounted) return;
    final text = _commentController.text;
    final sel = _commentController.selection;
    final cursor = (sel.isValid ? sel.baseOffset : text.length)
        .clamp(0, text.length)
        .toInt();

    int? anchor;
    var query = '';
    final at = text.lastIndexOf('@', cursor > 0 ? cursor - 1 : 0);
    if (at >= 0 && (at == 0 || _isMentionBoundary(text[at - 1]))) {
      final term = text.substring(at + 1, cursor);
      // Termo com espaço no fim = menção já fechada (ou um `@` solto): o
      // painel some em vez de ficar aberto atrás do resto da frase.
      if (!term.contains('\n') &&
          !term.endsWith(' ') &&
          term.length <= 32 &&
          term.split(' ').length <= 3) {
        anchor = at;
        query = term;
      }
    }

    setState(() {
      _commentLength = text.length;
      _mentionAnchor = anchor;
      _mentionQuery = query;
    });
    if (anchor != null) _ensureMembers();
  }

  static bool _isMentionBoundary(String char) =>
      char == ' ' || char == '\n' || char == '(' || char == '\t';

  /// Sugestões do `@` — no máximo 6, sem repetir quem já foi mencionado.
  List<KanbanUser> get _mentionSuggestions {
    if (_mentionAnchor == null) return const [];
    final q = _mentionQuery.trim().toLowerCase();
    final chosen = _pendingMentions.map((u) => u.id).toSet();
    final list = _members.where((u) {
      if (chosen.contains(u.id)) return false;
      if (q.isEmpty) return true;
      return u.name.toLowerCase().contains(q) ||
          u.email.toLowerCase().contains(q);
    }).toList();
    return list.length > 6 ? list.sublist(0, 6) : list;
  }

  /// Troca o `@termo` pelo `@Nome ` e guarda o id para o POST.
  void _applyMention(KanbanUser user) {
    final anchor = _mentionAnchor;
    if (anchor == null) return;
    final text = _commentController.text;
    final sel = _commentController.selection;
    final cursor = (sel.isValid ? sel.baseOffset : text.length)
        .clamp(0, text.length)
        .toInt();
    final safeEnd = cursor < anchor ? anchor : cursor;
    final inserted = '@${user.name} ';
    final novo = text.replaceRange(anchor, safeEnd, inserted);
    _commentController.value = TextEditingValue(
      text: novo,
      selection: TextSelection.collapsed(offset: anchor + inserted.length),
    );
    setState(() {
      if (!_pendingMentions.any((u) => u.id == user.id)) {
        _pendingMentions.add(user);
      }
      _mentionAnchor = null;
      _mentionQuery = '';
    });
  }

  /// Membros da empresa (fonte das menções, dos envolvidos e dos convidados).
  Future<void> _ensureMembers() async {
    if (_didLoadMembers || _loadingMembers) return;
    setState(() => _loadingMembers = true);
    final r = await _kanbanService.getCompanyMembersSimple();
    if (!mounted) return;
    setState(() {
      _loadingMembers = false;
      _didLoadMembers = true;
      if (r.success && r.data != null) _members = r.data!;
    });
  }

  /// Recarrega o card completo para obter o cliente/lead com telefone,
  /// WhatsApp etc. (a listagem do board omite esses campos).
  ///
  /// Vai no CRU (`ApiService`) em vez do `getTaskById` porque o mesmo
  /// payload carrega campos que o modelo não parseia — `internalNotes` e o
  /// imóvel vinculado — e a tela agora os edita. O `KanbanTask` continua
  /// saindo do mesmo mapa via `fromJson`, então é uma requisição só.
  Future<void> _loadTaskFields() async {
    try {
      final r = await ApiService.instance.get<Map<String, dynamic>>(
        ApiConstants.kanbanTaskFields(widget.task.id),
      );
      if (!mounted) return;
      if (r.success && r.data != null) {
        final map = r.data!;
        KanbanTask? parsed;
        try {
          parsed = KanbanTask.fromJson(map);
        } catch (e) {
          debugPrint('⚠️ [TASK_DETAILS] Erro ao parsear campos do card: $e');
        }
        setState(() {
          _rawFields = map;
          if (parsed != null) _detailedTask = parsed;
          if (!_editingNotes) _notesCtrl.text = _internalNotes ?? '';
        });
      }
    } catch (e) {
      debugPrint('⚠️ [TASK_DETAILS] Erro ao carregar campos do card: $e');
    }
  }

  /// Pessoas envolvidas vindas do payload cru — o `KanbanTask` não carrega
  /// `involvedUsers`, mas o `GET /kanban/tasks/:id/fields` (que é o
  /// `getTaskById` do backend) traz o array populado.
  List<KanbanUser> get _involvedUsers {
    final raw = _rawFields?['involvedUsers'];
    if (raw is! List) return const [];
    final out = <KanbanUser>[];
    for (final item in raw) {
      if (item is! Map) continue;
      try {
        final u = KanbanUser.fromJson(Map<String, dynamic>.from(item));
        if (u.id.isNotEmpty) out.add(u);
      } catch (e) {
        debugPrint('⚠️ [TASK_DETAILS] parse envolvido: $e');
      }
    }
    return out;
  }

  /// Abre o multi-seletor e grava a lista inteira
  /// (`PUT /kanban/tasks/:id/involved-users` substitui o conjunto).
  Future<void> _manageInvolvedUsers() async {
    await _ensureMembers();
    if (!mounted) return;
    final escolhidos = await TaskPeopleMultiSelectSheet.show(
      context,
      eyebrow: 'Envolvidos',
      title: 'Quem mais acompanha este card?',
      tone: _kInvolvedTone,
      confirmLabel: 'Salvar envolvidos',
      initialSelected: _involvedUsers,
      preloaded: _members.isEmpty ? null : _members,
      emptyHint: 'Ninguém acompanhando além do responsável.',
    );
    if (escolhidos == null || !mounted) return;
    await _saveInvolvedUsers(escolhidos.map((u) => u.id).toList());
  }

  Future<void> _removeInvolvedUser(KanbanUser user) async {
    final restante = _involvedUsers
        .where((u) => u.id != user.id)
        .map((u) => u.id)
        .toList();
    await _saveInvolvedUsers(restante);
  }

  Future<void> _saveInvolvedUsers(List<String> userIds) async {
    setState(() => _savingField = 'involvedUsers');
    final r = await _kanbanService.setInvolvedUsers(widget.task.id, userIds);
    if (!mounted) return;
    if (r.success) {
      // A lista mora no payload cru — recarregar é o que a repinta.
      await _loadTaskFields();
      if (!mounted) return;
      setState(() => _savingField = null);
      _snack('Pessoas envolvidas atualizadas', ok: true);
    } else {
      setState(() => _savingField = null);
      _snack(r.message ?? 'Erro ao salvar envolvidos', erro: true);
    }
  }

  /// Observação interna vinda do payload cru (o modelo não tem o campo).
  String? get _internalNotes {
    final v = _rawFields?['internalNotes'];
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  /// Imóvel vinculado: rótulo escolhido nesta sessão manda; senão o que o
  /// payload cru trouxer (`property.title` / `property.code`).
  String? get _propertyLabel {
    if (_linkedPropertyLabel != null) return _linkedPropertyLabel;
    final raw = _rawFields?['property'];
    if (raw is Map) {
      final title = raw['title']?.toString().trim();
      if (title != null && title.isNotEmpty) return title;
      final name = raw['name']?.toString().trim();
      if (name != null && name.isNotEmpty) return name;
      final code = raw['code']?.toString().trim();
      if (code != null && code.isNotEmpty) return 'Imóvel $code';
    }
    final id = _rawFields?['propertyId']?.toString().trim();
    if (id != null && id.isNotEmpty) return 'Imóvel vinculado';
    return null;
  }

  String? get _propertyId {
    final raw = _rawFields?['property'];
    if (raw is Map) {
      final id = raw['id']?.toString().trim();
      if (id != null && id.isNotEmpty) return id;
    }
    final id = _rawFields?['propertyId']?.toString().trim();
    return (id == null || id.isEmpty) ? null : id;
  }

  void _onTabChanged() {
    if (!mounted) return;
    setState(() {});
    final i = _tabController.index;
    if (i == 1) {
      if (!_didLoadJourney) _loadJourney();
      // Transferências moram na MESMA aba da jornada: mudar de funil é o
      // movimento mais largo que o card faz.
      if (!_didLoadTransfers) _loadTransferHistory();
    }
    if (i == 4 && !_didLoadFiles) {
      _loadTaskFiles();
    }
    if (i == 5 && !_didLoadAppointments) {
      _loadAppointments();
    }
    if (i == 6 && _canViewTaskAnalytics && !_didLoadMetrics) {
      _loadTaskMetrics();
    }
    if (i == 7 && _history.isEmpty && !_loadingHistory) {
      _loadHistory();
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _commentController.removeListener(_onCommentTextChanged);
    _commentController.dispose();
    _commentFocus.dispose();
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // DATA
  // ---------------------------------------------------------------------------

  Future<void> _loadCurrentUserId() async {
    try {
      final token = await SecureStorageService.instance.getAccessToken();
      if (token != null) {
        final payload = JwtUtils.decodeToken(token);
        if (payload != null && mounted) {
          setState(() {
            _currentUserId = payload['sub']?.toString() ??
                payload['userId']?.toString();
          });
        }
      }
    } catch (e) {
      debugPrint('⚠️ [TASK_DETAILS] Erro ao obter userId: $e');
    }
  }

  Future<void> _loadComments() async {
    setState(() {
      _loadingComments = true;
      _commentsError = null;
    });
    try {
      final response = await _kanbanService.listComments(widget.task.id);
      if (!mounted) return;
      if (response.success && response.data != null) {
        setState(() {
          _comments = response.data!;
          _loadingComments = false;
        });
      } else {
        setState(() {
          _commentsError = response.message;
          _commentsErrorStatus = response.statusCode;
          _loadingComments = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _commentsError = 'Erro ao carregar comentários: $e';
        _loadingComments = false;
      });
    }
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loadingHistory = true;
      _historyError = null;
    });
    try {
      final response = await _kanbanService.getTaskHistory(widget.task.id);
      if (!mounted) return;
      if (response.success && response.data != null) {
        setState(() {
          _history = response.data!;
          _loadingHistory = false;
        });
      } else {
        setState(() {
          _historyError = response.message;
          _historyErrorStatus = response.statusCode;
          _loadingHistory = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _historyError = 'Erro ao carregar histórico: $e';
        _loadingHistory = false;
      });
    }
  }

  Future<void> _selectFiles() async {
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );
      if (result != null && result.files.isNotEmpty) {
        final files = result.files
            .where((f) => f.path != null)
            .map((f) => File(f.path!))
            .toList();
        if (_selectedFiles.length + files.length > 10) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Máximo de 10 arquivos por comentário'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
        setState(() => _selectedFiles.addAll(files));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao selecionar arquivos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _removeFile(int index) {
    setState(() => _selectedFiles.removeAt(index));
  }

  Future<void> _submitComment() async {
    final message = _commentController.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mensagem não pode estar vazia'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (message.length > 2000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mensagem não pode exceder 2000 caracteres'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _submittingComment = true);
    try {
      // Só vão os ids cujo `@Nome` sobreviveu ao texto final (a pessoa pode
      // ter apagado a menção depois de escolher).
      final mentionIds = _pendingMentions
          .where((u) => message.contains('@${u.name}'))
          .map((u) => u.id)
          .toList();
      final response = await _kanbanService.createComment(
        widget.task.id,
        message,
        _selectedFiles.isNotEmpty ? _selectedFiles : null,
        mentionedUserIds: mentionIds.isEmpty ? null : mentionIds,
        parentCommentId: _replyTo?.id,
      );
      if (!mounted) return;
      if (response.success && response.data != null) {
        setState(() {
          _comments.add(response.data!);
          _commentController.clear();
          _selectedFiles.clear();
          _pendingMentions.clear();
          _replyTo = null;
          _mentionAnchor = null;
          _mentionQuery = '';
          _submittingComment = false;
        });
        // Enviou → teclado sai da frente: o hero volta e a mensagem recém
        // criada aparece na lista (antes o teclado seguia aberto e a pessoa
        // não via o que tinha acabado de escrever entrar).
        _commentFocus.unfocus();
        FocusScope.of(context).unfocus();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Comentário criado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        setState(() => _submittingComment = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.message ?? 'Erro ao criar comentário'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submittingComment = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao criar comentário: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteComment(String commentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir comentário'),
        content: const Text('Tem certeza que deseja excluir este comentário?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            // O tema global pinta TextButton de vermelho: cancelar não é
            // destrutivo, então a cor é forçada para o texto secundário.
            style: TextButton.styleFrom(
              foregroundColor: ThemeHelpers.textSecondaryColor(context),
            ),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: _kDangerRed),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final response =
          await _kanbanService.deleteComment(widget.task.id, commentId);
      if (!mounted) return;
      if (response.success) {
        setState(() {
          _comments.removeWhere((c) => c.id == commentId);
          // Respondendo a um comentário que acabou de sumir → o banner some
          // junto (senão o POST iria com um `parentCommentId` inválido).
          if (_replyTo?.id == commentId) _replyTo = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Comentário excluído'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.message ?? 'Erro ao excluir comentário'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao excluir comentário: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  bool _canDeleteComment(KanbanTaskComment comment) =>
      _currentUserId != null && comment.userId == _currentUserId;

  /// Card atualizado após marcar resultado / mover no board (paridade com detalhe web).
  KanbanTask _mergedTask(KanbanController c) {
    final id = widget.task.id;
    KanbanTask base = widget.task;
    final board = c.board;
    if (board != null) {
      for (final t in board.tasks) {
        if (t.id == id) {
          base = t;
          break;
        }
      }
    }
    // A listagem do board não traz o cliente completo (sem telefone);
    // sobrepõe os campos completos quando já carregados.
    if (_detailedTask != null) {
      base = base.copyWith(
        clientId: _detailedTask!.clientId,
        client: _detailedTask!.client,
        // Contatos avulsos também: lead sem cliente vinculado só tem telefone
        // aqui, e é ele que alimenta a seção Contato.
        contacts: _detailedTask!.contacts,
      );
    }
    return base;
  }

  void _openMarkResultSheet(
    BuildContext context,
    KanbanTask task, {
    String? quickEntry,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (ctx) =>
          MarkTaskResultSheet(task: task, quickEntry: quickEntry),
    );
  }

  // ---------------------------------------------------------------------------
  // ESCRITA — a ficha é VIVA
  // ---------------------------------------------------------------------------
  //
  // Regra de sincronia (uma só, para não haver dois caminhos):
  // • tudo que cabe no `UpdateTaskDto` vai pelo `KanbanController.updateTask`,
  //   que troca a task dentro do board e chama `notifyListeners()` — o board
  //   atrás e esta tela (que vive num `ListenableBuilder` + `_mergedTask`)
  //   repintam juntos, sem callback nem resultado de pop;
  // • o que só existe em `updateTaskFields` (valor, observação interna) não
  //   passa pelo controller: depois de gravar, o valor recarrega o board
  //   inteiro (mesmo remédio que `deleteTask`/`markTaskResult` já usam) e a
  //   observação, que o board nem mostra, recarrega só o card.
  // Em TODOS os casos o payload cru é relido no fim (`_loadTaskFields`).

  KanbanTask get _taskNow => _mergedTask(KanbanController.instance);

  KanbanPermissions? get _perms => KanbanController.instance.permissions;

  bool get _canEdit => _perms?.canEditTasks ?? false;

  bool get _canDelete => _perms?.canDeleteTasks ?? false;

  /// Tags são de gestão: no CRM web só gestor/líder/admin mexem nelas
  /// (`canManageCardTags`). Sem esse flag no app, o papel do usuário faz o
  /// mesmo recorte — corretor comum VÊ as tags e não edita.
  bool get _canManageTags {
    if (!_canEdit) return false;
    final role =
        ModuleAccessService.instance.userRole?.toLowerCase().trim() ?? '';
    return role == 'master' || role == 'admin' || role == 'manager';
  }

  /// Funil de referência para os seletores (membros, clientes, imóveis).
  String? get _pickerProjectId {
    final t = _taskNow;
    final fromTask = t.projectId?.trim();
    if (fromTask != null && fromTask.isNotEmpty) return fromTask;
    final fromProject = t.project?.id.trim();
    if (fromProject != null && fromProject.isNotEmpty) return fromProject;
    final fromController = KanbanController.instance.projectId?.trim();
    if (fromController != null && fromController.isNotEmpty) {
      return fromController;
    }
    return null;
  }

  void _snack(String message, {bool erro = false, bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: erro
              ? _kDangerRed
              : ok
                  ? _kConfirmGreen
                  : null,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  /// Escrita pelo `UpdateTaskDto`.
  ///
  /// **`includeTags: false` é obrigatório em patch parcial**: o `toJson`
  /// sempre manda `tags` (o modal de edição depende disso para limpar), e
  /// sem o flag salvar a prioridade apagaria as tags do card.
  Future<bool> _patchTask(
    UpdateTaskDto dto, {
    KanbanTask Function(KanbanTask atual)? overlay,
    bool dropDetailed = false,
  }) async {
    final controller = KanbanController.instance;
    final ok = await controller.updateTask(widget.task.id, dto);
    if (!mounted) return false;
    if (!ok) {
      _snack(controller.error ?? 'Não foi possível salvar a alteração.',
          erro: true);
      return false;
    }
    // O overlay de `_detailedTask` é mais VELHO que a resposta que o
    // controller acabou de aplicar no board — ajusta antes do refetch para
    // a tela não piscar o dado antigo.
    if (dropDetailed) {
      setState(() => _detailedTask = null);
    } else if (overlay != null && _detailedTask != null) {
      setState(() => _detailedTask = overlay(_detailedTask!));
    }
    await _loadTaskFields();
    return true;
  }

  /// Escrita pelo `updateTaskFields` (valor, observação interna).
  Future<bool> _patchFields(
    UpdateTaskFieldsDto dto, {
    bool reloadBoard = false,
  }) async {
    final r = await _kanbanService.updateTaskFields(widget.task.id, dto);
    if (!mounted) return false;
    if (!r.success) {
      _snack(r.message ?? 'Não foi possível salvar a alteração.', erro: true);
      return false;
    }
    if (reloadBoard) {
      final c = KanbanController.instance;
      await c.loadBoard(teamId: c.teamId, projectId: c.projectId);
    }
    if (!mounted) return true;
    await _loadTaskFields();
    return true;
  }

  // ─── 1. REGISTRAR LIGAÇÃO ────────────────────────────────────────────────

  /// Ação mais repetida do corretor: um toque, sem formulário.
  ///
  /// Registrou há menos de 2 minutos nesta sessão? Pergunta antes — dedo
  /// duplo em botão grande é o erro mais provável aqui, e a ligação
  /// duplicada suja o histórico e as métricas de atividade.
  Future<void> _registerCall() async {
    if (_registeringCall) return;
    final last = _lastCallAt;
    if (last != null && DateTime.now().difference(last).inMinutes < 2) {
      final again = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Registrar outra ligação?'),
          content: const Text(
            'Você acabou de registrar uma ligação para este lead. Quer '
            'registrar mais uma?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(
                foregroundColor: ThemeHelpers.textSecondaryColor(ctx),
              ),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: _kConfirmGreen),
              child: const Text('Registrar'),
            ),
          ],
        ),
      );
      if (again != true || !mounted) return;
    }

    setState(() => _registeringCall = true);
    final r = await _kanbanService.registerTaskCall(widget.task.id);
    if (!mounted) return;
    setState(() => _registeringCall = false);
    if (!r.success) {
      _snack(r.message ?? 'Não foi possível registrar a ligação.', erro: true);
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _lastCallAt = DateTime.now());
    _snack('Ligação registrada no histórico', ok: true);
    if (_history.isNotEmpty) await _loadHistory();
  }

  // ─── 3. TÍTULO E BRIEFING (edição inline) ────────────────────────────────

  void _startTitleEdit() {
    _titleCtrl.text = _taskNow.title;
    setState(() => _editingTitle = true);
  }

  Future<void> _saveTitle() async {
    final novo = _titleCtrl.text.trim();
    if (novo.isEmpty) {
      _snack('O título não pode ficar vazio.', erro: true);
      return;
    }
    if (novo == _taskNow.title.trim()) {
      setState(() => _editingTitle = false);
      return;
    }
    setState(() => _savingTitle = true);
    final ok = await _patchTask(
      UpdateTaskDto(title: novo, includeTags: false),
      overlay: (t) => t.copyWith(title: novo),
    );
    if (!mounted) return;
    setState(() {
      _savingTitle = false;
      if (ok) _editingTitle = false;
    });
    if (ok) {
      HapticFeedback.selectionClick();
      _snack('Título atualizado', ok: true);
    }
  }

  // ─── 4. CAMPOS DO RAIO-X ─────────────────────────────────────────────────

  Future<void> _editPriority() async {
    final task = _taskNow;
    final escolha =
        await TaskPrioritySheet.show(context, current: task.priority);
    if (escolha == null || !mounted || escolha == task.priority) return;
    setState(() => _savingField = 'priority');
    final ok = await _patchTask(
      UpdateTaskDto(priority: escolha.name, includeTags: false),
      overlay: (t) => t.copyWith(priority: escolha),
    );
    if (!mounted) return;
    setState(() => _savingField = null);
    if (ok) {
      HapticFeedback.selectionClick();
      _snack('Prioridade: ${escolha.label}', ok: true);
    }
  }

  Future<void> _editDeadline() async {
    final task = _taskNow;
    final escolha =
        await TaskDeadlineSheet.show(context, current: task.dueDate);
    if (escolha == null || !mounted) return;
    setState(() => _savingField = 'dueDate');
    bool ok;
    if (escolha.clear) {
      ok = await _clearDueDate();
    } else {
      ok = await _patchTask(
        UpdateTaskDto(dueDate: escolha.date, includeTags: false),
        overlay: (t) => t.copyWith(dueDate: escolha.date),
      );
    }
    if (!mounted) return;
    setState(() => _savingField = null);
    if (ok) {
      HapticFeedback.selectionClick();
      _snack(
        escolha.clear
            ? 'Prazo removido'
            : 'Prazo: ${DateFormat("d 'de' MMMM", 'pt_BR').format(escolha.date!)}',
        ok: true,
      );
    }
  }

  /// Remover o prazo não cabe no `UpdateTaskDto` (o `toJson` só manda
  /// `dueDate` quando tem valor, então null nunca chegaria ao backend). O
  /// PUT vai cru no MESMO endpoint do serviço — nada de rota inventada — e
  /// o board recarrega logo em seguida, já que o controller não participou.
  Future<bool> _clearDueDate() async {
    try {
      final r = await ApiService.instance.put<Map<String, dynamic>>(
        ApiConstants.kanbanTaskById(widget.task.id),
        body: const {'dueDate': null},
      );
      if (!mounted) return false;
      if (!r.success) {
        _snack(r.message ?? 'Não foi possível remover o prazo.', erro: true);
        return false;
      }
      final c = KanbanController.instance;
      await c.loadBoard(teamId: c.teamId, projectId: c.projectId);
      if (!mounted) return true;
      await _loadTaskFields();
      return true;
    } catch (e) {
      if (mounted) _snack('Erro ao remover o prazo: $e', erro: true);
      return false;
    }
  }

  Future<void> _editValue() async {
    final novo = await TaskValueSheet.show(context, current: _taskNow.totalValue);
    if (novo == null || !mounted) return;
    setState(() => _savingField = 'totalValue');
    final ok = await _patchFields(
      UpdateTaskFieldsDto(totalValue: novo),
      reloadBoard: true,
    );
    if (!mounted) return;
    setState(() => _savingField = null);
    if (ok) {
      HapticFeedback.selectionClick();
      _snack('Valor da negociação atualizado', ok: true);
    }
  }

  Future<void> _editAssignee() async {
    final projectId = _pickerProjectId;
    if (projectId == null) {
      _snack('Funil do card não identificado.', erro: true);
      return;
    }
    final task = _taskNow;
    final escolhido = await TaskAssigneeSheet.show(
      context,
      projectId: projectId,
      currentUserId: task.assignedToId,
    );
    if (escolhido == null || !mounted || escolhido.id == task.assignedToId) {
      return;
    }
    setState(() => _savingField = 'assignedTo');
    final ok = await _patchTask(
      UpdateTaskDto(assignedToId: escolhido.id, includeTags: false),
      overlay: (t) =>
          t.copyWith(assignedToId: escolhido.id, assignedTo: escolhido),
    );
    if (!mounted) return;
    setState(() => _savingField = null);
    if (ok) {
      HapticFeedback.selectionClick();
      _snack('Responsável: ${escolhido.name}', ok: true);
    }
  }

  // ─── 5. OBSERVAÇÃO INTERNA ───────────────────────────────────────────────

  void _startNotesEdit() {
    _notesCtrl.text = _internalNotes ?? '';
    setState(() => _editingNotes = true);
  }

  Future<void> _saveNotes() async {
    final novo = _notesCtrl.text.trim();
    if (novo == (_internalNotes ?? '')) {
      setState(() => _editingNotes = false);
      return;
    }
    setState(() => _savingNotes = true);
    final ok = await _patchFields(UpdateTaskFieldsDto(internalNotes: novo));
    if (!mounted) return;
    setState(() {
      _savingNotes = false;
      if (ok) _editingNotes = false;
    });
    if (ok) {
      HapticFeedback.selectionClick();
      _snack('Observação interna salva', ok: true);
    }
  }

  // ─── 6. VÍNCULOS (cliente / imóvel) ──────────────────────────────────────

  /// Sem opção de DESVINCULAR: o backend valida UUID e recusa null nesses
  /// campos, então a UI só oferece o que a API aceita — trocar.
  Future<void> _editClientLink() async {
    final projectId = _pickerProjectId;
    if (projectId == null) {
      _snack('Funil do card não identificado.', erro: true);
      return;
    }
    final task = _taskNow;
    // Contato avulso alimenta o "Cadastrar como cliente" já preenchido.
    KanbanTaskContactInput? avulso;
    for (final c in task.contacts ?? const <KanbanTaskContactInput>[]) {
      if ((c.phone?.trim().isNotEmpty ?? false)) {
        avulso = c;
        break;
      }
    }
    final sugestaoTelefone =
        avulso?.phone?.trim() ?? task.contactPhone?.trim() ?? task.contactWhatsapp?.trim();

    final escolha = await TaskLinkPickerSheet.show(
      context,
      kind: TaskLinkKind.client,
      projectId: projectId,
      currentId: task.clientId,
      suggestedName: avulso?.name?.trim(),
      suggestedPhone: task.client == null ? sugestaoTelefone : null,
    );
    if (escolha == null || !mounted || escolha.id == task.clientId) return;

    setState(() => _savingField = 'client');
    final ok = await _patchTask(
      UpdateTaskDto(clientId: escolha.id, includeTags: false),
      // O cliente antigo está no overlay — cai fora e volta do refetch.
      dropDetailed: true,
    );
    if (!mounted) return;
    setState(() => _savingField = null);
    if (ok) {
      HapticFeedback.selectionClick();
      _snack('Cliente vinculado: ${escolha.label}', ok: true);
    }
  }

  Future<void> _editPropertyLink() async {
    final projectId = _pickerProjectId;
    if (projectId == null) {
      _snack('Funil do card não identificado.', erro: true);
      return;
    }
    final escolha = await TaskLinkPickerSheet.show(
      context,
      kind: TaskLinkKind.property,
      projectId: projectId,
      currentId: _propertyId,
    );
    if (escolha == null || !mounted || escolha.id == _propertyId) return;

    setState(() => _savingField = 'property');
    final ok = await _patchTask(
      UpdateTaskDto(propertyId: escolha.id, includeTags: false),
    );
    if (!mounted) return;
    setState(() {
      _savingField = null;
      if (ok) _linkedPropertyLabel = escolha.label;
    });
    if (ok) {
      HapticFeedback.selectionClick();
      _snack('Imóvel vinculado: ${escolha.label}', ok: true);
    }
  }

  // ─── 7. CONTATOS DO LEAD ─────────────────────────────────────────────────

  Future<void> _manageContacts() async {
    final task = _taskNow;
    final atuais = task.contacts ?? const <KanbanTaskContactInput>[];
    final nova = await TaskContactsSheet.show(context, contacts: atuais);
    if (nova == null || !mounted) return;
    setState(() => _savingField = 'contacts');
    final ok = await _patchTask(
      UpdateTaskDto(contacts: nova, includeTags: false),
      overlay: (t) => t.copyWith(contacts: nova),
    );
    if (!mounted) return;
    setState(() => _savingField = null);
    if (ok) {
      HapticFeedback.selectionClick();
      _snack(
        nova.isEmpty
            ? 'Contatos removidos'
            : 'Contatos salvos (${nova.length})',
        ok: true,
      );
    }
  }

  // ─── 8. EXCLUIR CARD ─────────────────────────────────────────────────────

  Future<void> _openCardActions() async {
    final acao = await TaskCardActionsSheet.show(context, canDelete: _canDelete);
    if (acao == null || !mounted) return;
    if (acao == TaskCardAction.delete) await _confirmDelete();
  }

  Future<void> _confirmDelete() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir card'),
        content: Text(
          'Excluir "${_taskNow.title}" do funil? Comentários, tarefas e '
          'histórico vão junto. Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              foregroundColor: ThemeHelpers.textSecondaryColor(ctx),
            ),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: _kDangerRed),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted || _deleting) return;

    setState(() => _deleting = true);
    final controller = KanbanController.instance;
    // O messenger e o navigator são capturados ANTES: depois do pop este
    // context morre e o SnackBar não teria onde nascer.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // `deleteTask` do controller já recarrega o board no sucesso.
    final ok = await controller.deleteTask(widget.task.id);
    if (!mounted) return;
    setState(() => _deleting = false);
    if (!ok) {
      _snack(controller.error ?? 'Não foi possível excluir o card.',
          erro: true);
      return;
    }
    HapticFeedback.mediumImpact();
    if (navigator.canPop()) navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Card excluído'),
          backgroundColor: _kConfirmGreen,
        ),
      );
  }

  // ─── 9. TAGS ─────────────────────────────────────────────────────────────

  Future<void> _manageTags() async {
    final task = _taskNow;
    final atuais = List<String>.from(task.displayTags ?? const <String>[]);
    final novas = await TaskTagsSheet.show(
      context,
      teamId: KanbanController.instance.teamId,
      selected: atuais,
    );
    if (novas == null || !mounted) return;
    setState(() => _savingField = 'tags');
    // Aqui a lista COMPLETA é a intenção — `includeTags` fica no padrão
    // (true) justamente para conseguir esvaziar as tags do card.
    final ok = await _patchTask(
      UpdateTaskDto(tags: novas),
      overlay: (t) => t.copyWith(tags: novas),
    );
    if (!mounted) return;
    setState(() => _savingField = null);
    if (ok) {
      HapticFeedback.selectionClick();
      _snack(novas.isEmpty ? 'Tags removidas' : 'Tags atualizadas', ok: true);
    }
  }

  /// Coluna (etapa) do board por id — a lista vem do controller singleton,
  /// o mesmo board que a tela de trás está exibindo.
  KanbanColumn? _columnById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final c in KanbanController.instance.columns) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// MOVER O LEAD DE ETAPA sem arrastar no board (paridade com o CRM web).
  ///
  /// A ação passa pelo `KanbanController.moveTask`, que já faz o movimento
  /// otimista + `MoveTaskDto` com `fromColumnId` obrigatório + rollback no
  /// erro. Como o controller notifica os listeners, o board ATRÁS e este
  /// modal (que vive dentro de um `ListenableBuilder` + `_mergedTask`)
  /// re-renderizam sozinhos — sem inventar callback nem resultado de pop.
  Future<void> _openMoveStageSheet(BuildContext context, KanbanTask task) async {
    if (_movingStage) return;
    final controller = KanbanController.instance;
    final columns = controller.columns
        .where((c) => !KanbanSyntheticColumns.isSyntheticId(c.id))
        .toList();
    if (columns.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Etapas do funil ainda não carregadas.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final target = await showModalBottomSheet<KanbanColumn>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (ctx) => _MoveStageSheet(
        columns: columns,
        currentColumnId: task.columnId,
        counts: {
          for (final c in columns) c.id: controller.columnDisplayTotal(c),
        },
      ),
    );
    if (!mounted || target == null) return;
    await _moveToStage(context, task, target);
  }

  /// Executa a mudança de etapa. Serve aos DOIS caminhos: o toque no trilho
  /// do hero (principal) e o sheet de lista (quando o funil é longo).
  ///
  /// Como o toque no trilho é de um dedo só, o sucesso oferece **Desfazer**
  /// por alguns segundos — mover errado é o engano mais provável aqui, e
  /// desfazer é mais gentil que um diálogo de confirmação antes de cada
  /// movimento.
  Future<void> _moveToStage(
    BuildContext context,
    KanbanTask task,
    KanbanColumn target, {
    bool permitirDesfazer = true,
  }) async {
    if (_movingStage || target.id == task.columnId) return;
    final controller = KanbanController.instance;
    final origem = _columnById(task.columnId);

    setState(() => _movingStage = true);
    setState(() => _movingToColumnId = target.id);
    final ok = await controller.moveTask(
      taskId: task.id,
      fromColumnId: task.columnId,
      targetColumnId: target.id,
      targetPosition: 0,
    );
    if (!mounted) return;
    setState(() {
      _movingStage = false;
      _movingToColumnId = null;
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(controller.error ?? 'Erro ao mover o lead'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Lead movido para ${target.title}'),
          backgroundColor: const Color(0xFF059669),
          duration: const Duration(seconds: 4),
          action: (permitirDesfazer && origem != null)
              ? SnackBarAction(
                  label: 'Desfazer',
                  textColor: Colors.white,
                  onPressed: () {
                    final atual = _mergedTask(KanbanController.instance);
                    _moveToStage(
                      context,
                      atual,
                      origem,
                      permitirDesfazer: false,
                    );
                  },
                )
              : null,
        ),
      );
  }

  Future<void> _openTransferSheet(BuildContext context, KanbanTask task) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (ctx) => TransferTaskSheet(task: task),
    );
    if (!mounted) return;
    // O sheet não devolve resultado: fechou, a rota é relida (se não houve
    // transferência, a lista volta igual — custo de uma requisição).
    if (_didLoadTransfers) await _loadTransferHistory();
    if (!mounted) return;
    if (_didLoadJourney) await _loadJourney();
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: KanbanController.instance,
      builder: (context, _) {
        final theme = Theme.of(context);
        final task = _mergedTask(KanbanController.instance);
        final state = _TaskState.from(task);
        final perms = KanbanController.instance.permissions;
        final canMark =
            perms?.canMarkResult ?? perms?.canEditTasks ?? false;
        final canXfer =
            perms?.canTransfer ?? perms?.canEditTasks ?? false;

        // Título da barra = o próprio lead (o chrome já corta com ellipsis).
        final leadTitle = task.title.trim();

        // TELA (não sheet): sem altura calculada, sem padding de viewInsets e
        // sem "modo digitação" — o Scaffold do AppScaffold já encolhe o corpo
        // com o teclado (resizeToAvoidBottomInset) e o hero fica sempre à
        // vista. Voltar é o back da barra.
        return AppScaffold(
          title: leadTitle.isEmpty ? 'Negociação' : leadTitle,
          showBottomNavigation: false,
          showDrawer: false,
          actions: [
            ChromeToolbarIconButton(
              icon: Icons.copy_rounded,
              tooltip: 'Copiar ID',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: task.id));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('ID da tarefa copiado'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
            // Destrutivo mora no chrome, longe do conteúdo — nunca ao lado
            // de uma ação que se usa todo dia.
            if (_canDelete)
              ChromeToolbarIconButton(
                icon: Icons.more_horiz_rounded,
                tooltip: 'Mais ações',
                onPressed: _openCardActions,
              ),
          ],
          // A TELA INTEIRA ROLA. Antes o hero era fixo e só o conteúdo da aba
          // rolava — daí a sensação de "metade da tela travada", com a área
          // útil espremida no rodapé. Aqui o hero e o trilho do funil sobem
          // junto com o dedo e as ABAS ficam presas no topo, que é o padrão
          // que todo app de ficha usa.
          body: NestedScrollView(
            headerSliverBuilder: (context, _) => [
              SliverToBoxAdapter(
                child:
              // Teclado aberto = o hero sai de cena com fade (AnimatedSize +
              // opacidade, saída suave, nunca corte seco).
              //
              // Não é herança do modal: a AppBar já identifica o lead, e a
              // conta de espaço em aparelho baixo (360×640, teclado ~250px)
              // não fecha com hero + abas + composer — faltavam ~20px com
              // título de 2 linhas. Quem está digitando quer ver o que
              // escreve, não o cabeçalho. Sem clamp de altura e sem padding
              // de viewInsets: quem encolhe o corpo é o próprio Scaffold.
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                // Editando o título o hero FICA: é lá que o campo vive, e
                // some-lo com o teclado tiraria da tela justamente o que a
                // pessoa está digitando.
                child: MediaQuery.of(context).viewInsets.bottom > 0 &&
                        !_editingTitle
                    ? const SizedBox(width: double.infinity)
                    : _TaskHeroHeader(
                        task: task,
                        state: state,
                        canMarkResult: canMark,
                        canTransfer: canXfer,
                        onMarkLost: () => _openMarkResultSheet(
                          context,
                          task,
                          quickEntry: 'lost',
                        ),
                        // GANHO direto do hero: fechar a venda é o momento
                        // mais importante do funil e não pode custar mais
                        // toques que perder o lead.
                        onMarkWon: () => _openMarkResultSheet(
                          context,
                          task,
                          quickEntry: 'won',
                        ),
                        onTransfer: () => _openTransferSheet(context, task),
                        onOpenResult: () =>
                            _openMarkResultSheet(context, task),
                        canEditTitle: _canEdit,
                        editingTitle: _editingTitle,
                        savingTitle: _savingTitle,
                        titleController: _titleCtrl,
                        onStartTitleEdit: _startTitleEdit,
                        onCancelTitleEdit: () {
                          FocusScope.of(context).unfocus();
                          setState(() => _editingTitle = false);
                        },
                        onSaveTitle: _saveTitle,
                        // Trilho do funil: etapas reais do board (sem as
                        // colunas sintéticas de filtro).
                        stages: KanbanController.instance.columns
                            .where(
                              (c) => !KanbanSyntheticColumns.isSyntheticId(
                                c.id,
                              ),
                            )
                            .toList(),
                        canMoveStage:
                            perms?.canMoveTasks ?? perms?.canEditTasks ?? false,
                        movingToColumnId: _movingToColumnId,
                        onPickStage: (col) =>
                            _moveToStage(context, task, col),
                        onOpenStageList: () =>
                            _openMoveStageSheet(context, task),
                      ),
              ),
              ),
              // Cada aba com identidade própria (ativa colore ícone +
              // label + indicador; inativas slate).
              SliverPersistentHeader(
                pinned: true,
                delegate: _PinnedTabBarDelegate(
                  child: _MinimalTabBar(
                controller: _tabController,
                tabs: [
                  const _TabItem(
                    icon: Icons.article_outlined,
                    label: 'Detalhes',
                    color: Color(0xFF6366F1), // indigo
                  ),
                  const _TabItem(
                    icon: Icons.signpost_outlined,
                    label: 'Jornada',
                    color: Color(0xFFD97706), // âmbar
                  ),
                  const _TabItem(
                    icon: Icons.checklist_rounded,
                    label: 'Tarefas',
                    color: Color(0xFF14B8A6), // teal
                  ),
                  _TabItem(
                    icon: Icons.forum_outlined,
                    label: 'Conversas',
                    color: const Color(0xFF3B82F6), // azul
                    badge: _comments.length,
                  ),
                  _TabItem(
                    icon: Icons.attach_file_rounded,
                    label: 'Arquivos',
                    color: const Color(0xFF0891B2), // cyan
                    badge: _taskFiles.isNotEmpty ? _taskFiles.length : null,
                  ),
                  _TabItem(
                    icon: Icons.event_outlined,
                    label: 'Agenda',
                    color: _kAgendaTone, // magenta
                    badge:
                        _appointments.isEmpty ? null : _appointments.length,
                  ),
                  const _TabItem(
                    icon: Icons.insights_rounded,
                    label: 'Métricas',
                    color: Color(0xFF10B981), // emerald
                  ),
                  _TabItem(
                    icon: Icons.history_rounded,
                    label: 'Histórico',
                    color: const Color(0xFF64748B), // slate
                    badge: (_history.isNotEmpty || _loadingHistory)
                        ? _history.length
                        : null,
                  ),
                ],
                  ),
                ),
              ),
            ],
            body: TabBarView(
                  controller: _tabController,
                  physics: const ClampingScrollPhysics(),
                  children: [
                    _buildDetailsTab(context, theme, state, task),
                    _buildJourneyTab(context, theme),
                    SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: SubTaskManager(
                        taskId: task.id,
                        parentCardTitle: task.title,
                      ),
                    ),
                    _buildCommentsTab(context, theme),
                    _buildFilesTab(context, theme),
                    _buildAgendaTab(context, theme),
                    _buildMetricsTab(context, theme),
                    _buildHistoryTab(context, theme),
                  ],
                ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // TAB: DETAILS
  // ---------------------------------------------------------------------------

  /// Aba **Detalhes** redesenhada — layout editorial assimétrico.
  ///
  /// Antes era uma sequência de 5 caixas cinzas idênticas empilhadas,
  /// cada uma com SectionHeader iguais e conteúdo listado verticalmente.
  /// Resultado: parecia um formulário, não uma ficha de informação rica.
  ///
  /// Agora a hierarquia visual é distinta por bloco:
  /// 1. **Descrição editorial** — sem caixa, borda accent fina à esquerda,
  ///    fonte maior com leading generoso. É o conteúdo principal e ganha
  ///    destaque tipográfico próprio.
  /// 2. **Bento grid 2×2** — 4 tiles temáticos com cores próprias por
  ///    categoria (prazo cinza/âmbar/vermelho conforme saúde, prioridade
  ///    na cor da própria prioridade, funil roxo, status verde/cinza).
  ///    Substitui o `_InfoStack` linear vertical.
  /// 3. **Equipe** — cards lado a lado quando largura permite.
  /// 4. **Tags** — chips coloridos como antes (já estavam OK).
  /// 5. **Timeline horizontal** — 3 marcadores numa linha temporal
  ///    horizontal (Criada → Atualizada → Prazo) com conector gradient.
  ///    Substitui a lista vertical de datas.
  Widget _buildDetailsTab(
    BuildContext context,
    ThemeData theme,
    _TaskState state,
    KanbanTask task,
  ) {
    final tags = task.displayTags ?? const <String>[];
    final hasTags = tags.isNotEmpty;

    // LEAD SEM CLIENTE VINCULADO — o card do board mostra o telefone mesmo
    // assim (vem de `task.contacts` via `contactPhone`), mas o detalhe só
    // montava a seção quando havia `client`: o número sumia justamente nos
    // leads de campanha/WhatsApp, que são a maioria. Aqui os contatos avulsos
    // alimentam a MESMA seção.
    final looseContacts = task.client == null
        ? (task.contacts ?? const <KanbanTaskContactInput>[])
            .where((c) => c.hasAny)
            .toList()
        : const <KanbanTaskContactInput>[];
    KanbanTaskContactInput? primaryContact;
    for (final c in looseContacts) {
      final p = c.phone?.trim();
      if (p != null && p.isNotEmpty) {
        primaryContact = c;
        break;
      }
    }
    primaryContact ??= looseContacts.isEmpty ? null : looseContacts.first;
    final extraContacts = looseContacts
        .where((c) =>
            !identical(c, primaryContact) &&
            (c.phone?.trim().isNotEmpty ?? false))
        .toList();
    final rawLoosePhone = task.client == null
        ? (task.contactPhone ?? task.contactWhatsapp)?.trim()
        : null;
    final loosePhone =
        (rawLoosePhone != null && rawLoosePhone.isNotEmpty) ? rawLoosePhone : null;
    final primaryPhone = primaryContact?.phone?.trim();
    final leadPhone = (primaryPhone != null && primaryPhone.isNotEmpty)
        ? primaryPhone
        : loosePhone;
    final hasLooseContact = task.client == null &&
        (leadPhone != null ||
            (primaryContact?.name?.trim().isNotEmpty ?? false) ||
            (primaryContact?.email?.trim().isNotEmpty ?? false));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. LEAD / CONTATO — PRIMEIRA seção: é para isso que o corretor
          // abre o card. Número do lead estilizado (paridade com o
          // web) + as duas ações que o corretor mais repete no dia.
          // Sem contagem no cabeçalho: quem conta os contatos é o botão
          // "Contatos (n)" logo abaixo — dois números para a mesma coisa
          // seria ruído.
          const _SectionHeader(
            overline: 'Lead',
            title: 'Contato',
            accent: _kContactTone,
          ),
          const SizedBox(height: 10),
          if (task.client != null)
            _LeadContactCard(client: task.client!)
          else if (hasLooseContact)
            _LeadContactCard(
              contactName: primaryContact?.name,
              contactPhone: leadPhone,
              contactEmail: primaryContact?.email,
              contactJobTitle: primaryContact?.jobTitle,
              extraContacts: extraContacts,
            )
          else
            const _MutedHint(
              icon: Icons.person_off_outlined,
              text: 'Nenhum contato cadastrado neste lead ainda.',
            ),
          const SizedBox(height: 12),
          _ContactActionBar(
            registering: _registeringCall,
            onRegisterCall: _registerCall,
            canEdit: _canEdit,
            savingContacts: _savingField == 'contacts',
            contactsCount: (task.contacts ?? const []).length,
            onManageContacts: _manageContacts,
          ),
          const SizedBox(height: 26),
          // A seção "Briefing" saiu daqui: era o bloco mais alto da aba e
          // empurrava a ficha para baixo sem ser o que o corretor abre o
          // card para ver. A descrição continua no card do board.
          //
          // 2. RAIO-X — ficha técnica flush (valor, resultado, prazo, cadência…)
          //
          // A etapa NÃO mora mais aqui: virou o trilho do funil no hero, onde
          // ela é desenho (percurso do lead) e não "mais uma linha de opção"
          // no meio da ficha. O sheet de lista continua vivo como atalho para
          // funis longos — chamado pelo toque no nome da etapa no trilho.
          _TaskDossier(
            task: task,
            state: state,
            canEdit: _canEdit,
            savingField: _savingField,
            onEditValue: _editValue,
            onEditDeadline: _editDeadline,
            onEditPriority: _editPriority,
          ),
          const SizedBox(height: 26),

          // 3. VÍNCULOS — cliente e imóvel da negociação. Trocar sim,
          // desvincular não: o backend valida UUID e recusa null, então a UI
          // não oferece o que a API não aceita.
          _SectionHeader(
            overline: 'Vínculos',
            title: 'Cliente e imóvel',
            accent: _kLinksTone,
          ),
          const SizedBox(height: 10),
          _LinkRow(
            icon: Icons.badge_outlined,
            label: 'Cliente',
            value: task.client?.name.trim(),
            canEdit: _canEdit,
            saving: _savingField == 'client',
            onTap: _editClientLink,
          ),
          _LinkRow(
            icon: Icons.home_work_outlined,
            label: 'Imóvel',
            value: _propertyLabel,
            canEdit: _canEdit,
            saving: _savingField == 'property',
            onTap: _editPropertyLink,
            isLast: true,
          ),
          const SizedBox(height: 26),


          // 4. INTERNO — o que o time anota e o cliente nunca vê.
          _InternalNotesSection(
            notes: _internalNotes,
            canEdit: _canEdit,
            editing: _editingNotes,
            saving: _savingNotes,
            controller: _notesCtrl,
            onStartEdit: _startNotesEdit,
            onCancel: () {
              FocusScope.of(context).unfocus();
              setState(() => _editingNotes = false);
            },
            onSave: _saveNotes,
          ),
          const SizedBox(height: 26),

          // 5. EQUIPE — autoria do card (quem criou, quem responde).
          _SectionHeader(
            overline: 'Equipe',
            title: 'Responsável e autoria',
            accent: _kPeopleTone,
          ),
          const SizedBox(height: 10),
          _PeopleStrip(
            task: task,
            canEditAssignee: _canEdit,
            savingAssignee: _savingField == 'assignedTo',
            onEditAssignee: _editAssignee,
          ),

          // 3b. ENVOLVIDOS — a rede em volta do card. Fala em teal para não
          // se confundir com a autoria (violeta) logo acima.
          if (_involvedUsers.isNotEmpty || _canEdit) ...[
            const SizedBox(height: 26),
            _SectionHeader(
              overline: 'Envolvidos',
              title: 'Quem mais acompanha',
              trailing: _involvedUsers.isEmpty
                  ? null
                  : '${_involvedUsers.length}',
              accent: _kInvolvedTone,
            ),
            const SizedBox(height: 10),
            _InvolvedPeopleStrip(
              people: _involvedUsers,
              canEdit: _canEdit,
              saving: _savingField == 'involvedUsers',
              onManage: _manageInvolvedUsers,
              onRemove: _removeInvolvedUser,
            ),
          ],

          // 4. TAGS — visíveis para todo mundo, editáveis só para gestão.
          if (hasTags || _canManageTags) ...[
            const SizedBox(height: 26),
            _SectionHeader(
              overline: 'Categorias',
              title: 'Tags',
              trailing: hasTags ? '${tags.length}' : null,
              accent: _kTagsTone,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final t in tags) _PillTag(label: t),
                if (_canManageTags)
                  _ManageTagsChip(
                    hasTags: hasTags,
                    saving: _savingField == 'tags',
                    onTap: _manageTags,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 26),

          // 5. TIMELINE HORIZONTAL
          _SectionHeader(
            overline: 'Auditoria',
            title: 'Linha do tempo',
            accent: _kAuditTone,
          ),
          const SizedBox(height: 14),
          _HorizontalTimeline(task: task, state: state),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB: COMMENTS
  // ---------------------------------------------------------------------------

  Widget _buildCommentsTab(BuildContext context, ThemeData theme) {
    // Conversa fala em azul (bolhas, composer, anexos) — não na cor da marca.
    const accent = _kChatTone;
    // Anatomia de conversa: lista em Expanded, composer fixo no rodapé. Como
    // isto virou TELA, o Scaffold encolhe o corpo com o teclado — não existe
    // mais o failsafe de capar/rolar o composer que o sheet exigia.
    return Column(
      children: [
        Expanded(
          child: _loadingComments
              ? const _LoadingView()
              : _commentsError != null
                  ? _ErrorView(
                      message: _commentsError,
                      statusCode: _commentsErrorStatus,
                      onRetry: _loadComments,
                    )
                  : _comments.isEmpty
                      ? const _EmptyState(
                          icon: Icons.forum_outlined,
                          title: 'Sem conversas por aqui',
                          subtitle:
                              'Seja o primeiro a comentar e deixar contexto para o time.',
                        )
                      : Builder(
                          builder: (context) {
                            final thread = _threadedComments();
                            return ListView.separated(
                              padding:
                                  const EdgeInsets.fromLTRB(18, 14, 18, 14),
                              physics: const BouncingScrollPhysics(),
                              itemCount: thread.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 4),
                              itemBuilder: (context, i) {
                                final node = thread[i];
                                final c = node.comment;
                                return _CommentBubble(
                                  comment: c,
                                  isMe: c.userId == _currentUserId,
                                  canDelete: _canDeleteComment(c),
                                  onDelete: () => _deleteComment(c.id),
                                  isReply: node.isReply,
                                  replyToName: node.parentAuthor,
                                  mentionNames: _memberNames,
                                  onReply: () => _startReply(c),
                                );
                              },
                            );
                          },
                        ),
        ),
        _CommentComposer(
          controller: _commentController,
          focusNode: _commentFocus,
          onSubmit: _submittingComment ? null : _submitComment,
          isSubmitting: _submittingComment,
          length: _commentLength,
          maxLength: 2000,
          files: _selectedFiles,
          onPickFiles: _selectFiles,
          onRemoveFile: _removeFile,
          accent: accent,
          mentionSuggestions: _mentionSuggestions,
          loadingMentions: _loadingMembers && _mentionAnchor != null,
          onPickMention: _applyMention,
          replyTo: _replyTo,
          onCancelReply: () => setState(() => _replyTo = null),
        ),
      ],
    );
  }

  /// Nomes dos membros — o realce da menção casa `@Nome Sobrenome` inteiro
  /// (nome composto sem isso viraria "@Ana" + " Paula" solto).
  List<String> get _memberNames =>
      _members.map((u) => u.name).where((n) => n.trim().isNotEmpty).toList();

  void _startReply(KanbanTaskComment comment) {
    setState(() => _replyTo = comment);
    _commentFocus.requestFocus();
  }

  /// Achata a lista plana do backend em raízes + respostas (um nível, como o
  /// web). Resposta órfã — pai excluído — volta a ser raiz para não sumir.
  List<_CommentNode> _threadedComments() {
    final byId = {for (final c in _comments) c.id: c};
    final children = <String, List<KanbanTaskComment>>{};
    final roots = <KanbanTaskComment>[];
    for (final c in _comments) {
      final parent = c.parentCommentId;
      if (parent != null && parent.isNotEmpty && byId.containsKey(parent)) {
        children.putIfAbsent(parent, () => []).add(c);
      } else {
        roots.add(c);
      }
    }
    int byDate(KanbanTaskComment a, KanbanTaskComment b) =>
        a.createdAt.compareTo(b.createdAt);
    roots.sort(byDate);
    final out = <_CommentNode>[];
    for (final root in roots) {
      out.add(_CommentNode(comment: root));
      final kids = children[root.id];
      if (kids == null) continue;
      kids.sort(byDate);
      for (final kid in kids) {
        out.add(
          _CommentNode(
            comment: kid,
            isReply: true,
            parentAuthor: root.user?.name,
          ),
        );
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // TAB: HISTORY
  // ---------------------------------------------------------------------------

  Widget _buildHistoryTab(BuildContext context, ThemeData theme) {
    if (_loadingHistory) return const _LoadingView();
    if (_historyError != null) {
      return _ErrorView(message: _historyError, statusCode: _historyErrorStatus, onRetry: _loadHistory);
    }
    if (_history.isEmpty) {
      return const _EmptyState(
        icon: Icons.history_toggle_off_rounded,
        title: 'Sem histórico ainda',
        subtitle:
            'As ações nesta tarefa (criação, edições, movimentações) aparecem aqui.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      physics: const BouncingScrollPhysics(),
      itemCount: _history.length,
      itemBuilder: (context, i) {
        return _HistoryRow(
          entry: _history[i],
          isLast: i == _history.length - 1,
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // TAB: JORNADA (GET /kanban/tasks/:id/journey)
  // ---------------------------------------------------------------------------

  List<Map<String, dynamic>> _journey = [];
  bool _loadingJourney = false;
  String? _journeyError;
  int _journeyErrorStatus = 0;
  bool _didLoadJourney = false;

  Future<void> _loadJourney() async {
    setState(() {
      _loadingJourney = true;
      _journeyError = null;
    });
    final r = await _kanbanService.getTaskJourney(widget.task.id);
    if (!mounted) return;
    if (r.success && r.data != null) {
      setState(() {
        _journey = r.data!;
        _loadingJourney = false;
        _didLoadJourney = true;
      });
    } else {
      setState(() {
        _journeyError = r.message;
        _journeyErrorStatus = r.statusCode;
        _loadingJourney = false;
        _didLoadJourney = true;
      });
    }
  }

  Widget _buildJourneyTab(BuildContext context, ThemeData theme) {
    if (_loadingJourney) return const _LoadingView();
    if (_journeyError != null) {
      return _ErrorView(message: _journeyError, statusCode: _journeyErrorStatus, onRetry: _loadJourney);
    }

    final temTransfer = _transfers.isNotEmpty;
    final podeTransferir =
        _perms?.canTransfer ?? _perms?.canEditTasks ?? false;
    final vazio = _journey.isEmpty && !temTransfer && !podeTransferir;
    if (vazio) {
      return const _EmptyState(
        icon: Icons.signpost_outlined,
        title: 'Sem eventos de jornada',
        subtitle:
            'Eventos de atribuição, colunas, transferências e resultado aparecem aqui.',
      );
    }

    return RefreshIndicator(
      color: _kRouteTone,
      onRefresh: () async {
        await Future.wait([_loadJourney(), _loadTransferHistory()]);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        children: [
          // ROTAS — mudar de funil é o movimento mais largo que o card faz,
          // então abre a aba antes do miúdo da jornada.
          if (temTransfer || podeTransferir || _loadingTransfers) ...[
            _SectionHeader(
              overline: 'Rotas',
              title: 'Transferências de funil',
              trailing: temTransfer ? '${_transfers.length}' : null,
              accent: _kRouteTone,
            ),
            const SizedBox(height: 12),
            if (podeTransferir) ...[
              _TransferActionBar(
                onTap: () => _openTransferSheet(context, _taskNow),
              ),
              const SizedBox(height: 14),
            ],
            if (_loadingTransfers)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: _kRouteTone,
                    ),
                  ),
                ),
              )
            else if (_transfersError != null)
              _MutedHint(
                icon: Icons.cloud_off_rounded,
                text: _transfersError!,
              )
            else if (!temTransfer)
              const _MutedHint(
                icon: Icons.alt_route_rounded,
                text: 'Este card nunca mudou de funil.',
              )
            else
              for (var i = 0; i < _transfers.length; i++)
                _TransferRow(
                  entry: _transfers[i],
                  isLast: i == _transfers.length - 1,
                ),
            const SizedBox(height: 26),
          ],
          _SectionHeader(
            overline: 'Jornada',
            title: 'Linha de eventos',
            trailing: _journey.isEmpty ? null : '${_journey.length}',
            accent: const Color(0xFFD97706),
          ),
          const SizedBox(height: 14),
          if (_journey.isEmpty)
            const _MutedHint(
              icon: Icons.signpost_outlined,
              text: 'Nenhum evento registrado nesta negociação ainda.',
            )
          else
            for (var i = 0; i < _journey.length; i++)
              _journeyRow(context, theme, i),
        ],
      ),
    );
  }

  /// Um evento da jornada (dot + fio + texto). Extraído do `itemBuilder` para
  /// a aba poder empilhar seções acima dele sem duplicar o desenho.
  Widget _journeyRow(BuildContext context, ThemeData theme, int i) {
        final e = _journey[i];
        final title = e['title']?.toString() ?? '';
        final subtitle = e['subtitle']?.toString();
        final at = e['at']?.toString() ?? '';
        final tone = e['tone']?.toString();
        // Sem tone do backend → slate neutro (o primary vermelho pintava a
        // trilha inteira de vermelho quando o tone não vinha).
        Color dot = _kAuditTone;
        if (tone != null && tone.startsWith('#') && tone.length >= 7) {
          try {
            dot = Color(int.parse(tone.replaceFirst('#', '0xFF')));
          } catch (_) {}
        }
        String timeStr = at;
        try {
          timeStr = DateFormat('dd/MM/yy HH:mm')
              .format(DateTime.parse(at).toLocal());
        } catch (_) {}
        final isLast = i == _journey.length - 1;
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: dot.withValues(alpha: 0.35),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  if (!isLast)
                    Container(
                      width: 2,
                      height: 48,
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: ThemeHelpers.borderColor(context)
                            .withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        timeStr,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (subtitle != null && subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
  }

  // ---------------------------------------------------------------------------
  // TAB: ARQUIVOS (GET /kanban/tasks/:id/attachments)
  // ---------------------------------------------------------------------------

  /// Anexos do card já parseados (a `key` do S3 é o que o DELETE exige).
  List<Attachment> _taskFiles = [];
  bool _loadingFiles = false;
  String? _filesError;
  int _filesErrorStatus = 0;
  bool _didLoadFiles = false;
  bool _uploadingFiles = false;

  /// Chave do anexo sendo removido — o spinner nasce na própria linha.
  String? _deletingAttachmentKey;

  Future<void> _loadTaskFiles() async {
    setState(() {
      _loadingFiles = true;
      _filesError = null;
    });
    final r = await _kanbanService.getTaskAttachmentList(widget.task.id);
    if (!mounted) return;
    if (r.success && r.data != null) {
      setState(() {
        _taskFiles = r.data!;
        _loadingFiles = false;
        _didLoadFiles = true;
      });
    } else {
      setState(() {
        _filesError = r.message;
        _filesErrorStatus = r.statusCode;
        _loadingFiles = false;
        _didLoadFiles = true;
      });
    }
  }

  /// Escolhe e sobe anexos direto no card (multipart `files`).
  ///
  /// As duas travas do backend são conferidas ANTES de gastar rede: no máximo
  /// [KanbanService.maxTaskAttachments] arquivos no card e 200 MB por arquivo
  /// — e a mensagem diz qual arquivo estourou, não um 413 genérico.
  Future<void> _uploadTaskFiles() async {
    if (_uploadingFiles) return;
    List<File> escolhidos;
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );
      if (result == null || result.files.isEmpty) return;
      escolhidos = result.files
          .where((f) => f.path != null)
          .map((f) => File(f.path!))
          .toList();
    } catch (e) {
      _snack('Erro ao selecionar arquivos: $e', erro: true);
      return;
    }
    if (escolhidos.isEmpty) return;

    final restante = KanbanService.maxTaskAttachments - _taskFiles.length;
    if (restante <= 0) {
      _snack(
        'O card já tem o máximo de ${KanbanService.maxTaskAttachments} anexos. '
        'Remova um antes de enviar outro.',
        erro: true,
      );
      return;
    }
    if (escolhidos.length > restante) {
      _snack(
        'Cabem só mais $restante ${restante == 1 ? 'arquivo' : 'arquivos'} '
        'neste card (limite de ${KanbanService.maxTaskAttachments}).',
        erro: true,
      );
      return;
    }
    for (final f in escolhidos) {
      final bytes = await f.length();
      if (bytes > KanbanService.maxTaskAttachmentBytes) {
        final nome = f.path.split(RegExp(r'[\\/]')).last;
        if (!mounted) return;
        _snack('"$nome" passa do limite de 200 MB por arquivo.', erro: true);
        return;
      }
    }

    setState(() => _uploadingFiles = true);
    final r = await _kanbanService.uploadTaskAttachments(
      widget.task.id,
      escolhidos,
    );
    if (!mounted) return;
    setState(() => _uploadingFiles = false);
    if (r.success) {
      _snack(
        escolhidos.length == 1
            ? 'Arquivo anexado ao card'
            : '${escolhidos.length} arquivos anexados ao card',
        ok: true,
      );
      await _loadTaskFiles();
    } else {
      _snack(r.message ?? 'Erro ao enviar anexos', erro: true);
    }
  }

  Future<void> _deleteTaskFile(Attachment file) async {
    final chave = file.key;
    if (chave == null || chave.isEmpty) {
      _snack('Este anexo não tem chave de armazenamento — não dá para remover.',
          erro: true);
      return;
    }
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover anexo'),
        content: Text('"${file.filename}" sai do card para todo o time.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            // Cancelar não é destrutivo: o tema global pinta TextButton de
            // vermelho, então a cor é forçada de volta ao texto secundário.
            style: TextButton.styleFrom(
              foregroundColor: ThemeHelpers.textSecondaryColor(ctx),
            ),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: _kDangerRed),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;
    setState(() => _deletingAttachmentKey = chave);
    final r = await _kanbanService.deleteTaskAttachment(widget.task.id, chave);
    if (!mounted) return;
    setState(() => _deletingAttachmentKey = null);
    if (r.success) {
      _snack('Anexo removido', ok: true);
      await _loadTaskFiles();
    } else {
      _snack(r.message ?? 'Erro ao remover anexo', erro: true);
    }
  }

  Future<void> _openAttachment(Attachment file) async {
    if (file.url.isEmpty) {
      _snack('Este anexo não tem link para abrir.', erro: true);
      return;
    }
    try {
      final uri = Uri.parse(file.url);
      final abriu = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!abriu && mounted) {
        _snack('Não foi possível abrir o arquivo.', erro: true);
      }
    } catch (_) {
      if (!mounted) return;
      _snack('Link do arquivo inválido.', erro: true);
    }
  }

  Widget _buildFilesTab(BuildContext context, ThemeData theme) {
    const accent = _kFilesTone;
    if (_loadingFiles) return const _LoadingView();
    if (_filesError != null) {
      return _ErrorView(message: _filesError, statusCode: _filesErrorStatus, onRetry: _loadTaskFiles);
    }

    final total = _taskFiles.length;
    final cheio = total >= KanbanService.maxTaskAttachments;

    return RefreshIndicator(
      color: accent,
      onRefresh: _loadTaskFiles,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        children: [
          _SectionHeader(
            overline: 'Documentos',
            title: 'Anexos do card',
            trailing: '$total/${KanbanService.maxTaskAttachments}',
            accent: accent,
          ),
          const SizedBox(height: 12),
          if (_canEdit)
            _AttachmentUploadBar(
              accent: accent,
              uploading: _uploadingFiles,
              full: cheio,
              onPick: _uploadTaskFiles,
            ),
          if (_canEdit) const SizedBox(height: 16),
          if (total == 0)
            _MutedHint(
              icon: Icons.folder_open_rounded,
              text: _canEdit
                  ? 'Sem anexos no card. Contratos, plantas e propostas '
                      'enviados aqui ficam fora da conversa e todo o time vê.'
                  : 'Sem anexos no card. Arquivos enviados diretamente na '
                      'tarefa (fora dos comentários) aparecem aqui.',
            )
          else
            for (var i = 0; i < total; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  color:
                      ThemeHelpers.borderColor(context).withValues(alpha: 0.35),
                ),
              _TaskAttachmentTile(
                file: _taskFiles[i],
                accent: accent,
                canDelete: _canEdit,
                deleting: _deletingAttachmentKey != null &&
                    _deletingAttachmentKey == _taskFiles[i].key,
                onOpen: () => _openAttachment(_taskFiles[i]),
                onCopy: () {
                  Clipboard.setData(ClipboardData(text: _taskFiles[i].url));
                  _snack('Link copiado');
                },
                onDelete: () => _deleteTaskFile(_taskFiles[i]),
              ),
            ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB: AGENDA (GET /appointments?kanbanTaskId= · POST /appointments)
  // ---------------------------------------------------------------------------
  //
  // Sem serviço paralelo: quem fala com a API é o `AppointmentService` da
  // feature de agenda — o card só empurra o `kanbanTaskId` no filtro e no
  // corpo da criação, que é exatamente o que o web faz.

  List<Appointment> _appointments = const [];
  bool _loadingAppointments = false;
  String? _appointmentsError;
  int _appointmentsErrorStatus = 0;
  bool _didLoadAppointments = false;
  bool _creatingAppointment = false;

  Future<void> _loadAppointments() async {
    setState(() {
      _loadingAppointments = true;
      _appointmentsError = null;
    });
    final r = await AppointmentService.instance.listAppointments(
      kanbanTaskId: widget.task.id,
      limit: 50,
      // Compromisso do card é do CARD, não "meu": admin/gestor vê o que o
      // time todo marcou nesta negociação. O backend IGNORA a flag para
      // colaborador (sem 403) e ele segue vendo só os próprios — é a mesma
      // regra de escopo da tela de Agenda, não uma exceção do card.
      viewAllCompany: true,
    );
    if (!mounted) return;
    if (r.success && r.data != null) {
      final lista = [...r.data!.appointments]
        ..sort((a, b) => a.startDate.compareTo(b.startDate));
      setState(() {
        _appointments = lista;
        _loadingAppointments = false;
        _didLoadAppointments = true;
      });
    } else {
      setState(() {
        _appointmentsError = r.message;
        _appointmentsErrorStatus = r.statusCode;
        _loadingAppointments = false;
        _didLoadAppointments = true;
      });
    }
  }

  Future<void> _createAppointmentFromCard() async {
    if (_creatingAppointment) return;
    await _ensureMembers();
    if (!mounted) return;
    final draft = await TaskAppointmentSheet.show(
      context,
      suggestedTitle: _taskNow.title,
      members: _members.isEmpty ? null : _members,
      currentUserId: _currentUserId,
    );
    if (draft == null || !mounted) return;

    setState(() => _creatingAppointment = true);
    final task = _taskNow;
    final r = await AppointmentService.instance.createAppointment(
      CreateAppointmentData(
        title: draft.title,
        // Visita é o compromisso natural de um card de funil imobiliário —
        // e é o default do próprio enum.
        type: AppointmentType.visit,
        startDate: draft.start,
        endDate: draft.end,
        kanbanTaskId: task.id,
        clientId: task.clientId,
        inviteUserIds:
            draft.inviteUserIds.isEmpty ? null : draft.inviteUserIds,
      ),
    );
    if (!mounted) return;
    setState(() => _creatingAppointment = false);
    if (r.success) {
      _snack('Compromisso agendado', ok: true);
      await _loadAppointments();
    } else {
      _snack(r.message ?? 'Erro ao agendar compromisso', erro: true);
    }
  }

  Widget _buildAgendaTab(BuildContext context, ThemeData theme) {
    const accent = _kAgendaTone;
    if (_loadingAppointments) return const _LoadingView();
    if (_appointmentsError != null) {
      return _ErrorView(
        message: _appointmentsError,
        statusCode: _appointmentsErrorStatus,
        onRetry: _loadAppointments,
      );
    }

    final agora = DateTime.now();
    final futuros =
        _appointments.where((a) => !a.startDate.isBefore(agora)).toList();
    final passados =
        _appointments.where((a) => a.startDate.isBefore(agora)).toList()
          ..sort((a, b) => b.startDate.compareTo(a.startDate));

    return RefreshIndicator(
      color: accent,
      onRefresh: _loadAppointments,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        children: [
          _SectionHeader(
            overline: 'Agenda',
            title: 'Compromissos deste card',
            trailing: _appointments.isEmpty ? null : '${_appointments.length}',
            accent: accent,
          ),
          const SizedBox(height: 12),
          if (_canEdit)
            _AgendaCreateBar(
              accent: accent,
              busy: _creatingAppointment,
              onTap: _createAppointmentFromCard,
            ),
          if (_canEdit) const SizedBox(height: 16),
          if (_appointments.isEmpty)
            const _MutedHint(
              icon: Icons.event_available_outlined,
              text: 'Nada marcado ainda. Visitas e reuniões criadas aqui '
                  'entram na agenda do time já ligadas a esta negociação.',
            )
          else ...[
            if (futuros.isNotEmpty) ...[
              _AgendaGroupLabel(label: 'A seguir', accent: accent),
              for (var i = 0; i < futuros.length; i++) ...[
                if (i > 0) _agendaDivider(context),
                _AppointmentTile(
                  appointment: futuros[i],
                  accent: accent,
                  past: false,
                ),
              ],
            ],
            if (passados.isNotEmpty) ...[
              const SizedBox(height: 20),
              _AgendaGroupLabel(label: 'Já aconteceu', accent: _kAuditTone),
              for (var i = 0; i < passados.length; i++) ...[
                if (i > 0) _agendaDivider(context),
                _AppointmentTile(
                  appointment: passados[i],
                  accent: _kAuditTone,
                  past: true,
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }

  Widget _agendaDivider(BuildContext context) => Divider(
        height: 1,
        thickness: 1,
        color: ThemeHelpers.borderColor(context).withValues(alpha: 0.35),
      );

  // ---------------------------------------------------------------------------
  // TRANSFERÊNCIAS (GET /kanban/tasks/:id/transfer-history)
  // ---------------------------------------------------------------------------

  List<KanbanTransferHistoryEntry> _transfers = const [];
  bool _loadingTransfers = false;
  String? _transfersError;
  bool _didLoadTransfers = false;

  Future<void> _loadTransferHistory() async {
    setState(() {
      _loadingTransfers = true;
      _transfersError = null;
    });
    final r = await _kanbanService.getTaskTransferHistory(widget.task.id);
    if (!mounted) return;
    if (r.success && r.data != null) {
      final lista = [...r.data!]..sort((a, b) {
          final da = a.transferredAt;
          final db = b.transferredAt;
          if (da == null || db == null) return 0;
          return db.compareTo(da);
        });
      setState(() {
        _transfers = lista;
        _loadingTransfers = false;
        _didLoadTransfers = true;
      });
    } else {
      setState(() {
        // 403 = sem `kanban:view_history`. A seção some em silêncio em vez de
        // gritar um erro que a pessoa não pode resolver.
        _transfersError =
            r.statusCode == 403 ? null : (r.message ?? 'Erro ao carregar');
        _transfers = const [];
        _loadingTransfers = false;
        _didLoadTransfers = true;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // TAB: MÉTRICAS (GET /kanban/analytics/tasks/:id/metrics)
  // ---------------------------------------------------------------------------

  Map<String, dynamic>? _taskMetrics;
  bool _loadingMetrics = false;
  String? _metricsError;
  int _metricsErrorStatus = 0;
  bool _didLoadMetrics = false;

  bool get _canViewTaskAnalytics =>
      ModuleAccessService.instance.hasPermission('kanban:view_analytics');

  Future<void> _loadTaskMetrics() async {
    setState(() {
      _loadingMetrics = true;
      _metricsError = null;
    });
    final r =
        await KanbanAnalyticsService.instance.getTaskMetrics(widget.task.id);
    if (!mounted) return;
    if (r.success && r.data != null) {
      setState(() {
        _taskMetrics = r.data;
        _loadingMetrics = false;
        _didLoadMetrics = true;
      });
    } else {
      setState(() {
        _metricsError = r.message;
        _metricsErrorStatus = r.statusCode;
        _loadingMetrics = false;
        _didLoadMetrics = true;
      });
    }
  }

  Widget _buildMetricsTab(BuildContext context, ThemeData theme) {
    if (!_canViewTaskAnalytics) {
      return const _EmptyState(
        icon: Icons.insights_outlined,
        title: 'Métricas analíticas',
        subtitle:
            'É necessária a permissão kanban:view_analytics (e módulo Kanban) para ver esta aba.',
      );
    }
    if (_loadingMetrics) return const _LoadingView();
    if (_metricsError != null) {
      return _ErrorView(message: _metricsError, statusCode: _metricsErrorStatus, onRetry: _loadTaskMetrics);
    }
    final m = _taskMetrics;
    if (m == null || m.isEmpty) {
      return const _EmptyState(
        icon: Icons.analytics_outlined,
        title: 'Sem dados',
        subtitle: 'Não foi possível interpretar a resposta de métricas.',
      );
    }
    String? s(dynamic v) => v?.toString();
    Widget row(String label, String? value) {
      if (value == null || value.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final nf = NumberFormat.decimalPattern('pt_BR');
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Título na identidade da aba (emerald) — nada de vermelho default.
          const _SectionHeader(
            overline: 'Métricas',
            title: 'Resumo analítico',
            accent: Color(0xFF10B981),
          ),
          const SizedBox(height: 12),
          row('Subtarefas',
              '${s(m['completedSubtasks']) ?? '0'} / ${s(m['totalSubtasks']) ?? '0'} concluídas'),
          row('Taxa subtarefas %', s(m['subtaskCompletionRate'])),
          row('Tempo na coluna atual (h)', s(m['timeInCurrentColumn'])),
          row('Tempo total no board (h)', s(m['totalTimeInBoard'])),
          row('Coluna', s(m['columnName'])),
          row('Funil', s(m['projectName'])),
          row('Cliente', s(m['clientName'])),
          row('Imóvel', s(m['propertyTitle'])),
          row('Valor', m['totalValue'] != null ? nf.format(m['totalValue']) : null),
          row('Origem', s(m['source'])),
          row('Campanha', s(m['campaign'])),
          row('Qualificação', s(m['qualification'])),
          row('Resultado', s(m['result'])),
        ],
      ),
    );
  }
}

// =============================================================================
// SHARED STATE (overdue / due-today / completed / active)
// =============================================================================

enum _TaskHealth { ok, dueToday, overdue, completed }

class _TaskState {
  final _TaskHealth health;
  final Color accent;
  final String stateLabel;
  final IconData stateIcon;
  final DateTime? dueDate;
  final int? daysFromToday;

  const _TaskState({
    required this.health,
    required this.accent,
    required this.stateLabel,
    required this.stateIcon,
    required this.dueDate,
    required this.daysFromToday,
  });

  static _TaskState from(KanbanTask task) {
    if (task.isCompleted) {
      return const _TaskState(
        health: _TaskHealth.completed,
        accent: Color(0xFF10B981),
        stateLabel: 'Concluída',
        stateIcon: Icons.check_circle_rounded,
        dueDate: null,
        daysFromToday: null,
      );
    }
    final due = task.dueDate;
    if (due != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final localDue = due.toLocal();
      final dueDay = DateTime(localDue.year, localDue.month, localDue.day);
      final diffDays = dueDay.difference(today).inDays;
      if (diffDays < 0) {
        return _TaskState(
          health: _TaskHealth.overdue,
          accent: const Color(0xFFEF4444),
          stateLabel: 'Atrasada',
          stateIcon: Icons.error_rounded,
          dueDate: due,
          daysFromToday: diffDays,
        );
      }
      if (diffDays == 0) {
        return _TaskState(
          health: _TaskHealth.dueToday,
          accent: const Color(0xFFF59E0B),
          stateLabel: 'Vence hoje',
          stateIcon: Icons.warning_amber_rounded,
          dueDate: due,
          daysFromToday: 0,
        );
      }
    }
    return _TaskState(
      health: _TaskHealth.ok,
      accent: task.priority != null
          ? Color(int.parse(task.priority!.color.replaceFirst('#', '0xFF')))
          : const Color(0xFF0891B2),
      stateLabel: 'Em andamento',
      stateIcon: Icons.bolt_rounded,
      dueDate: due,
      daysFromToday: due?.toLocal().difference(DateTime.now()).inDays,
    );
  }
}

/// Tira finíssima no topo do header indicando o estado da tarefa. Substitui
/// o gradiente colorido do header anterior — visualmente mais leve no claro.
// =============================================================================
// TRILHO DO FUNIL — percurso do lead (e a troca de etapa como consequência)
// =============================================================================

/// Percurso do funil em UMA linha, com o NOME da etapa por extenso.
///
/// A fita anterior era uma régua de bolinhas numeradas com rolagem
/// horizontal: número solto não diz nada ao corretor, que pediu justamente
/// ver o NOME da coluna. Aqui o nome ocupa o centro, a posição vira texto
/// ("etapa 4 de 9") e o progresso vira uma barra segmentada — que aguenta
/// funil curto ou longo sem quebrar linha e SEM rolagem horizontal, porque
/// os segmentos apenas afinam conforme a quantidade de colunas.
///
/// As setas avançam/voltam UMA etapa (o caso comum, num único toque);
/// tocar no nome abre a lista completa para saltar para qualquer etapa —
/// que é como o funil longo continua alcançável sem varrer a tela.
class _FunnelStageBar extends StatelessWidget {
  final List<KanbanColumn> stages;
  final String currentColumnId;
  final bool canMove;
  final String? movingToColumnId;
  final void Function(KanbanColumn column) onPick;

  /// Toque no nome — abre a lista completa (funil longo).
  final VoidCallback onOpenList;

  const _FunnelStageBar({
    required this.stages,
    required this.currentColumnId,
    required this.canMove,
    required this.movingToColumnId,
    required this.onPick,
    required this.onOpenList,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);

    final idx = stages.indexWhere((c) => c.id == currentColumnId);
    final atual = idx >= 0 ? stages[idx] : null;
    final tone = _columnTone(atual?.color);

    final movendo = movingToColumnId != null;
    final podeVoltar = canMove && idx > 0 && !movendo;
    final podeAvancar =
        canMove && idx >= 0 && idx < stages.length - 1 && !movendo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Posição em texto: substitui a contagem que o usuário tinha de
        // inferir contando bolinhas.
        Row(
          children: [
            Container(
              width: 3.5,
              height: 11,
              decoration: BoxDecoration(
                color: tone,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                idx >= 0
                    ? 'ETAPA ${idx + 1} DE ${stages.length}'
                    : 'ETAPA NÃO IDENTIFICADA',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: secondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            _StageArrow(
              icon: LucideIcons.chevronLeft,
              tooltip: 'Etapa anterior',
              enabled: podeVoltar,
              tone: tone,
              onTap: podeVoltar ? () => onPick(stages[idx - 1]) : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StageNamePill(
                label: atual?.title ?? 'Selecionar etapa',
                tone: tone,
                ink: _inkOnTone(tone),
                isDark: isDark,
                busy: movendo,
                // Sem permissão de mover o nome continua legível (é
                // informação), apenas não abre a lista.
                onTap: canMove && !movendo ? onOpenList : null,
              ),
            ),
            const SizedBox(width: 8),
            _StageArrow(
              icon: LucideIcons.chevronRight,
              tooltip: 'Próxima etapa',
              enabled: podeAvancar,
              tone: tone,
              onTap: podeAvancar ? () => onPick(stages[idx + 1]) : null,
            ),
          ],
        ),
        const SizedBox(height: 11),
        _StageTrack(total: stages.length, currentIndex: idx, tone: tone),
      ],
    );
  }
}

/// Seta de uma etapa. Fica apagada (não some) quando não há para onde ir —
/// sumir botão faz o layout pular a cada movimentação.
class _StageArrow extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final Color tone;
  final VoidCallback? onTap;

  const _StageArrow({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.tone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borda = ThemeHelpers.borderColor(context);
    final cor = enabled
        ? tone
        : ThemeHelpers.textSecondaryColor(context).withValues(alpha: 0.35);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: enabled
            ? tone.withValues(alpha: isDark ? 0.14 : 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: enabled
                    ? tone.withValues(alpha: 0.35)
                    : borda.withValues(alpha: 0.5),
              ),
            ),
            child: Icon(icon, size: 17, color: cor),
          ),
        ),
      ),
    );
  }
}

/// Tinta LEGÍVEL sobre um fundo sólido [tone].
///
/// Não use `_columnInk` aqui: aquele devolve a própria cor da coluna (ou um
/// escurecimento leve dela), pensado para texto sobre fundo NEUTRO. Sobre a
/// cor cheia dava cor-sobre-a-mesma-cor — o nome da etapa sumia e a pill
/// virava um retângulo liso. Aqui a escolha vem da luminância: coluna clara
/// (amarelo, lima) pede tinta escura; o resto pede branco.
Color _inkOnTone(Color tone) =>
    tone.computeLuminance() > 0.55 ? const Color(0xFF0F172A) : Colors.white;

/// O nome da etapa — peça central. Pill sólida na cor da coluna, com o
/// ícone de lista sinalizando que dá para trocar por ali.
class _StageNamePill extends StatelessWidget {
  final String label;
  final Color tone;
  final Color ink;
  final bool isDark;
  final bool busy;
  final VoidCallback? onTap;

  const _StageNamePill({
    required this.label,
    required this.tone,
    required this.ink,
    required this.isDark,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tone,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              // Expanded + uma linha só: nome longo vira reticências em vez
              // de quebrar para baixo (regra do layout).
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.1,
                    color: ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (busy)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(ink),
                  ),
                )
              else if (onTap != null)
                Icon(
                  LucideIcons.chevronsUpDown,
                  size: 15,
                  color: ink.withValues(alpha: 0.85),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barra segmentada: um traço por etapa, preenchido até a atual.
///
/// Cada segmento é `Expanded`, então 4 ou 24 colunas cabem na mesma largura
/// — os traços afinam, o layout não estoura e nada rola para o lado.
class _StageTrack extends StatelessWidget {
  final int total;
  final int currentIndex;
  final Color tone;

  const _StageTrack({
    required this.total,
    required this.currentIndex,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final vazio = ThemeHelpers.borderColor(context).withValues(alpha: 0.55);
    return SizedBox(
      height: 4,
      child: Row(
        children: List<Widget>.generate(total, (i) {
          final andado = currentIndex >= 0 && i < currentIndex;
          final atual = i == currentIndex;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == total - 1 ? 0 : 3),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: atual
                      ? tone
                      : andado
                          ? tone.withValues(alpha: 0.45)
                          : vazio,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// =============================================================================
// HEADER
// =============================================================================

class _TaskHeroHeader extends StatelessWidget {
  final KanbanTask task;
  final _TaskState state;
  final bool canMarkResult;
  final bool canTransfer;
  final VoidCallback onMarkLost;
  final VoidCallback onMarkWon;
  final VoidCallback onTransfer;
  final VoidCallback onOpenResult;

  /// Colunas REAIS do funil (sintéticas já filtradas) para o trilho.
  final List<KanbanColumn> stages;
  final bool canMoveStage;

  /// Coluna destino em movimento — pinta o alvo em estado "indo".
  final String? movingToColumnId;
  final void Function(KanbanColumn column) onPickStage;

  /// Toque na etapa atual abre a lista completa (atalho de funil longo).
  final VoidCallback onOpenStageList;

  /// Edição do título NO PRÓPRIO hero (sem sheet): o nome do lead se
  /// corrige onde ele é lido.
  final bool canEditTitle;
  final bool editingTitle;
  final bool savingTitle;
  final TextEditingController titleController;
  final VoidCallback onStartTitleEdit;
  final VoidCallback onCancelTitleEdit;
  final VoidCallback onSaveTitle;

  const _TaskHeroHeader({
    required this.task,
    required this.state,
    required this.canMarkResult,
    required this.canTransfer,
    required this.onMarkLost,
    required this.onMarkWon,
    required this.onTransfer,
    required this.onOpenResult,
    required this.stages,
    required this.canMoveStage,
    required this.movingToColumnId,
    required this.onPickStage,
    required this.onOpenStageList,
    required this.canEditTitle,
    required this.editingTitle,
    required this.savingTitle,
    required this.titleController,
    required this.onStartTitleEdit,
    required this.onCancelTitleEdit,
    required this.onSaveTitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final priorityColor = task.priority != null
        ? Color(int.parse(task.priority!.color.replaceFirst('#', '0xFF')))
        : null;

    final closed = task.hasClosedResult;
    final showCrm = canMarkResult || canTransfer;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Trilha de contexto do card. Fechar e copiar ID saíram daqui: a
          // tela tem back e cluster de ações no chrome da barra.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (task.project != null)
                _BreadcrumbChip(
                  icon: Icons.account_tree_outlined,
                  label: task.project!.name,
                ),
              Icon(
                Icons.chevron_right_rounded,
                size: 14,
                color: secondary,
              ),
              _BreadcrumbChip(
                icon: state.stateIcon,
                label: state.stateLabel,
                color: state.accent,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PriorityMark(
                color: priorityColor ?? state.accent,
                hasPriority: task.priority != null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: editingTitle
                    ? _HeroTitleEditor(
                        controller: titleController,
                        saving: savingTitle,
                        onCancel: onCancelTitleEdit,
                        onSave: onSaveTitle,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Toque no título edita — a affordance é um lápis
                          // discreto colado ao fim do texto, não um botão.
                          InkWell(
                            onTap: canEditTitle ? onStartTitleEdit : null,
                            borderRadius: BorderRadius.circular(8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Flexible(
                                  child: Text(
                                    task.title,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.4,
                                      height: 1.2,
                                      fontSize: 18,
                                      color: ThemeHelpers.textColor(context),
                                    ),
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (canEditTitle) ...[
                                  const SizedBox(width: 7),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Icon(
                                      Icons.edit_rounded,
                                      size: 13,
                                      color:
                                          secondary.withValues(alpha: 0.75),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text.rich(
                            TextSpan(children: _headerSubtitleSpans(task)),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: secondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 11.5,
                              height: 1.35,
                              letterSpacing: 0.1,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
              ),
            ],
          ),
          // Linha de ações CRM: só as pills SÓLIDAS (cor cheia + texto
          // branco), ancoradas à DIREITA — o responsável saiu daqui, a
          // seção "Pessoas envolvidas" já cobre. FittedBox segura tela
          // estreita: encolhe o grupo em escala em vez de estourar a Row.
          // Digitando o título, o hero fica só com o essencial: com o
          // teclado aberto o espaço é curto e ninguém vai marcar resultado
          // no meio de uma correção de nome.
          if (showCrm && !editingTitle) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (canMarkResult && closed)
                      _HeroCrmIconButton(
                        icon: Icons.tune_rounded,
                        tooltip: 'Resultado · reabrir ou revisar',
                        color: secondary,
                        onPressed: onOpenResult,
                      ),
                    if (canMarkResult && !closed) ...[
                      _HeroSolidAction(
                        icon: LucideIcons.trophy,
                        label: 'Ganho',
                        color: _kConfirmGreen,
                        onPressed: onMarkWon,
                      ),
                      const SizedBox(width: 6),
                      _HeroSolidAction(
                        icon: LucideIcons.trendingDown,
                        label: 'Perdido',
                        color: const Color(0xFFDC2626),
                        onPressed: onMarkLost,
                      ),
                    ],
                    if (canTransfer) ...[
                      if (canMarkResult) const SizedBox(width: 6),
                      _HeroSolidAction(
                        icon: LucideIcons.arrowLeftRight,
                        label: 'Transferir',
                        color: const Color(0xFF6366F1),
                        onPressed: onTransfer,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          // TRILHO DO FUNIL — o percurso do lead como elemento gráfico do
          // hero, não como "opção" perdida no meio da ficha. Mostra de onde
          // ele veio, onde está e o que falta; tocar numa etapa MOVE o card.
          // Assim a função mais pedida vira desenho: informação e ação na
          // mesma peça.
          if (stages.isNotEmpty && !editingTitle) ...[
            const SizedBox(height: 16),
            _FunnelStageBar(
              stages: stages,
              currentColumnId: task.columnId,
              canMove: canMoveStage,
              movingToColumnId: movingToColumnId,
              onPick: onPickStage,
              onOpenList: onOpenStageList,
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Container(
              height: 1,
              color: ThemeHelpers.borderColor(context)
                  .withValues(alpha: isDark ? 0.45 : 0.55),
            ),
          ),
        ],
      ),
    );
  }

  /// Subtítulo do hero: "Criada por **Nome** · criada 3 d · atualizada 2 h".
  /// Nome do autor em w700; separadores '·' com respiro. Sem vermelho.
  static List<InlineSpan> _headerSubtitleSpans(KanbanTask task) {
    const sep = TextSpan(text: '  ·  ');
    final spans = <InlineSpan>[];
    final creator = task.createdBy?.name.trim() ?? '';
    if (creator.isNotEmpty) {
      spans.add(const TextSpan(text: 'Criada por '));
      spans.add(
        TextSpan(
          text: creator,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
      spans.add(sep);
    }
    spans.add(TextSpan(text: 'criada ${_relativeTime(task.createdAt)}'));
    if (task.updatedAt.difference(task.createdAt).inMinutes > 1) {
      spans.add(sep);
      spans.add(
        TextSpan(text: 'atualizada ${_relativeTime(task.updatedAt)}'),
      );
    }
    return spans;
  }
}

/// Barra de ações da edição inline: Cancelar (NUNCA vermelho — a cor vai
/// forçada porque o tema global pinta TextButton de vermelho) + Salvar
/// verde com estado de carregando no próprio botão.
class _InlineEditBar extends StatelessWidget {
  const _InlineEditBar({
    required this.onCancel,
    required this.onSave,
    required this.saving,
    this.saveLabel = 'Salvar',
    this.helper,
  });

  final VoidCallback onCancel;
  final VoidCallback onSave;
  final bool saving;
  final String saveLabel;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Row(
      children: [
        if (helper != null)
          Expanded(
            child: Text(
              helper!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                height: 1.3,
                color: secondary,
              ),
            ),
          )
        else
          const Spacer(),
        TextButton(
          onPressed: saving ? null : onCancel,
          style: TextButton.styleFrom(
            foregroundColor: secondary,
            visualDensity: VisualDensity.compact,
            textStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          child: const Text('Cancelar'),
        ),
        const SizedBox(width: 6),
        FilledButton(
          onPressed: saving ? null : onSave,
          style: FilledButton.styleFrom(
            backgroundColor: _kConfirmGreen,
            foregroundColor: Colors.white,
            disabledBackgroundColor: _kConfirmGreen.withValues(alpha: 0.4),
            disabledForegroundColor: Colors.white.withValues(alpha: 0.8),
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          child: saving
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(saveLabel),
        ),
      ],
    );
  }
}

/// Campo do título dentro do hero (mesma tipografia forte do título, para
/// a troca de modo não sacudir o layout).
class _HeroTitleEditor extends StatelessWidget {
  const _HeroTitleEditor({
    required this.controller,
    required this.saving,
    required this.onCancel,
    required this.onSave,
  });

  final TextEditingController controller;
  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = ThemeHelpers.borderColor(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: controller,
          autofocus: true,
          enabled: !saving,
          maxLines: 3,
          minLines: 1,
          maxLength: 200,
          textCapitalization: TextCapitalization.sentences,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
            height: 1.25,
            fontSize: 18,
            color: ThemeHelpers.textColor(context),
          ),
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            filled: true,
            fillColor: border.withValues(alpha: isDark ? 0.16 : 0.1),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: border.withValues(alpha: 0.5)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: border.withValues(alpha: 0.5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _kConfirmGreen.withValues(alpha: 0.7),
                width: 1.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _InlineEditBar(
          onCancel: onCancel,
          onSave: onSave,
          saving: saving,
          helper: 'Nome do lead no board',
        ),
      ],
    );
  }
}

/// Ícone compacto no hero (paridade com ações discretas no CRM web).
class _HeroCrmIconButton extends StatelessWidget {
  const _HeroCrmIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 420),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(11),
          child: Ink(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              color: color.withValues(alpha: 0.1),
              border: Border.all(color: color.withValues(alpha: 0.32)),
            ),
            child: Icon(icon, size: 21, color: color),
          ),
        ),
      ),
    );
  }
}

/// Pill SÓLIDA de ação CRM no hero (Perdido / Transferir): cor cheia,
/// texto branco, compacta — sem lavagem de tint nem borda.
class _HeroSolidAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _HeroSolidAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(11),
        splashColor: Colors.white.withValues(alpha: 0.18),
        highlightColor: Colors.white.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  letterSpacing: -0.1,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BreadcrumbChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _BreadcrumbChip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: color == null
            ? ThemeHelpers.borderColor(context).withValues(alpha: 0.12)
            : c.withValues(alpha: 0.1),
        border: Border.all(
          color: color == null
              ? ThemeHelpers.borderColor(context).withValues(alpha: 0.45)
              : c.withValues(alpha: 0.34),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: c),
          const SizedBox(width: 5),
          // Flexible (não maxWidth fixo): o chip encolhe pro espaço REAL da
          // linha — constante de 200 ainda estourava em tela estreita.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.1,
                color: c,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PriorityMark extends StatelessWidget {
  final Color color;
  final bool hasPriority;

  const _PriorityMark({required this.color, required this.hasPriority});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.36)),
      ),
      alignment: Alignment.center,
      child: Icon(
        hasPriority ? Icons.flag_rounded : Icons.task_alt_rounded,
        color: color,
        size: 20,
      ),
    );
  }
}

/// Avatar circular sólido (cor accent + iniciais), sem gradiente nem sombra.
class _SolidAvatar extends StatelessWidget {
  final KanbanUser? user;
  final double size;

  const _SolidAvatar({required this.user, this.size = 28});

  @override
  Widget build(BuildContext context) {
    final accent = _personColor(user?.name);
    final initials = _initialsFromName(user?.name);
    final hasAvatar = user?.avatar != null && user!.avatar!.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent,
        border: Border.all(
          color: accent.withValues(alpha: 0.6),
          width: 0.6,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasAvatar
          ? Image.network(
              user!.avatar!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _initialFallback(initials),
            )
          : _initialFallback(initials),
    );
  }

  Widget _initialFallback(String initials) => Center(
        child: Text(
          initials,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: size * 0.42,
            letterSpacing: 0.2,
            height: 1,
          ),
        ),
      );
}

String _initialsFromName(String? name) {
  if (name == null || name.trim().isEmpty) return '?';
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

// =============================================================================
// MINIMAL TAB BAR (underline)
// =============================================================================

class _TabItem {
  final IconData icon;
  final String label;
  final int? badge;

  /// Identidade da aba: a ATIVA pinta ícone + label + indicador nesta cor
  /// (inativas ficam slate/secundário). Cada aba fala na sua família.
  final Color color;

  const _TabItem({
    required this.icon,
    required this.label,
    required this.color,
    this.badge,
  });
}

/// Prende a barra de abas no topo enquanto o resto rola.
///
/// Altura fixa em 51: os `Tab` têm `height: 50` e o container soma 1px de
/// borda inferior. Um sliver persistente exige altura declarada — se ela
/// divergir da real, a barra corta ou deixa fresta.
class _PinnedTabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  const _PinnedTabBarDelegate({required this.child});

  static const double _altura = 51;

  @override
  double get minExtent => _altura;

  @override
  double get maxExtent => _altura;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // Fundo opaco: sem ele o conteúdo passaria POR TRÁS da barra presa.
    return Material(
      color: ThemeHelpers.backgroundColor(context),
      child: SizedBox(height: _altura, child: child),
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedTabBarDelegate old) =>
      old.child != child;
}

class _MinimalTabBar extends StatelessWidget {
  final TabController controller;
  final List<_TabItem> tabs;

  const _MinimalTabBar({required this.controller, required this.tabs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Cor da aba ativa — o modal dá setState no listener do controller,
    // então o rebuild acompanha a troca de aba.
    final active = controller.index.clamp(0, tabs.length - 1).toInt();
    final accent = tabs[active].color;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
          ),
        ),
      ),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: accent,
        unselectedLabelColor: secondary,
        indicatorColor: accent,
        indicatorWeight: 2.5,
        indicatorSize: TabBarIndicatorSize.label,
        dividerHeight: 0,
        labelPadding: EdgeInsets.zero,
        labelStyle: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w900,
          fontSize: 13,
          letterSpacing: 0.1,
        ),
        unselectedLabelStyle: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          letterSpacing: 0.1,
        ),
        tabs: [
          for (final t in tabs) _renderTab(t, secondary),
        ],
      ),
    );
  }

  Widget _renderTab(_TabItem t, Color secondary) {
    return Tab(
      height: 50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(t.icon, size: 16),
            const SizedBox(width: 7),
            Flexible(child: Text(t.label, overflow: TextOverflow.ellipsis)),
            if (t.badge != null && t.badge! > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: secondary.withValues(alpha: 0.14),
                ),
                child: Text(
                  '${t.badge}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// SECTION HEADER (overline + title)
// =============================================================================

class _SectionHeader extends StatelessWidget {
  final String overline;
  final String title;
  final String? trailing;

  /// Cor da seção — cada bloco da aba fala na sua família (indigo, emerald,
  /// violet…). Null cai no accent vermelho da marca (abas antigas).
  final Color? accent;

  const _SectionHeader({
    required this.overline,
    required this.title,
    this.trailing,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final tone = accent ?? _kanbanAccent(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 3.5,
          height: 24,
          decoration: BoxDecoration(
            color: tone,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                overline.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                  color: tone,
                  fontSize: 10,
                  height: 1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                  height: 1.1,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: secondary,
              letterSpacing: 0.4,
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// LEAD / CONTATO — número do lead estilizado (paridade com ClientInfoCard web)
// =============================================================================

/// Card do lead vinculado à negociação: nome + badges de tipo/status e os
/// dados de contato (telefone, WhatsApp, e-mail, CPF, cidade). Telefone e
/// WhatsApp são acionáveis (discar / abrir conversa). Espelha o
/// `ClientInfoCard` do front web.
///
/// Serve DOIS casos com o mesmo desenho:
/// 1. [client] preenchido — lead com cliente vinculado (tipo, status, CPF…);
/// 2. contato AVULSO ([contactName]/[contactPhone]/[contactEmail]) — lead de
///    campanha/WhatsApp que vive só em `task.contacts`. Sem cliente não há
///    tipo/status/CPF/cidade, então essas linhas simplesmente não aparecem.
class _LeadContactCard extends StatelessWidget {
  final KanbanTaskClient? client;

  /// Contato avulso (usado apenas quando [client] é nulo).
  final String? contactName;
  final String? contactPhone;
  final String? contactEmail;
  final String? contactJobTitle;

  /// Demais contatos do card com telefone — viram linhas extras no fim.
  final List<KanbanTaskContactInput> extraContacts;

  const _LeadContactCard({
    this.client,
    this.contactName,
    this.contactPhone,
    this.contactEmail,
    this.contactJobTitle,
    this.extraContacts = const [],
  });

  static const Map<String, Color> _typeColors = {
    'buyer': Color(0xFF3B82F6),
    'seller': Color(0xFFEF4444),
    'renter': Color(0xFF10B981),
    'tenant': Color(0xFF10B981),
    'lessor': Color(0xFFF59E0B),
    'landlord': Color(0xFFF59E0B),
    'investor': Color(0xFF8B5CF6),
  };

  static const Map<String, String> _typeLabels = {
    'buyer': 'Comprador',
    'seller': 'Vendedor',
    'renter': 'Inquilino',
    'tenant': 'Inquilino',
    'lessor': 'Proprietário',
    'landlord': 'Proprietário',
    'investor': 'Investidor',
  };

  static const Map<String, String> _statusLabels = {
    'active': 'Ativo',
    'inactive': 'Inativo',
    'contacted': 'Contatado',
    'interested': 'Interessado',
    'closed': 'Fechado',
  };

  static Future<void> _launch(String uri) async {
    final u = Uri.parse(uri);
    if (await canLaunchUrl(u)) {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    }
  }

  static String _telDigits(String s) => s.replaceAll(RegExp(r'[^0-9+]'), '');
  static String _waDigits(String s) => s.replaceAll(RegExp(r'\D'), '');
  static String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

  /// Máscara de exibição do telefone: remove o DDI 55 quando presente
  /// (números salvos como 55DD9XXXXXXXX) e aplica (DD) 9XXXX-XXXX.
  static String _maskPhone(String s) {
    var digits = s.replaceAll(RegExp(r'\D'), '');
    if ((digits.length == 12 || digits.length == 13) &&
        digits.startsWith('55')) {
      digits = digits.substring(2);
    }
    if (digits.length < 10) return s.trim();
    return Masks.phone(digits);
  }

  static void _copyToClipboard(BuildContext context, String value,
      String message) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  /// Trio de ações do número: copiar (slate), ligar (azul), WhatsApp (verde).
  /// Mesma tripla para o cliente vinculado e para o contato avulso.
  List<Widget> _phoneActions(BuildContext context, String raw) => [
        _LeadContactAction(
          icon: Icons.copy_rounded,
          tooltip: 'Copiar número',
          color: _kAuditTone,
          onTap: () =>
              _copyToClipboard(context, _maskPhone(raw), 'Número copiado'),
        ),
        _LeadContactAction(
          icon: Icons.call_rounded,
          tooltip: 'Ligar',
          color: _kChatTone,
          onTap: () => _launch('tel:${_telDigits(raw)}'),
        ),
        _LeadContactAction(
          icon: Icons.chat_rounded,
          tooltip: 'WhatsApp',
          color: const Color(0xFF25D366),
          onTap: () => _launch('https://wa.me/${_waDigits(raw)}'),
        ),
      ];

  /// Linhas dos demais contatos do card (nome como label, número como valor).
  List<Widget> _extraContactRows(BuildContext context) {
    final rows = <Widget>[];
    for (final c in extraContacts) {
      final raw = c.phone?.trim();
      if (raw == null || raw.isEmpty) continue;
      final name = c.name?.trim();
      rows.add(
        _LeadContactRow(
          icon: Icons.person_outline_rounded,
          label: (name != null && name.isNotEmpty) ? name : 'Outro contato',
          value: _maskPhone(raw),
          onCopy: () =>
              _copyToClipboard(context, _maskPhone(raw), 'Número copiado'),
          actions: _phoneActions(context, raw),
        ),
      );
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = ThemeHelpers.textColor(context);
    final border = ThemeHelpers.borderColor(context);

    final c = client;
    final typeKey = c?.type?.toLowerCase();
    final typeColor = typeKey != null ? _typeColors[typeKey] : null;
    final typeRaw = c?.type?.trim();
    final typeLabel = (typeRaw != null && typeRaw.isNotEmpty)
        ? (_typeLabels[typeKey] ?? _titleCase(typeRaw))
        : null;
    final statusKey = c?.status?.toLowerCase();
    final statusRaw = c?.status?.trim();
    final statusLabel = (statusRaw != null && statusRaw.isNotEmpty)
        ? (_statusLabels[statusKey] ?? _titleCase(statusRaw))
        : null;

    // Cliente vinculado manda; sem ele, o contato avulso do card assume.
    final rawName = c != null ? c.name.trim() : (contactName?.trim() ?? '');
    final displayName = rawName.isNotEmpty
        ? rawName
        : (c != null ? 'Lead sem nome' : 'Contato do lead');
    final phone =
        c != null ? c.phone?.trim() : contactPhone?.trim();
    final whatsapp = c?.whatsapp?.trim();
    final showWhatsapp =
        whatsapp != null && whatsapp.isNotEmpty && whatsapp != phone;
    final email = c != null ? c.email?.trim() : contactEmail?.trim();
    final cpf = c?.cpf?.trim();
    final city = c?.city?.trim();
    final role = c == null ? contactJobTitle?.trim() : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabeçalho: nome + badge de tipo
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  displayName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: textColor,
                    fontSize: 16,
                  ),
                ),
              ),
              if (typeLabel != null) ...[
                const SizedBox(width: 8),
                _LeadBadge(label: typeLabel, color: typeColor),
              ] else if (role != null && role.isNotEmpty) ...[
                const SizedBox(width: 8),
                _LeadBadge(label: role, color: _kContactTone),
              ],
            ],
          ),
          if (statusLabel != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: _LeadBadge(label: statusLabel, color: null),
            ),
          ],
          const SizedBox(height: 14),
          Container(height: 1, color: border.withValues(alpha: 0.6)),
          const SizedBox(height: 14),

          // Telefone (número do lead) em destaque: máscara correta + copiar
          if (phone != null && phone.isNotEmpty)
            _LeadContactRow(
              icon: Icons.phone_rounded,
              label: 'Telefone',
              value: _maskPhone(phone),
              onCopy: () => _copyToClipboard(
                context,
                _maskPhone(phone),
                'Número copiado',
              ),
              actions: _phoneActions(context, phone),
            ),
          if (showWhatsapp)
            _LeadContactRow(
              icon: Icons.chat_rounded,
              label: 'WhatsApp',
              value: _maskPhone(whatsapp),
              onCopy: () => _copyToClipboard(
                context,
                _maskPhone(whatsapp),
                'Número copiado',
              ),
              actions: [
                _LeadContactAction(
                  icon: Icons.copy_rounded,
                  tooltip: 'Copiar número',
                  color: _kAuditTone,
                  onTap: () => _copyToClipboard(
                    context,
                    _maskPhone(whatsapp),
                    'Número copiado',
                  ),
                ),
                _LeadContactAction(
                  icon: Icons.chat_rounded,
                  tooltip: 'Abrir WhatsApp',
                  color: const Color(0xFF25D366),
                  onTap: () => _launch('https://wa.me/${_waDigits(whatsapp)}'),
                ),
              ],
            ),
          if (email != null && email.isNotEmpty)
            _LeadContactRow(
              icon: Icons.mail_outline_rounded,
              label: 'E-mail',
              value: email,
              actions: [
                _LeadContactAction(
                  icon: Icons.send_rounded,
                  tooltip: 'Enviar e-mail',
                  color: _kBriefingTone,
                  onTap: () => _launch('mailto:$email'),
                ),
              ],
            ),
          if (cpf != null && cpf.isNotEmpty)
            _LeadContactRow(
              icon: Icons.badge_outlined,
              label: 'CPF',
              value: cpf.replaceAll(RegExp(r'\D'), '').length == 11
                  ? Masks.cpf(cpf)
                  : cpf,
              onCopy: () => _copyToClipboard(
                context,
                cpf.replaceAll(RegExp(r'\D'), '').length == 11
                    ? Masks.cpf(cpf)
                    : cpf,
                'CPF copiado',
              ),
            ),
          if (city != null && city.isNotEmpty)
            _LeadContactRow(
              icon: Icons.location_on_outlined,
              label: 'Cidade',
              value: city,
            ),
          ..._extraContactRows(context),
        ],
      ),
    );
  }
}

/// Pílula de categoria/status do lead (estilo badge do web).
class _LeadBadge extends StatelessWidget {
  final String label;
  final Color? color;

  const _LeadBadge({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF6B7280);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: c,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Linha de um dado de contato: label (ícone + texto) + valor, com ações
/// opcionais à direita (ligar / WhatsApp / e-mail).
class _LeadContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final List<Widget> actions;

  /// Toque no valor copia (feedback fica a cargo do chamador).
  final VoidCallback? onCopy;

  const _LeadContactRow({
    required this.icon,
    required this.label,
    required this.value,
    this.actions = const [],
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final valueText = Text(
      value,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: textColor,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 14, color: secondary),
                    const SizedBox(width: 6),
                    Text(
                      label.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: secondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                onCopy == null
                    ? valueText
                    : InkWell(
                        onTap: onCopy,
                        borderRadius: BorderRadius.circular(6),
                        child: valueText,
                      ),
              ],
            ),
          ),
          for (final a in actions) ...[
            const SizedBox(width: 8),
            a,
          ],
        ],
      ),
    );
  }
}

/// Botão de ação rápida (ligar / WhatsApp / e-mail) no card do lead.
/// Cada ação fala na sua cor: ligar azul, WhatsApp verde, copiar neutro.
class _LeadContactAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  const _LeadContactAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final accent = color ?? _kanbanAccent(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: accent),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// RAIO-X — ficha técnica flush do card (substitui o antigo grid 2×2 de caixas)
// =============================================================================

/// Segue a mesma gramática editorial do BRIEFING logo acima: eyebrow +
/// hairline, conteúdo direto na página (sem caixas tingidas).
///
/// Estrutura:
/// 1. Eyebrow `RAIO-X` com o **resultado** do card à direita (EM ABERTO /
///    GANHO / PERDIDO / CANCELADO) — substitui o antigo tile de "Status".
/// 2. **Valor da negociação** como linha-herói (tipografia grande, verde).
/// 3. Ficha técnica em 2 colunas separadas por hairlines: prazo, prioridade,
///    funil, idade no funil, última atividade e cadência — e, quando
///    existem, recuperação de perdido, pré-atendimento e transferência.
///    Valores com informação REAL falam na cor do accent da entrada (a
///    ficha era "morta", toda slate); "sem prazo"/"inativa" seguem neutros.
/// 4. Card perdido ganha uma régua vermelha com o motivo da perda (mesma
///    linguagem da régua accent do briefing).
class _TaskDossier extends StatelessWidget {
  final KanbanTask task;
  final _TaskState state;

  /// Ficha VIVA: a célula editável ganha só um lápis discreto no canto e
  /// responde ao toque — nada de virar formulário.
  final bool canEdit;
  final String? savingField;
  final VoidCallback onEditValue;
  final VoidCallback onEditDeadline;
  final VoidCallback onEditPriority;

  const _TaskDossier({
    required this.task,
    required this.state,
    required this.canEdit,
    required this.savingField,
    required this.onEditValue,
    required this.onEditDeadline,
    required this.onEditPriority,
  });

  static String? _deadlineHelper(_TaskState state) {
    final d = state.daysFromToday;
    if (d == null) return null;
    if (d < 0) {
      final abs = d.abs();
      return 'Atrasada há $abs dia${abs == 1 ? '' : 's'}';
    }
    if (d == 0) return 'Vence hoje';
    return 'Em $d dia${d == 1 ? '' : 's'}';
  }

  static String _money(double v) {
    return NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
      decimalDigits: v % 1 == 0 ? 0 : 2,
    ).format(v);
  }

  /// "há 5 min" / "há 3 h" / "há 2 dias" — voz curta pra última atividade.
  static String _relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'agora mesmo';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'há ${diff.inHours} h';
    if (diff.inDays < 30) {
      return 'há ${diff.inDays} dia${diff.inDays == 1 ? '' : 's'}';
    }
    final months = diff.inDays ~/ 30;
    if (months < 12) return 'há $months ${months == 1 ? 'mês' : 'meses'}';
    final years = diff.inDays ~/ 365;
    return 'há $years ano${years == 1 ? '' : 's'}';
  }

  (String, Color) _resultInfo() {
    switch (task.result) {
      case 'won':
        return ('GANHO', const Color(0xFF10B981));
      case 'lost':
        return ('PERDIDO', const Color(0xFFEF4444));
      case 'cancelled':
        return ('CANCELADO', const Color(0xFF94A3B8));
    }
    if (task.isCompleted) return ('CONCLUÍDA', const Color(0xFF10B981));
    return ('EM ABERTO', const Color(0xFF0891B2));
  }

  _SpecEntry _cadenceEntry(Color slate) {
    if (task.cadenceEnabled == true) {
      final attempts = task.cadenceAttemptCount ?? 0;
      final max = task.cadenceMaxAttempts;
      final awaiting = task.cadenceAwaitingReply == true;
      return _SpecEntry(
        icon: LucideIcons.repeat,
        accent: awaiting ? const Color(0xFFF59E0B) : const Color(0xFF059669),
        label: 'Cadência',
        value: max != null && max > 0
            ? '$attempts de $max envios'
            : '$attempts envio${attempts == 1 ? '' : 's'}',
        helper: awaiting
            ? 'Aguardando resposta do lead'
            : 'Automação ativa na etapa',
        // Cadência ativa fala na cor: verde rodando, âmbar aguardando.
        valueAccent: true,
        numeric: true,
      );
    }
    return _SpecEntry(
      icon: LucideIcons.repeat,
      accent: slate,
      label: 'Cadência',
      value: 'Inativa',
      helper: 'Sem automação nesta etapa',
    );
  }

  List<_SpecEntry> _entries() {
    final priorityColor = task.priority != null
        ? Color(int.parse(task.priority!.color.replaceFirst('#', '0xFF')))
        : null;
    const slate = Color(0xFF64748B);
    final due = task.dueDate?.toLocal();
    final created = task.createdAt.toLocal();
    final updated = task.updatedAt.toLocal();
    final ageDays = DateTime.now().difference(created).inDays;

    final entries = <_SpecEntry>[
      // PRAZO — data real do card; cor segue a saúde (atrasada/vence hoje).
      _SpecEntry(
        icon: state.health == _TaskHealth.overdue
            ? LucideIcons.circleAlert
            : state.health == _TaskHealth.dueToday
                ? LucideIcons.triangleAlert
                : LucideIcons.calendarClock,
        accent: due == null ? slate : state.accent,
        label: 'Prazo',
        value: due == null
            ? 'Sem prazo'
            : DateFormat("d 'de' MMM", 'pt_BR').format(due),
        helper: state.health == _TaskHealth.completed
            ? 'Card concluído'
            : due == null
                ? (canEdit ? 'Toque para definir' : 'Sem prazo definido')
                : _deadlineHelper(state),
        // Com prazo definido o valor fala na cor do estado (em dia
        // inclusive) — só "Sem prazo" fica neutro.
        valueAccent: due != null,
        onTap: canEdit ? onEditDeadline : null,
        saving: savingField == 'dueDate',
      ),

      // PRIORIDADE — dot na cor real vinda do backend.
      _SpecEntry(
        icon: LucideIcons.flag,
        accent: priorityColor ?? const Color(0xFF94A3B8),
        label: 'Prioridade',
        value: task.priority?.label ?? 'Não definida',
        helper: task.priority == null
            ? (canEdit ? 'Toque para definir' : 'Não definida')
            : null,
        dot: priorityColor != null,
        valueAccent: task.priority != null,
        onTap: canEdit ? onEditPriority : null,
        saving: savingField == 'priority',
      ),

      // FUNIL — violeta = contexto/organização.
      _SpecEntry(
        icon: LucideIcons.gitBranch,
        accent: task.project != null ? const Color(0xFF8B5CF6) : slate,
        label: 'Funil',
        value: task.project?.name ?? 'Sem funil',
        helper: task.project == null
            ? 'Sem projeto associado'
            : task.project!.isPersonal == true
                ? 'Workspace pessoal'
                : task.project!.status.label,
        valueAccent: task.project != null,
      ),

      // IDADE — quanto tempo o lead está vivo no funil (sky).
      _SpecEntry(
        icon: LucideIcons.hourglass,
        accent: const Color(0xFF0EA5E9),
        label: 'No funil há',
        value: ageDays <= 0 ? 'Hoje' : '$ageDays dia${ageDays == 1 ? '' : 's'}',
        helper: 'desde ${DateFormat("d 'de' MMM", 'pt_BR').format(created)}',
        numeric: true,
        valueAccent: true,
      ),

      // ÚLTIMA ATIVIDADE — voz relativa + data completa no helper.
      _SpecEntry(
        icon: LucideIcons.history,
        accent: slate,
        label: 'Última atividade',
        value: _relative(updated),
        helper: DateFormat("d 'de' MMM, HH:mm", 'pt_BR').format(updated),
        numeric: true,
      ),

      // CADÊNCIA WhatsApp da etapa atual.
      _cadenceEntry(slate),
    ];

    // Entradas condicionais — só aparecem quando carregam informação real.
    if ((task.lossMarkCount ?? 0) > 0 || task.inRecoveryPool == true) {
      entries.add(_SpecEntry(
        icon: LucideIcons.rotateCcw,
        accent: const Color(0xFFEC4899),
        label: 'Recuperação',
        value:
            task.inRecoveryPool == true ? 'Pool de perdidos' : 'Reincidente',
        helper: (task.lossMarkCount ?? 0) > 0
            ? 'Marcado perdido ${task.lossMarkCount}×'
            : 'Lead em recuperação',
        valueAccent: true,
      ));
    }
    final preService = task.preService?.trim();
    if (preService != null && preService.isNotEmpty) {
      entries.add(_SpecEntry(
        icon: LucideIcons.headset,
        accent: const Color(0xFF14B8A6),
        label: 'Pré-atendimento',
        value: preService,
        helper: 'Quem qualificou o lead',
        valueAccent: true,
      ));
    }
    if (task.transferDate != null) {
      entries.add(_SpecEntry(
        icon: LucideIcons.arrowLeftRight,
        accent: const Color(0xFF6366F1),
        label: 'Transferência',
        value: DateFormat("d 'de' MMM 'de' yyyy", 'pt_BR')
            .format(task.transferDate!.toLocal()),
        helper: 'Card movido de funil',
        valueAccent: true,
      ));
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    const accent = _kDossierTone;
    final hairline = ThemeHelpers.borderColor(context).withValues(alpha: 0.35);
    final (resultLabel, resultColor) = _resultInfo();
    final entries = _entries();
    final money = task.totalValue;
    final moneyColor =
        isDark ? const Color(0xFF34D399) : const Color(0xFF059669);

    // Pares de entradas por linha; sobra ímpar vira linha cheia.
    final rows = <List<_SpecEntry>>[];
    for (var i = 0; i < entries.length; i += 2) {
      rows.add(entries.sublist(
          i, i + 2 > entries.length ? entries.length : i + 2));
    }

    final lossReason = task.lossReason?.trim();
    final resultNotes = task.resultNotes?.trim();
    final showLoss = task.result == 'lost' &&
        ((lossReason != null && lossReason.isNotEmpty) ||
            (resultNotes != null && resultNotes.isNotEmpty));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Eyebrow no mesmo ritmo do BRIEFING + selo de resultado à direita.
        Row(
          children: [
            Text(
              'RAIO-X',
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 2.6,
                fontWeight: FontWeight.w900,
                color: accent,
                fontSize: 10,
                height: 1,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Container(height: 1, color: hairline)),
            const SizedBox(width: 10),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: resultColor,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              resultLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1.6,
                fontWeight: FontWeight.w900,
                color: resultColor,
                fontSize: 10,
                height: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Linha-herói: valor da negociação (também editável no toque).
        InkWell(
          onTap: canEdit ? onEditValue : null,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'VALOR DA NEGOCIAÇÃO',
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w800,
                        color: secondary,
                        fontSize: 10,
                        height: 1,
                      ),
                    ),
                    if (canEdit) ...[
                      const SizedBox(width: 7),
                      if (savingField == 'totalValue')
                        SizedBox(
                          width: 11,
                          height: 11,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: moneyColor,
                          ),
                        )
                      else
                        Icon(
                          Icons.edit_rounded,
                          size: 12,
                          color: secondary.withValues(alpha: 0.7),
                        ),
                    ],
                  ],
                ),
                const SizedBox(height: 7),
                if (money != null)
                  Text(
                    _money(money),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.8,
                      height: 1.05,
                      fontSize: 26,
                      color: moneyColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  )
                else ...[
                  Text(
                    'Não informado',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: secondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    canEdit
                        ? 'Toque para registrar o potencial'
                        : 'Potencial não registrado',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: secondary.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Ficha técnica — linhas de 2 colunas com hairlines.
        for (final row in rows) ...[
          Container(height: 1, color: hairline),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _SpecTile(
                    entry: row[0],
                    padRight: row.length == 2,
                  ),
                ),
                if (row.length == 2) ...[
                  Container(width: 1, color: hairline),
                  Expanded(
                    child: _SpecTile(entry: row[1], padLeft: true),
                  ),
                ],
              ],
            ),
          ),
        ],
        Container(height: 1, color: hairline),

        // Motivo da perda — régua vermelha na linguagem do briefing.
        if (showLoss) ...[
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MOTIVO DA PERDA',
                        style: theme.textTheme.labelSmall?.copyWith(
                          letterSpacing: 1.6,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFFEF4444),
                          fontSize: 10,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        KanbanLossReason.tryParse(lossReason)?.label ??
                            (lossReason != null && lossReason.isNotEmpty
                                ? lossReason
                                : 'Não informado'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          letterSpacing: -0.2,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                      if (resultNotes != null && resultNotes.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          resultNotes,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12.5,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w500,
                            color: secondary,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Uma entrada da ficha técnica do dossiê.
class _SpecEntry {
  final IconData icon;
  final Color accent;
  final String label;
  final String value;
  final String? helper;

  /// Valor pintado na cor accent — sempre que a entrada carrega informação
  /// real (prazo definido, funil, idade, cadência ativa…); estados
  /// "quentes" (atrasada, aguardando) continuam forçados. No modo claro o
  /// tile escurece a tinta pra manter contraste.
  final bool valueAccent;

  /// Números tabulares (datas relativas, contagens, dias).
  final bool numeric;

  /// Dot colorido antes do valor (prioridade usa a cor real do backend).
  final bool dot;

  /// Célula editável — ganha lápis discreto no canto e responde ao toque.
  final VoidCallback? onTap;

  /// Gravando este campo — o spinner nasce no lugar do lápis.
  final bool saving;

  const _SpecEntry({
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
    this.helper,
    this.valueAccent = false,
    this.numeric = false,
    this.dot = false,
    this.onTap,
    this.saving = false,
  });
}

/// Célula flush da ficha técnica: ícone tingido + label small-caps,
/// valor forte, helper discreto. Sem caixa — as hairlines do dossiê
/// fazem a divisão.
class _SpecTile extends StatelessWidget {
  final _SpecEntry entry;
  final bool padLeft;
  final bool padRight;

  const _SpecTile({
    required this.entry,
    this.padLeft = false,
    this.padRight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    // Tinta rende diferente por tema: no claro, sky/âmbar puros lavam no
    // fundo branco — escurece ~18% preservando o matiz; no escuro a cor
    // pura já contrasta.
    final accentInk = isDark
        ? entry.accent
        : Color.alphaBlend(
            Colors.black.withValues(alpha: 0.18),
            entry.accent,
          );

    final conteudo = Padding(
      padding: EdgeInsets.only(
        top: 12,
        bottom: 12,
        left: padLeft ? 14 : 0,
        right: padRight ? 14 : 0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(entry.icon, size: 13, color: entry.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  entry.label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                    color: secondary,
                    fontSize: 9.5,
                    height: 1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Affordance mínima: só um lápis de 12 no canto da célula.
              if (entry.saving) ...[
                const SizedBox(width: 4),
                SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: entry.accent,
                  ),
                ),
              ] else if (entry.onTap != null) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.edit_rounded,
                  size: 12,
                  color: secondary.withValues(alpha: 0.65),
                ),
              ],
            ],
          ),
          const SizedBox(height: 7),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (entry.dot) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: entry.accent,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  entry.value,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    letterSpacing: -0.2,
                    height: 1.2,
                    color: entry.valueAccent
                        ? accentInk
                        : ThemeHelpers.textColor(context),
                    fontFeatures: entry.numeric
                        ? const [FontFeature.tabularFigures()]
                        : null,
                  ),
                ),
              ),
            ],
          ),
          if (entry.helper != null && entry.helper!.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              entry.helper!,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: secondary,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );

    if (entry.onTap == null) return conteudo;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: entry.saving ? null : entry.onTap,
        borderRadius: BorderRadius.circular(10),
        child: conteudo,
      ),
    );
  }
}

// =============================================================================
// ETAPA DO FUNIL — linha do RAIO-X + seletor de coluna
// =============================================================================

/// Cor REAL da coluna (`KanbanColumn.color`, hex do backend — mesma leitura
/// do board). Sem cor válida cai no violeta de contexto/organização já usado
/// na entrada FUNIL.
Color _columnTone(String? hex) {
  final raw = hex?.trim();
  if (raw != null && raw.isNotEmpty) {
    try {
      return Color(int.parse(raw.replaceFirst('#', '0xFF')));
    } catch (_) {}
  }
  return _kPeopleTone;
}

/// Tinta legível da cor da coluna: no claro escurece ~18% preservando o matiz
/// (mesma regra do `_SpecTile`); no escuro a cor pura já contrasta.
Color _columnInk(BuildContext context, Color tone) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark
      ? tone
      : Color.alphaBlend(Colors.black.withValues(alpha: 0.18), tone);
}


/// Seletor de etapa — bottom sheet na anatomia da casa (grabber, eyebrow na
/// cor do funil, título, fechar, divisor gradient). Devolve a coluna escolhida
/// via `Navigator.pop`; quem move é o modal (que tem o contexto vivo pro
/// SnackBar).
class _MoveStageSheet extends StatelessWidget {
  final List<KanbanColumn> columns;
  final String currentColumnId;
  final Map<String, int?> counts;

  const _MoveStageSheet({
    required this.columns,
    required this.currentColumnId,
    required this.counts,
  });

  /// Violeta de contexto/funil — a mesma família da entrada FUNIL no RAIO-X.
  static const Color _tone = Color(0xFF8B5CF6);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mq = MediaQuery.of(context);
    final border = ThemeHelpers.borderColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.78),
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: ThemeHelpers.cardBackgroundColor(context),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(26)),
              border: Border.all(color: border.withValues(alpha: 0.45)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.14),
                  blurRadius: 44,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  child: Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: border.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 4, 10, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'MOVER LEAD',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.35,
                                color: _tone,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Para qual etapa?',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.65,
                                height: 1.02,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close_rounded, color: muted),
                        tooltip: 'Fechar',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _tone.withValues(alpha: 0.55),
                        _tone.withValues(alpha: 0.08),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                        14, 12, 14, 16 + mq.padding.bottom),
                    physics: const BouncingScrollPhysics(),
                    shrinkWrap: true,
                    itemCount: columns.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final c = columns[i];
                      return _StageOptionRow(
                        column: c,
                        isCurrent: c.id == currentColumnId,
                        count: counts[c.id],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Linha rica de uma etapa: dot na cor REAL da coluna, nome e contagem. A
/// etapa atual aparece marcada (check) e sem toque.
class _StageOptionRow extends StatelessWidget {
  final KanbanColumn column;
  final bool isCurrent;
  final int? count;

  const _StageOptionRow({
    required this.column,
    required this.isCurrent,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final tone = _columnTone(column.color);
    final ink = _columnInk(context, tone);

    final helper = isCurrent
        ? 'Etapa atual do lead'
        : (count == null
            ? null
            : '$count lead${count == 1 ? '' : 's'} nesta etapa');

    final row = Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: isCurrent
            ? tone.withValues(alpha: isDark ? 0.14 : 0.08)
            : Colors.transparent,
        border: Border.all(
          color: isCurrent
              ? tone.withValues(alpha: 0.4)
              : ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tone,
              boxShadow: [
                BoxShadow(
                  color: tone.withValues(alpha: 0.4),
                  blurRadius: 7,
                ),
              ],
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  column.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    letterSpacing: -0.2,
                    height: 1.2,
                    color: isCurrent ? ink : ThemeHelpers.textColor(context),
                  ),
                ),
                if (helper != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    helper,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: secondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(
            isCurrent
                ? Icons.check_circle_rounded
                : Icons.arrow_forward_rounded,
            size: isCurrent ? 20 : 18,
            color: isCurrent ? tone : secondary,
          ),
        ],
      ),
    );

    if (isCurrent) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(column),
        borderRadius: BorderRadius.circular(14),
        child: row,
      ),
    );
  }
}

// =============================================================================
// PEOPLE STRIP
// =============================================================================

/// Duas colunas flush lado a lado (Responsável · Criado por) separadas por
/// hairline VERTICAL — substitui os 2 cards encaixotados. Cada coluna:
/// avatar 44 com anel de 2px na cor da pessoa, nome forte, papel em small
/// caps colorido e e-mail discreto. Sem containers nem bordas.
class _PeopleStrip extends StatelessWidget {
  final KanbanTask task;

  /// Só o RESPONSÁVEL é editável — "criado por" é fato histórico.
  final bool canEditAssignee;
  final bool savingAssignee;
  final VoidCallback onEditAssignee;

  const _PeopleStrip({
    required this.task,
    required this.canEditAssignee,
    required this.savingAssignee,
    required this.onEditAssignee,
  });

  @override
  Widget build(BuildContext context) {
    final hairline =
        ThemeHelpers.borderColor(context).withValues(alpha: 0.45);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _PersonColumn(
              role: 'Responsável',
              user: task.assignedTo,
              emptyHint: 'Nenhum responsável',
              onTap: canEditAssignee ? onEditAssignee : null,
              saving: savingAssignee,
            ),
          ),
          VerticalDivider(width: 28, thickness: 1, color: hairline),
          Expanded(
            child: _PersonColumn(
              role: 'Criado por',
              user: task.createdBy,
              emptyHint: 'Desconhecido',
            ),
          ),
        ],
      ),
    );
  }
}

/// Coluna flush de uma pessoa do card. Vazio = anel tracejado slate +
/// texto muted (sem inventar pessoa).
class _PersonColumn extends StatelessWidget {
  final String role;
  final KanbanUser? user;
  final String emptyHint;

  /// Coluna editável (responsável) — toque troca a pessoa.
  final VoidCallback? onTap;
  final bool saving;

  const _PersonColumn({
    required this.role,
    required this.user,
    required this.emptyHint,
    this.onTap,
    this.saving = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final assigned = user != null;
    final tone = assigned ? _personColor(user!.name) : const Color(0xFF64748B);

    final coluna = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (assigned)
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: tone.withValues(alpha: 0.75),
                width: 2,
              ),
            ),
            child: _SolidAvatar(user: user, size: 44),
          )
        else
          CustomPaint(
            painter: _DashedRingPainter(
              color: secondary.withValues(alpha: 0.55),
            ),
            child: SizedBox(
              // Mesmo footprint do avatar com anel (44 + 2×2.5 + 2×2).
              width: 53,
              height: 53,
              child: Icon(
                Icons.person_outline_rounded,
                size: 20,
                color: secondary,
              ),
            ),
          ),
        const SizedBox(height: 10),
        Text(
          assigned ? user!.name : emptyHint,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            letterSpacing: -0.2,
            height: 1.2,
            color: assigned ? ThemeHelpers.textColor(context) : secondary,
          ),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                role.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 9.5,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                  color: assigned ? tone : secondary,
                  height: 1,
                ),
              ),
            ),
            if (saving) ...[
              const SizedBox(width: 5),
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(strokeWidth: 1.6, color: tone),
              ),
            ] else if (onTap != null) ...[
              const SizedBox(width: 5),
              Icon(
                Icons.edit_rounded,
                size: 11,
                color: secondary.withValues(alpha: 0.65),
              ),
            ],
          ],
        ),
        if (assigned && user!.email.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            user!.email,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: secondary,
              height: 1.2,
            ),
          ),
        ],
      ],
    );

    if (onTap == null) return coluna;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: saving ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: coluna,
        ),
      ),
    );
  }
}

/// Anel circular tracejado (slot vazio de pessoa) — Border não faz dash.
class _DashedRingPainter extends CustomPainter {
  final Color color;

  const _DashedRingPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final radius = (size.shortestSide - paint.strokeWidth) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    const dashCount = 14;
    const step = 2 * math.pi / dashCount;
    // 55% traço / 45% respiro por segmento.
    const sweep = step * 0.55;
    for (var i = 0; i < dashCount; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * step,
        sweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter oldDelegate) =>
      oldDelegate.color != color;
}

// =============================================================================
// PEÇAS DE EDIÇÃO NA FICHA (flush — nenhuma vira card dentro de card)
// =============================================================================

/// Lápis de 12 num alvo de toque decente. Usado onde o conteúdo já responde
/// a outro gesto (texto selecionável, por exemplo).
class _MicroEditButton extends StatelessWidget {
  const _MicroEditButton({required this.onTap, required this.tooltip});

  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(
              Icons.edit_rounded,
              size: 13,
              color: secondary.withValues(alpha: 0.8),
            ),
          ),
        ),
      ),
    );
  }
}

/// Linha discreta de "aqui não tem nada" — sem caixa, sem drama.
class _MutedHint extends StatelessWidget {
  const _MutedHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.only(left: 2, top: 2, bottom: 2),
      child: Row(
        children: [
          Icon(icon, size: 15, color: secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w600,
                height: 1.4,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Linha de vínculo (cliente / imóvel): hairline em cima, dado à esquerda,
/// affordance de edição à direita. Mesma gramática das células do RAIO-X.
class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.canEdit,
    required this.saving,
    required this.onTap,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String? value;
  final bool canEdit;
  final bool saving;
  final VoidCallback onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hairline = ThemeHelpers.borderColor(context).withValues(alpha: 0.35);
    final vinculado = value != null && value!.trim().isNotEmpty;

    final linha = Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: vinculado ? _kLinksTone : secondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                    color: secondary,
                    fontSize: 9.5,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  vinculado ? value!.trim() : 'Não vinculado',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: vinculado ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 14.5,
                    letterSpacing: -0.2,
                    height: 1.2,
                    fontStyle:
                        vinculado ? FontStyle.normal : FontStyle.italic,
                    color: vinculado
                        ? ThemeHelpers.textColor(context)
                        : secondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (saving)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: _kLinksTone,
              ),
            )
          else if (canEdit)
            Icon(
              vinculado ? Icons.edit_rounded : Icons.add_link_rounded,
              size: 15,
              color: secondary.withValues(alpha: 0.7),
            ),
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: hairline),
          bottom: isLast ? BorderSide(color: hairline) : BorderSide.none,
        ),
      ),
      child: canEdit
          ? Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: saving ? null : onTap,
                child: linha,
              ),
            )
          : linha,
    );
  }
}

/// As duas ações do bloco de contato: registrar ligação (a mais repetida do
/// dia, por isso sólida e à esquerda) e gerenciar a lista de contatos.
class _ContactActionBar extends StatelessWidget {
  const _ContactActionBar({
    required this.registering,
    required this.onRegisterCall,
    required this.canEdit,
    required this.savingContacts,
    required this.contactsCount,
    required this.onManageContacts,
  });

  final bool registering;
  final VoidCallback onRegisterCall;
  final bool canEdit;
  final bool savingContacts;
  final int contactsCount;
  final VoidCallback onManageContacts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);

    final registrar = Material(
      color: registering
          ? _kContactTone.withValues(alpha: 0.55)
          : _kContactTone,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: registering ? null : onRegisterCall,
        borderRadius: BorderRadius.circular(13),
        splashColor: Colors.white.withValues(alpha: 0.18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (registering)
                  const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else
                  const Icon(Icons.phone_in_talk_rounded,
                      size: 17, color: Colors.white),
                const SizedBox(width: 8),
                const Text(
                  'Registrar ligação',
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                    letterSpacing: -0.1,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final gerenciar = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: savingContacts ? null : onManageContacts,
        borderRadius: BorderRadius.circular(13),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            color: _kContactTone.withValues(alpha: isDark ? 0.12 : 0.07),
            border: Border.all(
              color: _kContactTone.withValues(alpha: 0.34),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (savingContacts)
                    const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _kContactTone,
                      ),
                    )
                  else
                    const Icon(Icons.contacts_rounded,
                        size: 17, color: _kContactTone),
                  const SizedBox(width: 8),
                  Text(
                    contactsCount > 0 ? 'Contatos ($contactsCount)' : 'Contatos',
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(
                      color: _kContactTone,
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                      letterSpacing: -0.1,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(flex: 3, child: registrar),
            if (canEdit) ...[
              const SizedBox(width: 10),
              Expanded(flex: 2, child: gerenciar),
            ],
          ],
        ),
        const SizedBox(height: 7),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.history_rounded, size: 12, color: secondary),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                'A ligação entra no histórico do card com data e hora.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: secondary,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// INTERNO — a anotação que fica entre o time. Mesma gramática editorial do
/// BRIEFING (eyebrow + hairline + régua accent), em âmbar queimado para
/// separar na leitura o que é do cliente do que é da casa.
class _InternalNotesSection extends StatelessWidget {
  const _InternalNotesSection({
    required this.notes,
    required this.canEdit,
    required this.editing,
    required this.saving,
    required this.controller,
    required this.onStartEdit,
    required this.onCancel,
    required this.onSave,
  });

  final String? notes;
  final bool canEdit;
  final bool editing;
  final bool saving;
  final TextEditingController controller;
  final VoidCallback onStartEdit;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final border = ThemeHelpers.borderColor(context);
    const accent = _kInternalTone;
    final vazio = notes == null || notes!.trim().isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'INTERNO',
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 2.6,
                fontWeight: FontWeight.w900,
                color: accent,
                fontSize: 10,
                height: 1,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 1,
                color: border.withValues(alpha: 0.35),
              ),
            ),
            if (canEdit && !editing && !vazio) ...[
              const SizedBox(width: 6),
              _MicroEditButton(
                onTap: onStartEdit,
                tooltip: 'Editar observação interna',
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        if (editing) ...[
          TextField(
            controller: controller,
            autofocus: true,
            enabled: !saving,
            minLines: 3,
            maxLines: 10,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            keyboardType: TextInputType.multiline,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.5,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText:
                  'Combinados, alertas e o que o time precisa saber antes de falar com o lead…',
              hintStyle: theme.textTheme.bodySmall?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w500,
              ),
              counterText: '',
              filled: true,
              fillColor: border.withValues(alpha: isDark ? 0.16 : 0.1),
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: border.withValues(alpha: 0.5)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: border.withValues(alpha: 0.5)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: accent.withValues(alpha: 0.8),
                  width: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _InlineEditBar(
            onCancel: onCancel,
            onSave: onSave,
            saving: saving,
            helper: 'Só o time vê — o cliente nunca recebe esta nota',
          ),
        ] else if (vazio)
          InkWell(
            onTap: canEdit ? onStartEdit : null,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.only(left: 14, top: 2, bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 15, color: secondary),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      canEdit
                          ? 'Sem observação interna. Toque para anotar algo que só o time vê.'
                          : 'Sem observação interna.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  if (canEdit) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.edit_rounded,
                      size: 13,
                      color: accent.withValues(alpha: 0.9),
                    ),
                  ],
                ],
              ),
            ),
          )
        else ...[
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: SelectableText(
                    notes!.trim(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                      fontSize: 14,
                      letterSpacing: -0.1,
                      color: ThemeHelpers.textColor(context),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 17),
            child: Row(
              children: [
                Icon(Icons.visibility_off_rounded, size: 12, color: secondary),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Nota interna — não aparece para o cliente.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Chip que abre o seletor de tags (só gestão vê). Vazado para não competir
/// com as tags reais, que são o conteúdo.
class _ManageTagsChip extends StatelessWidget {
  const _ManageTagsChip({
    required this.hasTags,
    required this.saving,
    required this.onTap,
  });

  final bool hasTags;
  final bool saving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: saving ? null : onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: _kTagsTone.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (saving)
                const SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: _kTagsTone,
                  ),
                )
              else
                const Icon(Icons.add_rounded, size: 13, color: _kTagsTone),
              const SizedBox(width: 5),
              Text(
                hasTags ? 'Gerenciar' : 'Adicionar tag',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: _kTagsTone,
                  fontSize: 11.5,
                  letterSpacing: 0.1,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// TAGS
// =============================================================================

class _PillTag extends StatelessWidget {
  final String label;

  const _PillTag({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = _tagColor(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: isDark ? 0.16 : 0.1),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
              fontSize: 11.5,
              letterSpacing: 0.1,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

Color _tagColor(String tag) {
  const palette = [
    Color(0xFF0EA5E9),
    Color(0xFF14B8A6),
    Color(0xFF6366F1),
    Color(0xFFF97316),
    Color(0xFF22C55E),
    Color(0xFFEC4899),
    Color(0xFFA855F7),
  ];
  if (tag.isEmpty) return palette.first;
  var h = 0;
  for (final c in tag.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return palette[h % palette.length];
}

// =============================================================================
// HORIZONTAL TIMELINE (created → updated → due)
// =============================================================================

/// Linha do tempo **horizontal** ligando os marcos do card:
/// Criada → (Transferido) → Atualizada → (Resultado) → Prazo. Os marcos
/// entre parênteses são CONDICIONAIS e entram ordenados cronologicamente
/// entre os eventos; o Prazo é destino, não evento — fica sempre por
/// último. Com mais de 3 marcos a régua rola na horizontal (larguras
/// fixas) mantendo a linha conectora contínua.
class _HorizontalTimeline extends StatelessWidget {
  final KanbanTask task;
  final _TaskState state;

  const _HorizontalTimeline({required this.task, required this.state});

  /// Largura fixa de cada marco quando a régua entra em modo scroll.
  static const double _kScrollItemWidth = 112;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fmt = DateFormat("d MMM", 'pt_BR');
    final timeFmt = DateFormat("HH:mm");

    // Eventos datados (sort manual estável — List.sort do Dart não é
    // estável; o índice de inserção desempata datas iguais, ex.:
    // Resultado ancorado em updatedAt fica DEPOIS de Atualizada).
    final dated = <(DateTime, _TimelineEntry)>[
      (
        task.createdAt,
        _TimelineEntry(
          icon: LucideIcons.circlePlus,
          accent: const Color(0xFF10B981),
          label: 'Criada',
          value: fmt.format(task.createdAt.toLocal()),
          time: timeFmt.format(task.createdAt.toLocal()),
          helper: _relativeTime(task.createdAt),
        ),
      ),
      (
        task.updatedAt,
        _TimelineEntry(
          icon: LucideIcons.refreshCw,
          accent: const Color(0xFF0EA5E9),
          label: 'Atualizada',
          value: fmt.format(task.updatedAt.toLocal()),
          time: timeFmt.format(task.updatedAt.toLocal()),
          helper: _relativeTime(task.updatedAt),
        ),
      ),
    ];

    final transfer = task.transferDate;
    if (transfer != null) {
      final t = transfer.toLocal();
      dated.add((
        transfer,
        _TimelineEntry(
          icon: LucideIcons.arrowLeftRight,
          accent: const Color(0xFF6366F1),
          label: 'Transferido',
          value: fmt.format(t),
          // Transferência costuma ser só data (00:00) — não mostra hora vazia.
          time: (t.hour == 0 && t.minute == 0) ? '' : timeFmt.format(t),
          helper: _relativeTime(transfer),
        ),
      ));
    }

    if (task.hasClosedResult) {
      final (resultLabel, resultColor, resultIcon) =
          switch (task.normalizedResult) {
        'won' => ('Ganho', const Color(0xFF10B981), LucideIcons.trophy),
        'lost' => ('Perdido', const Color(0xFFEF4444), LucideIcons.trendingDown),
        _ => ('Cancelado', const Color(0xFF64748B), LucideIcons.x),
      };
      // Sem data própria de resultado no payload — updatedAt é a âncora
      // (fechar o card é a última mutação na prática).
      dated.add((
        task.updatedAt,
        _TimelineEntry(
          icon: resultIcon,
          accent: resultColor,
          label: 'Resultado',
          value: resultLabel,
          time: fmt.format(task.updatedAt.toLocal()),
          helper: _relativeTime(task.updatedAt),
          emphasized: true,
        ),
      ));
    }

    final indexed = [for (var i = 0; i < dated.length; i++) (i, dated[i])];
    indexed.sort((a, b) {
      final byDate = a.$2.$1.compareTo(b.$2.$1);
      return byDate != 0 ? byDate : a.$1.compareTo(b.$1);
    });

    final entries = <_TimelineEntry>[
      for (final e in indexed) e.$2.$2,
      if (state.dueDate != null)
        _TimelineEntry(
          icon: state.health == _TaskHealth.overdue
              ? LucideIcons.circleAlert
              : state.health == _TaskHealth.dueToday
                  ? LucideIcons.triangleAlert
                  : LucideIcons.calendarClock,
          accent: state.health == _TaskHealth.ok
              ? const Color(0xFF8B5CF6)
              : state.accent,
          label: 'Prazo',
          value: fmt.format(state.dueDate!.toLocal()),
          time: timeFmt.format(state.dueDate!.toLocal()),
          helper: _TaskDossier._deadlineHelper(state),
          emphasized: state.health != _TaskHealth.ok,
        ),
    ];

    final lineColor = ThemeHelpers.borderColor(context)
        .withValues(alpha: isDark ? 0.6 : 0.45);

    // Com 4-5 marcos, Expanded espreme tudo em tela estreita — régua
    // passa a rolar com larguras fixas, linha conectora contínua.
    final scrollable = entries.length > 3;

    Widget rail({double? itemWidth}) {
      return Stack(
        children: [
          // Linha conectora — sutil e contínua atrás dos pontos.
          Positioned(
            left: 22,
            right: 22,
            top: 17, // alinha com centro vertical do círculo (34/2)
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    lineColor.withValues(alpha: 0.0),
                    lineColor.withValues(alpha: 1.0),
                    lineColor.withValues(alpha: 1.0),
                    lineColor.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.05, 0.95, 1.0],
                ),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in entries)
                if (itemWidth != null)
                  SizedBox(
                    width: itemWidth,
                    child: entry.render(context, theme),
                  )
                else
                  Expanded(child: entry.render(context, theme)),
            ],
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: scrollable
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: SizedBox(
                width: entries.length * _kScrollItemWidth,
                child: rail(itemWidth: _kScrollItemWidth),
              ),
            )
          : rail(),
    );
  }
}

class _TimelineEntry {
  final IconData icon;
  final Color accent;
  final String label;
  final String value;
  final String time;
  final String? helper;
  final bool emphasized;

  const _TimelineEntry({
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
    required this.time,
    this.helper,
    this.emphasized = false,
  });

  Widget render(BuildContext context, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final scaffoldBg = isDark
        ? Theme.of(context).scaffoldBackgroundColor
        : Theme.of(context).cardColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Bullet circular accent — fica POR CIMA da linha conectora. O
        // fundo é o scaffold MESCLADO com um tint da cor do evento
        // (alphaBlend mantém opacidade total, escondendo a linha atrás).
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color.alphaBlend(
              accent.withValues(alpha: isDark ? 0.16 : 0.10),
              scaffoldBg,
            ),
            border: Border.all(
              color: accent.withValues(alpha: emphasized ? 0.85 : 0.45),
              width: emphasized ? 2 : 1.2,
            ),
            boxShadow: emphasized
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.3),
                      blurRadius: 10,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: 15,
            color: accent,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 1.2,
            fontWeight: FontWeight.w800,
            color: secondary,
            fontSize: 9.5,
            height: 1,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.2,
            color: emphasized ? accent : ThemeHelpers.textColor(context),
            height: 1.15,
            fontSize: 13.5,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (time.isNotEmpty)
          Text(
            time,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: secondary,
              fontSize: 10.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        if (helper != null && helper!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            helper!,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: emphasized ? accent : secondary,
              fontSize: 10,
              height: 1.1,
            ),
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

// =============================================================================
// COMMENT BUBBLE / COMPOSER
// =============================================================================

/// Um comentário já posicionado na thread (raiz ou resposta de 1º nível).
class _CommentNode {
  final KanbanTaskComment comment;
  final bool isReply;
  final String? parentAuthor;

  const _CommentNode({
    required this.comment,
    this.isReply = false,
    this.parentAuthor,
  });
}

class _CommentBubble extends StatelessWidget {
  final KanbanTaskComment comment;
  final bool isMe;
  final bool canDelete;
  final VoidCallback onDelete;

  /// Resposta de 1º nível — recua e ganha o cordão de thread à esquerda.
  final bool isReply;
  final String? replyToName;

  /// Nomes conhecidos da empresa: o realce casa o nome INTEIRO depois do `@`.
  final List<String> mentionNames;

  final VoidCallback? onReply;

  const _CommentBubble({
    required this.comment,
    required this.isMe,
    required this.canDelete,
    required this.onDelete,
    this.isReply = false,
    this.replyToName,
    this.mentionNames = const [],
    this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Comunicação fala em azul — vermelho aqui brigava com todo o resto.
    const accent = _kChatTone;
    final secondary = ThemeHelpers.textSecondaryColor(context);

    final bubbleColor = isMe
        ? accent.withValues(alpha: isDark ? 0.16 : 0.08)
        : ThemeHelpers.cardBackgroundColor(context)
            .withValues(alpha: isDark ? 0.5 : 0.7);
    final borderColor = isMe
        ? accent.withValues(alpha: 0.34)
        : ThemeHelpers.borderColor(context).withValues(alpha: 0.45);

    return Padding(
      padding: EdgeInsets.only(top: 6, bottom: 6, left: isReply ? 22 : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cordão da thread: hairline vertical no tom da conversa, nunca um
          // card dentro de card.
          if (isReply) ...[
            Container(
              width: 2,
              height: 34,
              margin: const EdgeInsets.only(right: 8, top: 4),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
          _SolidAvatar(user: comment.user, size: isReply ? 28 : 34),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 12, 12),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
                color: bubbleColor,
                border: Border.all(color: borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          comment.user?.name ??
                              (isMe ? 'Você' : 'Usuário'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.2,
                            height: 1.15,
                            color: isMe
                                ? accent
                                : ThemeHelpers.textColor(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _relativeTime(comment.createdAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: secondary,
                          letterSpacing: 0.2,
                        ),
                      ),
                      // Responder só nas raízes: a thread do web tem UM nível,
                      // e resposta de resposta viraria fio sem fim no celular.
                      if (onReply != null && !isReply)
                        InkWell(
                          onTap: onReply,
                          borderRadius: BorderRadius.circular(999),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.reply_rounded,
                              size: 16,
                              color: accent,
                            ),
                          ),
                        ),
                      if (canDelete)
                        InkWell(
                          onTap: onDelete,
                          borderRadius: BorderRadius.circular(999),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.delete_outline_rounded,
                              size: 16,
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (isReply && (replyToName ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.subdirectory_arrow_right_rounded,
                          size: 13,
                          color: secondary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Em resposta a $replyToName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: secondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 6),
                  SelectableText.rich(
                    TextSpan(
                      children: _mentionSpans(
                        comment.message,
                        mentionNames,
                        theme.textTheme.bodyMedium?.copyWith(
                              height: 1.5,
                              fontSize: 13.5,
                            ) ??
                            const TextStyle(height: 1.5, fontSize: 13.5),
                      ),
                    ),
                  ),
                  if (comment.attachments.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ...comment.attachments.map(
                      (a) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _AttachmentRow(attachment: a),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  final Attachment attachment;

  const _AttachmentRow({required this.attachment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const accent = _kChatTone;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: ThemeHelpers.borderColor(context)
            .withValues(alpha: isDark ? 0.14 : 0.08),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: accent.withValues(alpha: isDark ? 0.18 : 0.12),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.attach_file_rounded, size: 14, color: accent),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  attachment.filename,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _formatFileSize(attachment.size),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.download_rounded, size: 18, color: accent),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Download: ${attachment.url}')),
              );
            },
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// ENVOLVIDOS — pílulas de quem acompanha o card
// =============================================================================

/// Wrap de pílulas (avatar + nome + remover) mais o chip de gerenciar. Wrap,
/// não Row: cinco nomes longos em 320dp precisam quebrar linha, não estourar.
class _InvolvedPeopleStrip extends StatelessWidget {
  const _InvolvedPeopleStrip({
    required this.people,
    required this.canEdit,
    required this.saving,
    required this.onManage,
    required this.onRemove,
  });

  final List<KanbanUser> people;
  final bool canEdit;
  final bool saving;
  final VoidCallback onManage;
  final ValueChanged<KanbanUser> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);

    if (people.isEmpty && !canEdit) {
      return const _MutedHint(
        icon: Icons.groups_outlined,
        text: 'Ninguém além do responsável acompanha este card.',
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final p in people)
          Container(
            padding: EdgeInsets.fromLTRB(4, 4, canEdit ? 2 : 11, 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: _kInvolvedTone.withValues(alpha: isDark ? 0.13 : 0.07),
              border: Border.all(
                color: _kInvolvedTone.withValues(alpha: 0.32),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SolidAvatar(user: p, size: 24),
                const SizedBox(width: 7),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                if (canEdit)
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: saving ? secondary : _kInvolvedTone,
                    ),
                    onPressed: saving ? null : () => onRemove(p),
                    tooltip: 'Remover ${p.name}',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 26, minHeight: 26),
                  ),
              ],
            ),
          ),
        if (canEdit)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: saving ? null : onManage,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: _kInvolvedTone.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (saving)
                      const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _kInvolvedTone,
                        ),
                      )
                    else
                      const Icon(
                        Icons.person_add_alt_1_rounded,
                        size: 14,
                        color: _kInvolvedTone,
                      ),
                    const SizedBox(width: 7),
                    Text(
                      people.isEmpty ? 'Adicionar pessoas' : 'Gerenciar',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                        color: _kInvolvedTone,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// AGENDA DO CARD — criar compromisso + lista ligada ao card
// =============================================================================

/// Convite para marcar: mesma gramática da barra de anexos (faixa larga,
/// hairline, sem sombra) falando em magenta.
class _AgendaCreateBar extends StatelessWidget {
  const _AgendaCreateBar({
    required this.accent,
    required this.busy,
    required this.onTap,
  });

  final Color accent;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: accent.withValues(alpha: isDark ? 0.12 : 0.06),
            border: Border.all(color: accent.withValues(alpha: 0.38)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: busy
                    ? CircularProgressIndicator(strokeWidth: 2.2, color: accent)
                    : Icon(Icons.event_outlined, size: 20, color: accent),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      busy ? 'Agendando…' : 'Marcar compromisso',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Visita, reunião ou retorno — já vinculado a este card.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: secondary,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (!busy) ...[
                const SizedBox(width: 8),
                Icon(Icons.add_rounded, size: 18, color: accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Rótulo de grupo da agenda — barrinha curta + palavra, sem virar um segundo
/// `_SectionHeader` (o cabeçalho da seção já foi dado uma vez).
class _AgendaGroupLabel extends StatelessWidget {
  const _AgendaGroupLabel({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 2,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
                fontSize: 10,
                letterSpacing: 1.4,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Linha de compromisso: bloco de data à esquerda (dia grande + mês), título e
/// horário no meio, status à direita. Passado entra dessaturado.
class _AppointmentTile extends StatelessWidget {
  const _AppointmentTile({
    required this.appointment,
    required this.accent,
    required this.past,
  });

  final Appointment appointment;
  final Color accent;
  final bool past;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final inicio = appointment.startDate.toLocal();
    final fim = appointment.endDate.toLocal();
    final cancelado = appointment.status == AppointmentStatus.cancelled;
    final tone = cancelado ? _kDangerRed : accent;

    final convidados = appointment.invites?.length ?? 0;
    final meta = <String>[
      '${DateFormat('HH:mm').format(inicio)}–${DateFormat('HH:mm').format(fim)}',
      appointment.type.label,
      if (convidados > 0)
        '$convidados ${convidados == 1 ? 'convidado' : 'convidados'}',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              color: tone.withValues(alpha: isDark ? 0.16 : 0.09),
              border: Border.all(color: tone.withValues(alpha: 0.3)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('dd').format(inicio),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: tone,
                    height: 1,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('MMM', 'pt_BR').format(inicio).toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: tone,
                    fontSize: 9.5,
                    letterSpacing: 0.8,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  appointment.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    height: 1.25,
                    color: past ? secondary : null,
                    decoration:
                        cancelado ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  meta,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    height: 1.3,
                  ),
                ),
                if ((appointment.location ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.place_outlined, size: 12, color: secondary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          appointment.location!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: secondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: tone.withValues(alpha: isDark ? 0.16 : 0.09),
              border: Border.all(color: tone.withValues(alpha: 0.3)),
            ),
            child: Text(
              appointment.status.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: tone,
                fontWeight: FontWeight.w800,
                fontSize: 10,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// TRANSFERÊNCIAS — histórico de troca de funil
// =============================================================================

/// Atalho para transferir a partir da própria seção de rotas — a pill do hero
/// continua sendo o caminho rápido; esta é a porta de quem já está lendo o
/// histórico e decide mudar o card de funil ali mesmo.
class _TransferActionBar extends StatelessWidget {
  const _TransferActionBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    const tone = _kRouteTone;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: tone.withValues(alpha: isDark ? 0.12 : 0.06),
            border: Border.all(color: tone.withValues(alpha: 0.38)),
          ),
          child: Row(
            children: [
              const Icon(Icons.alt_route_rounded, size: 20, color: tone),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Transferir para outro funil',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Cria a cópia no destino e registra a rota aqui.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: secondary,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_rounded, size: 17, color: tone),
            ],
          ),
        ),
      ),
    );
  }
}

/// Uma transferência: origem → destino, quem levou e para quem ficou.
/// Trilha (dot + fio), nunca card — é a mesma gramática da jornada ao lado.
class _TransferRow extends StatelessWidget {
  const _TransferRow({required this.entry, required this.isLast});

  final KanbanTransferHistoryEntry entry;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    const tone = _kRouteTone;

    final quando = entry.transferredAt == null
        ? null
        : DateFormat('dd/MM/yy HH:mm').format(entry.transferredAt!.toLocal());

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 4),
                decoration: const BoxDecoration(
                  color: tone,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.only(top: 4),
                    color: ThemeHelpers.borderColor(context)
                        .withValues(alpha: 0.45),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (quando != null)
                    Text(
                      quando,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: secondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  const SizedBox(height: 4),
                  // Origem → destino em Wrap: nome de funil longo quebra para
                  // a linha de baixo em vez de estourar a largura.
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _TransferFunnelChip(
                        label: entry.fromProjectName ?? 'Funil de origem',
                        tone: secondary,
                      ),
                      Icon(Icons.arrow_forward_rounded, size: 13, color: tone),
                      _TransferFunnelChip(
                        label: entry.toProjectName ?? 'Funil de destino',
                        tone: tone,
                        strong: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if ((entry.transferredByName ?? '').isNotEmpty)
                    _TransferMetaLine(
                      icon: Icons.swap_horiz_rounded,
                      text: 'Transferido por ${entry.transferredByName}',
                    ),
                  if ((entry.assignedToName ?? '').isNotEmpty)
                    _TransferMetaLine(
                      icon: Icons.person_outline_rounded,
                      text: 'Ficou com ${entry.assignedToName}',
                    ),
                  if ((entry.notes ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: tone.withValues(alpha: isDark ? 0.1 : 0.05),
                        border: Border(
                          left: BorderSide(color: tone, width: 2.5),
                        ),
                      ),
                      child: Text(
                        entry.notes!.trim(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransferFunnelChip extends StatelessWidget {
  const _TransferFunnelChip({
    required this.label,
    required this.tone,
    this.strong = false,
  });

  final String label;
  final Color tone;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 190),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: tone.withValues(alpha: isDark ? 0.16 : 0.09),
          border: Border.all(color: tone.withValues(alpha: strong ? 0.4 : 0.28)),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: tone,
            fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
            fontSize: 11,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

class _TransferMetaLine extends StatelessWidget {
  const _TransferMetaLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 13, color: secondary),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w600,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// ANEXOS DO CARD — barra de envio + linha de arquivo
// =============================================================================

/// Convite para anexar: uma faixa tracejada larga (alvo de toque generoso),
/// nunca um card com sombra. Some do caminho quando o limite estoura.
class _AttachmentUploadBar extends StatelessWidget {
  const _AttachmentUploadBar({
    required this.accent,
    required this.uploading,
    required this.full,
    required this.onPick,
  });

  final Color accent;
  final bool uploading;
  final bool full;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final bloqueado = full || uploading;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: bloqueado ? null : onPick,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: bloqueado
                ? Colors.transparent
                : accent.withValues(alpha: isDark ? 0.12 : 0.06),
            border: Border.all(
              color: bloqueado
                  ? ThemeHelpers.borderColor(context).withValues(alpha: 0.5)
                  : accent.withValues(alpha: 0.38),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: uploading
                    ? CircularProgressIndicator(strokeWidth: 2.2, color: accent)
                    : Icon(
                        full
                            ? Icons.block_rounded
                            : Icons.cloud_upload_outlined,
                        size: 20,
                        color: full ? secondary : accent,
                      ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      uploading
                          ? 'Enviando…'
                          : full
                              ? 'Limite de ${KanbanService.maxTaskAttachments} anexos atingido'
                              : 'Anexar arquivos ao card',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        letterSpacing: -0.1,
                        color: full ? secondary : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      full
                          ? 'Remova um anexo antes de enviar outro.'
                          : 'Até ${KanbanService.maxTaskAttachments} arquivos, 200 MB cada.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: secondary,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (!bloqueado) ...[
                const SizedBox(width: 8),
                Icon(Icons.add_rounded, size: 18, color: accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Linha de anexo do card: miniatura/ícone + nome + peso/data + ações.
/// Flush — a separação entre linhas é a hairline da lista, não uma caixa.
class _TaskAttachmentTile extends StatelessWidget {
  const _TaskAttachmentTile({
    required this.file,
    required this.accent,
    required this.canDelete,
    required this.deleting,
    required this.onOpen,
    required this.onCopy,
    required this.onDelete,
  });

  final Attachment file;
  final Color accent;
  final bool canDelete;
  final bool deleting;
  final VoidCallback onOpen;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  IconData get _icon {
    final mime = file.mimeType.toLowerCase();
    final nome = file.filename.toLowerCase();
    if (mime.startsWith('image/')) return Icons.image_outlined;
    if (mime.startsWith('video/')) return Icons.movie_outlined;
    if (mime.startsWith('audio/')) return Icons.audiotrack_outlined;
    if (mime.contains('pdf') || nome.endsWith('.pdf')) {
      return Icons.picture_as_pdf_outlined;
    }
    if (nome.endsWith('.xlsx') || nome.endsWith('.xls') || nome.endsWith('.csv')) {
      return Icons.table_chart_outlined;
    }
    if (nome.endsWith('.doc') || nome.endsWith('.docx')) {
      return Icons.description_outlined;
    }
    if (nome.endsWith('.zip') || nome.endsWith('.rar')) {
      return Icons.folder_zip_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);

    final meta = <String>[
      if (file.size > 0) _formatFileSize(file.size),
      if (file.uploadedAt != null)
        DateFormat('dd/MM/yy HH:mm').format(file.uploadedAt!.toLocal()),
    ].join(' · ');

    return InkWell(
      onTap: deleting ? null : onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                color: accent.withValues(alpha: isDark ? 0.18 : 0.1),
              ),
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              child: file.isImage && file.bestPreviewUrl.isNotEmpty
                  ? Image.network(
                      file.bestPreviewUrl,
                      fit: BoxFit.cover,
                      width: 40,
                      height: 40,
                      errorBuilder: (_, _, _) =>
                          Icon(_icon, size: 18, color: accent),
                    )
                  : Icon(_icon, size: 18, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    file.filename,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      height: 1.25,
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: secondary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (deleting)
              const SizedBox(
                width: 34,
                height: 34,
                child: Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else ...[
              IconButton(
                icon: Icon(Icons.open_in_new_rounded, size: 17, color: accent),
                onPressed: onOpen,
                tooltip: 'Abrir',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              ),
              IconButton(
                icon: Icon(Icons.link_rounded, size: 17, color: secondary),
                onPressed: onCopy,
                tooltip: 'Copiar link',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              ),
              if (canDelete)
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 17,
                    color: _kDangerRed,
                  ),
                  onPressed: onDelete,
                  tooltip: 'Remover',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 34, minHeight: 34),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CommentComposer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback? onSubmit;
  final bool isSubmitting;
  final int length;
  final int maxLength;
  final List<File> files;
  final VoidCallback onPickFiles;
  final ValueChanged<int> onRemoveFile;
  final Color accent;

  /// Sugestões abertas pelo `@` (vazio = painel fechado).
  final List<KanbanUser> mentionSuggestions;
  final bool loadingMentions;
  final ValueChanged<KanbanUser> onPickMention;

  /// Comentário sendo respondido — vira faixa acima do campo.
  final KanbanTaskComment? replyTo;
  final VoidCallback onCancelReply;

  const _CommentComposer({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.isSubmitting,
    required this.length,
    required this.maxLength,
    required this.files,
    required this.onPickFiles,
    required this.onRemoveFile,
    required this.accent,
    this.mentionSuggestions = const [],
    this.loadingMentions = false,
    required this.onPickMention,
    this.replyTo,
    required this.onCancelReply,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mq = MediaQuery.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final focused = focusNode.hasFocus;

    return Container(
      padding: EdgeInsets.fromLTRB(14, 10, 14, 12 + mq.padding.bottom),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          top: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // MENÇÕES — painel ACIMA do campo (o teclado sobe por baixo, então
          // uma lista flutuante embaixo ficaria escondida). Teto de 168px com
          // rolagem própria: em 320dp o composer não cresce sem controle.
          if (mentionSuggestions.isNotEmpty || loadingMentions) ...[
            Container(
              constraints: const BoxConstraints(maxHeight: 168),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: _kMentionTone.withValues(alpha: isDark ? 0.12 : 0.06),
                border: Border.all(
                  color: _kMentionTone.withValues(alpha: 0.32),
                ),
              ),
              child: loadingMentions
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _kMentionTone,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      physics: const ClampingScrollPhysics(),
                      itemCount: mentionSuggestions.length,
                      itemBuilder: (context, i) {
                        final u = mentionSuggestions[i];
                        return InkWell(
                          onTap: () => onPickMention(u),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            child: Row(
                              children: [
                                _SolidAvatar(user: u, size: 26),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        u.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                      if (u.email.isNotEmpty)
                                        Text(
                                          u.email,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            color: secondary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.alternate_email_rounded,
                                  size: 15,
                                  color: _kMentionTone,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
          // RESPOSTA — faixa com o trecho citado e a saída explícita.
          if (replyTo != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: accent.withValues(alpha: isDark ? 0.14 : 0.07),
                border: Border(
                  left: BorderSide(color: accent, width: 3),
                  top: BorderSide(color: accent.withValues(alpha: 0.24)),
                  right: BorderSide(color: accent.withValues(alpha: 0.24)),
                  bottom: BorderSide(color: accent.withValues(alpha: 0.24)),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.reply_rounded, size: 15, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Respondendo ${replyTo!.user?.name ?? 'comentário'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: accent,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          replyTo!.message,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: secondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 16, color: secondary),
                    onPressed: onCancelReply,
                    tooltip: 'Cancelar resposta',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (files.isNotEmpty) ...[
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: files.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, i) {
                  final f = files[i];
                  final name = f.path.split(RegExp(r'[\\/]')).last;
                  return Container(
                    padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: accent.withValues(alpha: isDark ? 0.14 : 0.08),
                      border:
                          Border.all(color: accent.withValues(alpha: 0.28)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.attach_file_rounded, size: 14, color: accent),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 140),
                          child: Text(
                            name,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: accent,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close_rounded,
                              size: 14, color: accent),
                          onPressed: () => onRemoveFile(i),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 26,
                            minHeight: 26,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: ThemeHelpers.cardBackgroundColor(context)
                  .withValues(alpha: isDark ? 0.45 : 0.65),
              border: Border.all(
                color: focused
                    ? accent.withValues(alpha: 0.6)
                    : ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
                width: focused ? 1.4 : 1,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  icon: Icon(Icons.attach_file_rounded,
                      color: accent, size: 20),
                  onPressed: onPickFiles,
                  tooltip: 'Anexar arquivos',
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: maxLength,
                    // Observação é frase, não etiqueta: o teclado abre em
                    // maiúscula e recapitaliza depois de cada ponto.
                    textCapitalization: TextCapitalization.sentences,
                    keyboardType: TextInputType.multiline,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Escreva para o time… use @ para marcar',
                      hintStyle: theme.textTheme.bodyMedium?.copyWith(
                        color: secondary,
                        fontWeight: FontWeight.w500,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      counterText: '',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                // Saída óbvia do "modo digitação": só existe com o teclado
                // aberto, discreto, à esquerda do enviar. Layout de teclado
                // fechado fica exatamente como era.
                if (mq.viewInsets.bottom > 0)
                  IconButton(
                    icon: Icon(
                      Icons.keyboard_hide_rounded,
                      size: 18,
                      color: secondary,
                    ),
                    onPressed: () {
                      focusNode.unfocus();
                      FocusScope.of(context).unfocus();
                    },
                    tooltip: 'Fechar teclado',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 34,
                      minHeight: 34,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onSubmit,
                      borderRadius: BorderRadius.circular(12),
                      child: Ink(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: onSubmit == null
                              ? ThemeHelpers.borderColor(context)
                                  .withValues(alpha: 0.3)
                              : accent,
                        ),
                        child: SizedBox(
                          width: 38,
                          height: 38,
                          child: Center(
                            child: isSubmitting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    Icons.send_rounded,
                                    size: 18,
                                    color: onSubmit == null
                                        ? secondary
                                        : Colors.white,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 12, color: secondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Notas, links e arquivos ficam visíveis ao time todo.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '$length / $maxLength',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: length > maxLength * 0.9
                        ? theme.colorScheme.error
                        : secondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// HISTORY ROW (timeline minimal)
// =============================================================================

class _HistoryRow extends StatelessWidget {
  final HistoryEntry entry;
  final bool isLast;

  const _HistoryRow({required this.entry, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final action = _ActionStyle.fromAction(entry.action);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: action.color.withValues(alpha: isDark ? 0.22 : 0.12),
                    border: Border.all(
                      color: action.color.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Icon(action.icon, size: 13, color: action.color),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: ThemeHelpers.borderColor(context)
                          .withValues(alpha: isDark ? 0.4 : 0.5),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.4,
                        fontSize: 13.5,
                        color: ThemeHelpers.textColor(context),
                      ),
                      children: [
                        TextSpan(
                          text: entry.user?.name ?? 'Sistema',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        TextSpan(text: ' ${action.label}'),
                        if (entry.fieldLabel != null)
                          TextSpan(
                            text: ' · ${entry.fieldLabel}',
                            style: TextStyle(
                              color: secondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (entry.fromColumn != null && entry.toColumn != null) ...[
                    const SizedBox(height: 8),
                    _ColumnTransitionRow(
                      from: entry.fromColumn!,
                      to: entry.toColumn!,
                    ),
                  ] else if (entry.oldValue != null ||
                      entry.newValue != null) ...[
                    const SizedBox(height: 8),
                    _ValueDelta(
                      oldValue: entry.oldValue,
                      newValue: entry.newValue,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded, size: 11, color: secondary),
                      const SizedBox(width: 4),
                      Text(
                        _relativeTime(entry.createdAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: secondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ColumnTransitionRow extends StatelessWidget {
  final HistoryColumn from;
  final HistoryColumn to;

  const _ColumnTransitionRow({required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(child: _ColumnPill(column: from)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Icon(
            Icons.east_rounded,
            size: 14,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
        ),
        Flexible(child: _ColumnPill(column: to)),
      ],
    );
  }
}

class _ColumnPill extends StatelessWidget {
  final HistoryColumn column;

  const _ColumnPill({required this.column});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color color;
    try {
      color = Color(int.parse(column.color.replaceFirst('#', '0xFF')));
    } catch (_) {
      color = _kanbanAccent(context);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Text(
        column.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

class _ValueDelta extends StatelessWidget {
  final String? oldValue;
  final String? newValue;

  const _ValueDelta({required this.oldValue, required this.newValue});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (oldValue != null && oldValue!.isNotEmpty)
          _DeltaRow(
            color: const Color(0xFFEF4444),
            icon: Icons.remove_circle_outline_rounded,
            label: 'antes',
            value: oldValue!,
            theme: theme,
          ),
        if (oldValue != null && newValue != null) const SizedBox(height: 4),
        if (newValue != null && newValue!.isNotEmpty)
          _DeltaRow(
            color: const Color(0xFF10B981),
            icon: Icons.add_circle_outline_rounded,
            label: 'agora',
            value: newValue!,
            theme: theme,
          ),
      ],
    );
  }
}

class _DeltaRow extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final String value;
  final ThemeData theme;

  const _DeltaRow({
    required this.color,
    required this.icon,
    required this.label,
    required this.value,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.4,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionStyle {
  final String label;
  final IconData icon;
  final Color color;

  const _ActionStyle._(this.label, this.icon, this.color);

  static _ActionStyle fromAction(String action) {
    switch (action) {
      case 'created':
        return const _ActionStyle._(
          'criou a tarefa',
          Icons.add_circle_rounded,
          Color(0xFF10B981),
        );
      case 'moved':
        return const _ActionStyle._(
          'moveu',
          Icons.drag_handle_rounded,
          Color(0xFF0891B2),
        );
      case 'assigned':
        return const _ActionStyle._(
          'atribuiu responsável',
          Icons.person_add_alt_1_rounded,
          Color(0xFF8B5CF6),
        );
      case 'unassigned':
        return const _ActionStyle._(
          'removeu responsável',
          Icons.person_remove_rounded,
          Color(0xFF94A3B8),
        );
      case 'priority_changed':
        return const _ActionStyle._(
          'alterou a prioridade',
          Icons.flag_rounded,
          Color(0xFFF59E0B),
        );
      case 'due_date_changed':
        return const _ActionStyle._(
          'alterou o prazo',
          Icons.event_rounded,
          Color(0xFF06B6D4),
        );
      case 'description_changed':
        return const _ActionStyle._(
          'alterou a descrição',
          Icons.notes_rounded,
          Color(0xFF6366F1),
        );
      case 'title_changed':
        return const _ActionStyle._(
          'alterou o título',
          Icons.title_rounded,
          Color(0xFF6366F1),
        );
      case 'tags_changed':
        return const _ActionStyle._(
          'alterou as tags',
          Icons.local_offer_rounded,
          Color(0xFFEC4899),
        );
      case 'project_changed':
        return const _ActionStyle._(
          'alterou o funil',
          Icons.account_tree_rounded,
          Color(0xFF14B8A6),
        );
      case 'completed':
        return const _ActionStyle._(
          'concluiu a tarefa',
          Icons.check_circle_rounded,
          Color(0xFF10B981),
        );
      case 'reopened':
        return const _ActionStyle._(
          'reabriu a tarefa',
          Icons.restart_alt_rounded,
          Color(0xFFF97316),
        );
      case 'cadence_sent':
        return const _ActionStyle._(
          'enviou cadência WhatsApp',
          Icons.schedule_send_rounded,
          Color(0xFF128C7E),
        );
      case 'cadence_skipped':
        return const _ActionStyle._(
          'pulou a cadência (sem contato)',
          Icons.skip_next_rounded,
          Color(0xFF94A3B8),
        );
      case 'cadence_failed':
        return const _ActionStyle._(
          'falha ao enviar cadência',
          Icons.error_outline_rounded,
          Color(0xFFEF4444),
        );
      case 'updated':
      default:
        return _ActionStyle._(
          action.isEmpty ? 'atualizou' : 'atualizou ($action)',
          Icons.edit_rounded,
          const Color(0xFF94A3B8),
        );
    }
  }
}

// =============================================================================
// SHARED: loading / error / empty
// =============================================================================

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    final accent = _kanbanAccent(context);
    return Center(
      child: SizedBox(
        width: 32,
        height: 32,
        child: CircularProgressIndicator(strokeWidth: 2.6, color: accent),
      ),
    );
  }
}

/// Erro de uma aba do card. Delega ao estado de erro padrão do app: o
/// [statusCode] é o que permite dizer a causa REAL — sem ele, "sem
/// permissão para ver o histórico" e "servidor fora do ar" viravam a mesma
/// frase genérica.
class _ErrorView extends StatelessWidget {
  final String? message;
  final int statusCode;
  final Future<void> Function() onRetry;

  const _ErrorView({
    required this.message,
    required this.onRetry,
    this.statusCode = 0,
  });

  @override
  Widget build(BuildContext context) {
    return AppErrorState.fromApi(
      message: message,
      statusCode: statusCode,
      onRetry: onRetry,
      dense: true,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Estado vazio é NEUTRO — vermelho aqui lia como erro.
    const accent = _kAuditTone;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.1),
                border: Border.all(color: accent.withValues(alpha: 0.32)),
              ),
              child: Icon(icon, size: 28, color: accent),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// UTILS
// =============================================================================

Color _kanbanAccent(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
}

/// Quebra o texto do comentário em trechos normais + menções destacadas.
///
/// A menção vale quando o `@` abre palavra (início da linha ou depois de
/// espaço/parêntese) — assim `contato@empresa.com` continua texto comum. Se o
/// que vem depois casa com o nome de alguém da empresa, o nome INTEIRO entra
/// no destaque; senão só a primeira palavra.
List<TextSpan> _mentionSpans(
  String message,
  List<String> names,
  TextStyle base,
) {
  final mentionStyle = base.copyWith(
    color: _kMentionTone,
    fontWeight: FontWeight.w800,
  );
  final sorted = [...names]..sort((a, b) => b.length.compareTo(a.length));
  final lower = message.toLowerCase();
  final spans = <TextSpan>[];
  final buffer = StringBuffer();

  void flush() {
    if (buffer.isEmpty) return;
    spans.add(TextSpan(text: buffer.toString(), style: base));
    buffer.clear();
  }

  var i = 0;
  while (i < message.length) {
    final char = message[i];
    final opensWord =
        i == 0 || _mentionOpeners.contains(message[i - 1]);
    if (char != '@' || !opensWord) {
      buffer.write(char);
      i++;
      continue;
    }

    String? hit;
    for (final name in sorted) {
      if (name.trim().isEmpty) continue;
      final n = name.toLowerCase();
      if (lower.startsWith(n, i + 1)) {
        hit = message.substring(i + 1, i + 1 + name.length);
        break;
      }
    }
    hit ??= _firstMentionWord(message.substring(i + 1));
    if (hit.isEmpty) {
      buffer.write(char);
      i++;
      continue;
    }
    flush();
    spans.add(TextSpan(text: '@$hit', style: mentionStyle));
    i += hit.length + 1;
  }
  flush();
  return spans.isEmpty ? [TextSpan(text: message, style: base)] : spans;
}

const Set<String> _mentionOpeners = {' ', '\n', '\t', '(', '[', '-', ','};

final RegExp _mentionWordRe = RegExp(r'^[A-Za-zÀ-ÿ0-9_.]+');

String _firstMentionWord(String rest) =>
    _mentionWordRe.firstMatch(rest)?.group(0) ?? '';

String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _relativeTime(DateTime date, {String prefix = ''}) {
  final now = DateTime.now();
  final diff = now.difference(date);
  String value;
  if (diff.inSeconds < 60) {
    value = 'agora';
  } else if (diff.inMinutes < 60) {
    value = '${diff.inMinutes} min';
  } else if (diff.inHours < 24) {
    value = '${diff.inHours} h';
  } else if (diff.inDays < 7) {
    value = '${diff.inDays} d';
  } else {
    value = DateFormat('d MMM', 'pt_BR').format(date.toLocal());
  }
  return prefix.isEmpty ? value : '$prefix $value';
}
