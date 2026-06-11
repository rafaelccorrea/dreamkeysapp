import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/shell_visual_tokens.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../features/kanban/models/kanban_subtask_models.dart';
import '../../../features/kanban/services/kanban_subtask_service.dart';
import '../../../features/appointments/services/appointment_service.dart';
import '../../../features/appointments/models/appointment_model.dart';
import '../../../shared/utils/broker_contact_actions.dart';
import '../../../shared/services/purchase_proposals_service.dart';
import '../../../shared/state/broker_offline_cache.dart';
import '../../../shared/state/broker_shortcuts_prefs.dart';
import '../../../shared/state/recent_navigation_cache.dart';
import 'broker_global_search_sheet.dart';

/// Hub do corretor no Início: continuar, busca, leads hoje, propostas, atalhos.
class BrokerDashboardHub extends StatefulWidget {
  const BrokerDashboardHub({super.key});

  @override
  State<BrokerDashboardHub> createState() => _BrokerDashboardHubState();
}

class _BrokerDashboardHubState extends State<BrokerDashboardHub> {
  bool _loading = true;
  List<KanbanSubTask> _todaySubtasks = [];
  List<Appointment> _todayVisits = [];
  int _pendingSignatures = 0;
  List<String> _shortcutIds = BrokerShortcutsPrefs.defaultIds;
  RecentNavigationCache? _recent;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    await RecentNavigationCache.instance.ensureLoaded();
    _recent = RecentNavigationCache.instance;
    _shortcutIds = await BrokerShortcutsPrefs.instance.load();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final subRes = await KanbanSubtaskService.instance.getMySubTasks(
      filters: SubTasksListFilters(
        onlyMine: true,
        isCompleted: false,
        dueDateFrom: today.subtract(const Duration(days: 7)),
        dueDateTo: today,
        page: 1,
        limit: 8,
      ),
    );

    if (subRes.success && subRes.data != null) {
      _todaySubtasks = subRes.data!.data;
      unawaited(
        BrokerOfflineCache.instance.saveSubtasks(
          _todaySubtasks
              .map(
                (s) => {
                  'id': s.id,
                  'title': s.title,
                  'taskId': s.taskId,
                },
              )
              .toList(),
        ),
      );
    }

    final propRes = await PurchaseProposalsService.instance.list(
      filters: const ProposalFilters(page: 1, limit: 30),
    );
    if (propRes.success && propRes.data != null) {
      _pendingSignatures = propRes.data!.items
          .where((p) => p.status == ProposalStatus.processing)
          .length;
    }

    final dayEnd = today.add(const Duration(days: 1));
    final apptRes = await AppointmentService.instance.listAppointments(
      startDate: today.toIso8601String(),
      endDate: dayEnd.toIso8601String(),
      limit: 8,
      onlyMyData: true,
    );
    if (apptRes.success && apptRes.data != null) {
      _todayVisits = apptRes.data!.appointments
          .where((a) => a.type == AppointmentType.visit)
          .toList();
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  void _openGlobalSearch() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const BrokerGlobalSearchSheet(),
    );
  }

  IconData _iconForShortcut(String iconKey) {
    switch (iconKey) {
      case 'squareKanban':
        return Icons.view_kanban_rounded;
      case 'calendarDays':
        return Icons.calendar_month_rounded;
      case 'users':
        return Icons.people_outline_rounded;
      case 'fileEdit':
        return Icons.edit_note_rounded;
      case 'listChecks':
        return Icons.checklist_rounded;
      case 'fileSignature':
        return Icons.description_outlined;
      case 'sparkles':
        return Icons.auto_awesome_rounded;
      case 'home':
        return Icons.home_outlined;
      default:
        return Icons.circle_outlined;
    }
  }

  String? _routeForShortcut(String id) {
    switch (id) {
      case 'kanban':
        return AppRoutes.kanban;
      case 'calendar':
        return AppRoutes.calendar;
      case 'clients':
        return AppRoutes.clients;
      case 'drafts':
        return AppRoutes.propertyDraftsLocal;
      case 'tasks':
        return AppRoutes.kanbanSubtasks;
      case 'proposals':
        return AppRoutes.proposals;
      case 'matches':
        return AppRoutes.matches;
      case 'properties':
        return AppRoutes.properties;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = Theme.of(context).brightness == Brightness.dark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: ShellVisualTokens.dashboardGlassFill(context),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _openGlobalSearch,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, color: accent, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Buscar imóvel, cliente ou lead…',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_recent?.hasRecent == true) ...[
          const _SectionHeader(
            title: 'Continuar',
            icon: Icons.play_circle_outline,
          ),
          const SizedBox(height: 8),
          _HubTile(
            title: _recent!.label ?? 'Última tela',
            subtitle: _recent!.extra,
            icon: Icons.history_rounded,
            accent: accent,
            onTap: () {
              final route = _recent!.route;
              if (route != null) {
                Navigator.of(context).pushNamed(route);
              }
            },
          ),
          const SizedBox(height: 12),
        ],
        if (_pendingSignatures > 0) ...[
          _HubTile(
            title: '$_pendingSignatures proposta(s) em andamento',
            subtitle: 'Toque para ver fichas e assinaturas',
            icon: Icons.description_outlined,
            accent: const Color(0xFFD97706),
            onTap: () => Navigator.of(context).pushNamed(AppRoutes.proposals),
          ),
          const SizedBox(height: 12),
        ],
        if (_todayVisits.isNotEmpty) ...[
          _SectionHeader(
            title: 'Visitas de hoje',
            icon: Icons.event_available_rounded,
            trailing: TextButton(
              onPressed: () =>
                  Navigator.of(context).pushNamed(AppRoutes.calendar),
              child: const Text('Agenda'),
            ),
          ),
          const SizedBox(height: 8),
          ..._todayVisits.take(4).map(
                (a) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _HubTile(
                    title: a.title,
                    subtitle: a.location ?? a.startDate.toString(),
                    icon: Icons.place_outlined,
                    accent: const Color(0xFF0891B2),
                    onTap: () {
                      if (a.location != null && a.location!.trim().isNotEmpty) {
                        BrokerContactActions.openMaps(context, a.location!);
                      } else {
                        Navigator.of(context).pushNamed(
                          AppRoutes.calendarDetails(a.id),
                        );
                      }
                    },
                  ),
                ),
              ),
          const SizedBox(height: 12),
        ],
        _SectionHeader(
          title: 'Meus follow-ups',
          icon: Icons.task_alt_rounded,
          trailing: TextButton(
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.kanbanSubtasks),
            child: const Text('Ver todas'),
          ),
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (_todaySubtasks.isEmpty)
          Text(
            'Nenhuma tarefa pendente com prazo recente.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          )
        else
          ..._todaySubtasks.take(5).map(
                (s) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _HubTile(
                    title: s.title,
                    subtitle: s.taskTitle ?? s.parentTaskTitle ?? 'CRM',
                    icon: s.isOverdue
                        ? Icons.warning_amber_rounded
                        : Icons.checklist_rounded,
                    accent:
                        s.isOverdue ? AppColors.status.error : accent,
                    onTap: () => Navigator.of(context).pushNamed(
                      AppRoutes.kanbanTaskDetails(s.taskId),
                    ),
                  ),
                ),
              ),
        const SizedBox(height: 12),
        _SectionHeader(
          title: 'Atalhos',
          icon: Icons.apps_rounded,
          trailing: IconButton(
            icon: const Icon(Icons.tune_rounded, size: 20),
            tooltip: 'Configurar atalhos',
            onPressed: () => _showShortcutPicker(context),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _shortcutIds.map((id) {
            final def = BrokerShortcutsPrefs.allShortcuts
                .where((d) => d.id == id)
                .cast<BrokerShortcutDef?>()
                .firstOrNull;
            if (def == null) return const SizedBox.shrink();
            final route = _routeForShortcut(def.id);
            return ActionChip(
              avatar: Icon(_iconForShortcut(def.iconKey), size: 18),
              label: Text(def.label),
              onPressed:
                  route != null ? () => Navigator.of(context).pushNamed(route) : null,
            );
          }).toList(),
        ),
      ],
    );
  }

  Future<void> _showShortcutPicker(BuildContext context) async {
    final selected = List<String>.from(_shortcutIds);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Atalhos do Início',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 12),
                ...BrokerShortcutsPrefs.allShortcuts.map((def) {
                  final on = selected.contains(def.id);
                  return CheckboxListTile(
                    value: on,
                    title: Text(def.label),
                    onChanged: (v) {
                      setModalState(() {
                        if (v == true) {
                          if (selected.length < 4 &&
                              !selected.contains(def.id)) {
                            selected.add(def.id);
                          }
                        } else {
                          selected.remove(def.id);
                        }
                      });
                    },
                  );
                }),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () async {
                    await BrokerShortcutsPrefs.instance.save(selected);
                    if (mounted) {
                      setState(() => _shortcutIds = selected);
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Salvar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget? trailing;

  const _SectionHeader({
    required this.title,
    required this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: ThemeHelpers.textSecondaryColor(context)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _HubTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const _HubTile({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ThemeHelpers.cardBackgroundColor(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null && subtitle!.trim().isNotEmpty)
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ThemeHelpers.textSecondaryColor(context),
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (it.moveNext()) return it.current;
    return null;
  }
}
