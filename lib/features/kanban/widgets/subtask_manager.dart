import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/kanban_subtask_models.dart';
import '../services/kanban_subtask_service.dart';
import 'create_subtask_sheet.dart';
import 'subtask_card.dart';

/// Gerenciador de subtarefas (checklist) que vive **dentro do detalhe**
/// de um card do Kanban — paridade direta com `SubTaskManager.tsx` do
/// front web.
///
/// Gera carregamento, criação inline, toggle com optimistic update,
/// edição (placeholder) e exclusão. Notifica o pai via [onChanged] para
/// refletir contadores/badges.
class SubTaskManager extends StatefulWidget {
  final String taskId;
  final String? parentCardTitle;
  final VoidCallback? onChanged;

  const SubTaskManager({
    super.key,
    required this.taskId,
    this.parentCardTitle,
    this.onChanged,
  });

  @override
  State<SubTaskManager> createState() => _SubTaskManagerState();
}

class _SubTaskManagerState extends State<SubTaskManager> {
  bool _loading = true;
  String? _error;
  List<KanbanSubTask> _items = const [];
  final Set<String> _busyIds = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await KanbanSubtaskService.instance.getSubTasks(widget.taskId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _items = res.data!;
      } else {
        _error = res.message ?? 'Erro ao carregar tarefas';
      }
    });
  }

  Future<void> _toggle(KanbanSubTask st) async {
    final previous = _items;
    setState(() {
      _busyIds.add(st.id);
      _items = _items
          .map((e) => e.id == st.id
              ? e.copyWith(
                  isCompleted: !e.isCompleted,
                  completedAt: !e.isCompleted ? DateTime.now() : null,
                )
              : e)
          .toList();
    });
    final res = await KanbanSubtaskService.instance.toggleSubTask(st.id);
    if (!mounted) return;
    setState(() => _busyIds.remove(st.id));
    if (!res.success) {
      setState(() => _items = previous);
      _showSnack(res.message ?? 'Falha ao atualizar tarefa');
      return;
    }
    widget.onChanged?.call();
    // Refetch silencioso pra alinhar com servidor (timestamps, etc).
    unawaitedRefresh();
  }

  Future<void> _delete(KanbanSubTask st) async {
    final danger = Theme.of(context).brightness == Brightness.dark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir tarefa'),
        content: Text(
          'Excluir «${st.title}»? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: danger),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final previous = _items;
    setState(() {
      _busyIds.add(st.id);
      _items = _items.where((e) => e.id != st.id).toList();
    });
    final res = await KanbanSubtaskService.instance.deleteSubTask(st.id);
    if (!mounted) return;
    setState(() => _busyIds.remove(st.id));
    if (!res.success) {
      setState(() => _items = previous);
      _showSnack(res.message ?? 'Falha ao excluir tarefa');
      return;
    }
    widget.onChanged?.call();
    _showSnack('Tarefa excluída.', success: true);
  }

  Future<void> _createNew() async {
    final result = await showCreateSubTaskSheet(
      context: context,
      taskId: widget.taskId,
      parentCardTitle: widget.parentCardTitle,
    );
    if (result == null || !mounted) return;
    setState(() {
      _items = [result.subtask, ..._items];
    });
    widget.onChanged?.call();
    _showSnack('Tarefa criada.', success: true);
    unawaitedRefresh();
  }

  void unawaitedRefresh() {
    KanbanSubtaskService.instance.getSubTasks(widget.taskId).then((res) {
      if (!mounted) return;
      if (res.success && res.data != null) {
        setState(() => _items = res.data!);
      }
    });
  }

  void _showSnack(String message, {bool success = false}) {
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = success
        ? (isDark
            ? AppColors.status.greenDarkMode
            : AppColors.status.green)
        : (isDark
            ? AppColors.status.errorDarkMode
            : AppColors.status.error);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        content: Row(
          children: [
            Icon(
              success ? LucideIcons.checkCircle2 : LucideIcons.alertCircle,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark
        ? const Color(0xFFFF4D67)
        : AppColors.primary.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(theme, accent),
          const SizedBox(height: 12),
          if (_loading && _items.isEmpty) _buildSkeleton(),
          if (_error != null && _items.isEmpty) _buildError(),
          if (!_loading && _items.isEmpty && _error == null) _buildEmpty(),
          if (_items.isNotEmpty) ...[
            for (var i = 0; i < _items.length; i++) ...[
              SubTaskCard(
                subtask: _items[i],
                busy: _busyIds.contains(_items[i].id),
                onToggle: () => _toggle(_items[i]),
                onDelete: () => _delete(_items[i]),
                // edição inline ainda não está no escopo desta primeira
                // entrega — abrir como sheet de edição é o próximo passo
                // natural (paridade `EditSubTaskPage` do web).
                onEdit: null,
              ),
              if (i < _items.length - 1) const SubTaskDivider(),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, Color accent) {
    final pending = _items.where((e) => !e.isCompleted).length;
    final total = _items.length;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [accent, const Color(0xFF7C3AED)],
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.28),
                blurRadius: 10,
                offset: const Offset(0, 5),
                spreadRadius: -2,
              ),
            ],
          ),
          child: const Icon(LucideIcons.checkSquare,
              color: Colors.white, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TAREFAS DO CARD',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                total == 0
                    ? 'Sem tarefas ainda'
                    : '$pending pendente${pending == 1 ? '' : 's'} · $total no total',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
        ElevatedButton.icon(
          onPressed: _loading ? null : _createNew,
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            elevation: 0,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          icon: const Icon(LucideIcons.plus, size: 16),
          label: const Text('Nova'),
        ),
      ],
    );
  }

  Widget _buildSkeleton() {
    return Column(
      children: List.generate(
        2,
        (i) => Padding(
          padding: EdgeInsets.only(bottom: i < 1 ? 10 : 0),
          child: SkeletonBox(height: 92, borderRadius: 16),
        ),
      ),
    );
  }

  Widget _buildError() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Icon(LucideIcons.cloudOff, size: 28, color: danger),
          const SizedBox(height: 8),
          Text(
            _error ?? 'Erro ao carregar',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(LucideIcons.refreshCw, size: 14),
            label: const Text('Tentar de novo'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark
        ? const Color(0xFFFF4D67)
        : AppColors.primary.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.32),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  accent.withValues(alpha: 0.18),
                  accent.withValues(alpha: 0.06),
                ],
              ),
              border: Border.all(color: accent.withValues(alpha: 0.32)),
            ),
            child: Icon(LucideIcons.checkSquare, color: accent, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            'Sem tarefas neste card',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Adicione lembretes do que fazer com este lead — ligar, enviar proposta, agendar visita…',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _createNew,
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              elevation: 0,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(LucideIcons.plus, size: 16),
            label: const Text('Criar primeira tarefa'),
          ),
        ],
      ),
    );
  }
}
