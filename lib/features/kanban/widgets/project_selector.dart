import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/kanban_models.dart';
import '../controllers/kanban_controller.dart';

/// Widget para selecionar projeto no Kanban
class ProjectSelector extends StatelessWidget {
  const ProjectSelector({super.key});

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Linha com nome da equipe
              if (controller.team != null) ...[
                Row(
                  children: [
                    Icon(
                      Icons.group_outlined,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          controller.team!.name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
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
                                height: 40,
                                borderRadius: 8,
                              )
                            : Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: ThemeHelpers.cardBackgroundColor(context),
                                  border: Border.all(
                                    color: ThemeHelpers.borderColor(context),
                                  ),
                                  borderRadius: BorderRadius.circular(8),
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
                                                        .withOpacity(0.1),
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
          ),
        );
      },
    );
  }
}

