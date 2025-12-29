import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/kanban_models.dart';
import '../controllers/kanban_controller.dart';
import '../services/kanban_service.dart';

/// Modal para editar tarefa
class EditTaskModal extends StatefulWidget {
  final KanbanTask task;

  const EditTaskModal({
    super.key,
    required this.task,
  });

  @override
  State<EditTaskModal> createState() => _EditTaskModalState();
}

class _EditTaskModalState extends State<EditTaskModal> {
  final _formKey = GlobalKey<FormState>();
  final KanbanService _kanbanService = KanbanService.instance;
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  KanbanPriority? _selectedPriority;
  DateTime? _selectedDueDate;
  String? _selectedAssignedToId;
  List<String> _selectedTags = [];
  List<String> _availableTags = [];
  bool _isLoading = false;
  bool _loadingTags = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _descriptionController = TextEditingController(
      text: widget.task.description ?? '',
    );
    _selectedPriority = widget.task.priority;
    _selectedDueDate = widget.task.dueDate;
    _selectedAssignedToId = widget.task.assignedToId;
    _selectedTags = List<String>.from(widget.task.tags ?? []);
    _loadTags();
  }

  Future<void> _loadTags() async {
    final controller = context.read<KanbanController>();
    if (controller.teamId == null) return;

    setState(() {
      _loadingTags = true;
    });

    try {
      final response = await _kanbanService.listTags(controller.teamId!);
      if (response.success && response.data != null) {
        setState(() {
          _availableTags = response.data!;
          _loadingTags = false;
        });
      } else {
        setState(() {
          _loadingTags = false;
        });
      }
    } catch (e) {
      setState(() {
        _loadingTags = false;
      });
    }
  }

  List<KanbanUser> _getAvailableUsers() {
    final controller = context.read<KanbanController>();
    final board = controller.board;
    if (board == null) return [];

    // Extrair usuários únicos das tarefas (assignedTo e createdBy)
    final usersMap = <String, KanbanUser>{};
    
    for (final task in board.tasks) {
      if (task.assignedTo != null) {
        usersMap[task.assignedTo!.id] = task.assignedTo!;
      }
      if (task.createdBy != null) {
        usersMap[task.createdBy!.id] = task.createdBy!;
      }
    }

    // Se a tarefa atual tem assignedTo, garantir que está na lista
    if (widget.task.assignedTo != null) {
      usersMap[widget.task.assignedTo!.id] = widget.task.assignedTo!;
    }

    return usersMap.values.toList();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedDueDate = picked;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    final controller = context.read<KanbanController>();

    final success = await controller.updateTask(
      widget.task.id,
      UpdateTaskDto(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        priority: _selectedPriority?.name,
        dueDate: _selectedDueDate,
        assignedToId: _selectedAssignedToId,
        tags: _selectedTags.isNotEmpty ? _selectedTags : null,
      ),
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      if (success) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tarefa atualizada com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(controller.error ?? 'Erro ao atualizar tarefa'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
                  Icons.edit,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Editar Tarefa',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          // Form
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Título
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Título *',
                        hintText: 'Digite o título da tarefa',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Título é obrigatório';
                        }
                        return null;
                      },
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 16),
                    // Descrição
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Descrição',
                        hintText: 'Digite a descrição da tarefa',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 16),
                    // Responsável
                    DropdownButtonFormField<String>(
                      value: _selectedAssignedToId,
                      decoration: const InputDecoration(
                        labelText: 'Responsável',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('Sem responsável'),
                        ),
                        ..._getAvailableUsers().map((user) {
                          return DropdownMenuItem<String>(
                            value: user.id,
                            child: Row(
                              children: [
                                if (user.avatar != null)
                                  CircleAvatar(
                                    radius: 12,
                                    backgroundImage: NetworkImage(user.avatar!),
                                  )
                                else
                                  CircleAvatar(
                                    radius: 12,
                                    child: Text(
                                      user.name[0].toUpperCase(),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    user.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedAssignedToId = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    // Prioridade
                    DropdownButtonFormField<KanbanPriority>(
                      value: _selectedPriority,
                      decoration: const InputDecoration(
                        labelText: 'Prioridade',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<KanbanPriority>(
                          value: null,
                          child: Text('Sem prioridade'),
                        ),
                        ...KanbanPriority.values.map((priority) {
                          return DropdownMenuItem(
                            value: priority,
                            child: Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: Color(int.parse(
                                      priority.color.replaceFirst('#', '0xFF'),
                                    )),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(priority.label),
                              ],
                            ),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedPriority = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    // Data de vencimento
                    InkWell(
                      onTap: _selectDueDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Data de Vencimento',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _selectedDueDate != null
                                    ? '${_selectedDueDate!.day}/${_selectedDueDate!.month}/${_selectedDueDate!.year}'
                                    : 'Selecione uma data',
                                style: TextStyle(
                                  color: _selectedDueDate != null
                                      ? ThemeHelpers.textColor(context)
                                      : ThemeHelpers.textSecondaryColor(context),
                                ),
                              ),
                            ),
                            if (_selectedDueDate != null)
                              IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  setState(() {
                                    _selectedDueDate = null;
                                  });
                                },
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Tags
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tags',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_loadingTags)
                          const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _availableTags.map((tag) {
                              final isSelected = _selectedTags.contains(tag);
                              return FilterChip(
                                label: Text(tag),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setState(() {
                                    if (selected) {
                                      _selectedTags.add(tag);
                                    } else {
                                      _selectedTags.remove(tag);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        if (_availableTags.isEmpty && !_loadingTags)
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(
                              'Nenhuma tag disponível',
                              style: TextStyle(
                                color: ThemeHelpers.textSecondaryColor(context),
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
          // Actions
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: ThemeHelpers.cardBackgroundColor(context),
              border: Border(
                top: BorderSide(
                  color: ThemeHelpers.borderColor(context),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isLoading ? null : _save,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Salvar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


