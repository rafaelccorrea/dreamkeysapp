import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/kanban_models.dart';
import '../controllers/kanban_controller.dart';

/// Widget para selecionar funil (equipe) e projeto no Kanban.
class ProjectSelector extends StatelessWidget {
  /// Quando [true], omiti o cartão externo (uso dentro do painel agrupado na [KanbanPage]).
  final bool embedded;

  const ProjectSelector({super.key, this.embedded = false});

  void _openFunnelPickerSheet(BuildContext context) {
    final ctrl = context.read<KanbanController>();
    final scrollController = ScrollController();

    void onScroll() {
      if (!scrollController.hasClients) return;
      final pos = scrollController.position;
      if (pos.maxScrollExtent <= 0) return;
      if (pos.pixels >= pos.maxScrollExtent - 120) {
        ctrl.loadMoreTeams();
      }
    }

    scrollController.addListener(onScroll);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * 0.62,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Trocar funil',
                            style: Theme.of(sheetContext)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close_rounded),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Mais funis são carregados ao chegar ao fim da lista.',
                      style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                            color:
                                ThemeHelpers.textSecondaryColor(sheetContext),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  Expanded(
                    child: Consumer<KanbanController>(
                      builder: (context, c, _) {
                        if (c.loadingTeams && c.teams.isEmpty) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }
                        if (c.teams.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'Nenhum funil disponível.',
                                style: Theme.of(sheetContext).textTheme.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        }
                        return ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount:
                              c.teams.length + (c.teamsHasMore || c.loadingMoreTeams ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i >= c.teams.length) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 16,
                                ),
                                child: Center(
                                  child: c.loadingMoreTeams
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Text(
                                          'Role para carregar mais funis',
                                          style: Theme.of(sheetContext)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: ThemeHelpers
                                                    .textSecondaryColor(
                                                  sheetContext,
                                                ),
                                              ),
                                        ),
                                ),
                              );
                            }
                            final team = c.teams[i];
                            final selected = c.team?.id == team.id ||
                                c.selectedTeam?.id == team.id;
                            return ListTile(
                              leading: Icon(
                                selected
                                    ? Icons.check_circle_rounded
                                    : Icons.arrow_right_rounded,
                                color: selected
                                    ? Theme.of(sheetContext).colorScheme.primary
                                    : ThemeHelpers.textSecondaryColor(
                                        sheetContext,
                                      ),
                              ),
                              title: Text(
                                team.name,
                                style: TextStyle(
                                  fontWeight: selected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                              onTap: () async {
                                Navigator.pop(sheetContext);
                                await c.selectTeam(team);
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).whenComplete(() {
      scrollController.removeListener(onScroll);
      scrollController.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<KanbanController>(
      builder: (context, controller, _) {
        final theme = Theme.of(context);
        final projects = controller.projects;
        final selectedProjectId = controller.projectId;
        final isLoading = controller.loadingProjects;

        // Filtrar apenas projetos ativos
        // Se o time selecionado for "Pessoal", não mostrar projetos pessoais
        final isPersonalTeam = controller.team?.name.toLowerCase().contains('pessoal') ?? false;
        final activeProjects = projects
            .where((p) {
              // Filtrar por status ativo
              if (p.status != KanbanProjectStatus.active) return false;
              
              // Se o time for "Pessoal", não mostrar projetos pessoais
              if (isPersonalTeam && (p.isPersonal == true)) return false;
              
              return true;
            })
            .toList();

        final primary = theme.colorScheme.primary;
        final cool = const Color(0xFF0891B2);

        final body = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Funil atual + troca (lista paginada em bottom sheet)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.account_tree_rounded,
                    size: 18,
                    color: primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Funil',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                        ),
                        const SizedBox(height: 6),
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: controller.loadingTeams && controller.teams.isEmpty
                              ? null
                              : () => _openFunnelPickerSheet(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: embedded
                                  ? LinearGradient(
                                      colors: [
                                        primary.withValues(alpha: 0.09),
                                        cool.withValues(alpha: 0.07),
                                      ],
                                    )
                                  : null,
                              color: embedded
                                  ? null
                                  : primary.withValues(alpha: 0.10),
                              border: embedded
                                  ? Border.all(
                                      color: primary.withValues(alpha: 0.22),
                                    )
                                  : null,
                            ),
                            child: controller.loadingTeams &&
                                    controller.teams.isEmpty
                                ? SkeletonBox(
                                    height: 22,
                                    borderRadius: 8,
                                  )
                                : Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          controller.team?.name ??
                                              (controller.teams.isEmpty
                                                  ? 'Carregando funis…'
                                                  : 'Escolher funil'),
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                            color: primary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 2,
                                        ),
                                      ),
                                      Icon(
                                        Icons.swap_vert_rounded,
                                        size: 20,
                                        color: primary.withValues(alpha: 0.75),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        if (controller.teamsHasMore)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Lista parcial — toque para carregar mais ao rolar.',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: ThemeHelpers.textSecondaryColor(context),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Seletor de projeto - título e select em coluna
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Título "Projeto"
                  Row(
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        size: 20,
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Projeto:',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Select em full width
                  Row(
                    children: [
                      Expanded(
                        child: isLoading
                            ? SkeletonBox(
                                height: 46,
                                borderRadius: 16,
                              )
                            : Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                                  child: DropdownButton<String?>(
                                    value: selectedProjectId,
                                    isExpanded: true,
                                    hint: Text(
                                      'Todos os projetos',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                    items: [
                                      // Opção "Todos os projetos"
                                      const DropdownMenuItem<String?>(
                                        value: null,
                                        child: Text('Todos os projetos'),
                                      ),
                                      // Projetos ativos
                                      ...activeProjects.map((project) {
                                        return DropdownMenuItem<String?>(
                                          value: project.id,
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 8,
                                                height: 8,
                                                decoration: BoxDecoration(
                                                  color: project.status ==
                                                          KanbanProjectStatus.active
                                                      ? Colors.green
                                                      : Colors.grey,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  project.name,
                                                  style: theme.textTheme.bodyMedium,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (project.taskCount > 0) ...[
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: theme.colorScheme.primary
                                                        .withValues(alpha: 0.1),
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: Text(
                                                    '${project.taskCount}',
                                                    style: theme.textTheme.bodySmall?.copyWith(
                                                      color: theme.colorScheme.primary,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        );
                                      }),
                                    ],
                                    onChanged: (String? newProjectId) {
                                      if (newProjectId != selectedProjectId) {
                                        controller.selectProject(newProjectId);
                                      }
                                    },
                                    icon: Icon(
                                      Icons.arrow_drop_down,
                                      color: ThemeHelpers.textSecondaryColor(context),
                                    ),
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                              ),
                      ),
                      if (activeProjects.isEmpty && !isLoading) ...[
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () {
                            // TODO: Abrir modal de criar projeto
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Funcionalidade de criar projeto em desenvolvimento'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Criar'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ],
                    ],
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

