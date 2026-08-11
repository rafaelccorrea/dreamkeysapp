import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../controllers/kanban_controller.dart';
import '../models/kanban_subtask_models.dart';
import '../services/kanban_subtask_service.dart';
import 'create_subtask_sheet.dart';
import 'subtask_assignee_sheet.dart';
import 'subtask_card.dart';

/// Critérios de ordenação da lista — paridade 1:1 com o `<select>` do
/// `SubTaskManager.tsx` do web (`createdAt | dueDate | title | position`).
/// A escolha vive só em memória (não persiste entre aberturas do card).
enum _SubTaskSort {
  createdAt('Criação', LucideIcons.clock),
  dueDate('Agendamento', LucideIcons.calendarClock),
  title('Título', LucideIcons.caseSensitive),
  position('Ordem no card', LucideIcons.listOrdered);

  final String label;
  final IconData icon;
  const _SubTaskSort(this.label, this.icon);
}

/// Gerenciador de subtarefas (checklist) que vive **dentro do detalhe**
/// de um card do Kanban — paridade direta com `SubTaskManager.tsx` do
/// front web.
///
/// Cobre carregamento, criação, toggle com optimistic update, **edição**,
/// **atribuição de responsável**, **ordenação** e **reordenação manual**
/// (modo "Ordem no card"), além de exclusão. Notifica o pai via
/// [onChanged] para refletir contadores/badges.
class SubTaskManager extends StatefulWidget {
  final String taskId;
  final String? parentCardTitle;

  /// Funil (projeto) do card pai — usado para listar os membros no seletor
  /// de responsável. Opcional: quando não vier, é deduzido do payload das
  /// subtarefas e, em último caso, do funil ativo no [KanbanController].
  final String? projectId;

  final VoidCallback? onChanged;

  const SubTaskManager({
    super.key,
    required this.taskId,
    this.parentCardTitle,
    this.projectId,
    this.onChanged,
  });

  @override
  State<SubTaskManager> createState() => _SubTaskManagerState();
}

class _SubTaskManagerState extends State<SubTaskManager> {
  /// Identidade da aba Tarefas no modal do card: teal (o vermelho fica
  /// reservado pra marca/erro/destrutivo/atraso).
  static const Color _accent = kSubTaskAccent;

  bool _loading = true;
  String? _error;
  List<KanbanSubTask> _items = const [];
  final Set<String> _busyIds = <String>{};

  _SubTaskSort _sort = _SubTaskSort.createdAt;

  /// Ordem manual do modo "Ordem no card" (id → rank). Nasce do `position`
  /// devolvido pelo backend e passa a ser a verdade local depois de um
  /// arraste/mover bem-sucedido — assim a lista não "pula de volta"
  /// enquanto o servidor propaga as novas posições.
  Map<String, int> _rank = <String, int>{};
  bool _reordering = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ─── Dados ───────────────────────────────────────────────────────────

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
        _rank = _ranksFromPositions(_items);
      } else {
        _error = res.message ?? 'Erro ao carregar tarefas';
      }
    });
  }

  void unawaitedRefresh() {
    KanbanSubtaskService.instance.getSubTasks(widget.taskId).then((res) {
      if (!mounted) return;
      if (res.success && res.data != null) {
        setState(() {
          _items = res.data!;
          _syncRanks();
        });
      }
    });
  }

  Map<String, int> _ranksFromPositions(List<KanbanSubTask> items) {
    final sorted = [...items]..sort((a, b) => a.position.compareTo(b.position));
    return {for (var i = 0; i < sorted.length; i++) sorted[i].id: i};
  }

  /// Preserva a ordem manual já conhecida e anexa os itens novos ao fim,
  /// descartando os que sumiram.
  void _syncRanks() {
    final known = <String, int>{};
    final unknown = <KanbanSubTask>[];
    for (final st in _items) {
      final r = _rank[st.id];
      if (r == null) {
        unknown.add(st);
      } else {
        known[st.id] = r;
      }
    }
    if (known.isEmpty) {
      _rank = _ranksFromPositions(_items);
      return;
    }
    var next = known.values.fold<int>(-1, (m, v) => v > m ? v : m) + 1;
    unknown.sort((a, b) => a.position.compareTo(b.position));
    for (final st in unknown) {
      known[st.id] = next++;
    }
    _rank = known;
  }

  /// Sem prazo vai pro fim da lista quando ordenado por agendamento.
  static int _dueSortKey(KanbanSubTask st) =>
      st.dueDate?.millisecondsSinceEpoch ?? (1 << 62);

  List<KanbanSubTask> get _ordered {
    final arr = [..._items];
    switch (_sort) {
      case _SubTaskSort.position:
        arr.sort((a, b) {
          final ra = _rank[a.id] ?? a.position;
          final rb = _rank[b.id] ?? b.position;
          return ra.compareTo(rb);
        });
        break;
      case _SubTaskSort.title:
        arr.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
        break;
      case _SubTaskSort.dueDate:
        // Sem prazo vai pro fim (idem web: MAX_SAFE_INTEGER).
        arr.sort((a, b) => _dueSortKey(a).compareTo(_dueSortKey(b)));
        break;
      case _SubTaskSort.createdAt:
        arr.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
    }
    return arr;
  }

  void _replaceItem(KanbanSubTask updated) {
    setState(() {
      _items =
          _items.map((e) => e.id == updated.id ? updated : e).toList();
    });
  }

  String? _resolveProjectId(KanbanSubTask st) {
    String? clean(String? v) {
      final t = v?.trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    final fromWidget = clean(widget.projectId);
    if (fromWidget != null) return fromWidget;

    final fromItem = clean(st.parentTask?.projectId);
    if (fromItem != null) return fromItem;

    for (final e in _items) {
      final fromAny = clean(e.parentTask?.projectId);
      if (fromAny != null) return fromAny;
    }

    return clean(KanbanController.instance.projectId);
  }

  // ─── Ações ───────────────────────────────────────────────────────────

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
            // Cancelar nunca é destrutivo — o tema global pinta o
            // TextButton de vermelho, então forçamos o cinza.
            style: TextButton.styleFrom(
              foregroundColor: ThemeHelpers.textSecondaryColor(ctx),
            ),
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
    setState(() => _rank.remove(st.id));
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
      _syncRanks();
    });
    widget.onChanged?.call();
    _showSnack('Tarefa criada.', success: true);
    unawaitedRefresh();
  }

  Future<void> _edit(KanbanSubTask st) async {
    final updated = await showEditSubTaskSheet(
      context: context,
      subtask: st,
      parentCardTitle: widget.parentCardTitle,
    );
    if (updated == null || !mounted) return;
    var merged = updated;
    // A resposta do update nem sempre reidrata o responsável — preserva o
    // que já estava pra não piscar "sem responsável" no cartão.
    if (merged.assignedTo == null && st.assignedTo != null) {
      merged = merged.copyWith(
        assignedTo: st.assignedTo,
        assignedToId: st.assignedToId,
      );
    }
    _replaceItem(merged);
    widget.onChanged?.call();
    _showSnack('Tarefa atualizada.', success: true);
    unawaitedRefresh();
  }

  Future<void> _assign(KanbanSubTask st) async {
    final choice = await showSubTaskAssigneeSheet(
      context: context,
      subtask: st,
      projectId: _resolveProjectId(st),
    );
    if (choice == null || !mounted) return;

    setState(() => _busyIds.add(st.id));
    final service = KanbanSubtaskService.instance;
    final res = choice.isUnassign
        ? await service.unassignSubTask(st.id)
        : await service.assignSubTask(st.id, choice.user!.id);
    if (!mounted) return;
    setState(() => _busyIds.remove(st.id));

    if (!res.success || res.data == null) {
      _showSnack(res.message ?? 'Falha ao definir o responsável');
      return;
    }

    var updated = res.data!;
    // Algumas respostas voltam sem o objeto do usuário embutido — o card
    // mostra o responsável, então preenchemos com quem acabou de ser
    // escolhido pra não piscar "sem responsável".
    if (!choice.isUnassign && updated.assignedTo == null) {
      updated = updated.copyWith(
        assignedTo: choice.user,
        assignedToId: choice.user!.id,
      );
    }
    _replaceItem(updated);
    widget.onChanged?.call();
    _showSnack(
      choice.isUnassign
          ? 'Responsável removido.'
          : 'Responsável: ${choice.user!.name}.',
      success: true,
    );
    unawaitedRefresh();
  }

  Future<void> _openActions(KanbanSubTask st) async {
    final ordered = _ordered;
    final index = ordered.indexWhere((e) => e.id == st.id);
    final manual = _sort == _SubTaskSort.position && ordered.length > 1;
    final action = await showSubTaskActionsSheet(
      context: context,
      subtask: st,
      canMoveUp: manual && index > 0,
      canMoveDown: manual && index >= 0 && index < ordered.length - 1,
    );
    if (action == null || !mounted) return;
    switch (action) {
      case SubTaskItemAction.edit:
        await _edit(st);
        break;
      case SubTaskItemAction.assign:
        await _assign(st);
        break;
      case SubTaskItemAction.moveUp:
        await _move(st, -1);
        break;
      case SubTaskItemAction.moveDown:
        await _move(st, 1);
        break;
      case SubTaskItemAction.delete:
        await _delete(st);
        break;
    }
  }

  /// Move a subtarefa [delta] posições (−1 = sobe, +1 = desce) na ordem
  /// manual do card e persiste via `reorderSubTasks`.
  Future<void> _move(KanbanSubTask st, int delta) async {
    if (_reordering) return;
    final ordered = _ordered;
    final from = ordered.indexWhere((e) => e.id == st.id);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= ordered.length) return;

    HapticFeedback.selectionClick();
    final previousRank = Map<String, int>.from(_rank);
    final reordered = [...ordered];
    final moved = reordered.removeAt(from);
    reordered.insert(to, moved);

    setState(() {
      _reordering = true;
      _busyIds.add(st.id);
      _rank = {
        for (var i = 0; i < reordered.length; i++) reordered[i].id: i,
      };
    });

    final res = await KanbanSubtaskService.instance.reorderSubTasks(
      widget.taskId,
      st.id,
      reordered.map((e) => e.id).toList(),
    );
    if (!mounted) return;
    setState(() {
      _reordering = false;
      _busyIds.remove(st.id);
    });

    if (!res.success) {
      setState(() => _rank = previousRank);
      _showSnack(res.message ?? 'Falha ao reordenar as tarefas');
      return;
    }
    widget.onChanged?.call();
  }

  void _showSnack(String message, {bool success = false}) {
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = success
        ? (isDark ? AppColors.status.greenDarkMode : AppColors.status.green)
        : (isDark ? AppColors.status.errorDarkMode : AppColors.status.error);
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
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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

  // ─── UI ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ordered = _ordered;
    final manual = _sort == _SubTaskSort.position && ordered.length > 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(theme),
          if (_items.length > 1) ...[
            const SizedBox(height: 12),
            _buildSortBar(theme),
          ],
          const SizedBox(height: 12),
          if (_loading && _items.isEmpty) _buildSkeleton(),
          if (_error != null && _items.isEmpty) _buildError(),
          if (!_loading && _items.isEmpty && _error == null) _buildEmpty(),
          if (ordered.isNotEmpty) ...[
            for (var i = 0; i < ordered.length; i++) ...[
              _buildItem(ordered[i], i, ordered.length, manual),
              if (i < ordered.length - 1) const SubTaskDivider(),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildItem(
    KanbanSubTask st,
    int index,
    int total,
    bool manual,
  ) {
    final card = SubTaskCard(
      subtask: st,
      busy: _busyIds.contains(st.id),
      onTap: () => _openActions(st),
      onToggle: () => _toggle(st),
      onEdit: () => _edit(st),
      onDelete: () => _delete(st),
    );

    if (!manual) return card;

    // Modo "Ordem no card": rail discreto de setas ao lado do cartão.
    // Optamos por setas em vez de arraste pra não brigar com o scroll do
    // modal nem com o long-press do próprio cartão.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: card),
        const SizedBox(width: 6),
        _ReorderRail(
          canMoveUp: index > 0,
          canMoveDown: index < total - 1,
          busy: _reordering,
          onUp: () => _move(st, -1),
          onDown: () => _move(st, 1),
        ),
      ],
    );
  }

  Widget _buildSortBar(ThemeData theme) {
    return Row(
      children: [
        Icon(
          LucideIcons.arrowUpDown,
          size: 13,
          color: ThemeHelpers.textSecondaryColor(context),
        ),
        const SizedBox(width: 6),
        Text(
          'ORDENAR',
          style: theme.textTheme.labelSmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            fontSize: 9.5,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                for (final s in _SubTaskSort.values) ...[
                  _SortChip(
                    label: s.label,
                    icon: s.icon,
                    active: _sort == s,
                    accent: _accent,
                    onTap: () {
                      if (_sort == s) return;
                      HapticFeedback.selectionClick();
                      setState(() => _sort = s);
                    },
                  ),
                  if (s != _SubTaskSort.values.last) const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme) {
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
            gradient: const LinearGradient(
              // Fala na família da aba: teal → cyan (nada de violeta órfão).
              colors: [_accent, Color(0xFF0891B2)],
            ),
            boxShadow: [
              BoxShadow(
                color: _accent.withValues(alpha: 0.28),
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: _loading ? null : _createNew,
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
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
          child: const SkeletonBox(height: 92, borderRadius: 16),
        ),
      ),
    );
  }

  Widget _buildError() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
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
                  _accent.withValues(alpha: 0.18),
                  _accent.withValues(alpha: 0.06),
                ],
              ),
              border: Border.all(color: _accent.withValues(alpha: 0.32)),
            ),
            child: const Icon(LucideIcons.checkSquare,
                color: _accent, size: 24),
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
              backgroundColor: _accent,
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

// ─── Peças locais ───────────────────────────────────────────────────────

/// Chip discreto de ordenação — mesma gramática dos chips de tipo, num
/// tamanho menor porque é controle, não conteúdo.
class _SortChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  const _SortChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? accent.withValues(alpha: isDark ? 0.18 : 0.11)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active
                  ? accent.withValues(alpha: 0.45)
                  : ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
              width: active ? 1.3 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 12,
                color:
                    active ? accent : ThemeHelpers.textSecondaryColor(context),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: active
                      ? accent
                      : ThemeHelpers.textSecondaryColor(context),
                  fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                  fontSize: 10.5,
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

/// Rail vertical de reordenação — só aparece no modo "Ordem no card".
class _ReorderRail extends StatelessWidget {
  final bool canMoveUp;
  final bool canMoveDown;
  final bool busy;
  final VoidCallback onUp;
  final VoidCallback onDown;

  const _ReorderRail({
    required this.canMoveUp,
    required this.canMoveDown,
    required this.busy,
    required this.onUp,
    required this.onDown,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RailButton(
          icon: LucideIcons.arrowUp,
          tooltip: 'Mover para cima',
          onTap: (canMoveUp && !busy) ? onUp : null,
        ),
        const SizedBox(height: 4),
        _RailButton(
          icon: LucideIcons.arrowDown,
          tooltip: 'Mover para baixo',
          onTap: (canMoveDown && !busy) ? onDown : null,
        ),
      ],
    );
  }
}

class _RailButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _RailButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final tone = ThemeHelpers.textSecondaryColor(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: ThemeHelpers.borderColor(context)
                    .withValues(alpha: enabled ? 0.55 : 0.22),
              ),
            ),
            child: Icon(
              icon,
              size: 14,
              color: tone.withValues(alpha: enabled ? 1 : 0.3),
            ),
          ),
        ),
      ),
    );
  }
}
