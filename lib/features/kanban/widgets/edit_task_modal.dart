import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/kanban_models.dart';
import '../controllers/kanban_controller.dart';
import '../services/kanban_service.dart';

/// Modal para editar tarefa
class EditTaskModal extends StatefulWidget {
  final KanbanTask task;

  const EditTaskModal({super.key, required this.task});

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
  List<KanbanUser> _projectMembers = [];
  bool _loadingMembers = false;

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
    _loadProjectMembers();
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

  Future<void> _loadProjectMembers() async {
    debugPrint('👥 [EDIT_TASK_MODAL] _loadProjectMembers - Iniciando');
    
    final controller = context.read<KanbanController>();
    final board = controller.board;
    
    // Tentar obter projeto do objeto task primeiro
    KanbanProject? project = widget.task.project;
    String? projectId = widget.task.projectId;
    
    debugPrint('👥 [EDIT_TASK_MODAL] Estado inicial:');
    debugPrint('   - task.project: ${project != null ? "existe" : "null"}');
    debugPrint('   - task.projectId: ${projectId ?? "null"}');
    debugPrint('   - controller.projectId: ${controller.projectId ?? "null"}');
    
    // Se o projeto não está populado na tarefa, usar o projectId do controller (projeto selecionado)
    if (project == null && projectId == null) {
      projectId = controller.projectId;
      debugPrint('👥 [EDIT_TASK_MODAL] Usando projectId do controller: $projectId');
    }
    
    // Se ainda não temos projeto, tentar buscar da lista de projetos do board
    if (project == null && projectId != null && projectId.isNotEmpty) {
      debugPrint('👥 [EDIT_TASK_MODAL] Projeto não está populado, buscando do board...');
      
      if (board != null && board.projects != null) {
        debugPrint('👥 [EDIT_TASK_MODAL] Board tem ${board.projects!.length} projetos');
        try {
          project = board.projects!.firstWhere(
            (p) => p.id == projectId,
          );
          debugPrint('👥 [EDIT_TASK_MODAL] ✅ Projeto encontrado no board: ${project.name}');
        } catch (e) {
          debugPrint('👥 [EDIT_TASK_MODAL] ❌ Projeto não encontrado no board: $e');
        }
      } else {
        debugPrint('👥 [EDIT_TASK_MODAL] ⚠️ Board ou lista de projetos é null');
      }
    }
    
    debugPrint('👥 [EDIT_TASK_MODAL] Projeto final:');
    debugPrint('   - project: ${project != null ? "existe" : "null"}');
    debugPrint('   - projectId: ${projectId ?? "null"}');
    if (project != null) {
      debugPrint('   - project.id: ${project.id}');
      debugPrint('   - project.name: ${project.name}');
      debugPrint('   - project.isPersonal: ${project.isPersonal}');
    }
    
    // Se não há projeto, não carregar membros
    if (project == null) {
      if (projectId != null && projectId.isNotEmpty) {
        debugPrint('👥 [EDIT_TASK_MODAL] ⚠️ Temos projectId mas projeto não foi encontrado');
        debugPrint('👥 [EDIT_TASK_MODAL] Tentando carregar membros diretamente com projectId: $projectId');
        // Mesmo sem o objeto projeto, podemos tentar carregar membros se temos o ID
        // Mas precisamos verificar se é pessoal primeiro - vamos assumir que não é pessoal se não encontramos o objeto
      } else {
        debugPrint('👥 [EDIT_TASK_MODAL] ⚠️ Projeto é null e projectId também, não carregando membros');
        return;
      }
    } else {
      // Se temos o objeto projeto, verificar se é pessoal
      if (project.isPersonal == true) {
        debugPrint('👥 [EDIT_TASK_MODAL] ⚠️ Projeto é pessoal, não carregando membros');
        return;
      }
    }

    // Se chegamos aqui, temos um projectId válido (mesmo sem o objeto projeto)
    final finalProjectId = project?.id ?? projectId;
    if (finalProjectId == null || finalProjectId.isEmpty) {
      debugPrint('👥 [EDIT_TASK_MODAL] ❌ Não temos projectId válido para carregar membros');
      return;
    }

    debugPrint('👥 [EDIT_TASK_MODAL] ✅ Carregando membros do projeto...');
    debugPrint('   - projectId: $finalProjectId');

    setState(() {
      _loadingMembers = true;
    });

    try {
      debugPrint('👥 [EDIT_TASK_MODAL] Chamando _kanbanService.getProjectMembers($finalProjectId)');
      final response = await _kanbanService.getProjectMembers(finalProjectId);
      
      debugPrint('👥 [EDIT_TASK_MODAL] Resposta recebida:');
      debugPrint('   - success: ${response.success}');
      debugPrint('   - statusCode: ${response.statusCode}');
      debugPrint('   - message: ${response.message}');
      debugPrint('   - data: ${response.data != null ? "${response.data!.length} membros" : "null"}');
      
      if (response.success && response.data != null) {
        debugPrint('👥 [EDIT_TASK_MODAL] ✅ ${response.data!.length} membros carregados');
        setState(() {
          // Converter ProjectMember para KanbanUser
          _projectMembers = response.data!
              .map((member) {
                debugPrint('   - Membro: ${member.user.name} (${member.user.id}) - Role: ${member.role}');
                return member.user;
              })
              .toList();
          _loadingMembers = false;
        });
        debugPrint('👥 [EDIT_TASK_MODAL] ✅ _projectMembers atualizado com ${_projectMembers.length} usuários');
      } else {
        debugPrint('👥 [EDIT_TASK_MODAL] ❌ Erro ao carregar membros: ${response.message}');
        setState(() {
          _loadingMembers = false;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('👥 [EDIT_TASK_MODAL] ❌ Exceção ao carregar membros: $e');
      debugPrint('👥 [EDIT_TASK_MODAL] StackTrace: $stackTrace');
      setState(() {
        _loadingMembers = false;
      });
    }
  }

  List<KanbanUser> _getAvailableUsers() {
    debugPrint('👥 [EDIT_TASK_MODAL] _getAvailableUsers - Iniciando');
    
    final controller = context.read<KanbanController>();
    final board = controller.board;
    
    // Tentar obter projeto do objeto task primeiro
    KanbanProject? project = widget.task.project;
    String? projectId = widget.task.projectId;
    
    // Se o projeto não está populado na tarefa, usar o projectId do controller
    if (project == null && projectId == null) {
      projectId = controller.projectId;
      debugPrint('👥 [EDIT_TASK_MODAL] Usando projectId do controller: $projectId');
    }
    
    // Se o projeto não está populado, tentar buscar da lista de projetos do board
    if (project == null && projectId != null && projectId.isNotEmpty) {
      if (board != null && board.projects != null) {
        try {
          project = board.projects!.firstWhere(
            (p) => p.id == projectId,
          );
          debugPrint('👥 [EDIT_TASK_MODAL] ✅ Projeto encontrado no board: ${project.name}');
        } catch (e) {
          debugPrint('👥 [EDIT_TASK_MODAL] ⚠️ Projeto não encontrado no board: $e');
        }
      }
    }
    
    debugPrint('👥 [EDIT_TASK_MODAL] Estado atual:');
    debugPrint('   - project: ${project != null ? "existe" : "null"}');
    debugPrint('   - project.isPersonal: ${project?.isPersonal}');
    debugPrint('   - projectId: ${projectId ?? "null"}');
    debugPrint('   - _projectMembers.length: ${_projectMembers.length}');
    
    // Se é projeto de equipe (ou temos membros carregados), usar membros do projeto
    // Verificamos se não é pessoal OU se temos membros carregados (mesmo sem objeto projeto)
    final isTeamProject = project == null || project.isPersonal != true;
    if (isTeamProject && _projectMembers.isNotEmpty) {
      debugPrint('👥 [EDIT_TASK_MODAL] ✅ Usando membros do projeto (${_projectMembers.length} membros)');
      // Garantir que o responsável atual está na lista
      final usersMap = <String, KanbanUser>{};
      for (final user in _projectMembers) {
        usersMap[user.id] = user;
      }
      if (widget.task.assignedTo != null) {
        debugPrint('👥 [EDIT_TASK_MODAL] Adicionando responsável atual: ${widget.task.assignedTo!.name}');
        usersMap[widget.task.assignedTo!.id] = widget.task.assignedTo!;
      }
      final users = usersMap.values.toList();
      debugPrint('👥 [EDIT_TASK_MODAL] Retornando ${users.length} usuários');
      return users;
    }
    
    debugPrint('👥 [EDIT_TASK_MODAL] ⚠️ Usando lógica antiga (extrair das tarefas)');

    // Para projetos pessoais ou quando não há membros, usar lógica antiga
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
        assignedToId:
            _selectedAssignedToId ??
            widget.task.assignedToId, // Sempre deve ter um responsável
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
                Icon(Icons.edit, color: theme.colorScheme.primary),
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
                    Builder(
                      builder: (context) {
                        final isPersonalProject =
                            widget.task.project?.isPersonal == true;
                        return IgnorePointer(
                          ignoring: isPersonalProject,
                          child: Opacity(
                            opacity: isPersonalProject ? 0.6 : 1.0,
                            child: DropdownButtonFormField<String>(
                              value: _selectedAssignedToId,
                              decoration: InputDecoration(
                                labelText: 'Responsável *',
                                border: const OutlineInputBorder(),
                                helperText: isPersonalProject
                                    ? 'Não é possível alterar o responsável em projetos pessoais'
                                    : null,
                              ),
                              items: _getAvailableUsers().map((user) {
                                return DropdownMenuItem<String>(
                                  value: user.id,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (user.avatar != null)
                                        CircleAvatar(
                                          radius: 12,
                                          backgroundImage: NetworkImage(
                                            user.avatar!,
                                          ),
                                        )
                                      else
                                        CircleAvatar(
                                          radius: 12,
                                          child: Text(
                                            user.name[0].toUpperCase(),
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          user.name,
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Responsável é obrigatório';
                                }
                                return null;
                              },
                              onChanged: isPersonalProject
                                  ? null
                                  : (value) {
                                      setState(() {
                                        _selectedAssignedToId = value;
                                      });
                                    },
                            ),
                          ),
                        );
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
                                    color: Color(
                                      int.parse(
                                        priority.color.replaceFirst(
                                          '#',
                                          '0xFF',
                                        ),
                                      ),
                                    ),
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
                                      : ThemeHelpers.textSecondaryColor(
                                          context,
                                        ),
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
                top: BorderSide(color: ThemeHelpers.borderColor(context)),
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
