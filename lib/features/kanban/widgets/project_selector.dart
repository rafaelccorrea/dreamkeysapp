import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/kanban_models.dart';
import '../controllers/kanban_controller.dart';

/// Seletor de funil Kanban (paridade com `ProjectSelect` do web: só funis permitidos).
/// Sempre há um funil selecionado; o padrão é o workspace (definido no [KanbanController]).
class ProjectSelector extends StatelessWidget {
  /// Quando [true], omiti o cartão externo (uso dentro do painel agrupado na [KanbanPage]).
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
          if (keep && p.id.isNotEmpty) {
            byId[p.id] = p;
          }
        }
        final funnelOptions = byId.values.toList()
          ..sort((a, b) {
            final ap = a.isPersonal == true ? 0 : 1;
            final bp = b.isPersonal == true ? 0 : 1;
            if (ap != bp) return ap.compareTo(bp);
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });

        final idSet = funnelOptions.map((p) => p.id).toSet();
        final effectiveValue = (rawId != null && idSet.contains(rawId))
            ? rawId
            : (funnelOptions.isNotEmpty ? funnelOptions.first.id : null);

        final primary = theme.colorScheme.primary;
        final cool = const Color(0xFF0891B2);

        final body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_tree_rounded,
                  size: 20,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
                const SizedBox(width: 8),
                Text(
                  'Funil:',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: isLoading && funnelOptions.isEmpty
                      ? SkeletonBox(
                          height: 46,
                          borderRadius: 16,
                        )
                      : funnelOptions.isEmpty
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Nenhum funil disponível',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: ThemeHelpers.textSecondaryColor(
                                      context,
                                    ),
                                    fontWeight: FontWeight.w600,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 14),
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
                            )
                          : Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                gradient: embedded
                                    ? LinearGradient(
                                        colors: [
                                          primary.withValues(alpha: 0.05),
                                          cool.withValues(alpha: 0.04),
                                        ],
                                      )
                                    : null,
                                color: embedded
                                    ? null
                                    : ThemeHelpers.cardBackgroundColor(context),
                                border: Border.all(
                                  color: embedded
                                      ? primary.withValues(alpha: 0.2)
                                      : ThemeHelpers.borderColor(context),
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: effectiveValue,
                                  isExpanded: true,
                                  items: funnelOptions.map((project) {
                                    return DropdownMenuItem<String>(
                                      value: project.id,
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: project.status ==
                                                      KanbanProjectStatus
                                                          .active
                                                  ? Colors.green
                                                  : Colors.grey,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              project.name,
                                              style:
                                                  theme.textTheme.bodyMedium,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (project.taskCount > 0) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: theme.colorScheme.primary
                                                    .withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                '${project.taskCount}',
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                  color: theme
                                                      .colorScheme.primary,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (String? newProjectId) {
                                    if (newProjectId == null ||
                                        newProjectId == controller.projectId) {
                                      return;
                                    }
                                    controller.selectProject(newProjectId);
                                  },
                                  icon: Icon(
                                    Icons.arrow_drop_down,
                                    color: ThemeHelpers.textSecondaryColor(
                                      context,
                                    ),
                                  ),
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                            ),
                ),
              ],
            ),
          ],
        );

        if (embedded) {
          return body;
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            border: Border(
              bottom: BorderSide(
                color: ThemeHelpers.borderColor(context),
              ),
            ),
          ),
          child: body,
        );
      },
    );
  }
}

/// Botão de criar funil quando não há funis na lista — gradiente, profundidade e hierarquia visual.
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
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.11),
                blurRadius: 14,
                offset: const Offset(0, 6),
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
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
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
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                        ],
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
