import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/kanban_models.dart';
import '../controllers/kanban_controller.dart';

/// Modal para editar coluna
class EditColumnModal extends StatefulWidget {
  final KanbanColumn column;

  const EditColumnModal({
    super.key,
    required this.column,
  });

  @override
  State<EditColumnModal> createState() => _EditColumnModalState();
}

class _EditColumnModalState extends State<EditColumnModal> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  String? _selectedColor;
  bool _isLoading = false;

  final List<String> _colorOptions = [
    '#3B82F6', // Azul
    '#10B981', // Verde
    '#F59E0B', // Laranja
    '#EF4444', // Vermelho
    '#8B5CF6', // Roxo
    '#EC4899', // Rosa
    '#06B6D4', // Ciano
    '#84CC16', // Lima
  ];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.column.title);
    _descriptionController = TextEditingController(
      text: widget.column.description ?? '',
    );
    _selectedColor = widget.column.color ?? _colorOptions[0];
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    final controller = context.read<KanbanController>();

    final success = await controller.updateColumn(
      widget.column.id,
      UpdateColumnDto(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        color: _selectedColor,
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
            content: Text('Coluna atualizada com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(controller.error ?? 'Erro ao atualizar coluna'),
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
                    'Editar Coluna',
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
          Padding(
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
                      hintText: 'Ex: A Fazer, Em Progresso, Concluído',
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
                      hintText: 'Descrição opcional da coluna',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 16),
                  // Cor
                  Text(
                    'Cor',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: _colorOptions.map((color) {
                      final isSelected = _selectedColor == color;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedColor = color;
                          });
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Color(int.parse(
                              color.replaceFirst('#', '0xFF'),
                            )),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: isSelected
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 20,
                                )
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                ],
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


