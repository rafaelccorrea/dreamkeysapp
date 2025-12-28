import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/kanban_models.dart';
import '../controllers/kanban_controller.dart';

/// Modal para criar tarefa
class CreateTaskModal extends StatefulWidget {
  final String columnId;
  final String teamId;

  const CreateTaskModal({
    super.key,
    required this.columnId,
    required this.teamId,
  });

  @override
  State<CreateTaskModal> createState() => _CreateTaskModalState();
}

class _CreateTaskModalState extends State<CreateTaskModal> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  KanbanPriority? _selectedPriority;
  DateTime? _selectedDueDate;
  bool _isLoading = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
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

    final success = await controller.createTask(
      CreateTaskDto(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        columnId: widget.columnId,
        priority: _selectedPriority,
        dueDate: _selectedDueDate,
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
            content: Text('Tarefa criada com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(controller.error ?? 'Erro ao criar tarefa'),
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
                  Icons.add_task,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Nova Tarefa',
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
                    // Prioridade
                    DropdownButtonFormField<KanbanPriority>(
                      value: _selectedPriority,
                      decoration: const InputDecoration(
                        labelText: 'Prioridade',
                        border: OutlineInputBorder(),
                      ),
                      items: KanbanPriority.values.map((priority) {
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
                      }).toList(),
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
                      : const Text('Criar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

