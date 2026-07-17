import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/workspace_directory_service.dart';

/// Usuário escolhido para entrar na equipe — carrega e-mail junto para a
/// linha de membro do formulário ficar rica (nome + e-mail discreto).
class PickedTeamMember {
  final String id;
  final String name;
  final String email;
  const PickedTeamMember({
    required this.id,
    required this.name,
    required this.email,
  });
}

/// Bottom-sheet de seleção de membro para a equipe (usuários ativos da
/// empresa via `GET /admin/users`). Quem já está na equipe aparece marcado
/// e não é selecionável de novo. Devolve `null` se cancelado.
Future<PickedTeamMember?> showTeamMemberPickerSheet(
  BuildContext context, {
  required Color accent,
  Set<String> excludeIds = const {},
}) {
  return showModalBottomSheet<PickedTeamMember>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) => _TeamMemberPickerSheet(
      accent: accent,
      excludeIds: excludeIds,
    ),
  );
}

class _TeamMemberPickerSheet extends StatefulWidget {
  const _TeamMemberPickerSheet({
    required this.accent,
    required this.excludeIds,
  });

  final Color accent;
  final Set<String> excludeIds;

  @override
  State<_TeamMemberPickerSheet> createState() => _TeamMemberPickerSheetState();
}

class _TeamMemberPickerSheetState extends State<_TeamMemberPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<CompanyUserRow> _users = const [];
  bool _loading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await AdminUsersService.instance.listUsers(limit: 200);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _users = res.data!.users.where((u) => u.isActiveInCompany).toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
      } else {
        _error = res.message ?? 'Erro ao carregar usuários';
      }
    });
  }

  List<CompanyUserRow> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _users;
    return _users
        .where(
          (u) =>
              u.name.toLowerCase().contains(q) ||
              u.email.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = widget.accent;
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: ThemeHelpers.backgroundColor(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ThemeHelpers.borderColor(context)
                          .withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
              // Header.
              Container(
                padding: const EdgeInsets.fromLTRB(20, 4, 10, 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: ThemeHelpers.borderLightColor(context),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: isDark ? 0.2 : 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(LucideIcons.userPlus, color: accent, size: 19),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Adicionar membro',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: ThemeHelpers.textColor(context),
                            ),
                          ),
                          Text(
                            'Usuários ativos da empresa',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: secondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Fechar',
                    ),
                  ],
                ),
              ),
              // Busca.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: ThemeHelpers.cardBackgroundColor(context),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: ThemeHelpers.borderLightColor(context),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.search, size: 17, color: secondary),
                      const SizedBox(width: 9),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: (v) => setState(() => _query = v),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: ThemeHelpers.textColor(context),
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: 'Buscar por nome ou e-mail…',
                            hintStyle: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              color: secondary.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _loading
                    ? Center(child: CircularProgressIndicator(color: accent))
                    : _error != null
                        ? _buildError(context)
                        : ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
                            children: [
                              for (final u in _filtered)
                                _userRow(
                                  context,
                                  user: u,
                                  alreadyIn: widget.excludeIds.contains(u.id),
                                ),
                              if (_filtered.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(30),
                                  child: Text(
                                    'Nenhum usuário encontrado.',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: secondary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _userRow(
    BuildContext context, {
    required CompanyUserRow user,
    required bool alreadyIn,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = widget.accent;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final green =
        isDark ? AppColors.status.successDarkMode : AppColors.status.success;
    final initial =
        user.name.trim().isNotEmpty ? user.name.trim()[0].toUpperCase() : '?';

    return InkWell(
      onTap: alreadyIn
          ? null
          : () {
              HapticFeedback.selectionClick();
              Navigator.of(context).pop(
                PickedTeamMember(
                  id: user.id,
                  name: user.name,
                  email: user.email,
                ),
              );
            },
      borderRadius: BorderRadius.circular(12),
      child: Opacity(
        opacity: alreadyIn ? 0.55 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: isDark ? 0.18 : 0.1),
                  border: Border.all(color: accent.withValues(alpha: 0.3)),
                ),
                child: Text(
                  initial,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                    if (user.email.isNotEmpty)
                      Text(
                        user.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (alreadyIn)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.check, size: 11, color: green),
                      const SizedBox(width: 4),
                      Text(
                        'Na equipe',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: green,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.cloudOff, size: 32, color: secondary),
            const SizedBox(height: 10),
            Text(
              _error ?? 'Erro ao carregar usuários',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(LucideIcons.refreshCw, size: 15),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
