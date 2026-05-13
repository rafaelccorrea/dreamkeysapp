import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../controllers/kanban_controller.dart';
import '../models/kanban_models.dart';
import '../services/kanban_service.dart';

/// Bottom sheet para editar o card — layout **editorial**: hierarquia forte,
/// blocos por tema (identidade, fluxo, tags), sem “formulário cinza” genérico.
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
    _selectedTags = KanbanUiTagFilter.visible(widget.task.tags ?? []);
    _loadTags();
    _loadProjectMembers();
  }

  Future<void> _loadTags() async {
    final controller = context.read<KanbanController>();
    if (controller.teamId == null) return;

    setState(() => _loadingTags = true);

    try {
      final response = await _kanbanService.listTags(controller.teamId!);
      if (response.success && response.data != null) {
        if (!mounted) return;
        setState(() {
          _availableTags = KanbanUiTagFilter.visible(response.data!);
          _loadingTags = false;
        });
      } else {
        if (!mounted) return;
        setState(() => _loadingTags = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingTags = false);
    }
  }

  Future<void> _loadProjectMembers() async {
    final controller = context.read<KanbanController>();
    final board = controller.board;

    KanbanProject? project = widget.task.project;
    String? projectId = widget.task.projectId;

    if (project == null && projectId == null) {
      projectId = controller.projectId;
    }

    if (project == null && projectId != null && projectId.isNotEmpty) {
      if (board?.projects != null) {
        try {
          project = board!.projects!.firstWhere((p) => p.id == projectId);
        } catch (_) {}
      }
    }

    if (project != null && project.isPersonal == true) {
      return;
    }

    final finalProjectId = project?.id ?? projectId;
    if (finalProjectId == null || finalProjectId.isEmpty) {
      return;
    }

    try {
      final response = await _kanbanService.getProjectMembers(finalProjectId);
      if (response.success && response.data != null && mounted) {
        setState(() {
          _projectMembers =
              response.data!.map((m) => m.user).toList();
        });
      }
    } catch (_) {}
  }

  List<KanbanUser> _getAvailableUsers() {
    final controller = context.read<KanbanController>();
    final board = controller.board;

    KanbanProject? project = widget.task.project;
    String? projectId = widget.task.projectId;

    if (project == null && projectId == null) {
      projectId = controller.projectId;
    }

    if (project == null && projectId != null && projectId.isNotEmpty) {
      if (board?.projects != null) {
        try {
          project = board!.projects!.firstWhere((p) => p.id == projectId);
        } catch (_) {}
      }
    }

    final isTeamProject = project == null || project.isPersonal != true;
    if (isTeamProject && _projectMembers.isNotEmpty) {
      final usersMap = <String, KanbanUser>{};
      for (final user in _projectMembers) {
        usersMap[user.id] = user;
      }
      if (widget.task.assignedTo != null) {
        usersMap[widget.task.assignedTo!.id] = widget.task.assignedTo!;
      }
      return usersMap.values.toList();
    }

    if (board == null) return [];

    final usersMap = <String, KanbanUser>{};
    for (final task in board.tasks) {
      if (task.assignedTo != null) {
        usersMap[task.assignedTo!.id] = task.assignedTo!;
      }
      if (task.createdBy != null) {
        usersMap[task.createdBy!.id] = task.createdBy!;
      }
    }
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
      setState(() => _selectedDueDate = picked);
    }
  }

  InputDecoration _fieldDecoration(
    BuildContext context, {
    required String label,
    String? hint,
    IconData? prefix,
  }) {
    final accent = _editAccent(context);
    final border = ThemeHelpers.borderColor(context);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefix != null
          ? Icon(prefix, size: 20, color: ThemeHelpers.textSecondaryColor(context))
          : null,
      labelStyle: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 12,
        color: ThemeHelpers.textSecondaryColor(context),
        letterSpacing: 0.2,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: border.withValues(alpha: 0.65)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: border.withValues(alpha: 0.55)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: accent, width: 1.35),
      ),
      filled: true,
      fillColor: ThemeHelpers.backgroundColor(context).withValues(alpha: 0.55),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  String _columnLabel(BuildContext context) {
    try {
      final col = context
          .read<KanbanController>()
          .columns
          .firstWhere((c) => c.id == widget.task.columnId);
      return col.title;
    } catch (_) {
      return 'Etapa';
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

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
        assignedToId: _selectedAssignedToId ?? widget.task.assignedToId,
        tags: _selectedTags.isNotEmpty ? _selectedTags : null,
      ),
    );

    if (mounted) {
      setState(() => _isLoading = false);

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
    final accent = _editAccent(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final sheetH = MediaQuery.sizeOf(context).height * 0.92;
    final columnName = _columnLabel(context);

    return Material(
      color: Colors.transparent,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          height: sheetH,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: ThemeHelpers.cardBackgroundColor(context),
                border: Border(
                  top: BorderSide(
                    color: ThemeHelpers.borderColor(context).withValues(alpha: 0.4),
                  ),
                ),
              ),
              child: Column(
                children: [
                  Container(height: 3, width: double.infinity, color: accent),
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: secondary.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'EDIÇÃO',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  letterSpacing: 2.4,
                                  fontWeight: FontWeight.w900,
                                  color: accent,
                                  fontSize: 10,
                                  height: 1,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Editar negociação',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.35,
                                  height: 1.05,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    Icons.view_column_outlined,
                                    size: 14,
                                    color: secondary,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      columnName,
                                      style: theme.textTheme.labelMedium?.copyWith(
                                        color: secondary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close_rounded, color: secondary),
                          onPressed: () => Navigator.of(context).pop(),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _EditSectionHeader(
                              overline: 'IDENTIDADE',
                              title: 'Título e briefing',
                              accent: accent,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _titleController,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                              ),
                              decoration: _fieldDecoration(
                                context,
                                label: 'Título',
                                hint: 'Nome visível no funil',
                                prefix: Icons.title_rounded,
                              ).copyWith(
                                floatingLabelBehavior: FloatingLabelBehavior.always,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Título é obrigatório';
                                }
                                return null;
                              },
                              textCapitalization: TextCapitalization.sentences,
                            ),
                            const SizedBox(height: 18),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  'BRIEFING',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    letterSpacing: 2.2,
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
                                    color: ThemeHelpers.borderColor(context)
                                        .withValues(alpha: 0.35),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Container(
                                    width: 3,
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _descriptionController,
                                      minLines: 4,
                                      maxLines: 8,
                                      style: theme.textTheme.bodyLarge?.copyWith(
                                        height: 1.5,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: -0.05,
                                      ),
                                      decoration: InputDecoration(
                                        hintText:
                                            'Contexto, próximos passos, observações…',
                                        hintStyle: TextStyle(
                                          color: secondary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                      textCapitalization:
                                          TextCapitalization.sentences,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 28),
                            _EditSectionHeader(
                              overline: 'FLUXO',
                              title: 'Responsável, prioridade e prazo',
                              accent: accent,
                            ),
                            const SizedBox(height: 14),
                            Builder(
                              builder: (context) {
                                final isPersonal =
                                    widget.task.project?.isPersonal == true;
                                return IgnorePointer(
                                  ignoring: isPersonal,
                                  child: Opacity(
                                    opacity: isPersonal ? 0.55 : 1,
                                    child: DropdownButtonFormField<String>(
                                      initialValue: _selectedAssignedToId,
                                      isExpanded: true,
                                      menuMaxHeight: 360,
                                      borderRadius: BorderRadius.circular(16),
                                      dropdownColor:
                                          ThemeHelpers.cardBackgroundColor(context),
                                      icon: Icon(
                                        Icons.unfold_more_rounded,
                                        color: secondary,
                                      ),
                                      decoration: _fieldDecoration(
                                        context,
                                        label: 'Responsável',
                                        hint: 'Quem conduz o card',
                                        prefix: Icons.person_outline_rounded,
                                      ).copyWith(
                                        helperText: isPersonal
                                            ? 'Projetos pessoais: responsável fixo.'
                                            : null,
                                        helperMaxLines: 2,
                                      ),
                                      items: _getAvailableUsers().map((user) {
                                        return DropdownMenuItem<String>(
                                          value: user.id,
                                          child: Row(
                                            children: [
                                              CircleAvatar(
                                                radius: 14,
                                                backgroundColor: accent
                                                    .withValues(alpha: 0.12),
                                                backgroundImage: user.avatar != null
                                                    ? NetworkImage(user.avatar!)
                                                    : null,
                                                child: user.avatar == null
                                                    ? Text(
                                                        user.name.isNotEmpty
                                                            ? user.name[0]
                                                                .toUpperCase()
                                                            : '?',
                                                        style: const TextStyle(
                                                          fontSize: 13,
                                                          fontWeight: FontWeight.w800,
                                                        ),
                                                      )
                                                    : null,
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  user.name,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: theme.textTheme.bodyMedium
                                                      ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
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
                                      onChanged: isPersonal
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
                            const SizedBox(height: 18),
                            Text(
                              'PRIORIDADE',
                              style: theme.textTheme.labelSmall?.copyWith(
                                letterSpacing: 1.6,
                                fontWeight: FontWeight.w800,
                                color: secondary,
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _PriorityChip(
                                  label: 'Sem prioridade',
                                  selected: _selectedPriority == null,
                                  dotColor: const Color(0xFF94A3B8),
                                  onTap: () =>
                                      setState(() => _selectedPriority = null),
                                ),
                                ...KanbanPriority.values.map((p) {
                                  final c = Color(
                                    int.parse(p.color.replaceFirst('#', '0xFF')),
                                  );
                                  return _PriorityChip(
                                    label: p.label,
                                    selected: _selectedPriority == p,
                                    dotColor: c,
                                    onTap: () =>
                                        setState(() => _selectedPriority = p),
                                  );
                                }),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _selectDueDate,
                                borderRadius: BorderRadius.circular(14),
                                child: Ink(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: ThemeHelpers.borderColor(context)
                                          .withValues(alpha: 0.55),
                                    ),
                                    color: ThemeHelpers.backgroundColor(context)
                                        .withValues(alpha: 0.55),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 16,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.event_outlined,
                                        color: accent,
                                        size: 22,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Prazo',
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                color: secondary,
                                                letterSpacing: 0.6,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _selectedDueDate != null
                                                  ? DateFormat(
                                                      "EEEE, d 'de' MMMM",
                                                      'pt_BR',
                                                    ).format(_selectedDueDate!)
                                                  : 'Sem data definida',
                                              style: theme.textTheme.bodyLarge
                                                  ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: -0.2,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (_selectedDueDate != null)
                                        IconButton(
                                          icon: Icon(
                                            Icons.close_rounded,
                                            size: 20,
                                            color: secondary,
                                          ),
                                          onPressed: () => setState(
                                            () => _selectedDueDate = null,
                                          ),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 28),
                            _EditSectionHeader(
                              overline: 'ETIQUETAS',
                              title: 'Tags do card',
                              accent: accent,
                            ),
                            const SizedBox(height: 12),
                            if (_loadingTags)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Center(
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                              )
                            else if (_availableTags.isEmpty)
                              Text(
                                'Nenhuma tag disponível para este time.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: secondary,
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _availableTags.map((tag) {
                                  final sel = _selectedTags.contains(tag);
                                  return FilterChip(
                                    showCheckmark: false,
                                    label: Text(
                                      tag,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5,
                                        color: sel
                                            ? Colors.white
                                            : ThemeHelpers.textColor(context),
                                      ),
                                    ),
                                    selected: sel,
                                    onSelected: (v) {
                                      setState(() {
                                        if (v) {
                                          _selectedTags.add(tag);
                                        } else {
                                          _selectedTags.remove(tag);
                                        }
                                      });
                                    },
                                    selectedColor: accent,
                                    backgroundColor:
                                        ThemeHelpers.backgroundColor(context)
                                            .withValues(alpha: 0.5),
                                    side: BorderSide(
                                      color: sel
                                          ? accent
                                          : ThemeHelpers.borderColor(context)
                                              .withValues(alpha: 0.55),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                  );
                                }).toList(),
                              ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      12,
                      20,
                      12 + MediaQuery.paddingOf(context).bottom,
                    ),
                    decoration: BoxDecoration(
                      color: ThemeHelpers.cardBackgroundColor(context),
                      border: Border(
                        top: BorderSide(
                          color: ThemeHelpers.borderColor(context)
                              .withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed:
                              _isLoading ? null : () => Navigator.of(context).pop(),
                          child: Text(
                            'Cancelar',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: secondary,
                            ),
                          ),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: _isLoading ? null : _save,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_rounded, size: 20),
                          label: Text(
                            _isLoading ? 'Salvando…' : 'Salvar alterações',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Editorial widgets
// ---------------------------------------------------------------------------

Color _editAccent(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
}

class _EditSectionHeader extends StatelessWidget {
  final String overline;
  final String title;
  final Color accent;

  const _EditSectionHeader({
    required this.overline,
    required this.title,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(width: 4, height: 14, color: accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
      ],
    );
  }
}

class _PriorityChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color dotColor;
  final VoidCallback onTap;

  const _PriorityChip({
    required this.label,
    required this.selected,
    required this.dotColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _editAccent(context);
    final border = ThemeHelpers.borderColor(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? accent : border.withValues(alpha: 0.55),
              width: selected ? 1.35 : 1,
            ),
            color: selected
                ? accent.withValues(alpha: 0.12)
                : ThemeHelpers.backgroundColor(context).withValues(alpha: 0.45),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
