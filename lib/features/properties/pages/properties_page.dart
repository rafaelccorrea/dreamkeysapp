import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../shared/services/property_service.dart';
import '../../../../shared/services/module_access_service.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/skeleton_box.dart';
import '../../../../shared/widgets/shimmer_image.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/shell_visual_tokens.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../widgets/property_filters_drawer.dart';
import '../widgets/intelligent_search_modal.dart';
import '../widgets/export_import_dialog.dart';
import '../services/property_local_draft_storage.dart';
import '../../../../shared/services/ai_service.dart';
import '../../matches/widgets/matches_badge.dart';
import '../../../../core/routes/app_routes.dart';
import '../models/property_wizard_pop_result.dart';

// Formatter de moeda
final _currencyFormatter = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 2,
);

final _compactIntFormatter = NumberFormat.decimalPattern('pt_BR');

/// Métricas agregadas apenas da página/lista carregada.
class _ListedPropertyMetrics {
  const _ListedPropertyMetrics({
    required this.available,
    required this.rented,
    required this.sold,
    required this.draft,
    required this.pendingReview,
    required this.maintenance,
    required this.active,
    required this.inactive,
    required this.featuredHighlights,
    required this.publishedOnline,
    required this.negotiationFriendly,
    required this.sumOfferPending,
    this.avgRentPrice,
    this.avgSalePriceOnly,
    this.avgAreaSqm,
  });

  final int available;
  final int rented;
  final int sold;
  final int draft;
  /// `pending_approval` + `pending_owner_authorization` no CRM.
  final int pendingReview;
  final int maintenance;
  final int active;
  final int inactive;
  final int featuredHighlights;
  final int publishedOnline;
  final int negotiationFriendly;
  final int sumOfferPending;
  final double? avgRentPrice;
  final double? avgSalePriceOnly;
  final double? avgAreaSqm;
}

/// Linha do menu ⋯ do card de imóvel: ícone em cápsula + título + subtítulo + chevron.
class _PropertyActionMenuRow extends StatelessWidget {
  const _PropertyActionMenuRow({
    required this.icon,
    required this.iconBackground,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.isDestructive = false,
  });

  final IconData icon;
  final Color iconBackground;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final titleColor = ThemeHelpers.textColor(context);
    final error = theme.colorScheme.error;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: iconBackground,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: isDestructive
                  ? error.withValues(alpha: 0.22)
                  : iconColor.withValues(alpha: 0.16),
            ),
          ),
          child: Icon(icon, size: 21, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.25,
                  height: 1.15,
                  color: isDestructive ? error : titleColor,
                  fontSize: 14.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  height: 1.25,
                  color: isDestructive
                      ? error.withValues(alpha: 0.78)
                      : muted.withValues(alpha: 0.95),
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Icon(
          Icons.chevron_right_rounded,
          size: 22,
          color: muted.withValues(alpha: 0.38),
        ),
      ],
    );
  }
}

class PropertiesPage extends StatefulWidget {
  const PropertiesPage({super.key});

  @override
  State<PropertiesPage> createState() => _PropertiesPageState();
}

class _PropertiesPageState extends State<PropertiesPage> {
  static const double _kHeaderPadH = 20;
  static const double _kHeaderPadVTop = 10;
  static const double _kStatCarouselHeight = 118;
  static const double _kStatTileWidth = 140;

  int _exploreGridCrossAxisCount(double width) {
    if (width >= 900) return 4;
    if (width >= 640) return 3;
    return 2;
  }

  double _exploreGridChildAspectRatio(int columns) {
    switch (columns) {
      case 4:
        return 0.86;
      case 3:
        return 0.78;
      default:
        return 0.69;
    }
  }

  /// Acima deste tamanho, uma faixa horizontal de destaques evita sensação de “fila” única.
  int _discoverLeadCount(int total) {
    if (total <= 8) return 0;
    return total >= 18 ? 8 : 6;
  }

  final PropertyService _propertyService = PropertyService.instance;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  List<Property> _properties = [];
  PropertyStats? _globalStats;
  int _currentPage = 1;
  int _totalPages = 1;
  int _total = 0;
  String? _errorMessage;
  PropertyFilters? _filters;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  int _localDraftCount = 0;

  @override
  void initState() {
    super.initState();
    _loadProperties();
    _refreshLocalDraftCount();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshLocalDraftCount() async {
    final n =
        (await PropertyLocalDraftStorage.instance.loadAllForCurrentCompany())
            .length;
    if (mounted) setState(() => _localDraftCount = n);
  }

  Future<void> _onPropertyWizardReturned(Object? result) async {
    await _refreshLocalDraftCount();
    if (!mounted || result == null) return;

    await _loadProperties(refresh: true);
    if (result is PropertyWizardPopResult) {
      final r = result;
      if (r.showApprovalShortcut &&
          r.propertyId != null &&
          r.propertyId!.isNotEmpty) {
        final id = r.propertyId!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: const Text(
              'Imóvel na fila de aprovação ou autorização — o backend aplicou o mesmo fluxo do CRM web.',
            ),
            action: SnackBarAction(
              label: 'Abrir imóvel',
              onPressed: () {
                Navigator.of(context).pushNamed(AppRoutes.propertyDetails(id));
              },
            ),
          ),
        );
      }
      return;
    }

    // Compat: rotas mais antigas retornavam apenas `true`
    if (result == true) {
      return;
    }
  }

  Future<void> _openPropertyCreateThenRefreshDrafts() async {
    final r = await Navigator.of(context).pushNamed(AppRoutes.propertyCreate);
    await _onPropertyWizardReturned(r);
  }

  Future<void> _openLocalDrafts() async {
    await Navigator.of(context).pushNamed(AppRoutes.propertyDraftsLocal);
    await _refreshLocalDraftCount();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      // Carregar mais quando estiver a 200px do final
      if (!_isLoadingMore && _currentPage < _totalPages) {
        _loadMoreProperties();
      }
    }
  }

  Future<void> _loadProperties({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _currentPage = 1;
        _properties.clear();
      });
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final filters =
          _filters?.copyWith(
            search: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
          ) ??
          (_searchQuery.trim().isNotEmpty
              ? PropertyFilters(search: _searchQuery.trim())
              : null);

      final response = await _propertyService.getProperties(
        page: _currentPage,
        limit: 50,
        filters: filters,
      );

      if (mounted) {
        if (response.success && response.data != null) {
          PropertyStats? gs;
          try {
            final statsRes = await _propertyService.getPropertyStats();
            if (mounted && statsRes.success && statsRes.data != null) {
              gs = statsRes.data!;
            }
          } catch (_) {}

          if (mounted) {
            setState(() {
              _properties = response.data!.data;
              _totalPages = response.data!.totalPages;
              _total = response.data!.total;
              _globalStats = gs;
              _isLoading = false;
            });
          }
        } else {
          setState(() {
            _errorMessage = response.message ?? 'Erro ao carregar propriedades';
            _globalStats = null;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ [PROPERTIES_PAGE] Erro: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro ao conectar com o servidor';
          _globalStats = null;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoreProperties() async {
    if (_isLoadingMore || _currentPage >= _totalPages) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final nextPage = _currentPage + 1;
      final filters =
          _filters?.copyWith(
            search: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
          ) ??
          (_searchQuery.trim().isNotEmpty
              ? PropertyFilters(search: _searchQuery.trim())
              : null);

      final response = await _propertyService.getProperties(
        page: nextPage,
        limit: 50,
        filters: filters,
      );

      if (mounted) {
        if (response.success && response.data != null) {
          setState(() {
            _properties.addAll(response.data!.data);
            _currentPage = nextPage;
            _totalPages = response.data!.totalPages;
            _isLoadingMore = false;
          });
        } else {
          setState(() {
            _isLoadingMore = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ [PROPERTIES_PAGE] Erro ao carregar mais: $e');
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  Widget _buildPropertiesScreenOverflowMenu(BuildContext context) {
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
        icon: Icon(Icons.more_vert, color: ThemeHelpers.textColor(context).withValues(alpha: 0.88)),
        tooltip: 'Mais opções',
        onSelected: (value) {
          switch (value) {
              case 'search':
                _showSearchBottomSheet(context);
                break;
              case 'filters':
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  barrierColor: Colors.black54,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  builder: (context) => PropertyFiltersDrawer(
                    initialFilters: _filters,
                    onFiltersChanged: (filters) {
                      setState(() {
                        _filters = filters;
                      });
                      _loadProperties(refresh: true);
                    },
                  ),
                );
                break;
              case 'offers':
                Navigator.of(context).pushNamed(AppRoutes.propertyOffers);
                break;
              case 'export_import':
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  barrierColor: Colors.black54,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  builder: (context) => const ExportImportDialog(),
                ).then((success) {
                  if (success == true) {
                    _loadProperties(refresh: true);
                  }
                });
                break;
              case 'portfolio_metrics':
                _showPortfolioOverflowMetricsSheet(context);
                break;
              case 'ai_search':
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  barrierColor: Colors.black54,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  builder: (context) => IntelligentSearchModal(
                    onResults: (results) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${results.results.length} propriedades encontradas',
                          ),
                          action: SnackBarAction(
                            label: 'Ver Resultados',
                            onPressed: () {},
                          ),
                        ),
                      );
                    },
                  ),
                );
                break;
              case 'optimize':
                _showOptimizationDialog(context);
                break;
            }
          },
          itemBuilder: (menuCtx) {
            final pmt = Theme.of(menuCtx).popupMenuTheme;
            final labelStyle = pmt.textStyle ?? Theme.of(menuCtx).textTheme.bodyMedium;
            final iconColor =
                pmt.iconColor ?? ThemeHelpers.textSecondaryColor(menuCtx);
            return [
              PopupMenuItem(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                value: 'search',
                child: Text.rich(
                  TextSpan(
                    children: [
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Icon(Icons.search, size: 20, color: iconColor),
                      ),
                      const WidgetSpan(child: SizedBox(width: 10)),
                      TextSpan(text: 'Buscar', style: labelStyle),
                    ],
                  ),
                ),
              ),
              PopupMenuItem(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                value: 'filters',
                child: Text.rich(
                  TextSpan(
                    children: [
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(Icons.filter_list, size: 20, color: iconColor),
                            if (_filters != null && _hasActiveFilters())
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
                    ],
                  ),
                ),
              ),
              const PopupMenuDivider(height: 10, thickness: 1),
              PopupMenuItem(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                value: 'portfolio_metrics',
                child: Text.rich(
                  TextSpan(
                    children: [
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Icon(Icons.insights_outlined, size: 20, color: iconColor),
                      ),
                      const WidgetSpan(child: SizedBox(width: 10)),
                      TextSpan(text: 'Métricas detalhadas', style: labelStyle),
                    ],
                  ),
                ),
              ),
              PopupMenuItem(
                value: 'ai_search',
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                height: 58,
                child: _buildPremiumAiSearchMenuHighlight(menuCtx),
              ),
              PopupMenuItem(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                value: 'optimize',
                child: Text.rich(
                  TextSpan(
                    children: [
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Icon(Icons.trending_up_rounded, size: 20, color: iconColor),
                      ),
                      const WidgetSpan(child: SizedBox(width: 10)),
                      TextSpan(text: 'Otimizar portfólio', style: labelStyle),
                    ],
                  ),
                ),
              ),
              PopupMenuItem(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                value: 'offers',
                child: Text.rich(
                  TextSpan(
                    children: [
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Icon(Icons.request_quote, size: 20, color: iconColor),
                      ),
                      const WidgetSpan(child: SizedBox(width: 10)),
                      TextSpan(text: 'Ver Ofertas', style: labelStyle),
                    ],
                  ),
                ),
              ),
              PopupMenuItem(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                value: 'export_import',
                child: Text.rich(
                  TextSpan(
                    children: [
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Icon(Icons.import_export, size: 20, color: iconColor),
                      ),
                      const WidgetSpan(child: SizedBox(width: 10)),
                      TextSpan(text: 'Exportar/Importar', style: labelStyle),
                    ],
                  ),
                ),
              ),
            ];
          },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Imóveis',
      currentBottomNavIndex: 1,
      showBottomNavigation: true,
      actions: [
        _buildPropertiesScreenOverflowMenu(context),
      ],
      body: _isLoading
          ? Column(
              children: [
                _buildPortfolioHeader(context),
                Expanded(child: _buildSkeleton(context)),
              ],
            )
          : _errorMessage != null
              ? Column(
                  children: [
                    _buildPortfolioHeader(context),
                    Expanded(child: _buildErrorState(context)),
                  ],
                )
              : _properties.isEmpty
                  ? Column(
                      children: [
                        _buildPortfolioHeader(context),
                        Expanded(
                          child: _buildEmptyPropertiesState(context, Theme.of(context)),
                        ),
                      ],
                    )
                  : _buildScrollablePropertiesViewport(context),
    );
  }

  /// Faixa de 4 KPIs: preenche a largura com colunas iguais ([Expanded]).
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

  /// KPIs compactos do hero (4 peças). Largura vem do [Expanded] no pai.
  List<Widget> _portfolioHeroKpiTiles(
    BuildContext context, {
    required double th,
  }) {
    final accent = _portfolioAccentColor(context);
    final hasFilters = _filters != null && _hasActiveFilters();
    final hasSearch = _searchQuery.trim().isNotEmpty;
    final gatedGlobal = !hasFilters && !hasSearch;
    final m = _listedPropertyMetrics();
    final gs = _globalStats;

    if (gs != null && gatedGlobal) {
      return [
        _buildPortfolioStatTile(
          context,
          value: _compactIntFormatter.format(gs.total),
          label: 'No CRM',
          icon: Icons.apartment_rounded,
          accent: accent,
          tileHeight: th,
          dense: true,
        ),
        _buildPortfolioStatTile(
          context,
          value: _compactIntFormatter.format(gs.available),
          label: 'Disponíveis',
          icon: Icons.event_available_rounded,
          accent: AppColors.status.success,
          tileHeight: th,
          dense: true,
        ),
        _buildPortfolioStatTile(
          context,
          value: '${_properties.length}',
          label: 'Nesta página',
          icon: Icons.view_module_outlined,
          accent: accent,
          tileHeight: th,
          dense: true,
        ),
        _buildPortfolioStatTile(
          context,
          value: '${m.available}',
          label: 'Seleção · livres',
          icon: Icons.circle_outlined,
          accent: AppColors.status.success,
          tileHeight: th,
          dense: true,
        ),
      ];
    }

    return [
      _buildPortfolioStatTile(
        context,
        value: _compactIntFormatter.format(_total),
        label: 'Filtro',
        icon: Icons.filter_alt_outlined,
        accent: const Color(0xFF6366F1),
        tileHeight: th,
        dense: true,
      ),
      _buildPortfolioStatTile(
        context,
        value: '${_properties.length}',
        label: 'Nesta página',
        icon: Icons.view_module_outlined,
        accent: accent,
        tileHeight: th,
        dense: true,
      ),
      _buildPortfolioStatTile(
        context,
        value: '${m.available}',
        label: 'Seleção · livres',
        icon: Icons.circle_outlined,
        accent: AppColors.status.success,
        tileHeight: th,
        dense: true,
      ),
      _buildPortfolioStatTile(
        context,
        value: '${m.active}',
        label: 'Ativos',
        icon: Icons.verified_rounded,
        accent: AppColors.status.success,
        tileHeight: th,
        dense: true,
      ),
    ];
  }

  /// Indicadores que saíram do hero (menu ⋮ → Métricas detalhadas).
  List<Widget> _portfolioOverflowKpiTiles(
    BuildContext context, {
    required double tw,
    required double th,
  }) {
    final accent = _portfolioAccentColor(context);
    final hasFilters = _filters != null && _hasActiveFilters();
    final hasSearch = _searchQuery.trim().isNotEmpty;
    final gatedGlobal = !hasFilters && !hasSearch;
    final m = _listedPropertyMetrics();
    final gs = _globalStats;

    return [
      if (gs != null && gatedGlobal) ...[
        _buildPortfolioStatTile(
          context,
          value: _compactIntFormatter.format(gs.rented),
          label: 'Locação CRM',
          hint: 'Contratos ativos',
          icon: Icons.key_rounded,
          accent: const Color(0xFF818CF8),
          tileWidth: tw,
          tileHeight: th,
        ),
        _buildPortfolioStatTile(
          context,
          value: _compactIntFormatter.format(gs.sold),
          label: 'Vendas CRM',
          hint: 'Encerradas',
          icon: Icons.sell_outlined,
          accent: AppColors.status.info,
          tileWidth: tw,
          tileHeight: th,
        ),
      ],
      if (gs != null && !gatedGlobal) ...[
        _buildPortfolioStatTile(
          context,
          value: _compactIntFormatter.format(gs.total),
          label: 'No CRM',
          hint: 'Portfolio completo',
          icon: Icons.apartment_rounded,
          accent: accent,
          tileHeight: th,
        ),
        _buildPortfolioStatTile(
          context,
          value: _compactIntFormatter.format(gs.available),
          label: 'Disponíveis CRM',
          hint: 'Mercado',
          icon: Icons.event_available_rounded,
          accent: AppColors.status.success,
          tileHeight: th,
        ),
        _buildPortfolioStatTile(
          context,
          value: _compactIntFormatter.format(gs.rented),
          label: 'Locação CRM',
          hint: 'Contratos ativos',
          icon: Icons.key_rounded,
          accent: const Color(0xFF818CF8),
          tileWidth: tw,
          tileHeight: th,
        ),
        _buildPortfolioStatTile(
          context,
          value: _compactIntFormatter.format(gs.sold),
          label: 'Vendas CRM',
          hint: 'Encerradas',
          icon: Icons.sell_outlined,
          accent: AppColors.status.info,
          tileWidth: tw,
          tileHeight: th,
        ),
      ],
      _buildPortfolioStatTile(
        context,
        value: '${m.rented}',
        label: 'Seleção · locação',
        hint: '${m.featuredHighlights} destaques',
        icon: Icons.houseboat_outlined,
        accent: const Color(0xFFF59E0B),
        tileWidth: tw,
        tileHeight: th,
      ),
      _buildPortfolioStatTile(
        context,
        value: '${m.sold}',
        label: 'Seleção · vendas',
        hint: '${m.publishedOnline} públicos',
        icon: Icons.receipt_long_outlined,
        accent: AppColors.status.info,
        tileWidth: tw,
        tileHeight: th,
      ),
      _buildPortfolioStatTile(
        context,
        value: '${m.draft + m.pendingReview}',
        label: 'Pré-publicação',
        hint: m.pendingReview > 0
            ? '${m.draft} rasc. · ${m.pendingReview} em análise'
            : '${m.maintenance} revisão',
        icon: Icons.edit_note_rounded,
        accent: ThemeHelpers.textSecondaryColor(context),
        tileWidth: tw,
        tileHeight: th,
      ),
      if (m.avgRentPrice != null)
        _buildPortfolioStatTile(
          context,
          value: _currencyFormatter.format(m.avgRentPrice!),
          label: 'Média aluguel',
          hint: 'Nesta página',
          icon: Icons.payments_rounded,
          accent: const Color(0xFFEC4899),
          tileWidth: tw,
          tileHeight: th,
        ),
      if (m.avgSalePriceOnly != null)
        _buildPortfolioStatTile(
          context,
          value: _currencyFormatter.format(m.avgSalePriceOnly!),
          label: 'Média venda',
          hint: 'Nesta página',
          icon: Icons.storefront_rounded,
          accent: const Color(0xFF06B6D4),
          tileWidth: tw,
          tileHeight: th,
        ),
      if (m.avgAreaSqm != null)
        _buildPortfolioStatTile(
          context,
          value:
              '${m.avgAreaSqm!.toStringAsFixed(m.avgAreaSqm! >= 10 ? 0 : 1)} m²',
          label: 'Área média',
          hint: 'Declarada',
          icon: Icons.straighten_rounded,
          accent: AppColors.primary.primary,
          tileWidth: tw,
          tileHeight: th,
        ),
      if (gatedGlobal && gs != null)
        _buildPortfolioStatTile(
          context,
          value: '${m.active}',
          label: 'Ativos',
          hint: '${m.inactive} pausados',
          icon: Icons.verified_rounded,
          accent: AppColors.status.success,
          tileHeight: th,
        ),
    ];
  }

  /// Radar / KPIs / atalhos — hero alinhado ao painel principal (dashboard).
  Widget _buildPortfolioHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _portfolioAccentColor(context);
    final hasFilters = _filters != null && _hasActiveFilters();
    final hasSearch = _searchQuery.trim().isNotEmpty;
    final gatedGlobal = !hasFilters && !hasSearch;

    final quickActions = <Widget>[
      _buildQuickActionButton(
        context,
        icon: Icons.add_business_rounded,
        label: 'Novo imóvel',
        isPrimary: true,
        onPressed: _openPropertyCreateThenRefreshDrafts,
      ),
      _buildQuickActionButton(
        context,
        icon: Icons.folder_special_rounded,
        label:
            _localDraftCount > 0 ? 'Rascunhos ($_localDraftCount)' : 'Rascunhos',
        highlight: _localDraftCount > 0,
        onPressed: _openLocalDrafts,
      ),
      _buildQuickActionButton(
        context,
        icon: Icons.tune_rounded,
        label: hasFilters ? 'Filtros ativos' : 'Filtros',
        highlight: hasFilters,
        onPressed: () {
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            barrierColor: Colors.black54,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            clipBehavior: Clip.antiAlias,
            builder: (context) => PropertyFiltersDrawer(
              initialFilters: _filters,
              onFiltersChanged: (filters) {
                setState(() => _filters = filters);
                _loadProperties(refresh: true);
              },
            ),
          );
        },
      ),
    ];

    final subtitleParts = [
      DateFormat(
        "'Atualização' HH:mm · d MMMM",
        'pt_BR',
      ).format(DateTime.now()),
      if (_totalPages > 1) 'página $_currentPage de $_totalPages',
      if (_globalStats != null && gatedGlobal) 'KPIs sincronizados com o CRM',
      if (hasSearch)
        'busca ativa para “${_searchQuery.length > 32 ? '${_searchQuery.substring(0, 32)}…' : _searchQuery}”'
      else if (hasFilters)
        'filtro granular ativo'
      else if (!gatedGlobal)
        'filtros combinados',
    ].where((s) => s.trim().isNotEmpty).join(' · ');

    final headline =
        hasSearch ? 'Radar de imóveis' : 'Radar comercial Intellisys';

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
        final innerW =
            (w - padH * 2).clamp(0.0, double.infinity).toDouble();
        final kpiCols = innerW >= 360 ? 4 : 2;
        final gap = statSep;
        final statH = compact ? 72.0 : (w >= 520 ? 78.0 : 74.0);
        final statTiles = _portfolioHeroKpiTiles(
          context,
          th: statH,
        );

        final mainTitles = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'GESTÃO PORTFÓLIO',
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

        Widget pillRow() {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.start,
            children: _portfolioHeroContextPills(
              context,
              gatedGlobal: gatedGlobal,
              compact: compact,
            ),
          );
        }

        Widget insightBlock() => _buildPortfolioHeroInsight(
              context,
              gatedGlobal: gatedGlobal,
              hasSearch: hasSearch,
              hasFilters: hasFilters,
            );

        Widget actionsBar() {
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: quickActions,
          );
        }

        Widget heroTop;
        if (!spread) {
          heroTop = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _portfolioHeroLeadingIcon(context),
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
              Align(
                alignment: Alignment.centerRight,
                child: actionsBar(),
              ),
            ],
          );
        } else {
          heroTop = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _portfolioHeroLeadingIcon(context),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 52,
                          child: mainTitles,
                        ),
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
                    Expanded(
                      flex: 42,
                      child: pillRow(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 58,
                      child: insightBlock(),
                    ),
                  ],
                )
              else ...[
                pillRow(),
                const SizedBox(height: 10),
                insightBlock(),
              ],
              if (!actionsTop) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: actionsBar(),
                ),
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
                  : const [
                      Colors.transparent,
                      Colors.transparent,
                    ],
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
              ..._portfolioAmbientGlows(context),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  padH,
                  _kHeaderPadVTop,
                  padH,
                  12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    heroTop,
                    SizedBox(height: compact ? 8 : 10),
                    _buildHeroKpiStripe(statTiles, gap, kpiCols),
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
                                setState(() => _searchQuery = '');
                                _loadProperties(refresh: true);
                              },
                            ),
                          if (hasFilters)
                            _buildActiveContextChip(
                              context,
                              Icons.tune_rounded,
                              'Filtros aplicados',
                              onClear: () {
                                setState(() => _filters = null);
                                _loadProperties(refresh: true);
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

  Color _portfolioAccentColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFFF4D67)
        : AppColors.primary.primary;
  }

  List<Widget> _portfolioAmbientGlows(BuildContext context) {
    final accent = _portfolioAccentColor(context);
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

  _ListedPropertyMetrics _listedPropertyMetrics() {
    int available = 0;
    int rented = 0;
    int sold = 0;
    int draft = 0;
    int pendingReview = 0;
    int maintenance = 0;
    int active = 0;
    int inactive = 0;
    int featured = 0;
    int published = 0;
    int negotiation = 0;
    int sumPending = 0;
    double sumSale = 0;
    int countSale = 0;
    double sumRent = 0;
    int countRent = 0;
    double sumArea = 0;
    int countArea = 0;

    for (final p in _properties) {
      if (p.isActive) {
        active++;
      } else {
        inactive++;
      }
      if (p.isFeatured) featured++;
      if (p.isAvailableForSite == true) published++;
      if (p.acceptsNegotiation == true) negotiation++;
      if (p.hasPendingOffers == true) {
        sumPending += p.pendingOffersCount ?? 1;
      }
      switch (p.status) {
        case PropertyStatus.available:
          available++;
          break;
        case PropertyStatus.rented:
          rented++;
          break;
        case PropertyStatus.sold:
          sold++;
          break;
        case PropertyStatus.draft:
          draft++;
          break;
        case PropertyStatus.pendingApproval:
        case PropertyStatus.pendingOwnerAuthorization:
          pendingReview++;
          break;
        case PropertyStatus.maintenance:
          maintenance++;
          break;
      }
      if (p.salePrice != null) {
        sumSale += p.salePrice!;
        countSale++;
      }
      if (p.rentPrice != null) {
        sumRent += p.rentPrice!;
        countRent++;
      }
      if (p.totalArea > 0) {
        sumArea += p.totalArea;
        countArea++;
      }
    }

    return _ListedPropertyMetrics(
      available: available,
      rented: rented,
      sold: sold,
      draft: draft,
      pendingReview: pendingReview,
      maintenance: maintenance,
      active: active,
      inactive: inactive,
      featuredHighlights: featured,
      publishedOnline: published,
      negotiationFriendly: negotiation,
      sumOfferPending: sumPending,
      avgRentPrice: countRent > 0 ? sumRent / countRent : null,
      avgSalePriceOnly: countSale > 0 ? sumSale / countSale : null,
      avgAreaSqm: countArea > 0 ? sumArea / countArea : null,
    );
  }

  /// Cartões KPI do **hero** — alinhados às pills / glass do cabeçalho (sem gradiente forte).
  BoxDecoration _portfolioHeroKpiDecoration(BuildContext context, Color accent) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      color: isDark
          ? accent.withValues(alpha: 0.065)
          : ShellVisualTokens.dashboardGlassFill(context),
      border: Border.all(
        color: isDark
            ? accent.withValues(alpha: 0.14)
            : ShellVisualTokens.dashboardGlassBorder(context),
      ),
      boxShadow: isDark
          ? null
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.065),
                blurRadius: 14,
                offset: const Offset(0, 4),
                spreadRadius: -2,
              ),
            ],
    );
  }

  Widget _portfolioHeroKpiIconPlate(
    BuildContext context,
    IconData icon,
    Color accent,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const sz = 34.0;
    return Container(
      width: sz,
      height: sz,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: accent.withValues(alpha: isDark ? 0.14 : 0.1),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.26 : 0.24),
        ),
      ),
      child: Icon(icon, size: 18, color: accent),
    );
  }

  /// Alinhado ao `_buildSummaryCard` do dashboard (gradiente suave + borda glass).
  BoxDecoration _kpiMetricCardDecoration(
    BuildContext context,
    Color accent, {
    bool dense = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final r = dense ? 14.0 : 20.0;
    return BoxDecoration(
      borderRadius: BorderRadius.circular(r),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          accent.withValues(alpha: isDark ? 0.16 : 0.11),
          accent.withValues(alpha: isDark ? 0.05 : 0.04),
        ],
      ),
      border: Border.all(color: ShellVisualTokens.portfolioGlassBorder(context)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.075),
          blurRadius: isDark ? 14 : 14,
          offset: Offset(0, isDark ? 7 : 4),
          spreadRadius: isDark ? -3 : -2,
        ),
      ],
    );
  }

  Widget _portfolioHeroLeadingIcon(BuildContext context) {
    final accent = _portfolioAccentColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: [
            accent,
            const Color(0xFF7C3AED),
          ],
        ),
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
      child: const Icon(Icons.maps_home_work_outlined, color: Colors.white, size: 22),
    );
  }

  Widget _buildPortfolioHeroPill(BuildContext context, IconData icon, String label) {
    final accent = _portfolioAccentColor(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderCol = ThemeHelpers.borderColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isDark ? accent.withValues(alpha: 0.07) : ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark ? accent.withValues(alpha: 0.14) : borderCol.withValues(alpha: 0.55),
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

  List<Widget> _portfolioHeroContextPills(
    BuildContext context, {
    required bool gatedGlobal,
    required bool compact,
  }) {
    final pageChip = _totalPages > 1
        ? 'Pág. $_currentPage · $_totalPages'
        : '${_compactIntFormatter.format(_properties.length)} neste painel';
    return [
      _buildPortfolioHeroPill(
        context,
        gatedGlobal ? Icons.hub_outlined : Icons.filter_alt_outlined,
        gatedGlobal ? 'Portfolio CRM' : 'Contexto filtrado',
      ),
      _buildPortfolioHeroPill(
        context,
        Icons.visibility_outlined,
        compact && pageChip.length > 18 ? '${_properties.length} itens' : pageChip,
      ),
    ];
  }

  Widget _buildPortfolioHeroInsight(
    BuildContext context, {
    required bool gatedGlobal,
    required bool hasSearch,
    required bool hasFilters,
  }) {
    final theme = Theme.of(context);
    final gs = _globalStats;
    final m = _listedPropertyMetrics();

    late final IconData insightIcon;
    late final Color iconBg;
    late final Color iconFg;
    late final String body;

    if (hasSearch) {
      insightIcon = Icons.manage_search_rounded;
      iconBg = ThemeHelpers.borderColor(context).withValues(alpha: 0.2);
      iconFg = ThemeHelpers.textSecondaryColor(context);
      body =
          'Resultados combinam busca textual com os filtros deste momento — use os KPIs para validar distribuição na página atual.';
    } else if (hasFilters) {
      insightIcon = Icons.tune_rounded;
      iconBg = _portfolioAccentColor(context).withValues(alpha: 0.14);
      iconFg = _portfolioAccentColor(context);
      body =
          'Métricas da listagem espelham o filtro granular. Limpe os chips de contexto ou redefina os filtros para alinhar ao CRM global.';
    } else if (gs != null && gatedGlobal) {
      insightIcon = Icons.auto_graph_rounded;
      iconFg = AppColors.status.success;
      iconBg = AppColors.status.success.withValues(alpha: 0.14);
      body =
          '${_compactIntFormatter.format(gs.total)} imóveis catalogados · '
          '${_compactIntFormatter.format(gs.available)} disponíveis neste panorama · '
          '${m.negotiationFriendly} aceitam negociação na página atual.';
    } else {
      insightIcon = Icons.layers_outlined;
      iconFg = ThemeHelpers.textSecondaryColor(context);
      iconBg = ThemeHelpers.borderColor(context).withValues(alpha: 0.18);
      body = '$_total registros combinam filtros pesquisáveis · '
          '${m.available} listados livres · ${m.negotiationFriendly} flexíveis a proposta.';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: iconBg,
            ),
            child: Icon(insightIcon, color: iconFg, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'INSIGHT PORTFÓLIO',
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

  Widget _buildPortfolioIconBadge(
    BuildContext context,
    IconData icon,
    Color color, {
    double size = 32,
    double iconSize = 16,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.33),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.95),
            color.withValues(alpha: 0.62),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.22),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: iconSize),
    );
  }

  Widget _buildPortfolioStatTile(
    BuildContext context, {
    required String value,
    required String label,
    String? hint,
    required IconData icon,
    required Color accent,
    double? tileWidth,
    double? tileHeight,
    bool dense = false,
  }) {
    final theme = Theme.of(context);
    final tw = tileWidth ?? (dense ? double.infinity : _kStatTileWidth);
    final th = tileHeight ?? _kStatCarouselHeight;
    final pad = dense
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
        : const EdgeInsets.fromLTRB(12, 10, 12, 10);
    final showHint = !dense && hint != null && hint.isNotEmpty;

    final Widget inner;
    if (dense) {
      inner = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _portfolioHeroKpiIconPlate(context, icon, accent),
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
      );
    } else {
      inner = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildPortfolioIconBadge(
                context,
                icon,
                accent,
                size: 32,
                iconSize: 16,
              ),
              Container(
                width: 38,
                height: 5,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: LinearGradient(
                    colors: [
                      accent.withValues(alpha: 0.22),
                      accent.withValues(alpha: 0.82),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    height: 1.02,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.35,
                  fontSize: 10.5,
                ),
              ),
              if (showHint) ...[
                const SizedBox(height: 2),
                Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context)
                        .withValues(alpha: 0.88),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
              ],
            ],
          ),
        ],
      );
    }

    final content = SizedBox(
      width: tw,
      height: th,
      child: Container(
        padding: pad,
        decoration: dense
            ? _portfolioHeroKpiDecoration(context, accent)
            : _kpiMetricCardDecoration(context, accent, dense: false),
        child: inner,
      ),
    );

    if (!dense && hint != null && hint.length > 26) {
      return Tooltip(
        message: '$label · $hint',
        waitDuration: const Duration(milliseconds: 450),
        child: content,
      );
    }
    return content;
  }

  void _showPortfolioOverflowMetricsSheet(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.sizeOf(context);
    const padH = 20.0;
    final innerW = (mq.width - padH * 2).clamp(0.0, double.infinity);
    const gap = 10.0;
    final kpiCols = innerW >= 520 ? 3 : 2;
    final kpiTileRaw = (innerW - gap * (kpiCols - 1)) / kpiCols;
    final kpiTileW = kpiTileRaw.clamp(100.0, 168.0);
    const tileH = 104.0;

    final tiles = _portfolioOverflowKpiTiles(
      context,
      tw: kpiTileW,
      th: tileH,
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (ctx) {
        final maxH = MediaQuery.sizeOf(ctx).height * 0.72;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(padH, 10, padH, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: ThemeHelpers.borderColor(ctx).withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Text(
                  'Métricas detalhadas',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Indicadores desta página e panorama do CRM.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(ctx),
                  ),
                ),
                const SizedBox(height: 14),
                if (tiles.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Text(
                      'Sem métricas adicionais neste contexto.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  )
                else
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: tiles,
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

  void _showOptimizationDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (context) => _buildOptimizationDialog(context),
    );
  }

  Widget _buildOptimizationDialog(BuildContext context) {
    final theme = Theme.of(context);
    String? selectedFocus;
    bool isOptimizing = false;

    return StatefulBuilder(
      builder: (context, setState) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.trending_up_rounded,
                        color: AppColors.primary.primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Otimização de Portfólio',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: isOptimizing ? null : () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Selecione o foco da otimização:',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                RadioListTile<String>(
                  title: const Text('Vendas Rápidas'),
                  subtitle: const Text(
                    'Priorizar propriedades com maior potencial de venda rápida',
                  ),
                  value: 'sales_speed',
                  groupValue: selectedFocus,
                  onChanged: isOptimizing
                      ? null
                      : (value) {
                          setState(() {
                            selectedFocus = value;
                          });
                        },
                ),
                RadioListTile<String>(
                  title: const Text('Maximizar Lucro'),
                  subtitle: const Text(
                    'Priorizar propriedades com maior rentabilidade',
                  ),
                  value: 'profitability',
                  groupValue: selectedFocus,
                  onChanged: isOptimizing
                      ? null
                      : (value) {
                          setState(() {
                            selectedFocus = value;
                          });
                        },
                ),
                RadioListTile<String>(
                  title: const Text('Cobertura de Mercado'),
                  subtitle: const Text(
                    'Otimizar para melhor cobertura de mercado',
                  ),
                  value: 'market_coverage',
                  groupValue: selectedFocus,
                  onChanged: isOptimizing
                      ? null
                      : (value) {
                          setState(() {
                            selectedFocus = value;
                          });
                        },
                ),
                RadioListTile<String>(
                  title: const Text('Balanceado'),
                  subtitle: const Text(
                    'Equilíbrio entre vendas rápidas e lucro',
                  ),
                  value: 'balanced',
                  groupValue: selectedFocus,
                  onChanged: isOptimizing
                      ? null
                      : (value) {
                          setState(() {
                            selectedFocus = value;
                          });
                        },
                ),
                const SizedBox(height: 20),
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isOptimizing || selectedFocus == null
                            ? null
                            : () async {
                                setState(() {
                                  isOptimizing = true;
                                });

                                try {
                                  final aiService = AiService.instance;
                                  final response = await aiService
                                      .optimizePortfolio(
                                        PortfolioOptimizationRequest(
                                          focus: selectedFocus!,
                                        ),
                                      );

                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    if (response.success &&
                                        response.data != null) {
                                      _showOptimizationResults(
                                        context,
                                        response.data!,
                                      );
                                    } else {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            response.message ??
                                                'Erro ao otimizar portfólio',
                                          ),
                                          backgroundColor:
                                              AppColors.status.error,
                                        ),
                                      );
                                    }
                                  }
                                } catch (e) {
                                  debugPrint('Erro na otimização: $e');
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Erro ao conectar com o servidor',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                        icon: isOptimizing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.trending_up),
                        label: Text(
                          isOptimizing ? 'Otimizando...' : 'Otimizar',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: isOptimizing
                            ? null
                            : () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                        label: const Text('Cancelar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showOptimizationResults(BuildContext context, dynamic results) {
    final theme = Theme.of(context);

    if (results is List<PortfolioOptimizationResponse>) {
      // Múltiplas propriedades
      final resultsList = results;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        barrierColor: Colors.black54,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        clipBehavior: Clip.antiAlias,
        builder: (context) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.9,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        'Resultados da Otimização',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.25,
                            ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: resultsList.length,
                    itemBuilder: (context, index) {
                      final result = resultsList[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          title: Text(result.propertyTitle),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Score: ${result.priorityScore.toStringAsFixed(1)}%',
                              ),
                              if (result.recommendedActions.isNotEmpty)
                                Text(
                                  result.recommendedActions.first,
                                  style: theme.textTheme.bodySmall,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.arrow_forward),
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.of(
                                context,
                              ).pushNamed(
                                AppRoutes.propertyDetails(result.propertyId),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    label: const Text('Fechar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else if (results is PortfolioOptimizationResponse) {
      // Uma única propriedade
      final result = results;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        barrierColor: Colors.black54,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        clipBehavior: Clip.antiAlias,
        builder: (context) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          'Resultados da Otimização',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.25,
                              ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    result.propertyTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Score: ${result.priorityScore.toStringAsFixed(1)}%',
                    style: theme.textTheme.bodyLarge,
                  ),
                  if (result.recommendedActions.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Ações Recomendadas:',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    ...result.recommendedActions.map(
                      (action) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Icon(
                                Icons.chevron_right_rounded,
                                size: 16,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                action,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  height: 1.38,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.of(
                              context,
                            ).pushNamed(
                              AppRoutes.propertyDetails(result.propertyId),
                            );
                          },
                          icon: const Icon(Icons.visibility),
                          label: const Text('Ver Propriedade'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                          label: const Text('Fechar'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }

  Widget _buildSkeleton(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final cols = _exploreGridCrossAxisCount(w);
    final aspect = _exploreGridChildAspectRatio(cols);
    final hPad = w < 360 ? 10.0 : (cols >= 3 ? 14.0 : 12.0);
    final spacingH = cols >= 3 ? 9.0 : 11.0;
    final spacingV = cols >= 3 ? 11.0 : 13.0;
    final narrow = w < 360;

    Widget gridTile() {
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const SkeletonBox(
              width: double.infinity,
              height: double.infinity,
              borderRadius: 20,
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SkeletonText(width: 118, height: 13, borderRadius: 6),
                  const SizedBox(height: 8),
                  SkeletonText(width: w * 0.42, height: 11, borderRadius: 5),
                  const SizedBox(height: 6),
                  SkeletonText(width: w * 0.24, height: 9, borderRadius: 4),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SkeletonBox(
                  height: 48,
                  borderRadius: 12,
                  margin: EdgeInsets.only(bottom: narrow ? 12 : 16),
                ),
              ),
              SizedBox(width: narrow ? 8 : 12),
              SkeletonBox(
                width: narrow ? 44 : 48,
                height: narrow ? 44 : 48,
                borderRadius: 12,
                margin: EdgeInsets.only(bottom: narrow ? 12 : 16),
              ),
            ],
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: spacingH,
              mainAxisSpacing: spacingV,
              childAspectRatio: aspect,
            ),
            itemCount: 10,
            itemBuilder: (_, _) => gridTile(),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final err = AppColors.status.error;
    final borderCol = ThemeHelpers.borderColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final bg = isDark
        ? AppColors.background.backgroundSecondaryDarkMode
        : AppColors.background.backgroundSecondary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
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
                children: [
                  Container(
                    height: 3,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          err.withValues(alpha: 0.82),
                          err.withValues(alpha: 0.18),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: err.withValues(alpha: 0.09),
                            border: Border.all(
                              color: err.withValues(alpha: 0.2),
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            Icons.error_outline_rounded,
                            size: 28,
                            color: err.withValues(alpha: 0.92),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Não foi possível carregar',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.25,
                            color: ThemeHelpers.textColor(context),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage ??
                              'Verifique sua conexão ou tente novamente.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: muted,
                            height: 1.45,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            onPressed: () => _loadProperties(refresh: true),
                            icon: Icon(
                              Icons.refresh_rounded,
                              size: 19,
                              color: AppColors.primary.primary,
                            ),
                            label: const Text(
                              'Tentar novamente',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
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

  bool _hasActiveFilters() {
    if (_filters == null) return false;
    return _filters!.type != null ||
        _filters!.status != null ||
        _filters!.city != null ||
        _filters!.neighborhood != null ||
        _filters!.minPrice != null ||
        _filters!.maxPrice != null ||
        _filters!.minArea != null ||
        _filters!.maxArea != null;
  }

  void _showSearchBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        'Buscar Propriedades',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.25,
                            ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'Digite palavras-chave, endereço, código...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
                onSubmitted: (value) {
                  _performSearch(value);
                  Navigator.of(context).pop();
                },
              ),
              const SizedBox(height: 20),
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _performSearch(_searchController.text);
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.search),
                      label: const Text('Buscar'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                            _loadProperties(refresh: true);
                            Navigator.of(context).pop();
                          },
                          icon: const Icon(Icons.clear),
                          label: const Text('Limpar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                          label: const Text('Cancelar'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _performSearch(String query) {
    setState(() {
      _searchQuery = query;
    });
    _loadProperties(refresh: true);
  }

  /// Faixa horizontal antes da grade — quebra o ritmo “tudo empilhado”.
  Widget _buildDiscoverHorizontalStrip(
    BuildContext context,
    ThemeData theme, {
    required double horizontalPad,
    required int columns,
  }) {
    final lead = _discoverLeadCount(_properties.length);
    if (lead <= 0) return const SizedBox.shrink();

    final w = MediaQuery.sizeOf(context).width;
    final aspect = _exploreGridChildAspectRatio(columns);
    final cardW = (w * 0.74).clamp(258.0, 312.0);
    final cardH = cardW / aspect;
    final muted = ThemeHelpers.textSecondaryColor(context);

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(horizontalPad, 0, horizontalPad, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.view_carousel_outlined,
                      size: 18,
                      color: AppColors.primary.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Propriedades em destaque — percorra ao lado',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.25,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  'Abaixo ficam as demais propriedades.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: muted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: cardH,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(horizontalPad, 0, horizontalPad + 8, 0),
              itemCount: lead,
              itemBuilder: (context, i) {
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: cardW,
                    child: AspectRatio(
                      aspectRatio: aspect,
                      child: _buildPropertyExploreTile(
                        context,
                        theme,
                        _properties[i],
                        featuredStripLayout: true,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Radar e grade explorável no mobile, estilo galeria; sem fila larga vertical de propriedades.
  Widget _buildScrollablePropertiesViewport(BuildContext context) {
    final theme = Theme.of(context);
    final w = MediaQuery.sizeOf(context).width;
    final cols = _exploreGridCrossAxisCount(w);
    final horizontal = w < 360 ? 10.0 : (cols >= 3 ? 14.0 : 12.0);
    final n = _properties.length;
    final aspect = _exploreGridChildAspectRatio(cols);
    final lead = _discoverLeadCount(n);
    final gridCount = n - lead;

    return RefreshIndicator(
      onRefresh: () => _loadProperties(refresh: true),
      color: AppColors.primary.primary,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(child: _buildPortfolioHeader(context)),
          SliverToBoxAdapter(
            child: _buildDiscoverHorizontalStrip(
              context,
              theme,
              horizontalPad: horizontal,
              columns: cols,
            ),
          ),
          if (lead > 0 && gridCount > 0)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Divider(
                        color: theme.dividerColor.withValues(alpha: 0.38),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'Explorar o restante',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Divider(
                        color: theme.dividerColor.withValues(alpha: 0.38),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(horizontal, lead > 0 ? 2 : 14, horizontal, 8),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: cols >= 3 ? 9 : 11,
                mainAxisSpacing: cols >= 3 ? 11 : 13,
                childAspectRatio: aspect,
              ),
              itemCount: gridCount,
              itemBuilder: (context, index) {
                return _buildPropertyExploreTile(
                  context,
                  theme,
                  _properties[lead + index],
                  featuredStripLayout: false,
                );
              },
            ),
          ),
          if (_isLoadingMore)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.primary.primary,
                    ),
                  ),
                ),
              ),
            ),
          if (_totalPages > 1)
            SliverToBoxAdapter(
              child: KeyedSubtree(
                key: const ValueKey<String>('properties_pagination_footer'),
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: _buildPagination(context),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 10)),
        ],
      ),
    );
  }

  Widget _buildEmptyPropertiesState(BuildContext context, ThemeData theme) {
    final accent = _portfolioAccentColor(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderCol = ThemeHelpers.borderColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final bg = isDark
        ? AppColors.background.backgroundSecondaryDarkMode
        : AppColors.background.backgroundSecondary;
    final obstructed =
        _searchQuery.trim().isNotEmpty || (_filters != null && _hasActiveFilters());

    void clearFiltersAndSearch() {
      _searchController.clear();
      setState(() {
        _searchQuery = '';
        _filters = null;
      });
      _loadProperties(refresh: true);
    }

    final eyebrow = obstructed ? 'Resultados' : 'Portfólio';
    final title = obstructed
        ? 'Nenhum imóvel encontrado'
        : 'Nenhum imóvel cadastrado';
    final subtitle = obstructed
        ? 'Amplie os critérios ou volte ao panorama completo.'
        : 'Inclua um endereço para passar a gerir ofertas e status daqui.';

    Widget content() {
      return DecoratedBox(
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
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                color: accent.withValues(alpha: isDark ? 0.12 : 0.1),
                                border: Border.all(
                                  color: accent.withValues(alpha: 0.22),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: accent.withValues(alpha: 0.14),
                                    blurRadius: 12,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Icon(
                                obstructed
                                    ? Icons.manage_search_rounded
                                    : Icons.layers_outlined,
                                size: 26,
                                color: accent,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                  const SizedBox(height: 5),
                                  Text(
                                    title,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.35,
                                      height: 1.12,
                                      color: ThemeHelpers.textColor(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                    const SizedBox(height: 14),
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: 6,
                      endIndent: 6,
                      color: borderCol.withValues(alpha: 0.42),
                    ),
                    const SizedBox(height: 13),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: muted,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () async {
                        final r = await Navigator.of(context)
                            .pushNamed(AppRoutes.propertyCreate);
                        if (context.mounted) {
                          await _onPropertyWizardReturned(r);
                        }
                      },
                      icon: Icon(
                        obstructed ? Icons.add_rounded : Icons.add_home_rounded,
                        size: 20,
                      ),
                      label: Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: Text(
                          obstructed
                              ? 'Cadastrar imóvel'
                              : 'Criar primeiro imóvel',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                        elevation: 0,
                      ),
                    ),
                    if (obstructed) ...[
                      const SizedBox(height: 9),
                      OutlinedButton.icon(
                        onPressed: clearFiltersAndSearch,
                        icon: Icon(
                          Icons.filter_alt_off_outlined,
                          size: 19,
                          color: accent.withValues(alpha: 0.94),
                        ),
                        label: const Text(
                          'Limpar busca e filtros',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: accent,
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                          side: BorderSide(
                            color: accent.withValues(alpha: 0.38),
                          ),
                          backgroundColor: accent.withValues(
                            alpha: isDark ? 0.06 : 0.065,
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
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadProperties(refresh: true),
      color: accent,
      displacement: 44,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 36, 20, 32),
        children: [
          LayoutBuilder(
            builder: (_, c) => Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: c.maxWidth > 440 ? 380 : double.infinity,
                ),
                child: content(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Resumo editorial (sem „grade de formulário”) — detalhe completo na ficha.
  String? _editorialSpecsLine(Property property) {
    final parts = <String>[];
    if (property.bedrooms != null && property.bedrooms! > 0) {
      parts.add('${property.bedrooms} qt');
    }
    if (property.bathrooms != null && property.bathrooms! > 0) {
      parts.add('${property.bathrooms} ban');
    }
    if (property.parkingSpaces != null && property.parkingSpaces! > 0) {
      parts.add('${property.parkingSpaces} vag');
    }
    if (property.totalArea > 0) {
      parts.add('${property.totalArea.toInt()} m²');
    }
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  /// Localização curta só para preview na grade (bairro · cidade quando existir).
  String _compactLocationLine(Property property) {
    final n = property.neighborhood.trim();
    final c = property.city.trim();
    final s =
        (n.isNotEmpty && c.isNotEmpty) ? '$n · $c' : _formatPropertyLocation(property);
    if (s.length <= 38) return s;
    return '${s.substring(0, 36)}…';
  }

  List<BoxShadow> _exploreTileBoxShadows(bool isDark, bool featuredStripLayout) {
    if (!featuredStripLayout) {
      return [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.42 : 0.08),
          blurRadius: isDark ? 18 : 12,
          offset: const Offset(0, 8),
          spreadRadius: -3,
        ),
      ];
    }
    final primary = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
    return [
      BoxShadow(
        color: primary.withValues(alpha: isDark ? 0.26 : 0.2),
        blurRadius: 28,
        offset: const Offset(0, 11),
        spreadRadius: -7,
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.48 : 0.1),
        blurRadius: isDark ? 22 : 16,
        offset: const Offset(0, 12),
        spreadRadius: -4,
      ),
    ];
  }

  LinearGradient _exploreTileFeaturedRingGradient(bool isDark) {
    final p = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
    final pLight = isDark
        ? AppColors.primary.primaryLightDarkMode
        : AppColors.primary.primaryLight;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        pLight.withValues(alpha: 0.85),
        const Color(0xFFFFB74D).withValues(alpha: 0.55),
        p.withValues(alpha: 0.75),
      ],
      stops: const [0.0, 0.45, 1.0],
    );
  }

  Widget _buildPropertyFeaturedChip({required bool stripLayout}) {
    final compact = !stripLayout;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 9,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 10 : 14),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFE082),
            Color(0xFFFFA000),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.55),
          width: 0.85,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFA000).withValues(alpha: 0.38),
            blurRadius: compact ? 6 : 10,
            offset: Offset(0, compact ? 2 : 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.star_rounded,
            size: compact ? 12 : 14,
            color: const Color(0xFF4E342E),
          ),
          if (!compact) ...[
            const SizedBox(width: 4),
            Text(
              'Em destaque',
              style: TextStyle(
                color: const Color(0xFF3E2723),
                fontSize: 10,
                fontWeight: FontWeight.w900,
                height: 1,
                letterSpacing: -0.15,
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(left: 1),
              child: Text(
                'Destaque',
                style: TextStyle(
                  color: const Color(0xFF3E2723),
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  letterSpacing: -0.1,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Célula da grade: foto cheia + overlay (explorar, não lista linear).
  /// [featuredStripLayout] ativa moldura luminosa + overlay na faixa de destaques.
  Widget _buildPropertyExploreTile(
    BuildContext context,
    ThemeData theme,
    Property property, {
    bool featuredStripLayout = false,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final price = _formatMainPrice(property);
    final specs = _editorialSpecsLine(property);
    final locCompact = _compactLocationLine(property);
    const innerRadius = 20.0;
    final ringPad = featuredStripLayout ? 1.5 : 0.0;
    final outerRadius = innerRadius + ringPad;

    final inner = ClipRRect(
      borderRadius: BorderRadius.circular(innerRadius),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () =>
              Navigator.of(context).pushNamed(AppRoutes.propertyDetails(property.id)),
          onLongPress: () {
            HapticFeedback.mediumImpact();
            _showPropertyQuickActionsSheet(context, theme, property);
          },
          splashColor: AppColors.primary.primary.withValues(alpha: 0.18),
          highlightColor: Colors.white.withValues(alpha: 0.06),
          child: Ink(
            decoration: BoxDecoration(
              border: Border.all(
                color: featuredStripLayout
                    ? Colors.white.withValues(alpha: isDark ? 0.12 : 0.24)
                    : ShellVisualTokens.propertyListCardBorder(context),
                width: featuredStripLayout ? 0.85 : 1,
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (property.mainImage != null)
                  ShimmerImage(
                    imageUrl: property.mainImage!.url,
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.cover,
                    errorWidget: _buildPropertyImageFallback(context, theme),
                  )
                else
                  _buildPropertyImageFallback(context, theme),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: featuredStripLayout
                          ? const [0.0, 0.28, 0.72, 1.0]
                          : const [0.0, 0.32, 1.0],
                      colors: featuredStripLayout
                          ? [
                              Colors.black.withValues(alpha: 0.5),
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.35),
                              Colors.black.withValues(alpha: 0.92),
                            ]
                          : [
                              Colors.black.withValues(alpha: 0.52),
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.9),
                            ],
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(-0.75, -0.9),
                          radius: 1.15,
                          colors: [
                            Colors.white.withValues(
                              alpha: featuredStripLayout ? 0.09 : 0.05,
                            ),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 7,
                  left: 7,
                  right: 50,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (property.isFeatured) ...[
                        if (featuredStripLayout)
                          _buildPropertyFeaturedChip(stripLayout: true)
                        else
                          Flexible(
                            child: FittedBox(
                              alignment: Alignment.centerLeft,
                              fit: BoxFit.scaleDown,
                              child: _buildPropertyFeaturedChip(
                                stripLayout: false,
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: _buildPropertyActionsMenu(context, theme, property),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 9,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        price.value,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                          letterSpacing: -0.35,
                          fontSize: featuredStripLayout ? 14.25 : 13.5,
                          shadows: const [
                            Shadow(
                              offset: Offset(0, 1),
                              blurRadius: 10,
                              color: Colors.black87,
                            ),
                            Shadow(
                              offset: Offset(0, 2),
                              blurRadius: 18,
                              color: Colors.black54,
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      MatchesBadge(
                        propertyId: property.id,
                        onClick: () => Navigator.pushNamed(
                          context,
                          AppRoutes.matchesByProperty(property.id),
                        ),
                        child: Text(
                          property.title,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.97),
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                            fontSize: featuredStripLayout ? 11.75 : 11.25,
                            shadows: const [
                              Shadow(
                                offset: Offset(0, 1),
                                blurRadius: 8,
                                color: Colors.black54,
                              ),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        locCompact,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white.withValues(
                            alpha: featuredStripLayout ? 0.76 : 0.72,
                          ),
                          fontWeight: FontWeight.w600,
                          fontSize: featuredStripLayout ? 9.25 : 9,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (specs != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          specs,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white.withValues(
                              alpha: featuredStripLayout ? 0.66 : 0.62,
                            ),
                            fontWeight: FontWeight.w700,
                            fontSize: featuredStripLayout ? 8.75 : 8.5,
                            height: 1.05,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
    );

    if (featuredStripLayout) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(outerRadius),
          boxShadow: _exploreTileBoxShadows(isDark, true),
          gradient: _exploreTileFeaturedRingGradient(isDark),
        ),
        padding: EdgeInsets.all(ringPad),
        child: inner,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(innerRadius),
        boxShadow: _exploreTileBoxShadows(isDark, false),
      ),
      child: inner,
    );
  }


  Widget _buildPropertyImageFallback(BuildContext context, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
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
              : [
                  AppColors.background.backgroundSecondary,
                  AppColors.background.background,
                ],
        ),
      ),
      child: Center(
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.primary.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Icon(
            Icons.home_work_outlined,
            size: 36,
            color: AppColors.primary.primary,
          ),
        ),
      ),
    );
  }

  /// Menu contextual estilo Pinterest: bottom sheet com ações conforme permissões (`property:*`, `match:view`).
  Future<void> _showPropertyQuickActionsSheet(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) async {
    final access = ModuleAccessService.instance;
    final canEdit = access.hasPermission('property:update');
    final canDelete = access.hasPermission('property:delete');
    final canMatches = access.hasPermission('match:view') &&
        access.isModuleAvailableForCompany('match_system');

    // O menu abre para todos (igual ao toque no cartão). Cada ação continua
    // condicionada a permissões abaixo (ex.: excluir só com property:delete).

    final parentContext = context;
    final isDark = theme.brightness == Brightness.dark;
    final primary =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final err = theme.colorScheme.error;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (sheetContext) {
        final padBottom = MediaQuery.paddingOf(sheetContext).bottom;

        Widget sheetTile({
          required _PropertyActionMenuRow row,
          required VoidCallback onTap,
        }) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(20),
                child: Ink(
                  decoration: BoxDecoration(
                    color: isDark
                        ? theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.55)
                        : ShellVisualTokens.dashboardGlassFill(context),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark
                          ? ThemeHelpers.borderColor(context)
                              .withValues(alpha: 0.35)
                          : ShellVisualTokens.dashboardGlassBorder(context),
                    ),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                  child: row,
                ),
              ),
            ),
          );
        }

        return DraggableScrollableSheet(
          initialChildSize: 0.46,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (ctx, scrollController) {
            return DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 28,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      width: 42,
                      height: 5,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 8, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            width: 58,
                            height: 58,
                            child: property.mainImage != null
                                ? ShimmerImage(
                                    imageUrl: property.mainImage!.url,
                                    width: 58,
                                    height: 58,
                                    fit: BoxFit.cover,
                                  )
                                : ColoredBox(
                                    color: theme
                                        .colorScheme.surfaceContainerHighest,
                                    child: Icon(
                                      LucideIcons.building2,
                                      color: primary,
                                      size: 28,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                property.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _compactLocationLine(property),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: ThemeHelpers.textSecondaryColor(
                                    sheetContext,
                                  ),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                          tooltip: 'Fechar',
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 18 + padBottom),
                      children: [
                        // Sempre disponível: alinhado ao onTap do tile (sem checagem extra).
                        sheetTile(
                          row: _PropertyActionMenuRow(
                            icon: LucideIcons.layoutGrid,
                            iconBackground:
                                primary.withValues(alpha: isDark ? 0.2 : 0.12),
                            iconColor: primary,
                            title: 'Abrir ficha',
                            subtitle:
                                'Detalhes, fotos, documentos e histórico do imóvel',
                          ),
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            Future.microtask(() {
                              if (!mounted || !parentContext.mounted) return;
                              Navigator.of(parentContext).pushNamed(
                                AppRoutes.propertyDetails(property.id),
                              );
                            });
                          },
                        ),
                        if (canMatches)
                          sheetTile(
                            row: _PropertyActionMenuRow(
                              icon: LucideIcons.sparkles,
                              iconBackground:
                                  primary.withValues(alpha: isDark ? 0.2 : 0.12),
                              iconColor: primary,
                              title: 'Matches',
                              subtitle:
                                  'Clientes compatíveis com este imóvel',
                            ),
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              Future.microtask(() {
                                if (!mounted || !parentContext.mounted) return;
                                Navigator.of(parentContext).pushNamed(
                                  AppRoutes.matchesByProperty(property.id),
                                );
                              });
                            },
                          ),
                        if (canEdit)
                          sheetTile(
                            row: _PropertyActionMenuRow(
                              icon: LucideIcons.pencil,
                              iconBackground:
                                  primary.withValues(alpha: isDark ? 0.2 : 0.12),
                              iconColor: primary,
                              title: 'Editar imóvel',
                              subtitle:
                                  'Dados, valores, proprietário e galeria',
                            ),
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              Future.microtask(() {
                                if (!mounted || !parentContext.mounted) return;
                                Navigator.of(parentContext).pushNamed(
                                  '/properties/${property.id}/edit',
                                );
                              });
                            },
                          ),
                        if (canDelete)
                          sheetTile(
                            row: _PropertyActionMenuRow(
                              icon: LucideIcons.trash2,
                              iconBackground:
                                  err.withValues(alpha: isDark ? 0.18 : 0.12),
                              iconColor: err,
                              title: 'Excluir permanentemente',
                              subtitle:
                                  'Remove o imóvel do portfólio da empresa',
                              isDestructive: true,
                            ),
                            onTap: () async {
                              Navigator.of(sheetContext).pop();
                              await Future<void>.delayed(Duration.zero);
                              if (!mounted || !parentContext.mounted) return;
                              await _confirmAndDeleteProperty(
                                parentContext,
                                property,
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPropertyActionsMenu(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          _showPropertyQuickActionsSheet(context, theme, property);
        },
        borderRadius: BorderRadius.circular(16),
        child: Tooltip(
          message: 'Opções do imóvel',
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: const Icon(
              Icons.more_horiz_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmAndDeleteProperty(
    BuildContext context,
    Property property,
  ) async {
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(22),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.status.error.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.delete_outline_rounded, color: AppColors.status.error),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Excluir imóvel',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context, false),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Tem certeza que deseja excluir "${property.title}"? Esta ação não pode ser desfeita.',
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Excluir imóvel'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.status.error,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Cancelar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirm == true && mounted) {
      final response = await _propertyService.deleteProperty(property.id);
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);

      if (response.success) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Propriedade excluída com sucesso')),
        );
        _loadProperties(refresh: true);
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(response.message ?? 'Erro ao excluir propriedade'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    }
  }

  Widget _buildActiveContextChip(
    BuildContext context,
    IconData icon,
    String label, {
    VoidCallback? onClear,
  }) {
    final theme = Theme.of(context);
    final accent = _portfolioAccentColor(context);
    final chipMaxW =
        (MediaQuery.sizeOf(context).width * 0.52).clamp(96.0, 220.0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: chipMaxW),
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onClear != null) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: onClear,
              borderRadius: BorderRadius.circular(10),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.close_rounded, size: 14),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Item do menu ⋮ — acabamento premium (gradiente, borda luminosa, ícone halo).
  Widget _buildPremiumAiSearchMenuHighlight(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? const [
              Color(0xFF3730A3),
              Color(0xFF5B21B6),
              Color(0xFF0369A1),
              Color(0xFF0F766E),
            ]
          : const [
              Color(0xFFF8FAFC),
              Color(0xFFEEF2FF),
              Color(0xFFF5F3FF),
              Color(0xFFECFEFF),
            ],
      stops: const [0.0, 0.32, 0.68, 1.0],
    );
    final borderColor = Color.lerp(
      const Color(0xFF67E8F9),
      const Color(0xFFC084FC),
      0.45,
    )!.withValues(alpha: isDark ? 0.5 : 0.55);

    Widget sparkleIcon() {
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              Colors.white.withValues(alpha: isDark ? 0.14 : 0.92),
              Colors.white.withValues(alpha: 0),
            ],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: isDark ? 0.26 : 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF818CF8).withValues(alpha: isDark ? 0.42 : 0.28),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFDE68A),
              Color(0xFFC084FC),
              Color(0xFF67E8F9),
            ],
          ).createShader(bounds),
          child: const Icon(Icons.auto_awesome_rounded, size: 15, color: Colors.white),
        ),
      );
    }

    Widget titlePrimary() {
      final ts = theme.textTheme.titleSmall;
      if (isDark) {
        return Text(
          'Busca IA',
          style: (ts ?? const TextStyle(fontSize: 14)).copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 14,
            letterSpacing: 0.18,
            height: 1.1,
            shadows: [
              Shadow(
                offset: const Offset(0, 1),
                blurRadius: 10,
                color: const Color(0xFF22D3EE).withValues(alpha: 0.45),
              ),
            ],
          ),
        );
      }
      return ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => const LinearGradient(
          colors: [
            Color(0xFF312E81),
            Color(0xFF6D28D9),
            Color(0xFF0F766E),
          ],
        ).createShader(bounds),
        child: Text(
          'Busca IA',
          style: (ts ?? const TextStyle(fontSize: 14)).copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 14,
            letterSpacing: 0.12,
            height: 1.1,
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: bgGradient,
        border: Border.all(width: 0.95, color: borderColor.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: isDark ? 0.32 : 0.18),
            blurRadius: isDark ? 14 : 11,
            offset: const Offset(0, 5),
            spreadRadius: -2,
          ),
          BoxShadow(
            color: const Color(0xFF22D3EE).withValues(alpha: isDark ? 0.18 : 0.14),
            blurRadius: 9,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        child: Row(
          children: [
            sparkleIcon(),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  titlePrimary(),
                  const SizedBox(height: 2),
                  Text(
                    'Semântico · critérios inteligentes',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.7)
                          : const Color(0xFF475569),
                      fontWeight: FontWeight.w600,
                      fontSize: 9.5,
                      height: 1.05,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 11,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.68)
                  : const Color(0xFF64748B).withValues(alpha: 0.88),
            ),
          ],
        ),
      ),
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
    final accent = _portfolioAccentColor(context);
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
            Icon(
              icon,
              size: 18,
              color: isPrimary ? Colors.white : accent,
            ),
            const SizedBox(width: 8),
            Text(label, style: style),
          ],
        ),
      ),
    );
  }

  ({String label, String value}) _formatMainPrice(Property property) {
    if (property.salePrice != null && property.rentPrice != null) {
      return (
        label: 'VENDA E LOCAÇÃO',
        value: '${_formatCompactCurrency(property.salePrice!)} · ${_formatCompactCurrency(property.rentPrice!)}/mês',
      );
    }
    if (property.salePrice != null) {
      return (label: 'VALOR DE VENDA', value: _currencyFormatter.format(property.salePrice));
    }
    if (property.rentPrice != null) {
      return (label: 'VALOR DE ALUGUEL', value: '${_currencyFormatter.format(property.rentPrice)}/mês');
    }
    return (label: 'VALOR', value: 'Sob consulta');
  }

  String _formatCompactCurrency(double value) {
    if (value >= 1000000) {
      final compact = value / 1000000;
      return 'R\$ ${compact.toStringAsFixed(compact >= 10 ? 0 : 1)}M';
    }
    if (value >= 1000) {
      final compact = value / 1000;
      return 'R\$ ${compact.toStringAsFixed(compact >= 100 ? 0 : 1)}k';
    }
    return _currencyFormatter.format(value);
  }

  String _formatPropertyLocation(Property property) {
    if (property.address.trim().isNotEmpty) {
      return property.address;
    }

    final parts = <String>[];
    final streetLine = [property.street, property.number]
        .where((part) => part.trim().isNotEmpty)
        .join(', ');
    if (streetLine.isNotEmpty) parts.add(streetLine);
    if (property.neighborhood.trim().isNotEmpty) parts.add(property.neighborhood);

    final cityState = [property.city, property.state]
        .where((part) => part.trim().isNotEmpty)
        .join(' - ');
    if (cityState.isNotEmpty) parts.add(cityState);

    return parts.isNotEmpty ? parts.join(' • ') : 'Localização não informada';
  }

  Widget _buildPagination(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final narrow = MediaQuery.sizeOf(context).width < 360;

    return Container(
      padding: EdgeInsets.fromLTRB(narrow ? 10 : 14, 10, narrow ? 10 : 14, 14),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.background.backgroundDarkMode
            : AppColors.background.background,
        border: Border(
          top: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.70),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Container(
          padding:
              EdgeInsets.symmetric(horizontal: narrow ? 8 : 12, vertical: 10),
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
            crossAxisAlignment: CrossAxisAlignment.center,
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
                      '$_total imóveis encontrados',
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
                        _loadProperties();
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
                        _loadProperties();
                      }
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }


}
