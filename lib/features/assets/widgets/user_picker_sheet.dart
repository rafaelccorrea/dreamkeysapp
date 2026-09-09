import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/workspace_directory_service.dart';
import '../../../shared/widgets/app_error_state.dart';

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
  int _errorStatus = 0;
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
        _error = null;
        _errorStatus = 0;
      } else {
        _error = res.message ?? 'Erro ao carregar usuários';
        _errorStatus = res.statusCode;
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
                                  role: u.role,
                                  avatarUrl: u.avatarUrl,
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
    String? role,
    String? avatarUrl,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    // "Sem responsável" (clear) usa cinza neutro; cada pessoa ganha um tom
    // próprio (fim do vermelho único da marca em tudo).
    final tone = icon != null ? secondary : _avatarColor(name);
    final roleLabel = _formatRole(role);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected
              ? tone.withValues(alpha: isDark ? 0.16 : 0.10)
              : Colors.transparent,
          border: Border.all(
            color: selected
                ? tone.withValues(alpha: isDark ? 0.5 : 0.38)
                : ThemeHelpers.borderLightColor(context)
                    .withValues(alpha: isDark ? 0.4 : 0.55),
          ),
        ),
        child: Row(
          children: [
            icon != null
                ? Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: secondary.withValues(alpha: isDark ? 0.16 : 0.1),
                      border: Border.all(
                        color: secondary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Icon(icon, size: 18, color: secondary),
                  )
                : _UserAvatar(
                    avatarUrl: avatarUrl,
                    initials: _initials(name),
                    color: tone,
                    size: 42,
                  ),
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
                      letterSpacing: -0.2,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (roleLabel != null) ...[
                        Flexible(
                          child: Text(
                            roleLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: tone,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        if (email.isNotEmpty) ...[
                          Text(
                            '  ·  ',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: secondary.withValues(alpha: 0.5),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ],
                      if (email.isNotEmpty)
                        Flexible(
                          child: Text(
                            email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: secondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (selected)
              Icon(LucideIcons.circleCheck, size: 20, color: tone)
            else
              Icon(
                LucideIcons.chevronRight,
                size: 18,
                color: secondary.withValues(alpha: 0.5),
              ),
          ],
        ),
      ),
    );
  }

  /// Paleta determinística por nome — tom único por pessoa.
  Color _avatarColor(String seed) {
    const palette = [
      Color(0xFF6366F1), // indigo
      Color(0xFF0EA5E9), // sky
      Color(0xFF14B8A6), // teal
      Color(0xFF22C55E), // green
      Color(0xFFF59E0B), // amber
      Color(0xFFEC4899), // pink
      Color(0xFFA855F7), // purple
      Color(0xFFEA580C), // orange
    ];
    final code = seed.codeUnits.fold<int>(0, (a, b) => a + b);
    return palette[code % palette.length];
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String? _formatRole(String? raw) {
    final r = raw?.trim();
    if (r == null || r.isEmpty) return null;
    return r
        .replaceAll('_', ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }

  Widget _buildError(BuildContext context) {
    return AppErrorState.fromApi(
      message: _error,
      statusCode: _errorStatus,
      onRetry: _load,
      dense: true,
    );
  }
}

/// Avatar do colaborador: foto real (quando houver) sobre um anel na cor do
/// usuário; enquanto carrega ou se falhar, cai para o monograma colorido.
class _UserAvatar extends StatelessWidget {
  const _UserAvatar({
    required this.avatarUrl,
    required this.initials,
    required this.color,
    required this.size,
  });

  final String? avatarUrl;
  final String initials;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = avatarUrl != null && avatarUrl!.isNotEmpty;
    final monogram = Container(
      color: color,
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: size * 0.36,
          letterSpacing: 0.2,
        ),
      ),
    );
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1.5),
      ),
      child: hasPhoto
          ? Image.network(
              avatarUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => monogram,
              loadingBuilder: (_, child, prog) =>
                  prog == null ? child : monogram,
            )
          : monogram,
    );
  }
}
