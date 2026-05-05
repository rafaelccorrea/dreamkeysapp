import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../controllers/kanban_controller.dart';
import '../models/kanban_models.dart';

/// Seletor de funil Kanban (paridade com `ProjectSelect` do web: só funis permitidos).
///
/// Abandona o `DropdownButton` nativo: o trigger é um cartão premium com gradient sutil,
/// avatar do funil, nome em destaque, equipa, contagem de cards e chevron. Ao tocar abre
/// um bottom sheet com busca e lista detalhada — sem clipping da janela do dropdown e
/// sem desempenho ruim em listas grandes.
class ProjectSelector extends StatelessWidget {
  /// Quando [true], omite o cartão externo (uso dentro do painel agrupado na [KanbanPage]).
  final bool embedded;

  const ProjectSelector({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    return Consumer<KanbanController>(
      builder: (context, controller, _) {
        final theme = Theme.of(context);
        final rawId = controller.projectId;
        final isLoading = controller.loadingProjects;

        final byId = <String, KanbanProject>{};
        for (final p in controller.projects) {
          final keep =
              p.status == KanbanProjectStatus.active || p.id == rawId;
          if (keep && p.id.isNotEmpty) byId[p.id] = p;
        }
        final options = byId.values.toList()
          ..sort((a, b) {
            final ap = a.isPersonal == true ? 0 : 1;
            final bp = b.isPersonal == true ? 0 : 1;
            if (ap != bp) return ap.compareTo(bp);
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });

        final idSet = options.map((p) => p.id).toSet();
        final effectiveValue = (rawId != null && idSet.contains(rawId))
            ? rawId
            : (options.isNotEmpty ? options.first.id : null);

        final current = effectiveValue == null
            ? null
            : options.firstWhere(
                (p) => p.id == effectiveValue,
                orElse: () => options.first,
              );

        Widget content;
        if (isLoading && options.isEmpty) {
          content = const SkeletonBox(height: 64, borderRadius: 18);
        } else if (options.isEmpty) {
          content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Nenhum funil disponível',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              _KanbanCreateFunnelCta(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Funcionalidade de criar funil em desenvolvimento',
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        } else {
          content = _ProjectTriggerCard(
            current: current!,
            allProjects: options,
            onTap: () => _openPicker(context, controller, options, current.id),
          );
        }

        if (embedded) return content;

        return Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            border: Border(
              bottom: BorderSide(color: ThemeHelpers.borderColor(context)),
            ),
          ),
          child: content,
        );
      },
    );
  }

  Future<void> _openPicker(
    BuildContext context,
    KanbanController controller,
    List<KanbanProject> options,
    String selectedId,
  ) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => _ProjectPickerSheet(
        options: options,
        selectedId: selectedId,
      ),
    );
    if (picked != null && picked.isNotEmpty && picked != controller.projectId) {
      controller.selectProject(picked);
    }
  }
}

// ============================================================================
// TRIGGER CARD
// ============================================================================

class _ProjectTriggerCard extends StatelessWidget {
  final KanbanProject current;
  final List<KanbanProject> allProjects;
  final VoidCallback onTap;

  const _ProjectTriggerCard({
    required this.current,
    required this.allProjects,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _kanbanAccent(context);
    const cool = Color(0xFF0891B2);
    final accentBlend = Color.lerp(accent, cool, 0.4)!;

    final palette = _funnelPalette(current, accent);
    final isPersonal = current.isPersonal == true;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      accent.withValues(alpha: 0.16),
                      accent.withValues(alpha: 0.08),
                      ThemeHelpers.cardBackgroundColor(context),
                    ]
                  : [
                      accent.withValues(alpha: 0.085),
                      accent.withValues(alpha: 0.045),
                      Colors.white,
                    ],
              stops: const [0.0, 0.42, 1.0],
            ),
            border: Border.all(
              color: accent.withValues(alpha: isDark ? 0.42 : 0.28),
              width: 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: isDark ? 0.22 : 0.1),
                blurRadius: 16,
                spreadRadius: -4,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.32 : 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            child: Row(
              children: [
                _FunnelGlyph(
                  color: palette,
                  accent: accentBlend,
                  isPersonal: isPersonal,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            'FUNIL ATIVO',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.4,
                              color: accent,
                              height: 1,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isPersonal)
                            _StatusPill(
                              label: 'Pessoal',
                              color: const Color(0xFF8B5CF6),
                            )
                          else if (current.status == KanbanProjectStatus.active)
                            _StatusPill(
                              label: 'Ativo',
                              color: const Color(0xFF10B981),
                            )
                          else
                            _StatusPill(
                              label: _statusLabel(current.status),
                              color: ThemeHelpers.textSecondaryColor(context),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        current.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          height: 1.1,
                          color: ThemeHelpers.textColor(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            Icons.assignment_outlined,
                            size: 13,
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            current.taskCount == 1
                                ? '1 card'
                                : '${current.taskCount} cards',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: ThemeHelpers.textSecondaryColor(context),
                              height: 1,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            width: 3,
                            height: 3,
                            decoration: BoxDecoration(
                              color: ThemeHelpers.textSecondaryColor(context)
                                  .withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              allProjects.length == 1
                                  ? '1 funil disponível'
                                  : '${allProjects.length} funis disponíveis',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color:
                                    ThemeHelpers.textSecondaryColor(context),
                                height: 1,
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
                const SizedBox(width: 8),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        accent.withValues(alpha: isDark ? 0.32 : 0.18),
                        cool.withValues(alpha: isDark ? 0.32 : 0.18),
                      ],
                    ),
                    border: Border.all(
                      color: accent.withValues(alpha: isDark ? 0.4 : 0.28),
                    ),
                  ),
                  child: Icon(
                    Icons.unfold_more_rounded,
                    color: accent,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FunnelGlyph extends StatelessWidget {
  final Color color;
  final Color accent;
  final bool isPersonal;

  const _FunnelGlyph({
    required this.color,
    required this.accent,
    required this.isPersonal,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: isDark ? 0.42 : 0.28),
            accent.withValues(alpha: isDark ? 0.32 : 0.18),
          ],
        ),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: isDark ? 0.32 : 0.18),
            blurRadius: 12,
            spreadRadius: -3,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(
        isPersonal ? Icons.workspaces_outlined : Icons.account_tree_rounded,
        color: color,
        size: 22,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: color,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// PICKER SHEET
// ============================================================================

class _ProjectPickerSheet extends StatefulWidget {
  final List<KanbanProject> options;
  final String selectedId;

  const _ProjectPickerSheet({
    required this.options,
    required this.selectedId,
  });

  @override
  State<_ProjectPickerSheet> createState() => _ProjectPickerSheetState();
}

class _ProjectPickerSheetState extends State<_ProjectPickerSheet> {
  late final TextEditingController _search;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _search = TextEditingController();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _kanbanAccent(context);
    final mq = MediaQuery.of(context);

    final filtered = widget.options.where((p) {
      if (_query.trim().isEmpty) return true;
      return p.name.toLowerCase().contains(_query.toLowerCase());
    }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.16),
                blurRadius: 28,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: ThemeHelpers.textSecondaryColor(context)
                      .withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          colors: [
                            accent.withValues(alpha: isDark ? 0.42 : 0.22),
                            const Color(0xFF0891B2)
                                .withValues(alpha: isDark ? 0.42 : 0.22),
                          ],
                        ),
                        border:
                            Border.all(color: accent.withValues(alpha: 0.4)),
                      ),
                      child: Icon(
                        Icons.account_tree_rounded,
                        size: 20,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Trocar de funil',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.3,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.options.length} pipeline(s) disponível(is)',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: ThemeHelpers.textSecondaryColor(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Buscar funil…',
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: ThemeHelpers.cardBackgroundColor(context)
                        .withValues(alpha: 0.6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color:
                            ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: ThemeHelpers.borderColor(context)
                            .withValues(alpha: 0.5),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          BorderSide(color: accent.withValues(alpha: 0.7), width: 1.4),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.search_off_rounded,
                                size: 48,
                                color: ThemeHelpers.textSecondaryColor(context)
                                    .withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Nenhum funil encontrado',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: ThemeHelpers.textSecondaryColor(
                                    context,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: EdgeInsets.fromLTRB(
                          16,
                          8,
                          16,
                          16 + mq.padding.bottom,
                        ),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final p = filtered[i];
                          final selected = p.id == widget.selectedId;
                          return _ProjectPickerTile(
                            project: p,
                            selected: selected,
                            onTap: () => Navigator.of(context).pop(p.id),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProjectPickerTile extends StatelessWidget {
  final KanbanProject project;
  final bool selected;
  final VoidCallback onTap;

  const _ProjectPickerTile({
    required this.project,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _kanbanAccent(context);
    final palette = _funnelPalette(project, accent);
    final isPersonal = project.isPersonal == true;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: selected
                ? accent.withValues(alpha: isDark ? 0.16 : 0.07)
                : ThemeHelpers.cardBackgroundColor(context)
                    .withValues(alpha: 0.5),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: isDark ? 0.55 : 0.4)
                  : ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            child: Row(
              children: [
                _FunnelGlyph(
                  color: palette,
                  accent: palette,
                  isPersonal: isPersonal,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              project.name,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                                height: 1.1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isPersonal)
                            _StatusPill(
                              label: 'Pessoal',
                              color: const Color(0xFF8B5CF6),
                            )
                          else if (project.status ==
                              KanbanProjectStatus.active)
                            _StatusPill(
                              label: 'Ativo',
                              color: const Color(0xFF10B981),
                            )
                          else
                            _StatusPill(
                              label: _statusLabel(project.status),
                              color:
                                  ThemeHelpers.textSecondaryColor(context),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.assignment_outlined,
                            size: 12,
                            color:
                                ThemeHelpers.textSecondaryColor(context),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            project.taskCount == 1
                                ? '1 card'
                                : '${project.taskCount} cards',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              color:
                                  ThemeHelpers.textSecondaryColor(context),
                              height: 1,
                            ),
                          ),
                          if (project.completedTaskCount != null &&
                              project.completedTaskCount! > 0) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.check_circle_outline_rounded,
                              size: 12,
                              color: const Color(0xFF10B981),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${project.completedTaskCount} concluídos',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                                color: const Color(0xFF10B981),
                                height: 1,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (selected)
                  Icon(Icons.check_circle_rounded, color: accent, size: 24)
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// HELPERS
// ============================================================================

Color _kanbanAccent(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
}

/// Cor estável por funil — combina o accent com um hash do nome para distinguir
/// pipelines visualmente sem depender de campo na API.
Color _funnelPalette(KanbanProject p, Color fallback) {
  if (p.isPersonal == true) return const Color(0xFF8B5CF6);
  const palette = [
    Color(0xFF0EA5E9),
    Color(0xFF14B8A6),
    Color(0xFF6366F1),
    Color(0xFFF97316),
    Color(0xFF22C55E),
    Color(0xFFEC4899),
    Color(0xFF06B6D4),
    Color(0xFFA855F7),
  ];
  if (p.id.isEmpty) return fallback;
  var h = 0;
  for (final c in p.id.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return palette[h % palette.length];
}

String _statusLabel(KanbanProjectStatus s) {
  switch (s) {
    case KanbanProjectStatus.active:
      return 'Ativo';
    case KanbanProjectStatus.completed:
      return 'Concluído';
    case KanbanProjectStatus.archived:
      return 'Arquivado';
    case KanbanProjectStatus.cancelled:
      return 'Cancelado';
  }
}

// ============================================================================
// CTA "Criar funil" (mantido para o estado vazio)
// ============================================================================

class _KanbanCreateFunnelCta extends StatelessWidget {
  final VoidCallback onPressed;

  const _KanbanCreateFunnelCta({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
    const cool = Color(0xFF0891B2);
    final bridge = Color.lerp(primary, cool, 0.45)!;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(primary, Colors.white, isDark ? 0.04 : 0.08)!,
                primary,
                bridge,
                cool,
              ],
              stops: const [0.0, 0.28, 0.62, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: primary.withValues(alpha: 0.45),
                blurRadius: 20,
                spreadRadius: -6,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: cool.withValues(alpha: 0.22),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(
              width: 1.25,
              color: Colors.white.withValues(alpha: isDark ? 0.16 : 0.42),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 16, 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.white.withValues(alpha: 0.2),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.38),
                    ),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(7),
                    child: Icon(
                      Icons.add_rounded,
                      size: 21,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Criar funil',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                        height: 1.05,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Novo pipeline de vendas',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.88),
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 26,
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
