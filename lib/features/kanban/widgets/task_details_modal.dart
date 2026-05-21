import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/secure_storage_service.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/kanban_analytics_service.dart';
import '../../../shared/utils/jwt_utils.dart';
import '../models/kanban_models.dart';
import '../services/kanban_service.dart';
import '../controllers/kanban_controller.dart';
import 'subtask_manager.dart';
import 'mark_task_result_sheet.dart';
import 'transfer_task_sheet.dart';

/// Modal completo de detalhes do card.
///
/// Reestilizado num conceito **editorial**: hierarquia tipográfica forte, sem
/// sombras pesadas nem gradientes coloridos no fundo dos blocos. Estados (em
/// dia, vence hoje, atrasada, concluída) são sinalizados por uma "stripe"
/// finíssima no topo do header e pelas pílulas de meta-status. A intenção é
/// que o modal pareça mais um documento estruturado do que uma sopa de cards
/// coloridos — mais legível no modo claro e ainda elegante no escuro.
class TaskDetailsModal extends StatefulWidget {
  final KanbanTask task;

  const TaskDetailsModal({super.key, required this.task});

  @override
  State<TaskDetailsModal> createState() => _TaskDetailsModalState();
}

class _TaskDetailsModalState extends State<TaskDetailsModal>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final KanbanService _kanbanService = KanbanService.instance;

  // Comentários
  List<KanbanTaskComment> _comments = [];
  bool _loadingComments = false;
  String? _commentsError;
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocus = FocusNode();
  final List<File> _selectedFiles = [];
  bool _submittingComment = false;
  int _commentLength = 0;

  // Histórico
  List<HistoryEntry> _history = [];
  bool _loadingHistory = false;
  String? _historyError;

  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _tabController.addListener(_onTabChanged);
    _commentController.addListener(() {
      if (mounted) setState(() => _commentLength = _commentController.text.length);
    });
    _commentFocus.addListener(() => setState(() {}));
    _loadCurrentUserId();
    _loadComments();
  }

  void _onTabChanged() {
    if (!mounted) return;
    setState(() {});
    final i = _tabController.index;
    if (i == 1 && !_didLoadJourney) {
      _loadJourney();
    }
    if (i == 4 && !_didLoadFiles) {
      _loadTaskFiles();
    }
    if (i == 5 && _canViewTaskAnalytics && !_didLoadMetrics) {
      _loadTaskMetrics();
    }
    if (i == 6 && _history.isEmpty && !_loadingHistory) {
      _loadHistory();
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _commentController.dispose();
    _commentFocus.dispose();
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
          _commentsError = response.message ?? 'Erro ao carregar comentários';
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
          _historyError = response.message ?? 'Erro ao carregar histórico';
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
      final response = await _kanbanService.createComment(
        widget.task.id,
        message,
        _selectedFiles.isNotEmpty ? _selectedFiles : null,
      );
      if (!mounted) return;
      if (response.success && response.data != null) {
        setState(() {
          _comments.add(response.data!);
          _commentController.clear();
          _selectedFiles.clear();
          _submittingComment = false;
        });
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
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
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
        setState(() => _comments.removeWhere((c) => c.id == commentId));
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
    final board = c.board;
    if (board != null) {
      for (final t in board.tasks) {
        if (t.id == id) return t;
      }
    }
    return widget.task;
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

  void _openTransferSheet(BuildContext context, KanbanTask task) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (ctx) => TransferTaskSheet(task: task),
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return ListenableBuilder(
      listenable: KanbanController.instance,
      builder: (context, _) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final task = _mergedTask(KanbanController.instance);
        final state = _TaskState.from(task);
        final perms = KanbanController.instance.permissions;
        final canMark =
            perms?.canMarkResult ?? perms?.canEditTasks ?? false;
        final canXfer =
            perms?.canTransfer ?? perms?.canEditTasks ?? false;

        return Material(
          color: Colors.transparent,
          child: Container(
            height: mq.size.height * 0.94,
            decoration: BoxDecoration(
              color: ThemeHelpers.cardBackgroundColor(context),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
              border: Border.all(
                color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _buildDragHandle(context, isDark),
                _StateRibbon(state: state),
                _TaskHeroHeader(
                  task: task,
                  state: state,
                  canMarkResult: canMark,
                  canTransfer: canXfer,
                  onMarkWon: () =>
                      _openMarkResultSheet(context, task, quickEntry: 'won'),
                  onMarkLost: () =>
                      _openMarkResultSheet(context, task, quickEntry: 'lost'),
                  onTransfer: () => _openTransferSheet(context, task),
                  onOpenResult: () =>
                      _openMarkResultSheet(context, task),
                  onClose: () => Navigator.of(context).pop(),
                  onCopyId: () {
                    Clipboard.setData(ClipboardData(text: task.id));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('ID da tarefa copiado'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                _MinimalTabBar(
                  controller: _tabController,
                  tabs: [
                    const _TabItem(icon: Icons.article_outlined, label: 'Detalhes'),
                    const _TabItem(
                      icon: Icons.signpost_outlined,
                      label: 'Jornada',
                    ),
                    const _TabItem(
                      icon: Icons.checklist_rounded,
                      label: 'Tarefas',
                    ),
                    _TabItem(
                      icon: Icons.forum_outlined,
                      label: 'Conversas',
                      badge: _comments.length,
                    ),
                    _TabItem(
                      icon: Icons.attach_file_rounded,
                      label: 'Arquivos',
                      badge: _taskFiles.isNotEmpty ? _taskFiles.length : null,
                    ),
                    const _TabItem(
                      icon: Icons.insights_rounded,
                      label: 'Métricas',
                    ),
                    _TabItem(
                      icon: Icons.history_rounded,
                      label: 'Histórico',
                      badge: (_history.isNotEmpty || _loadingHistory)
                          ? _history.length
                          : null,
                    ),
                  ],
                ),
                Expanded(
                  child: TabBarView(
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
                      _buildMetricsTab(context, theme),
                      _buildHistoryTab(context, theme),
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

  Widget _buildDragHandle(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: ThemeHelpers.textSecondaryColor(context)
                .withValues(alpha: isDark ? 0.32 : 0.22),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
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
    final hasDescription =
        task.description != null && task.description!.trim().isNotEmpty;
    final tags = task.displayTags;
    final hasTags = tags != null && tags.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. DESCRIÇÃO em destaque editorial
          _EditorialDescription(
            text: hasDescription ? task.description!.trim() : null,
          ),
          const SizedBox(height: 26),

          // 2. BENTO GRID — info chave em 2×2 com cores próprias
          _BentoInfoGrid(task: task, state: state),
          const SizedBox(height: 26),

          // 3. EQUIPE
          _SectionHeader(
            overline: 'Equipe',
            title: 'Pessoas envolvidas',
          ),
          const SizedBox(height: 10),
          _PeopleStrip(task: task),

          // 4. TAGS (se houver)
          if (hasTags) ...[
            const SizedBox(height: 26),
            _SectionHeader(
              overline: 'Categorias',
              title: 'Tags',
              trailing: '${tags.length}',
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final t in tags) _PillTag(label: t)],
            ),
          ],
          const SizedBox(height: 26),

          // 5. TIMELINE HORIZONTAL
          _SectionHeader(
            overline: 'Auditoria',
            title: 'Linha do tempo',
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
    final accent = _kanbanAccent(context);
    return Column(
      children: [
        Expanded(
          child: _loadingComments
              ? const _LoadingView()
              : _commentsError != null
                  ? _ErrorView(
                      message: _commentsError!,
                      onRetry: _loadComments,
                    )
                  : _comments.isEmpty
                      ? const _EmptyState(
                          icon: Icons.forum_outlined,
                          title: 'Sem conversas por aqui',
                          subtitle:
                              'Seja o primeiro a comentar e deixar contexto para o time.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                          physics: const BouncingScrollPhysics(),
                          itemCount: _comments.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 4),
                          itemBuilder: (context, i) {
                            final c = _comments[i];
                            return _CommentBubble(
                              comment: c,
                              isMe: c.userId == _currentUserId,
                              canDelete: _canDeleteComment(c),
                              onDelete: () => _deleteComment(c.id),
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
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB: HISTORY
  // ---------------------------------------------------------------------------

  Widget _buildHistoryTab(BuildContext context, ThemeData theme) {
    if (_loadingHistory) return const _LoadingView();
    if (_historyError != null) {
      return _ErrorView(message: _historyError!, onRetry: _loadHistory);
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
        _journeyError = r.message ?? 'Erro ao carregar jornada';
        _loadingJourney = false;
        _didLoadJourney = true;
      });
    }
  }

  Widget _buildJourneyTab(BuildContext context, ThemeData theme) {
    if (_loadingJourney) return const _LoadingView();
    if (_journeyError != null) {
      return _ErrorView(message: _journeyError!, onRetry: _loadJourney);
    }
    if (_journey.isEmpty) {
      return const _EmptyState(
        icon: Icons.signpost_outlined,
        title: 'Sem eventos de jornada',
        subtitle:
            'Eventos de atribuição, colunas, transferências e resultado aparecem aqui.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      physics: const BouncingScrollPhysics(),
      itemCount: _journey.length,
      itemBuilder: (context, i) {
        final e = _journey[i];
        final title = e['title']?.toString() ?? '';
        final subtitle = e['subtitle']?.toString();
        final at = e['at']?.toString() ?? '';
        final tone = e['tone']?.toString();
        Color dot = theme.colorScheme.primary;
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
      },
    );
  }

  // ---------------------------------------------------------------------------
  // TAB: ARQUIVOS (GET /kanban/tasks/:id/attachments)
  // ---------------------------------------------------------------------------

  List<Map<String, dynamic>> _taskFiles = [];
  bool _loadingFiles = false;
  String? _filesError;
  bool _didLoadFiles = false;

  Future<void> _loadTaskFiles() async {
    setState(() {
      _loadingFiles = true;
      _filesError = null;
    });
    final r = await _kanbanService.getTaskAttachments(widget.task.id);
    if (!mounted) return;
    if (r.success && r.data != null) {
      setState(() {
        _taskFiles = r.data!;
        _loadingFiles = false;
        _didLoadFiles = true;
      });
    } else {
      setState(() {
        _filesError = r.message ?? 'Erro ao listar arquivos';
        _loadingFiles = false;
        _didLoadFiles = true;
      });
    }
  }

  Widget _buildFilesTab(BuildContext context, ThemeData theme) {
    if (_loadingFiles) return const _LoadingView();
    if (_filesError != null) {
      return _ErrorView(message: _filesError!, onRetry: _loadTaskFiles);
    }
    if (_taskFiles.isEmpty) {
      return const _EmptyState(
        icon: Icons.folder_open_rounded,
        title: 'Sem anexos no card',
        subtitle:
            'Arquivos enviados diretamente na tarefa (fora dos comentários) aparecem aqui.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      physics: const BouncingScrollPhysics(),
      itemCount: _taskFiles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final f = _taskFiles[i];
        final name =
            f['name']?.toString() ?? f['filename']?.toString() ?? 'Arquivo';
        final url = f['url']?.toString() ?? '';
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          tileColor: ThemeHelpers.cardBackgroundColor(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.35),
            ),
          ),
          leading: const Icon(Icons.attach_file_rounded),
          title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: url.isNotEmpty ? Text(url, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
          onTap: url.isEmpty
              ? null
              : () {
                  Clipboard.setData(ClipboardData(text: url));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Link copiado')),
                  );
                },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // TAB: MÉTRICAS (GET /kanban/analytics/tasks/:id/metrics)
  // ---------------------------------------------------------------------------

  Map<String, dynamic>? _taskMetrics;
  bool _loadingMetrics = false;
  String? _metricsError;
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
        _metricsError = r.message ?? 'Erro ao carregar métricas';
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
      return _ErrorView(message: _metricsError!, onRetry: _loadTaskMetrics);
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
          Text(
            'Resumo analítico',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
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
class _StateRibbon extends StatelessWidget {
  final _TaskState state;

  const _StateRibbon({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 3,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            state.accent.withValues(alpha: 0.0),
            state.accent.withValues(alpha: 0.95),
            state.accent.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
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
  final VoidCallback onClose;
  final VoidCallback onCopyId;
  final VoidCallback onMarkWon;
  final VoidCallback onMarkLost;
  final VoidCallback onTransfer;
  final VoidCallback onOpenResult;

  const _TaskHeroHeader({
    required this.task,
    required this.state,
    required this.canMarkResult,
    required this.canTransfer,
    required this.onClose,
    required this.onCopyId,
    required this.onMarkWon,
    required this.onMarkLost,
    required this.onTransfer,
    required this.onOpenResult,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final priorityColor = task.priority != null
        ? Color(int.parse(task.priority!.color.replaceFirst('#', '0xFF')))
        : null;

    const win = Color(0xFF15803D);
    const loss = Color(0xFFB91C1C);
    final xfer = theme.colorScheme.primary;

    final closed = task.hasClosedResult;
    final showCrm = canMarkResult || canTransfer;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
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
              ),
              IconButton(
                tooltip: 'Copiar ID',
                onPressed: onCopyId,
                icon: const Icon(Icons.copy_rounded, size: 18),
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  foregroundColor: secondary,
                ),
              ),
              IconButton(
                tooltip: 'Fechar',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PriorityMark(
                  color: priorityColor ?? state.accent,
                  hasPriority: task.priority != null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        task.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                          height: 1.2,
                          fontSize: 20,
                          color: ThemeHelpers.textColor(context),
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _headerSubtitle(task),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      if (task.assignedTo != null)
                        _MetaAvatarPill(user: task.assignedTo!)
                      else
                        Text(
                          'Sem responsável',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: secondary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.1,
                          ),
                        ),
                    ],
                  ),
                ),
                if (showCrm) ...[
                  Container(
                    width: 1,
                    height: 26,
                    margin: const EdgeInsets.only(right: 6),
                    color: ThemeHelpers.borderColor(context)
                        .withValues(alpha: isDark ? 0.4 : 0.35),
                  ),
                  if (canMarkResult && closed)
                    _HeroCrmIconButton(
                      icon: Icons.tune_rounded,
                      tooltip: 'Resultado · reabrir ou revisar',
                      color: secondary,
                      onPressed: onOpenResult,
                    ),
                  if (canMarkResult && !closed) ...[
                    _HeroCrmIconButton(
                      icon: Icons.emoji_events_outlined,
                      tooltip: 'Marcar como vendido',
                      color: win,
                      onPressed: onMarkWon,
                    ),
                    const SizedBox(width: 4),
                    _HeroCrmIconButton(
                      icon: Icons.south_west_rounded,
                      tooltip: 'Marcar como perdido',
                      color: loss,
                      onPressed: onMarkLost,
                    ),
                  ],
                  if (canTransfer) ...[
                    if (canMarkResult) const SizedBox(width: 4),
                    _HeroCrmIconButton(
                      icon: Icons.swap_horiz_rounded,
                      tooltip: 'Transferir para outro funil',
                      color: xfer,
                      onPressed: onTransfer,
                    ),
                  ],
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 16, right: 16),
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

  static String _headerSubtitle(KanbanTask task) {
    final parts = <String>[];
    if (task.createdBy?.name.isNotEmpty == true) {
      parts.add('Criada por ${task.createdBy!.name}');
    }
    parts.add(_relativeTime(task.createdAt, prefix: '• criada'));
    if (task.updatedAt.difference(task.createdAt).inMinutes > 1) {
      parts.add(_relativeTime(task.updatedAt, prefix: '• atualizada'));
    }
    return parts.join('  ');
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
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
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

class _MetaAvatarPill extends StatelessWidget {
  final KanbanUser user;

  const _MetaAvatarPill({required this.user});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _kanbanAccent(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: accent.withValues(alpha: isDark ? 0.16 : 0.08),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SolidAvatar(user: user, size: 22),
          const SizedBox(width: 8),
          // `Flexible` (em vez de `ConstrainedBox(maxWidth: 160)`) deixa o
          // texto encolher quando o `Expanded` pai for menor que a soma
          // mínima dos chips — antes estourava por uns 3px em telas
          // estreitas.
          Flexible(
            child: Text(
              user.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
                height: 1,
              ),
            ),
          ),
        ],
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
    final accent = _kanbanAccent(context);
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

  const _TabItem({required this.icon, required this.label, this.badge});
}

class _MinimalTabBar extends StatelessWidget {
  final TabController controller;
  final List<_TabItem> tabs;

  const _MinimalTabBar({required this.controller, required this.tabs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _kanbanAccent(context);
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

  const _SectionHeader({
    required this.overline,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final accent = _kanbanAccent(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(width: 4, height: 14, color: accent),
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
                  color: accent,
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
// DESCRIPTION — editorial, sem caixa
// =============================================================================

/// Descrição "tipo pull-quote": eyebrow `BRIEFING` em cima, texto grande
/// com leading 1.55, e uma borda accent fina (3px) à esquerda fazendo o
/// papel de "régua editorial". Sem container cinza padrão.
///
/// Quando vazia: mensagem explicitamente discreta com ícone, sem
/// container — fica claro que está vazio sem ocupar muito espaço.
class _EditorialDescription extends StatelessWidget {
  final String? text;

  const _EditorialDescription({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final accent = _kanbanAccent(context);
    final empty = text == null || text!.isEmpty;
    final hasText = !empty;
    final length = hasText ? text!.length : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Eyebrow + título "Briefing" — alinhado, mas mais leve que o
        // _SectionHeader padrão (sem o stripe vertical de 4px à esquerda).
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'BRIEFING',
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
                color: ThemeHelpers.borderColor(context).withValues(alpha: 0.35),
              ),
            ),
            if (hasText) ...[
              const SizedBox(width: 10),
              Text(
                '$length caracteres',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: secondary,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),

        if (empty)
          Padding(
            padding: const EdgeInsets.only(left: 14, top: 4),
            child: Row(
              children: [
                Icon(Icons.short_text_rounded, size: 16, color: secondary),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Sem descrição. Edite o card para adicionar contexto.',
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
          )
        else
          // Régua accent à esquerda + texto editorial generoso
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: SelectableText(
                    text!,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      height: 1.55,
                      fontSize: 15,
                      letterSpacing: -0.1,
                      color: ThemeHelpers.textColor(context),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// BENTO INFO GRID (2×2 — substitui a lista vertical _InfoStack)
// =============================================================================

/// Grid 2×2 de tiles temáticos com info-chave do card.
///
/// Cada tile tem **cor própria** (não uma caixa cinza idêntica), com a
/// cor refletindo a categoria ou o estado:
/// - **Prazo**: cinza neutro / âmbar (vence hoje) / vermelho (atrasada)
/// - **Prioridade**: cor da própria prioridade (vinda do backend)
/// - **Funil**: roxo (`#8B5CF6`) — categoria de "contexto/organização"
/// - **Status**: verde (`#10B981`) se concluída, cinza se em aberto
///
/// O destaque é o **valor central grande** (não a label). Cada tile
/// também tem uma "helper line" no rodapé (ex.: "Em 3 dias", "Workspace
/// pessoal"). É bem mais escaneável que linhas verticais alinhadas.
class _BentoInfoGrid extends StatelessWidget {
  final KanbanTask task;
  final _TaskState state;

  const _BentoInfoGrid({required this.task, required this.state});

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

  @override
  Widget build(BuildContext context) {
    final priorityColor = task.priority != null
        ? Color(int.parse(task.priority!.color.replaceFirst('#', '0xFF')))
        : null;

    final tiles = <_BentoTile>[
      // PRAZO — destaque para data + helper "Em N dias"
      _BentoTile(
        icon: state.health == _TaskHealth.overdue
            ? Icons.error_rounded
            : state.health == _TaskHealth.dueToday
                ? Icons.warning_amber_rounded
                : Icons.event_outlined,
        accent: state.dueDate == null
            ? const Color(0xFF64748B) // slate
            : state.accent,
        label: 'Prazo',
        value: state.dueDate == null
            ? 'Sem prazo'
            : DateFormat("d 'de' MMM", 'pt_BR')
                .format(state.dueDate!.toLocal()),
        helper: state.dueDate == null ? null : _deadlineHelper(state),
        valueAccent: state.dueDate != null && state.health != _TaskHealth.ok,
      ),

      // PRIORIDADE — usa cor real vinda do backend
      _BentoTile(
        icon: Icons.flag_rounded,
        accent: priorityColor ?? const Color(0xFF94A3B8),
        label: 'Prioridade',
        value: task.priority?.label ?? 'Não definida',
        valueAccent: task.priority != null,
        helper: task.priority == null ? 'Defina ao editar' : null,
      ),

      // FUNIL — sempre roxo (cor de "contexto")
      if (task.project != null)
        _BentoTile(
          icon: Icons.account_tree_outlined,
          accent: const Color(0xFF8B5CF6),
          label: 'Funil',
          value: task.project!.name,
          helper: task.project!.isPersonal == true
              ? 'Workspace pessoal'
              : task.project!.status.label,
        )
      else
        _BentoTile(
          icon: Icons.account_tree_outlined,
          accent: const Color(0xFF94A3B8),
          label: 'Funil',
          value: 'Sem funil',
          helper: 'Sem projeto associado',
        ),

      // STATUS
      _BentoTile(
        icon: task.isCompleted
            ? Icons.check_circle_rounded
            : Icons.circle_outlined,
        accent: task.isCompleted
            ? const Color(0xFF10B981)
            : const Color(0xFF94A3B8),
        label: 'Status',
        value: task.isCompleted ? 'Concluída' : 'Em aberto',
        valueAccent: task.isCompleted,
        helper: task.isCompleted ? 'Marcada como done' : 'Aguardando',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // 2 colunas em larguras > 320 (sempre verdade pra mobile portrait
        // moderno). Em telas muito largas (tablet), dá pra usar 4 colunas.
        final cols = constraints.maxWidth >= 720 ? 4 : 2;
        const aspectRatio = 1.55; // largura/altura — tile ligeiramente
        // mais largo que alto, dá mais espaço pra label longa.

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: tiles.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: aspectRatio,
          ),
          itemBuilder: (_, i) => tiles[i].render(context),
        );
      },
    );
  }
}

class _BentoTile {
  final IconData icon;
  final Color accent;
  final String label;
  final String value;
  final String? helper;

  /// Quando `true`, o valor central usa a cor accent (chama atenção
  /// pra valores "ativos" — prazo crítico, prioridade definida, etc).
  final bool valueAccent;

  const _BentoTile({
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
    this.helper,
    this.valueAccent = false,
  });

  Widget render(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        // Fundo sutilmente tingido na cor do accent — não cinza idêntico.
        color: accent.withValues(alpha: isDark ? 0.10 : 0.06),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.32 : 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Topo: ícone + eyebrow label
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: accent.withValues(alpha: isDark ? 0.22 : 0.16),
                ),
                child: Icon(icon, size: 14, color: accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                    color: secondary,
                    fontSize: 10,
                    height: 1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          // Valor central em destaque
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
                height: 1.1,
                fontSize: 15.5,
                color: valueAccent
                    ? accent
                    : ThemeHelpers.textColor(context),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Helper line discreta no rodapé
          if (helper != null && helper!.isNotEmpty)
            Text(
              helper!,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: secondary,
                height: 1.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// PEOPLE STRIP
// =============================================================================

class _PeopleStrip extends StatelessWidget {
  final KanbanTask task;

  const _PeopleStrip({required this.task});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final twoCols = c.maxWidth >= 460;
        final cards = <Widget>[
          _PersonCard(
            label: 'Responsável',
            user: task.assignedTo,
            emptyHint: 'Nenhum responsável',
          ),
          _PersonCard(
            label: 'Criado por',
            user: task.createdBy,
            emptyHint: 'Desconhecido',
          ),
        ];
        if (!twoCols) {
          return Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                cards[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 10),
            Expanded(child: cards[1]),
          ],
        );
      },
    );
  }
}

class _PersonCard extends StatelessWidget {
  final String label;
  final KanbanUser? user;
  final String emptyHint;

  const _PersonCard({
    required this.label,
    required this.user,
    required this.emptyHint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final assigned = user != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: ThemeHelpers.cardBackgroundColor(context)
            .withValues(alpha: isDark ? 0.42 : 0.55),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (assigned)
            _SolidAvatar(user: user, size: 38)
          else
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ThemeHelpers.borderColor(context)
                    .withValues(alpha: 0.18),
                border: Border.all(
                  color: ThemeHelpers.borderColor(context)
                      .withValues(alpha: 0.5),
                ),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.person_outline_rounded,
                size: 18,
                color: secondary,
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                    color: secondary,
                    fontSize: 10,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  assigned ? user!.name : emptyHint,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    height: 1.2,
                    color: assigned
                        ? ThemeHelpers.textColor(context)
                        : secondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (assigned && (user!.email).isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    user!.email,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11.5,
                      color: secondary,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
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

/// Linha do tempo **horizontal** ligando 3 marcos do card:
/// Criada → Atualizada → Prazo. Cada marco tem ícone circular accent,
/// label, data e helper (tempo relativo).
///
/// Substitui o `_TimelineFooter` antigo que era uma lista vertical de 3
/// rows iguais — visualmente entediante e idêntico aos outros blocos.
class _HorizontalTimeline extends StatelessWidget {
  final KanbanTask task;
  final _TaskState state;

  const _HorizontalTimeline({required this.task, required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fmt = DateFormat("d MMM", 'pt_BR');
    final timeFmt = DateFormat("HH:mm");

    final entries = <_TimelineEntry>[
      _TimelineEntry(
        icon: Icons.add_circle_outline_rounded,
        accent: const Color(0xFF22C55E),
        label: 'Criada',
        value: fmt.format(task.createdAt.toLocal()),
        time: timeFmt.format(task.createdAt.toLocal()),
        helper: _relativeTime(task.createdAt),
      ),
      _TimelineEntry(
        icon: Icons.update_rounded,
        accent: const Color(0xFF3B82F6),
        label: 'Atualizada',
        value: fmt.format(task.updatedAt.toLocal()),
        time: timeFmt.format(task.updatedAt.toLocal()),
        helper: _relativeTime(task.updatedAt),
      ),
      if (state.dueDate != null)
        _TimelineEntry(
          icon: state.health == _TaskHealth.overdue
              ? Icons.error_rounded
              : state.health == _TaskHealth.dueToday
                  ? Icons.warning_amber_rounded
                  : Icons.event_outlined,
          accent: state.health == _TaskHealth.ok
              ? const Color(0xFF8B5CF6)
              : state.accent,
          label: 'Prazo',
          value: fmt.format(state.dueDate!.toLocal()),
          time: timeFmt.format(state.dueDate!.toLocal()),
          helper: _BentoInfoGrid._deadlineHelper(state),
          emphasized: state.health != _TaskHealth.ok,
        ),
    ];

    final lineColor = ThemeHelpers.borderColor(context)
        .withValues(alpha: isDark ? 0.6 : 0.45);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Posicionamento equidistante dos pontos. O segmento entre
          // pontos é a "linha conectora" pintada por baixo.
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
                  for (var i = 0; i < entries.length; i++)
                    Expanded(child: entries[i].render(context, theme)),
                ],
              ),
            ],
          );
        },
      ),
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
        // Bullet circular accent — fica POR CIMA da linha conectora,
        // por isso tem fundo do scaffold pra "esconder" a linha que passa
        // por trás (ilusão de quebra do conector).
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scaffoldBg,
            border: Border.all(
              color: accent.withValues(alpha: emphasized ? 0.85 : 0.55),
              width: emphasized ? 2 : 1.5,
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
            size: 16,
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

class _CommentBubble extends StatelessWidget {
  final KanbanTaskComment comment;
  final bool isMe;
  final bool canDelete;
  final VoidCallback onDelete;

  const _CommentBubble({
    required this.comment,
    required this.isMe,
    required this.canDelete,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _kanbanAccent(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    final bubbleColor = isMe
        ? accent.withValues(alpha: isDark ? 0.16 : 0.08)
        : ThemeHelpers.cardBackgroundColor(context)
            .withValues(alpha: isDark ? 0.5 : 0.7);
    final borderColor = isMe
        ? accent.withValues(alpha: 0.34)
        : ThemeHelpers.borderColor(context).withValues(alpha: 0.45);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SolidAvatar(user: comment.user, size: 34),
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
                  const SizedBox(height: 6),
                  SelectableText(
                    comment.message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                      fontSize: 13.5,
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
    final accent = _kanbanAccent(context);
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
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Escreva uma mensagem para o time…',
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

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final danger = theme.colorScheme.error;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: danger.withValues(alpha: 0.12),
                border: Border.all(color: danger.withValues(alpha: 0.36)),
              ),
              child: Icon(Icons.error_outline_rounded, color: danger, size: 26),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
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
    final accent = _kanbanAccent(context);
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
