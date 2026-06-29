import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_permissions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/state/screen_state_cache.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/admin_user_model.dart';
import '../services/admin_users_service.dart';
import '../widgets/users_filters_sheet.dart';
import 'edit_user_page.dart';

/// Tela de Colaboradores → Usuários.
///
/// Paridade visual com `imobx-front` `UsersPage.tsx` (cards de usuário,
/// hero com stats, busca debounced + filtros), adaptado pra mobile.
class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  static const String _stateCacheKey = 'workspace/users';
  static const int _pageSize = 20;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _loading = true;
  bool _loadingMore = false;
  bool _refetching = false;
  String? _error;

  List<AdminUser> _users = [];
  int _page = 1;
  int _totalPages = 1;
  int _total = 0;

  AdminUsersStats? _stats;

  // Filtros
  String _search = '';
  UsersFilters _filters = const UsersFilters();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _restoreCachedState();
    _searchController.addListener(() {
      final v = _searchController.text;
      if (v == _search) return;
      _search = v;
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 420), () {
        if (!mounted) return;
        _persistState();
        _reload();
      });
    });
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _reload();
      _loadStats();
    });
  }

  void _restoreCachedState() {
    final cached = ScreenStateCache.instance.read<Map<String, dynamic>>(
      _stateCacheKey,
    );
    if (cached == null) return;
    final s = cached['search']?.toString() ?? '';
    if (s.isNotEmpty) {
      _search = s;
      _searchController.text = s;
    }
    final f = cached['filters'];
    if (f is Map) {
      _filters = UsersFilters.fromMap(Map<String, dynamic>.from(f));
    }
  }

  void _persistState() {
    ScreenStateCache.instance.save(
      _stateCacheKey,
      {
        'search': _search,
        'filters': _filters.toMap(),
      },
      ttl: const Duration(minutes: 15),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    _persistState();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || _loading) return;
    if (_page >= _totalPages) return;
    if (!_scrollController.hasClients) return;
    final p = _scrollController.position;
    if (p.pixels >= p.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _refetching = _users.isNotEmpty;
      _error = null;
      _page = 1;
    });
    final res = await AdminUsersService.instance.listUsers(
      page: 1,
      limit: _pageSize,
      search: _search.trim().isEmpty ? null : _search.trim(),
      role: _filters.role,
      active: _filters.active,
      includeInactiveCompanyUsers: _filters.includeInactiveCompanyUsers,
      hasAvatar: _filters.hasAvatar,
      dateRange: _filters.dateRange,
      neverLoggedIn: _filters.neverLoggedIn,
      lastLoginFrom: _filters.lastLoginFrom,
      lastLoginTo: _filters.lastLoginTo,
      onlyMyData: _filters.onlyMyData,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _refetching = false;
      if (res.success && res.data != null) {
        _users = res.data!.users;
        _page = res.data!.page;
        _totalPages = res.data!.totalPages;
        _total = res.data!.total;
      } else {
        _error = res.message ?? 'Erro ao listar usuários';
      }
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    final next = _page + 1;
    final res = await AdminUsersService.instance.listUsers(
      page: next,
      limit: _pageSize,
      search: _search.trim().isEmpty ? null : _search.trim(),
      role: _filters.role,
      active: _filters.active,
      includeInactiveCompanyUsers: _filters.includeInactiveCompanyUsers,
      hasAvatar: _filters.hasAvatar,
      dateRange: _filters.dateRange,
      neverLoggedIn: _filters.neverLoggedIn,
      lastLoginFrom: _filters.lastLoginFrom,
      lastLoginTo: _filters.lastLoginTo,
      onlyMyData: _filters.onlyMyData,
    );
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (res.success && res.data != null) {
        _users.addAll(res.data!.users);
        _page = res.data!.page;
        _totalPages = res.data!.totalPages;
      }
    });
  }

  Future<void> _loadStats() async {
    final res = await AdminUsersService.instance.getStats();
    if (!mounted) return;
    if (res.success && res.data != null) {
      setState(() => _stats = res.data);
    }
  }

  Future<void> _openFilters() async {
    final updated = await showModalBottomSheet<UsersFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UsersFiltersSheet(initial: _filters),
    );
    if (updated == null) return;
    setState(() => _filters = updated);
    _persistState();
    _reload();
  }

  void _clearAll() {
    _searchController.clear();
    setState(() {
      _search = '';
      _filters = const UsersFilters();
    });
    _persistState();
    _reload();
  }

  Future<void> _openEdit(AdminUser u) async {
    final canEdit = ModuleAccessService.instance.hasPermission(
      AppPermissions.userUpdate,
    );
    if (!canEdit) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditUserPage(user: u)),
    );
    if (changed == true && mounted) {
      await _reload();
      await _loadStats();
    }
  }

  Future<void> _toggleActive(AdminUser u) async {
    final canEdit = ModuleAccessService.instance.hasPermission(
      AppPermissions.userUpdate,
    );
    if (!canEdit) return;
    final next = !u.active;
    final res = await AdminUsersService.instance.setActive(u.id, next);
    if (!mounted) return;
    if (res.success) {
      setState(() {
        final idx = _users.indexWhere((x) => x.id == u.id);
        if (idx >= 0) {
          _users[idx] = AdminUser(
            id: u.id,
            name: u.name,
            email: u.email,
            role: u.role,
            active: next,
            isActiveInCompany: u.isActiveInCompany,
            avatar: u.avatar,
            phone: u.phone,
            document: u.document,
            hasAppAccess: u.hasAppAccess,
            isAvailableForPublicSite: u.isAvailableForPublicSite,
            lastLoginAt: u.lastLoginAt,
            createdAt: u.createdAt,
            updatedAt: u.updatedAt,
          );
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(next ? 'Usuário ativado.' : 'Usuário desativado.'),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message ?? 'Falha ao atualizar.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canView = ModuleAccessService.instance.hasPermission(
          AppPermissions.userView,
        ) ||
        ModuleAccessService.instance.hasCompanyModule('user_management');

    if (!canView) {
      return const AppScaffold(
        title: 'Usuários',
        showBottomNavigation: false,
        body: _UsersDeniedView(),
      );
    }

    final filterCount = _filters.activeCount;
    final hasAnyFilter = filterCount > 0 || _search.trim().isNotEmpty;

    return AppScaffold(
      title: 'Usuários',
      showBottomNavigation: false,
      body: RefreshIndicator(
        onRefresh: () async {
          await _reload();
          await _loadStats();
        },
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            _Hero(stats: _stats, total: _total),
            const SizedBox(height: 16),
            _Toolbar(
              controller: _searchController,
              onFilterTap: _openFilters,
              filterCount: filterCount,
              onClearAll: hasAnyFilter ? _clearAll : null,
            ),
            const SizedBox(height: 12),
            if (_loading)
              const _UsersShimmer()
            else if (_error != null)
              _ErrorBlock(message: _error!, onRetry: _reload)
            else if (_users.isEmpty)
              const _EmptyBlock()
            else
              _UsersList(
                users: _users,
                onToggleActive: _toggleActive,
                onOpenEdit: _openEdit,
              ),
            if (_loadingMore)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                ),
              ),
            if (_refetching && !_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Center(
                  child: Text(
                    'Atualizando…',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Hero (eyebrow + título + subtítulo + stats inline)
// ──────────────────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero({required this.stats, required this.total});

  final AdminUsersStats? stats;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondaryColor = ThemeHelpers.textSecondaryColor(context);
    final formatter = NumberFormat.decimalPattern('pt_BR');

    // Paleta editorial — emerald pra "vivos / ativos", violet pra hierarquia,
    // amber pra fluxo (novos/mês), slate pra texto secundário.
    final emerald =
        isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
    final indigo =
        isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1);
    final violet =
        isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED);
    final amber =
        isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);

    final displayTotal = stats?.total ?? total;
    final regulars = stats?.regulars ?? 0;
    final admins = stats?.admins ?? 0;
    final newThisMonth = stats?.newThisMonth ?? 0;

    // Linha de contexto curta sob o título — adapta o tom conforme dados.
    final subtitle = displayTotal == 0
        ? 'Convide o primeiro membro pra começar a montar sua equipe.'
        : (newThisMonth > 0
            ? '$newThisMonth ${newThisMonth == 1 ? 'novo' : 'novos'} este mês · $regulars regulares · $admins administradores'
            : '$regulars regulares · $admins administradores');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Eyebrow editorial: dot esmeralda pulsante + label uppercase.
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: emerald,
                  boxShadow: [
                    BoxShadow(
                      color: emerald.withValues(alpha: 0.55),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              Text(
                'COLABORADORES · USUÁRIOS',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: emerald,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.2,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Headline com número grande + rótulo pequeno alinhados na base.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatter.format(displayTotal),
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
                  displayTotal == 1 ? 'usuário' : 'usuários',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: secondaryColor,
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
              color: secondaryColor,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          // Strip editorial — 4 colunas separadas por 1px vertical.
          // Mesmo padrão usado no hero de Equipes pra consistência.
          _HeroKpiStrip(
            blocks: [
              _HeroKpiBlock(
                icon: LucideIcons.userCheck,
                label: 'REGULARES',
                value: '$regulars',
                sub: displayTotal > 0
                    ? '${((regulars / displayTotal) * 100).toStringAsFixed(0)}% do quadro'
                    : 'operacionais',
                tone: emerald,
              ),
              _HeroKpiBlock(
                icon: LucideIcons.shieldCheck,
                label: 'ADMINS',
                value: '$admins',
                sub: admins == 1 ? 'operador' : 'operadores',
                tone: violet,
              ),
              _HeroKpiBlock(
                icon: LucideIcons.briefcase,
                label: 'GESTORES',
                value: '${stats?.managers ?? 0}',
                sub: 'liderança',
                tone: indigo,
              ),
              _HeroKpiBlock(
                icon: LucideIcons.userPlus,
                label: 'NOVOS',
                value: '$newThisMonth',
                sub: newThisMonth == 1 ? 'este mês' : 'no mês',
                tone: amber,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bloco vertical do strip de KPI do hero — ícone + label uppercase +
/// valor grande em tom + sub-rótulo contextual + traço fino accent.
/// Sem bordas / sem fill — pura tipografia editorial. Compartilhado
/// (espelhado) com `teams_page.dart` para consistência visual entre
/// as duas telas de Colaboradores.
class _HeroKpiBlock {
  const _HeroKpiBlock({
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final String value;
  final String sub;
  final Color tone;

  Widget render(BuildContext context) {
    final theme = Theme.of(context);
    final secondaryColor = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: tone),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: tone,
                    letterSpacing: 1.4,
                    height: 1.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: tone,
                letterSpacing: -0.6,
                height: 1.0,
                fontSize: 22,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            sub,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: secondaryColor,
              letterSpacing: 0.1,
              height: 1.0,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 7),
          Container(
            height: 2,
            width: 18,
            decoration: BoxDecoration(
              color: tone,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

/// Strip horizontal de KPIs do hero — 4 colunas com peso igual,
/// separadas por linhas verticais finas. Editorial aberto, sem
/// encapsulamento por chip.
class _HeroKpiStrip extends StatelessWidget {
  const _HeroKpiStrip({required this.blocks});

  final List<_HeroKpiBlock> blocks;

  @override
  Widget build(BuildContext context) {
    final divider = ThemeHelpers.borderColor(context).withValues(alpha: 0.45);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < blocks.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: divider,
              ),
            Expanded(child: blocks[i].render(context)),
          ],
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Toolbar (busca + filtros)
// ──────────────────────────────────────────────────────────────────────────

class _Toolbar extends StatefulWidget {
  const _Toolbar({
    required this.controller,
    required this.onFilterTap,
    required this.filterCount,
    this.onClearAll,
  });

  final TextEditingController controller;
  final VoidCallback onFilterTap;
  final int filterCount;
  final VoidCallback? onClearAll;

  @override
  State<_Toolbar> createState() => _ToolbarState();
}

class _ToolbarState extends State<_Toolbar> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent =
        isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1);
    final textColor = ThemeHelpers.textColor(context);
    final secondaryColor = ThemeHelpers.textSecondaryColor(context);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final cardColor = ThemeHelpers.cardBackgroundColor(context);
    final hasText = widget.controller.text.isNotEmpty;
    final showAccent = _focused || hasText;
    final filterActive = widget.filterCount > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Controle único: ícone + input + clear + divisor + botão filtros.
          // Borda animada que tinge em accent quando há foco/texto/filtro.
          Focus(
            onFocusChange: (f) => setState(() => _focused = f),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              height: 50,
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: (showAccent || filterActive)
                      ? accent.withValues(alpha: isDark ? 0.5 : 0.42)
                      : borderColor,
                  width: (showAccent || filterActive) ? 1.4 : 1,
                ),
                boxShadow: showAccent
                    ? [
                        BoxShadow(
                          color: accent.withValues(
                              alpha: isDark ? 0.18 : 0.12),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                          spreadRadius: -4,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  Icon(
                    LucideIcons.search,
                    size: 17,
                    color: showAccent ? accent : secondaryColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      textInputAction: TextInputAction.search,
                      cursorColor: accent,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                      ),
                      // IMPORTANTE: o tema global tem `filled: true` +
                      // borders no `inputDecorationTheme`. Sem desligar
                      // explicitamente aqui o TextField pinta o próprio
                      // retângulo dentro do nosso container — virava o
                      // "card dentro de card".
                      decoration: InputDecoration(
                        hintText: 'Buscar por nome ou e-mail',
                        hintStyle: TextStyle(
                          color: secondaryColor.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w500,
                          fontSize: 13.5,
                        ),
                        filled: false,
                        fillColor: Colors.transparent,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (hasText) ...[
                    InkResponse(
                      radius: 18,
                      onTap: () {
                        widget.controller.clear();
                        setState(() {});
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          LucideIcons.x,
                          size: 14,
                          color: secondaryColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  // Divisor interno entre input e botão de filtros — fundindo
                  // os dois numa única peça (acaba o "card ao lado de card").
                  Container(
                    width: 1,
                    height: 24,
                    color: borderColor,
                  ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(13),
                        bottomRight: Radius.circular(13),
                      ),
                      onTap: widget.onFilterTap,
                      child: Container(
                        height: 50,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.center,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              LucideIcons.slidersHorizontal,
                              size: 18,
                              color: filterActive ? accent : textColor,
                            ),
                            if (filterActive)
                              Positioned(
                                right: -8,
                                top: -6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accent,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: cardColor,
                                      width: 1.5,
                                    ),
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 16,
                                    minHeight: 16,
                                  ),
                                  child: Text(
                                    '${widget.filterCount}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      height: 1,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Link ghost "Limpar busca e filtros" — só aparece quando há
          // estado ativo. Some sem ocupar espaço quando não usado.
          if (widget.onClearAll != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                onTap: widget.onClearAll,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.x, size: 11, color: secondaryColor),
                      const SizedBox(width: 4),
                      Text(
                        'Limpar busca e filtros',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: secondaryColor,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Lista de usuários (cards refinados)
// ──────────────────────────────────────────────────────────────────────────

class _UsersList extends StatelessWidget {
  const _UsersList({
    required this.users,
    required this.onToggleActive,
    required this.onOpenEdit,
  });

  final List<AdminUser> users;
  final Future<void> Function(AdminUser) onToggleActive;
  final Future<void> Function(AdminUser) onOpenEdit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          for (final u in users) ...[
            _UserCard(
              user: u,
              onToggleActive: () => onToggleActive(u),
              onOpenEdit: () => onOpenEdit(u),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.onToggleActive,
    required this.onOpenEdit,
  });

  final AdminUser user;
  final Future<void> Function() onToggleActive;
  final Future<void> Function() onOpenEdit;

  Color _roleColor(BuildContext context) {
    switch (user.role.toLowerCase()) {
      case 'master':
        return const Color(0xFF8B5CF6);
      case 'admin':
        return const Color(0xFFE65100);
      case 'manager':
        return const Color(0xFF1E88E5);
      case 'user':
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  /// Status visual de presença — alinhado com web `UsersPage.tsx`.
  /// `active` → conta ativa e já acessou. `unknown` → nunca acessou.
  /// `inactive` → conta desativada na empresa.
  Color _presenceColor() {
    if (!user.isActiveInCompany || !user.active) {
      return const Color(0xFFA1A1AA); // slate — desativado
    }
    if (user.neverLoggedIn) return const Color(0xFFF59E0B); // amber — nunca
    return const Color(0xFF10B981); // emerald — ativo
  }

  String _statusLabel() {
    if (!user.isActiveInCompany || !user.active) return 'Desativado';
    if (user.neverLoggedIn) return 'Nunca acessou';
    return 'Ativo';
  }

  IconData _statusIcon() {
    if (!user.isActiveInCompany || !user.active) return LucideIcons.minus;
    if (user.neverLoggedIn) return LucideIcons.clock;
    return LucideIcons.check;
  }

  /// Mascara CPF como `***.***.***-XX` (apenas últimos 2 dígitos visíveis),
  /// paridade com `maskCPFOculto` do web.
  String? _maskedDocument() {
    final raw = user.document;
    if (raw == null || raw.trim().isEmpty) return null;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 2) return '***.***.***-**';
    final tail = digits.substring(digits.length - 2);
    return '***.***.***-$tail';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.colorScheme.primary;
    final textColor = ThemeHelpers.textColor(context);
    final secondaryColor = ThemeHelpers.textSecondaryColor(context);
    final borderColor = ThemeHelpers.borderColor(context);
    final cardColor = ThemeHelpers.cardBackgroundColor(context);
    final roleColor = _roleColor(context);
    final presence = _presenceColor();

    final canEdit = ModuleAccessService.instance.hasPermission(
      AppPermissions.userUpdate,
    );

    final phone = user.phone?.trim();
    final docMasked = _maskedDocument();
    final lastLoginLabel = user.lastLoginAt != null
        ? DateFormat("d 'de' MMM · HH:mm", 'pt_BR')
            .format(user.lastLoginAt!.toLocal())
        : 'Nunca';
    final createdAtLabel = user.createdAt != null
        ? DateFormat("d 'de' MMM yyyy", 'pt_BR')
            .format(user.createdAt!.toLocal())
        : null;
    final isAppRoleUser = user.role.toLowerCase() == 'user';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: canEdit ? () => onOpenEdit() : null,
        child: Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: borderColor.withValues(alpha: 0.55),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── HEADER: avatar com presence dot + identidade + menu ────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _UserAvatar(
                    name: user.name,
                    avatarUrl: user.avatar,
                    accent: accent,
                    presenceColor: presence,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          user.name.isEmpty ? '—' : user.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: textColor,
                            letterSpacing: -0.3,
                            height: 1.15,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.mail,
                                size: 11, color: secondaryColor),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                user.email,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: secondaryColor,
                                  fontWeight: FontWeight.w600,
                                  height: 1.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (phone != null || docMasked != null) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 10,
                            runSpacing: 4,
                            children: [
                              if (phone != null)
                                _InlineDatum(
                                  icon: LucideIcons.phone,
                                  text: phone,
                                  color: secondaryColor,
                                ),
                              if (docMasked != null)
                                _InlineDatum(
                                  icon: LucideIcons.fingerprint,
                                  text: docMasked,
                                  color: secondaryColor,
                                  monospace: true,
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (canEdit)
                    InkResponse(
                      radius: 20,
                      onTap: () => _showUserActions(context),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          LucideIcons.moreVertical,
                          size: 18,
                          color: secondaryColor,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // ── BADGE ROW: role + status (paridade com web) ───────────
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _Badge(
                    label: user.roleLabel,
                    color: roleColor,
                    isDark: isDark,
                    icon: LucideIcons.shieldCheck,
                  ),
                  _Badge(
                    label: _statusLabel(),
                    color: presence,
                    isDark: isDark,
                    icon: _statusIcon(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // ── META GRID: último acesso · visibilidade ───────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _MetaCell(
                      icon: LucideIcons.clock,
                      label: 'ÚLTIMO ACESSO',
                      child: Text(
                        lastLoginLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 32,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    color: borderColor.withValues(alpha: 0.4),
                  ),
                  Expanded(
                    child: _MetaCell(
                      icon: LucideIcons.eye,
                      label: 'VISIBILIDADE',
                      child: _VisibilityPill(
                        isPublic: user.isAvailableForPublicSite,
                      ),
                    ),
                  ),
                ],
              ),
              if (isAppRoleUser) ...[
                const SizedBox(height: 10),
                _AppAccessRow(active: user.hasAppAccess),
              ],
              const SizedBox(height: 12),
              Container(
                height: 1,
                color: borderColor.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 10),
              // ── FOOTER: "Desde {date}" + edit hint ───────────────────
              Row(
                children: [
                  if (createdAtLabel != null) ...[
                    Icon(
                      LucideIcons.calendar,
                      size: 12,
                      color: secondaryColor.withValues(alpha: 0.75),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 11,
                            color: secondaryColor,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1,
                          ),
                          children: [
                            const TextSpan(text: 'Desde '),
                            TextSpan(
                              text: createdAtLabel,
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else
                    const SizedBox.shrink(),
                  const Spacer(),
                  if (canEdit) ...[
                    Text(
                      'Abrir edição',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: accent,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(LucideIcons.arrowRight, size: 13, color: accent),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUserActions(BuildContext context) {
    final canEdit = ModuleAccessService.instance.hasPermission(
      AppPermissions.userUpdate,
    );
    if (!canEdit) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;
        final textColor = ThemeHelpers.textColor(ctx);
        final secondaryColor = ThemeHelpers.textSecondaryColor(ctx);
        final editAccent =
            isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1);
        final danger =
            isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
        final emerald =
            isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
        final roleColor = _roleColor(ctx);
        final presence = _presenceColor();
        final willDeactivate = user.active;

        return Container(
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(ctx),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: ThemeHelpers.borderColor(ctx).withValues(alpha: 0.5),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ThemeHelpers.borderColor(ctx),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Identidade.
                Row(
                  children: [
                    _UserAvatar(
                      name: user.name,
                      avatarUrl: user.avatar,
                      accent: theme.colorScheme.primary,
                      presenceColor: presence,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            user.name.isEmpty ? '—' : user.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: textColor,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user.email,
                            style: TextStyle(
                              color: secondaryColor,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 7),
                          _Badge(
                            label: user.roleLabel,
                            color: roleColor,
                            isDark: isDark,
                            icon: LucideIcons.shieldCheck,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _ActionTile(
                  icon: LucideIcons.userPen,
                  tone: editAccent,
                  title: 'Editar usuário',
                  subtitle: 'Papel, acessos e permissões',
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await onOpenEdit();
                  },
                ),
                const SizedBox(height: 10),
                _ActionTile(
                  icon: willDeactivate
                      ? LucideIcons.userMinus
                      : LucideIcons.userCheck,
                  tone: willDeactivate ? danger : emerald,
                  title: willDeactivate
                      ? 'Desativar usuário'
                      : 'Ativar usuário',
                  subtitle: willDeactivate
                      ? 'Revoga o acesso ao sistema'
                      : 'Restaura o acesso ao sistema',
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await onToggleActive();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Tile de ação do modal — ícone tonal em quadrado + título/subtítulo +
/// chevron. Refinado, com toque amplo.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tone.withValues(alpha: isDark ? 0.10 : 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tone.withValues(alpha: 0.28)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: isDark ? 0.20 : 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 19, color: tone),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: secondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronRight, size: 18, color: secondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Avatar do usuário — paridade com `UserCardAvatar` do web. Mostra foto
/// quando disponível; caso contrário, monograma de 2 letras em gradiente.
/// Presence dot pequeno sobreposto no canto inferior direito, com cor
/// herdada do status semântico (ativo · nunca · desativado).
class _UserAvatar extends StatelessWidget {
  const _UserAvatar({
    required this.name,
    required this.avatarUrl,
    required this.accent,
    required this.presenceColor,
  });

  final String name;
  final String? avatarUrl;
  final Color accent;
  final Color presenceColor;

  static const double _size = 52;
  static const double _dotSize = 13;

  String _initials() {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Widget _monogram() {
    final deep = HSLColor.fromColor(accent)
        .withLightness(
            (HSLColor.fromColor(accent).lightness * 0.78).clamp(0.0, 1.0))
        .toColor();
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, deep],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        _initials(),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 17,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = avatarUrl != null && avatarUrl!.trim().isNotEmpty;
    final cardColor = ThemeHelpers.cardBackgroundColor(context);

    final avatar = hasPhoto
        ? Container(
            width: _size,
            height: _size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: accent.withValues(alpha: 0.22),
                width: 1.2,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.network(
              avatarUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _monogram(),
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return _monogram();
              },
            ),
          )
        : _monogram();

    return SizedBox(
      width: _size + 2,
      height: _size + 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          // Presence dot — sobreposto, com ring da cor do card pra recortar
          // o avatar e dar destaque.
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: _dotSize,
              height: _dotSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: presenceColor,
                border: Border.all(color: cardColor, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: presenceColor.withValues(alpha: 0.55),
                    blurRadius: 6,
                    spreadRadius: 0.3,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.color,
    required this.isDark,
    required this.icon,
  });

  final String label;
  final Color color;
  final bool isDark;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.35 : 0.22),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
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

/// Item inline de dado complementar (telefone, CPF). Ícone pequeno +
/// texto compacto — usado abaixo do email do usuário no card. Paridade
/// com `UserCardInlineDataItem` do web.
class _InlineDatum extends StatelessWidget {
  const _InlineDatum({
    required this.icon,
    required this.text,
    required this.color,
    this.monospace = false,
  });

  final IconData icon;
  final String text;
  final Color color;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: monospace ? 0.4 : 0.1,
            fontFamily: monospace ? 'monospace' : null,
            height: 1.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Célula da meta grid (último acesso · visibilidade). Label uppercase
/// pequeno em accent secondary + child livre. Paridade com `UserCardMetaItem`.
class _MetaCell extends StatelessWidget {
  const _MetaCell({
    required this.icon,
    required this.label,
    required this.child,
  });

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final secondaryColor = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: secondaryColor),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: secondaryColor,
                  height: 1.0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        child,
      ],
    );
  }
}

/// Pílula compacta de visibilidade — verde quando público, neutra quando
/// privado. Paridade com `UserCardVisibilityPill`.
class _VisibilityPill extends StatelessWidget {
  const _VisibilityPill({required this.isPublic});

  final bool isPublic;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone = isPublic
        ? const Color(0xFF10B981)
        : (isDark
            ? Colors.white.withValues(alpha: 0.5)
            : Colors.black.withValues(alpha: 0.45));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: isDark ? 0.35 : 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPublic ? LucideIcons.globe : LucideIcons.lock,
            size: 10,
            color: tone,
          ),
          const SizedBox(width: 4),
          Text(
            isPublic ? 'Público' : 'Privado',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: tone,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Linha de status do acesso ao app móvel — só aparece para `role = user`.
/// Indica se o colaborador tem permissão pra usar o app, igual ao bloco
/// `App móvel` do `UserCardMeta` no web.
class _AppAccessRow extends StatelessWidget {
  const _AppAccessRow({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final secondaryColor = ThemeHelpers.textSecondaryColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone = active
        ? const Color(0xFF1E88E5)
        : (isDark
            ? Colors.white.withValues(alpha: 0.5)
            : Colors.black.withValues(alpha: 0.45));
    return Row(
      children: [
        Icon(LucideIcons.smartphone, size: 10, color: secondaryColor),
        const SizedBox(width: 5),
        Text(
          'APP MÓVEL',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: secondaryColor,
            height: 1.0,
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: tone.withValues(alpha: isDark ? 0.18 : 0.10),
            borderRadius: BorderRadius.circular(999),
            border:
                Border.all(color: tone.withValues(alpha: isDark ? 0.35 : 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active ? LucideIcons.check : LucideIcons.minus,
                size: 10,
                color: tone,
              ),
              const SizedBox(width: 4),
              Text(
                active ? 'Ativado' : 'Desativado',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: tone,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Shimmer / Empty / Error / Denied
// ──────────────────────────────────────────────────────────────────────────

class _UsersShimmer extends StatelessWidget {
  const _UsersShimmer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: List.generate(
          5,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              decoration: BoxDecoration(
                color: ThemeHelpers.cardBackgroundColor(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
                ),
              ),
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 48, height: 48, borderRadius: 14),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SkeletonBox(width: 160, height: 14, borderRadius: 4),
                        SizedBox(height: 8),
                        SkeletonBox(width: 220, height: 11, borderRadius: 4),
                        SizedBox(height: 14),
                        Row(
                          children: [
                            SkeletonBox(width: 60, height: 18, borderRadius: 999),
                            SizedBox(width: 6),
                            SkeletonBox(width: 70, height: 18, borderRadius: 999),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock();

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final textColor = ThemeHelpers.textColor(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 30),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: ThemeHelpers.borderColor(context)
                    .withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.users, size: 24, color: secondary),
            ),
            const SizedBox(height: 14),
            Text(
              'Nenhum usuário encontrado',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Ajuste a busca ou os filtros para tentar novamente.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: secondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(LucideIcons.alertCircle, color: Colors.red.shade400, size: 32),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: ThemeHelpers.textSecondaryColor(context),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(LucideIcons.refreshCcw, size: 16),
            onPressed: onRetry,
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}

class _UsersDeniedView extends StatelessWidget {
  const _UsersDeniedView();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.lock,
                size: 38,
                color: ThemeHelpers.textSecondaryColor(context)),
            const SizedBox(height: 12),
            Text(
              'Você não tem permissão para ver usuários.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Solicite ao administrador a permissão "user:view".',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textSecondaryColor(context),
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
