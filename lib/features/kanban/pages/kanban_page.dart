import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/kanban_models.dart';
import '../controllers/kanban_controller.dart';
import '../widgets/create_task_modal.dart';
import '../widgets/create_column_modal.dart';
import '../widgets/edit_task_modal.dart';
import '../widgets/edit_column_modal.dart';
import '../widgets/kanban_filters.dart';
import '../../../shared/services/module_access_service.dart';

/// Página principal do Kanban
class KanbanPage extends StatefulWidget {
  const KanbanPage({super.key});

  @override
  State<KanbanPage> createState() => _KanbanPageState();
}

class _KanbanPageState extends State<KanbanPage> {
  final _moduleAccess = ModuleAccessService.instance;
  bool _hasAccess = false;
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  Future<void> _checkAccess() async {
    // Verificar se módulo está disponível e se tem permissão
    final hasModule = _moduleAccess.isModuleAvailableForCompany('kanban_management');
    final hasPermission = _moduleAccess.hasPermission('kanban:view');
    
    setState(() {
      _hasAccess = hasModule && hasPermission;
      _isChecking = false;
    });

    // Se tem acesso, carregar o quadro
    if (_hasAccess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<KanbanController>().loadBoard();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Verificar acesso antes de renderizar
    if (_isChecking) {
      return AppScaffold(
        title: 'Tarefas',
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasAccess) {
      return AppScaffold(
        title: 'Tarefas',
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Acesso Negado',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Você não tem permissão para acessar o sistema de tarefas.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Voltar'),
              ),
            ],
          ),
        ),
      );
    }

    return Consumer<KanbanController>(
      builder: (context, controller, _) {
        final theme = Theme.of(context);

        return AppScaffold(
          title: 'Tarefas',
          body: controller.loading
              ? const Center(child: CircularProgressIndicator())
              : controller.error != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 64,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            controller.error!,
                            style: theme.textTheme.bodyLarge,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => controller.loadBoard(),
                            child: const Text('Tentar Novamente'),
                          ),
                        ],
                      ),
                    )
                  : controller.columns.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.dashboard_outlined,
                                size: 64,
                                color: ThemeHelpers.textSecondaryColor(context),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Nenhuma coluna encontrada',
                                style: theme.textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Crie uma coluna para começar',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: ThemeHelpers.textSecondaryColor(context),
                                ),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton.icon(
                                onPressed: () => _showCreateColumnModal(context),
                                icon: const Icon(Icons.add),
                                label: const Text('Criar Coluna'),
                              ),
                            ],
                          ),
                        )
                      : _buildKanbanBoard(controller),
        );
      },
    );
  }

  void _showCreateColumnModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const CreateColumnModal(),
    );
  }

  Widget _buildKanbanBoard(KanbanController controller) {
    return Column(
      children: [
        // Header com informações
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            border: Border(
              bottom: BorderSide(
                color: ThemeHelpers.borderColor(context),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Quadro Kanban',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              if (controller.permissions?.canCreateColumns ?? true)
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _showCreateColumnModal(context),
                  tooltip: 'Criar Coluna',
                ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => controller.loadBoard(),
                tooltip: 'Atualizar',
              ),
            ],
          ),
        ),
        // Filtros
        const KanbanFilters(),
        // Quadro com colunas
        Expanded(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(16),
            itemCount: controller.columns.length,
            itemBuilder: (context, index) {
              final column = controller.columns[index];
              final columnTasks = controller.getTasksForColumn(column.id);

              return _buildColumn(context, controller, column, columnTasks);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildColumn(
    BuildContext context,
    KanbanController controller,
    KanbanColumn column,
    List<KanbanTask> tasks,
  ) {
    final theme = Theme.of(context);
    final columnColor = column.color != null
        ? Color(int.parse(column.color!.replaceFirst('#', '0xFF')))
        : Theme.of(context).colorScheme.primary;

    return Container(
      width: 300,
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ThemeHelpers.borderColor(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            // Header da coluna
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: columnColor.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 24,
                    decoration: BoxDecoration(
                      color: columnColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          column.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (column.description != null)
                          Text(
                            column.description!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: ThemeHelpers.textSecondaryColor(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: columnColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${tasks.length}',
                      style: TextStyle(
                        color: columnColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if ((controller.permissions?.canEditColumns ?? false) ||
                      (controller.permissions?.canDeleteColumns ?? false))
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_vert,
                        size: 20,
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                      itemBuilder: (context) => [
                        if (controller.permissions?.canEditColumns ?? true)
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit, size: 18),
                                SizedBox(width: 8),
                                Text('Editar'),
                              ],
                            ),
                          ),
                        if (controller.permissions?.canDeleteColumns ?? true)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, size: 18, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Deletar', style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                      ],
                      onSelected: (value) {
                        if (value == 'edit') {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (context) => EditColumnModal(column: column),
                          );
                        } else if (value == 'delete') {
                          _confirmDeleteColumn(context, controller, column);
                        }
                      },
                    ),
                ],
              ),
            ),
          // Lista de tarefas (com drag and drop)
          Expanded(
            child: tasks.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Nenhuma tarefa',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                      ),
                    ),
                  )
                : DragTarget<KanbanTask>(
                    onWillAccept: (data) => data != null && data.columnId != column.id,
                    onAccept: (task) {
                      _handleTaskDrop(context, controller, task, column.id);
                    },
                    builder: (context, candidateData, rejectedData) {
                      final isTargeting = candidateData.isNotEmpty;
                      return Container(
                        decoration: BoxDecoration(
                          color: isTargeting
                              ? columnColor.withOpacity(0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: tasks.length,
                          itemBuilder: (context, index) {
                            return _buildDraggableTask(
                              context,
                              controller,
                              tasks[index],
                              column.id,
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
          // Botão para adicionar tarefa
          if (controller.permissions?.canCreateTasks ?? true)
            Padding(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => Padding(
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.of(context).viewInsets.bottom,
                        ),
                        child: CreateTaskModal(
                          columnId: column.id,
                          teamId: controller.teamId ?? '',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Adicionar Tarefa'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDraggableTask(
    BuildContext context,
    KanbanController controller,
    KanbanTask task,
    String currentColumnId,
  ) {
    if (!(controller.permissions?.canMoveTasks ?? false)) {
      return GestureDetector(
        onLongPress: () {
          _showTaskActions(context, task);
        },
        child: _buildTaskCard(task),
      );
    }

    return LongPressDraggable<KanbanTask>(
      data: task,
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 280,
          child: _buildTaskCard(task),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildTaskCard(task),
      ),
      child: GestureDetector(
        onLongPress: () {
          _showTaskActions(context, task);
        },
        child: _buildTaskCard(task),
      ),
    );
  }

  void _handleTaskDrop(
    BuildContext context,
    KanbanController controller,
    KanbanTask task,
    String targetColumnId,
  ) {
    if (task.columnId == targetColumnId) return;

    final targetTasks = controller.getTasksForColumn(targetColumnId);
    final newPosition = targetTasks.length;

    controller.moveTask(
      taskId: task.id,
      targetColumnId: targetColumnId,
      targetPosition: newPosition,
    );
  }

  Widget _buildTaskCard(KanbanTask task) {
    final theme = Theme.of(context);
    final priorityColor = task.priority != null
        ? Color(int.parse(
            task.priority!.color.replaceFirst('#', '0xFF'),
          ))
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: priorityColor?.withOpacity(0.3) ??
              ThemeHelpers.borderColor(context),
          width: priorityColor != null ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            task.title,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (task.description != null && task.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              task.description!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (task.priority != null || task.assignedTo != null || task.dueDate != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (task.priority != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: priorityColor?.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      task.priority!.label,
                      style: TextStyle(
                        color: priorityColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (task.assignedTo != null) ...[
                  const Spacer(),
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                    backgroundImage: task.assignedTo!.avatar != null
                        ? NetworkImage(task.assignedTo!.avatar!)
                        : null,
                    child: task.assignedTo!.avatar == null
                        ? Text(
                            task.assignedTo!.name[0].toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : null,
                  ),
                ],
                if (task.dueDate != null) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.calendar_today,
                    size: 14,
                    color: _isOverdue(task.dueDate!)
                        ? theme.colorScheme.error
                        : ThemeHelpers.textSecondaryColor(context),
                  ),
                ],
                if (task.commentsCount != null && task.commentsCount! > 0) ...[
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.comment,
                        size: 14,
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${task.commentsCount}',
                        style: TextStyle(
                          fontSize: 12,
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                      ),
                    ],
                  ),
                ],
                if (task.tags != null && task.tags!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Wrap(
                    spacing: 4,
                    children: task.tags!.take(2).map((tag) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  bool _isOverdue(DateTime dueDate) {
    return dueDate.isBefore(DateTime.now());
  }

  void _showTaskActions(BuildContext context, KanbanTask task) {
    final controller = context.read<KanbanController>();
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Editar'),
              onTap: () {
                Navigator.pop(context);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom,
                    ),
                    child: EditTaskModal(task: task),
                  ),
                );
              },
            ),
            if (controller.permissions?.canDeleteTasks ?? true)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Deletar', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeleteTask(context, controller, task);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteTask(
    BuildContext context,
    KanbanController controller,
    KanbanTask task,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deletar Tarefa'),
        content: Text('Tem certeza que deseja deletar a tarefa "${task.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final success = await controller.deleteTask(task.id);
              if (context.mounted) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Tarefa deletada com sucesso!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        controller.error ?? 'Erro ao deletar tarefa',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Deletar'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteColumn(
    BuildContext context,
    KanbanController controller,
    KanbanColumn column,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deletar Coluna'),
        content: Text(
          'Tem certeza que deseja deletar a coluna "${column.title}"? '
          'Todas as tarefas desta coluna serão movidas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final success = await controller.deleteColumn(column.id);
              if (context.mounted) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Coluna deletada com sucesso!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        controller.error ?? 'Erro ao deletar coluna',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Deletar'),
          ),
        ],
      ),
    );
  }
}

