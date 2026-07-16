import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/ticket_models.dart';
import '../services/ticket_service.dart';
import '../widgets/ticket_card.dart';

// Rotas do domínio (mesmos nomes registrados no AppRoutes central).
const String _kTicketCreateRoute = '/tickets/new';
const String _kTicketDetailRoute = '/tickets/detail';

// Permissões (strings exatas do web — `ticket:*` não existe em AppPermissions).
const String _kPermTicketCreate = 'ticket:create';
const String _kPermTicketView = 'ticket:view';

String _normalize(String value) {
  const from = 'áàãâäéèêëíìîïóòõôöúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  var out = value.toLowerCase();
  for (var i = 0; i < from.length; i++) {
    out = out.replaceAll(from[i], to[i]);
  }
  return out;
}

/// Tela **Suporte / Meus tickets** — mesmo DNA da tela de Comissões: hero
/// editorial com KPIs, busca flush, abas flush com sublinhado e contagem,
/// lista em linhas flush. Espelha a `TicketsPage` do imobx-front (visão do
/// solicitante): abrir ticket, acompanhar respostas e manter o histórico.
class TicketsPage extends StatefulWidget {
  const TicketsPage({super.key});

  @override
  State<TicketsPage> createState() => _TicketsPageState();
}

class _TicketsPageState extends State<TicketsPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 108;
  static const double _kSectionGap = 12;

  static const _tabs = [
    TicketTab.active,
    TicketTab.waiting,
    TicketTab.finished,
  ];

  TicketTab _activeTab = TicketTab.active;
  List<Ticket> _tickets = const [];
  bool _loading = true;
  bool _loadedOnce = false;
  String? _error;

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _appliedSearch = '';
  bool _searchFocused = false;

  bool get _canView => ModuleAccessService.instance.hasAnyPermission(const [
    _kPermTicketCreate,
    _kPermTicketView,
  ]);

  bool get _canCreate =>
      ModuleAccessService.instance.hasPermission(_kPermTicketCreate);

  @override
  void initState() {
    super.initState();
    _load();
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

  Color _tabColor(BuildContext context, TicketTab tab) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (tab) {
      case TicketTab.active:
        return isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
      case TicketTab.waiting:
        return isDark
            ? AppColors.status.warningDarkMode
            : AppColors.status.warning;
      case TicketTab.finished:
        return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    }
  }

  // ─── Dados ───────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // Paridade web: carrega tudo de uma vez (limit 100) e recorta no cliente
    // por aba/busca — o volume de tickets por empresa é pequeno.
    final res = await TicketService.instance.list(limit: 100);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadedOnce = true;
      if (res.success && res.data != null) {
        _tickets = res.data!.items;
      } else {
        _error = res.message ?? 'Erro ao carregar os tickets';
      }
    });
  }

  List<Ticket> get _searched {
    final term = _normalize(_appliedSearch.trim());
    if (term.isEmpty) return _tickets;
    return _tickets.where((t) {
      return _normalize(t.title).contains(term) ||
          _normalize(t.description).contains(term) ||
          _normalize(t.category.label).contains(term);
    }).toList();
  }

  List<Ticket> _itemsFor(TicketTab tab) {
    switch (tab) {
      case TicketTab.active:
        return _searched.where((t) => t.status.isActive).toList();
      case TicketTab.waiting:
        return _searched
            .where((t) => t.status == TicketStatus.waiting)
            .toList();
      case TicketTab.finished:
        return _searched.where((t) => t.status.isFinished).toList();
    }
  }

  int get _activeCount => _tickets.where((t) => t.status.isActive).length;
  int get _waitingCount =>
      _tickets.where((t) => t.status == TicketStatus.waiting).length;
  int get _resolvedCount =>
      _tickets.where((t) => t.status == TicketStatus.resolved).length;
  int get _urgentOpenCount => _tickets
      .where((t) => t.priority == TicketPriority.urgent && !t.status.isFinished)
      .length;

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final v = value.trim();
      if (v == _appliedSearch) return;
      setState(() => _appliedSearch = v);
    });
  }

  void _selectTab(TicketTab tab) {
    if (tab == _activeTab) return;
    setState(() => _activeTab = tab);
  }

  Future<void> _openCreate() async {
    await Navigator.of(context).pushNamed(_kTicketCreateRoute);
    if (mounted) _load();
  }

  Future<void> _openDetail(Ticket ticket) async {
    await Navigator.of(
      context,
    ).pushNamed(_kTicketDetailRoute, arguments: ticket.id);
    if (mounted) _load();
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canView) {
      return const AppScaffold(
        title: 'Suporte',
        showBottomNavigation: false,
        body: _DeniedView(),
      );
    }
    return AppScaffold(
      title: 'Suporte',
      showBottomNavigation: false,
      body: Stack(
        children: [
          RefreshIndicator(
            color: _accentColor(context),
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
                          _kPagePadH,
                          _kPagePadTop,
                          _kPagePadH,
                          0,
                        ),
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
                          _kPagePadH,
                          _kSectionGap,
                          _kPagePadH,
                          _kPagePadBottom,
                        ),
                        child: _buildActivePanel(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_canCreate) _buildCreateButton(context),
        ],
      ),
    );
  }

  /// Botão flutuante "Abrir ticket" — ação principal da tela, na cor da marca.
  Widget _buildCreateButton(BuildContext context) {
    final accent = _accentColor(context);
    return Positioned(
      right: 16,
      bottom: 24,
      child: Material(
        color: accent,
        borderRadius: BorderRadius.circular(16),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _openCreate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: ThemeHelpers.cardShadow(context),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.plus, size: 18, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  'Abrir ticket',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
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
    final emerald = isDark
        ? AppColors.status.greenDarkMode
        : AppColors.status.green;
    final amber = isDark
        ? AppColors.status.warningDarkMode
        : AppColors.status.warning;
    final blue = isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    final danger = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;

    final total = _tickets.length;
    final hasWaiting = _waitingCount > 0;
    final hasActive = _activeCount > 0;
    final dot = hasWaiting
        ? amber
        : hasActive
        ? blue
        : emerald;
    final subtitle = total == 0
        ? 'Abra solicitações para a equipe de desenvolvimento e acompanhe tudo por aqui.'
        : hasWaiting
        ? '$_waitingCount ticket${_waitingCount == 1 ? '' : 's'} aguardando sua resposta.'
        : hasActive
        ? '$_activeCount em atendimento — você recebe as respostas aqui.'
        : 'Nenhum ticket em aberto no momento.';

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
                'SUPORTE · MEUS TICKETS',
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
                  total == 1 ? 'ticket' : 'tickets',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (_urgentOpenCount > 0) ...[
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: danger.withValues(alpha: isDark ? 0.16 : 0.1),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: danger.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.zap, size: 11, color: danger),
                        const SizedBox(width: 4),
                        Text(
                          '$_urgentOpenCount urgente${_urgentOpenCount == 1 ? '' : 's'}',
                          style: TextStyle(
                            color: danger,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
          _buildKpiStrip(context, blue, amber, emerald),
        ],
      ),
    );
  }

  Widget _buildKpiStrip(
    BuildContext context,
    Color blue,
    Color amber,
    Color emerald,
  ) {
    final divider = ThemeHelpers.borderColor(context).withValues(alpha: 0.45);
    final blocks = <Widget>[
      _heroKpiBlock(
        context,
        LucideIcons.wrench,
        'ATIVOS',
        '$_activeCount',
        'em atendimento',
        blue,
      ),
      _heroKpiBlock(
        context,
        LucideIcons.clock3,
        'AGUARDANDO VOCÊ',
        '$_waitingCount',
        'respostas pendentes',
        amber,
      ),
      _heroKpiBlock(
        context,
        LucideIcons.circleCheckBig,
        'RESOLVIDOS',
        '$_resolvedCount',
        'para confirmar',
        emerald,
      ),
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

  Widget _heroKpiBlock(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    String sub,
    Color tone,
  ) {
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
              !_loadedOnce && _loading ? '—' : value,
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
            Icon(
              LucideIcons.search,
              size: 18,
              color: showAccent ? accent : secondary,
            ),
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
                  hintText: 'Buscar por título ou descrição…',
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

  // ─── Abas flush ──────────────────────────────────────────────────────────

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
                count: _itemsFor(tab).length,
                tone: _tabColor(context, tab),
                selected: _activeTab == tab,
                onTap: () => _selectTab(tab),
              ),
            ),
        ],
      ),
    );
  }

  IconData _tabIcon(TicketTab tab) {
    switch (tab) {
      case TicketTab.active:
        return LucideIcons.wrench;
      case TicketTab.waiting:
        return LucideIcons.clock3;
      case TicketTab.finished:
        return LucideIcons.circleCheckBig;
    }
  }

  String _tabLabel(TicketTab tab) {
    switch (tab) {
      case TicketTab.active:
        return 'Ativos';
      case TicketTab.waiting:
        return 'Aguardando';
      case TicketTab.finished:
        return 'Encerrados';
    }
  }

  // ─── Painel ativo ────────────────────────────────────────────────────────

  ({IconData icon, String eyebrow, String title, String hint}) _panelMeta(
    TicketTab tab,
  ) {
    switch (tab) {
      case TicketTab.active:
        return (
          icon: LucideIcons.wrench,
          eyebrow: 'EM ATENDIMENTO',
          title: 'Tickets ativos',
          hint: 'Abertos e em andamento com a equipe de desenvolvimento.',
        );
      case TicketTab.waiting:
        return (
          icon: LucideIcons.clock3,
          eyebrow: 'SUA VEZ',
          title: 'Aguardando sua resposta',
          hint: 'O suporte respondeu e está esperando o seu retorno.',
        );
      case TicketTab.finished:
        return (
          icon: LucideIcons.circleCheckBig,
          eyebrow: 'ENCERRADOS',
          title: 'Resolvidos e fechados',
          hint: 'Histórico do que já foi atendido, do mais recente ao antigo.',
        );
    }
  }

  Widget _buildActivePanel(BuildContext context) {
    final items = _itemsFor(_activeTab);
    Widget child;
    if (_loading && !_loadedOnce) {
      child = _buildSkeleton();
    } else if (_error != null && _tickets.isEmpty) {
      child = _buildError(context, _error!);
    } else if (items.isEmpty) {
      child = _buildEmpty(context, _activeTab);
    } else {
      child = _buildList(context, items);
    }

    return Column(
          key: ValueKey('panel-${_activeTab.name}'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPanelHeader(context, _activeTab),
            const SizedBox(height: 14),
            child,
          ],
        )
        .animate(key: ValueKey('panel-${_activeTab.name}'))
        .fadeIn(duration: 240.ms);
  }

  Widget _buildPanelHeader(BuildContext context, TicketTab tab) {
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

  Widget _buildList(BuildContext context, List<Ticket> items) {
    var animIndex = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final ticket in items)
          TicketCard(ticket: ticket, onTap: () => _openDetail(ticket))
              .animate(key: ValueKey('t-${ticket.id}'))
              .fadeIn(
                delay: Duration(milliseconds: 30 * (animIndex++).clamp(0, 12)),
                duration: 220.ms,
              ),
      ],
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
                    SkeletonText(width: 170, height: 12),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const SkeletonText(width: 52, height: 14),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, TicketTab tab) {
    final theme = Theme.of(context);
    final tone = _tabColor(context, tab);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hasSearch = _appliedSearch.trim().isNotEmpty;
    final (icon, title, body) = hasSearch
        ? (
            LucideIcons.searchX,
            'Nada encontrado',
            'Nenhum ticket corresponde a "${_appliedSearch.trim()}".',
          )
        : switch (tab) {
            TicketTab.active => (
              LucideIcons.inbox,
              'Nenhum ticket ativo',
              'Precisa de ajuda? Toque em "Abrir ticket" para falar com a equipe.',
            ),
            TicketTab.waiting => (
              LucideIcons.partyPopper,
              'Nada esperando por você',
              'Quando o suporte responder e precisar do seu retorno, aparece aqui.',
            ),
            TicketTab.finished => (
              LucideIcons.archive,
              'Nenhum ticket encerrado',
              'Os tickets resolvidos e fechados ficam guardados aqui.',
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
              gradient: LinearGradient(
                colors: [
                  tone.withValues(alpha: 0.18),
                  tone.withValues(alpha: 0.06),
                ],
              ),
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

  Widget _buildError(BuildContext context, String message) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;
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
            onPressed: _load,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
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
                        fontWeight: selected
                            ? FontWeight.w900
                            : FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
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
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(3),
                ),
              ),
            ),
          ],
        ),
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
              'Você não tem acesso ao suporte por tickets.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Peça ao administrador para liberar a abertura de tickets no seu perfil.',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
