import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/kanban_subtask_models.dart';
import '../services/kanban_subtask_service.dart';
import 'subtask_visual_helpers.dart';

/// Identidade cromática da aba "Tarefas" do card — teal/cyan. O vermelho
/// fica reservado pra marca / erro / destrutivo / atraso.
const Color kSubTaskAccent = Color(0xFF14B8A6);

/// Verde canônico de confirmar/salvar da casa.
const Color kConfirmGreen = Color(0xFF059669);

/// Resultado do bottom sheet de criação — `null` se cancelado, instância
/// preenchida quando a subtarefa é criada com sucesso.
class CreateSubTaskResult {
  final KanbanSubTask subtask;
  const CreateSubTaskResult(this.subtask);
}

/// Bottom sheet de **criação** de subtarefa (checklist) dentro de um card
/// do Kanban. Paridade funcional com `CreateSubTaskPage.tsx` do web, mas
/// como **modal** mais natural pra mobile.
Future<CreateSubTaskResult?> showCreateSubTaskSheet({
  required BuildContext context,
  required String taskId,
  String? parentCardTitle,
}) async {
  final created = await _showSubTaskFormSheet(
    context: context,
    taskId: taskId,
    parentCardTitle: parentCardTitle,
    initial: null,
  );
  return created == null ? null : CreateSubTaskResult(created);
}

/// Bottom sheet de **edição** da subtarefa — mesma anatomia do de criação,
/// com os campos pré-preenchidos e salvamento via `PUT /kanban/subtasks/:id`.
/// Devolve a subtarefa atualizada, ou `null` se o usuário cancelou.
Future<KanbanSubTask?> showEditSubTaskSheet({
  required BuildContext context,
  required KanbanSubTask subtask,
  String? parentCardTitle,
}) {
  return _showSubTaskFormSheet(
    context: context,
    taskId: subtask.taskId,
    parentCardTitle: parentCardTitle,
    initial: subtask,
  );
}

Future<KanbanSubTask?> _showSubTaskFormSheet({
  required BuildContext context,
  required String taskId,
  required String? parentCardTitle,
  required KanbanSubTask? initial,
}) {
  final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
  return showModalBottomSheet<KanbanSubTask>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: ThemeHelpers.cardBackgroundColor(context),
    constraints: BoxConstraints(maxHeight: maxHeight),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) => _SubTaskFormSheet(
      taskId: taskId,
      parentCardTitle: parentCardTitle,
      initial: initial,
    ),
  );
}

class _SubTaskFormSheet extends StatefulWidget {
  final String taskId;
  final String? parentCardTitle;
  final KanbanSubTask? initial;

  const _SubTaskFormSheet({
    required this.taskId,
    required this.parentCardTitle,
    required this.initial,
  });

  @override
  State<_SubTaskFormSheet> createState() => _SubTaskFormSheetState();
}

class _SubTaskFormSheetState extends State<_SubTaskFormSheet> {
  static const int _kTitleMax = 200;
  static const int _kDescMax = 4000;

  late final TextEditingController _titleController;
  late final TextEditingController _descController;

  SubTaskType? _selectedType;
  DateTime? _dueDate;
  TimeOfDay? _dueTime;
  bool _submitting = false;
  String? _formError;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _titleController = TextEditingController(text: initial?.title ?? '');
    _descController = TextEditingController(text: initial?.description ?? '');
    _selectedType = initial?.taskType;
    _dueDate = initial?.dueDate?.toLocal();
    _dueTime = _parseTime(initial?.dueTime);
  }

  static TimeOfDay? _parseTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parts = raw.trim().split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return TimeOfDay(hour: h, minute: m);
  }

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

    final title = _titleController.text.trim();
    final desc = _descController.text.trim();
    final dueTimeStr = _dueTime == null ? null : _fmtTime(_dueTime!);

    if (_isEdit) {
      final initial = widget.initial!;
      final dto = UpdateSubTaskDto(
        title: title,
        description: desc,
        dueDate: _dueDate,
        clearDueDate: _dueDate == null && initial.dueDate != null,
        dueTime: dueTimeStr,
        clearDueTime: dueTimeStr == null && (initial.dueTime ?? '').isNotEmpty,
        taskType: _selectedType,
        clearTaskType: _selectedType == null && initial.taskType != null,
      );
      final res =
          await KanbanSubtaskService.instance.updateSubTask(initial.id, dto);
      if (!mounted) return;
      if (res.success && res.data != null) {
        Navigator.of(context).pop(res.data!);
      } else {
        setState(() {
          _submitting = false;
          _formError = res.message ?? 'Não foi possível salvar a tarefa.';
        });
      }
      return;
    }

    final dto = CreateSubTaskDto(
      title: title,
      description: desc.isEmpty ? null : desc,
      dueDate: _dueDate,
      dueTime: dueTimeStr,
      taskType: _selectedType,
    );
    final res =
        await KanbanSubtaskService.instance.createSubTask(widget.taskId, dto);
    if (!mounted) return;
    if (res.success && res.data != null) {
      Navigator.of(context).pop(res.data!);
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
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final viewInsets = MediaQuery.viewInsetsOf(context);

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SubTaskSheetGrabber(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
            child: _buildHeader(theme),
          ),
          Flexible(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _label('Título', required: true),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _titleController,
                    autofocus: !_isEdit,
                    maxLength: _kTitleMax,
                    maxLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
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
                          accent: kSubTaskAccent,
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
                          accent: kSubTaskAccent,
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
                    textCapitalization: TextCapitalization.sentences,
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
                        border:
                            Border.all(color: danger.withValues(alpha: 0.22)),
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
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
          _buildFooter(theme),
        ],
      ),
    );
  }

  Widget _buildFooter(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.35),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: _submitting ? null : () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                // O tema global pinta TextButton de vermelho — forçamos o
                // cinza aqui: "Cancelar" nunca é ação destrutiva.
                foregroundColor: ThemeHelpers.textSecondaryColor(context),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
                textStyle: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: const Text('Cancelar'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _canSubmit ? _submit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: kConfirmGreen,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    kConfirmGreen.withValues(alpha: 0.35),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.75),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
                textStyle: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w900,
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
                  : Icon(_isEdit ? LucideIcons.check : LucideIcons.plus,
                      size: 18),
              label: Text(
                _submitting
                    ? (_isEdit ? 'Salvando…' : 'Criando…')
                    : (_isEdit ? 'Salvar' : 'Criar tarefa'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final subtitle = _isEdit
        ? widget.initial!.title
        : (widget.parentCardTitle == null || widget.parentCardTitle!.isEmpty
            ? 'Adicionar tarefa ao card'
            : 'No card "${widget.parentCardTitle}"');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            gradient: const LinearGradient(
              colors: [kSubTaskAccent, Color(0xFF0891B2)],
            ),
            boxShadow: [
              BoxShadow(
                color: kSubTaskAccent.withValues(alpha: 0.28),
                blurRadius: 12,
                offset: const Offset(0, 6),
                spreadRadius: -3,
              ),
            ],
          ),
          child: Icon(
            _isEdit ? LucideIcons.pencil : LucideIcons.checkSquare,
            color: Colors.white,
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isEdit ? 'EDITAR TAREFA' : 'NOVA TAREFA',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: kSubTaskAccent,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
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
        const SizedBox(width: 8),
        IconButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          visualDensity: VisualDensity.compact,
          tooltip: 'Fechar',
          icon: Icon(
            LucideIcons.x,
            size: 18,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
        ),
      ],
    );
  }

  Widget _label(String text, {bool required = false}) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Flexible(
          child: Text(
            text.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
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

/// Grabber padrão da casa — 42×4, centralizado, com respiro acima/abaixo.
class SubTaskSheetGrabber extends StatelessWidget {
  const SubTaskSheetGrabber({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 10),
      child: Center(
        child: Container(
          width: 42,
          height: 4,
          decoration: BoxDecoration(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
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
                  color:
                      active ? style.color : ThemeHelpers.textColor(context),
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
