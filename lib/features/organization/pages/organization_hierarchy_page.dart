import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/org_user_model.dart';
import '../organization_access.dart';
import '../services/hierarchy_service.dart';
import '../widgets/org_ui.dart';

enum _HierarchyTab { tree, assign }

/// Tela **Hierarquia de Gestores** — árvore visual da estrutura + atribuição
/// de gestor aos colaboradores (paridade com o `HierarchyPage.tsx` do painel;
/// acesso restrito a admin/master).
class OrganizationHierarchyPage extends StatefulWidget {
  const OrganizationHierarchyPage({super.key});

  @override
  State<OrganizationHierarchyPage> createState() =>
      _OrganizationHierarchyPageState();
}

class _OrganizationHierarchyPageState
    extends State<OrganizationHierarchyPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const double _kSectionGap = 12;

  _HierarchyTab _tab = _HierarchyTab.tree;

  List<OrgUser> _users = const [];
  List<OrgUser> _managersFromApi = const [];
  bool _loading = true;
  String? _error;

  final Set<String> _expanded = {};

  // Atribuição
  String? _selectedManagerId;
  final Set<String> _selectedUserIds = {};
  final TextEditingController _searchController = TextEditingController();
  String _search = '';
  bool _assigning = false;

  bool get _canView => OrganizationAccess.canViewHierarchy();

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

  // ─── Cores ───────────────────────────────────────────────────────────────

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Color get _accent =>
      _isDark ? AppColors.status.infoDarkMode : AppColors.status.info;

  Color get _purple =>
      _isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;

  Color get _green =>
      _isDark ? AppColors.status.greenDarkMode : AppColors.status.green;

  Color get _amber =>
      _isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;

  Color get _danger =>
      _isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

  Color _roleTone(OrgUserRole role) {
    switch (role) {
      case OrgUserRole.master:
        return _danger;
      case OrgUserRole.admin:
        return _purple;
      case OrgUserRole.manager:
        return _accent;
      case OrgUserRole.user:
      case OrgUserRole.unknown:
        return ThemeHelpers.textSecondaryColor(context);
    }
  }

  IconData _roleIcon(OrgUserRole role) {
    switch (role) {
      case OrgUserRole.master:
        return LucideIcons.crown;
      case OrgUserRole.admin:
        return LucideIcons.shieldCheck;
      case OrgUserRole.manager:
        return LucideIcons.userCog;
      case OrgUserRole.user:
      case OrgUserRole.unknown:
        return LucideIcons.user;
    }
  }

  // ─── Dados ───────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final results = await Future.wait([
      HierarchyService.instance.getUsers(),
      HierarchyService.instance.getUsers(role: 'manager'),
    ]);
    if (!mounted) return;
    final usersRes = results[0];
    final managersRes = results[1];
    setState(() {
      _loading = false;
      if (usersRes.success && usersRes.data != null) {
        _users = usersRes.data!;
        _managersFromApi =
            managersRes.success ? (managersRes.data ?? const []) : const [];
        // Auto-expande nós com filhos (paridade web).
        _expanded
          ..clear()
          ..addAll(_users
              .where((u) => _users.any((c) => c.managerId == u.id))
              .map((u) => u.id));
      } else {
        _error = usersRes.message ?? 'Erro ao carregar usuários';
      }
    });
  }

  /// Gestores: role manager da API + quem já tem subordinados (paridade web).
  List<OrgUser> get _managers {
    final withSubordinates = _users.where((u) =>
        _users.any((other) => other.managerId == u.id) &&
        !_managersFromApi.any((m) => m.id == u.id));
    return [..._managersFromApi, ...withSubordinates];
  }

  List<OrgUser> get _collaborators =>
      _users.where((u) => u.role == OrgUserRole.user).toList();

  List<OrgUser> get _filteredCollaborators {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _collaborators;
    return _collaborators
        .where((u) =>
            u.name.toLowerCase().contains(q) ||
            u.email.toLowerCase().contains(q))
        .toList();
  }

  List<OrgUser> get _rootUsers =>
      _users.where((u) => u.managerId == null).toList();

  List<OrgUser> _childrenOf(String id) =>
      _users.where((u) => u.managerId == id).toList();

  bool get _hasHierarchy => _users.any((u) => u.managerId != null);

  int get _linkedCount => _users.where((u) => u.managerId != null).length;

  int get _unlinkedCount => _collaborators
      .where((u) => u.managerId == null)
      .length;

  // ─── Ações ───────────────────────────────────────────────────────────────

  Future<void> _assign() async {
    final managerId = _selectedManagerId;
    if (managerId == null) {
      _snack('Selecione um gestor primeiro.');
      return;
    }
    if (_selectedUserIds.isEmpty) {
      _snack('Selecione pelo menos um colaborador.');
      return;
    }
    setState(() => _assigning = true);
    final res = await HierarchyService.instance.assignManager(
      userIds: _selectedUserIds.toList(),
      managerId: managerId,
    );
    if (!mounted) return;
    setState(() => _assigning = false);
    if (res.success) {
      _snack(res.data ?? 'Gestor atribuído com sucesso!');
      setState(() {
        _selectedManagerId = null;
        _selectedUserIds.clear();
      });
      _load();
    } else {
      _snack(res.message ?? 'Erro ao atribuir gestor');
    }
  }

  Future<void> _unlink(OrgUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Desvincular do gestor'),
        content: Text(
          'Remover o vínculo de "${user.name}" com o gestor atual? '
          'A pessoa volta para a raiz da estrutura.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Desvincular'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final res =
        await HierarchyService.instance.removeManager(userIds: [user.id]);
    if (!mounted) return;
    if (res.success) {
      _snack(res.data ?? 'Gestor removido com sucesso!');
      _load();
    } else {
      _snack(res.message ?? 'Erro ao remover gestor');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canView) {
      return const AppScaffold(
        title: 'Hierarquia',
        showBottomNavigation: false,
        body: OrgDeniedView(
          message: 'Acesso negado.',
          hint: 'Apenas Administradores e Masters podem acessar a hierarquia.',
        ),
      );
    }
    return AppScaffold(
      title: 'Hierarquia',
      showBottomNavigation: false,
      body: RefreshIndicator(
        color: _accent,
        onRefresh: _load,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        _kPagePadH, _kPagePadTop, _kPagePadH, 0),
                    child: _buildHero(context),
                  ),
                  const SizedBox(height: _kSectionGap),
                  _buildTabsRail(context),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        _kPagePadH, _kSectionGap, _kPagePadH, _kPagePadBottom),
                    child: _buildActivePanel(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Hero ────────────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    final total = _users.length;
    final dot = _hasHierarchy ? _green : _amber;
    final subtitle = total == 0
        ? 'A estrutura da empresa aparece aqui assim que houver usuários.'
        : _hasHierarchy
            ? '$_linkedCount vinculado${_linkedCount == 1 ? '' : 's'} a '
                'gestor · $_unlinkedCount sem gestor'
            : 'Nenhuma hierarquia estruturada — atribua gestores na aba '
                '"Atribuir".';

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dot,
                  boxShadow: [
                    BoxShadow(
                      color: dot.withValues(alpha: 0.55),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              Text(
                'HIERARQUIA DE GESTORES',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _accent,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.2,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _loading ? '—' : '$total',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: textColor,
                  height: 1.0,
                  letterSpacing: -1.0,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  total == 1 ? 'pessoa' : 'pessoas',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: secondary,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          OrgHeroKpiStrip(blocks: [
            OrgHeroKpi(
              icon: LucideIcons.userCog,
              label: 'GESTORES',
              value: _loading ? '—' : '${_managers.length}',
              sub: 'com equipe',
              tone: _accent,
            ),
            OrgHeroKpi(
              icon: LucideIcons.gitFork,
              label: 'VINCULADOS',
              value: _loading ? '—' : '$_linkedCount',
              sub: 'com gestor',
              tone: _green,
            ),
            OrgHeroKpi(
              icon: LucideIcons.userMinus,
              label: 'SEM GESTOR',
              value: _loading ? '—' : '$_unlinkedCount',
              sub: 'corretores soltos',
              tone: _amber,
            ),
          ]),
        ],
      ),
    );
  }

  // ─── Abas ────────────────────────────────────────────────────────────────

  Widget _buildTabsRail(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: _kPagePadH - 8),
      child: Row(
        children: [
          Expanded(
            child: OrgFlushTab(
              icon: LucideIcons.listTree,
              label: 'Estrutura',
              count: _rootUsers.length,
              tone: _accent,
              selected: _tab == _HierarchyTab.tree,
              onTap: () => setState(() => _tab = _HierarchyTab.tree),
            ),
          ),
          Expanded(
            child: OrgFlushTab(
              icon: LucideIcons.userPlus,
              label: 'Atribuir',
              count: _selectedUserIds.length,
              tone: _purple,
              selected: _tab == _HierarchyTab.assign,
              onTap: () => setState(() => _tab = _HierarchyTab.assign),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Painéis ─────────────────────────────────────────────────────────────

  Widget _buildActivePanel(BuildContext context) {
    Widget child;
    if (_loading && _users.isEmpty) {
      child = _buildSkeleton();
    } else if (_error != null && _users.isEmpty) {
      child = OrgErrorState(message: _error!, onRetry: _load);
    } else if (_tab == _HierarchyTab.tree) {
      child = _buildTreePanel(context);
    } else {
      child = _buildAssignPanel(context);
    }

    final meta = _tab == _HierarchyTab.tree
        ? (
            icon: LucideIcons.listTree,
            eyebrow: 'ESTRUTURA',
            title: 'Árvore da empresa',
            hint: 'Toque num nó com subordinados para expandir ou recolher.',
            tone: _accent,
          )
        : (
            icon: LucideIcons.userPlus,
            eyebrow: 'ATRIBUIR GESTOR',
            title: 'Vincular colaboradores',
            hint: 'Escolha o gestor e marque quem passa a responder a ele.',
            tone: _purple,
          );

    return Column(
      key: ValueKey('panel-${_tab.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OrgPanelHeader(
          icon: meta.icon,
          eyebrow: meta.eyebrow,
          title: meta.title,
          hint: meta.hint,
          tone: meta.tone,
        ),
        const SizedBox(height: 14),
        child,
      ],
    ).animate(key: ValueKey('panel-${_tab.name}')).fadeIn(duration: 240.ms);
  }

  // ─── Árvore ──────────────────────────────────────────────────────────────

  Widget _buildTreePanel(BuildContext context) {
    if (_users.isEmpty) {
      return OrgEmptyState(
        icon: LucideIcons.users2,
        title: 'Nenhum usuário cadastrado',
        body: 'Crie usuários no painel e atribua gestores na aba "Atribuir".',
        tone: _accent,
      );
    }
    if (!_hasHierarchy) {
      return OrgEmptyState(
        icon: LucideIcons.network,
        title: 'Nenhuma hierarquia estruturada',
        body: 'Atribua gestores aos colaboradores na aba "Atribuir" para '
            'montar a árvore.',
        tone: _accent,
        action: OutlinedButton.icon(
          onPressed: () => setState(() => _tab = _HierarchyTab.assign),
          style: OutlinedButton.styleFrom(
            foregroundColor: _purple,
            side: BorderSide(color: _purple.withValues(alpha: 0.45)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(LucideIcons.userPlus, size: 16),
          label: const Text('Atribuir gestor'),
        ),
      );
    }

    var animIndex = 0;
    final nodes = <Widget>[];
    for (final root in _rootUsers) {
      nodes.add(_buildTreeNode(context, root, 0, animIndex++));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: nodes,
    );
  }

  Widget _buildTreeNode(
      BuildContext context, OrgUser user, int level, int animIndex) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final children = _childrenOf(user.id);
    final hasChildren = children.isNotEmpty;
    final expanded = _expanded.contains(user.id);
    final tone = _roleTone(user.role);

    final row = Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(14),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: hasChildren
              ? () => setState(() {
                    if (!_expanded.remove(user.id)) _expanded.add(user.id);
                  })
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                if (hasChildren)
                  AnimatedRotation(
                    turns: expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(LucideIcons.chevronRight,
                        size: 17, color: secondary),
                  )
                else
                  const SizedBox(width: 17),
                const SizedBox(width: 8),
                OrgAvatar(
                  name: user.name,
                  imageUrl: user.avatar,
                  tone: tone,
                  size: 34,
                ),
                const SizedBox(width: 10),
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
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OrgMiniPill(
                            label: user.role.label,
                            tone: tone,
                            icon: _roleIcon(user.role),
                          ),
                          if (hasChildren)
                            Text(
                              '${children.length} subordinado'
                              '${children.length == 1 ? '' : 's'}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: secondary,
                                fontWeight: FontWeight.w700,
                                fontSize: 10.5,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (user.managerId != null)
                  IconButton(
                    tooltip: 'Desvincular do gestor',
                    onPressed: () => _unlink(user),
                    visualDensity: VisualDensity.compact,
                    icon: Icon(LucideIcons.unlink, size: 15, color: secondary),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(left: level == 0 ? 0 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row
              .animate(key: ValueKey('node-${user.id}'))
              .fadeIn(
                delay: Duration(milliseconds: 25 * animIndex.clamp(0, 12)),
                duration: 200.ms,
              ),
          if (hasChildren && expanded)
            Container(
              margin: const EdgeInsets.only(left: 16),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: _accent.withValues(alpha: 0.28),
                    width: 1.6,
                  ),
                ),
              ),
              padding: const EdgeInsets.only(left: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final child in children)
                    _buildTreeNode(context, child, 1, animIndex++),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ─── Atribuir ────────────────────────────────────────────────────────────

  Widget _buildAssignPanel(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final managers = _managers;
    final selectedManager = managers
        .where((m) => m.id == _selectedManagerId)
        .cast<OrgUser?>()
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OrgSubsectionHeader(
          label: '1 · Gestor responsável',
          icon: LucideIcons.userCog,
          count: 0,
        ),
        const SizedBox(height: 10),
        if (managers.isEmpty)
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: _amber.withValues(alpha: _isDark ? 0.14 : 0.09),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: _amber.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.triangleAlert, size: 17, color: _amber),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Nenhum gestor cadastrado. Cadastre usuários com papel '
                    '"Gestor" primeiro.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _pickManager(managers),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  color: ThemeHelpers.cardBackgroundColor(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selectedManager != null
                        ? _purple.withValues(alpha: 0.45)
                        : ThemeHelpers.borderColor(context)
                            .withValues(alpha: 0.55),
                    width: selectedManager != null ? 1.3 : 1,
                  ),
                  boxShadow: ThemeHelpers.cardShadow(context),
                ),
                child: Row(
                  children: [
                    if (selectedManager != null) ...[
                      OrgAvatar(
                        name: selectedManager.name,
                        imageUrl: selectedManager.avatar,
                        tone: _purple,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selectedManager.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: ThemeHelpers.textColor(context),
                              ),
                            ),
                            Text(
                              selectedManager.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: secondary,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              _purple.withValues(alpha: _isDark ? 0.2 : 0.1),
                        ),
                        child:
                            Icon(LucideIcons.userCog, size: 17, color: _purple),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Escolher gestor…',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: secondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    Icon(LucideIcons.chevronDown, size: 17, color: secondary),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 18),
        OrgSubsectionHeader(
          label: '2 · Colaboradores',
          icon: LucideIcons.users2,
          count: _selectedUserIds.length,
        ),
        const SizedBox(height: 10),
        OrgSearchField(
          controller: _searchController,
          hint: 'Buscar por nome ou e-mail…',
          accent: _purple,
          onChanged: (v) => setState(() => _search = v),
        ),
        const SizedBox(height: 10),
        if (_filteredCollaborators.isEmpty)
          OrgEmptyState(
            icon: LucideIcons.searchX,
            title: 'Nenhum colaborador encontrado',
            body: _search.trim().isEmpty
                ? 'Não há corretores para vincular.'
                : 'Nada corresponde a "${_search.trim()}".',
            tone: _purple,
          )
        else
          ..._filteredCollaborators.map((u) => _collaboratorRow(context, u)),
        const SizedBox(height: 8),
        if (_selectedUserIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '${_selectedUserIds.length} colaborador'
              '${_selectedUserIds.length == 1 ? '' : 'es'} selecionado'
              '${_selectedUserIds.length == 1 ? '' : 's'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: _purple,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        Row(
          children: [
            if (_selectedUserIds.isNotEmpty)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _assigning
                      ? null
                      : () => setState(() {
                            _selectedManagerId = null;
                            _selectedUserIds.clear();
                          }),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: secondary,
                    side:
                        BorderSide(color: ThemeHelpers.borderColor(context)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  icon: const Icon(LucideIcons.x, size: 15),
                  label: const Text('Limpar'),
                ),
              ),
            if (_selectedUserIds.isNotEmpty) const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _assigning ||
                        managers.isEmpty ||
                        _selectedManagerId == null ||
                        _selectedUserIds.isEmpty
                    ? null
                    : _assign,
                style: FilledButton.styleFrom(
                  backgroundColor: _purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                icon: _assigning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(LucideIcons.check, size: 16),
                label: Text(_assigning ? 'Atribuindo…' : 'Atribuir gestor'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _collaboratorRow(BuildContext context, OrgUser user) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final selected = _selectedUserIds.contains(user.id);
    final managerName = user.managerId == null
        ? null
        : _users
            .where((m) => m.id == user.managerId)
            .cast<OrgUser?>()
            .firstOrNull
            ?.name;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() {
            if (!_selectedUserIds.remove(user.id)) {
              _selectedUserIds.add(user.id);
            }
          }),
          borderRadius: BorderRadius.circular(13),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: selected
                  ? _purple.withValues(alpha: _isDark ? 0.12 : 0.07)
                  : ThemeHelpers.cardBackgroundColor(context),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: selected
                    ? _purple.withValues(alpha: 0.45)
                    : ThemeHelpers.borderColor(context)
                        .withValues(alpha: 0.55),
                width: selected ? 1.3 : 1,
              ),
            ),
            child: Row(
              children: [
                OrgAvatar(
                  name: user.name,
                  imageUrl: user.avatar,
                  tone: selected ? _purple : secondary,
                ),
                const SizedBox(width: 10),
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
                      Text(
                        managerName != null
                            ? '${user.email} · gestor: $managerName'
                            : user.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? _green : Colors.transparent,
                    border: Border.all(
                      color: selected
                          ? _green
                          : ThemeHelpers.borderColor(context),
                      width: 1.6,
                    ),
                  ),
                  child: selected
                      ? const Icon(LucideIcons.check,
                          size: 13, color: Colors.white)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _pickManager(List<OrgUser> managers) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => _ManagerPickerSheet(
        managers: managers,
        selectedId: _selectedManagerId,
        accent: _purple,
        onPicked: (id) => setState(() => _selectedManagerId = id),
      ),
    );
  }

  // ─── Skeleton ────────────────────────────────────────────────────────────

  /// Skeleton fiel aos nós da árvore (chevron + avatar + linhas + pill).
  Widget _buildSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(
        6,
        (i) => Container(
          margin: EdgeInsets.only(bottom: 8, left: i.isOdd ? 30 : 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: BorderRadius.circular(14),
            boxShadow: ThemeHelpers.cardShadow(context),
          ),
          child: Row(
            children: [
              SkeletonBox(width: 34, height: 34, borderRadius: 999),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonText(width: 130, height: 14),
                    SizedBox(height: 7),
                    SkeletonText(width: 80, height: 11, borderRadius: 999),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Seletor de gestor (bottom sheet com busca) ──────────────────────────────

class _ManagerPickerSheet extends StatefulWidget {
  final List<OrgUser> managers;
  final String? selectedId;
  final Color accent;
  final ValueChanged<String> onPicked;

  const _ManagerPickerSheet({
    required this.managers,
    required this.selectedId,
    required this.accent,
    required this.onPicked,
  });

  @override
  State<_ManagerPickerSheet> createState() => _ManagerPickerSheetState();
}

class _ManagerPickerSheetState extends State<_ManagerPickerSheet> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<OrgUser> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.managers;
    return widget.managers
        .where((m) =>
            m.name.toLowerCase().contains(q) ||
            m.email.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final accent = widget.accent;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scrollController) => Container(
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: accent.withValues(alpha: isDark ? 0.2 : 0.12),
                    ),
                    child: Icon(LucideIcons.userCog, color: accent, size: 19),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      'Escolher gestor',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(LucideIcons.x, size: 20, color: secondary),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: OrgSearchField(
                controller: _controller,
                hint: 'Buscar gestor…',
                accent: accent,
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                itemCount: _filtered.length,
                itemBuilder: (context, index) {
                  final manager = _filtered[index];
                  final selected = manager.id == widget.selectedId;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          widget.onPicked(manager.id);
                          Navigator.of(context).pop();
                        },
                        borderRadius: BorderRadius.circular(13),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: selected
                                ? accent
                                    .withValues(alpha: isDark ? 0.12 : 0.07)
                                : ThemeHelpers.cardBackgroundColor(context),
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(
                              color: selected
                                  ? accent.withValues(alpha: 0.45)
                                  : ThemeHelpers.borderColor(context)
                                      .withValues(alpha: 0.55),
                              width: selected ? 1.3 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              OrgAvatar(
                                name: manager.name,
                                imageUrl: manager.avatar,
                                tone: accent,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      manager.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color:
                                            ThemeHelpers.textColor(context),
                                      ),
                                    ),
                                    Text(
                                      manager.email,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                        color: secondary,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (selected)
                                Icon(LucideIcons.check,
                                    size: 17, color: accent),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
