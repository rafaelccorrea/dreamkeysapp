import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/kanban_subtask_models.dart';
import '../services/kanban_subtask_service.dart';
import 'subtask_visual_helpers.dart';

/// Resultado do bottom sheet de criação — `null` se cancelado, instância
/// preenchida quando a subtarefa é criada com sucesso.
class CreateSubTaskResult {
  final KanbanSubTask subtask;
  const CreateSubTaskResult(this.subtask);
}

/// Bottom sheet de criação de **subtarefa (checklist) dentro de um card**
/// do Kanban. Paridade funcional com `CreateSubTaskPage.tsx` do web, mas
/// como **modal** mais natural pra mobile.
///
/// Use sempre que precisar criar uma tarefa atrelada a um cartão:
///   - Dentro do detalhe do card (aba "Tarefas").
///   - Na tela global "Lista de tarefas" via "Nova tarefa" → seleciona card → abre este sheet.
Future<CreateSubTaskResult?> showCreateSubTaskSheet({
  required BuildContext context,
  required String taskId,
  String? parentCardTitle,
}) {
  return showModalBottomSheet<CreateSubTaskResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: ThemeHelpers.cardBackgroundColor(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) => _CreateSubTaskSheet(
      taskId: taskId,
      parentCardTitle: parentCardTitle,
    ),
  );
}

class _CreateSubTaskSheet extends StatefulWidget {
  final String taskId;
  final String? parentCardTitle;

  const _CreateSubTaskSheet({
    required this.taskId,
    required this.parentCardTitle,
  });

  @override
  State<_CreateSubTaskSheet> createState() => _CreateSubTaskSheetState();
}

class _CreateSubTaskSheetState extends State<_CreateSubTaskSheet> {
  static const int _kTitleMax = 200;
  static const int _kDescMax = 4000;

  final _titleController = TextEditingController();
  final _descController = TextEditingController();

  SubTaskType? _selectedType;
  DateTime? _dueDate;
  TimeOfDay? _dueTime;
  bool _submitting = false;
  String? _formError;

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _titleController.text.trim().isNotEmpty &&
      _titleController.text.trim().length <= _kTitleMax &&
      !_submitting;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      locale: const Locale('pt', 'BR'),
    );
    if (picked != null && mounted) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _dueTime ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null && mounted) {
      setState(() => _dueTime = picked);
    }
  }

  String _fmtDate(DateTime d) =>
      DateFormat("d 'de' MMM, EEEE", 'pt_BR').format(d);

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _submitting = true;
      _formError = null;
    });
    final dueTimeStr = _dueTime == null ? null : _fmtTime(_dueTime!);
    final dto = CreateSubTaskDto(
      title: _titleController.text.trim(),
      description: _descController.text.trim().isEmpty
          ? null
          : _descController.text.trim(),
      dueDate: _dueDate,
      dueTime: dueTimeStr,
      taskType: _selectedType,
    );
    final res =
        await KanbanSubtaskService.instance.createSubTask(widget.taskId, dto);
    if (!mounted) return;
    if (res.success && res.data != null) {
      Navigator.of(context).pop(CreateSubTaskResult(res.data!));
    } else {
      setState(() {
        _submitting = false;
        _formError = res.message ?? 'Não foi possível criar a tarefa.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark
        ? const Color(0xFFFF4D67)
        : AppColors.primary.primary;
    final danger = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;
    final viewInsets = MediaQuery.viewInsetsOf(context);

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(theme, accent),
            const SizedBox(height: 18),
            _label('Título', required: true),
            const SizedBox(height: 6),
            TextField(
              controller: _titleController,
              autofocus: true,
              maxLength: _kTitleMax,
              maxLines: 1,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Ex.: Retornar ligação, enviar proposta…',
                counterText: '',
                isDense: true,
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: ThemeHelpers.textColor(context),
              ),
            ),
            const SizedBox(height: 18),
            _label('Tipo de atividade'),
            const SizedBox(height: 8),
            _TypeChips(
              selected: _selectedType,
              onChanged: (t) => setState(() => _selectedType = t),
            ),
            const SizedBox(height: 18),
            _label('Prazo'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _PickerTile(
                    icon: LucideIcons.calendar,
                    label: _dueDate == null ? 'Data' : _fmtDate(_dueDate!),
                    isSelected: _dueDate != null,
                    accent: accent,
                    onTap: _pickDate,
                    onClear: _dueDate == null
                        ? null
                        : () => setState(() => _dueDate = null),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PickerTile(
                    icon: LucideIcons.clock,
                    label: _dueTime == null ? 'Hora' : _fmtTime(_dueTime!),
                    isSelected: _dueTime != null,
                    accent: accent,
                    onTap: _pickTime,
                    onClear: _dueTime == null
                        ? null
                        : () => setState(() => _dueTime = null),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _label('Descrição'),
            const SizedBox(height: 6),
            TextField(
              controller: _descController,
              maxLines: 3,
              maxLength: _kDescMax,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Detalhes da tarefa (opcional)…',
                isDense: true,
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: ThemeHelpers.textColor(context),
              ),
            ),
            if (_formError != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: danger.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: danger.withValues(alpha: 0.22)),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.alertCircle, size: 16, color: danger),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _formError!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: danger,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _submitting ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _canSubmit ? _submit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    icon: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(LucideIcons.plus, size: 18),
                    label: Text(_submitting ? 'Criando…' : 'Criar tarefa'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, Color accent) {
    final isDark = theme.brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: [accent, const Color(0xFF7C3AED)],
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: isDark ? 0.32 : 0.22),
                blurRadius: 12,
                offset: const Offset(0, 6),
                spreadRadius: -2,
              ),
            ],
          ),
          child: const Icon(LucideIcons.checkSquare,
              color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'NOVA TAREFA',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.parentCardTitle == null ||
                        widget.parentCardTitle!.isEmpty
                    ? 'Adicionar tarefa ao card'
                    : 'No card "${widget.parentCardTitle}"',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: -0.3,
                  height: 1.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _label(String text, {bool required = false}) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          text.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
        if (required) ...[
          const SizedBox(width: 4),
          Text(
            '*',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.status.error,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ],
    );
  }
}

class _TypeChips extends StatelessWidget {
  final SubTaskType? selected;
  final ValueChanged<SubTaskType?> onChanged;

  const _TypeChips({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          for (final t in SubTaskType.values) ...[
            _Chip(
              type: t,
              active: selected == t,
              onTap: () => onChanged(selected == t ? null : t),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final SubTaskType type;
  final bool active;
  final VoidCallback onTap;

  const _Chip({
    required this.type,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = SubTaskTypeStyle.of(context, type);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? style.color.withValues(alpha: isDark ? 0.22 : 0.14)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.045)
                    : Colors.black.withValues(alpha: 0.035)),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active
                  ? style.color.withValues(alpha: 0.5)
                  : ThemeHelpers.borderLightColor(context),
              width: active ? 1.4 : 1,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: style.color.withValues(alpha: 0.22),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                      spreadRadius: -3,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(style.icon, size: 14, color: style.color),
              const SizedBox(width: 6),
              Text(
                type.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: active
                      ? style.color
                      : ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _PickerTile({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.accent,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
          decoration: BoxDecoration(
            color: isSelected
                ? accent.withValues(alpha: 0.10)
                : ThemeHelpers.cardBackgroundColor(context),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: isSelected
                  ? accent.withValues(alpha: 0.42)
                  : ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 16,
                  color: isSelected
                      ? accent
                      : ThemeHelpers.textSecondaryColor(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: isSelected
                        ? ThemeHelpers.textColor(context)
                        : ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onClear != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  icon: Icon(LucideIcons.x,
                      size: 14,
                      color: ThemeHelpers.textSecondaryColor(context)),
                  onPressed: onClear,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
