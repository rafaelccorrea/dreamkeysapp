import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../shared/services/property_service.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/skeleton_box.dart';
import '../../../../shared/widgets/shimmer_image.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../widgets/property_filters_drawer.dart';
import '../widgets/intelligent_search_modal.dart';
import '../widgets/export_import_dialog.dart';
import '../../../../shared/services/ai_service.dart';
import '../../matches/widgets/matches_badge.dart';
import '../../../../core/routes/app_routes.dart';

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

class PropertiesPage extends StatefulWidget {
  const PropertiesPage({super.key});

  @override
  State<PropertiesPage> createState() => _PropertiesPageState();
}

class _PropertiesPageState extends State<PropertiesPage> {
  static const double _kHeaderPadH = 20;
  static const double _kHeaderPadVTop = 8;
  static const double _kStatCarouselHeight = 118;
  static const double _kStatTileWidth = 140;
  static const double _kQuickCarouselHeight = 44;
  static const double _kHeaderSectionGap = 12;

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

  @override
  void initState() {
    super.initState();
    _loadProperties();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Imóveis',
      currentBottomNavIndex: 1,
      showBottomNavigation: true,
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
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
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'search',
              child: Row(
                children: [
                  Icon(Icons.search, size: 20),
                  SizedBox(width: 8),
                  Text('Buscar'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'filters',
              child: Row(
                children: [
                  Stack(
                    children: [
                      const Icon(Icons.filter_list, size: 20),
                      if (_filters != null && _hasActiveFilters())
                        Positioned(
                          right: 0,
                          top: 0,
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
                  const SizedBox(width: 8),
                  const Text('Filtros'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'offers',
              child: Row(
                children: [
                  Icon(Icons.request_quote, size: 20),
                  SizedBox(width: 8),
                  Text('Ver Ofertas'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'export_import',
              child: Row(
                children: [
                  Icon(Icons.import_export, size: 20),
                  SizedBox(width: 8),
                  Text('Exportar/Importar'),
                ],
              ),
            ),
          ],
        ),
      ],
      body: Column(
        children: [
          // Barra de ações com botões
          _buildActionBar(context),

          // Lista de propriedades
          Expanded(
            child: _isLoading
                ? _buildSkeleton(context)
                : _errorMessage != null
                ? _buildErrorState(context)
                : _buildPropertiesList(context),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _portfolioAccentColor(context);
    final hasFilters = _filters != null && _hasActiveFilters();
    final hasSearch = _searchQuery.trim().isNotEmpty;
    final gatedGlobal = !hasFilters && !hasSearch;
    final m = _listedPropertyMetrics();

    final statTiles = <Widget>[
      if (_globalStats != null && gatedGlobal) ...[
        _buildPortfolioStatTile(
          context,
          value: _compactIntFormatter.format(_globalStats!.total),
          label: 'No CRM',
          hint: 'Portfolio completo',
          icon: Icons.apartment_rounded,
          accent: accent,
        ),
        _buildPortfolioStatTile(
          context,
          value: _compactIntFormatter.format(_globalStats!.available),
          label: 'Disponíveis',
          hint: 'Mercado',
          icon: Icons.event_available_rounded,
          accent: AppColors.status.success,
        ),
        _buildPortfolioStatTile(
          context,
          value: _compactIntFormatter.format(_globalStats!.rented),
          label: 'Locação',
          hint: 'Contratos ativos',
          icon: Icons.key_rounded,
          accent: const Color(0xFF818CF8),
        ),
        _buildPortfolioStatTile(
          context,
          value: _compactIntFormatter.format(_globalStats!.sold),
          label: 'Vendas',
          hint: 'Encerradas',
          icon: Icons.sell_outlined,
          accent: AppColors.status.info,
        ),
      ],
      _buildPortfolioStatTile(
        context,
        value: _compactIntFormatter.format(_total),
        label: 'Filtro',
        hint: gatedGlobal
            ? 'Ranking'
            : hasSearch
                ? 'Busca'
                : 'Critérios',
        icon: Icons.filter_alt_outlined,
        accent: const Color(0xFF6366F1),
      ),
      _buildPortfolioStatTile(
        context,
        value: '${_properties.length}',
        label: 'Nesta página',
        hint: m.sumOfferPending > 0
            ? '${m.sumOfferPending} pendências'
            : 'Lista carregada',
        icon: Icons.view_carousel_rounded,
        accent: accent,
      ),
      _buildPortfolioStatTile(
        context,
        value: '${m.available}',
        label: 'Lista · livres',
        hint: '${m.negotiationFriendly} negócio',
        icon: Icons.circle_outlined,
        accent: AppColors.status.success,
      ),
      _buildPortfolioStatTile(
        context,
        value: '${m.rented}',
        label: 'Lista · locação',
        hint: '${m.featuredHighlights} destaques',
        icon: Icons.houseboat_outlined,
        accent: const Color(0xFFF59E0B),
      ),
      _buildPortfolioStatTile(
        context,
        value: '${m.sold}',
        label: 'Lista · vendas',
        hint: '${m.publishedOnline} públicos',
        icon: Icons.receipt_long_outlined,
        accent: AppColors.status.info,
      ),
      _buildPortfolioStatTile(
        context,
        value: '${m.draft}',
        label: 'Rascunhos',
        hint: '${m.maintenance} revisão',
        icon: Icons.edit_note_rounded,
        accent: ThemeHelpers.textSecondaryColor(context),
      ),
      if (m.avgRentPrice != null)
        _buildPortfolioStatTile(
          context,
          value: _currencyFormatter.format(m.avgRentPrice!),
          label: 'Média aluguel',
          hint: 'Nesta página',
          icon: Icons.payments_rounded,
          accent: const Color(0xFFEC4899),
        ),
      if (m.avgSalePriceOnly != null)
        _buildPortfolioStatTile(
          context,
          value: _currencyFormatter.format(m.avgSalePriceOnly!),
          label: 'Média venda',
          hint: 'Nesta página',
          icon: Icons.storefront_rounded,
          accent: const Color(0xFF06B6D4),
        ),
      if (m.avgAreaSqm != null)
        _buildPortfolioStatTile(
          context,
          value: '${m.avgAreaSqm!.toStringAsFixed(m.avgAreaSqm! >= 10 ? 0 : 1)} m²',
          label: 'Área média',
          hint: 'Declarada',
          icon: Icons.straighten_rounded,
          accent: AppColors.primary.primary,
        ),
      _buildPortfolioStatTile(
        context,
        value: '${m.active}',
        label: 'Ativos',
        hint: '${m.inactive} pausados',
        icon: Icons.verified_rounded,
        accent: AppColors.status.success,
      ),
    ];

    final quickActions = <Widget>[
      _buildQuickActionButton(
        context,
        icon: Icons.add_business_rounded,
        label: 'Novo imóvel',
        isPrimary: true,
        onPressed: () => Navigator.of(context).pushNamed(AppRoutes.propertyCreate),
      ),
      _buildPremiumAiSearchQuickAction(
        context,
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
        },
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
      _buildQuickActionButton(
        context,
        icon: Icons.trending_up_rounded,
        label: 'Otimizar',
        onPressed: () => _showOptimizationDialog(context),
      ),
      _buildQuickActionButton(
        context,
        icon: Icons.request_quote_outlined,
        label: 'Ofertas',
        onPressed: () => Navigator.of(context).pushNamed(AppRoutes.propertyOffers),
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
                  AppColors.background.background,
                  AppColors.background.backgroundSecondary,
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
            padding: const EdgeInsets.fromLTRB(
              _kHeaderPadH,
              _kHeaderPadVTop,
              _kHeaderPadH,
              14,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'GESTÃO PORTFÓLIO',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        letterSpacing: 2.35,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      hasSearch ? 'Radar de imóveis' : 'Radar comercial Intellisys',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        height: 1.02,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitleParts,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                    if (hasFilters || hasSearch) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Use as faixas abaixo para comparar cenário global e recorte atual sem empilhar a lista inteira.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              ThemeHelpers.textSecondaryColor(context).withValues(alpha: 0.88),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: _kHeaderSectionGap),
                SizedBox(
                  height: _kStatCarouselHeight,
                  child: ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    clipBehavior: Clip.none,
                    scrollDirection: Axis.horizontal,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemCount: statTiles.length,
                    itemBuilder: (_, i) => statTiles[i],
                  ),
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
                const SizedBox(height: 10),
                SizedBox(
                  height: _kQuickCarouselHeight + 10,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const BouncingScrollPhysics(),
                      scrollDirection: Axis.horizontal,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemCount: quickActions.length,
                      itemBuilder: (_, i) => quickActions[i],
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

  Color _portfolioGlassBorderColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? Colors.white.withValues(alpha: 0.085)
        : Colors.black.withValues(alpha: 0.055);
  }

  /// Alinhado ao `_buildSummaryCard` do dashboard (gradiente suave + borda glass).
  BoxDecoration _kpiMetricCardDecoration(BuildContext context, Color accent) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          accent.withValues(alpha: isDark ? 0.16 : 0.11),
          accent.withValues(alpha: isDark ? 0.05 : 0.04),
        ],
      ),
      border: Border.all(color: _portfolioGlassBorderColor(context)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.04),
          blurRadius: 14,
          offset: const Offset(0, 7),
          spreadRadius: -3,
        ),
      ],
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
  }) {
    final theme = Theme.of(context);

    final content = SizedBox(
      width: _kStatTileWidth,
      height: _kStatCarouselHeight,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: _kpiMetricCardDecoration(context, accent),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildPortfolioIconBadge(context, icon, accent, size: 32, iconSize: 16),
                Container(
                  width: 34,
                  height: 5,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: LinearGradient(
                      colors: [
                        accent.withValues(alpha: 0.2),
                        accent.withValues(alpha: 0.75),
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
                      height: 1.05,
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
                if (hint != null && hint.isNotEmpty) ...[
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
        ),
      ),
    );

    if (hint != null && hint.length > 26) {
      return Tooltip(
        message: '$label · $hint',
        waitDuration: const Duration(milliseconds: 450),
        child: content,
      );
    }
    return content;
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
                  children: [
                    Icon(Icons.trending_up, color: AppColors.primary.primary),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Otimização de Portfólio',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: isOptimizing
                          ? null
                          : () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
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
                  children: [
                    const Expanded(
                      child: Text(
                        'Resultados da Otimização',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
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
                    children: [
                      const Expanded(
                        child: Text(
                          'Resultados da Otimização',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
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
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• '),
                            Expanded(child: Text(action)),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Skeleton da barra de busca
          Row(
            children: [
              Expanded(
                child: SkeletonBox(
                  height: 48,
                  borderRadius: 12,
                  margin: const EdgeInsets.only(bottom: 16),
                ),
              ),
              const SizedBox(width: 12),
              SkeletonBox(width: 48, height: 48, borderRadius: 12),
            ],
          ),
          // Skeleton dos cards
          ...List.generate(
            3,
            (index) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SkeletonCard(
                height: 200,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 150, height: 150, borderRadius: 12),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonText(
                            width: double.infinity,
                            height: 20,
                            margin: const EdgeInsets.only(bottom: 8),
                          ),
                          SkeletonText(
                            width: 150,
                            height: 16,
                            margin: const EdgeInsets.only(bottom: 8),
                          ),
                          SkeletonText(
                            width: 200,
                            height: 16,
                            margin: const EdgeInsets.only(bottom: 12),
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              SkeletonText(width: 50, height: 14),
                              SkeletonText(width: 50, height: 14),
                              SkeletonText(width: 50, height: 14),
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
                  color: Colors.black.withValues(alpha: isDark ? 0.26 : 0.05),
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
                children: [
                  const Expanded(
                    child: Text(
                      'Buscar Propriedades',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
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

  Widget _buildPropertiesList(BuildContext context) {
    final theme = Theme.of(context);

    if (_properties.isEmpty) {
      return _buildEmptyPropertiesState(context, theme);
    }

    return RefreshIndicator(
      onRefresh: () => _loadProperties(refresh: true),
      color: AppColors.primary.primary,
      child: Column(
        children: [
          Expanded(child: _buildListView(context, theme)),
          if (_totalPages > 1) _buildPagination(context),
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
              color: Colors.black.withValues(alpha: isDark ? 0.26 : 0.05),
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
                      crossAxisAlignment: CrossAxisAlignment.center,
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
                      onPressed: () => Navigator.of(context)
                          .pushNamed(AppRoutes.propertyCreate),
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

  Widget _buildListView(BuildContext context, ThemeData theme) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 22),
      itemCount: _properties.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _properties.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 22),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary.primary),
            ),
          );
        }
        final property = _properties[index];
        return _buildPropertyListCard(context, theme, property, index);
      },
    );
  }

  Widget _buildPropertyListCard(
    BuildContext context,
    ThemeData theme,
    Property property,
    int index,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = isDark
        ? AppColors.background.backgroundSecondaryDarkMode
        : AppColors.background.backgroundSecondary;
    final price = _formatMainPrice(property);
    final location = _formatPropertyLocation(property);
    final hasCommercialFlags = property.hasPendingOffers == true ||
        property.totalOffersCount != null ||
        property.acceptsNegotiation == true ||
        property.mcmvEligible == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: isDark ? 0.58 : 0.80),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.06),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () =>
                Navigator.of(context).pushNamed(AppRoutes.propertyDetails(property.id)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  SizedBox(
                    height: 214,
                    width: double.infinity,
                    child: property.mainImage != null
                        ? ShimmerImage(
                            imageUrl: property.mainImage!.url,
                            width: double.infinity,
                            height: 214,
                            fit: BoxFit.cover,
                            errorWidget: _buildPropertyImageFallback(context, theme),
                          )
                        : _buildPropertyImageFallback(context, theme),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.10),
                            Colors.black.withValues(alpha: 0.03),
                            Colors.black.withValues(alpha: 0.72),
                          ],
                          stops: const [0.0, 0.44, 1.0],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Row(
                      children: [
                        Flexible(
                          child: Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: [
                              _buildOverlayBadge(
                                context,
                                property.type.label,
                                Icons.category_outlined,
                                Colors.white,
                              ),
                              _buildOverlayBadge(
                                context,
                                property.status.label,
                                Icons.circle,
                                _getStatusColor(property.status),
                              ),
                              if (property.isFeatured)
                                _buildOverlayBadge(
                                  context,
                                  'Destaque',
                                  Icons.star_rounded,
                                  AppColors.status.warning,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildPropertyActionsMenu(context, theme, property),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                price.label,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.82),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.1,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (property.imageCount != null && property.imageCount! > 0)
                              _buildOverlayBadge(
                                context,
                                '${property.imageCount}',
                                Icons.photo_library_outlined,
                                Colors.white,
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          price.value,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            height: 1.05,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: MatchesBadge(
                            propertyId: property.id,
                            onClick: () {
                              Navigator.pushNamed(
                                context,
                                AppRoutes.matchesByProperty(property.id),
                              );
                            },
                            child: Text(
                              property.title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: ThemeHelpers.textColor(context),
                                fontWeight: FontWeight.w900,
                                height: 1.15,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        if (property.code != null && property.code!.trim().isNotEmpty) ...[
                          const SizedBox(width: 10),
                          _buildCodePill(context, property.code!),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildLocationLine(context, theme, location),
                    const SizedBox(height: 14),
                    _buildCompactSpecsGrid(context, theme, property),
                    if (_buildFinancialDetails(property).isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _buildFinancialStrip(context, theme, property),
                    ],
                    if (property.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        property.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                          height: 1.45,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (property.features.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _buildFeaturesPreview(context, theme, property),
                    ],
                    if (hasCommercialFlags) ...[
                      const SizedBox(height: 14),
                      _buildCommercialSignals(context, theme, property),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildCardFooterSignal(
                            context,
                            icon: property.isAvailableForSite == true
                                ? Icons.public_rounded
                                : Icons.visibility_off_outlined,
                            label: property.isAvailableForSite == true
                                ? 'Publicado no site'
                                : 'Interno',
                            color: property.isAvailableForSite == true
                                ? AppColors.status.success
                                : ThemeHelpers.textSecondaryColor(context),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildCardFooterSignal(
                            context,
                            icon: property.isActive
                                ? Icons.check_circle_outline_rounded
                                : Icons.pause_circle_outline_rounded,
                            label: property.isActive ? 'Ativo' : 'Inativo',
                            color: property.isActive
                                ? AppColors.status.success
                                : AppColors.status.warning,
                          ),
                        ),
                      ],
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

  Widget _buildPropertyActionsMenu(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 20),
        tooltip: 'Ações do imóvel',
        color: theme.scaffoldBackgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onSelected: (value) async {
          if (value == 'edit' && mounted) {
            Navigator.of(context).pushNamed('/properties/${property.id}/edit');
          } else if (value == 'delete') {
            await _confirmAndDeleteProperty(context, property);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                Icon(Icons.edit_outlined, size: 20, color: ThemeHelpers.textColor(context)),
                const SizedBox(width: 12),
                Text(
                  'Editar',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.red),
                const SizedBox(width: 12),
                Text(
                  'Excluir',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
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
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.status.error.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.delete_outline_rounded, color: AppColors.status.error),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Excluir imóvel',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context, false),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.primary.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.primary.primary),
          const SizedBox(width: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 172),
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

  /// Atalho «Busca IA» com acabamento premium (gradiente, borda luminosa, halo no ícone).
  Widget _buildPremiumAiSearchQuickAction(
    BuildContext context, {
    required VoidCallback onPressed,
  }) {
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
        width: 26,
        height: 26,
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
          child: const Icon(Icons.auto_awesome_rounded, size: 14, color: Colors.white),
        ),
      );
    }

    Widget labelPrimary() {
      final ts = theme.textTheme.titleSmall;
      if (isDark) {
        return Text(
          'Busca IA',
          style: (ts ?? const TextStyle(fontSize: 14)).copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 14,
            letterSpacing: 0.2,
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
            letterSpacing: 0.15,
            height: 1.1,
          ),
        ),
      );
    }

    return Tooltip(
      message: 'Busca inteligente com critérios semânticos',
      child: Material(
        color: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(18),
          splashColor: const Color(0xFF818CF8).withValues(alpha: 0.22),
          highlightColor: Colors.white.withValues(alpha: 0.06),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: bgGradient,
              border: Border.all(width: 0.95, color: borderColor.withValues(alpha: 0.9)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withValues(alpha: isDark ? 0.32 : 0.18),
                  blurRadius: isDark ? 16 : 12,
                  offset: const Offset(0, 6),
                  spreadRadius: -2,
                ),
                BoxShadow(
                  color: const Color(0xFF22D3EE).withValues(alpha: isDark ? 0.18 : 0.14),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                sparkleIcon(),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    labelPrimary(),
                    const SizedBox(height: 1),
                    Text(
                      'Semântico · matches',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.68)
                            : const Color(0xFF475569),
                        letterSpacing: 0.06,
                        fontWeight: FontWeight.w600,
                        fontSize: 9.5,
                        height: 1.05,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 11,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.68)
                        : const Color(0xFF64748B).withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ),
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
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final appPrimary = AppColors.primary.primary;

    final Color accent = isPrimary || highlight ? appPrimary : muted;

    Decoration decoration() {
      final r = BorderRadius.circular(16);
      if (isPrimary) {
        return BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(appPrimary, Colors.white, 0.12)!,
              Color.lerp(appPrimary, Colors.black, 0.08)!,
            ],
          ),
          borderRadius: r,
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          boxShadow: [
            BoxShadow(
              color: appPrimary.withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 4),
              spreadRadius: -2,
            ),
          ],
        );
      }
      if (highlight) {
        return BoxDecoration(
          color: appPrimary.withValues(alpha: 0.077),
          borderRadius: r,
          border: Border.all(
            color: appPrimary.withValues(alpha: 0.48),
            width: 1.15,
          ),
        );
      }
      return BoxDecoration(
        color: accent.withValues(alpha: 0.058),
        borderRadius: r,
        border: Border.all(
          color: accent.withValues(alpha: 0.14),
          width: 1,
        ),
      );
    }

    Color iconColor() {
      if (isPrimary) return Colors.white.withValues(alpha: 0.96);
      if (highlight) return appPrimary;
      return accent;
    }

    Color labelColor() {
      if (isPrimary) return Colors.white;
      if (highlight) return appPrimary;
      return ThemeHelpers.textColor(context);
    }

    final style = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w800,
      fontSize: 12.75,
      height: 1.15,
      letterSpacing: -0.1,
      color: labelColor(),
    );

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        splashFactory: InkRipple.splashFactory,
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (!isPrimary && states.contains(WidgetState.pressed)) {
            return accent.withValues(alpha: 0.07);
          }
          return accent.withValues(alpha: 0.055);
        }),
        child: Ink(
          decoration: decoration(),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16.5, color: iconColor()),
              const SizedBox(width: 7),
              Text(label, style: style),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverlayBadge(
    BuildContext context,
    String label,
    IconData icon,
    Color accent,
  ) {
    final displayColor = accent == Colors.white ? Colors.white : accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: displayColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodePill(BuildContext context, String code) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.primary.withValues(alpha: 0.20)),
      ),
      child: Text(
        '#$code',
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.primary.primary,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildLocationLine(BuildContext context, ThemeData theme, String location) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.location_on_outlined,
          size: 18,
          color: AppColors.primary.primary,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            location,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactSpecsGrid(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final specs = <Widget>[
      if (property.bedrooms != null)
        _buildSpecTile(context, theme, Icons.bed_rounded, '${property.bedrooms}', 'quartos'),
      if (property.bathrooms != null)
        _buildSpecTile(context, theme, Icons.bathtub_outlined, '${property.bathrooms}', 'banhos'),
      if (property.parkingSpaces != null)
        _buildSpecTile(context, theme, Icons.local_parking_rounded, '${property.parkingSpaces}', 'vagas'),
      if (property.totalArea > 0)
        _buildSpecTile(context, theme, Icons.square_foot_rounded, '${property.totalArea.toInt()}', 'm² total'),
      if (property.builtArea != null && property.builtArea! > 0)
        _buildSpecTile(context, theme, Icons.architecture_outlined, '${property.builtArea!.toInt()}', 'm² útil'),
    ];

    if (specs.isEmpty) {
      return _buildSoftInfoBox(
        context,
        icon: Icons.info_outline_rounded,
        text: 'Características principais ainda não informadas',
      );
    }

    return Wrap(spacing: 8, runSpacing: 8, children: specs);
  }

  Widget _buildSpecTile(
    BuildContext context,
    ThemeData theme,
    IconData icon,
    String value,
    String label,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      constraints: const BoxConstraints(minWidth: 82),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ThemeHelpers.borderColor(context).withValues(alpha: 0.65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: AppColors.primary.primary),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialStrip(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final details = _buildFinancialDetails(property);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.primary.withValues(alpha: 0.14)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        children: details,
      ),
    );
  }

  List<Widget> _buildFinancialDetails(Property property) {
    return [
      if (property.condominiumFee != null)
        _buildFinancialItem(Icons.apartment_rounded, 'Condomínio', property.condominiumFee!),
      if (property.iptu != null)
        _buildFinancialItem(Icons.receipt_long_outlined, 'IPTU', property.iptu!),
      if (property.minSalePrice != null)
        _buildFinancialItem(Icons.sell_outlined, 'Mín. venda', property.minSalePrice!),
      if (property.minRentPrice != null)
        _buildFinancialItem(Icons.key_outlined, 'Mín. aluguel', property.minRentPrice!),
    ];
  }

  Widget _buildFinancialItem(IconData icon, String label, double value) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: AppColors.primary.primary),
            const SizedBox(width: 5),
            Text(
              '$label: ${_formatCompactCurrency(value)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFeaturesPreview(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final visibleFeatures = property.features.take(3).toList();
    final remaining = property.features.length - visibleFeatures.length;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ...visibleFeatures.map(
          (feature) => _buildMiniTag(context, feature, Icons.check_rounded),
        ),
        if (remaining > 0)
          _buildMiniTag(context, '+$remaining detalhes', Icons.more_horiz_rounded),
      ],
    );
  }

  Widget _buildCommercialSignals(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (property.hasPendingOffers == true)
          _buildSignalTag(
            context,
            'Oferta pendente',
            Icons.notifications_active_outlined,
            AppColors.status.warning,
          ),
        if (property.totalOffersCount != null && property.totalOffersCount! > 0)
          _buildSignalTag(
            context,
            '${property.totalOffersCount} ofertas',
            Icons.request_quote_outlined,
            AppColors.status.info,
          ),
        if (property.acceptsNegotiation == true)
          _buildSignalTag(
            context,
            'Negociável',
            Icons.handshake_outlined,
            AppColors.status.success,
          ),
        if (property.mcmvEligible == true)
          _buildSignalTag(
            context,
            'MCMV',
            Icons.account_balance_outlined,
            AppColors.primary.primary,
          ),
      ],
    );
  }

  Widget _buildMiniTag(BuildContext context, String label, IconData icon) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: ThemeHelpers.textSecondaryColor(context).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: ThemeHelpers.textSecondaryColor(context)),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignalTag(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardFooterSignal(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSoftInfoBox(
    BuildContext context, {
    required IconData icon,
    required String text,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ThemeHelpers.textSecondaryColor(context).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: ThemeHelpers.textSecondaryColor(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
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

  Color _getStatusColor(PropertyStatus status) {
    switch (status) {
      case PropertyStatus.available:
        return AppColors.status.success;
      case PropertyStatus.sold:
        return AppColors.status.info;
      case PropertyStatus.rented:
        return AppColors.status.warning;
      case PropertyStatus.maintenance:
        return AppColors.status.warning;
      case PropertyStatus.draft:
        return AppColors.text.textSecondary;
    }
  }

  Widget _buildPagination(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$_total imóveis encontrados',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
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
