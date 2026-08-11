import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/kanban_models.dart';
import '../models/kanban_subtask_models.dart';
import '../services/kanban_service.dart';
import 'create_subtask_sheet.dart' show SubTaskSheetGrabber, kSubTaskAccent, kConfirmGreen;

// ─── Cor estável por pessoa ────────────────────────────────────────────

/// Cor estável derivada do nome — cada pessoa tem a sua. Mesma mecânica e
/// paleta do `_personColor` do chat do CRM (`task_details_modal.dart`),
/// republicada aqui porque lá ela é privada da library. Sem nome → slate.
Color subTaskPersonColor(String? name) {
  if (name == null || name.trim().isEmpty) return const Color(0xFF64748B);
  const palette = [
    Color(0xFF0EA5E9),
    Color(0xFF14B8A6),
    Color(0xFF6366F1),
    Color(0xFFF97316),
    Color(0xFF22C55E),
    Color(0xFFEC4899),
    Color(0xFFA855F7),
    Color(0xFF0891B2),
  ];
  var h = 0;
  for (final c in name.trim().toLowerCase().codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return palette[h % palette.length];
}

/// Iniciais (1–2 letras) do nome, em caixa alta.
String subTaskInitials(String? name) {
  final raw = (name ?? '').trim();
  if (raw.isEmpty) return '?';
  final parts = raw.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return (parts.first.characters.first + parts.last.characters.first)
      .toUpperCase();
}

/// Avatar circular com foto quando existe, senão iniciais sobre a cor
/// estável da pessoa.
class SubTaskPersonAvatar extends StatelessWidget {
  final String? name;
  final String? avatarUrl;
  final double size;

  const SubTaskPersonAvatar({
    super.key,
    required this.name,
    this.avatarUrl,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    final tone = subTaskPersonColor(name);
    final hasAvatar = (avatarUrl ?? '').isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tone.withValues(alpha: 0.16),
        image: hasAvatar
            ? DecorationImage(
                image: NetworkImage(avatarUrl!),
                fit: BoxFit.cover,
              )
            : null,
        border: Border.all(color: tone.withValues(alpha: 0.42), width: 1.2),
      ),
      alignment: Alignment.center,
      child: hasAvatar
          ? null
          : Text(
              subTaskInitials(name),
              style: TextStyle(
                color: tone,
                fontSize: size * 0.36,
                fontWeight: FontWeight.w900,
                height: 1,
                letterSpacing: 0.2,
              ),
            ),
    );
  }
}

// ─── Menu de ações do item ─────────────────────────────────────────────

/// Ações disponíveis no menu de um item da lista de tarefas do card.
enum SubTaskItemAction { edit, assign, moveUp, moveDown, delete }

/// Bottom sheet compacto com as ações do item (editar · responsável ·
/// mover · excluir). Devolve `null` se o usuário fechou sem escolher.
Future<SubTaskItemAction?> showSubTaskActionsSheet({
  required BuildContext context,
  required KanbanSubTask subtask,
  bool canMoveUp = false,
  bool canMoveDown = false,
}) {
  final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
  return showModalBottomSheet<SubTaskItemAction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: ThemeHelpers.cardBackgroundColor(context),
    constraints: BoxConstraints(maxHeight: maxHeight),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final isDark = theme.brightness == Brightness.dark;
      final danger =
          isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
      final assignedName = subtask.assignedTo?.name;

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SubTaskSheetGrabber(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
            child: _SheetHeader(
              eyebrow: 'TAREFA DO CARD',
              title: subtask.title,
              icon: LucideIcons.listChecks,
            ),
          ),
          const SizedBox(height: 14),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ActionRow(
                    icon: LucideIcons.pencil,
                    tone: kSubTaskAccent,
                    label: 'Editar tarefa',
                    hint: 'Título, tipo, prazo e descrição',
                    onTap: () => Navigator.of(ctx).pop(SubTaskItemAction.edit),
                  ),
                  _ActionRow(
                    icon: LucideIcons.userCheck,
                    tone: subTaskPersonColor(assignedName),
                    label: 'Responsável',
                    hint: (assignedName ?? '').isEmpty
                        ? 'Sem responsável definido'
                        : assignedName!,
                    onTap: () =>
                        Navigator.of(ctx).pop(SubTaskItemAction.assign),
                  ),
                  if (canMoveUp)
                    _ActionRow(
                      icon: LucideIcons.arrowUp,
                      tone: const Color(0xFF6366F1),
                      label: 'Mover para cima',
                      hint: 'Sobe uma posição na ordem do card',
                      onTap: () =>
                          Navigator.of(ctx).pop(SubTaskItemAction.moveUp),
                    ),
                  if (canMoveDown)
                    _ActionRow(
                      icon: LucideIcons.arrowDown,
                      tone: const Color(0xFF6366F1),
                      label: 'Mover para baixo',
                      hint: 'Desce uma posição na ordem do card',
                      onTap: () =>
                          Navigator.of(ctx).pop(SubTaskItemAction.moveDown),
                    ),
                  _ActionRow(
                    icon: LucideIcons.trash2,
                    tone: danger,
                    label: 'Excluir tarefa',
                    hint: 'Remove a tarefa deste card',
                    destructive: true,
                    onTap: () =>
                        Navigator.of(ctx).pop(SubTaskItemAction.delete),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
      );
    },
  );
}

// ─── Seletor de responsável ────────────────────────────────────────────

/// Escolha feita no seletor de responsável. [user] nulo significa
/// **remover responsável** (rota `/unassign`).
class SubTaskAssigneeChoice {
  final KanbanUser? user;
  const SubTaskAssigneeChoice(this.user);

  bool get isUnassign => user == null;
}

/// Bottom sheet de **atribuição de responsável** da subtarefa. Lista os
/// membros do funil (projeto) com avatar-inicial em cor estável por nome e
/// oferece a opção "Sem responsável" (desatribuir).
///
/// Devolve `null` quando o usuário cancela/fecha; devolve um
/// [SubTaskAssigneeChoice] quando confirma.
Future<SubTaskAssigneeChoice?> showSubTaskAssigneeSheet({
  required BuildContext context,
  required KanbanSubTask subtask,
  required String? projectId,
}) {
  final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
  return showModalBottomSheet<SubTaskAssigneeChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: ThemeHelpers.cardBackgroundColor(context),
    constraints: BoxConstraints(maxHeight: maxHeight),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) => _AssigneeSheet(subtask: subtask, projectId: projectId),
  );
}

class _AssigneeSheet extends StatefulWidget {
  final KanbanSubTask subtask;
  final String? projectId;

  const _AssigneeSheet({required this.subtask, required this.projectId});

  @override
  State<_AssigneeSheet> createState() => _AssigneeSheetState();
}

class _AssigneeSheetState extends State<_AssigneeSheet> {
  final _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  List<KanbanUser> _people = const [];
  String _query = '';

  /// `null` = "Sem responsável" selecionado.
  String? _selectedId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.subtask.assignedToId ?? widget.subtask.assignedTo?.id;
    _loadMembers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    final projectId = widget.projectId?.trim();
    if (projectId == null || projectId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _people = _seedFromSubtask();
        _error = _people.isEmpty
            ? 'Não foi possível identificar o funil deste card para listar os membros.'
            : null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await KanbanService.instance.getProjectMembers(projectId);
    if (!mounted) return;
    if (res.success && res.data != null) {
      final seen = <String>{};
      final people = <KanbanUser>[];
      // Sem filtro por `isActive`: o payload nem sempre traz o campo e o
      // `fromJson` o resolve como `false`, o que zeraria a lista. Mesmo
      // critério do `transfer_task_sheet`.
      for (final m in res.data!) {
        if (m.user.id.isEmpty || !seen.add(m.user.id)) continue;
        people.add(m.user);
      }
      // Mantém o responsável atual visível mesmo se ele não estiver mais
      // no funil (evita "sumir" o dado que a lista mostra).
      for (final u in _seedFromSubtask()) {
        if (seen.add(u.id)) people.add(u);
      }
      people.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      setState(() {
        _loading = false;
        _people = people;
      });
    } else {
      setState(() {
        _loading = false;
        _people = _seedFromSubtask();
        _error = res.message ?? 'Erro ao carregar os membros do funil';
      });
    }
  }

  List<KanbanUser> _seedFromSubtask() {
    final current = widget.subtask.assignedTo;
    if (current == null || current.id.isEmpty) return const [];
    return [current];
  }

  List<KanbanUser> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _people;
    return _people
        .where((u) =>
            u.name.toLowerCase().contains(q) ||
            u.email.toLowerCase().contains(q))
        .toList();
  }

  bool get _dirty {
    final original =
        widget.subtask.assignedToId ?? widget.subtask.assignedTo?.id;
    return _selectedId != original;
  }

  void _select(String? id) {
    HapticFeedback.selectionClick();
    setState(() => _selectedId = id);
  }

  void _confirm() {
    if (_saving) return;
    setState(() => _saving = true);
    final id = _selectedId;
    KanbanUser? picked;
    if (id != null) {
      for (final u in _people) {
        if (u.id == id) {
          picked = u;
          break;
        }
      }
    }
    Navigator.of(context).pop(SubTaskAssigneeChoice(picked));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            child: _SheetHeader(
              eyebrow: 'RESPONSÁVEL',
              title: widget.subtask.title,
              icon: LucideIcons.userCheck,
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Buscar pessoa…',
                prefixIcon: Icon(
                  LucideIcons.search,
                  size: 16,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 38, minHeight: 38),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          LucideIcons.x,
                          size: 15,
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: ThemeHelpers.textColor(context),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Flexible(child: _buildBody(theme)),
          _buildFooter(theme),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 34),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
        ),
      );
    }

    final people = _filtered;
    final isDark = theme.brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Container(
              margin: const EdgeInsets.fromLTRB(8, 0, 8, 10),
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
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: danger,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_query.trim().isEmpty)
            _PersonRow(
              name: 'Sem responsável',
              subtitle: 'Ninguém fica com esta tarefa',
              selected: _selectedId == null,
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ThemeHelpers.borderColor(context)
                      .withValues(alpha: 0.25),
                  border: Border.all(
                    color: ThemeHelpers.borderColor(context)
                        .withValues(alpha: 0.5),
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  LucideIcons.userMinus,
                  size: 16,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
              onTap: () => _select(null),
            ),
          if (people.isEmpty && _query.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 26),
              child: Column(
                children: [
                  Icon(
                    LucideIcons.userSearch,
                    size: 26,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ninguém encontrado com "$_query"',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          for (final u in people)
            _PersonRow(
              name: u.name.isEmpty ? 'Sem nome' : u.name,
              subtitle: u.email.isEmpty ? null : u.email,
              selected: _selectedId == u.id,
              leading: SubTaskPersonAvatar(name: u.name, avatarUrl: u.avatar),
              onTap: () => _select(u.id),
            ),
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
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                // Tema global pinta TextButton de vermelho — cinza forçado.
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
              onPressed: (_dirty && !_saving && !_loading) ? _confirm : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: kConfirmGreen,
                foregroundColor: Colors.white,
                disabledBackgroundColor: kConfirmGreen.withValues(alpha: 0.35),
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
              icon: const Icon(LucideIcons.check, size: 18),
              label: Text(
                _selectedId == null ? 'Remover responsável' : 'Confirmar',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Peças compartilhadas ──────────────────────────────────────────────

class _SheetHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final IconData icon;

  const _SheetHeader({
    required this.eyebrow,
    required this.title,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: kSubTaskAccent,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: -0.3,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
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
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final Color tone;
  final String label;
  final String? hint;
  final bool destructive;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.tone,
    required this.label,
    required this.onTap,
    this.hint,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  color: tone.withValues(alpha: 0.12),
                  border: Border.all(color: tone.withValues(alpha: 0.28)),
                ),
                child: Icon(icon, size: 16, color: tone),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: destructive
                            ? tone
                            : ThemeHelpers.textColor(context),
                        letterSpacing: -0.1,
                      ),
                    ),
                    if (hint != null && hint!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        hint!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                LucideIcons.chevronRight,
                size: 16,
                color: ThemeHelpers.textSecondaryColor(context)
                    .withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  final String name;
  final String? subtitle;
  final bool selected;
  final Widget leading;
  final VoidCallback onTap;

  const _PersonRow({
    required this.name,
    required this.subtitle,
    required this.selected,
    required this.leading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: selected
                ? kConfirmGreen.withValues(alpha: 0.08)
                : Colors.transparent,
            border: Border.all(
              color: selected
                  ? kConfirmGreen.withValues(alpha: 0.42)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.1,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: selected ? 1 : 0,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: kConfirmGreen,
                  ),
                  child: const Icon(Icons.check_rounded,
                      size: 15, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
