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

/// Tela **Suporte / Meus tickets** — personalidade própria: lista SÓBRIA com
/// **status strip** no topo (faixa fina segmentada, proporcional à
/// distribuição por status, com legenda compacta tocável) no lugar de hero
/// com KPIs. As linhas de ticket usam indicador lateral fino de status e
/// tipografia protagonista. Espelha a `TicketsPage` do imobx-front (visão do
/// solicitante): abrir ticket, acompanhar respostas e manter o histórico.
class TicketsPage extends StatefulWidget {
  const TicketsPage({super.key});

  @override
  State<TicketsPage> createState() => _TicketsPageState();
}

class _TicketsPageState extends State<TicketsPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 12;
  static const double _kPagePadBottom = 108;

  static const _tabs = [
    TicketTab.active,
    TicketTab.waiting,
    TicketTab.finished,
  ];

  /// Ordem fixa dos segmentos da faixa de status (ciclo de vida do ticket).
  static const List<TicketStatus> _stripOrder = [
    TicketStatus.open,
    TicketStatus.inProgress,
    TicketStatus.waiting,
    TicketStatus.resolved,
    TicketStatus.closed,
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

  /// Contagem global por status (sem recorte de busca) — alimenta a faixa.
  Map<TicketStatus, int> get _statusCounts {
    final map = <TicketStatus, int>{};
    for (final t in _tickets) {
      map[t.status] = (map[t.status] ?? 0) + 1;
    }
    return map;
  }

  /// Aba correspondente a um status — a faixa filtra através das abas que já
  /// existem (não inventa filtro novo).
  TicketTab _tabForStatus(TicketStatus status) {
    switch (status) {
      case TicketStatus.open:
      case TicketStatus.inProgress:
        return TicketTab.active;
      case TicketStatus.waiting:
        return TicketTab.waiting;
      case TicketStatus.resolved:
      case TicketStatus.closed:
      case TicketStatus.unknown:
        return TicketTab.finished;
    }
  }

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
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(
                top: _kPagePadTop,
                bottom: _kPagePadBottom,
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _kPagePadH),
                  child: _buildStatusStrip(context),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _kPagePadH),
                  child: _buildSearchField(context),
                ),
                const SizedBox(height: 12),
                _buildTabsRail(context),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    _kPagePadH,
                    10,
                    _kPagePadH,
                    0,
                  ),
                  child: _buildActivePanel(context),
                ),
              ],
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

  // ─── Status strip ────────────────────────────────────────────────────────

  /// Assinatura da tela: título sóbrio + faixa fina segmentada com a
  /// distribuição por status (cores semânticas) e legenda compacta. Cada
  /// segmento/legenda é tocável e leva à aba correspondente.
  Widget _buildStatusStrip(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    if (_loading && !_loadedOnce) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              SkeletonText(width: 118, height: 17),
              Spacer(),
              SkeletonText(width: 62, height: 11),
            ],
          ),
          const SizedBox(height: 12),
          const SkeletonBox(
            width: double.infinity,
            height: 10,
            borderRadius: 999,
          ),
          const SizedBox(height: 10),
          Row(
            children: const [
              SkeletonText(width: 74, height: 11, borderRadius: 999),
              SizedBox(width: 14),
              SkeletonText(width: 92, height: 11, borderRadius: 999),
              SizedBox(width: 14),
              SkeletonText(width: 80, height: 11, borderRadius: 999),
            ],
          ),
        ],
      );
    }

    final counts = _statusCounts;
    final total = _tickets.length;
    final visible = _stripOrder
        .where((s) => (counts[s] ?? 0) > 0)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Meus tickets',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: textColor,
                letterSpacing: -0.4,
                height: 1.0,
              ),
            ),
            const Spacer(),
            Text(
              total == 0
                  ? (_error != null ? '—' : 'nenhum registro')
                  : total == 1
                  ? '1 no total'
                  : '$total no total',
              style: theme.textTheme.labelSmall?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w700,
                fontSize: 11,
                height: 1.0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (total == 0)
          Container(
            height: 10,
            decoration: BoxDecoration(
              color: secondary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
            ),
          )
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  for (var i = 0; i < visible.length; i++)
                    Expanded(
                      flex: counts[visible[i]]!,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _selectTab(_tabForStatus(visible[i])),
                        child: Container(
                          margin: EdgeInsets.only(left: i == 0 ? 0 : 2),
                          color: ticketStatusColor(context, visible[i]),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 10),
        if (total == 0)
          Text(
            _error != null
                ? 'Não foi possível carregar a distribuição por status.'
                : 'Abra sua primeira solicitação para a equipe de desenvolvimento.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondary,
              height: 1.35,
            ),
          )
        else
          Wrap(
            spacing: 14,
            runSpacing: 7,
            children: [
              for (final status in visible)
                _StripLegendItem(
                  count: counts[status]!,
                  label: status.label,
                  tone: ticketStatusColor(context, status),
                  onTap: () => _selectTab(_tabForStatus(status)),
                ),
            ],
          ),
      ],
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

  String _tabHint(TicketTab tab) {
    switch (tab) {
      case TicketTab.active:
        return 'Abertos e em andamento com a equipe de desenvolvimento.';
      case TicketTab.waiting:
        return 'O suporte respondeu e está esperando o seu retorno.';
      case TicketTab.finished:
        return 'Histórico do que já foi resolvido ou fechado.';
    }
  }

  // ─── Painel ativo ────────────────────────────────────────────────────────

  Widget _buildActivePanel(BuildContext context) {
    final theme = Theme.of(context);
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
            // Contexto discreto da aba — uma linha, sem eyebrow nem ícone.
            Text(
              _tabHint(_activeTab),
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 4),
            child,
          ],
        )
        .animate(key: ValueKey('panel-${_activeTab.name}'))
        .fadeIn(duration: 240.ms);
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

  /// Skeleton fiel à linha nova: barra lateral fina + título protagonista +
  /// linha de status + resumo + rodapé, com a data à direita.
  Widget _buildSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(
        6,
        (_) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBox(width: 3, height: 76, borderRadius: 999),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonText(width: double.infinity, height: 15),
                    SizedBox(height: 7),
                    SkeletonText(width: 150, height: 11, borderRadius: 999),
                    SizedBox(height: 9),
                    SkeletonText(width: double.infinity, height: 12),
                    SizedBox(height: 6),
                    SkeletonText(width: 180, height: 11),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const SkeletonText(width: 44, height: 10),
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

// ─── Legenda da faixa de status ──────────────────────────────────────────────

/// Item compacto da legenda: quadradinho na cor semântica + contagem + rótulo.
/// Tocar leva à aba que contém aquele status.
class _StripLegendItem extends StatelessWidget {
  final int count;
  final String label;
  final Color tone;
  final VoidCallback onTap;

  const _StripLegendItem({
    required this.count,
    required this.label,
    required this.tone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: tone,
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: ThemeHelpers.textColor(context),
                height: 1.0,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: secondary,
                height: 1.0,
              ),
            ),
          ],
        ),
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
