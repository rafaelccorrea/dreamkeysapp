import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/secure_storage_service.dart';
import '../../../shared/utils/jwt_utils.dart';
import '../models/kanban_models.dart';
import '../services/kanban_service.dart';

/// Modal completo de detalhes da tarefa com abas
class TaskDetailsModal extends StatefulWidget {
  final KanbanTask task;

  const TaskDetailsModal({
    super.key,
    required this.task,
  });

  @override
  State<TaskDetailsModal> createState() => _TaskDetailsModalState();
}

class _TaskDetailsModalState extends State<TaskDetailsModal>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final KanbanService _kanbanService = KanbanService.instance;

  // Estado de comentários
  List<KanbanTaskComment> _comments = [];
  bool _loadingComments = false;
  String? _commentsError;
  final TextEditingController _commentController = TextEditingController();
  List<File> _selectedFiles = [];
  bool _submittingComment = false;
  int _commentLength = 0;

  // Estado de histórico
  List<HistoryEntry> _history = [];
  bool _loadingHistory = false;
  String? _historyError;

  // ID do usuário atual (para verificar se pode deletar comentários)
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadCurrentUserId();
    _loadComments();
    _tabController.addListener(() {
      if (_tabController.index == 2 && _history.isEmpty && !_loadingHistory) {
        _loadHistory();
      }
    });
    _commentController.addListener(() {
      setState(() {
        _commentLength = _commentController.text.length;
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUserId() async {
    try {
      final token = await SecureStorageService.instance.getAccessToken();
      if (token != null) {
        final payload = JwtUtils.decodeToken(token);
        if (payload != null) {
          setState(() {
            _currentUserId = payload['sub']?.toString() ?? payload['userId']?.toString();
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
      setState(() {
        _commentsError = 'Erro ao carregar comentários: ${e.toString()}';
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
      setState(() {
        _historyError = 'Erro ao carregar histórico: ${e.toString()}';
        _loadingHistory = false;
      });
    }
  }

  Future<void> _selectFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );

      if (result != null && result.files.isNotEmpty) {
        final files = result.files
            .where((f) => f.path != null)
            .map((f) => File(f.path!))
            .toList();

        // Validar quantidade (máx. 10)
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

        setState(() {
          _selectedFiles.addAll(files);
        });
      }
    } catch (e) {
      debugPrint('❌ [TASK_DETAILS] Erro ao selecionar arquivos: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao selecionar arquivos: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _removeFile(int index) {
    setState(() {
      _selectedFiles.removeAt(index);
    });
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

    setState(() {
      _submittingComment = true;
    });

    try {
      final response = await _kanbanService.createComment(
        widget.task.id,
        message,
        _selectedFiles.isNotEmpty ? _selectedFiles : null,
      );

      if (mounted) {
        if (response.success && response.data != null) {
          // Adicionar comentário à lista (optimistic update)
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
          setState(() {
            _submittingComment = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao criar comentário'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submittingComment = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao criar comentário: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteComment(String commentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deletar Comentário'),
        content: const Text('Tem certeza que deseja deletar este comentário?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Deletar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await _kanbanService.deleteComment(widget.task.id, commentId);
      if (response.success) {
        setState(() {
          _comments.removeWhere((c) => c.id == commentId);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Comentário deletado com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao deletar comentário'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao deletar comentário: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  bool _canDeleteComment(KanbanTaskComment comment) {
    return _currentUserId != null && comment.userId == _currentUserId;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _getActionLabel(String action) {
    switch (action) {
      case 'created':
        return 'criou a tarefa';
      case 'updated':
        return 'atualizou';
      case 'moved':
        return 'moveu';
      case 'assigned':
        return 'atribuiu responsável';
      case 'unassigned':
        return 'removeu responsável';
      case 'priority_changed':
        return 'alterou prioridade';
      case 'due_date_changed':
        return 'alterou data de vencimento';
      case 'description_changed':
        return 'alterou descrição';
      case 'title_changed':
        return 'alterou título';
      case 'tags_changed':
        return 'alterou tags';
      case 'project_changed':
        return 'alterou projeto';
      case 'completed':
        return 'concluiu a tarefa';
      case 'reopened':
        return 'reabriu a tarefa';
      default:
        return action;
    }
  }

  String _getPriorityLabel(String? priority) {
    switch (priority?.toLowerCase()) {
      case 'low':
        return 'Baixa';
      case 'medium':
        return 'Média';
      case 'high':
        return 'Alta';
      case 'urgent':
        return 'Urgente';
      default:
        return priority ?? 'Não definida';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final task = widget.task;

    return Material(
      color: ThemeHelpers.cardBackgroundColor(context),
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(20),
        topRight: Radius.circular(20),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
        child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: ThemeHelpers.textSecondaryColor(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(
                  Icons.task_alt,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    task.title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          // Tabs
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Detalhes', icon: Icon(Icons.info_outline)),
              Tab(text: 'Comentários', icon: Icon(Icons.comment_outlined)),
              Tab(text: 'Histórico', icon: Icon(Icons.history)),
            ],
          ),
          // Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildDetailsTab(context, task, theme),
                _buildCommentsTab(context, theme),
                _buildHistoryTab(context, theme),
              ],
            ),
          ),
        ],
        ),
        ),
      ),
    );
  }

  Widget _buildDetailsTab(
    BuildContext context,
    KanbanTask task,
    ThemeData theme,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Descrição
          if (task.description != null && task.description!.isNotEmpty) ...[
            Text(
              'Descrição',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              task.description!,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
          ],
          // Informações
          Text(
            'Informações',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            context,
            'Prioridade',
            task.priority != null
                ? Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Color(int.parse(
                            task.priority!.color.replaceFirst('#', '0xFF'),
                          )),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(_getPriorityLabel(task.priority!.name)),
                    ],
                  )
                : const Text('Não definida'),
          ),
          if (task.assignedTo != null) ...[
            const SizedBox(height: 8),
            _buildInfoRow(
              context,
              'Responsável',
              Row(
                children: [
                  if (task.assignedTo!.avatar != null)
                    CircleAvatar(
                      radius: 12,
                      backgroundImage: NetworkImage(task.assignedTo!.avatar!),
                    )
                  else
                    CircleAvatar(
                      radius: 12,
                      child: Text(
                        task.assignedTo!.name[0].toUpperCase(),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Text(task.assignedTo!.name),
                ],
              ),
            ),
          ],
          if (task.createdBy != null) ...[
            const SizedBox(height: 8),
            _buildInfoRow(
              context,
              'Criado por',
              Row(
                children: [
                  if (task.createdBy!.avatar != null)
                    CircleAvatar(
                      radius: 12,
                      backgroundImage: NetworkImage(task.createdBy!.avatar!),
                    )
                  else
                    CircleAvatar(
                      radius: 12,
                      child: Text(
                        task.createdBy!.name[0].toUpperCase(),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Text(task.createdBy!.name),
                ],
              ),
            ),
          ],
          if (task.dueDate != null) ...[
            const SizedBox(height: 8),
            _buildInfoRow(
              context,
              'Data de Vencimento',
              Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: task.dueDate!.isBefore(DateTime.now())
                        ? Colors.red
                        : ThemeHelpers.textSecondaryColor(context),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('dd/MM/yyyy').format(task.dueDate!),
                    style: TextStyle(
                      color: task.dueDate!.isBefore(DateTime.now())
                          ? Colors.red
                          : null,
                      fontWeight: task.dueDate!.isBefore(DateTime.now())
                          ? FontWeight.w600
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (task.project != null) ...[
            const SizedBox(height: 8),
            _buildInfoRow(
              context,
              'Projeto',
              Text(task.project!.name),
            ),
          ],
          if (task.tags != null && task.tags!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Tags',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: task.tags!.map((tag) {
                return Chip(
                  label: Text(tag),
                  labelStyle: const TextStyle(fontSize: 12),
                  padding: EdgeInsets.zero,
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 24),
          // Datas
          Text(
            'Datas',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            context,
            'Criado em',
            Text(DateFormat('dd/MM/yyyy HH:mm').format(task.createdAt)),
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            context,
            'Atualizado em',
            Text(DateFormat('dd/MM/yyyy HH:mm').format(task.updatedAt)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, Widget value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              color: ThemeHelpers.textSecondaryColor(context),
              fontSize: 14,
            ),
          ),
        ),
        Expanded(child: value),
      ],
    );
  }

  Widget _buildCommentsTab(BuildContext context, ThemeData theme) {
    return Column(
      children: [
        // Lista de comentários
        Expanded(
          child: _loadingComments
              ? const Center(child: CircularProgressIndicator())
              : _commentsError != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 48,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _commentsError!,
                            style: theme.textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _loadComments,
                            child: const Text('Tentar Novamente'),
                          ),
                        ],
                      ),
                    )
                  : _comments.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.comment_outlined,
                                size: 48,
                                color: ThemeHelpers.textSecondaryColor(context),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Nenhum comentário ainda',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: ThemeHelpers.textSecondaryColor(context),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _comments.length,
                          itemBuilder: (context, index) {
                            final comment = _comments[index];
                            return _buildCommentItem(context, comment, theme);
                          },
                        ),
        ),
        // Formulário de comentário
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            border: Border(
              top: BorderSide(
                color: ThemeHelpers.borderColor(context),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Arquivos selecionados
              if (_selectedFiles.isNotEmpty) ...[
                SizedBox(
                  height: 60,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _selectedFiles.length,
                    itemBuilder: (context, index) {
                      final file = _selectedFiles[index];
                      return Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: ThemeHelpers.borderColor(context).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.attach_file, size: 16),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                file.path.split('/').last.split('\\').last,
                                style: const TextStyle(fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => _removeFile(index),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
              // Campo de mensagem
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      decoration: InputDecoration(
                        hintText: 'Escreva um comentário...',
                        filled: true,
                        fillColor: ThemeHelpers.cardBackgroundColor(context),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: ThemeHelpers.borderColor(context),
                            width: 1,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: ThemeHelpers.borderColor(context),
                            width: 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: theme.colorScheme.primary,
                            width: 2,
                          ),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: ThemeHelpers.borderColor(context).withOpacity(0.5),
                            width: 1,
                          ),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: theme.colorScheme.error,
                            width: 1,
                          ),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: theme.colorScheme.error,
                            width: 2,
                          ),
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.attach_file),
                          onPressed: _selectFiles,
                          tooltip: 'Anexar arquivos',
                        ),
                      ),
                      maxLines: 3,
                      maxLength: 2000,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: _submittingComment
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    onPressed: _submittingComment ? null : _submitComment,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
              // Contador de caracteres
              Text(
                '$_commentLength/2000',
                style: TextStyle(
                  fontSize: 12,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCommentItem(
    BuildContext context,
    KanbanTaskComment comment,
    ThemeData theme,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: ThemeHelpers.borderColor(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header do comentário
          Row(
            children: [
              // Avatar
              if (comment.user?.avatar != null)
                CircleAvatar(
                  radius: 16,
                  backgroundImage: NetworkImage(comment.user!.avatar!),
                )
              else
                CircleAvatar(
                  radius: 16,
                  child: Text(
                    comment.user?.name[0].toUpperCase() ?? '?',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              const SizedBox(width: 12),
              // Nome e data
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comment.user?.name ?? 'Usuário',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      DateFormat('dd/MM/yyyy HH:mm').format(comment.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                    ),
                  ],
                ),
              ),
              // Botão deletar (se for o criador)
              if (_canDeleteComment(comment))
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: Colors.red,
                  onPressed: () => _deleteComment(comment.id),
                  tooltip: 'Deletar comentário',
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Mensagem
          Text(
            comment.message,
            style: theme.textTheme.bodyMedium,
          ),
          // Anexos
          if (comment.attachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...comment.attachments.map((attachment) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: ThemeHelpers.borderColor(context).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.attach_file, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            attachment.filename,
                            style: const TextStyle(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _formatFileSize(attachment.size),
                            style: TextStyle(
                              fontSize: 10,
                              color: ThemeHelpers.textSecondaryColor(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.download, size: 18),
                      onPressed: () {
                        // TODO: Implementar download
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Download: ${attachment.url}'),
                          ),
                        );
                      },
                      tooltip: 'Download',
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryTab(BuildContext context, ThemeData theme) {
    return _loadingHistory
        ? const Center(child: CircularProgressIndicator())
        : _historyError != null
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _historyError!,
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadHistory,
                      child: const Text('Tentar Novamente'),
                    ),
                  ],
                ),
              )
            : _history.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.history,
                          size: 48,
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Nenhum histórico disponível',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _history.length,
                    itemBuilder: (context, index) {
                      final entry = _history[index];
                      return _buildHistoryItem(context, entry, theme);
                    },
                  );
  }

  Widget _buildHistoryItem(
    BuildContext context,
    HistoryEntry entry,
    ThemeData theme,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: ThemeHelpers.borderColor(context),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          if (entry.user?.avatar != null)
            CircleAvatar(
              radius: 16,
              backgroundImage: NetworkImage(entry.user!.avatar!),
            )
          else
            CircleAvatar(
              radius: 16,
              child: Text(
                entry.user?.name[0].toUpperCase() ?? '?',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          const SizedBox(width: 12),
          // Conteúdo
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ação
                RichText(
                  text: TextSpan(
                    style: theme.textTheme.bodyMedium,
                    children: [
                      TextSpan(
                        text: entry.user?.name ?? 'Sistema',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(text: ' ${_getActionLabel(entry.action)}'),
                      if (entry.fieldLabel != null)
                        TextSpan(
                          text: ' - ${entry.fieldLabel}',
                          style: TextStyle(
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                        ),
                    ],
                  ),
                ),
                // Valores antigos e novos
                if (entry.oldValue != null || entry.newValue != null) ...[
                  const SizedBox(height: 4),
                  if (entry.oldValue != null)
                    Text(
                      'Antes: ${entry.oldValue}',
                      style: TextStyle(
                        fontSize: 12,
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                    ),
                  if (entry.newValue != null)
                    Text(
                      'Agora: ${entry.newValue}',
                      style: TextStyle(
                        fontSize: 12,
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                    ),
                ],
                // Movimentação entre colunas
                if (entry.fromColumn != null && entry.toColumn != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'De ',
                        style: TextStyle(
                          fontSize: 12,
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Color(int.parse(
                            entry.fromColumn!.color.replaceFirst('#', '0xFF'),
                          )).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: Color(int.parse(
                              entry.fromColumn!.color.replaceFirst('#', '0xFF'),
                            )).withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          entry.fromColumn!.title,
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(int.parse(
                              entry.fromColumn!.color.replaceFirst('#', '0xFF'),
                            )),
                          ),
                        ),
                      ),
                      Text(
                        ' para ',
                        style: TextStyle(
                          fontSize: 12,
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Color(int.parse(
                            entry.toColumn!.color.replaceFirst('#', '0xFF'),
                          )).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: Color(int.parse(
                              entry.toColumn!.color.replaceFirst('#', '0xFF'),
                            )).withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          entry.toColumn!.title,
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(int.parse(
                              entry.toColumn!.color.replaceFirst('#', '0xFF'),
                            )),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                // Data
                const SizedBox(height: 4),
                Text(
                  DateFormat('dd/MM/yyyy HH:mm').format(entry.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: ThemeHelpers.textSecondaryColor(context),
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

