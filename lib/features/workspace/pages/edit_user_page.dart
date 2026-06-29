import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/admin_user_model.dart';
import '../services/admin_users_service.dart';
import '../utils/permission_meta.dart';

/// Tela de **Editar Usuário** (mobile, identidade própria — NÃO inspirada no
/// web; sem banner). Permite alterar papel, acessos (app/site) e o catálogo
/// de permissões por categoria em cartões expansíveis (grade compacta).
class EditUserPage extends StatefulWidget {
  const EditUserPage({super.key, required this.user});

  final AdminUser user;

  @override
  State<EditUserPage> createState() => _EditUserPageState();
}

class _EditUserPageState extends State<EditUserPage> {
  static const double _padH = 20;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  // Catálogo de permissões por categoria (ordenado por rótulo).
  final List<MapEntry<String, List<UserPermission>>> _catalog = [];
  final Set<String> _expanded = {};
  final TextEditingController _search = TextEditingController();
  String _query = '';

  // Estado editável.
  late String _role;
  late bool _hasAppAccess;
  late bool _isPublic;
  Set<String> _selected = {};

  // Snapshot inicial p/ detectar alterações.
  late String _role0;
  late bool _app0;
  late bool _pub0;
  Set<String> _selected0 = {};

  Color get _accent => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF818CF8)
      : const Color(0xFF6366F1);

  @override
  void initState() {
    super.initState();
    _role = widget.user.role.toLowerCase();
    _hasAppAccess = widget.user.hasAppAccess;
    _isPublic = widget.user.isAvailableForPublicSite;
    _search.addListener(() {
      final v = _search.text.trim().toLowerCase();
      if (v == _query) return;
      setState(() => _query = v);
    });
    _bootstrap();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final svc = AdminUsersService.instance;
    final results = await Future.wait([
      svc.getUserById(widget.user.id),
      svc.getPermissionCatalog(),
    ]);
    if (!mounted) return;
    final detailRes = results[0];
    final catalogRes = results[1];

    if (catalogRes.success && catalogRes.data != null) {
      final data = catalogRes.data! as Map<String, List<UserPermission>>;
      final entries = data.entries.toList()
        ..sort((a, b) => PermissionMeta.categoryLabel(a.key)
            .toLowerCase()
            .compareTo(PermissionMeta.categoryLabel(b.key).toLowerCase()));
      _catalog
        ..clear()
        ..addAll(entries);
    }

    // Detalhe é a autoridade pra papel/acesso/permissões; cai pro item da
    // lista se a chamada falhar.
    if (detailRes.success && detailRes.data != null) {
      final u = detailRes.data! as AdminUser;
      _role = u.role.toLowerCase();
      _hasAppAccess = u.hasAppAccess;
      _isPublic = u.isAvailableForPublicSite;
      _selected = {...u.permissionIds};
    } else {
      _selected = {...widget.user.permissionIds};
    }

    _role0 = _role;
    _app0 = _hasAppAccess;
    _pub0 = _isPublic;
    _selected0 = {..._selected};

    setState(() {
      _loading = false;
      if (!catalogRes.success && _catalog.isEmpty) {
        _error = catalogRes.message ?? 'Não foi possível carregar as permissões.';
      }
    });
  }

  bool get _dirty =>
      _role != _role0 ||
      _hasAppAccess != _app0 ||
      _isPublic != _pub0 ||
      !_setEquals(_selected, _selected0);

  bool _setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  int get _totalPerms =>
      _catalog.fold(0, (sum, e) => sum + e.value.length);

  bool get _isPrivileged => _role == 'admin' || _role == 'master';

  Future<void> _save() async {
    if (!_dirty || _saving) return;
    setState(() => _saving = true);
    final res = await AdminUsersService.instance.updateUser(
      widget.user.id,
      role: _role != _role0 ? _role : null,
      hasAppAccess: _role == 'user' ? _hasAppAccess : null,
      isAvailableForPublicSite: _isPublic,
      permissionIds: _selected.toList(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.success) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.status.error,
          content: Text(res.message ?? 'Falha ao salvar.'),
        ),
      );
    }
  }

  void _togglePerm(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _toggleCategory(String category, List<UserPermission> perms) {
    final ids = perms.map((p) => p.id).toSet();
    final allOn = ids.every(_selected.contains);
    setState(() {
      if (allOn) {
        _selected.removeAll(ids);
      } else {
        _selected.addAll(ids);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Editar usuário',
      showBottomNavigation: false,
      body: _loading
          ? _buildSkeleton()
          : Column(
              children: [
                Expanded(child: _buildContent()),
                _buildSaveBar(),
              ],
            ),
    );
  }

  // ─── Conteúdo ──────────────────────────────────────────────────────────

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(_padH, 16, _padH, 24),
      children: [
        _OverviewCard(user: widget.user, accent: _accent, role: _role),
        const SizedBox(height: 26),
        _SectionLabel(
          icon: LucideIcons.userCog,
          label: 'PAPEL NO SISTEMA',
          accent: _accent,
        ),
        const SizedBox(height: 12),
        _RoleSegmented(
          current: _role,
          includeMaster: _role0 == 'master',
          accent: _accent,
          onChanged: (r) => setState(() => _role = r),
        ),
        const SizedBox(height: 26),
        _SectionLabel(
          icon: LucideIcons.toggleRight,
          label: 'ACESSOS',
          accent: _accent,
        ),
        const SizedBox(height: 12),
        _buildAccessCards(),
        const SizedBox(height: 26),
        _buildPermissionsHeader(),
        const SizedBox(height: 12),
        if (_isPrivileged) ...[
          _PrivilegedNote(role: _role),
          const SizedBox(height: 12),
        ],
        if (_error != null && _catalog.isEmpty)
          _ErrorInline(message: _error!, onRetry: _bootstrap)
        else
          ..._buildCategoryCards(),
      ],
    );
  }

  Widget _buildAccessCards() {
    final isUser = _role == 'user';
    final cards = <Widget>[
      if (isUser)
        Expanded(
          child: _ToggleCard(
            icon: LucideIcons.smartphone,
            title: 'App móvel',
            subtitle: _hasAppAccess ? 'Liberado' : 'Bloqueado',
            value: _hasAppAccess,
            accent: _accent,
            onChanged: (v) => setState(() => _hasAppAccess = v),
          ),
        ),
      if (isUser) const SizedBox(width: 12),
      Expanded(
        child: _ToggleCard(
          icon: LucideIcons.globe,
          title: 'Site público',
          subtitle: _isPublic ? 'Visível' : 'Oculto',
          value: _isPublic,
          accent: const Color(0xFF10B981),
          onChanged: (v) => setState(() => _isPublic = v),
        ),
      ),
    ];
    return IntrinsicHeight(child: Row(children: cards));
  }

  Widget _buildPermissionsHeader() {
    final allExpanded = _expanded.length == _catalog.length &&
        _catalog.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(
          icon: LucideIcons.shieldCheck,
          label: 'PERMISSÕES',
          accent: _accent,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: _accent.withValues(alpha: 0.24)),
            ),
            child: Text(
              '${_selected.length} de $_totalPerms',
              style: TextStyle(
                color: _accent,
                fontWeight: FontWeight.w900,
                fontSize: 11,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildSearch()),
            const SizedBox(width: 10),
            _GhostButton(
              icon: allExpanded
                  ? LucideIcons.chevronsDownUp
                  : LucideIcons.chevronsUpDown,
              label: allExpanded ? 'Recolher' : 'Expandir',
              onTap: () => setState(() {
                if (allExpanded) {
                  _expanded.clear();
                } else {
                  _expanded.addAll(_catalog.map((e) => e.key));
                }
              }),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSearch() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hasText = _search.text.isNotEmpty;
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasText
              ? _accent.withValues(alpha: 0.42)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(LucideIcons.search,
              size: 16, color: hasText ? _accent : secondary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _search,
              cursorColor: _accent,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: ThemeHelpers.textColor(context),
              ),
              decoration: InputDecoration(
                hintText: 'Filtrar permissão…',
                hintStyle: TextStyle(
                  color: secondary.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
                filled: false,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (hasText)
            InkResponse(
              radius: 16,
              onTap: () => _search.clear(),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(LucideIcons.x, size: 14, color: secondary),
              ),
            ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  List<Widget> _buildCategoryCards() {
    final cards = <Widget>[];
    for (final entry in _catalog) {
      final category = entry.key;
      final perms = entry.value;
      // Filtro de busca: por rótulo da categoria ou ação.
      List<UserPermission> visible = perms;
      if (_query.isNotEmpty) {
        final catLabel = PermissionMeta.categoryLabel(category).toLowerCase();
        final catMatch = catLabel.contains(_query);
        visible = catMatch
            ? perms
            : perms
                .where((p) =>
                    PermissionMeta.actionLabel(p.name)
                        .toLowerCase()
                        .contains(_query) ||
                    p.name.toLowerCase().contains(_query))
                .toList();
        if (visible.isEmpty) continue;
      }
      final expanded = _query.isNotEmpty || _expanded.contains(category);
      cards.add(_CategoryCard(
        category: category,
        perms: visible,
        selected: _selected,
        accent: _accent,
        expanded: expanded,
        onToggleExpand: () => setState(() {
          if (_expanded.contains(category)) {
            _expanded.remove(category);
          } else {
            _expanded.add(category);
          }
        }),
        onTogglePerm: _togglePerm,
        onToggleAll: () => _toggleCategory(category, perms),
      ));
      cards.add(const SizedBox(height: 10));
    }
    if (cards.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Center(
            child: Text(
              'Nenhuma permissão encontrada.',
              style: TextStyle(
                color: ThemeHelpers.textSecondaryColor(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ];
    }
    return cards;
  }

  // ─── Save bar ──────────────────────────────────────────────────────────

  Widget _buildSaveBar() {
    final canSave = _dirty && !_saving;
    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          top: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        _padH,
        12,
        _padH,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        children: [
          if (_dirty) ...[
            TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Descartar'),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: FilledButton.icon(
              onPressed: canSave ? _save : null,
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                disabledBackgroundColor:
                    ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(LucideIcons.check, size: 18),
              label: Text(
                _saving
                    ? 'Salvando…'
                    : (_dirty ? 'Salvar alterações' : 'Tudo salvo'),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14.5,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Skeleton ──────────────────────────────────────────────────────────

  Widget _buildSkeleton() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(_padH, 18, _padH, 24),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        Row(
          children: [
            SkeletonBox(width: 60, height: 60, borderRadius: 18),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBox(width: 160, height: 16, borderRadius: 6),
                  SizedBox(height: 8),
                  SkeletonBox(width: 200, height: 12, borderRadius: 4),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        SkeletonBox(width: 120, height: 11, borderRadius: 999),
        const SizedBox(height: 12),
        SkeletonBox(width: double.infinity, height: 48, borderRadius: 14),
        const SizedBox(height: 24),
        SkeletonBox(width: 90, height: 11, borderRadius: 999),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: SkeletonBox(height: 76, borderRadius: 16)),
            const SizedBox(width: 12),
            Expanded(child: SkeletonBox(height: 76, borderRadius: 16)),
          ],
        ),
        const SizedBox(height: 24),
        SkeletonBox(width: 120, height: 11, borderRadius: 999),
        const SizedBox(height: 12),
        ...List.generate(
          5,
          (_) => const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: SkeletonBox(height: 60, borderRadius: 16),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Identity header (sem banner — linha de identidade refinada)
// ───────────────────────────────────────────────────────────────────────────

/// Cartão de visão geral do usuário — superfície elevada com leve tint do
/// papel, identidade (avatar + presença), badges de papel/status e uma grade
/// de metadados (telefone, CPF, último acesso, criado em).
class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.user,
    required this.accent,
    required this.role,
  });

  final AdminUser user;
  final Color accent;
  final String role;

  Color _roleColor() {
    switch (role) {
      case 'master':
        return const Color(0xFF8B5CF6);
      case 'admin':
        return const Color(0xFFE65100);
      case 'manager':
        return const Color(0xFF1E88E5);
      default:
        return accent;
    }
  }

  String _roleLabel() {
    switch (role) {
      case 'master':
        return 'Master';
      case 'admin':
        return 'Administrador';
      case 'manager':
        return 'Gerente';
      default:
        return 'Corretor';
    }
  }

  ({Color color, String label, IconData icon}) _presence() {
    if (!user.isActiveInCompany || !user.active) {
      return (
        color: const Color(0xFFA1A1AA),
        label: 'Desativado',
        icon: LucideIcons.minus,
      );
    }
    if (user.neverLoggedIn) {
      return (
        color: const Color(0xFFF59E0B),
        label: 'Nunca acessou',
        icon: LucideIcons.clock,
      );
    }
    return (
      color: const Color(0xFF10B981),
      label: 'Ativo',
      icon: LucideIcons.check,
    );
  }

  String? _maskedDocument() {
    final raw = user.document;
    if (raw == null || raw.trim().isEmpty) return null;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 2) return '***.***.***-**';
    return '***.***.***-${digits.substring(digits.length - 2)}';
  }

  String _initials() {
    final parts = user.name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final roleColor = _roleColor();
    final presence = _presence();
    final cardColor = ThemeHelpers.cardBackgroundColor(context);
    final hasPhoto = (user.avatar ?? '').trim().isNotEmpty;

    final deep = HSLColor.fromColor(roleColor)
        .withLightness(
            (HSLColor.fromColor(roleColor).lightness * 0.78).clamp(0.0, 1.0))
        .toColor();

    final lastLogin = user.lastLoginAt != null
        ? DateFormat("d 'de' MMM · HH:mm", 'pt_BR')
            .format(user.lastLoginAt!.toLocal())
        : 'Nunca';
    final created = user.createdAt != null
        ? DateFormat("d 'de' MMM yyyy", 'pt_BR')
            .format(user.createdAt!.toLocal())
        : '—';

    final avatarInner = hasPhoto
        ? Image.network(user.avatar!, width: 62, height: 62, fit: BoxFit.cover)
        : Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [roleColor, deep],
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              _initials(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 22,
                letterSpacing: 0.4,
              ),
            ),
          );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
                roleColor.withValues(alpha: isDark ? 0.10 : 0.05), cardColor),
            cardColor,
          ],
        ),
        border: Border.all(color: roleColor.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.25)
                : roleColor.withValues(alpha: 0.10),
            blurRadius: 22,
            offset: const Offset(0, 10),
            spreadRadius: -10,
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar com presença sobreposta.
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border:
                            Border.all(color: roleColor.withValues(alpha: 0.3)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: avatarInner,
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 15,
                        height: 15,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: presence.color,
                          border: Border.all(color: cardColor, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: presence.color.withValues(alpha: 0.55),
                              blurRadius: 6,
                              spreadRadius: 0.4,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name.isEmpty ? '—' : user.name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: textColor,
                        letterSpacing: -0.5,
                        height: 1.05,
                        fontSize: 20,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(LucideIcons.mail, size: 12, color: secondary),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            user.email,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: secondary,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _MiniBadge(
                          label: _roleLabel(),
                          color: roleColor,
                          icon: LucideIcons.shieldCheck,
                          isDark: isDark,
                        ),
                        _MiniBadge(
                          label: presence.label,
                          color: presence.color,
                          icon: presence.icon,
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(
            height: 1,
            color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.9),
          ),
          const SizedBox(height: 12),
          // Grade de metadados 2×2.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _MetaDatum(
                  icon: LucideIcons.phone,
                  label: 'TELEFONE',
                  value: (user.phone?.trim().isNotEmpty == true)
                      ? user.phone!.trim()
                      : '—',
                ),
              ),
              _metaDivider(context),
              Expanded(
                child: _MetaDatum(
                  icon: LucideIcons.fingerprint,
                  label: 'CPF',
                  value: _maskedDocument() ?? '—',
                  monospace: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(
            height: 1,
            color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _MetaDatum(
                  icon: LucideIcons.clock,
                  label: 'ÚLTIMO ACESSO',
                  value: lastLogin,
                  valueColor: user.neverLoggedIn
                      ? const Color(0xFFF59E0B)
                      : null,
                ),
              ),
              _metaDivider(context),
              Expanded(
                child: _MetaDatum(
                  icon: LucideIcons.calendar,
                  label: 'MEMBRO DESDE',
                  value: created,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metaDivider(BuildContext context) => Container(
        width: 1,
        height: 34,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.7),
      );
}

/// Badge compacto (papel / status) usado no cartão de visão geral.
class _MiniBadge extends StatelessWidget {
  const _MiniBadge({
    required this.label,
    required this.color,
    required this.icon,
    required this.isDark,
  });

  final String label;
  final Color color;
  final IconData icon;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: isDark ? 0.36 : 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 10.5,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Célula de metadado — rótulo uppercase pequeno + valor em destaque.
class _MetaDatum extends StatelessWidget {
  const _MetaDatum({
    required this.icon,
    required this.label,
    required this.value,
    this.monospace = false,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool monospace;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final textColor = ThemeHelpers.textColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 11, color: secondary),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: secondary,
                  height: 1.0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: valueColor ?? textColor,
            letterSpacing: monospace ? 0.4 : -0.1,
            fontFamily: monospace ? 'monospace' : null,
            height: 1.15,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Section label
// ───────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.label,
    required this.accent,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(7),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 12, color: accent),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.6,
            color: accent,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.8),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          trailing!,
        ],
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Role segmented
// ───────────────────────────────────────────────────────────────────────────

class _RoleSegmented extends StatelessWidget {
  const _RoleSegmented({
    required this.current,
    required this.includeMaster,
    required this.accent,
    required this.onChanged,
  });

  final String current;
  final bool includeMaster;
  final Color accent;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = <({String value, String label, IconData icon})>[
      (value: 'user', label: 'Corretor', icon: LucideIcons.user),
      (value: 'manager', label: 'Gerente', icon: LucideIcons.briefcase),
      (value: 'admin', label: 'Admin', icon: LucideIcons.shieldCheck),
      if (includeMaster)
        (value: 'master', label: 'Master', icon: LucideIcons.crown),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          for (final it in items)
            Expanded(
              child: _RoleChip(
                label: it.label,
                icon: it.icon,
                selected: current == it.value,
                accent: accent,
                onTap: () => onChanged(it.value),
              ),
            ),
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : ThemeHelpers.textSecondaryColor(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                    spreadRadius: -4,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Toggle card (acessos)
// ───────────────────────────────────────────────────────────────────────────

class _ToggleCard extends StatelessWidget {
  const _ToggleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.fromLTRB(13, 12, 10, 12),
        decoration: BoxDecoration(
          color: value
              ? accent.withValues(alpha: 0.06)
              : ThemeHelpers.cardBackgroundColor(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: value
                ? accent.withValues(alpha: 0.4)
                : ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: value
                        ? accent.withValues(alpha: 0.16)
                        : ThemeHelpers.borderColor(context)
                            .withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon,
                      size: 16, color: value ? accent : secondary),
                ),
                const Spacer(),
                SizedBox(
                  height: 24,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Switch(
                      value: value,
                      onChanged: onChanged,
                      activeTrackColor: accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: value ? accent : secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Category card (permissões — expansível)
// ───────────────────────────────────────────────────────────────────────────

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.perms,
    required this.selected,
    required this.accent,
    required this.expanded,
    required this.onToggleExpand,
    required this.onTogglePerm,
    required this.onToggleAll,
  });

  final String category;
  final List<UserPermission> perms;
  final Set<String> selected;
  final Color accent;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final ValueChanged<String> onTogglePerm;
  final VoidCallback onToggleAll;

  @override
  Widget build(BuildContext context) {
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final label = PermissionMeta.categoryLabel(category);
    final icon = PermissionMeta.categoryIcon(category);
    final total = perms.length;
    final active = perms.where((p) => selected.contains(p.id)).length;
    final allOn = active == total && total > 0;
    final frac = total == 0 ? 0.0 : active / total;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active > 0
              ? accent.withValues(alpha: 0.3)
              : ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: onToggleExpand,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Row(
                children: [
                  // Ícone com anel de progresso.
                  SizedBox(
                    width: 38,
                    height: 38,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 38,
                          height: 38,
                          child: CircularProgressIndicator(
                            value: frac,
                            strokeWidth: 2.4,
                            backgroundColor: ThemeHelpers.borderColor(context)
                                .withValues(alpha: 0.5),
                            valueColor:
                                AlwaysStoppedAnimation(accent),
                          ),
                        ),
                        Icon(icon,
                            size: 16,
                            color: active > 0 ? accent : secondary),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: textColor,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$active de $total ativas',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: active > 0 ? accent : secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(LucideIcons.chevronDown,
                        size: 18, color: secondary),
                  ),
                ],
              ),
            ),
          ),
          // Body
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(
                    height: 1,
                    color: ThemeHelpers.borderLightColor(context),
                  ),
                  const SizedBox(height: 10),
                  // Ação "Marcar tudo".
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: onToggleAll,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            allOn
                                ? LucideIcons.squareCheckBig
                                : LucideIcons.square,
                            size: 14,
                            color: accent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            allOn ? 'Desmarcar tudo' : 'Marcar tudo',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: accent,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Grade 2-col de toggles de permissão.
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in perms)
                        _PermChip(
                          label: PermissionMeta.actionLabel(p.name),
                          selected: selected.contains(p.id),
                          accent: accent,
                          onTap: () => onTogglePerm(p.id),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

/// Chip-toggle de uma permissão. Largura ~metade da linha (grade 2-col).
class _PermChip extends StatelessWidget {
  const _PermChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    // 2 colunas: (largura total - padding pai 24 - spacing 8) / 2.
    final w = (MediaQuery.sizeOf(context).width - 40 - 24 - 8) / 2;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: w,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.5)
                : ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: selected ? accent : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: selected
                      ? accent
                      : ThemeHelpers.borderColor(context).withValues(alpha: 0.8),
                  width: 1.6,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      size: 13, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? ThemeHelpers.textColor(context)
                      : secondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Misc
// ───────────────────────────────────────────────────────────────────────────

class _GhostButton extends StatelessWidget {
  const _GhostButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: secondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivilegedNote extends StatelessWidget {
  const _PrivilegedNote({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone =
        isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.info, size: 16, color: tone),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${role == 'master' ? 'Master' : 'Administradores'} têm acesso '
              'total — permissões individuais são ignoradas pelo sistema.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: tone,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorInline extends StatelessWidget {
  const _ErrorInline({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(LucideIcons.cloudOff,
              size: 30, color: ThemeHelpers.textSecondaryColor(context)),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(LucideIcons.refreshCw, size: 15),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}
