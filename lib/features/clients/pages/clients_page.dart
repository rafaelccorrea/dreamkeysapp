import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/shell_visual_tokens.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/utils/masks.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../../matches/models/match_model.dart';
import '../../matches/services/match_service.dart';
import '../models/client_model.dart';
import '../services/client_service.dart';
import '../widgets/async_excel_import_modal.dart';
import '../widgets/client_filters_drawer.dart';
import '../widgets/transfer_client_modal.dart';

final _compactIntFormatter = NumberFormat.decimalPattern('pt_BR');

/// Métricas agregadas a partir da listagem carregada (página atual).
class _ListedClientMetrics {
  const _ListedClientMetrics({
    required this.active,
    required this.inactive,
    required this.contacted,
    required this.interested,
    required this.closed,
    required this.buyers,
    required this.sellers,
    required this.renters,
    required this.lessors,
    required this.investors,
    required this.general,
    required this.withSpouse,
    required this.withWhatsapp,
    required this.mcmv,
  });

  final int active;
  final int inactive;
  final int contacted;
  final int interested;
  final int closed;
  final int buyers;
  final int sellers;
  final int renters;
  final int lessors;
  final int investors;
  final int general;
  final int withSpouse;
  final int withWhatsapp;
  final int mcmv;
}

/// Página de listagem de clientes.
class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key});

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  static const double _kHeaderPadH = 20;
  static const double _kHeaderPadVTop = 10;

  final ClientService _clientService = ClientService.instance;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _isLoadingMore = false;
  List<Client> _clients = [];
  int _currentPage = 1;
  int _totalPages = 1;
  int _total = 0;
  String? _errorMessage;
  ClientSearchFilters? _filters;
  String _searchQuery = '';
  ClientStatistics? _statistics;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadClients(refresh: true);
    _loadStatistics();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _currentPage < _totalPages && !_isLoading) {
        _loadMoreClients();
      }
    }
  }

  // ───────────────────────── Networking ─────────────────────────

  Future<void> _loadClients({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _currentPage = 1;
        _clients.clear();
      });
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final filters =
          (_filters ?? ClientSearchFilters()).copyWith(
            search: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
            page: _currentPage,
            limit: 50,
          );

      final response = await _clientService.getClients(filters: filters);

      if (!mounted) return;

      if (response.success && response.data != null) {
        final pagination = response.data!.pagination;
        setState(() {
          if (refresh) {
            _clients = response.data!.data;
          } else {
            _clients.addAll(response.data!.data);
          }
          _totalPages = pagination?.totalPages ?? 1;
          _total = pagination?.total ?? _clients.length;
          _isLoading = false;
          _isLoadingMore = false;
        });
      } else {
        setState(() {
          _errorMessage = response.message ?? 'Erro ao carregar clientes';
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Erro ao conectar com o servidor';
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _loadMoreClients() async {
    if (_isLoadingMore || _currentPage >= _totalPages) return;
    setState(() {
      _isLoadingMore = true;
      _currentPage++;
    });
    await _loadClients();
  }

  Future<void> _loadStatistics() async {
    try {
      final response = await _clientService.getStatistics(filters: _filters);
      if (!mounted) return;
      if (response.success && response.data != null) {
        setState(() => _statistics = response.data);
      }
    } catch (_) {
      // Estatísticas são opcionais — silenciamos erro.
    }
  }

  Future<void> _handleSearch(String query) async {
    setState(() {
      _searchQuery = query;
    });
    await _loadClients(refresh: true);
  }

  // ───────────────────────── Build ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Clientes',
      currentBottomNavIndex: 3,
      showBottomNavigation: true,
      actions: [_buildOverflowMenu(context)],
      body: _isLoading && _clients.isEmpty
          ? Column(
              children: [
                _buildClientsHeader(context),
                Expanded(child: _buildSkeleton(context)),
              ],
            )
          : _errorMessage != null && _clients.isEmpty
              ? Column(
                  children: [
                    _buildClientsHeader(context),
                    Expanded(child: _buildErrorState(context)),
                  ],
                )
              : _clients.isEmpty
                  ? Column(
                      children: [
                        _buildClientsHeader(context),
                        Expanded(child: _buildEmptyState(context)),
                      ],
                    )
                  : _buildScrollableViewport(context),
    );
  }

  // ───────────────────────── Overflow Menu ─────────────────────────

  Widget _buildOverflowMenu(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final pm = AppTheme.styledPopupMenu(brightness);
    final base = Theme.of(context);

    return Theme(
      data: base.copyWith(
        popupMenuTheme: pm,
        splashColor: AppColors.primary.primary.withValues(alpha: 0.10),
        highlightColor: AppColors.primary.primary.withValues(alpha: 0.05),
      ),
      child: PopupMenuButton<String>(
        clipBehavior: Clip.antiAlias,
        constraints: const BoxConstraints(minHeight: 40, minWidth: 44),
        color: pm.color,
        surfaceTintColor: pm.surfaceTintColor,
        elevation: pm.elevation ?? 20,
        shadowColor: pm.shadowColor,
        shape: pm.shape,
        offset: const Offset(0, 8),
        icon: Icon(
          Icons.more_vert,
          color: ThemeHelpers.textColor(context).withValues(alpha: 0.88),
        ),
        tooltip: 'Mais opções',
        onSelected: (value) {
          switch (value) {
            case 'new':
              _navigateToCreate();
              break;
            case 'search':
              _showSearchSheet(context);
              break;
            case 'filters':
              _openFilters(context);
              break;
            case 'import':
              _showImportModal();
              break;
            case 'export':
              _exportClients();
              break;
          }
        },
        itemBuilder: (menuCtx) {
          final pmt = Theme.of(menuCtx).popupMenuTheme;
          final labelStyle = pmt.textStyle ?? Theme.of(menuCtx).textTheme.bodyMedium;
          final iconColor = pmt.iconColor ?? ThemeHelpers.textSecondaryColor(menuCtx);
          return [
            PopupMenuItem(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              value: 'new',
              child: Text.rich(
                TextSpan(children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(Icons.person_add_alt_1, size: 20, color: iconColor),
                  ),
                  const WidgetSpan(child: SizedBox(width: 10)),
                  TextSpan(text: 'Novo cliente', style: labelStyle),
                ]),
              ),
            ),
            PopupMenuItem(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              value: 'search',
              child: Text.rich(
                TextSpan(children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(Icons.search, size: 20, color: iconColor),
                  ),
                  const WidgetSpan(child: SizedBox(width: 10)),
                  TextSpan(text: 'Buscar', style: labelStyle),
                ]),
              ),
            ),
            PopupMenuItem(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              value: 'filters',
              child: Text.rich(
                TextSpan(children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(Icons.filter_list, size: 20, color: iconColor),
                        if (_hasActiveFilters())
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const WidgetSpan(child: SizedBox(width: 10)),
                  TextSpan(text: 'Filtros', style: labelStyle),
                ]),
              ),
            ),
            const PopupMenuDivider(height: 10, thickness: 1),
            PopupMenuItem(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              value: 'import',
              child: Text.rich(
                TextSpan(children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(Icons.upload_file, size: 20, color: iconColor),
                  ),
                  const WidgetSpan(child: SizedBox(width: 10)),
                  TextSpan(text: 'Importar Excel', style: labelStyle),
                ]),
              ),
            ),
            PopupMenuItem(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              value: 'export',
              child: Text.rich(
                TextSpan(children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(Icons.download_outlined, size: 20, color: iconColor),
                  ),
                  const WidgetSpan(child: SizedBox(width: 10)),
                  TextSpan(text: 'Exportar dados', style: labelStyle),
                ]),
              ),
            ),
          ];
        },
      ),
    );
  }

  // ───────────────────────── Hero Header ─────────────────────────

  Color _accentColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFFF4D67)
        : AppColors.primary.primary;
  }

  Widget _buildClientsHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accentColor(context);
    final hasFilters = _hasActiveFilters();
    final hasSearch = _searchQuery.trim().isNotEmpty;
    final gatedGlobal = !hasFilters && !hasSearch;

    final subtitleParts = [
      DateFormat("'Atualização' HH:mm · d MMMM", 'pt_BR').format(DateTime.now()),
      if (_totalPages > 1) 'página $_currentPage de $_totalPages',
      if (_statistics != null && gatedGlobal) 'KPIs sincronizados com o CRM',
      if (hasSearch)
        'busca ativa para “${_searchQuery.length > 32 ? '${_searchQuery.substring(0, 32)}…' : _searchQuery}”'
      else if (hasFilters)
        'filtro granular ativo'
    ].where((s) => s.trim().isNotEmpty).join(' · ');

    final headline = hasSearch ? 'Radar de clientes' : 'Hub de relacionamento';

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final compact = w < 360;
        final narrow = w < 332;
        final spread = w >= 480;
        final actionsTop = w >= 640;
        final pillsBesideInsight = w >= 520;

        final padH = narrow ? 12.0 : (compact ? 16.0 : _kHeaderPadH);
        final statSep = compact ? 6.0 : 8.0;
        final innerW = (w - padH * 2).clamp(0.0, double.infinity).toDouble();
        final kpiCols = innerW >= 360 ? 4 : 2;
        final statH = compact ? 72.0 : (w >= 520 ? 78.0 : 74.0);

        final mainTitles = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'GESTÃO DE CLIENTES',
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent,
                letterSpacing: compact ? 1.15 : 2.35,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              headline,
              style: (compact
                      ? theme.textTheme.titleMedium
                      : theme.textTheme.titleLarge)
                  ?.copyWith(
                fontWeight: FontWeight.w900,
                height: 1.02,
                color: ThemeHelpers.textColor(context),
              ),
            ),
          ],
        );

        final dateLineWidget = Text(
          subtitleParts,
          style: theme.textTheme.bodySmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: spread ? TextAlign.right : TextAlign.start,
        );

        final quickActions = <Widget>[
          _buildQuickActionButton(
            context,
            icon: Icons.person_add_alt_1,
            label: 'Novo cliente',
            isPrimary: true,
            onPressed: _navigateToCreate,
          ),
          _buildQuickActionButton(
            context,
            icon: Icons.tune_rounded,
            label: hasFilters ? 'Filtros ativos' : 'Filtros',
            highlight: hasFilters,
            onPressed: () => _openFilters(context),
          ),
        ];

        Widget pillRow() => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _heroContextPills(
                context,
                gatedGlobal: gatedGlobal,
                compact: compact,
              ),
            );

        Widget insightBlock() => _buildHeroInsight(
              context,
              gatedGlobal: gatedGlobal,
              hasSearch: hasSearch,
              hasFilters: hasFilters,
            );

        Widget actionsBar() => Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: quickActions,
            );

        Widget heroTop;
        if (!spread) {
          heroTop = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _heroLeadingIcon(context),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        mainTitles,
                        const SizedBox(height: 6),
                        dateLineWidget,
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              pillRow(),
              const SizedBox(height: 10),
              insightBlock(),
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: actionsBar()),
            ],
          );
        } else {
          heroTop = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _heroLeadingIcon(context),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 52, child: mainTitles),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 48,
                          child: Align(
                            alignment: Alignment.topRight,
                            child: dateLineWidget,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (actionsTop) ...[
                    const SizedBox(width: 12),
                    actionsBar(),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              if (pillsBesideInsight)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 42, child: pillRow()),
                    const SizedBox(width: 12),
                    Expanded(flex: 58, child: insightBlock()),
                  ],
                )
              else ...[
                pillRow(),
                const SizedBox(height: 10),
                insightBlock(),
              ],
              if (!actionsTop) ...[
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: actionsBar()),
              ],
            ],
          );
        }

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      AppColors.background.backgroundDarkMode,
                      AppColors.background.backgroundSecondaryDarkMode,
                    ]
                  : const [Colors.transparent, Colors.transparent],
            ),
            border: Border(
              bottom: BorderSide(
                color: ThemeHelpers.borderColor(context).withValues(alpha: 0.65),
              ),
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ..._heroAmbientGlows(context),
              Padding(
                padding: EdgeInsets.fromLTRB(padH, _kHeaderPadVTop, padH, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    heroTop,
                    SizedBox(height: compact ? 8 : 10),
                    _buildHeroKpiStripe(
                      _heroKpiTiles(context, th: statH, gatedGlobal: gatedGlobal),
                      statSep,
                      kpiCols,
                    ),
                    if (hasFilters || hasSearch) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (hasSearch)
                            _buildActiveContextChip(
                              context,
                              Icons.search_rounded,
                              _searchQuery,
                              onClear: () {
                                _searchController.clear();
                                _handleSearch('');
                              },
                            ),
                          if (hasFilters)
                            _buildActiveContextChip(
                              context,
                              Icons.tune_rounded,
                              'Filtros aplicados',
                              onClear: () {
                                setState(() => _filters = null);
                                _loadClients(refresh: true);
                                _loadStatistics();
                              },
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _heroAmbientGlows(BuildContext context) {
    final accent = _accentColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cool = isDark ? const Color(0xFF6366F1) : const Color(0xFF818CF8);
    return [
      Positioned(
        top: -56,
        right: -40,
        child: IgnorePointer(
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  accent.withValues(alpha: isDark ? 0.24 : 0.14),
                  accent.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ),
      Positioned(
        top: 120,
        left: -90,
        child: IgnorePointer(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  cool.withValues(alpha: isDark ? 0.16 : 0.09),
                  cool.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _heroLeadingIcon(BuildContext context) {
    final accent = _accentColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(colors: [accent, const Color(0xFF7C3AED)]),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? accent.withValues(alpha: 0.35)
                : Colors.black.withValues(alpha: 0.14),
            blurRadius: isDark ? 14 : 10,
            offset: Offset(0, isDark ? 8 : 5),
          ),
        ],
      ),
      child: const Icon(Icons.diversity_3_outlined, color: Colors.white, size: 22),
    );
  }

  Widget _buildQuickActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool isPrimary = false,
    bool highlight = false,
  }) {
    final accent = _accentColor(context);
    final theme = Theme.of(context);
    final style = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w800,
      fontSize: 12.75,
      height: 1.15,
      letterSpacing: -0.1,
      color: isPrimary
          ? Colors.white
          : highlight
              ? accent
              : ThemeHelpers.textColor(context),
    );

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isPrimary
              ? accent
              : ShellVisualTokens.dashboardGlassFill(context),
          border: Border.all(
            color: isPrimary
                ? accent
                : highlight
                    ? accent.withValues(alpha: 0.55)
                    : ShellVisualTokens.dashboardGlassBorder(context),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: isPrimary ? Colors.white : accent),
            const SizedBox(width: 8),
            Text(label, style: style),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroPill(BuildContext context, IconData icon, String label) {
    final accent = _accentColor(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderCol = ThemeHelpers.borderColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isDark
            ? accent.withValues(alpha: 0.07)
            : ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark
              ? accent.withValues(alpha: 0.14)
              : borderCol.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: accent),
          const SizedBox(width: 7),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _heroContextPills(
    BuildContext context, {
    required bool gatedGlobal,
    required bool compact,
  }) {
    final pageChip = _totalPages > 1
        ? 'Pág. $_currentPage · $_totalPages'
        : '${_compactIntFormatter.format(_clients.length)} neste painel';
    return [
      _buildHeroPill(
        context,
        gatedGlobal ? Icons.diversity_2_outlined : Icons.filter_alt_outlined,
        gatedGlobal ? 'Carteira CRM' : 'Contexto filtrado',
      ),
      _buildHeroPill(
        context,
        Icons.visibility_outlined,
        compact && pageChip.length > 18 ? '${_clients.length} itens' : pageChip,
      ),
    ];
  }

  Widget _buildHeroInsight(
    BuildContext context, {
    required bool gatedGlobal,
    required bool hasSearch,
    required bool hasFilters,
  }) {
    final theme = Theme.of(context);
    final stats = _statistics;
    final m = _listedMetrics();

    late final IconData insightIcon;
    late final Color iconBg;
    late final Color iconFg;
    late final String body;

    if (hasSearch) {
      insightIcon = Icons.manage_search_rounded;
      iconBg = ThemeHelpers.borderColor(context).withValues(alpha: 0.20);
      iconFg = ThemeHelpers.textSecondaryColor(context);
      body =
          'Busca textual combinada com os filtros atuais — confira os KPIs para validar o perfil dos resultados.';
    } else if (hasFilters) {
      insightIcon = Icons.tune_rounded;
      iconBg = _accentColor(context).withValues(alpha: 0.14);
      iconFg = _accentColor(context);
      body =
          'Métricas espelham o filtro granular. Limpe o chip de contexto para voltar à carteira completa.';
    } else if (stats != null && gatedGlobal) {
      insightIcon = Icons.auto_graph_rounded;
      iconFg = AppColors.status.success;
      iconBg = AppColors.status.success.withValues(alpha: 0.14);
      body =
          '${_compactIntFormatter.format(stats.totalClients)} clientes no CRM · '
          '${_compactIntFormatter.format(stats.activeClients)} ativos · '
          '${stats.buyers} compradores · ${stats.sellers} vendedores.';
    } else {
      insightIcon = Icons.layers_outlined;
      iconFg = ThemeHelpers.textSecondaryColor(context);
      iconBg = ThemeHelpers.borderColor(context).withValues(alpha: 0.18);
      body = '$_total registros · ${m.active} ativos · '
          '${m.withWhatsapp} com WhatsApp · ${m.withSpouse} com cônjuge.';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(shape: BoxShape.circle, color: iconBg),
            child: Icon(insightIcon, color: iconFg, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'INSIGHT CARTEIRA',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.65,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w700,
                    height: 1.32,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── KPI Stripe ─────────────────────────

  Widget _buildHeroKpiStripe(List<Widget> tiles, double gap, int columns) {
    assert(tiles.length == 4);
    Widget row2(Widget a, Widget b) => Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: a),
            SizedBox(width: gap),
            Expanded(child: b),
          ],
        );
    if (columns >= 4) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: tiles[0]),
          SizedBox(width: gap),
          Expanded(child: tiles[1]),
          SizedBox(width: gap),
          Expanded(child: tiles[2]),
          SizedBox(width: gap),
          Expanded(child: tiles[3]),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row2(tiles[0], tiles[1]),
        SizedBox(height: gap),
        row2(tiles[2], tiles[3]),
      ],
    );
  }

  List<Widget> _heroKpiTiles(
    BuildContext context, {
    required double th,
    required bool gatedGlobal,
  }) {
    final accent = _accentColor(context);
    final stats = _statistics;
    final m = _listedMetrics();

    if (stats != null && gatedGlobal) {
      return [
        _buildKpiTile(
          context,
          value: _compactIntFormatter.format(stats.totalClients),
          label: 'Total CRM',
          icon: Icons.diversity_2_outlined,
          accent: accent,
          tileHeight: th,
        ),
        _buildKpiTile(
          context,
          value: _compactIntFormatter.format(stats.activeClients),
          label: 'Ativos',
          icon: Icons.verified_user_outlined,
          accent: AppColors.status.success,
          tileHeight: th,
        ),
        _buildKpiTile(
          context,
          value: _compactIntFormatter.format(stats.buyers),
          label: 'Compradores',
          icon: Icons.shopping_bag_outlined,
          accent: const Color(0xFF3B82F6),
          tileHeight: th,
        ),
        _buildKpiTile(
          context,
          value: _compactIntFormatter.format(stats.sellers),
          label: 'Vendedores',
          icon: Icons.sell_outlined,
          accent: const Color(0xFFF59E0B),
          tileHeight: th,
        ),
      ];
    }

    return [
      _buildKpiTile(
        context,
        value: _compactIntFormatter.format(_total),
        label: 'Filtro',
        icon: Icons.filter_alt_outlined,
        accent: const Color(0xFF6366F1),
        tileHeight: th,
      ),
      _buildKpiTile(
        context,
        value: '${_clients.length}',
        label: 'Nesta página',
        icon: Icons.view_list_rounded,
        accent: accent,
        tileHeight: th,
      ),
      _buildKpiTile(
        context,
        value: '${m.active}',
        label: 'Ativos',
        icon: Icons.verified_user_outlined,
        accent: AppColors.status.success,
        tileHeight: th,
      ),
      _buildKpiTile(
        context,
        value: '${m.buyers + m.renters}',
        label: 'Demanda',
        icon: Icons.trending_up_rounded,
        accent: const Color(0xFF14B8A6),
        tileHeight: th,
      ),
    ];
  }

  Widget _buildKpiTile(
    BuildContext context, {
    required String value,
    required String label,
    required IconData icon,
    required Color accent,
    required double tileHeight,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderCol = ThemeHelpers.borderColor(context);

    return SizedBox(
      width: double.infinity,
      height: tileHeight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isDark
              ? accent.withValues(alpha: 0.065)
              : ShellVisualTokens.dashboardGlassFill(context),
          border: Border.all(
            color: isDark
                ? accent.withValues(alpha: 0.14)
                : borderCol.withValues(alpha: 0.52),
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                    spreadRadius: -2,
                  ),
                ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: accent.withValues(alpha: isDark ? 0.14 : 0.10),
                border: Border.all(
                  color: accent.withValues(alpha: isDark ? 0.26 : 0.24),
                ),
              ),
              child: Icon(icon, size: 18, color: accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      maxLines: 1,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.35,
                        height: 1.05,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveContextChip(
    BuildContext context,
    IconData icon,
    String label, {
    VoidCallback? onClear,
  }) {
    final accent = _accentColor(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: accent.withValues(alpha: isDark ? 0.16 : 0.10),
        border: Border.all(color: accent.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: accent),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w800,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onClear != null) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: onClear,
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.close_rounded, size: 14, color: accent),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ───────────────────────── Métricas listagem ─────────────────────────

  _ListedClientMetrics _listedMetrics() {
    int active = 0,
        inactive = 0,
        contacted = 0,
        interested = 0,
        closed = 0,
        buyers = 0,
        sellers = 0,
        renters = 0,
        lessors = 0,
        investors = 0,
        general = 0,
        withSpouse = 0,
        withWhatsapp = 0,
        mcmv = 0;

    for (final c in _clients) {
      if (c.isActive) {
        active++;
      } else {
        inactive++;
      }
      switch (c.status) {
        case ClientStatus.active:
          break;
        case ClientStatus.inactive:
          break;
        case ClientStatus.contacted:
          contacted++;
          break;
        case ClientStatus.interested:
          interested++;
          break;
        case ClientStatus.closed:
          closed++;
          break;
      }
      switch (c.type) {
        case ClientType.buyer:
          buyers++;
          break;
        case ClientType.seller:
          sellers++;
          break;
        case ClientType.renter:
          renters++;
          break;
        case ClientType.lessor:
          lessors++;
          break;
        case ClientType.investor:
          investors++;
          break;
        case ClientType.general:
          general++;
          break;
      }
      if (c.spouse != null) withSpouse++;
      if ((c.whatsapp ?? '').trim().isNotEmpty) withWhatsapp++;
      if (c.mcmvInterested == true) mcmv++;
    }

    return _ListedClientMetrics(
      active: active,
      inactive: inactive,
      contacted: contacted,
      interested: interested,
      closed: closed,
      buyers: buyers,
      sellers: sellers,
      renters: renters,
      lessors: lessors,
      investors: investors,
      general: general,
      withSpouse: withSpouse,
      withWhatsapp: withWhatsapp,
      mcmv: mcmv,
    );
  }

  // ───────────────────────── Viewport / Lista ─────────────────────────

  Widget _buildScrollableViewport(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          _loadClients(refresh: true),
          _loadStatistics(),
        ]);
      },
      color: AppColors.primary.primary,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(child: _buildClientsHeader(context)),
          SliverToBoxAdapter(child: _buildSearchBar(context)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index >= _clients.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildClientCard(context, _clients[index]),
                  );
                },
                childCount: _clients.length + (_isLoadingMore ? 1 : 0),
              ),
            ),
          ),
          if (_totalPages > 1)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: _buildPagination(context),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accentColor(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Container(
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: ThemeHelpers.borderLightColor(context),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
              child: Icon(
                Icons.search_rounded,
                color: accent.withValues(alpha: 0.85),
              ),
            ),
            Expanded(
              child: TextField(
                controller: _searchController,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  hintText: 'Buscar nome, email, telefone, CPF…',
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w500,
                  ),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
                ),
                onChanged: _handleSearch,
                textInputAction: TextInputAction.search,
                onSubmitted: _handleSearch,
              ),
            ),
            if (_searchQuery.isNotEmpty)
              IconButton(
                tooltip: 'Limpar busca',
                icon: Icon(
                  Icons.close_rounded,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
                onPressed: () {
                  _searchController.clear();
                  _handleSearch('');
                },
              )
            else
              IconButton(
                tooltip: 'Filtros',
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                    if (_hasActiveFilters())
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
                onPressed: () => _openFilters(context),
              ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── Card de Cliente ─────────────────────────

  Widget _buildClientCard(BuildContext context, Client client) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final typeColor = _typeColor(client.type, context);
    final statusColor = _statusColor(client.status);
    final initials = _initialsFor(client.name);
    final muted = ThemeHelpers.textSecondaryColor(context);

    final phone = client.phone.trim();
    final whatsapp = (client.whatsapp ?? '').trim();
    final email = client.email.trim();
    final hasCity = client.city.trim().isNotEmpty;
    final hasContacts =
        phone.isNotEmpty || whatsapp.isNotEmpty || email.isNotEmpty;

    final summaryParts = <String>[];
    if (email.isNotEmpty) summaryParts.add(email);
    if (whatsapp.isNotEmpty) {
      summaryParts.add(Masks.phone(whatsapp));
    } else if (phone.isNotEmpty) {
      summaryParts.add(Masks.phone(phone));
    }
    if (hasCity) {
      summaryParts.add(
        client.state.trim().isNotEmpty
            ? '${client.city} · ${client.state}'
            : client.city,
      );
    }

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    typeColor.withValues(alpha: 0.12),
                    typeColor.withValues(alpha: 0.03),
                  ]
                : [
                    Colors.white,
                    typeColor.withValues(alpha: 0.06),
                  ],
          ),
          border: Border.all(
            color: typeColor.withValues(alpha: isDark ? 0.30 : 0.22),
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                    spreadRadius: -3,
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: () => Navigator.pushNamed(
              context,
              AppRoutes.clientDetails(client.id),
            ).then((_) => _loadClients(refresh: true)),
            onLongPress: () => _showClientActions(context, client),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Faixa lateral colorida — indicador visual de tipo
                  Container(
                    width: 5,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          typeColor.withValues(alpha: 0.9),
                          typeColor.withValues(alpha: 0.45),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Linha principal: avatar + nome + matches + menu
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _buildAvatar(
                                context,
                                initials: initials,
                                typeColor: typeColor,
                                typeIcon: _iconForType(client.type),
                                statusColor: statusColor,
                                isActive: client.isActive,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      client.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        color:
                                            ThemeHelpers.textColor(context),
                                        height: 1.05,
                                        letterSpacing: -0.35,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        _typePill(
                                          context,
                                          label: client.type.label,
                                          color: typeColor,
                                          icon: _iconForType(client.type),
                                        ),
                                        _statusDot(
                                          context,
                                          color: statusColor,
                                          label: client.status.label,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              _MatchesPill(
                                clientId: client.id,
                                accent: typeColor,
                                onTap: () => Navigator.pushNamed(
                                  context,
                                  AppRoutes.matchesByClient(client.id),
                                ),
                              ),
                              _buildCardOverflowMenu(context, client),
                            ],
                          ),
                          if (summaryParts.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _buildSummaryLine(
                              context,
                              parts: summaryParts,
                              muted: muted,
                            ),
                          ],
                          if (hasContacts ||
                              client.responsibleUser != null) ...[
                            const SizedBox(height: 10),
                            _buildActionsAndFooter(
                              context,
                              client: client,
                              phone: phone,
                              whatsapp: whatsapp,
                              email: email,
                              accent: typeColor,
                            ),
                          ],
                        ],
                      ),
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

  Widget _buildAvatar(
    BuildContext context, {
    required String initials,
    required Color typeColor,
    required IconData typeIcon,
    required Color statusColor,
    required bool isActive,
  }) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 54,
      height: 54,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  typeColor.withValues(alpha: 0.95),
                  typeColor.withValues(alpha: 0.55),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: typeColor.withValues(alpha: 0.32),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                height: 1.0,
              ),
            ),
          ),
          // Mini ícone de tipo flutuante
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ThemeHelpers.cardBackgroundColor(context),
                border: Border.all(
                  color: typeColor.withValues(alpha: 0.6),
                  width: 1.4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Icon(typeIcon, size: 12, color: typeColor),
            ),
          ),
          // Status dot inferior
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive ? statusColor : AppColors.status.error,
                border: Border.all(
                  color: ThemeHelpers.cardBackgroundColor(context),
                  width: 2.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _typePill(
    BuildContext context, {
    required String label,
    required Color color,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 9.5,
                letterSpacing: 0.55,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusDot(
    BuildContext context, {
    required Color color,
    required String label,
  }) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 4,
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w700,
              fontSize: 10,
              height: 1.1,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryLine(
    BuildContext context, {
    required List<String> parts,
    required Color muted,
  }) {
    final theme = Theme.of(context);
    final spans = <InlineSpan>[];
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) {
        spans.add(
          TextSpan(
            text: '  ·  ',
            style: theme.textTheme.bodySmall?.copyWith(
              color: muted.withValues(alpha: 0.45),
              fontWeight: FontWeight.w800,
            ),
          ),
        );
      }
      spans.add(
        TextSpan(
          text: parts[i],
          style: theme.textTheme.bodySmall?.copyWith(
            color: muted,
            fontWeight: FontWeight.w600,
            fontSize: 12.5,
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            color: muted.withValues(alpha: 0.22),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(children: spans),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildActionsAndFooter(
    BuildContext context, {
    required Client client,
    required String phone,
    required String whatsapp,
    required String email,
    required Color accent,
  }) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final hasResponsible = client.responsibleUser != null;
    final responsibleName = client.responsibleUser?.name ?? '';

    final actions = <Widget>[];
    if (whatsapp.isNotEmpty) {
      actions.add(_quickContact(
        context,
        icon: Icons.chat_outlined,
        label: 'WhatsApp',
        color: const Color(0xFF25D366),
        onTap: () => _launchUri('https://wa.me/${_onlyDigits(whatsapp)}'),
      ));
    }
    if (phone.isNotEmpty) {
      actions.add(_quickContact(
        context,
        icon: Icons.call_rounded,
        label: 'Ligar',
        color: const Color(0xFF3B82F6),
        onTap: () => _launchUri('tel:${_onlyDigits(phone)}'),
      ));
    }
    if (email.isNotEmpty) {
      actions.add(_quickContact(
        context,
        icon: Icons.alternate_email_rounded,
        label: 'Email',
        color: const Color(0xFFF59E0B),
        onTap: () => _launchUri('mailto:$email'),
      ));
    }

    if (actions.isEmpty && !hasResponsible) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: accent.withValues(alpha: 0.06),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          if (actions.isNotEmpty) ...[
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0)
                Container(
                  width: 1,
                  height: 18,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: accent.withValues(alpha: 0.16),
                ),
              actions[i],
            ],
            if (hasResponsible) const SizedBox(width: 6),
          ],
          if (hasResponsible)
            Expanded(
              child: Row(
                mainAxisAlignment: actions.isEmpty
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.end,
                children: [
                  Icon(
                    Icons.assignment_ind_outlined,
                    size: 13,
                    color: muted,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      responsibleName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w800,
                        fontSize: 10.5,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _quickContact(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Tooltip(
        message: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Icon(icon, size: 17, color: color),
        ),
      ),
    );
  }

  Widget _buildCardOverflowMenu(BuildContext context, Client client) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_horiz_rounded,
        color: ThemeHelpers.textSecondaryColor(context),
      ),
      tooltip: 'Ações',
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      padding: EdgeInsets.zero,
      iconSize: 22,
      splashRadius: 22,
      onSelected: (value) async {
        switch (value) {
          case 'view':
            await Navigator.pushNamed(
              context,
              AppRoutes.clientDetails(client.id),
            );
            _loadClients(refresh: true);
            break;
          case 'edit':
            await Navigator.pushNamed(
              context,
              AppRoutes.clientEdit(client.id),
            );
            _loadClients(refresh: true);
            _loadStatistics();
            break;
          case 'matches':
            Navigator.pushNamed(
              context,
              AppRoutes.matchesByClient(client.id),
            );
            break;
          case 'transfer':
            if (mounted) await _showTransferModal(context, client);
            break;
          case 'delete':
            if (mounted) await _showDeleteConfirmation(context, client);
            break;
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'view',
          child: Row(children: [
            Icon(Icons.open_in_new_rounded, size: 18),
            SizedBox(width: 10),
            Text('Abrir'),
          ]),
        ),
        PopupMenuItem(
          value: 'edit',
          child: Row(children: [
            Icon(Icons.edit_outlined, size: 18),
            SizedBox(width: 10),
            Text('Editar'),
          ]),
        ),
        PopupMenuItem(
          value: 'matches',
          child: Row(children: [
            Icon(Icons.handshake_outlined, size: 18),
            SizedBox(width: 10),
            Text('Ver matches'),
          ]),
        ),
        PopupMenuItem(
          value: 'transfer',
          child: Row(children: [
            Icon(Icons.swap_horiz_rounded, size: 18),
            SizedBox(width: 10),
            Text('Transferir'),
          ]),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Row(children: [
            Icon(Icons.delete_outline, size: 18, color: Colors.red),
            SizedBox(width: 10),
            Text('Excluir', style: TextStyle(color: Colors.red)),
          ]),
        ),
      ],
    );
  }

  String _onlyDigits(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

  Future<void> _launchUri(String uri) async {
    final parsed = Uri.tryParse(uri);
    if (parsed == null) return;
    try {
      await launchUrl(parsed, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir esse link')),
      );
    }
  }

  String _initialsFor(String name) {
    if (name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  Color _typeColor(ClientType type, BuildContext context) {
    switch (type) {
      case ClientType.buyer:
        return const Color(0xFF3B82F6);
      case ClientType.seller:
        return const Color(0xFFF59E0B);
      case ClientType.renter:
        return const Color(0xFF10B981);
      case ClientType.lessor:
        return const Color(0xFF06B6D4);
      case ClientType.investor:
        return const Color(0xFF8B5CF6);
      case ClientType.general:
        return ThemeHelpers.textSecondaryColor(context);
    }
  }

  IconData _iconForType(ClientType type) {
    switch (type) {
      case ClientType.buyer:
        return Icons.shopping_bag_outlined;
      case ClientType.seller:
        return Icons.sell_outlined;
      case ClientType.renter:
        return Icons.home_outlined;
      case ClientType.lessor:
        return Icons.business_outlined;
      case ClientType.investor:
        return Icons.trending_up_outlined;
      case ClientType.general:
        return Icons.person_outline;
    }
  }

  Color _statusColor(ClientStatus status) {
    switch (status) {
      case ClientStatus.active:
        return AppColors.status.success;
      case ClientStatus.inactive:
        return AppColors.status.error;
      case ClientStatus.contacted:
        return AppColors.status.info;
      case ClientStatus.interested:
        return AppColors.status.warning;
      case ClientStatus.closed:
        return Colors.grey;
    }
  }

  // ───────────────────────── Pagination ─────────────────────────

  Widget _buildPagination(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final narrow = MediaQuery.sizeOf(context).width < 360;

    return Container(
      padding: EdgeInsets.fromLTRB(narrow ? 10 : 14, 4, narrow ? 10 : 14, 8),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: narrow ? 8 : 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.background.backgroundSecondaryDarkMode
              : AppColors.background.backgroundSecondary,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.76),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Página $_currentPage de $_totalPages',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      fontWeight: FontWeight.w900,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$_total clientes encontrados',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: narrow ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              constraints: narrow
                  ? const BoxConstraints(minWidth: 38, minHeight: 38)
                  : BoxConstraints.loose(const Size.square(48)),
              padding: narrow ? EdgeInsets.zero : null,
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: _currentPage > 1
                  ? () {
                      setState(() => _currentPage--);
                      _loadClients();
                    }
                  : null,
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              constraints: narrow
                  ? const BoxConstraints(minWidth: 38, minHeight: 38)
                  : BoxConstraints.loose(const Size.square(48)),
              padding: narrow ? EdgeInsets.zero : null,
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: _currentPage < _totalPages
                  ? () {
                      setState(() => _currentPage++);
                      _loadClients();
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── Skeleton / Empty / Error ─────────────────────────

  Widget _buildSkeleton(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SkeletonBox(width: double.infinity, height: 56, borderRadius: 16),
          const SizedBox(height: 16),
          ...List.generate(
            6,
            (index) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SkeletonBox(
                width: double.infinity,
                height: 132,
                borderRadius: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.status.error.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: AppColors.status.error,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Não foi possível carregar a carteira',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Erro desconhecido',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: () {
                _loadClients(refresh: true);
                _loadStatistics();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar novamente'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accentColor(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderCol = ThemeHelpers.borderColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final bg = isDark
        ? AppColors.background.backgroundSecondaryDarkMode
        : AppColors.background.backgroundSecondary;
    final obstructed = _searchQuery.trim().isNotEmpty || _hasActiveFilters();

    final eyebrow = obstructed ? 'Resultados' : 'Carteira';
    final title = obstructed
        ? 'Nenhum cliente encontrado'
        : 'Nenhum cliente cadastrado';
    final subtitle = obstructed
        ? 'Amplie os critérios ou volte ao panorama completo da carteira.'
        : 'Comece adicionando o primeiro lead — ele aparecerá aqui em segundos.';

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: borderCol.withValues(alpha: isDark ? 0.48 : 0.62),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.26 : 0.075),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                  spreadRadius: -6,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(21),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          accent.withValues(alpha: 0.9),
                          accent.withValues(alpha: 0.22),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                color: accent.withValues(alpha: isDark ? 0.12 : 0.10),
                                border: Border.all(
                                  color: accent.withValues(alpha: 0.22),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: accent.withValues(alpha: 0.14),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Icon(
                                obstructed
                                    ? Icons.manage_search_rounded
                                    : Icons.diversity_3_outlined,
                                size: 22,
                                color: accent,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    eyebrow.toUpperCase(),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      letterSpacing: 0.9,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 10,
                                      color: muted.withValues(alpha: 0.95),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.3,
                                      height: 1.15,
                                      color: ThemeHelpers.textColor(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Divider(
                          height: 1,
                          thickness: 1,
                          indent: 4,
                          endIndent: 4,
                          color: borderCol.withValues(alpha: 0.42),
                        ),
                        const SizedBox(height: 11),
                        Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                            height: 1.4,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _navigateToCreate,
                            icon: const Icon(Icons.person_add_alt_1, size: 18),
                            label: Text(
                              obstructed
                                  ? 'Cadastrar cliente'
                                  : 'Criar primeiro cliente',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.1,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                        if (obstructed) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                  _filters = null;
                                });
                                _loadClients(refresh: true);
                                _loadStatistics();
                              },
                              icon: Icon(
                                Icons.filter_alt_off_outlined,
                                size: 17,
                                color: accent.withValues(alpha: 0.94),
                              ),
                              label: const Text(
                                'Limpar busca e filtros',
                                style:
                                    TextStyle(fontWeight: FontWeight.w800),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: accent,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 11),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: BorderSide(
                                  color: accent.withValues(alpha: 0.38),
                                ),
                              ),
                            ),
                          ),
                        ],
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

  // ───────────────────────── Ações ─────────────────────────

  void _navigateToCreate() {
    Navigator.pushNamed(context, AppRoutes.clientCreate).then((created) {
      if (!mounted) return;
      if (created != null) {
        _loadClients(refresh: true);
        _loadStatistics();
      }
    });
  }

  void _openFilters(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black54,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (context) => ClientFiltersDrawer(
        initialFilters: _filters,
        onFiltersChanged: (filters) {
          setState(() => _filters = filters);
          _loadClients(refresh: true);
          _loadStatistics();
        },
      ),
    );
  }

  Future<void> _showSearchSheet(BuildContext context) async {
    final controller =
        TextEditingController(text: _searchController.text);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            decoration: BoxDecoration(
              color: ThemeHelpers.cardBackgroundColor(ctx),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(
                color: ThemeHelpers.borderColor(ctx).withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: ThemeHelpers.borderColor(ctx).withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Text(
                  'Buscar clientes',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Nome, email, CPF, telefone…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onSubmitted: (value) {
                    Navigator.pop(ctx);
                    _searchController.text = value;
                    _handleSearch(value);
                  },
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _searchController.text = controller.text;
                    _handleSearch(controller.text);
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Aplicar busca'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showClientActions(BuildContext context, Client client) async {
    final theme = Theme.of(context);
    final typeColor = _typeColor(client.type, context);
    final navigator = Navigator.of(context);

    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(ctx),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ThemeHelpers.borderColor(ctx).withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          typeColor.withValues(alpha: 0.85),
                          typeColor.withValues(alpha: 0.55),
                        ],
                      ),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _initialsFor(client.name),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          client.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${client.type.label} · ${client.status.label}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(ctx),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _actionRow(
                ctx,
                Icons.open_in_new_rounded,
                'Abrir cliente',
                'Ver detalhes completos e interações',
                () => Navigator.pop(ctx, 'view'),
              ),
              _actionRow(
                ctx,
                Icons.edit_outlined,
                'Editar dados',
                'Atualizar informações cadastrais',
                () => Navigator.pop(ctx, 'edit'),
              ),
              _actionRow(
                ctx,
                Icons.handshake_outlined,
                'Ver matches',
                'Imóveis compatíveis com o perfil',
                () => Navigator.pop(ctx, 'matches'),
              ),
              _actionRow(
                ctx,
                Icons.swap_horiz_rounded,
                'Transferir',
                'Atribuir a outro responsável',
                () => Navigator.pop(ctx, 'transfer'),
              ),
              _actionRow(
                ctx,
                Icons.delete_outline,
                'Excluir cliente',
                'Remoção permanente do registro',
                () => Navigator.pop(ctx, 'delete'),
                destructive: true,
              ),
            ],
          ),
        ),
      ),
    );

    if (action == null || !mounted) return;
    switch (action) {
      case 'view':
        await navigator.pushNamed(AppRoutes.clientDetails(client.id));
        _loadClients(refresh: true);
        break;
      case 'edit':
        await navigator.pushNamed(AppRoutes.clientEdit(client.id));
        _loadClients(refresh: true);
        _loadStatistics();
        break;
      case 'matches':
        navigator.pushNamed(AppRoutes.matchesByClient(client.id));
        break;
      case 'transfer':
        if (!mounted) break;
        // ignore: use_build_context_synchronously
        await _showTransferModal(context, client);
        break;
      case 'delete':
        if (!mounted) break;
        // ignore: use_build_context_synchronously
        await _showDeleteConfirmation(context, client);
        break;
    }
  }

  Widget _actionRow(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap, {
    bool destructive = false,
  }) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final fg = destructive ? AppColors.status.error : ThemeHelpers.textColor(context);
    final iconColor = destructive ? AppColors.status.error : _accentColor(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                color: iconColor.withValues(alpha: 0.10),
                border: Border.all(color: iconColor.withValues(alpha: 0.22)),
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: fg,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: destructive
                          ? AppColors.status.error.withValues(alpha: 0.78)
                          : muted,
                      fontWeight: FontWeight.w500,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: muted.withValues(alpha: 0.38)),
          ],
        ),
      ),
    );
  }

  Future<void> _showTransferModal(BuildContext context, Client client) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        clipBehavior: Clip.antiAlias,
        child: TransferClientModal(
          clientId: client.id,
          clientName: client.name,
          currentResponsibleUserId: client.responsibleUserId,
          currentResponsibleName: client.responsibleUser?.name,
        ),
      ),
    );

    if (result == true) {
      _loadClients(refresh: true);
      _loadStatistics();
    }
  }

  Future<void> _showDeleteConfirmation(
    BuildContext context,
    Client client,
  ) async {
    final theme = Theme.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.status.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.warning_amber_rounded,
                color: AppColors.status.error,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Excluir cliente?')),
          ],
        ),
        content: Text(
          'O cliente "${client.name}" será removido permanentemente. '
          'Essa ação não pode ser desfeita.',
          style: theme.textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.status.error,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final response = await _clientService.deleteClient(client.id);
    if (!mounted) return;

    if (response.success) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Cliente excluído com sucesso!'),
          backgroundColor: AppColors.status.success,
        ),
      );
      _loadClients(refresh: true);
      _loadStatistics();
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(response.message ?? 'Erro ao excluir cliente'),
          backgroundColor: AppColors.status.error,
        ),
      );
    }
  }

  Future<void> _showImportModal() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (context) => AsyncExcelImportModal(
        onImportComplete: () {
          _loadClients(refresh: true);
          _loadStatistics();
        },
      ),
    );
  }

  Future<void> _exportClients() async {
    final format = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(ctx),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: ThemeHelpers.borderColor(ctx).withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Text(
                'Exportar carteira',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Os filtros atuais serão aplicados ao arquivo gerado.',
                textAlign: TextAlign.center,
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(ctx),
                    ),
              ),
              const SizedBox(height: 16),
              _actionRow(
                ctx,
                Icons.table_chart_outlined,
                'Excel (.xlsx)',
                'Planilha completa com todos os campos',
                () => Navigator.pop(ctx, 'xlsx'),
              ),
              _actionRow(
                ctx,
                Icons.description_outlined,
                'CSV (.csv)',
                'Formato leve, ideal para integrações',
                () => Navigator.pop(ctx, 'csv'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        ),
      ),
    );

    if (format == null || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Text('Exportando clientes...'),
          ],
        ),
        duration: Duration(seconds: 30),
      ),
    );

    try {
      final response = await _clientService.exportClients(
        filters: _filters,
        format: format,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (response.success && response.data != null) {
        final size = response.data!.length;
        final readable = size >= 1024 * 1024
            ? '${(size / (1024 * 1024)).toStringAsFixed(1)} MB'
            : '${(size / 1024).toStringAsFixed(1)} KB';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Exportação pronta · $readable. Em breve será possível baixar diretamente.',
            ),
            backgroundColor: AppColors.status.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.message ?? 'Erro ao exportar clientes'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao exportar: ${e.toString()}'),
          backgroundColor: AppColors.status.error,
        ),
      );
    }
  }

  // ───────────────────────── Helpers ─────────────────────────

  bool _hasActiveFilters() {
    final f = _filters;
    if (f == null) return false;
    return f.name != null ||
        f.email != null ||
        f.phone != null ||
        f.document != null ||
        f.city != null ||
        f.neighborhood != null ||
        f.state != null ||
        f.type != null ||
        f.status != null ||
        f.isActive != null ||
        f.onlyMyData != null ||
        f.createdFrom != null ||
        f.createdTo != null ||
        f.sortBy != null;
  }
}

/// Pill compacta que mostra a contagem de matches pendentes do cliente.
///
/// Aparece apenas quando há matches > 0; do contrário, ocupa zero espaço.
class _MatchesPill extends StatefulWidget {
  const _MatchesPill({
    required this.clientId,
    required this.accent,
    this.onTap,
  });

  final String clientId;
  final Color accent;
  final VoidCallback? onTap;

  @override
  State<_MatchesPill> createState() => _MatchesPillState();
}

class _MatchesPillState extends State<_MatchesPill> {
  int _count = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await MatchService.instance.getMatches(
        status: MatchStatus.pending,
        clientId: widget.clientId,
        limit: 1,
      );
      if (!mounted) return;
      setState(() {
        _count = response.data?.total ?? 0;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _count == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final color = widget.accent;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              colors: [color, color.withValues(alpha: 0.78)],
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.34),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.local_fire_department_rounded,
                size: 12,
                color: Colors.white,
              ),
              const SizedBox(width: 4),
              Text(
                _count > 99 ? '99+' : '$_count',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  height: 1.0,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Extensão para clonar filtros, útil em vários pontos da listagem.
extension ClientSearchFiltersExtension on ClientSearchFilters {
  ClientSearchFilters copyWith({
    String? name,
    String? email,
    String? phone,
    String? search,
    String? document,
    String? city,
    String? neighborhood,
    String? state,
    ClientType? type,
    ClientStatus? status,
    String? responsibleUserId,
    bool? isActive,
    bool? onlyMyData,
    String? createdFrom,
    String? createdTo,
    int? limit,
    int? page,
    String? sortBy,
    String? sortOrder,
  }) {
    return ClientSearchFilters(
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      search: search ?? this.search,
      document: document ?? this.document,
      city: city ?? this.city,
      neighborhood: neighborhood ?? this.neighborhood,
      state: state ?? this.state,
      type: type ?? this.type,
      status: status ?? this.status,
      responsibleUserId: responsibleUserId ?? this.responsibleUserId,
      isActive: isActive ?? this.isActive,
      onlyMyData: onlyMyData ?? this.onlyMyData,
      createdFrom: createdFrom ?? this.createdFrom,
      createdTo: createdTo ?? this.createdTo,
      limit: limit ?? this.limit,
      page: page ?? this.page,
      sortBy: sortBy ?? this.sortBy,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}
