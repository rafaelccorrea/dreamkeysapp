import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_permissions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/state/screen_state_cache.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/admin_user_model.dart';
import '../services/admin_users_service.dart';
import '../widgets/user_access_widgets.dart';
import '../widgets/users_filters_sheet.dart';
import 'edit_user_page.dart';

/// Tela de Colaboradores → Usuários.
///
/// Superfície do dia a dia: cabeçalho com o tamanho e a composição da equipe
/// por papel (nomes de [uaRoleLabel]) + "Novo usuário"; busca com
/// filtros; linhas flush com quem é, papel, estado e último acesso. Tocar na
/// linha abre a edição; o menu da linha traz editar e desativar/reativar.
/// Paridade de dados com `imobx-front` `UsersPage.tsx`.
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
  // Sem o código HTTP o erro não sabe dizer se foi permissão ou servidor.
  int _errorStatus = 0;
  Object? _errorRaw;

  List<AdminUser> _users = [];
  int _page = 1;
  int _totalPages = 1;
  int _total = 0;

  AdminUsersStats? _stats;
  // A 1ª resposta das estatísticas já chegou (com ou sem sucesso) — separa
  // "carregando" (skeleton) de "indisponível" (sem a barra de composição).
  bool _statsSettled = false;

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
    ScreenStateCache.instance.save(_stateCacheKey, {
      'search': _search,
      'filters': _filters.toMap(),
    }, ttl: const Duration(minutes: 15));
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
      _errorStatus = 0;
      _errorRaw = null;
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
        _errorStatus = res.statusCode;
        _errorRaw = res.error;
      }
    });
    // Resultados carregados → baixa o teclado (evita ficar tampando a lista).
    if (mounted) FocusScope.of(context).unfocus();
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
      setState(() {
        _stats = res.data;
        _statsSettled = true;
      });
    } else if (!_statsSettled) {
      setState(() => _statsSettled = true);
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

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).pushNamed('/users/create');
    if (created == true && mounted) {
      _reload();
      // O cabeçalho mostra o total e a composição da equipe: sem isso ele
      // ficaria com o número de antes do cadastro.
      unawaited(_loadStats());
    }
  }

  Future<void> _openEdit(AdminUser u) async {
    final canEdit = ModuleAccessService.instance.hasPermission(
      AppPermissions.userUpdate,
    );
    if (!canEdit) return;
    final changed = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => EditUserPage(user: u)));
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
    // A desativação é POR EMPRESA (user_company.isActive); o `active` global
    // fica intocado — decidir por ele deixava o desativado sem "Ativar".
    final isActive = u.isActiveInCompany;
    if (isActive) {
      final outcome = await showModalBottomSheet<_DeactivateOutcome>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        isDismissible: false,
        enableDrag: false,
        builder: (_) => _DeactivateUserSheet(
          user: u,
          canRedistributeFunnel: ModuleAccessService.instance.hasPermission(
            'kanban:update',
          ),
        ),
      );
      if (outcome == null || !mounted) return;
      for (final warning in outcome.warnings) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(warning),
            duration: const Duration(seconds: 5),
          ),
        );
      }
      if (!outcome.deactivated) return;
      _replaceLocal(u.copyWith(isActiveInCompany: false));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.status.success,
          content: Text(outcome.message),
          duration: const Duration(seconds: 6),
        ),
      );
      unawaited(_loadStats());
      return;
    }

    final res = await AdminUsersService.instance.setActive(u.id, true);
    if (!mounted) return;
    if (res.success) {
      _replaceLocal(u.copyWith(isActiveInCompany: true));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.status.success,
          content: Text('Acesso reativado para ${u.name}.'),
          duration: const Duration(seconds: 3),
        ),
      );
      unawaited(_loadStats());
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res.message ?? 'Erro ao alterar status do usuário',
          ),
        ),
      );
    }
  }

  void _replaceLocal(AdminUser next) {
    setState(() {
      final idx = _users.indexWhere((x) => x.id == next.id);
      if (idx >= 0) _users[idx] = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final access = ModuleAccessService.instance;
    final canView = access.hasPermission(AppPermissions.userView) ||
        access.hasCompanyModule('user_management');

    if (!canView) {
      return const AppScaffold(
        title: 'Usuários',
        showBottomNavigation: false,
        body: _UsersDeniedView(),
      );
    }

    final canCreate = access.hasPermission(AppPermissions.userCreate);
    final canEdit = access.hasPermission(AppPermissions.userUpdate);
    final filterCount = _filters.activeCount;
    final hasAnyFilter = filterCount > 0 || _search.trim().isNotEmpty;
    // 1ª carga (ou recarga sem nada na tela) = skeleton; recarga com lista
    // na tela mantém a lista e mostra só a barrinha de atualização.
    final firstLoad = _loading && !_refetching;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final brand =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    // Tela larga: coluna central de até 720dp. Calculado aqui — um
    // LayoutBuilder entre o RefreshIndicator e a lista crasha.
    final width = MediaQuery.sizeOf(context).width;
    final side = width > kUaMaxContentWidth + 32
        ? (width - kUaMaxContentWidth) / 2
        : 16.0;

    return AppScaffold(
      title: 'Usuários',
      showBottomNavigation: false,
      body: RefreshIndicator(
        color: brand,
        onRefresh: () async {
          await _reload();
          await _loadStats();
        },
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          // Arrastar a lista fecha o teclado (problema recorrente de teclado
          // atrapalhando ao rolar os resultados).
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(side, 0, side, 28),
          children: [
            _UsersHeader(
              stats: _stats,
              statsSettled: _statsSettled,
              fallbackTotal: _total,
              canCreate: canCreate,
              onCreate: _openCreate,
            ),
            const SizedBox(height: 18),
            _Toolbar(
              controller: _searchController,
              onFilterTap: _openFilters,
              filterCount: filterCount,
            ),
            const SizedBox(height: 8),
            if (!firstLoad && _error == null)
              _ListCaption(
                total: _total,
                loaded: _users.length,
                filtered: hasAnyFilter,
                onClearAll: hasAnyFilter ? _clearAll : null,
              ),
            if (_refetching)
              const _RefetchBar()
            else
              const SizedBox(height: 2),
            if (firstLoad)
              const _UsersSkeleton()
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _ErrorBlock(
                  message: _error!,
                  statusCode: _errorStatus,
                  error: _errorRaw,
                  onRetry: _reload,
                ),
              )
            else if (_users.isEmpty)
              _EmptyBlock(
                filtered: hasAnyFilter,
                canCreate: canCreate,
                onClear: _clearAll,
                onCreate: _openCreate,
              )
            else
              _UsersList(
                users: _users,
                canEdit: canEdit,
                onToggleActive: _toggleActive,
                onOpenEdit: _openEdit,
              ),
            if (_loadingMore) const _UsersSkeleton(rows: 2),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Cabeçalho — tamanho da equipe, composição por papel e "Novo usuário"
// ──────────────────────────────────────────────────────────────────────────

class _UsersHeader extends StatelessWidget {
  const _UsersHeader({
    required this.stats,
    required this.statsSettled,
    required this.fallbackTotal,
    required this.canCreate,
    required this.onCreate,
  });

  final AdminUsersStats? stats;
  final bool statsSettled;
  final int fallbackTotal;
  final bool canCreate;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final success =
        isDark ? AppColors.status.successDarkMode : AppColors.status.success;
    final fmt = NumberFormat.decimalPattern('pt_BR');
    final s = stats;
    final waiting = s == null && !statsSettled;
    final total = s?.total ?? fallbackTotal;
    final newThisMonth = s?.newThisMonth ?? 0;

    final headline = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (waiting && total == 0)
          const SkeletonBox(width: 150, height: 34, borderRadius: 8)
        else
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: fmt.format(total),
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: textColor,
                      height: 1.0,
                      letterSpacing: -1.2,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  TextSpan(
                    text: total == 1 ? '  usuário' : '  usuários',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
            ),
          ),
        const SizedBox(height: 7),
        if (waiting)
          const SkeletonBox(width: 160, height: 12, borderRadius: 4)
        else if (s != null)
          Row(
            children: [
              Icon(
                LucideIcons.userPlus,
                size: 13,
                color: newThisMonth > 0 ? success : secondary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  newThisMonth > 0
                      ? '$newThisMonth ${newThisMonth == 1 ? 'entrou' : 'entraram'} este mês'
                      : 'Nenhuma entrada este mês',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: secondary,
                  ),
                ),
              ),
            ],
          ),
      ],
    );

    Widget composition;
    if (waiting) {
      composition = const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkeletonBox(height: 10, borderRadius: 4),
          SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              SkeletonBox(width: 104, height: 12, borderRadius: 4),
              SkeletonBox(width: 80, height: 12, borderRadius: 4),
              SkeletonBox(width: 126, height: 12, borderRadius: 4),
            ],
          ),
        ],
      );
    } else if (s != null) {
      // Nomes pelo helper único (paridade com o `translateUserRole` do web);
      // o bloco de admins das estatísticas soma admin + master.
      composition = _RoleComposition(
        segments: [
          _RoleSegment(
            role: 'user',
            label: uaRoleLabel('user'),
            value: s.regulars,
          ),
          _RoleSegment(
            role: 'manager',
            label: uaRoleLabel('manager'),
            value: s.managers,
          ),
          _RoleSegment(
            role: 'admin',
            label: uaRoleLabel('admin'),
            value: s.admins,
          ),
        ],
      );
    } else {
      // Estatísticas indisponíveis: sem barra (não inventa composição).
      composition = const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 440;
          final cta = _CreateUserButton(
            canCreate: canCreate,
            onCreate: onCreate,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: headline),
                  if (wide) ...[const SizedBox(width: 16), cta],
                ],
              ),
              const SizedBox(height: 16),
              composition,
              if (!wide) ...[
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: cta),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// CTA principal de criação (vermelho da marca). Sem permissão não some:
/// fica travado com cadeado e explica ao toque.
class _CreateUserButton extends StatelessWidget {
  const _CreateUserButton({required this.canCreate, required this.onCreate});

  final bool canCreate;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final brand =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    const label = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text('Novo usuário', maxLines: 1, softWrap: false),
    );
    if (canCreate) {
      return FilledButton.icon(
        onPressed: onCreate,
        style: FilledButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: shape,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14.5,
          ),
        ),
        icon: const Icon(LucideIcons.userPlus, size: 18),
        label: label,
      );
    }
    return OutlinedButton.icon(
      onPressed: () {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text(
                'Você não tem permissão para cadastrar usuários. Peça ao '
                'administrador da empresa.',
              ),
            ),
          );
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: ThemeHelpers.textSecondaryColor(context),
        side: BorderSide(color: ThemeHelpers.borderColor(context)),
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: shape,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
      icon: const Icon(LucideIcons.lock, size: 16),
      label: label,
    );
  }
}

class _RoleSegment {
  const _RoleSegment({
    required this.role,
    required this.label,
    required this.value,
  });

  final String role;
  final String label;
  final int value;
}

/// Barra de composição da equipe (parte do todo) + legenda com os números.
/// Marca fina (10px), 2px de respiro entre as partes, ponta de dados
/// arredondada; a legenda carrega a identidade (nunca só a cor).
class _RoleComposition extends StatelessWidget {
  const _RoleComposition({required this.segments});

  final List<_RoleSegment> segments;

  @override
  Widget build(BuildContext context) {
    final sum = segments.fold<int>(0, (a, s) => a + s.value);
    final visible = segments.where((s) => s.value > 0).toList();
    const end = BorderRadius.horizontal(right: Radius.circular(4));
    return Semantics(
      label: 'Composição da equipe: '
          '${segments.map((s) => '${s.label} ${s.value}').join(', ')}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 10,
              child: sum == 0
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: ThemeHelpers.borderLightColor(context),
                        borderRadius: end,
                      ),
                      child: const SizedBox.expand(),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < visible.length; i++) ...[
                          if (i > 0) const SizedBox(width: 2),
                          Expanded(
                            flex: visible[i].value,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: uaRoleSwatch(visible[i].role),
                                borderRadius: i == visible.length - 1
                                    ? end
                                    : BorderRadius.zero,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                for (final s in segments) _LegendItem(segment: s),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.segment});

  final _RoleSegment segment;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: uaRoleSwatch(segment.role),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 7),
        // Nome (singular, do helper do web) + número: "Colaborador 38".
        Flexible(
          child: Text(
            segment.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          '${segment.value}',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w900,
            color: ThemeHelpers.textColor(context),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Busca + filtros (mesma gramática da tela de Imóveis) e legenda da lista
// ──────────────────────────────────────────────────────────────────────────

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.onFilterTap,
    required this.filterCount,
  });

  final TextEditingController controller;
  final VoidCallback onFilterTap;
  final int filterCount;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final brand =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final fill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;

    return Row(
      children: [
        Expanded(
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final hasText = value.text.isNotEmpty;
              return Container(
                constraints: const BoxConstraints(minHeight: 48),
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: ThemeHelpers.borderColor(context)
                        .withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    Icon(LucideIcons.search, size: 18, color: secondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        textInputAction: TextInputAction.search,
                        cursorColor: brand,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                        // IMPORTANTE: o tema global tem `filled: true` +
                        // bordas; sem desligar aqui o TextField pinta um
                        // segundo retângulo dentro do nosso.
                        decoration: InputDecoration(
                          hintText: 'Buscar por nome ou e-mail',
                          hintStyle: TextStyle(
                            color: secondary.withValues(alpha: 0.8),
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
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onSubmitted: (_) => FocusScope.of(context).unfocus(),
                      ),
                    ),
                    if (hasText)
                      IconButton(
                        tooltip: 'Limpar busca',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          controller.clear();
                          FocusScope.of(context).unfocus();
                        },
                        icon: Icon(LucideIcons.x, size: 16, color: secondary),
                      )
                    else
                      const SizedBox(width: 12),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        _FilterButton(count: filterCount, onTap: onFilterTap),
      ],
    );
  }
}

/// Botão de filtros colado à busca — quadrado; com filtro ativo ganha o
/// tom da marca e a contagem.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final brand =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final active = count > 0;
    final fill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final radius = BorderRadius.circular(14);
    return Tooltip(
      message: active ? 'Filtros ($count ativos)' : 'Filtros',
      child: Material(
        color: active ? brand.withValues(alpha: isDark ? 0.16 : 0.09) : fill,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: active
                    ? brand.withValues(alpha: 0.5)
                    : ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
                width: active ? 1.4 : 1,
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(
                  child: Icon(
                    LucideIcons.slidersHorizontal,
                    size: 19,
                    color: active ? brand : ThemeHelpers.textColor(context),
                  ),
                ),
                if (active)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: brand,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$count',
                        textScaler: TextScaler.noScaling,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Linha fina acima da lista: quantos resultados, quantos já carregados e o
/// atalho para limpar busca e filtros.
class _ListCaption extends StatelessWidget {
  const _ListCaption({
    required this.total,
    required this.loaded,
    required this.filtered,
    this.onClearAll,
  });

  final int total;
  final int loaded;
  final bool filtered;
  final VoidCallback? onClearAll;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final noun = filtered
        ? (total == 1 ? 'resultado' : 'resultados')
        : (total == 1 ? 'usuário na lista' : 'usuários na lista');
    final more = loaded < total ? ' · mostrando $loaded' : '';
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 36),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$total $noun$more',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: secondary,
              ),
            ),
          ),
          if (onClearAll != null)
            TextButton.icon(
              onPressed: onClearAll,
              style: TextButton.styleFrom(
                // Neutro: o tema pinta TextButton com o vermelho da marca.
                foregroundColor: secondary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 36),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(LucideIcons.x, size: 14),
              // Curto de propósito: ao lado da contagem, "Limpar" basta — e
              // não espreme o número em 320dp com fonte grande.
              label: const Text(
                'Limpar',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
              ),
            ),
        ],
      ),
    );
  }
}

class _RefetchBar extends StatelessWidget {
  const _RefetchBar();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final brand =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        minHeight: 2,
        semanticsLabel: 'Atualizando a lista',
        backgroundColor: ThemeHelpers.borderLightColor(context),
        valueColor: AlwaysStoppedAnimation(brand),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Lista — linhas flush com filete: quem, papel/cargo, estado, último acesso
// ──────────────────────────────────────────────────────────────────────────

/// "hoje às 14:20", "ontem às 09:10", "há 3 dias", "em 12 de mar."…
String _lastAccessLabel(DateTime at) {
  final local = at.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final days = (today.difference(day).inHours / 24).round();
  final hm = DateFormat('HH:mm', 'pt_BR').format(local);
  if (days <= 0) return 'hoje às $hm';
  if (days == 1) return 'ontem às $hm';
  if (days < 7) return 'há $days dias';
  if (local.year == now.year) {
    return 'em ${DateFormat("d 'de' MMM", 'pt_BR').format(local)}';
  }
  return 'em ${DateFormat("d 'de' MMM 'de' yyyy", 'pt_BR').format(local)}';
}

bool _isDisabled(AdminUser u) => !u.isActiveInCompany || !u.active;

class _UsersList extends StatelessWidget {
  const _UsersList({
    required this.users,
    required this.canEdit,
    required this.onToggleActive,
    required this.onOpenEdit,
  });

  final List<AdminUser> users;
  final bool canEdit;
  final Future<void> Function(AdminUser) onToggleActive;
  final Future<void> Function(AdminUser) onOpenEdit;

  @override
  Widget build(BuildContext context) {
    final hairline = ThemeHelpers.borderLightColor(context);
    return Column(
      children: [
        for (var i = 0; i < users.length; i++) ...[
          if (i > 0)
            Container(
              height: 1,
              margin: const EdgeInsets.only(left: 56),
              color: hairline,
            ),
          _UserRow(
            user: users[i],
            canEdit: canEdit,
            onToggleActive: () => onToggleActive(users[i]),
            onOpenEdit: () => onOpenEdit(users[i]),
          ),
        ],
      ],
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    required this.canEdit,
    required this.onToggleActive,
    required this.onOpenEdit,
  });

  final AdminUser user;
  final bool canEdit;
  final Future<void> Function() onToggleActive;
  final Future<void> Function() onOpenEdit;

  void _explainLocked(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Você não tem permissão para editar usuários. Peça ao '
            'administrador da empresa.',
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
      builder: (ctx) => _UserActionsSheet(
        user: user,
        onEdit: () async {
          Navigator.of(ctx).pop();
          await onOpenEdit();
        },
        onToggle: () async {
          Navigator.of(ctx).pop();
          await onToggleActive();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final disabled = _isDisabled(user);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: canEdit ? () => onOpenEdit() : () => _explainLocked(context),
        onLongPress: canEdit ? () => _showUserActions(context) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Opacity(
                opacity: disabled ? 0.5 : 1,
                child: UaAvatar(
                  name: user.name,
                  url: user.avatar,
                  tone: uaRoleTone(user.role, isDark: isDark),
                  size: 44,
                  radius: 14,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name.isEmpty ? 'Sem nome' : user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: disabled ? secondary : textColor,
                        letterSpacing: -0.2,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: secondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _RoleMark(user: user),
                        _StatusMark(user: user),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (canEdit)
                IconButton(
                  tooltip: 'Ações do usuário',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _showUserActions(context),
                  icon: Icon(
                    LucideIcons.ellipsisVertical,
                    size: 18,
                    color: secondary,
                  ),
                )
              else
                Tooltip(
                  message: 'Sem permissão para editar usuários',
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      LucideIcons.lock,
                      size: 15,
                      color: secondary.withValues(alpha: 0.75),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Papel (quadradinho na cor do papel + nome) e, quando houver, o cargo.
class _RoleMark extends StatelessWidget {
  const _RoleMark({required this.user});

  final AdminUser user;

  @override
  Widget build(BuildContext context) {
    final cargo = (user.jobLevelName ?? '').trim();
    final role = uaRoleLabel(user.role, isOwner: user.owner);
    final text = cargo.isEmpty ? role : '$role · $cargo';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: uaRoleSwatch(user.role),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: ThemeHelpers.textColor(context),
            ),
          ),
        ),
      ],
    );
  }
}

/// Estado + último acesso. Ativo = check discreto com "Acessou há…";
/// exceções (nunca acessou, desativado) ganham pílula para saltar aos olhos.
class _StatusMark extends StatelessWidget {
  const _StatusMark({required this.user});

  final AdminUser user;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final last = user.lastLoginAt;
    if (_isDisabled(user)) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Pill(
            label: 'Desativado',
            icon: LucideIcons.ban,
            tone: isDark
                ? AppColors.text.textLightDarkMode
                : AppColors.text.textLight,
          ),
          if (last != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'último acesso ${_lastAccessLabel(last)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: secondary,
                ),
              ),
            ),
          ],
        ],
      );
    }
    if (last == null) {
      return _Pill(
        label: 'Nunca acessou',
        icon: LucideIcons.clock,
        tone: isDark
            ? AppColors.status.warningDarkMode
            : AppColors.message.warningText,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          LucideIcons.circleCheck,
          size: 13,
          color: isDark
              ? AppColors.status.successDarkMode
              : AppColors.status.success,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            'Acessou ${_lastAccessLabel(last)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: secondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Pílula de estado: tom no fundo, borda e ícone; texto na tinta de texto.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.icon, required this.tone});

  final String label;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: isDark ? 0.4 : 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: tone),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: ThemeHelpers.textColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Folha de ações da linha (identidade + editar + desativar/reativar)
// ──────────────────────────────────────────────────────────────────────────

class _UserActionsSheet extends StatelessWidget {
  const _UserActionsSheet({
    required this.user,
    required this.onEdit,
    required this.onToggle,
  });

  final AdminUser user;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hairline = ThemeHelpers.borderLightColor(context);
    final willDeactivate = user.isActiveInCompany;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final success =
        isDark ? AppColors.status.successDarkMode : AppColors.status.success;
    final info = isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    final phone = user.phone?.trim();

    return Container(
      // Teto de 88%: em paisagem/tela baixa as ações rolam dentro.
      constraints: BoxConstraints(maxHeight: mq.size.height * 0.88),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 8, bottom: 10),
                decoration: BoxDecoration(
                  color: ThemeHelpers.borderColor(context),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 6, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  UaAvatar(
                    name: user.name,
                    url: user.avatar,
                    tone: uaRoleTone(user.role, isDark: isDark),
                    size: 48,
                    radius: 15,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name.isEmpty ? 'Sem nome' : user.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w900,
                            color: textColor,
                            letterSpacing: -0.3,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: secondary,
                          ),
                        ),
                        if (phone != null && phone.isNotEmpty)
                          Text(
                            phone,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: secondary,
                            ),
                          ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _RoleMark(user: user),
                            _StatusMark(user: user),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(LucideIcons.x, size: 20, color: secondary),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: hairline),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ActionTile(
                      icon: LucideIcons.userPen,
                      tone: info,
                      title: 'Editar usuário',
                      subtitle: 'Dados, papel, gestores, tags e permissões',
                      onTap: onEdit,
                    ),
                    Container(
                      height: 1,
                      margin: const EdgeInsets.only(left: 68, right: 12),
                      color: hairline,
                    ),
                    _ActionTile(
                      icon: willDeactivate
                          ? LucideIcons.userX
                          : LucideIcons.userCheck,
                      tone: willDeactivate ? danger : success,
                      title: willDeactivate
                          ? 'Desativar acesso'
                          : 'Reativar acesso',
                      subtitle: willDeactivate
                          ? 'Bloqueia o login nesta empresa. Antes de '
                              'confirmar, você vê o que acontece com os '
                              'cards do funil.'
                          : 'Libera o login nesta empresa de novo, na hora.',
                      titleColor: willDeactivate ? danger : null,
                      onTap: onToggle,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tile flush da folha de ações — roundel no tom do significado + título +
/// subtítulo informativo + chevron (sem caixa tingida em volta).
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.titleColor,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: isDark ? 0.18 : 0.12),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: titleColor ?? ThemeHelpers.textColor(context),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: secondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                LucideIcons.chevronRight,
                size: 18,
                color: secondary.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Skeleton / Vazio / Erro / Sem acesso
// ──────────────────────────────────────────────────────────────────────────

/// Skeleton fiel à linha: avatar, nome, e-mail e a linha de papel/estado.
class _UsersSkeleton extends StatelessWidget {
  const _UsersSkeleton({this.rows = 6});

  final int rows;

  @override
  Widget build(BuildContext context) {
    final hairline = ThemeHelpers.borderLightColor(context);
    return Column(
      children: [
        for (var i = 0; i < rows; i++) ...[
          if (i > 0)
            Container(
              height: 1,
              margin: const EdgeInsets.only(left: 56),
              color: hairline,
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonBox(width: 44, height: 44, borderRadius: 14),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(
                        width: 130.0 + (i % 3) * 22,
                        height: 14,
                        borderRadius: 4,
                      ),
                      const SizedBox(height: 7),
                      const SkeletonBox(width: 180, height: 11, borderRadius: 4),
                      const SizedBox(height: 11),
                      const Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          SkeletonBox(width: 84, height: 12, borderRadius: 4),
                          SkeletonBox(width: 118, height: 12, borderRadius: 4),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const SkeletonBox(width: 18, height: 18, borderRadius: 4),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Vazio que ensina: com busca/filtro, diz o que fazer e oferece limpar;
/// sem nada, explica para que serve a tela e leva ao cadastro.
class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({
    required this.filtered,
    required this.canCreate,
    required this.onClear,
    required this.onCreate,
  });

  final bool filtered;
  final bool canCreate;
  final VoidCallback onClear;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final textColor = ThemeHelpers.textColor(context);
    final brand =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 36, 8, 24),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: ThemeHelpers.borderLightColor(context),
              shape: BoxShape.circle,
            ),
            child: Icon(
              filtered ? LucideIcons.searchX : LucideIcons.users,
              size: 24,
              color: secondary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            filtered
                ? 'Ninguém com essa busca ou filtros'
                : 'Nenhum usuário por aqui ainda',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: textColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            filtered
                ? 'Confira a grafia do nome ou do e-mail, ou limpe os filtros '
                    'para ver a equipe inteira.'
                : 'Cadastre a equipe da empresa para que cada pessoa entre '
                    'no sistema com o próprio acesso.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: secondary,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          if (filtered)
            OutlinedButton.icon(
              onPressed: onClear,
              style: OutlinedButton.styleFrom(
                foregroundColor: textColor,
                side: BorderSide(color: ThemeHelpers.borderColor(context)),
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(LucideIcons.x, size: 16),
              label: const Text(
                'Limpar busca e filtros',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            )
          else if (canCreate)
            FilledButton.icon(
              onPressed: onCreate,
              style: FilledButton.styleFrom(
                backgroundColor: brand,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(LucideIcons.userPlus, size: 17),
              label: const Text(
                'Cadastrar o primeiro usuário',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({
    required this.message,
    required this.onRetry,
    this.statusCode = 0,
    this.error,
  });

  final String message;
  final int statusCode;
  final Object? error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return AppErrorState.fromApi(
      message: message,
      statusCode: statusCode,
      error: error,
      onRetry: onRetry,
      dense: true,
    );
  }
}

class _UsersDeniedView extends StatelessWidget {
  const _UsersDeniedView();

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: ThemeHelpers.borderLightColor(context),
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.lock, size: 24, color: secondary),
            ),
            const SizedBox(height: 14),
            Text(
              'Você não tem acesso à lista de usuários',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w800,
                fontSize: 15.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Peça ao administrador da empresa a permissão '
              '"Visualizar usuários".',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondary, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Desativar acesso — prévia do funil + redistribuição (UserDeactivateModal)
// ───────────────────────────────────────────────────────────────────────────

class _DeactivateOutcome {
  final bool deactivated;
  final String message;
  final List<String> warnings;
  const _DeactivateOutcome({
    required this.deactivated,
    required this.message,
    this.warnings = const [],
  });
}

/// Porte do `UserDeactivateModal` do web: carrega a prévia dos cards em
/// aberto por funil, oferece redistribuir entre a equipe (quem tem
/// `kanban:update`) e só então desativa na empresa. Tudo acontece aqui
/// dentro; a folha fecha com o resultado para a lista.
class _DeactivateUserSheet extends StatefulWidget {
  const _DeactivateUserSheet({
    required this.user,
    required this.canRedistributeFunnel,
  });

  final AdminUser user;
  final bool canRedistributeFunnel;

  @override
  State<_DeactivateUserSheet> createState() => _DeactivateUserSheetState();
}

class _DeactivateUserSheetState extends State<_DeactivateUserSheet> {
  bool _loading = true;
  bool _submitting = false;
  UserFunnelPreview _preview = const UserFunnelPreview();
  bool _redistribute = true;
  String? _error;

  String get _firstName {
    final f = widget.user.name.trim().split(RegExp(r'\s+')).first;
    return f.isEmpty ? 'ele' : f;
  }

  bool get _hasOpenCards => _preview.totalOpenTasks > 0;
  bool get _showRedistribute => _hasOpenCards && widget.canRedistributeFunnel;
  bool get _willRedistribute => _showRedistribute && _redistribute;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    final res = await AdminUsersService.instance.getFunnelAssignmentPreview(
      widget.user.id,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      // Falha na prévia = segue como o web: sem cards, sem redistribuir.
      _preview = res.success && res.data != null
          ? res.data!
          : const UserFunnelPreview();
      _redistribute = _preview.totalOpenTasks > 0 &&
          widget.canRedistributeFunnel;
    });
  }

  Future<void> _confirm() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final svc = AdminUsersService.instance;
    final warnings = <String>[];
    var infoPrefix = '';

    if (_willRedistribute) {
      var updatedTotal = 0;
      final failed = <String>[];
      for (final p in _preview.projects) {
        if (p.openTaskCount <= 0) continue;
        final r = await svc.redistributeFunnelLeads(p.projectId, widget.user.id);
        if (r.success) {
          updatedTotal += r.data ?? 0;
        } else {
          failed.add(p.projectName);
        }
        if (!mounted) return;
      }
      if (failed.isNotEmpty) {
        warnings.add(
          'Não foi possível redistribuir em: ${failed.join(', ')}. O desativar seguirá mesmo assim.',
        );
      } else if (updatedTotal > 0) {
        infoPrefix =
            '$updatedTotal card${updatedTotal == 1 ? '' : 's'} redistribuído${updatedTotal == 1 ? '' : 's'} no funil. ';
      }
    }

    final res = await svc.deactivateInCompany(widget.user.id);
    if (!mounted) return;
    if (!res.success) {
      setState(() {
        _submitting = false;
        _error = res.message ?? 'Erro ao alterar status do usuário';
      });
      if (warnings.isNotEmpty) {
        setState(() => _error = '${warnings.join(' ')} ${_error ?? ''}');
      }
      return;
    }
    final msg = (res.data ?? const DeactivateUserResult())
        .successMessage(widget.user.name);
    Navigator.of(context).pop(
      _DeactivateOutcome(
        deactivated: true,
        message: '$infoPrefix$msg',
        warnings: warnings,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hairline = ThemeHelpers.borderLightColor(context);
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final warn = isDark
        ? AppColors.status.warningDarkMode
        : AppColors.message.warningText;
    final info =
        isDark ? AppColors.status.infoDarkMode : AppColors.message.infoText;
    final success =
        isDark ? AppColors.status.successDarkMode : AppColors.status.success;
    final total = _preview.totalOpenTasks;
    final who = widget.user.name.trim().isEmpty
        ? 'Esta pessoa'
        : widget.user.name.trim();

    final confirmLabel = _submitting
        ? (_willRedistribute
            ? 'Redistribuindo e desativando…'
            : 'Desativando…')
        : (_willRedistribute
            ? 'Redistribuir e desativar'
            : 'Confirmar desativação');

    return Container(
      // Teto de 88% + corpo rolável: em paisagem só o miolo rola, título e
      // botões ficam à vista.
      constraints: BoxConstraints(maxHeight: mq.size.height * 0.88),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
          ),
        ),
      ),
      padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + mq.padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: ThemeHelpers.borderColor(context),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: danger.withValues(alpha: isDark ? 0.20 : 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(LucideIcons.userX, size: 19, color: danger),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Desativar acesso',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: textColor,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      who,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: hairline),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Frase do cabeçalho do modal do web (paridade) — já à
                  // vista enquanto a prévia do funil carrega.
                  Text(
                    'Você está desativando ${widget.user.name} nesta empresa. '
                    'Ele continua no cadastro, mas não entra mais no sistema.',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (_loading)
                    ...const [
                      SizedBox(height: 8),
                      SkeletonBox(height: 56, borderRadius: 12),
                      SizedBox(height: 12),
                      SkeletonBox(height: 56, borderRadius: 12),
                      SizedBox(height: 12),
                      SkeletonBox(height: 56, borderRadius: 12),
                    ]
                  else ...[
                        _impact(
                          icon: LucideIcons.ban,
                          tone: danger,
                          title: 'Acesso ao sistema',
                          body:
                              'O login e o uso do painel nesta empresa ficam bloqueados imediatamente após confirmar.',
                        ),
                        _divider(),
                        _impact(
                          icon: LucideIcons.house,
                          tone: warn,
                          title: 'Imóveis e cadastros',
                          body:
                              'Imóveis em que $_firstName era responsável podem ser transferidos automaticamente conforme as regras de desativação configuradas na empresa.',
                        ),
                        _divider(),
                        _impact(
                          icon: LucideIcons.kanban,
                          tone: _hasOpenCards ? warn : info,
                          title: 'Funil de vendas',
                          body: _hasOpenCards
                              ? '$total ${total == 1 ? 'negociação em aberto' : 'negociações em aberto'} com este responsável:'
                              : 'Nenhuma negociação em aberto no funil com este responsável.',
                          extra: _hasOpenCards
                              ? Column(
                                  children: [
                                    for (final p in _preview.projects)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                p.projectName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: textColor,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '${p.openTaskCount} ${p.openTaskCount == 1 ? 'card' : 'cards'}',
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w900,
                                                color: textColor,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                )
                              : null,
                        ),
                        if (_hasOpenCards) ...[
                          const SizedBox(height: 16),
                          Text(
                            'O QUE FAZER COM OS CARDS DO FUNIL',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                              color: secondary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (_showRedistribute) ...[
                            _choice(
                              selected: _redistribute,
                              tone: success,
                              icon: LucideIcons.split,
                              title: 'Redistribuir entre a equipe e desativar',
                              hint:
                                  'Reparte os cards em aberto entre os outros membros que recebem leads em cada funil (rodízio). Recomendado para não deixar negociações paradas.',
                              onTap: () =>
                                  setState(() => _redistribute = true),
                            ),
                            const SizedBox(height: 8),
                            _choice(
                              selected: !_redistribute,
                              tone: secondary,
                              icon: LucideIcons.userMinus,
                              title: 'Desativar sem redistribuir',
                              hint:
                                  'Os cards permanecem com $_firstName como responsável. Você pode redistribuir depois no quadro do funil.',
                              onTap: () =>
                                  setState(() => _redistribute = false),
                            ),
                          ] else
                            _impact(
                              icon: LucideIcons.info,
                              tone: info,
                              title: 'Sem permissão para redistribuir',
                              body:
                                  'Você não tem permissão para redistribuir leads. Após desativar, use "Redistribuir leads" no funil ou peça a um gestor.',
                            ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                            decoration: BoxDecoration(
                              color: danger.withValues(
                                alpha: isDark ? 0.14 : 0.08,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: danger.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  LucideIcons.circleAlert,
                                  size: 16,
                                  color: danger,
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: textColor,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                ],
              ),
            ),
          ),
          Container(height: 1, color: hairline),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed:
                    _submitting ? null : () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  // Cancelar nunca em vermelho: neutro forçado.
                  foregroundColor: secondary,
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Cancelar',
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _submitting || _loading ? null : _confirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: danger,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: danger.withValues(alpha: 0.4),
                    disabledForegroundColor:
                        Colors.white.withValues(alpha: 0.9),
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(LucideIcons.userX, size: 18),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      confirmLabel,
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        height: 1,
        margin: const EdgeInsets.only(left: 46),
        color: ThemeHelpers.borderLightColor(context),
      );

  Widget _impact({
    required IconData icon,
    required Color tone,
    required String title,
    required String body,
    Widget? extra,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: isDark ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: tone),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: ThemeHelpers.textSecondaryColor(context),
                    height: 1.35,
                  ),
                ),
                ?extra,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _choice({
    required bool selected,
    required Color tone,
    required IconData icon,
    required String title,
    required String hint,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final radius = BorderRadius.circular(14);
    return Material(
      color: selected
          ? tone.withValues(alpha: isDark ? 0.12 : 0.07)
          : Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: _submitting ? null : onTap,
        borderRadius: radius,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: selected
                  ? tone.withValues(alpha: 0.55)
                  : ThemeHelpers.borderColor(context),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected ? LucideIcons.circleDot : LucideIcons.circle,
                size: 18,
                color: selected ? tone : secondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(
                            icon,
                            size: 14,
                            color: selected ? tone : secondary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: textColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hint,
                      style: TextStyle(
                        fontSize: 12,
                        color: secondary,
                        height: 1.35,
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
}
