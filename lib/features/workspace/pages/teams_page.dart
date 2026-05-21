import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

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
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: secondaryColor,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
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
  });

  final List<CompanyTeam> teams;
  final Future<void> Function(CompanyTeam) onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          for (final t in teams) ...[
            _TeamCard(team: t, onDelete: () => onDelete(t)),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({required this.team, required this.onDelete});

  final CompanyTeam team;
  final Future<void> Function() onDelete;

  Color _teamColor() {
    final hex = (team.color ?? '#888888').replaceFirst('#', '');
    final v = int.tryParse('FF$hex', radix: 16) ?? 0xFF888888;
    return Color(v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondaryColor = ThemeHelpers.textSecondaryColor(context);
    final borderColor = ThemeHelpers.borderColor(context);
    final cardColor = ThemeHelpers.cardBackgroundColor(context);
    final color = _teamColor();

    final canUpdate = ModuleAccessService.instance.hasPermission(
      AppPermissions.teamUpdate,
    );
    final canDelete = ModuleAccessService.instance.hasPermission(
      AppPermissions.teamDelete,
    );

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor.withValues(alpha: 0.55)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.55),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      team.name.isEmpty ? '—' : team.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: textColor,
                        letterSpacing: -0.2,
                        height: 1.15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if ((team.description ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        team.description!,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: secondaryColor,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (!team.isActive)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.grey.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    'Inativa',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 1,
            color: borderColor.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          // Preview de membros (com fotos quando disponíveis). Quando há
          // líder, a coroa pequena no canto da bolha sinaliza visualmente.
          if (team.members.isNotEmpty) ...[
            _MembersPreview(members: team.members, color: color),
            const SizedBox(height: 10),
            // Nome do líder principal — paridade com chip de liderança do web.
            _LeaderLine(members: team.members, tone: color),
            const SizedBox(height: 12),
          ] else ...[
            _EmptyMembersRow(tone: color),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              _MetaPill(
                icon: LucideIcons.users,
                label: 'Membros',
                value: team.totalMembers.toString(),
                tone: color,
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _MetaPill(
                icon: LucideIcons.crown,
                label: 'Líderes',
                value: team.leadersCount.toString(),
                tone: const Color(0xFFD97706),
                isDark: isDark,
              ),
              const Spacer(),
              if (canUpdate)
                _IconAction(
                  icon: LucideIcons.pencil,
                  tooltip: 'Editar',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Edição completa disponível em breve no app. Use a versão web por enquanto.',
                        ),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
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
          if (team.createdAt != null) ...[
            const SizedBox(height: 12),
            Container(
              height: 1,
              color: borderColor.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
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
                          text: DateFormat("d 'de' MMM yyyy", 'pt_BR')
                              .format(team.createdAt!.toLocal()),
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                if (team.useInSaleForms)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.fileCheck,
                          size: 11, color: secondaryColor),
                      const SizedBox(width: 4),
                      Text(
                        'EM FORMULÁRIOS',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          color: secondaryColor,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Linha curta com o nome do líder principal — destaque tipográfico
/// pra evidenciar quem está à frente da equipe. Quando há mais de um
/// líder, mostra "+N" ao final.
class _LeaderLine extends StatelessWidget {
  const _LeaderLine({required this.members, required this.tone});

  final List<CompanyTeamMember> members;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final leaders = members.where((m) => m.isLeader).toList();
    if (leaders.isEmpty) {
      final secondaryColor = ThemeHelpers.textSecondaryColor(context);
      return Row(
        children: [
          Icon(LucideIcons.alertCircle, size: 11, color: secondaryColor),
          const SizedBox(width: 5),
          Text(
            'SEM LIDERANÇA DEFINIDA',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              color: secondaryColor,
              letterSpacing: 1.2,
            ),
          ),
        ],
      );
    }
    final primary = leaders.first.name;
    final extras = leaders.length - 1;
    final textColor = ThemeHelpers.textColor(context);
    final secondaryColor = ThemeHelpers.textSecondaryColor(context);
    return Row(
      children: [
        Icon(LucideIcons.crown, size: 12, color: const Color(0xFFD97706)),
        const SizedBox(width: 6),
        Flexible(
          child: RichText(
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: TextStyle(
                fontSize: 11.5,
                color: secondaryColor,
                fontWeight: FontWeight.w600,
              ),
              children: [
                const TextSpan(text: 'Líder · '),
                TextSpan(
                  text: primary,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.1,
                  ),
                ),
                if (extras > 0)
                  TextSpan(
                    text: '  + $extras',
                    style: TextStyle(
                      color: tone,
                      fontWeight: FontWeight.w900,
                      fontSize: 10.5,
                      letterSpacing: 0.3,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
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

class _MembersPreview extends StatelessWidget {
  const _MembersPreview({required this.members, required this.color});

  final List<CompanyTeamMember> members;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final visible = members.take(4).toList();
    final remaining = members.length - visible.length;

    return Row(
      children: [
        for (var i = 0; i < visible.length; i++)
          Align(
            widthFactor: i == 0 ? 1 : 0.74,
            child: _MemberBubble(member: visible[i], borderColor: color),
          ),
        if (remaining > 0)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: color.withValues(alpha: 0.32),
                ),
              ),
              child: Text(
                '+$remaining',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MemberBubble extends StatelessWidget {
  const _MemberBubble({required this.member, required this.borderColor});

  final CompanyTeamMember member;
  final Color borderColor;

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Widget _monogram(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
      ),
      alignment: Alignment.center,
      child: Text(
        _initials(member.name),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: borderColor,
          letterSpacing: 0.3,
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
              width: 32,
              height: 32,
              child: Image.network(
                member.avatar!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _monogram(context),
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return _monogram(context);
                },
              ),
            ),
          )
        : _monogram(context);

    return Tooltip(
      message: '${member.name} • ${member.isLeader ? "Líder" : "Membro"}',
      child: SizedBox(
        width: 34,
        height: 34,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: cardColor, width: 2),
              ),
              alignment: Alignment.center,
              child: inner,
            ),
            // Coroa pequena no canto superior direito quando é líder —
            // paridade visual com o badge "Líder" do web.
            if (member.isLeader)
              Positioned(
                top: -3,
                right: -3,
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

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tone;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: tone),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: tone,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: tone,
            ),
          ),
        ],
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
    final accent = Theme.of(context).colorScheme.primary;
    final color = destructive ? Colors.red.shade500 : accent;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: color.withValues(alpha: 0.10),
              border: Border.all(
                color: color.withValues(alpha: 0.28),
              ),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 15, color: color),
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
                  color: ThemeHelpers.borderColor(context)
                      .withValues(alpha: 0.5),
                ),
              ),
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 12, height: 12, borderRadius: 999),
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
