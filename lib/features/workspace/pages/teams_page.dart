import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_permissions.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/state/screen_state_cache.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/company_team_model.dart';
import '../services/company_team_service.dart';
import '../widgets/teams_filters_sheet.dart';

/// Tela de Colaboradores → Equipes.
///
/// Paridade visual com `imobx-front` `TeamsPage.tsx` (lista refinada de
/// equipes, busca, filtros, gating por permissão).
class TeamsPage extends StatefulWidget {
  const TeamsPage({super.key});

  @override
  State<TeamsPage> createState() => _TeamsPageState();
}

class _TeamsPageState extends State<TeamsPage> {
  static const String _stateCacheKey = 'workspace/teams';
  static const int _pageSize = 12;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  List<CompanyTeam> _teams = [];
  int _page = 1;
  int _totalPages = 1;
  int _total = 0;

  String _search = '';
  TeamsFilters _filters = const TeamsFilters();
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
      _searchDebounce = Timer(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        _persistState();
        _reload();
      });
    });
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _reload();
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
      _filters = TeamsFilters.fromMap(Map<String, dynamic>.from(f));
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
    if (p.pixels >= p.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
    });
    final res = await CompanyTeamService.instance.listTeams(
      page: 1,
      limit: _pageSize,
      search: _search.trim().isEmpty ? null : _search.trim(),
      teamName: _filters.teamName,
      memberName: _filters.memberName,
      tag: _filters.tag,
      status: _filters.status,
      color: _filters.color,
      dateRange: _filters.dateRange,
      onlyMyData: _filters.onlyMyData,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _teams = res.data!.teams;
        _page = res.data!.page;
        _totalPages = res.data!.totalPages;
        _total = res.data!.total;
      } else {
        _error = res.message ?? 'Erro ao listar equipes';
      }
    });
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    final res = await CompanyTeamService.instance.listTeams(
      page: _page + 1,
      limit: _pageSize,
      search: _search.trim().isEmpty ? null : _search.trim(),
      teamName: _filters.teamName,
      memberName: _filters.memberName,
      tag: _filters.tag,
      status: _filters.status,
      color: _filters.color,
      dateRange: _filters.dateRange,
      onlyMyData: _filters.onlyMyData,
    );
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (res.success && res.data != null) {
        _teams.addAll(res.data!.teams);
        _page = res.data!.page;
        _totalPages = res.data!.totalPages;
      }
    });
  }

  Future<void> _openFilters() async {
    final updated = await showModalBottomSheet<TeamsFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TeamsFiltersSheet(initial: _filters),
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
      _filters = const TeamsFilters();
    });
    _persistState();
    _reload();
  }

  Future<void> _confirmDelete(CompanyTeam team) async {
    final canDelete = ModuleAccessService.instance.hasPermission(
      AppPermissions.teamDelete,
    );
    if (!canDelete) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir equipe?'),
        content: Text(
          'A equipe "${team.name}" será excluída. Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade600,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final res = await CompanyTeamService.instance.deleteTeam(team.id);
    if (!mounted) return;
    if (res.success) {
      setState(() {
        _teams.removeWhere((t) => t.id == team.id);
        _total = (_total - 1).clamp(0, 1 << 30);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Equipe excluída.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message ?? 'Falha ao excluir.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canView = ModuleAccessService.instance.hasPermission(
          AppPermissions.teamView,
        ) ||
        ModuleAccessService.instance.hasCompanyModule('team_management');

    if (!canView) {
      return const AppScaffold(
        title: 'Equipes',
        showBottomNavigation: false,
        body: _TeamsDeniedView(),
      );
    }

    final filterCount = _filters.activeCount;
    final hasAnyFilter = filterCount > 0 || _search.trim().isNotEmpty;

    return AppScaffold(
      title: 'Equipes',
      showBottomNavigation: false,
      actions: [
        if (ModuleAccessService.instance
            .hasPermission(AppPermissions.teamCreate))
          IconButton(
            tooltip: 'Nova equipe',
            icon: const Icon(LucideIcons.plus, size: 20),
            onPressed: () async {
              final created = await Navigator.of(context)
                  .pushNamed('/teams/create');
              if (created == true && mounted) _reload();
            },
          ),
      ],
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            _Hero(
              total: _total,
              page: _page,
              totalPages: _totalPages,
              teams: _teams,
            ),
            const SizedBox(height: 16),
            _Toolbar(
              controller: _searchController,
              onFilterTap: _openFilters,
              filterCount: filterCount,
              onClearAll: hasAnyFilter ? _clearAll : null,
            ),
            const SizedBox(height: 12),
            if (_loading)
              const _TeamsShimmer()
            else if (_error != null)
              _ErrorBlock(message: _error!, onRetry: _reload)
            else if (_teams.isEmpty)
              const _EmptyBlock()
            else
              _TeamsList(
                teams: _teams,
                onDelete: _confirmDelete,
                onEdit: (t) async {
                  final changed = await Navigator.of(context)
                      .pushNamed('/teams/${t.id}/edit');
                  if (changed == true && mounted) _reload();
                },
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
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Hero
// ──────────────────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero({
    required this.total,
    required this.page,
    required this.totalPages,
    required this.teams,
  });

  final int total;
  final int page;
  final int totalPages;
  final List<CompanyTeam> teams;

  /// Soma membros únicos por id em todas as equipes carregadas até agora.
  /// Não é o total absoluto da empresa (depende da paginação), mas dá um
  /// número útil pro chip "Pessoas".
  int get _uniqueMembers {
    final ids = <String>{};
    for (final t in teams) {
      for (final m in t.members) {
        if (m.userId.isNotEmpty) ids.add(m.userId);
      }
    }
    return ids.length;
  }

  /// Cores distintas das equipes carregadas — vira o "colar" de identidade
  /// ao lado do subtítulo (máx. 6, na ordem da lista).
  List<Color> get _palette {
    final seen = <int>{};
    final out = <Color>[];
    for (final t in teams) {
      final c = _parseTeamColor(t.color);
      if (seen.add(c.toARGB32())) out.add(c);
      if (out.length >= 6) break;
    }
    return out;
  }

  /// Conta equipes ativas e equipes "vazias" (sem membros) na página atual.
  ({int active, int empty, int withLeader}) get _localStats {
    var active = 0;
    var empty = 0;
    var withLeader = 0;
    for (final t in teams) {
      if (t.isActive) active++;
      if (t.members.isEmpty) empty++;
      if (t.members.any((m) => m.isLeader)) withLeader++;
    }
    return (active: active, empty: empty, withLeader: withLeader);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondaryColor = ThemeHelpers.textSecondaryColor(context);
    final formatter = NumberFormat.decimalPattern('pt_BR');

    // Paleta editorial — indigo (equipes), emerald (ativas), violet
    // (lideranças), amber (página).
    final indigo =
        isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1);
    final emerald =
        isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
    final violet =
        isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED);
    final amber =
        isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);

    final stats = _localStats;
    final pageLabel = totalPages > 1 ? '$page / $totalPages' : '$page';

    final subtitle = total == 0
        ? 'Crie sua primeira equipe pra organizar fluxos por grupo.'
        : '${stats.active} ativas · ${stats.withLeader} com liderança · ${stats.empty} sem membros';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
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
                  color: indigo,
                  boxShadow: [
                    BoxShadow(
                      color: indigo.withValues(alpha: 0.55),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              Text(
                'ORGANIZAÇÃO · EQUIPES',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: indigo,
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
                formatter.format(total),
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
                  total == 1 ? 'equipe' : 'equipes',
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
          Row(
            children: [
              // Micro-pilha com as cores das equipes carregadas — ecoa a
              // identidade dos cards sem virar chip/pill.
              if (_palette.isNotEmpty) ...[
                SizedBox(
                  height: 13,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < _palette.length; i++)
                        Align(
                          widthFactor: i == 0 ? 1 : 0.58,
                          child: Container(
                            width: 13,
                            height: 13,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _palette[i],
                              border: Border.all(
                                color:
                                    ThemeHelpers.backgroundColor(context),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: secondaryColor,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Strip editorial — 4 colunas separadas por 1px vertical, sem
          // bordas/chips. Cada coluna conta uma micro-história (label +
          // valor grande + sub contextual + traço accent).
          _HeroKpiStrip(
            blocks: [
              _HeroKpiBlock(
                icon: LucideIcons.checkCircle2,
                label: 'ATIVAS',
                value: '${stats.active}',
                sub: total > 0
                    ? '${((stats.active / total) * 100).toStringAsFixed(0)}% do total'
                    : 'em operação',
                tone: emerald,
              ),
              _HeroKpiBlock(
                icon: LucideIcons.users,
                label: 'PESSOAS',
                value: '$_uniqueMembers',
                sub: _uniqueMembers == 1 ? 'única' : 'únicas',
                tone: indigo,
              ),
              _HeroKpiBlock(
                icon: LucideIcons.crown,
                label: 'COM LÍDER',
                value: '${stats.withLeader}',
                sub: stats.empty > 0
                    ? '${stats.empty} sem ninguém'
                    : 'liderança ativa',
                tone: violet,
              ),
              _HeroKpiBlock(
                icon: LucideIcons.layers,
                label: 'PÁGINA',
                value: pageLabel,
                sub: totalPages > 1
                    ? '$totalPages no total'
                    : 'única',
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
/// Sem bordas / sem fill — pura tipografia editorial.
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
// Toolbar
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
          // Acaba o "card dentro de card" — uma só peça responsiva.
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
                        hintText: 'Buscar por equipe ou membro',
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
// List
// ──────────────────────────────────────────────────────────────────────────

class _TeamsList extends StatelessWidget {
  const _TeamsList({
    required this.teams,
    required this.onDelete,
    required this.onEdit,
  });

  final List<CompanyTeam> teams;
  final Future<void> Function(CompanyTeam) onDelete;
  final Future<void> Function(CompanyTeam) onEdit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          for (final t in teams) ...[
            _TeamCard(
              team: t,
              onDelete: () => onDelete(t),
              onEdit: () => onEdit(t),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

/// Converte o hex vindo da API (`#RRGGBB`) na cor da equipe.
/// Fallback indigo — mesmo default do web (`#6366f1`).
Color _parseTeamColor(String? raw) {
  final hex = (raw ?? '').replaceFirst('#', '').trim();
  final v = int.tryParse('FF$hex', radix: 16);
  return v == null ? const Color(0xFF6366F1) : Color(v);
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({
    required this.team,
    required this.onDelete,
    required this.onEdit,
  });

  final CompanyTeam team;
  final Future<void> Function() onDelete;
  final Future<void> Function() onEdit;

  /// Iniciais da EQUIPE pro monograma — paridade com `getInitials` do web
  /// (uma palavra → 2 primeiras letras; várias → primeira + última).
  static String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final w = parts.first;
      return w.substring(0, w.length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondaryColor = ThemeHelpers.textSecondaryColor(context);
    final borderColor = ThemeHelpers.borderColor(context);
    final cardColor = ThemeHelpers.cardBackgroundColor(context);

    // Equipe inativa fica com a identidade "apagada" — a cor real ainda
    // aparece no hex tag do rodapé.
    final baseColor = _parseTeamColor(team.color);
    final color = team.isActive
        ? baseColor
        : Color.lerp(baseColor, const Color(0xFF9CA3AF), 0.5)!;
    // Fundo do gradiente do monograma/filete — mistura com índigo profundo,
    // igual ao `color-mix(... #312e81)` do web.
    final deep = Color.lerp(color, const Color(0xFF312E81), isDark ? 0.38 : 0.45)!;
    final amber = isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
    final emerald = isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
    final slate = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final canUpdate = ModuleAccessService.instance.hasPermission(
      AppPermissions.teamUpdate,
    );
    final canDelete = ModuleAccessService.instance.hasPermission(
      AppPermissions.teamDelete,
    );

    final leaders = team.members.where((m) => m.isLeader).toList();
    final statusTone = team.isActive ? emerald : slate;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? color.withValues(alpha: 0.18)
              : borderColor.withValues(alpha: 0.55),
        ),
        boxShadow: ThemeHelpers.cardShadow(context, strength: 0.7),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // Aura radial na cor da equipe — canto superior direito,
            // bem sutil (paridade com o ::after do card web).
            Positioned(
              top: -78,
              right: -52,
              child: IgnorePointer(
                child: Container(
                  width: 210,
                  height: 210,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        color.withValues(alpha: isDark ? 0.14 : 0.08),
                        color.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Filete gradiente na borda esquerda — assinatura da equipe.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 4.5,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [color, deep],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18.5, 14, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─── Cabeçalho: monograma + eyebrow/nome/descrição + ações
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TeamMonogram(
                        initials: _initials(team.name),
                        color: color,
                        deep: deep,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Eyebrow: contexto + status com cor semântica.
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'EQUIPE',
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w900,
                                    color: color,
                                    letterSpacing: 1.8,
                                    height: 1.0,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: statusTone,
                                    boxShadow: [
                                      BoxShadow(
                                        color: statusTone.withValues(
                                          alpha: 0.5,
                                        ),
                                        blurRadius: 5,
                                        spreadRadius: 0.5,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  team.isActive ? 'ATIVA' : 'INATIVA',
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w900,
                                    color: statusTone,
                                    letterSpacing: 1.4,
                                    height: 1.0,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              team.name.isEmpty ? '—' : team.name,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: textColor,
                                letterSpacing: -0.3,
                                fontSize: 15.5,
                                height: 1.1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            if ((team.description ?? '').isNotEmpty)
                              Text(
                                team.description!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: secondaryColor,
                                  fontWeight: FontWeight.w500,
                                  height: 1.35,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              )
                            else
                              Text(
                                'Sem descrição',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontStyle: FontStyle.italic,
                                  color: secondaryColor.withValues(
                                    alpha: 0.6,
                                  ),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (canUpdate)
                        _IconAction(
                          icon: LucideIcons.pencil,
                          tooltip: 'Editar',
                          onTap: () => onEdit(),
                        ),
                      if (canDelete) ...[
                        const SizedBox(width: 6),
                        _IconAction(
                          icon: LucideIcons.trash2,
                          tooltip: 'Excluir',
                          destructive: true,
                          onTap: () => onDelete(),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  // ─── Pessoas: pilha de avatares reais + chip de liderança
                  if (team.members.isNotEmpty)
                    Row(
                      children: [
                        _AvatarStack(
                          members: team.members,
                          color: color,
                          deep: deep,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: leaders.isNotEmpty
                              ? _LeadersChip(leaders: leaders, isDark: isDark)
                              : Text(
                                  'Sem liderança definida',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    fontStyle: FontStyle.italic,
                                    color: secondaryColor.withValues(
                                      alpha: 0.75,
                                    ),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                        ),
                      ],
                    )
                  else
                    _EmptyMembersRow(tone: color),
                  const SizedBox(height: 13),
                  Container(
                    height: 1,
                    color: borderColor.withValues(alpha: 0.38),
                  ),
                  const SizedBox(height: 10),
                  // ─── Rodapé: métricas com significado + hex da cor
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 13,
                          runSpacing: 7,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _FooterMetric(
                              icon: LucideIcons.users,
                              iconColor: color,
                              strong: '${team.totalMembers}',
                              label: team.totalMembers == 1
                                  ? 'membro'
                                  : 'membros',
                            ),
                            if (leaders.isNotEmpty)
                              _FooterMetric(
                                icon: LucideIcons.crown,
                                iconColor: amber,
                                strong: '${leaders.length}',
                                label: leaders.length == 1
                                    ? 'líder'
                                    : 'líderes',
                              ),
                            if (team.useInSaleForms)
                              _FooterMetric(
                                icon: LucideIcons.fileCheck,
                                iconColor: emerald,
                                label: 'em fichas',
                              ),
                            if (team.createdAt != null)
                              _FooterMetric(
                                icon: LucideIcons.calendar,
                                iconColor: secondaryColor.withValues(
                                  alpha: 0.8,
                                ),
                                label:
                                    'desde ${DateFormat('MMM yyyy', 'pt_BR').format(team.createdAt!.toLocal())}',
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _ColorHexTag(color: baseColor, rawHex: team.color),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placa de identidade da equipe — monograma branco sobre gradiente na cor
/// da equipe (paridade com `TeamMonogram` do web).
class _TeamMonogram extends StatelessWidget {
  const _TeamMonogram({
    required this.initials,
    required this.color,
    required this.deep,
  });

  final String initials;
  final Color color;
  final Color deep;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, deep],
        ),
        // Realce interno no topo — o "inset highlight" do web.
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.16),
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: isDark ? 0.4 : 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
            spreadRadius: -2,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          letterSpacing: 0.2,
          height: 1.0,
        ),
      ),
    );
  }
}

/// Chip âmbar de liderança — primeiros nomes dos líderes (máx. 2) + "+N".
/// Paridade com `LeadersInline`/`FooterMetric $tone='leader'` do web.
class _LeadersChip extends StatelessWidget {
  const _LeadersChip({required this.leaders, required this.isDark});

  final List<CompanyTeamMember> leaders;
  final bool isDark;

  String get _label {
    final names = leaders
        .map((l) => l.name.trim().split(RegExp(r'\s+')).first)
        .where((n) => n.isNotEmpty)
        .toList();
    if (names.isEmpty) return leaders.length == 1 ? 'Líder' : 'Líderes';
    if (names.length <= 2) return names.join(' · ');
    return '${names.take(2).join(' · ')} +${names.length - 2}';
  }

  @override
  Widget build(BuildContext context) {
    final fg = isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E);
    final amber = isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: isDark ? 0.12 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: amber.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.crown, size: 11, color: amber),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              _label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: fg,
                letterSpacing: 0.1,
                height: 1.0,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Métrica do rodapé — ícone com cor semântica + valor forte + rótulo.
/// Sem pill/encapsulamento: tipografia direta (FooterMetric do web).
class _FooterMetric extends StatelessWidget {
  const _FooterMetric({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.strong,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String? strong;

  @override
  Widget build(BuildContext context) {
    final textColor = ThemeHelpers.textColor(context);
    final secondaryColor = ThemeHelpers.textSecondaryColor(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12.5, color: iconColor),
        const SizedBox(width: 5),
        RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: secondaryColor,
              height: 1.0,
              letterSpacing: 0.1,
            ),
            children: [
              if (strong != null && strong!.isNotEmpty)
                TextSpan(
                  text: '$strong ',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    color: textColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              TextSpan(text: label),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tag discreta com o hex da cor da equipe — dot com anel + código.
/// Paridade com o `ColorTag` do web.
class _ColorHexTag extends StatelessWidget {
  const _ColorHexTag({required this.color, required this.rawHex});

  final Color color;
  final String? rawHex;

  @override
  Widget build(BuildContext context) {
    final borderColor = ThemeHelpers.borderColor(context);
    final secondaryColor = ThemeHelpers.textSecondaryColor(context);
    final hex =
        (rawHex ?? '#6366F1').replaceFirst('#', '').toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.26),
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            hex,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: secondaryColor,
              letterSpacing: 0.9,
              height: 1.0,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Estado vazio inline quando a equipe não tem membros — ocupa o
/// espaço do preview com uma mensagem editorial discreta.
class _EmptyMembersRow extends StatelessWidget {
  const _EmptyMembersRow({required this.tone});

  final Color tone;

  @override
  Widget build(BuildContext context) {
    final secondaryColor = ThemeHelpers.textSecondaryColor(context);
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: tone.withValues(alpha: 0.12),
            border: Border.all(color: tone.withValues(alpha: 0.32)),
          ),
          alignment: Alignment.center,
          child: Icon(LucideIcons.userPlus, size: 14, color: tone),
        ),
        const SizedBox(width: 10),
        Text(
          'Ninguém alocado ainda',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: secondaryColor,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }
}

/// Pilha de avatares REAIS sobrepostos — foto quando houver, fallback em
/// gradiente na cor da equipe; líder ganha anel âmbar + mini coroa; overflow
/// vira bolha "+N" no fim da pilha (paridade com `AvatarStack` do web).
class _AvatarStack extends StatelessWidget {
  const _AvatarStack({
    required this.members,
    required this.color,
    required this.deep,
  });

  final List<CompanyTeamMember> members;
  final Color color;
  final Color deep;

  static const int _maxVisible = 5;

  @override
  Widget build(BuildContext context) {
    // Líderes primeiro — são o rosto da equipe.
    final ordered = [
      ...members.where((m) => m.isLeader),
      ...members.where((m) => !m.isLeader),
    ];
    final visible = ordered.take(_maxVisible).toList();
    final remaining = members.length - visible.length;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = ThemeHelpers.cardBackgroundColor(context);
    final secondaryColor = ThemeHelpers.textSecondaryColor(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < visible.length; i++)
          Align(
            widthFactor: i == 0 ? 1 : 0.7,
            child: _MemberBubble(
              member: visible[i],
              color: color,
              deep: deep,
            ),
          ),
        if (remaining > 0)
          Align(
            widthFactor: 0.7,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFF0F172A).withValues(alpha: 0.06),
                border: Border.all(color: cardColor, width: 2),
              ),
              alignment: Alignment.center,
              child: Text(
                '+$remaining',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  color: secondaryColor,
                  letterSpacing: -0.2,
                  height: 1.0,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MemberBubble extends StatelessWidget {
  const _MemberBubble({
    required this.member,
    required this.color,
    required this.deep,
  });

  final CompanyTeamMember member;
  final Color color;
  final Color deep;

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  static const Color _amber = Color(0xFFF59E0B);

  /// Fallback de iniciais — gradiente na cor da equipe com texto branco,
  /// igual ao `StackAvatar` do web (nada de cinza sem vida).
  Widget _monogram() {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, deep],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        _initials(member.name),
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          letterSpacing: 0.2,
          height: 1.0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = ThemeHelpers.cardBackgroundColor(context);
    final hasPhoto =
        member.avatar != null && member.avatar!.trim().isNotEmpty;

    final inner = hasPhoto
        ? ClipOval(
            child: SizedBox(
              width: 30,
              height: 30,
              child: Image.network(
                member.avatar!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _monogram(),
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return _monogram();
                },
              ),
            ),
          )
        : _monogram();

    return Tooltip(
      message: '${member.name} • ${member.isLeader ? "Líder" : "Membro"}',
      child: SizedBox(
        width: 38,
        height: 38,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Anel externo: âmbar quando líder (halo de liderança do web),
            // senão a própria cor do card recortando a sobreposição.
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: member.isLeader ? _amber : cardColor,
                  width: member.isLeader ? 1.8 : 2,
                ),
              ),
              alignment: Alignment.center,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: cardColor, width: 2),
                ),
                alignment: Alignment.center,
                child: inner,
              ),
            ),
            // Mini coroa no ombro do líder.
            if (member.isLeader)
              Positioned(
                top: -3,
                right: -1,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFD97706),
                    border: Border.all(color: cardColor, width: 1.4),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    LucideIcons.crown,
                    size: 8,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = ThemeHelpers.borderColor(context);
    final secondaryColor = ThemeHelpers.textSecondaryColor(context);
    final red = isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
    final fg = destructive ? red : secondaryColor;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              color: destructive
                  ? red.withValues(alpha: isDark ? 0.12 : 0.07)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.white),
              border: Border.all(
                color: destructive
                    ? red.withValues(alpha: 0.30)
                    : borderColor.withValues(alpha: 0.6),
              ),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 14.5, color: fg),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Shimmer / Empty / Error / Denied
// ──────────────────────────────────────────────────────────────────────────

class _TeamsShimmer extends StatelessWidget {
  const _TeamsShimmer();

  @override
  Widget build(BuildContext context) {
    final borderColor = ThemeHelpers.borderColor(context);
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
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: borderColor.withValues(alpha: 0.5),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    // Filete esquerdo — fiel à assinatura do card real.
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 4.5,
                        color: borderColor.withValues(alpha: 0.55),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18.5, 14, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Monograma 46×46.
                              SkeletonBox(
                                  width: 46, height: 46, borderRadius: 13),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: const [
                                    // Eyebrow EQUIPE · STATUS.
                                    SkeletonBox(
                                        width: 74,
                                        height: 8,
                                        borderRadius: 4),
                                    SizedBox(height: 8),
                                    SkeletonBox(
                                        width: 150,
                                        height: 14,
                                        borderRadius: 4),
                                    SizedBox(height: 7),
                                    SkeletonBox(
                                        width: 210,
                                        height: 11,
                                        borderRadius: 4),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Ações editar/excluir.
                              SkeletonBox(
                                  width: 32, height: 32, borderRadius: 9),
                              const SizedBox(width: 6),
                              SkeletonBox(
                                  width: 32, height: 32, borderRadius: 9),
                            ],
                          ),
                          const SizedBox(height: 14),
                          // Pilha de avatares + chip de liderança.
                          Row(
                            children: [
                              for (var i = 0; i < 4; i++)
                                Align(
                                  widthFactor: i == 0 ? 1 : 0.7,
                                  child: const SkeletonBox(
                                      width: 36,
                                      height: 36,
                                      borderRadius: 999),
                                ),
                              const SizedBox(width: 10),
                              const SkeletonBox(
                                  width: 96, height: 20, borderRadius: 999),
                            ],
                          ),
                          const SizedBox(height: 13),
                          Container(
                            height: 1,
                            color: borderColor.withValues(alpha: 0.38),
                          ),
                          const SizedBox(height: 10),
                          // Métricas do rodapé + hex tag.
                          Row(
                            children: const [
                              SkeletonBox(
                                  width: 68, height: 11, borderRadius: 4),
                              SizedBox(width: 13),
                              SkeletonBox(
                                  width: 54, height: 11, borderRadius: 4),
                              SizedBox(width: 13),
                              SkeletonBox(
                                  width: 74, height: 11, borderRadius: 4),
                              Spacer(),
                              SkeletonBox(
                                  width: 62, height: 18, borderRadius: 999),
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
              child: Icon(LucideIcons.users2, size: 24, color: secondary),
            ),
            const SizedBox(height: 14),
            Text(
              'Nenhuma equipe encontrada',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Ajuste a busca ou crie a primeira equipe no painel web.',
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
  final Future<void> Function() onRetry;

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

class _TeamsDeniedView extends StatelessWidget {
  const _TeamsDeniedView();

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
              'Você não tem permissão para ver equipes.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Solicite ao administrador a permissão "team:view".',
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
