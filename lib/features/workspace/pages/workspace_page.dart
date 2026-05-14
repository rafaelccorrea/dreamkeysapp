import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/module_access_service.dart';
import '../../../../shared/services/workspace_directory_service.dart';
import '../../kanban/models/kanban_models.dart';
import '../../kanban/services/team_service.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/vivid_chrome.dart';

/// Colaboradores e assinatura — dados reais do backend (sem edição aqui).
class WorkspacePage extends StatefulWidget {
  const WorkspacePage({super.key});

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  AdminUsersListResult? _users;
  List<KanbanTeam>? _teams;
  Map<String, dynamic>? _subscription;
  String? _errUsers;
  String? _errTeams;
  String? _errSub;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errUsers = null;
      _errTeams = null;
      _errSub = null;
    });
    final m = ModuleAccessService.instance;

    if (m.hasCompanyModule('user_management') &&
        m.hasPermission('user:view')) {
      final ur = await AdminUsersService.instance.listUsers();
      if (ur.success && ur.data != null) {
        _users = ur.data;
      } else {
        _errUsers = ur.message;
      }
    }

    if (m.hasCompanyModule('team_management') &&
        m.hasPermission('team:view')) {
      final tr = await TeamService.instance.getTeams();
      if (tr.success && tr.data != null) {
        _teams = tr.data;
      } else {
        _errTeams = tr.message;
      }
    }

    final role = (m.userRole ?? '').toLowerCase();
    if (role == 'admin' || role == 'master') {
      final sr =
          await SubscriptionInfoService.instance.getMyActiveSubscription();
      if (sr.success && sr.data != null) {
        final msg = sr.data!['message']?.toString();
        if (msg != null &&
            msg.contains('Nenhuma assinatura ativa')) {
          _subscription = null;
          _errSub = msg;
        } else {
          _subscription = sr.data;
        }
      } else {
        _errSub = sr.message;
      }
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).brightness == Brightness.dark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;

    return AppScaffold(
      title: 'Colaboradores',
      currentBottomNavIndex: -1,
      showBottomNavigation: false,
      body: RefreshIndicator(
        color: accent,
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  VividChrome.heroBanner(
                    context,
                    accent: accent,
                    eyebrow: 'Organização',
                    title: 'Colaboradores',
                    subtitle:
                        'Utilizadores (GET /admin/users), equipes (GET /teams) e assinatura ativa quando o perfil é admin ou master.',
                    icon: Icons.groups_rounded,
                  ),
                  const SizedBox(height: 18),
                  VividChrome.sectionLabel(
                    context,
                    'Utilizadores',
                    accent: accent,
                  ),
                  if (_errUsers != null)
                    VividChrome.mutedMessage(context, _errUsers!, accent: accent)
                  else if (_users == null)
                    VividChrome.mutedMessage(
                      context,
                      'Sem permissão user:view ou módulo user_management na empresa.',
                      accent: accent,
                    )
                  else if (_users!.users.isEmpty)
                    VividChrome.mutedMessage(
                      context,
                      'Nenhum utilizador devolvido nesta página.',
                      accent: accent,
                    )
                  else
                    VividChrome.insetCard(
                      context,
                      accent: accent,
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < _users!.users.length; i++) ...[
                            if (i > 0)
                              Divider(
                                height: 1,
                                thickness: 1,
                                color: ThemeHelpers.borderColor(context)
                                    .withValues(alpha: 0.35),
                              ),
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              title: Text(
                                _users!.users[i].name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                '${_users!.users[i].email} · ${_users!.users[i].role}'
                                '${_users!.users[i].isActiveInCompany ? '' : ' · inativo'}',
                                style: TextStyle(
                                  color: ThemeHelpers.textSecondaryColor(
                                    context,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  VividChrome.sectionLabel(
                    context,
                    'Equipes',
                    accent: accent,
                  ),
                  if (_errTeams != null)
                    VividChrome.mutedMessage(context, _errTeams!, accent: accent)
                  else if (_teams == null)
                    VividChrome.mutedMessage(
                      context,
                      'Sem permissão team:view ou módulo team_management na empresa.',
                      accent: accent,
                    )
                  else if (_teams!.isEmpty)
                    VividChrome.mutedMessage(
                      context,
                      'Nenhuma equipa devolvida.',
                      accent: accent,
                    )
                  else
                    VividChrome.insetCard(
                      context,
                      accent: accent,
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < _teams!.length; i++) ...[
                            if (i > 0)
                              Divider(
                                height: 1,
                                thickness: 1,
                                color: ThemeHelpers.borderColor(context)
                                    .withValues(alpha: 0.35),
                              ),
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              title: Text(
                                _teams![i].name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                'ID ${_teams![i].id}',
                                style: TextStyle(
                                  color: ThemeHelpers.textSecondaryColor(
                                    context,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  VividChrome.sectionLabel(
                    context,
                    'Assinatura',
                    accent: accent,
                  ),
                  if (_errSub != null && _subscription == null)
                    VividChrome.mutedMessage(context, _errSub!, accent: accent)
                  else if (_subscription == null)
                    VividChrome.mutedMessage(
                      context,
                      'Resumo da assinatura ativa (GET /subscriptions/my-active-subscription) visível para perfis admin ou master.',
                      accent: accent,
                    )
                  else
                    VividChrome.insetCard(
                      context,
                      accent: accent,
                      child: SelectableText(
                        _subscription!.entries
                            .map((e) => '${e.key}: ${e.value}')
                            .join('\n'),
                        style: TextStyle(
                          height: 1.4,
                          color: ThemeHelpers.textColor(context),
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
