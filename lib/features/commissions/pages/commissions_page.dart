import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_permissions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/commission_model.dart';
import '../services/commission_service.dart';
import '../widgets/commission_card.dart';

final NumberFormat _money = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 2,
);
final NumberFormat _compact = NumberFormat.compactCurrency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 1,
);

/// Estado de uma aba (lista paginada independente).
class _TabState {
  List<Commission> items = const [];
  bool loading = false;
  bool loadingMore = false;
  bool loaded = false;
  String? error;
  int page = 1;
  int totalPages = 1;
  bool get hasMore => page < totalPages;
}

/// Tela **Comissões** (foco no corretor) — mesmo DNA refinado da tela de
/// Aprovações: hero editorial com KPIs, busca flush, abas flush com contagem,
/// cabeçalho de painel (eyebrow + dot + título + hint) e sub-seções. O backend
/// escopa por corretor, então aqui é "minhas comissões".
class CommissionsPage extends StatefulWidget {
  const CommissionsPage({super.key});

  @override
  State<CommissionsPage> createState() => _CommissionsPageState();
}

class _CommissionsPageState extends State<CommissionsPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const double _kSectionGap = 12;
  static const int _pageSize = 30;

  static const _tabs = [
    CommissionTab.pending,
    CommissionTab.received,
    CommissionTab.history,
  ];

  CommissionTab _activeTab = CommissionTab.pending;
  final Map<CommissionTab, _TabState> _state = {
    CommissionTab.pending: _TabState(),
    CommissionTab.received: _TabState(),
    CommissionTab.history: _TabState(),
  };

  CommissionStats _stats = CommissionStats.zero;
  bool _statsLoading = true;

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _appliedSearch = '';
  bool _searchFocused = false;

  bool get _canView =>
      ModuleAccessService.instance.hasPermission(AppPermissions.commissionView);

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadTab(CommissionTab.pending);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ─── Cores ───────────────────────────────────────────────────────────────

  Color _accentColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
  }

  /// Tom semântico de cada aba (âmbar = a receber, verde = recebidas,
  /// vermelho da marca = histórico).
  Color _tabColor(BuildContext context, CommissionTab tab) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (tab) {
      case CommissionTab.pending:
        return isDark
            ? AppColors.status.warningDarkMode
            : AppColors.status.warning;
      case CommissionTab.received:
        return isDark
            ? AppColors.status.greenDarkMode
            : AppColors.status.green;
      case CommissionTab.history:
        return _accentColor(context);
    }
  }

  int _tabCount(CommissionTab tab) {
    switch (tab) {
      case CommissionTab.pending:
        return _stats.openCount;
      case CommissionTab.received:
        return _stats.paid;
      case CommissionTab.history:
        return _stats.total;
    }
  }

  // ─── Dados ───────────────────────────────────────────────────────────────

  CommissionFilters _filtersFor(CommissionTab tab, int page) {
    final search = _appliedSearch.trim().isEmpty ? null : _appliedSearch.trim();
    switch (tab) {
      case CommissionTab.pending:
        return CommissionFilters(
            paid: false, search: search, page: page, limit: _pageSize);
      case CommissionTab.received:
        return CommissionFilters(
            paid: true, search: search, page: page, limit: _pageSize);
      case CommissionTab.history:
        return CommissionFilters(
            search: search, page: page, limit: _pageSize);
    }
  }

  /// Refina no cliente: "Pendentes" mostra só pendentes/aprovadas (o
  /// `paid=false` do backend também traz canceladas).
  List<Commission> _refine(CommissionTab tab, List<Commission> list) {
    if (tab == CommissionTab.pending) {
      return list.where((c) => c.status.isOpen).toList();
    }
    return list;
  }

  Future<void> _loadStats() async {
    setState(() => _statsLoading = true);
    final res = await CommissionService.instance.getStatistics();
    if (!mounted) return;
    setState(() {
      _statsLoading = false;
      if (res.success && res.data != null) _stats = res.data!;
    });
  }

  Future<void> _loadTab(CommissionTab tab, {bool refresh = false}) async {
    final st = _state[tab]!;
    setState(() {
      st.loading = true;
      if (refresh) st.error = null;
    });
    final res = await CommissionService.instance.getCommissions(
      filters: _filtersFor(tab, 1),
    );
    if (!mounted) return;
    setState(() {
      st.loading = false;
      st.loaded = true;
      if (res.success && res.data != null) {
        st.items = _refine(tab, res.data!.commissions);
        st.page = res.data!.page;
        st.totalPages = res.data!.totalPages;
        st.error = null;
      } else {
        st.error = res.message ?? 'Erro ao carregar comissões';
      }
    });
  }

  Future<void> _loadMore(CommissionTab tab) async {
    final st = _state[tab]!;
    if (st.loadingMore || !st.hasMore) return;
    setState(() => st.loadingMore = true);
    final res = await CommissionService.instance.getCommissions(
      filters: _filtersFor(tab, st.page + 1),
    );
    if (!mounted) return;
    setState(() {
      st.loadingMore = false;
      if (res.success && res.data != null) {
        st.items = [...st.items, ..._refine(tab, res.data!.commissions)];
        st.page = res.data!.page;
        st.totalPages = res.data!.totalPages;
      }
    });
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadStats(), _loadTab(_activeTab, refresh: true)]);
  }

  void _selectTab(CommissionTab tab) {
    if (tab == _activeTab) return;
    setState(() => _activeTab = tab);
    final st = _state[tab]!;
    if (!st.loaded && !st.loading) _loadTab(tab);
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final v = value.trim();
      if (v == _appliedSearch) return;
      setState(() {
        _appliedSearch = v;
        // Busca muda o resultado de todas as abas — reseta e recarrega a ativa.
        for (final s in _state.values) {
          s.items = const [];
          s.loaded = false;
          s.page = 1;
          s.totalPages = 1;
        }
      });
      _loadStats();
      _loadTab(_activeTab, refresh: true);
    });
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canView) {
      return const AppScaffold(
        title: 'Comissões',
        showBottomNavigation: false,
        body: _DeniedView(),
      );
    }
    return AppScaffold(
      title: 'Comissões',
      showBottomNavigation: false,
      body: RefreshIndicator(
        color: _accentColor(context),
        onRefresh: _refreshAll,
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHero(context),
                        const SizedBox(height: _kSectionGap),
                        _buildSearchField(context),
                        const SizedBox(height: _kSectionGap),
                      ],
                    ),
                  ),
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

  // ─── Hero editorial ──────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accentColor(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final blue =
        isDark ? AppColors.status.infoDarkMode : AppColors.status.info;

    final total = _stats.total;
    final hasOpen = _stats.totalPending > 0;
    final dot = hasOpen ? amber : emerald;
    final subtitle = total == 0
        ? 'Suas comissões aparecem aqui assim que forem lançadas.'
        : hasOpen
            ? '${_money.format(_stats.totalPending)} a receber · '
                '${_stats.openCount} em aberto'
            : 'Tudo recebido — nada pendente no momento.';

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
                'MINHAS COMISSÕES',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
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
                '$total',
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
                  total == 1 ? 'comissão' : 'comissões',
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
          _buildKpiStrip(context, amber, emerald, blue),
        ],
      ),
    );
  }

  Widget _buildKpiStrip(
      BuildContext context, Color amber, Color emerald, Color blue) {
    final divider = ThemeHelpers.borderColor(context).withValues(alpha: 0.45);
    final blocks = <Widget>[
      _heroKpiBlock(context, LucideIcons.hourglass, 'A RECEBER',
          _compact.format(_stats.totalPending),
          '${_stats.openCount} em aberto', amber),
      _heroKpiBlock(context, LucideIcons.circleCheckBig, 'RECEBIDO',
          _compact.format(_stats.totalPaid),
          '${_stats.paid} paga${_stats.paid == 1 ? '' : 's'}', emerald),
      _heroKpiBlock(context, LucideIcons.calendarDays, 'ESTE MÊS',
          _compact.format(_stats.thisMonthValue), 'no período', blue),
    ];
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
            Expanded(child: blocks[i]),
          ],
        ],
      ),
    );
  }

  Widget _heroKpiBlock(BuildContext context, IconData icon, String label,
      String value, String sub, Color tone) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
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
                    letterSpacing: 1.2,
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
              _statsLoading ? '—' : value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: tone,
                letterSpacing: -0.6,
                height: 1.0,
                fontSize: 22,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            sub,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: secondary,
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

  // ─── Busca flush ─────────────────────────────────────────────────────────

  Widget _buildSearchField(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accentColor(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final cardColor = ThemeHelpers.cardBackgroundColor(context);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final hasText = _searchController.text.isNotEmpty;
    final showAccent = _searchFocused || hasText;

    return Focus(
      onFocusChange: (f) => setState(() => _searchFocused = f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        height: 50,
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: showAccent
                ? accent.withValues(alpha: isDark ? 0.5 : 0.42)
                : borderColor,
            width: showAccent ? 1.4 : 1,
          ),
          boxShadow: showAccent
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: isDark ? 0.18 : 0.12),
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
            Icon(LucideIcons.search,
                size: 18, color: showAccent ? accent : secondary),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                cursorColor: accent,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
                decoration: InputDecoration(
                  hintText: 'Buscar por cliente, imóvel…',
                  hintStyle: TextStyle(
                    color: secondary.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w500,
                    fontSize: 13.5,
                  ),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
                onChanged: (v) {
                  _onSearchChanged(v);
                  setState(() {});
                },
              ),
            ),
            if (hasText)
              InkResponse(
                radius: 18,
                onTap: () {
                  _searchController.clear();
                  _onSearchChanged('');
                  setState(() {});
                },
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(LucideIcons.x, size: 15, color: secondary),
                ),
              ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  // ─── Abas flush fixas ────────────────────────────────────────────────────

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
          for (final tab in _tabs)
            Expanded(
              child: _FlushTab(
                icon: _tabIcon(tab),
                label: _tabLabel(tab),
                count: _tabCount(tab),
                tone: _tabColor(context, tab),
                selected: _activeTab == tab,
                onTap: () => _selectTab(tab),
              ),
            ),
        ],
      ),
    );
  }

  IconData _tabIcon(CommissionTab tab) {
    switch (tab) {
      case CommissionTab.pending:
        return LucideIcons.hourglass;
      case CommissionTab.received:
        return LucideIcons.wallet;
      case CommissionTab.history:
        return LucideIcons.receipt;
    }
  }

  String _tabLabel(CommissionTab tab) {
    switch (tab) {
      case CommissionTab.pending:
        return 'Pendentes';
      case CommissionTab.received:
        return 'Recebidas';
      case CommissionTab.history:
        return 'Histórico';
    }
  }

  // ─── Painel ativo ────────────────────────────────────────────────────────

  Widget _buildActivePanel(BuildContext context) {
    final st = _state[_activeTab]!;
    Widget child;
    if (st.loading && st.items.isEmpty) {
      child = _buildSkeleton();
    } else if (st.error != null && st.items.isEmpty) {
      child = _buildError(context, _activeTab, st.error!);
    } else if (st.items.isEmpty) {
      child = _buildEmpty(context, _activeTab);
    } else {
      child = _buildTabBody(context, _activeTab, st);
    }

    return Column(
      key: ValueKey('panel-${_activeTab.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPanelHeader(context, _activeTab),
        const SizedBox(height: 14),
        child,
      ],
    ).animate(key: ValueKey('panel-${_activeTab.name}')).fadeIn(
          duration: 240.ms,
        );
  }

  ({IconData icon, String eyebrow, String title, String hint}) _panelMeta(
      CommissionTab tab) {
    switch (tab) {
      case CommissionTab.pending:
        return (
          icon: LucideIcons.hourglass,
          eyebrow: 'A RECEBER',
          title: 'Aguardando recebimento',
          hint: 'O que ainda vai cair na sua conta — pendentes e aprovadas.',
        );
      case CommissionTab.received:
        return (
          icon: LucideIcons.wallet,
          eyebrow: 'RECEBIDAS',
          title: 'Comissões pagas',
          hint: 'Tudo que já foi pago a você, do mais recente ao mais antigo.',
        );
      case CommissionTab.history:
        return (
          icon: LucideIcons.receipt,
          eyebrow: 'HISTÓRICO',
          title: 'Todas as comissões',
          hint: 'Seu histórico completo, agrupado por mês de lançamento.',
        );
    }
  }

  Widget _buildPanelHeader(BuildContext context, CommissionTab tab) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = _tabColor(context, tab);
    final meta = _panelMeta(tab);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: tone.withValues(alpha: isDark ? 0.2 : 0.12),
          ),
          child: Icon(meta.icon, color: tone, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: tone,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: tone.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    meta.eyebrow,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                meta.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                meta.hint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  height: 1.32,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabBody(BuildContext context, CommissionTab tab, _TabState st) {
    final nodes = <Widget>[];
    var animIndex = 0;

    void addList(List<Commission> list) {
      for (final c in list) {
        nodes.add(
          CommissionCard(
            commission: c,
            onTap: () => _showDetail(context, c),
          )
              .animate(key: ValueKey('c-${c.id}'))
              .fadeIn(
                delay: Duration(milliseconds: 30 * (animIndex++).clamp(0, 12)),
                duration: 220.ms,
              ),
        );
      }
    }

    void addSubsection(String label, IconData icon, int count) {
      if (nodes.isNotEmpty) nodes.add(const SizedBox(height: 14));
      nodes.add(_PanelSubsectionHeader(label: label, icon: icon, count: count));
      nodes.add(const SizedBox(height: 8));
    }

    switch (tab) {
      case CommissionTab.pending:
        final waiting =
            st.items.where((c) => c.status == CommissionStatus.pending).toList();
        final approved = st.items
            .where((c) => c.status == CommissionStatus.approved)
            .toList();
        if (waiting.isNotEmpty) {
          addSubsection('Aguardando aprovação', LucideIcons.clock3,
              waiting.length);
          addList(waiting);
        }
        if (approved.isNotEmpty) {
          addSubsection('Aprovadas · a pagar', LucideIcons.circleCheck,
              approved.length);
          addList(approved);
        }
        if (waiting.isEmpty && approved.isEmpty) addList(st.items);
        break;
      case CommissionTab.received:
        for (final group in _groupByMonth(
            st.items, (c) => c.paidAt ?? c.createdAt)) {
          addSubsection(group.label, LucideIcons.calendarCheck, group.items.length);
          addList(group.items);
        }
        break;
      case CommissionTab.history:
        for (final group
            in _groupByMonth(st.items, (c) => c.createdAt)) {
          addSubsection(group.label, LucideIcons.calendarDays, group.items.length);
          addList(group.items);
        }
        break;
    }

    if (st.hasMore) {
      nodes.add(_buildLoadMore(context, tab, st));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: nodes,
    );
  }

  /// Agrupa por mês preservando a ordem (lista já vem desc por data).
  List<({String label, List<Commission> items})> _groupByMonth(
      List<Commission> list, DateTime? Function(Commission) dateOf) {
    final fmt = DateFormat('MMMM yyyy', 'pt_BR');
    // Map literal já é insertion-ordered no Dart (preserva a ordem desc).
    final map = <String, List<Commission>>{};
    for (final c in list) {
      final d = dateOf(c)?.toLocal();
      final key = d == null ? 'Sem data' : fmt.format(d);
      map.putIfAbsent(key, () => []).add(c);
    }
    return map.entries
        .map((e) => (label: e.key, items: e.value))
        .toList(growable: false);
  }

  Widget _buildLoadMore(BuildContext context, CommissionTab tab, _TabState st) {
    final accent = _accentColor(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Center(
        child: st.loadingMore
            ? SizedBox(
                width: 22,
                height: 22,
                child:
                    CircularProgressIndicator(strokeWidth: 2.2, color: accent),
              )
            : OutlinedButton.icon(
                onPressed: () => _loadMore(tab),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  side: BorderSide(color: accent.withValues(alpha: 0.45)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(LucideIcons.chevronDown, size: 16),
                label: const Text('Carregar mais'),
              ),
      ),
    );
  }

  // ─── Estados ─────────────────────────────────────────────────────────────

  Widget _buildSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(
        5,
        (_) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 44, height: 44, borderRadius: 13),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonText(width: 96, height: 16, borderRadius: 999),
                    SizedBox(height: 9),
                    SkeletonText(width: double.infinity, height: 14),
                    SizedBox(height: 6),
                    SkeletonText(width: 150, height: 12),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const SkeletonText(width: 72, height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, CommissionTab tab) {
    final theme = Theme.of(context);
    final tone = _tabColor(context, tab);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hasSearch = _appliedSearch.trim().isNotEmpty;
    final (icon, title, body) = hasSearch
        ? (
            LucideIcons.searchX,
            'Nada encontrado',
            'Nenhuma comissão corresponde a "${_appliedSearch.trim()}".',
          )
        : switch (tab) {
            CommissionTab.pending => (
                LucideIcons.partyPopper,
                'Nada pendente',
                'Você não tem comissões aguardando recebimento.',
              ),
            CommissionTab.received => (
                LucideIcons.wallet,
                'Nenhuma recebida ainda',
                'Quando uma comissão for paga, ela aparece aqui.',
              ),
            CommissionTab.history => (
                LucideIcons.receipt,
                'Sem comissões',
                'Seu histórico de comissões aparecerá aqui.',
              ),
          };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 4),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [
                tone.withValues(alpha: 0.18),
                tone.withValues(alpha: 0.06),
              ]),
              border: Border.all(color: tone.withValues(alpha: 0.32)),
            ),
            child: Icon(icon, color: tone, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, CommissionTab tab, String message) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 4),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: danger.withValues(alpha: 0.12),
              border: Border.all(color: danger.withValues(alpha: 0.32)),
            ),
            child: Icon(LucideIcons.cloudOff, color: danger, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _loadTab(tab, refresh: true),
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }

  // ─── Detalhe ─────────────────────────────────────────────────────────────

  void _showDetail(BuildContext context, Commission c) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => _CommissionDetailSheet(commission: c),
    );
  }
}

// ─── Aba flush (ícone + rótulo + contagem + sublinhado) ──────────────────────

class _FlushTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color tone;
  final bool selected;
  final VoidCallback onTap;

  const _FlushTab({
    required this.icon,
    required this.label,
    required this.count,
    required this.tone,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected ? tone : ThemeHelpers.textSecondaryColor(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: tone.withValues(alpha: 0.12),
        highlightColor: tone.withValues(alpha: 0.06),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: fg),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      maxLines: 1,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: fg,
                        fontWeight:
                            selected ? FontWeight.w900 : FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: tone.withValues(alpha: selected ? 0.18 : 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: selected
                                ? tone
                                : ThemeHelpers.textSecondaryColor(context),
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              height: 2.5,
              decoration: BoxDecoration(
                color: selected ? tone : Colors.transparent,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Cabeçalho de sub-seção ──────────────────────────────────────────────────

class _PanelSubsectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  final int count;

  const _PanelSubsectionHeader({
    required this.label,
    required this.icon,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Row(
      children: [
        Icon(icon, size: 14, color: secondary),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: secondary,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
        if (count > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: ThemeHelpers.borderLightColor(context)
                  .withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w900,
                fontSize: 10,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Container(
              height: 1,
              color:
                  ThemeHelpers.borderLightColor(context).withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Bottom sheet de detalhe ─────────────────────────────────────────────────

class _CommissionDetailSheet extends StatelessWidget {
  const _CommissionDetailSheet({required this.commission});
  final Commission commission;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = commissionStatusColor(context, commission.status);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final fmt = DateFormat('dd/MM/yyyy', 'pt_BR');

    final title = commission.title.trim().isNotEmpty
        ? commission.title.trim()
        : (commission.clientName ?? 'Comissão');

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: tone.withValues(alpha: isDark ? 0.22 : 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.16),
            blurRadius: 28,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: secondary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        color: tone.withValues(alpha: isDark ? 0.18 : 0.1),
                        border: Border.all(color: tone.withValues(alpha: 0.3)),
                      ),
                      child: Icon(commissionTypeIcon(commission.type),
                          color: tone, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: ThemeHelpers.textColor(context),
                              letterSpacing: -0.3,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _miniPill(commission.status.label, tone, isDark),
                              _miniPill(
                                  commission.type.label, secondary, isDark),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: tone.withValues(alpha: isDark ? 0.12 : 0.07),
                    border: Border.all(color: tone.withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'VALOR LÍQUIDO',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: tone,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _money.format(commission.netValue),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: ThemeHelpers.textColor(context),
                          letterSpacing: -0.6,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _row(context, 'Valor base', _money.format(commission.baseValue)),
                _row(context, 'Percentual',
                    '${commission.percentage.toStringAsFixed(2).replaceAll('.', ',')}%'),
                _row(context, 'Comissão bruta',
                    _money.format(commission.commissionValue)),
                if (commission.taxValue > 0)
                  _row(context, 'Impostos',
                      '- ${_money.format(commission.taxValue)}'),
                const _Divider(),
                if (commission.propertyLabel != null)
                  _row(context, 'Imóvel', commission.propertyLabel!,
                      icon: LucideIcons.home),
                if (commission.propertyCode != null &&
                    commission.propertyCode!.isNotEmpty)
                  _row(context, 'Código', commission.propertyCode!),
                if (commission.clientName != null &&
                    commission.clientName!.trim().isNotEmpty)
                  _row(context, 'Cliente', commission.clientName!.trim(),
                      icon: LucideIcons.user),
                if (commission.expectedPaymentDate != null)
                  _row(context, 'Previsão de pagamento',
                      fmt.format(commission.expectedPaymentDate!.toLocal())),
                if (commission.paidAt != null)
                  _row(context, 'Pago em',
                      fmt.format(commission.paidAt!.toLocal())),
                if (commission.createdAt != null)
                  _row(context, 'Lançada em',
                      fmt.format(commission.createdAt!.toLocal())),
                if (commission.notes != null &&
                    commission.notes!.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    'OBSERVAÇÕES',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    commission.notes!.trim(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniPill(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: isDark ? 0.4 : 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontWeight: FontWeight.w800, fontSize: 11),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value,
      {IconData? icon}) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: secondary),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        height: 1,
        color: ThemeHelpers.borderLightColor(context),
      ),
    );
  }
}

class _DeniedView extends StatelessWidget {
  const _DeniedView();
  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.lock, size: 38, color: secondary),
            const SizedBox(height: 12),
            Text(
              'Você não tem acesso às comissões.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Solicite ao administrador a permissão "commission:view".',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
