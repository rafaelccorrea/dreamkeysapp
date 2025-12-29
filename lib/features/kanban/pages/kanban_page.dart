import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../widgets/project_selector.dart';
import '../widgets/kanban_skeleton.dart';
import '../widgets/task_details_modal.dart';

// ScrollBehavior customizado para ocultar barras de rolagem
class NoScrollbarScrollBehavior extends ScrollBehavior {
  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child; // Não renderiza a barra de rolagem
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child; // Não renderiza o indicador de overscroll
  }
}

/// Página principal do Kanban
class KanbanPage extends StatefulWidget {
  const KanbanPage({super.key});

  @override
  State<KanbanPage> createState() => _KanbanPageState();
}

class _KanbanPageState extends State<KanbanPage> {
  final ScrollController _horizontalScrollController = ScrollController();
  Timer? _autoScrollTimer;
  bool _isDragging = false;
  double _scrollSpeed = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = context.read<KanbanController>();
      // Carregar times primeiro, depois o quadro
      controller.loadTeams().then((_) {
        controller.loadBoard();
      });
    });
  }

  @override
  void dispose() {
    _stopAutoScroll();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!_isDragging || !_horizontalScrollController.hasClients) {
        _stopAutoScroll();
        return;
      }
      _performAutoScroll();
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  void _updateAutoScroll(double dragX) {
    if (!_horizontalScrollController.hasClients) return;
    final screenWidth = MediaQuery.of(context).size.width;
    final scrollPosition = _horizontalScrollController.position;
    final scrollOffset = scrollPosition.pixels;
    final scrollMax = scrollPosition.maxScrollExtent;

    // Zona de ativação do auto-scroll (100px das bordas para detectar melhor)
    const scrollZone = 100.0;
    double newScrollSpeed = 0;

    // Verificar se está próximo da borda esquerda ou parcialmente fora
    if (dragX < scrollZone) {
      if (scrollOffset > 0) {
        // Scroll para a esquerda (valores negativos)
        // Se está fora da tela (dragX < 0), usar velocidade máxima
        if (dragX < 0) {
          newScrollSpeed = -20; // Velocidade máxima quando fora da tela
        } else {
          // Velocidade proporcional à proximidade da borda
          newScrollSpeed = -((scrollZone - dragX) / scrollZone) * 20;
        }
      }
    }
    // Verificar se está próximo da borda direita ou parcialmente fora
    else if (dragX > screenWidth - scrollZone) {
      if (scrollOffset < scrollMax) {
        // Scroll para a direita (valores positivos)
        // Se está fora da tela (dragX > screenWidth), usar velocidade máxima
        if (dragX > screenWidth) {
          newScrollSpeed = 20; // Velocidade máxima quando fora da tela
        } else {
          // Velocidade proporcional à proximidade da borda
          newScrollSpeed =
              ((dragX - (screenWidth - scrollZone)) / scrollZone) * 20;
        }
      }
    }

    _scrollSpeed = newScrollSpeed;

    if (newScrollSpeed != 0 && _autoScrollTimer == null) {
      _startAutoScroll();
    } else if (newScrollSpeed == 0) {
      _stopAutoScroll();
    }
  }

  void _performAutoScroll() {
    if (!_horizontalScrollController.hasClients || _scrollSpeed == 0) {
      _stopAutoScroll();
      return;
    }

    final scrollPosition = _horizontalScrollController.position;
    final scrollOffset = scrollPosition.pixels;
    final scrollMax = scrollPosition.maxScrollExtent;

    double newOffset = scrollOffset + _scrollSpeed;

    // Limitar o scroll aos limites
    newOffset = newOffset.clamp(0.0, scrollMax);

    if (newOffset != scrollOffset) {
      _horizontalScrollController.jumpTo(newOffset);
    } else {
      // Se chegou ao limite, parar o scroll
      _stopAutoScroll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<KanbanController>(
      builder: (context, controller, _) {
        final theme = Theme.of(context);

        return AppScaffold(
          title: 'Tarefas',
          body: controller.loading
              ? const KanbanSkeleton()
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
    return ScrollConfiguration(
      behavior: NoScrollbarScrollBehavior(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            // Header com informações
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: ThemeHelpers.cardBackgroundColor(context),
                border: Border(
                  bottom: BorderSide(color: ThemeHelpers.borderColor(context)),
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
            // Seletor de Projeto
            const ProjectSelector(),
            // Filtros
            const KanbanFilters(),
            // Espaço entre filtros e colunas
            const SizedBox(height: 16),
            // Quadro com colunas - scroll horizontal
            LayoutBuilder(
              builder: (context, constraints) {
                final screenHeight = MediaQuery.of(context).size.height;
                final availableHeight = screenHeight * 0.6;

                final totalWidth =
                    (controller.columns.length * 300.0) +
                    ((controller.columns.length - 1) *
                        16.0); // largura das colunas + margens
                return SizedBox(
                  height: availableHeight,
                  child: ScrollConfiguration(
                    behavior: NoScrollbarScrollBehavior(),
                    child: SingleChildScrollView(
                      controller: _horizontalScrollController,
                      scrollDirection: Axis.horizontal,
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: constraints.maxWidth > totalWidth
                              ? constraints.maxWidth
                              : totalWidth,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: controller.columns.map((column) {
                            final columnTasks = controller.getTasksForColumn(
                              column.id,
                            );
                            return _buildColumn(
                              context,
                              controller,
                              column,
                              columnTasks,
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
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
      constraints: const BoxConstraints(minHeight: 400),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ThemeHelpers.borderColor(context)),
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
                              Text(
                                'Deletar',
                                style: TextStyle(color: Colors.red),
                              ),
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
          // Lista de tarefas (com drag and drop) - sem scroll interno, altura fixa
          Expanded(
            child: tasks.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        'Nenhuma tarefa',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                      ),
                    ),
                  )
                : DragTarget<KanbanTask>(
                    onWillAccept: (data) =>
                        data != null && data.columnId != column.id,
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
                        child: ScrollConfiguration(
                          behavior: NoScrollbarScrollBehavior(),
                          child: ListView.builder(
                            shrinkWrap: false,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(8),
                            itemCount: tasks.length,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _buildDraggableTask(
                                  context,
                                  controller,
                                  tasks[index],
                                  column.id,
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
          // Botão para adicionar tarefa
          if (controller.permissions?.canCreateTasks ?? true)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
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
        onTap: () {
          // Abrir modal de detalhes ao tocar na tarefa
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => TaskDetailsModal(task: task),
          );
        },
        onLongPress: () {
          _showTaskActions(context, task);
        },
        child: _buildTaskCard(task),
      );
    }

    return LongPressDraggable<KanbanTask>(
      data: task,
      delay: const Duration(
        milliseconds: 100,
      ), // Delay menor para iniciar drag mais rápido
      onDragStarted: () {
        setState(() {
          _isDragging = true;
        });
        _startAutoScroll();
      },
      onDragEnd: (_) {
        setState(() {
          _isDragging = false;
        });
        _stopAutoScroll();
      },
      onDragUpdate: (details) {
        _updateAutoScroll(details.globalPosition.dx);
      },
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        child: Container(width: 280, child: _buildTaskCard(task)),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: _buildTaskCard(task)),
      child: _buildTaskCard(task),
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
        ? Color(int.parse(task.priority!.color.replaceFirst('#', '0xFF')))
        : null;

    return GestureDetector(
      onDoubleTap: () {
        // Abrir modal de detalhes ao dar duplo clique
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.black54,
          builder: (context) => TaskDetailsModal(task: task),
        );
      },
      child: Container(
        width: double.infinity,
        height: 120, // Altura fixa para os cards
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                priorityColor?.withOpacity(0.3) ??
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
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    task.title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onSelected: (value) {
                    switch (value) {
                      case 'details':
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (context) => TaskDetailsModal(task: task),
                        );
                        break;
                      case 'edit':
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
                        break;
                      case 'delete':
                        final controller = context.read<KanbanController>();
                        _confirmDeleteTask(context, controller, task);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'details',
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 18),
                          SizedBox(width: 8),
                          Text('Ver detalhes'),
                        ],
                      ),
                    ),
                    if (context
                            .read<KanbanController>()
                            .permissions
                            ?.canEditTasks ??
                        true)
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
                    if (context
                            .read<KanbanController>()
                            .permissions
                            ?.canDeleteTasks ??
                        true)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: Colors.red,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Excluir',
                              style: TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
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
            if (task.priority != null ||
                task.assignedTo != null ||
                task.dueDate != null) ...[
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
                      backgroundColor: theme.colorScheme.primary.withOpacity(
                        0.1,
                      ),
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
                  if (task.commentsCount != null &&
                      task.commentsCount! > 0) ...[
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
                title: const Text(
                  'Deletar',
                  style: TextStyle(color: Colors.red),
                ),
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
        content: Text(
          'Tem certeza que deseja deletar a tarefa "${task.title}"?',
        ),
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
            style: TextButton.styleFrom(foregroundColor: Colors.red),
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
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Deletar'),
          ),
        ],
      ),
    );
  }
}
