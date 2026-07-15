import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/workspace_directory_service.dart';

/// Resultado da seleção de responsável.
class PickedUser {
  final String id;
  final String name;
  const PickedUser({required this.id, required this.name});
}

/// Abre o bottom-sheet de seleção de responsável (usuários da empresa via
/// `GET /admin/users`). Devolve o usuário escolhido, `PickedUser` com id
/// vazio para "remover vínculo" (quando [allowClear]) ou `null` se cancelado.
Future<PickedUser?> showUserPickerSheet(
  BuildContext context, {
  String? selectedId,
  bool allowClear = false,
}) {
  return showModalBottomSheet<PickedUser>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) => _UserPickerSheet(
      selectedId: selectedId,
      allowClear: allowClear,
    ),
  );
}

class _UserPickerSheet extends StatefulWidget {
  final String? selectedId;
  final bool allowClear;

  const _UserPickerSheet({this.selectedId, required this.allowClear});

  @override
  State<_UserPickerSheet> createState() => _UserPickerSheetState();
}

class _UserPickerSheetState extends State<_UserPickerSheet> {
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
        _users = res.data!.users
            .where((u) => u.isActiveInCompany)
            .toList()
          ..sort((a, b) =>
              a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      } else {
        _error = res.message ?? 'Erro ao carregar usuários';
      }
    });
  }

  List<CompanyUserRow> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _users;
    return _users
        .where((u) =>
            u.name.toLowerCase().contains(q) ||
            u.email.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
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
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
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
                        color: ThemeHelpers.borderLightColor(context)),
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
                      child:
                          Icon(LucideIcons.userRound, color: accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Selecionar responsável',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: ThemeHelpers.textColor(context),
                        ),
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
                        color: ThemeHelpers.borderLightColor(context)),
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
                            padding:
                                const EdgeInsets.fromLTRB(20, 8, 20, 30),
                            children: [
                              if (widget.allowClear)
                                _userRow(
                                  context,
                                  icon: LucideIcons.userMinus,
                                  name: 'Sem responsável',
                                  email: 'Remover o vínculo atual',
                                  selected: false,
                                  onTap: () => Navigator.of(context).pop(
                                      const PickedUser(id: '', name: '')),
                                ),
                              for (final u in _filtered)
                                _userRow(
                                  context,
                                  name: u.name,
                                  email: u.email,
                                  selected: u.id == widget.selectedId,
                                  onTap: () => Navigator.of(context).pop(
                                      PickedUser(id: u.id, name: u.name)),
                                ),
                              if (_filtered.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(30),
                                  child: Text(
                                    'Nenhum usuário encontrado.',
                                    textAlign: TextAlign.center,
                                    style:
                                        theme.textTheme.bodyMedium?.copyWith(
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
    IconData? icon,
    required String name,
    required String email,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected
              ? accent.withValues(alpha: isDark ? 0.14 : 0.08)
              : Colors.transparent,
        ),
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
              child: icon != null
                  ? Icon(icon, size: 17, color: accent)
                  : Text(
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
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  if (email.isNotEmpty)
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                      ),
                    ),
                ],
              ),
            ),
            if (selected)
              Icon(LucideIcons.circleCheck, size: 18, color: accent),
          ],
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.cloudOff, size: 32, color: danger),
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
