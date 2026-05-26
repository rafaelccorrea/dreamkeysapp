import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../shared/services/property_service.dart';
import '../../../../shared/services/module_access_service.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/skeleton_box.dart';
import '../../../../shared/widgets/shimmer_image.dart';
import '../../../../shared/state/screen_state_cache.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/shell_visual_tokens.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../widgets/property_filters_drawer.dart';
import '../widgets/intelligent_search_modal.dart';
import '../widgets/export_import_dialog.dart';
import '../services/property_local_draft_storage.dart';
import '../../../../shared/services/ai_service.dart';
import '../../../../core/routes/app_routes.dart';
import '../models/property_wizard_pop_result.dart';
import '../utils/property_edit_permissions.dart';
import '../utils/property_status_visual.dart';

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
  Timer? _searchDebounce;
  final ScrollController _scrollController = ScrollController();

  int _localDraftCount = 0;

  /// Chave usada para guardar/restaurar estado desta tela quando o usuário
  /// sai e volta em curto prazo (filtros + termo de busca).
  static const String _stateCacheKey = 'properties:list';

  @override
  void initState() {
    super.initState();
    _restoreCachedState();
    _loadProperties();
    _refreshLocalDraftCount();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _persistState();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Restaura `_searchQuery` e `_filters` da cache em memória (se houver).
  /// Chamado uma vez no `initState` antes do primeiro `_loadProperties`.
  void _restoreCachedState() {
    final cache = ScreenStateCache.instance.read<Map<String, dynamic>>(
      _stateCacheKey,
    );
    if (cache == null) return;
    final cachedSearch = cache['search'] as String?;
    final cachedFilters = cache['filters'];
    if (cachedSearch != null && cachedSearch.isNotEmpty) {
      _searchQuery = cachedSearch;
      _searchController.text = cachedSearch;
    }
    if (cachedFilters is PropertyFilters) {
      _filters = cachedFilters;
    }
  }

  /// Guarda o estado atual da listagem (busca + filtros) na cache global.
  void _persistState() {
    ScreenStateCache.instance.save(_stateCacheKey, {
      'search': _searchQuery,
      'filters': _filters,
    });
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
              'Imóvel enviado para a fila de aprovação.',
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

  /// Espelha a `normalizeListingScope` do `useProperties.ts` do front web.
  ///
  /// Alguns ambientes do backend não interpretam `onlyMyData` consistentemente
  /// (em alguns lugares vira "criado por mim" e zera a lista para corretores
  /// que atuam como responsáveis sem ter criado a ficha). Por isso, quando
  /// o usuário ativa o toggle "Minhas propriedades", trocamos:
  ///   `onlyMyData: true` → `responsibleUserId: currentUserId`
  /// e mandamos `onlyMyData: false` na requisição. É exatamente o que a
  /// `useProperties.normalizeListingScope` faz no front web.
  PropertyFilters? _normalizeListingScope(PropertyFilters? filters) {
    if (filters == null) return null;
    if (filters.onlyMyData != true) return filters;
    final currentUserId = ModuleAccessService.instance.userId;
    if (currentUserId == null || currentUserId.trim().isEmpty) {
      return filters;
    }
    return filters.copyWithNullable(
      responsibleUserId: filters.responsibleUserId ?? currentUserId,
      onlyMyData: false,
    );
  }

  /// Monta os filtros enviados à API — paridade com `getCombinedFilters` (web).
  ///
  /// - `search` vem do campo de busca do header.
  /// - Aba **Todos** (`portfolioScope` nulo) sempre envia `includeInactive=true`
  ///   para listar ativos e inativos, todos os status.
  PropertyFilters? _buildRequestFilters() {
    final searchTrim = _searchQuery.trim();
    final base = _filters ?? PropertyFilters();
    final isTodosTab = _activeScope == null;

    var combined = base.copyWith(
      search: searchTrim.isEmpty ? null : searchTrim,
    );

    if (isTodosTab) {
      combined = combined.copyWith(includeInactive: true);
    } else {
      combined = combined.copyWithNullable(resetIncludeInactive: true);
    }

    if (isTodosTab) {
      return _normalizeListingScope(combined);
    }

    if (searchTrim.isEmpty && _filtersPayloadIsEmpty(base)) {
      return _normalizeListingScope(null);
    }

    return _normalizeListingScope(combined);
  }

  bool _filtersPayloadIsEmpty(PropertyFilters f) {
    return f.type == null &&
        f.status == null &&
        f.city == null &&
        f.state == null &&
        f.neighborhood == null &&
        f.minPrice == null &&
        f.maxPrice == null &&
        f.minArea == null &&
        f.maxArea == null &&
        f.bedrooms == null &&
        f.bathrooms == null &&
        f.parkingSpaces == null &&
        (f.features == null || f.features!.isEmpty) &&
        f.isActive == null &&
        f.isFeatured == null &&
        f.companyId == null &&
        f.responsibleUserId == null &&
        f.onlyMyData != true &&
        f.portfolioScope == null &&
        f.includeInactive != true;
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
      final filters = _buildRequestFilters();

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
      final filters = _buildRequestFilters();

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

  /// Botão de overflow do AppBar — abre o sheet premium com todas as
  /// ações secundárias da tela.
  Widget _buildPropertiesScreenOverflowMenu(BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.more_vert,
        color: ThemeHelpers.textColor(context).withValues(alpha: 0.88),
      ),
      tooltip: 'Mais opções',
      onPressed: () => _showPropertiesOverflowSheet(context),
    );
  }

  /// Bottom sheet premium do overflow — substitui o `PopupMenuButton`
  /// padrão do Flutter, que era simples demais e ocupava muito espaço com
  /// pouca identidade visual.
  ///
  /// Estrutura:
  /// - Header gradient + ícone + título + descrição + close
  /// - Itens em "tiles" com chip de ícone colorido (cor distinta por intent)
  /// - Item destacado de Busca IA (gradient premium)
  /// - Sections separadas por divisor sutil
  void _showPropertiesOverflowSheet(BuildContext context) {
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black54,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _PropertiesOverflowSheet(
        hasActiveFilters: _filters != null && _hasActiveFilters(),
        localDraftCount: _localDraftCount,
      ),
    ).then((value) {
      if (value == null || !mounted) return;
      _handlePropertiesOverflowAction(value);
    });
  }

  void _handlePropertiesOverflowAction(String value) {
    switch (value) {
      case 'search':
        _showSearchBottomSheet(context);
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
      case 'drafts':
        _openLocalDrafts();
        break;
      case 'portfolio_metrics':
        _showPortfolioOverflowMetricsSheet(context);
        break;
      case 'optimize':
        _showOptimizationDialog(context);
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
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Propriedades',
      currentBottomNavIndex: 1,
      showBottomNavigation: true,
      actions: [
        _buildPropertiesScreenOverflowMenu(context),
      ],
      body: _isLoading
          // Esqueleto de tela inteira: enquanto a chamada de listagem +
          // estatísticas não termina, mostramos placeholders inclusive na
          // área do hero. Antes o hero era renderizado "pronto" e só o grid
          // ficava em skeleton — passava a impressão de que a tela carregou
          // pela metade.
          ? _buildFullPageSkeleton(context)
          : _errorMessage != null
              ? _buildHeaderWithFillingChild(
                  context,
                  child: _buildErrorState(context),
                )
              : _properties.isEmpty
                  ? _buildHeaderWithFillingChild(
                      context,
                      child: _buildEmptyPropertiesState(context, Theme.of(context)),
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
    final hasFilters = _filters != null && _hasActiveFilters();
    final hasSearch = _searchQuery.trim().isNotEmpty;
    final gatedGlobal = !hasFilters && !hasSearch;
    final m = _listedPropertyMetrics();
    final gs = _globalStats;

    // Paleta de KPIs do hero — cada card usa uma cor distinta para evitar
    // a sensação "massante" de só duas cores alternando. As cores espelham o
    // tom semântico do indicador (roxo = total/portfolio premium, verde =
    // saúde/disponível, cyan = página/escopo atual, âmbar = atenção/seleção,
    // indigo = filtro ativo).
    const portfolioPurple = Color(0xFF8B5CF6);
    const pageCyan = Color(0xFF0891B2);
    const selectionAmber = Color(0xFFF59E0B);
    const filterIndigo = Color(0xFF6366F1);
    final successGreen = AppColors.status.success;

    if (gs != null && gatedGlobal) {
      return [
        _buildPortfolioStatTile(
          context,
          value: _compactIntFormatter.format(gs.total),
          // "No CRM" passava a impressão de "número de leads no CRM". O total
          // aqui é o portfolio de imóveis cadastrados.
          label: 'Portfolio',
          icon: Icons.apartment_rounded,
          accent: portfolioPurple,
          tileHeight: th,
          dense: true,
        ),
        _buildPortfolioStatTile(
          context,
          value: _compactIntFormatter.format(gs.available),
          label: 'Disponíveis',
          icon: Icons.event_available_rounded,
          accent: successGreen,
          tileHeight: th,
          dense: true,
        ),
        _buildPortfolioStatTile(
          context,
          value: '${_properties.length}',
          label: 'Nesta página',
          icon: Icons.view_module_outlined,
          accent: pageCyan,
          tileHeight: th,
          dense: true,
        ),
        _buildPortfolioStatTile(
          context,
          value: '${m.available}',
          label: 'Seleção · livres',
          icon: Icons.circle_outlined,
          accent: selectionAmber,
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
        accent: filterIndigo,
        tileHeight: th,
        dense: true,
      ),
      _buildPortfolioStatTile(
        context,
        value: '${_properties.length}',
        label: 'Nesta página',
        icon: Icons.view_module_outlined,
        accent: pageCyan,
        tileHeight: th,
        dense: true,
      ),
      _buildPortfolioStatTile(
        context,
        value: '${m.available}',
        label: 'Seleção · livres',
        icon: Icons.circle_outlined,
        accent: selectionAmber,
        tileHeight: th,
        dense: true,
      ),
      _buildPortfolioStatTile(
        context,
        value: '${m.active}',
        label: 'Ativos',
        icon: Icons.verified_rounded,
        accent: successGreen,
        tileHeight: th,
        dense: true,
      ),
    ];
  }

  /// Radar / KPIs / atalhos — hero alinhado ao painel principal (dashboard).
  // ────────────────────────────────────────────────────────────────────
  // Atalhos do corretor (broker UX) — paridade com web `PropertiesPage`:
  // chip strip por escopo da carteira + toggle "Minhas propriedades".
  // ────────────────────────────────────────────────────────────────────

  PortfolioScope? get _activeScope => _filters?.portfolioScope;

  /// "Apenas inativos" — verdadeiro filtro: backend recebe `isActive=false`
  /// e devolve SÓ cadastros desativados. (O antigo `includeInactive` apenas
  /// _incluía_ inativos junto com ativos, o que confundia o corretor.)
  bool get _onlyInactive => _filters?.isActive == false;

  bool get _onlyMyProperties => _filters?.onlyMyData == true;

  void _setPortfolioScope(PortfolioScope? scope) {
    final base = _filters ?? PropertyFilters();
    setState(() {
      _filters = base.copyWithNullable(
        portfolioScope: scope,
        resetPortfolioScope: scope == null,
      );
    });
    _persistState();
    _loadProperties(refresh: true);
  }

  void _toggleOnlyInactive() {
    final base = _filters ?? PropertyFilters();
    final next = !_onlyInactive;
    setState(() {
      _filters = base.copyWithNullable(
        isActive: next ? false : null,
        resetIsActive: !next,
        // Limpamos `includeInactive` antigo para não conflitar com a nova
        // semântica baseada em `isActive`.
        resetIncludeInactive: true,
      );
    });
    _persistState();
    _loadProperties(refresh: true);
  }

  void _toggleOnlyMyProperties() {
    final base = _filters ?? PropertyFilters();
    final next = !_onlyMyProperties;
    setState(() {
      _filters = base.copyWithNullable(
        onlyMyData: next,
        resetOnlyMyData: !next,
      );
    });
    _persistState();
    _loadProperties(refresh: true);
  }

  /// Painel unificado de atalhos do corretor — substitui o antigo bloco
  /// "INSIGHT PORTFÓLIO" do hero. Concentra "Minhas propriedades" (em
  /// destaque), as chips de escopo da carteira e o toggle "Ver inativos"
  /// em um único bloco visual coeso.
  ///
  /// Permissões: a tela em si já é gated por `property:view` (rota +
  /// drawer). Os filtros aqui só refinam a consulta — não há ação
  /// destrutiva, portanto não há gating adicional necessário. O backend
  /// continua aplicando RLS / role bypass para "minhas propriedades" e
  /// "pendentes" exatamente como na web.
  /// Painel de atalhos do corretor — totalmente flat, sem cards, sem
  /// bordas, sem sombras. Tudo vive direto no background do hero como
  /// o resto dos elementos do cabeçalho. Espaçamentos verticais
  /// compactos pra dar a sensação de "lista solta" e não de "form".
  Widget _buildBrokerFiltersPanel(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _portfolioAccentColor(context);

    final activeCount = (_activeScope != null ? 1 : 0) +
        (_onlyMyProperties ? 1 : 0) +
        (_onlyInactive ? 1 : 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.filter_alt_rounded, size: 14, color: accent),
            const SizedBox(width: 6),
            Text(
              'ATALHOS DO CORRETOR',
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent,
                letterSpacing: 1.65,
                fontWeight: FontWeight.w900,
                fontSize: 10.5,
              ),
            ),
            const Spacer(),
            if (activeCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.18 : 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  '$activeCount ativo${activeCount > 1 ? 's' : ''}',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 10.5,
                    letterSpacing: 0.25,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _FlatToggleRow(
          icon: Icons.person_rounded,
          inactiveIcon: Icons.person_outline_rounded,
          label: 'Minhas propriedades',
          hint: _onlyMyProperties
              ? 'Mostrando apenas imóveis sob sua responsabilidade'
              : 'Filtrar pelos imóveis onde você é responsável ou captador',
          active: _onlyMyProperties,
          tone: accent,
          onTap: _toggleOnlyMyProperties,
        ),
        const SizedBox(height: 4),
        _FlatToggleRow(
          icon: Icons.archive_rounded,
          inactiveIcon: Icons.archive_outlined,
          label: _onlyInactive
              ? 'Mostrando só inativos'
              : 'Apenas inativos',
          hint: _onlyInactive
              ? 'Lista filtrada para cadastros desativados'
              : 'Filtrar somente cadastros desativados',
          active: _onlyInactive,
          tone: const Color(0xFF6366F1),
          onTap: _toggleOnlyInactive,
        ),
        const SizedBox(height: 12),
        _buildPortfolioScopeStrip(context),
      ],
    );
  }

  /// Chip strip por status do portfólio (Todos / Disponíveis / Vendidos /
  /// Pendentes / Recusados). Em `Wrap` — sem scroll horizontal; quando
  /// não couber, quebra pra linha de baixo.
  Widget _buildPortfolioScopeStrip(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final chips = <_ScopeChipData>[
      _ScopeChipData(
        label: 'Todos',
        icon: Icons.apps_rounded,
        active: _activeScope == null,
        tone: theme.colorScheme.primary,
        onTap: () => _setPortfolioScope(null),
      ),
      _ScopeChipData(
        label: 'Disponíveis',
        icon: Icons.check_circle_rounded,
        active: _activeScope == PortfolioScope.available,
        tone: const Color(0xFF10B981),
        onTap: () => _setPortfolioScope(PortfolioScope.available),
      ),
      _ScopeChipData(
        label: 'Vendidos',
        icon: Icons.sell_rounded,
        active: _activeScope == PortfolioScope.sold,
        tone: const Color(0xFF8B5CF6),
        onTap: () => _setPortfolioScope(PortfolioScope.sold),
      ),
      _ScopeChipData(
        label: 'Pendentes',
        icon: Icons.schedule_rounded,
        active: _activeScope == PortfolioScope.pending,
        tone: const Color(0xFFF59E0B),
        onTap: () => _setPortfolioScope(PortfolioScope.pending),
      ),
      _ScopeChipData(
        label: 'Recusados',
        icon: Icons.cancel_rounded,
        active: _activeScope == PortfolioScope.rejected,
        tone: const Color(0xFFEF4444),
        onTap: () => _setPortfolioScope(PortfolioScope.rejected),
      ),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final c in chips)
          _PortfolioScopeChip(
            label: c.label,
            icon: c.icon,
            active: c.active,
            tone: c.tone,
            isDark: isDark,
            onTap: c.onTap,
          ),
      ],
    );
  }

  Widget _buildPortfolioHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _portfolioAccentColor(context);
    final hasFilters = _filters != null && _hasActiveFilters();
    final hasSearch = _searchQuery.trim().isNotEmpty;
    final gatedGlobal = !hasFilters && !hasSearch;

    // Ações rápidas do hero: apenas "Novo imóvel" (primário) e "Filtros".
    // "Rascunhos" foi movido para o menu de overflow (3 pontinhos do AppBar)
    // — uso menos frequente, não merece ocupar espaço aqui.
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
        icon: Icons.tune_rounded,
        label: hasFilters ? 'Filtros ativos' : 'Filtros',
        highlight: hasFilters,
        onPressed: () {
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            barrierColor: Colors.black54,
            // O drawer já carrega o próprio container com border-radius e
            // sombra premium — usamos transparente aqui pra ele não ficar
            // dentro de um wrapper Material padrão.
            backgroundColor: Colors.transparent,
            builder: (context) => PropertyFiltersDrawer(
              initialFilters: _filters,
              onFiltersChanged: (filters) {
                setState(() => _filters = filters);
                _persistState();
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

        final padH = narrow ? 12.0 : (compact ? 16.0 : _kHeaderPadH);
        // Gap mais amplo agora que os KPIs são fluidos (sem moldura) — dá
        // respiração entre as colunas, evitando que números grandes pareçam
        // "colados". Antes (com caixa) bastava 6/8 px.
        final statSep = compact ? 14.0 : 18.0;
        final innerW =
            (w - padH * 2).clamp(0.0, double.infinity).toDouble();
        final kpiCols = innerW >= 360 ? 4 : 2;
        final gap = statSep;
        // Sem caixa fixa, a altura final é definida pela tipografia interna do
        // KPI fluido. Mantemos um valor razoável só para alinhar verticalmente
        // os 4 tiles e dar espaço pra `FittedBox` reduzir números grandes.
        final statH = compact ? 78.0 : 84.0;
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

        Widget insightBlock() => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeaderSearchField(context),
                const SizedBox(height: 12),
                _buildBrokerFiltersPanel(context),
              ],
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
              // O painel de atalhos do corretor sempre ocupa a largura
              // inteira do hero, mesmo em telas largas — assim os toggles
              // e chips não ficam apertados num quadrante centralizado.
              pillRow(),
              const SizedBox(height: 12),
              insightBlock(),
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
                                _persistState();
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
                                _persistState();
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

    // Modo `dense` (KPIs do hero) — conteúdo FLUIDO, sem card/borda/sombra.
    // Hierarquia: ícone tinted + LABEL uppercase + número grande + traço
    // gradient na cor da categoria. Sem altura fixa: cresce com o conteúdo,
    // o que elimina o overflow de 2px do FittedBox dentro de SizedBox(118).
    if (dense) {
      return _buildFluidStatTile(
        context,
        value: value,
        label: label,
        icon: icon,
        accent: accent,
      );
    }

    final tw = tileWidth ?? _kStatTileWidth;
    final th = tileHeight ?? _kStatCarouselHeight;
    final pad = const EdgeInsets.fromLTRB(12, 10, 12, 10);
    final showHint = hint != null && hint.isNotEmpty;

    final Widget inner;
    {
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
        decoration: _kpiMetricCardDecoration(context, accent, dense: false),
        child: inner,
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

  /// KPI fluido do hero — sem caixa/borda/sombra. Apenas hierarquia
  /// tipográfica + ícone tinted + traço gradient na cor da categoria.
  ///
  /// Estrutura:
  /// ```
  /// [▣]  PORTFOLIO         ← ícone tinted 22×22 + label uppercase
  /// 1.245                  ← número grande, peso 900
  /// ───                    ← traço gradient 28×2 na cor do KPI
  /// ```
  Widget _buildFluidStatTile(
    BuildContext context, {
    required String value,
    required String label,
    required IconData icon,
    required Color accent,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final mutedColor = ThemeHelpers.textSecondaryColor(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header: ícone tinted compacto + label uppercase espaçada.
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.16 : 0.12),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: accent.withValues(alpha: isDark ? 0.32 : 0.22),
                  ),
                ),
                child: Icon(icon, color: accent, size: 13),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: mutedColor,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    fontSize: 9.5,
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Número — protagonista da tile. FittedBox garante que números
          // grandes (ex.: 99.999) não estouram a coluna do Row pai.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.6,
                height: 1.05,
                color: textColor,
                fontSize: 24,
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Traço gradient — detalhe sutil que carrega a cor do KPI sem
          // precisar de moldura. Substitui o card antigo.
          Container(
            height: 2,
            width: 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: LinearGradient(
                colors: [
                  accent.withValues(alpha: isDark ? 0.85 : 0.7),
                  accent.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Métricas detalhadas — bottom sheet fluido sem encapsulamento de cards.
  /// Foca estritamente no nome: títulos, números e gráficos estilizados.
  /// Substitui o grid antigo (`Wrap` de cards encapsulados) por um layout
  /// vertical com seções separadas por divisores sutis e visualizações
  /// dinâmicas (barra empilhada, barras horizontais, donuts).
  void _showPortfolioOverflowMetricsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black54,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _PortfolioMetricsSheet(
        listed: _listedPropertyMetrics(),
        global: _globalStats,
        listedCount: _properties.length,
        totalFiltered: _total,
        gatedGlobal:
            !(_filters != null && _hasActiveFilters()) &&
                _searchQuery.trim().isEmpty,
      ),
    );
  }

  /// Modal de Otimização de Portfólio — bottom sheet premium com cards
  /// selecionáveis em vez de `RadioListTile`. Cada foco tem cor própria,
  /// ícone temático e descrição. Botão "Otimizar" é o CTA destacado.
  void _showOptimizationDialog(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black54,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _PortfolioOptimizationSheet(
        onSubmit: (focus) async {
          final scaffold = ScaffoldMessenger.of(context);
          try {
            final aiService = AiService.instance;
            final response = await aiService.optimizePortfolio(
              PortfolioOptimizationRequest(focus: focus),
            );
            if (!context.mounted) return;
            Navigator.pop(sheetCtx);
            if (response.success && response.data != null) {
              _showOptimizationResults(context, response.data!);
            } else {
              scaffold.showSnackBar(
                SnackBar(
                  content: Text(
                    response.message ?? 'Erro ao otimizar portfólio',
                  ),
                  backgroundColor: AppColors.status.error,
                ),
              );
            }
          } catch (e) {
            debugPrint('Erro na otimização: $e');
            if (!context.mounted) return;
            Navigator.pop(sheetCtx);
            scaffold.showSnackBar(
              const SnackBar(
                content: Text('Erro ao conectar com o servidor'),
              ),
            );
          }
        },
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

  /// Esqueleto cobrindo a tela inteira — hero, KPIs, carrossel de
  /// "Adicionados recentemente" e grid. Mantém a sensação de uma única
  /// transição de carregamento → conteúdo (em vez de hero pronto + lista
  /// ainda carregando).
  Widget _buildFullPageSkeleton(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final hPad = w < 360 ? 10.0 : 14.0;
    final cols = _exploreGridCrossAxisCount(w);
    final aspect = _exploreGridChildAspectRatio(cols);
    final spacingH = cols >= 3 ? 9.0 : 11.0;
    final spacingV = cols >= 3 ? 11.0 : 13.0;
    final cardH = (w * 1.12).clamp(360.0, 460.0);

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

    Widget kpiTile() => const SkeletonBox(height: 92, borderRadius: 18);

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Hero placeholder ────────────────────────────────────────────
          // Linha 1: ícone do hero + título + subtítulo
          Row(
            children: [
              const SkeletonBox(width: 48, height: 48, borderRadius: 14),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonText(
                      width: w * 0.55,
                      height: 18,
                      borderRadius: 6,
                    ),
                    const SizedBox(height: 8),
                    SkeletonText(
                      width: w * 0.7,
                      height: 11,
                      borderRadius: 4,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Linha 2: ações rápidas (2 botões em pill — Novo imóvel + Filtros)
          Row(
            children: [
              const SkeletonBox(width: 124, height: 36, borderRadius: 18),
              const SizedBox(width: 8),
              const SkeletonBox(width: 92, height: 36, borderRadius: 18),
            ],
          ),
          const SizedBox(height: 16),
          // Linha 3: 4 KPIs lado a lado
          Row(
            children: [
              Expanded(child: kpiTile()),
              const SizedBox(width: 8),
              Expanded(child: kpiTile()),
              const SizedBox(width: 8),
              Expanded(child: kpiTile()),
              const SizedBox(width: 8),
              Expanded(child: kpiTile()),
            ],
          ),
          const SizedBox(height: 22),
          // ── Carrossel "Adicionados recentemente" placeholder ───────────
          Row(
            children: [
              const SkeletonBox(width: 18, height: 18, borderRadius: 4),
              const SizedBox(width: 8),
              const SkeletonText(width: 200, height: 14, borderRadius: 5),
            ],
          ),
          const SizedBox(height: 12),
          SkeletonBox(
            width: double.infinity,
            height: cardH,
            borderRadius: 22,
          ),
          const SizedBox(height: 22),
          // ── Grid placeholder ───────────────────────────────────────────
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: spacingH,
              mainAxisSpacing: spacingV,
              childAspectRatio: aspect,
            ),
            itemCount: 6,
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

  /// Modal de Busca Rápida — bottom sheet premium com input estilizado e
  /// chips de busca recente/sugerida. Substitui o `TextField` padrão Material
  /// por um campo customizado coerente com o restante do app.
  void _showSearchBottomSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black54,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _PropertiesSearchSheet(
        controller: _searchController,
        currentQuery: _searchQuery,
        onSubmit: (q) {
          Navigator.of(sheetCtx).pop();
          _performSearch(q);
        },
        onClear: () {
          _searchController.clear();
          setState(() => _searchQuery = '');
          _persistState();
          Navigator.of(sheetCtx).pop();
          _loadProperties(refresh: true);
        },
      ),
    );
  }

  void _performSearch(String query) {
    setState(() {
      _searchQuery = query;
    });
    _persistState();
    _loadProperties(refresh: true);
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final trimmed = value.trim();
      if (trimmed == _searchQuery.trim()) return;
      _performSearch(trimmed);
    });
  }

  void _onSearchSubmitted(String value) {
    _searchDebounce?.cancel();
    _performSearch(value.trim());
  }

  void _clearHeaderSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    if (_searchQuery.isEmpty) return;
    setState(() => _searchQuery = '');
    _persistState();
    _loadProperties(refresh: true);
  }

  /// Campo de busca livre no header — paridade com web `PropertiesPage`.
  /// Busca endereço, bairro, condomínio, empreendimento, lote, código etc.
  Widget _buildHeaderSearchField(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _portfolioAccentColor(context);
    final hasText = _searchController.text.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: hasText
            ? Color.alphaBlend(
                accent.withValues(alpha: isDark ? 0.10 : 0.05),
                ThemeHelpers.cardBackgroundColor(context),
              )
            : ThemeHelpers.cardBackgroundColor(context),
        border: Border.all(
          color: hasText
              ? accent.withValues(alpha: isDark ? 0.55 : 0.38)
              : ThemeHelpers.borderColor(context),
          width: hasText ? 1.35 : 1,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(
            Icons.search_rounded,
            size: 20,
            color: hasText
                ? accent
                : ThemeHelpers.textSecondaryColor(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
              decoration: InputDecoration(
                hintText:
                    'Buscar por endereço, bairro, condomínio, lote, código…',
                hintStyle: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w500,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
              ),
              onChanged: (value) {
                setState(() {});
                _onSearchChanged(value);
              },
              onSubmitted: _onSearchSubmitted,
            ),
          ),
          if (hasText)
            IconButton(
              icon: Icon(
                Icons.clear_rounded,
                size: 18,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
              visualDensity: VisualDensity.compact,
              tooltip: 'Limpar busca',
              onPressed: _clearHeaderSearch,
            )
          else
            const SizedBox(width: 4),
        ],
      ),
    );
  }

  /// situação, título, endereço, specs e preço — tudo visível de relance.
  Widget _buildScrollablePropertiesViewport(BuildContext context) {
    final theme = Theme.of(context);
    final w = MediaQuery.sizeOf(context).width;
    final horizontal = w < 360 ? 10.0 : 14.0;
    final all = _properties;

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
            child: Padding(
              padding: EdgeInsets.fromLTRB(horizontal, 16, horizontal, 10),
              child: _buildPropertiesListHeader(context, theme, all.length),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 8),
            sliver: SliverList.separated(
              itemCount: all.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                return _buildPropertyBrokerRow(context, theme, all[index]);
              },
            ),
          ),
          if (_isLoadingMore)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.3,
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

  /// Header da listagem — eyebrow accent + contagem (ex.: "23 IMÓVEIS").
  /// Fica entre o hero e a lista, dando contexto sem ocupar muito espaço.
  Widget _buildPropertiesListHeader(
    BuildContext context,
    ThemeData theme,
    int total,
  ) {
    final accent = _portfolioAccentColor(context);
    return Row(
      children: [
        Icon(Icons.view_list_rounded, size: 14, color: accent),
        const SizedBox(width: 6),
        Text(
          'LISTAGEM',
          style: theme.textTheme.labelSmall?.copyWith(
            color: accent,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.65,
            fontSize: 10.5,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '· $total imóve${total == 1 ? "l" : "is"} carregado${total == 1 ? "" : "s"}'
          '${_totalPages > 1 ? " · pg $_currentPage/$_totalPages" : ""}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  /// Row CRM (broker UX): thumbnail à esquerda + bloco denso com info
  /// operacional à direita. Status, código, título, endereço, specs e
  /// preço — TUDO visível sem precisar abrir o imóvel.
  Widget _buildPropertyBrokerRow(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondaryColor = ThemeHelpers.textSecondaryColor(context);
    final borderColor = ThemeHelpers.borderColor(context);
    final price = _formatMainPrice(property);
    final locCompact = _compactLocationLine(property);
    final hasCode = (property.code ?? '').isNotEmpty;
    final cardBg = isDark
        ? Colors.white.withValues(alpha: 0.025)
        : Colors.white;

    final specBits = <_SpecBit>[];
    if (property.bedrooms != null && property.bedrooms! > 0) {
      specBits.add(
        _SpecBit(icon: Icons.bed_rounded, label: '${property.bedrooms}'),
      );
    }
    if (property.suites != null && property.suites! > 0) {
      specBits.add(
        _SpecBit(
          icon: Icons.king_bed_rounded,
          label: '${property.suites} suíte${property.suites! > 1 ? "s" : ""}',
        ),
      );
    }
    if (property.bathrooms != null && property.bathrooms! > 0) {
      specBits.add(
        _SpecBit(icon: Icons.bathtub_rounded, label: '${property.bathrooms}'),
      );
    }
    if (property.parkingSpaces != null && property.parkingSpaces! > 0) {
      specBits.add(
        _SpecBit(
          icon: Icons.directions_car_rounded,
          label: '${property.parkingSpaces}',
        ),
      );
    }
    final area = property.builtArea ?? property.totalArea;
    if (area > 0) {
      specBits.add(
        _SpecBit(
          icon: Icons.square_foot_rounded,
          label: '${area.toStringAsFixed(0)} m²',
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).pushNamed(
          AppRoutes.propertyDetails(property.id),
          arguments: {'property': property},
        ),
        onLongPress: () {
          HapticFeedback.mediumImpact();
          _showPropertyQuickActionsSheet(context, theme, property);
        },
        splashColor: AppColors.primary.primary.withValues(alpha: 0.10),
        highlightColor: AppColors.primary.primary.withValues(alpha: 0.05),
        child: Ink(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: borderColor.withValues(alpha: 0.55),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail 92×92.
                _BrokerRowThumbnail(
                  property: property,
                  fallback: _buildPropertyImageFallback(context, theme),
                ),
                const SizedBox(width: 12),
                // Coluna direita: info densa.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // L1: status + situação + kebab no canto direito.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 5,
                              runSpacing: 4,
                              children: [
                                PropertyStatusPill(
                                  status: property.status,
                                  short: true,
                                  dense: true,
                                ),
                                PropertySituationPill(
                                  isActive: property.isActive,
                                  isAvailableForSite:
                                      property.isAvailableForSite ?? false,
                                  dense: true,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            height: 32,
                            child: _buildPropertyActionsMenu(
                              context,
                              theme,
                              property,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // L2: código + tipo de imóvel.
                      Row(
                        children: [
                          if (hasCode) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: secondaryColor.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: secondaryColor.withValues(alpha: 0.22),
                                ),
                              ),
                              child: Text(
                                '#${property.code}',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: secondaryColor,
                                  letterSpacing: 0.3,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Icon(
                            _typeIconCompact(property.type),
                            size: 12,
                            color: secondaryColor,
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              property.type.label,
                              style: TextStyle(
                                color: secondaryColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                                letterSpacing: -0.05,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // L3: título (1 linha bold).
                      Text(
                        property.title.isEmpty
                            ? 'Sem título'
                            : property.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: textColor,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                          letterSpacing: -0.25,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      // L4: endereço.
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_rounded,
                            size: 11,
                            color: secondaryColor,
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              locCompact,
                              style: TextStyle(
                                color: secondaryColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                                height: 1.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      // L5: specs (quartos/banheiros/area/vagas).
                      if (specBits.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 3,
                          children: [
                            for (final s in specBits)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    s.icon,
                                    size: 12,
                                    color: textColor.withValues(alpha: 0.8),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    s.label,
                                    style: TextStyle(
                                      color: textColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11.5,
                                      height: 1.0,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      // L6: preço (destaque) + divisor invisível.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              price.value,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: textColor,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.4,
                                fontSize: 15.5,
                                height: 1.0,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (property.hasPendingOffers == true) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: const Color(0xFFF59E0B)
                                      .withValues(alpha: 0.32),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(
                                    Icons.request_quote_outlined,
                                    size: 11,
                                    color: Color(0xFFF59E0B),
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Oferta',
                                    style: TextStyle(
                                      color: Color(0xFFF59E0B),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 10.5,
                                      letterSpacing: 0.2,
                                      height: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
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
    );
  }

  IconData _typeIconCompact(PropertyType type) {
    switch (type) {
      case PropertyType.house:
        return Icons.home_outlined;
      case PropertyType.apartment:
        return Icons.apartment;
      case PropertyType.commercial:
        return Icons.storefront_outlined;
      case PropertyType.land:
        return Icons.terrain_outlined;
      case PropertyType.rural:
        return Icons.agriculture_outlined;
    }
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
      _persistState();
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 36, 20, 32),
      child: LayoutBuilder(
        builder: (_, c) => Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: c.maxWidth > 440 ? 380 : double.infinity,
            ),
            child: content(),
          ),
        ),
      ),
    );
  }

  /// Header de portfólio + um child (empty/error) ocupando o resto da viewport.
  ///
  /// Antes era um `Column` com `Expanded(child)`, mas isso travava o header em
  /// altura intrínseca dentro de uma viewport fixa e quando o header era maior
  /// que a tela ele transbordava o `RenderFlex` (ex.: 318px de overflow no
  /// empty state). Agora usamos um `CustomScrollView` com `SliverFillRemaining`
  /// para que o header e o conteúdo *role junto* quando a tela for curta — o
  /// mesmo padrão do viewport com lista cheia (`_buildScrollablePropertiesViewport`).
  Widget _buildHeaderWithFillingChild(
    BuildContext context, {
    required Widget child,
  }) {
    return RefreshIndicator(
      onRefresh: () => _loadProperties(refresh: true),
      color: AppColors.primary.primary,
      displacement: 44,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildPortfolioHeader(context)),
          SliverFillRemaining(
            hasScrollBody: false,
            child: child,
          ),
        ],
      ),
    );
  }

  /// Localização curta só para preview na lista (bairro · cidade quando existir).
  String _compactLocationLine(Property property) {
    final n = property.neighborhood.trim();
    final c = property.city.trim();
    final s = (n.isNotEmpty && c.isNotEmpty)
        ? '$n · $c'
        : _formatPropertyLocation(property);
    if (s.length <= 38) return s;
    return '${s.substring(0, 36)}…';
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
    final canEdit = canUserEditThisPropertyRecord(
      property: property,
      currentUserId: access.userId,
      userRole: access.userRole,
      hasPermission: access.hasPermission,
    );
    final canDelete = canUserDeleteThisPropertyRecord(
      property: property,
      currentUserId: access.userId,
      userRole: access.userRole,
      hasPermission: access.hasPermission,
    );
    final canMatches = access.hasPermission('match:view') &&
        access.isModuleAvailableForCompany('match_system');

    final parentContext = context;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (sheetContext) => _PropertyQuickActionsSheet(
        property: property,
        canMatches: canMatches,
        canEdit: canEdit,
        canDelete: canDelete,
        compactLocation: _compactLocationLine(property),
        priceLine: _formatMainPrice(property).value,
        onOpenDetails: () {
          Navigator.of(sheetContext).pop();
          Future.microtask(() {
            if (!mounted || !parentContext.mounted) return;
            Navigator.of(parentContext).pushNamed(
              AppRoutes.propertyDetails(property.id),
              arguments: {'property': property},
            );
          });
        },
        onOpenMatches: () {
          Navigator.of(sheetContext).pop();
          Future.microtask(() {
            if (!mounted || !parentContext.mounted) return;
            Navigator.of(parentContext).pushNamed(
              AppRoutes.matchesByProperty(property.id),
            );
          });
        },
        onEdit: () {
          Navigator.of(sheetContext).pop();
          Future.microtask(() {
            if (!mounted || !parentContext.mounted) return;
            Navigator.of(parentContext).pushNamed(
              '/properties/${property.id}/edit',
            );
          });
        },
        onDelete: () async {
          Navigator.of(sheetContext).pop();
          await Future<void>.delayed(Duration.zero);
          if (!mounted || !parentContext.mounted) return;
          await _confirmAndDeleteProperty(parentContext, property);
        },
      ),
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

// ============================================================================
// OVERFLOW SHEET — premium bottom sheet do menu de "mais opções" da tela
// ============================================================================

/// Bottom sheet que substitui o `PopupMenu` do botão `more_vert` no AppBar.
///
/// Visual com **identidade própria** ao invés do menu plano padrão do Material:
/// - Header com gradient diagonal (accent → cool) + ícone-orb + título +
///   subtítulo + close
/// - Items agrupados em seções (cada seção com label minúsculo uppercase)
/// - Cada tile tem chip de ícone tinted na cor da intent
/// - Item especial de Busca IA com gradient premium e badge
/// - Animação de entrada padrão de modal sheet (sliding from bottom)
class _PropertiesOverflowSheet extends StatelessWidget {
  final bool hasActiveFilters;
  final int localDraftCount;

  const _PropertiesOverflowSheet({
    required this.hasActiveFilters,
    required this.localDraftCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mq = MediaQuery.of(context);

    return SafeArea(
      top: false,
      child: Container(
        // Sheet ocupa 100% da horizontal — bordas arredondadas só no topo
        // (estilo bottom sheet "atracado"). Sem margens laterais para
        // máximo respiro do conteúdo interno.
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(28),
          ),
          border: Border(
            top: BorderSide(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
              blurRadius: 18,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Drag handle ───────────────────────────────────────────
              Container(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: ThemeHelpers.textSecondaryColor(context)
                          .withValues(alpha: 0.32),
                    ),
                  ),
                ),
              ),
              // ── Header neutro ────────────────────────────────────────
              // Ícone principal sem gradient — minimalista e default. Os
              // tiles abaixo é que carregam a cor (cada um na sua intent),
              // criando contraste com o header neutro.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 14),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        color: ThemeHelpers.textSecondaryColor(context)
                            .withValues(alpha: isDark ? 0.14 : 0.08),
                        border: Border.all(
                          color: ThemeHelpers.borderColor(context),
                        ),
                      ),
                      child: Icon(
                        Icons.tune_rounded,
                        color: ThemeHelpers.textColor(context),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Mais opções',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.3,
                              height: 1.1,
                              color: ThemeHelpers.textColor(context),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Busca, métricas, rascunhos e exportações',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: ThemeHelpers.textSecondaryColor(context),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Fechar',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              // Linha gradient horizontal — separador estiloso do header
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      ThemeHelpers.borderColor(context),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
              // ── Body ─────────────────────────────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(
                  10,
                  10,
                  10,
                  10 + mq.padding.bottom * 0.3,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Seção: Buscar ───────────────────────────────────
                    _SectionLabel(label: 'Buscar'),
                    _OverflowTile(
                      icon: Icons.search_rounded,
                      label: 'Busca rápida',
                      subtitle: 'Endereço, bairro, condomínio, lote, código…',
                      color: const Color(0xFF0891B2), // cyan
                      onTap: () => Navigator.of(context).pop('search'),
                    ),
                    _OverflowAiTile(
                      onTap: () => Navigator.of(context).pop('ai_search'),
                    ),
                    const SizedBox(height: 10),
                    _SectionLabel(label: 'Trabalho em andamento'),
                    _OverflowTile(
                      icon: Icons.folder_special_rounded,
                      label: 'Rascunhos',
                      subtitle: localDraftCount > 0
                          ? '$localDraftCount imóvel(eis) salvo(s) localmente'
                          : 'Sem rascunhos pendentes',
                      color: const Color(0xFFF59E0B), // âmbar
                      trailingBadge: localDraftCount > 0
                          ? '$localDraftCount'
                          : null,
                      onTap: () => Navigator.of(context).pop('drafts'),
                    ),
                    const SizedBox(height: 10),
                    _SectionLabel(label: 'Portfolio'),
                    _OverflowTile(
                      icon: Icons.insights_rounded,
                      label: 'Métricas detalhadas',
                      subtitle: 'KPIs avançados do portfolio',
                      color: const Color(0xFF8B5CF6), // roxo
                      onTap: () => Navigator.of(context).pop('portfolio_metrics'),
                    ),
                    _OverflowTile(
                      icon: Icons.trending_up_rounded,
                      label: 'Otimizar portfolio',
                      subtitle: 'Sugestões para melhorar conversão',
                      color: const Color(0xFF10B981), // verde
                      onTap: () => Navigator.of(context).pop('optimize'),
                    ),
                    const SizedBox(height: 10),
                    _SectionLabel(label: 'Operações'),
                    _OverflowTile(
                      icon: Icons.request_quote_rounded,
                      label: 'Ver ofertas',
                      subtitle: 'Negociações em andamento',
                      color: const Color(0xFF6366F1), // indigo
                      onTap: () => Navigator.of(context).pop('offers'),
                    ),
                    _OverflowTile(
                      icon: Icons.import_export_rounded,
                      label: 'Exportar / Importar',
                      subtitle: 'Planilhas e backups',
                      color: ThemeHelpers.textSecondaryColor(context),
                      neutral: true,
                      onTap: () => Navigator.of(context).pop('export_import'),
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

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              fontSize: 9.5,
            ),
      ),
    );
  }
}

class _OverflowTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final String? trailingBadge;
  final bool neutral;

  const _OverflowTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.trailingBadge,
    this.neutral = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              // Chip do ícone tinted na cor da intent
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  color: neutral
                      ? color.withValues(alpha: isDark ? 0.16 : 0.10)
                      : color.withValues(alpha: isDark ? 0.18 : 0.12),
                  border: Border.all(
                    color: color.withValues(alpha: isDark ? 0.32 : 0.22),
                  ),
                ),
                child: Icon(icon, color: color, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.15,
                        height: 1.2,
                        color: ThemeHelpers.textColor(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: muted,
                        height: 1.3,
                        fontSize: 11.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (trailingBadge != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: color.withValues(alpha: isDark ? 0.22 : 0.14),
                    border: Border.all(
                      color: color.withValues(alpha: isDark ? 0.5 : 0.32),
                    ),
                  ),
                  child: Text(
                    trailingBadge!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: color,
                      fontSize: 10.5,
                      height: 1,
                    ),
                  ),
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  color: muted,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tile especial de "Busca IA" — premium gradient + badge "novo".
class _OverflowAiTile extends StatelessWidget {
  final VoidCallback onTap;

  const _OverflowAiTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = AppColors.primary.primary;
    const cool = Color(0xFF0891B2);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      accent.withValues(alpha: 0.22),
                      cool.withValues(alpha: 0.16),
                    ]
                  : [
                      accent.withValues(alpha: 0.12),
                      cool.withValues(alpha: 0.08),
                    ],
            ),
            border: Border.all(
              color: accent.withValues(alpha: isDark ? 0.45 : 0.32),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: isDark ? 0.22 : 0.10),
                blurRadius: 14,
                spreadRadius: -3,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [accent, Color.lerp(accent, cool, 0.55)!],
                  ),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Busca inteligente',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.2,
                              color: ThemeHelpers.textColor(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: accent,
                          ),
                          child: const Text(
                            'IA',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 9.5,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Descreva o imóvel em linguagem natural',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: ThemeHelpers.textSecondaryColor(context),
                        height: 1.3,
                        fontSize: 11.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: accent,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SEARCH SHEET — modal de Busca Rápida com input customizado
// ============================================================================

/// Bottom sheet premium da Busca Rápida. Substitui o `TextField` Material
/// padrão por um input customizado coerente com o resto do app.
class _PropertiesSearchSheet extends StatefulWidget {
  final TextEditingController controller;
  final String currentQuery;
  final ValueChanged<String> onSubmit;
  final VoidCallback onClear;

  const _PropertiesSearchSheet({
    required this.controller,
    required this.currentQuery,
    required this.onSubmit,
    required this.onClear,
  });

  @override
  State<_PropertiesSearchSheet> createState() => _PropertiesSearchSheetState();
}

class _PropertiesSearchSheetState extends State<_PropertiesSearchSheet> {
  late final FocusNode _focus;

  /// Sugestões rápidas de busca — atalhos reais que cobrem 80% dos casos.
  static const _suggestions = <({String label, IconData icon})>[
    (label: 'Casa', icon: Icons.home_rounded),
    (label: 'Apartamento', icon: Icons.apartment_rounded),
    (label: 'Sala comercial', icon: Icons.business_rounded),
    (label: 'Terreno', icon: Icons.landscape_rounded),
    (label: 'Galpão', icon: Icons.warehouse_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _focus = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = AppColors.primary.primary;
    final mq = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 12),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 12, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      margin: const EdgeInsets.only(top: 4, bottom: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: ThemeHelpers.textSecondaryColor(context)
                            .withValues(alpha: 0.32),
                      ),
                    ),
                  ),
                  // ── Header neutro (mesma estética do overflow) ─────────
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(13),
                          color: ThemeHelpers.textSecondaryColor(context)
                              .withValues(alpha: isDark ? 0.14 : 0.08),
                          border: Border.all(
                            color: ThemeHelpers.borderColor(context),
                          ),
                        ),
                        child: Icon(
                          Icons.search_rounded,
                          color: ThemeHelpers.textColor(context),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Busca rápida',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                                height: 1.1,
                                color: ThemeHelpers.textColor(context),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Por endereço, bairro, condomínio, lote ou código',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: ThemeHelpers.textSecondaryColor(
                                  context,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // ── Input customizado ─────────────────────────────────
                  AnimatedBuilder(
                    animation: Listenable.merge([
                      widget.controller,
                      _focus,
                    ]),
                    builder: (context, _) {
                      final hasText = widget.controller.text.isNotEmpty;
                      final focused = _focus.hasFocus;
                      final highlighted = focused || hasText;
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: highlighted
                              ? Color.alphaBlend(
                                  accent.withValues(
                                    alpha: isDark ? 0.10 : 0.05,
                                  ),
                                  ThemeHelpers.cardBackgroundColor(context),
                                )
                              : ThemeHelpers.cardBackgroundColor(context),
                          border: Border.all(
                            color: highlighted
                                ? accent.withValues(
                                    alpha: isDark ? 0.6 : 0.42,
                                  )
                                : ThemeHelpers.borderColor(context),
                            width: highlighted ? 1.4 : 1,
                          ),
                          boxShadow: highlighted
                              ? [
                                  BoxShadow(
                                    color: accent.withValues(
                                      alpha: isDark ? 0.16 : 0.08,
                                    ),
                                    blurRadius: 12,
                                    spreadRadius: -3,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : null,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.search_rounded,
                                size: 20,
                                color: highlighted
                                    ? accent
                                    : ThemeHelpers.textSecondaryColor(
                                        context,
                                      ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: widget.controller,
                                  focusNode: _focus,
                                  textInputAction: TextInputAction.search,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    height: 1.2,
                                    color: ThemeHelpers.textColor(context),
                                  ),
                                  decoration: InputDecoration(
                                    hintText:
                                        'Buscar por endereço, bairro, condomínio, lote, código…',
                                    hintStyle:
                                        theme.textTheme.bodyMedium?.copyWith(
                                      color:
                                          ThemeHelpers.textSecondaryColor(
                                            context,
                                          ),
                                      fontWeight: FontWeight.w500,
                                    ),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    isDense: true,
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                          horizontal: 0,
                                          vertical: 14,
                                        ),
                                  ),
                                  onSubmitted: widget.onSubmit,
                                ),
                              ),
                              if (hasText)
                                IconButton(
                                  icon: Icon(
                                    Icons.clear_rounded,
                                    size: 18,
                                    color: ThemeHelpers.textSecondaryColor(
                                      context,
                                    ),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                  onPressed: () {
                                    widget.controller.clear();
                                    setState(() {});
                                  },
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  // ── Sugestões rápidas (chips horizontais) ─────────────
                  Text(
                    'SUGESTÕES',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      fontSize: 9.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _suggestions
                        .map(
                          (s) => _buildSuggestionChip(
                            theme: theme,
                            isDark: isDark,
                            accent: accent,
                            label: s.label,
                            icon: s.icon,
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 18),
                  // ── Ações ─────────────────────────────────────────────
                  Row(
                    children: [
                      if (widget.currentQuery.isNotEmpty ||
                          widget.controller.text.isNotEmpty)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: widget.onClear,
                            icon: const Icon(Icons.clear_all_rounded),
                            label: const Text('Limpar busca'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                vertical: 13,
                              ),
                              side: BorderSide(
                                color: ThemeHelpers.borderColor(context),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13),
                              ),
                            ),
                          ),
                        ),
                      if (widget.currentQuery.isNotEmpty ||
                          widget.controller.text.isNotEmpty)
                        const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () =>
                              widget.onSubmit(widget.controller.text),
                          icon: const Icon(Icons.search_rounded),
                          label: const Text('Buscar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              vertical: 13,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionChip({
    required ThemeData theme,
    required bool isDark,
    required Color accent,
    required String label,
    required IconData icon,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          widget.controller.text = label;
          widget.controller.selection = TextSelection.fromPosition(
            TextPosition(offset: label.length),
          );
          setState(() {});
          _focus.requestFocus();
        },
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: ThemeHelpers.cardBackgroundColor(context).withValues(
              alpha: isDark ? 0.7 : 1,
            ),
            border: Border.all(
              color: ThemeHelpers.borderColor(context),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.05,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// PORTFOLIO OPTIMIZATION SHEET — modal de Otimizar com cards selecionáveis
// ============================================================================

class _PortfolioOptimizationFocus {
  final String key;
  final String title;
  final String description;
  final IconData icon;
  final Color color;

  const _PortfolioOptimizationFocus({
    required this.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });
}

/// Modal de Otimização de Portfólio. Substitui os `RadioListTile` Material
/// padrão por cards selecionáveis com identidade visual (ícone tinted, cor
/// por foco, estado selecionado com borda destacada).
class _PortfolioOptimizationSheet extends StatefulWidget {
  final Future<void> Function(String focus) onSubmit;

  const _PortfolioOptimizationSheet({required this.onSubmit});

  @override
  State<_PortfolioOptimizationSheet> createState() =>
      _PortfolioOptimizationSheetState();
}

class _PortfolioOptimizationSheetState
    extends State<_PortfolioOptimizationSheet> {
  String? _selected;
  bool _running = false;

  static const _focuses = <_PortfolioOptimizationFocus>[
    _PortfolioOptimizationFocus(
      key: 'sales_speed',
      title: 'Vendas rápidas',
      description: 'Priorizar imóveis com maior potencial de venda imediata',
      icon: Icons.bolt_rounded,
      color: Color(0xFFF59E0B), // âmbar — agilidade
    ),
    _PortfolioOptimizationFocus(
      key: 'profitability',
      title: 'Maximizar lucro',
      description: 'Priorizar imóveis com maior rentabilidade no portfólio',
      icon: Icons.trending_up_rounded,
      color: Color(0xFF10B981), // verde — dinheiro
    ),
    _PortfolioOptimizationFocus(
      key: 'market_coverage',
      title: 'Cobertura de mercado',
      description: 'Distribuir presença por regiões e perfis variados',
      icon: Icons.public_rounded,
      color: Color(0xFF0891B2), // cyan — alcance
    ),
    _PortfolioOptimizationFocus(
      key: 'balanced',
      title: 'Balanceado',
      description: 'Equilíbrio entre velocidade de venda e rentabilidade',
      icon: Icons.balance_rounded,
      color: Color(0xFF6366F1), // indigo — neutro
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = AppColors.primary.primary;
    final mq = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 12),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 12, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      margin: const EdgeInsets.only(top: 4, bottom: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: ThemeHelpers.textSecondaryColor(context)
                            .withValues(alpha: 0.32),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(13),
                          color: ThemeHelpers.textSecondaryColor(context)
                              .withValues(alpha: isDark ? 0.14 : 0.08),
                          border: Border.all(
                            color: ThemeHelpers.borderColor(context),
                          ),
                        ),
                        child: Icon(
                          Icons.trending_up_rounded,
                          color: ThemeHelpers.textColor(context),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Otimizar portfolio',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                                height: 1.1,
                                color: ThemeHelpers.textColor(context),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Selecione o foco e a IA prioriza ações',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: ThemeHelpers.textSecondaryColor(
                                  context,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _running
                            ? null
                            : () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // ── Cards selecionáveis ────────────────────────────────
                  for (var i = 0; i < _focuses.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    _buildFocusTile(
                      context: context,
                      theme: theme,
                      isDark: isDark,
                      focus: _focuses[i],
                      selected: _selected == _focuses[i].key,
                      onTap: _running
                          ? null
                          : () =>
                              setState(() => _selected = _focuses[i].key),
                    ),
                  ],
                  const SizedBox(height: 18),
                  // ── CTA ─────────────────────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _running
                              ? null
                              : () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            side: BorderSide(
                              color: ThemeHelpers.borderColor(context),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                          ),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: (_selected == null || _running)
                              ? null
                              : () async {
                                  setState(() => _running = true);
                                  await widget.onSubmit(_selected!);
                                  if (mounted) {
                                    setState(() => _running = false);
                                  }
                                },
                          icon: _running
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Icon(Icons.auto_awesome_rounded),
                          label: Text(_running ? 'Otimizando…' : 'Otimizar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFocusTile({
    required BuildContext context,
    required ThemeData theme,
    required bool isDark,
    required _PortfolioOptimizationFocus focus,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    final color = focus.color;
    final disabled = onTap == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: selected
                ? Color.alphaBlend(
                    color.withValues(alpha: isDark ? 0.14 : 0.08),
                    ThemeHelpers.cardBackgroundColor(context),
                  )
                : ThemeHelpers.cardBackgroundColor(context),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: isDark ? 0.55 : 0.4)
                  : ThemeHelpers.borderColor(context),
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: isDark ? 0.18 : 0.10),
                      blurRadius: 12,
                      spreadRadius: -3,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  color: color.withValues(alpha: isDark ? 0.20 : 0.12),
                  border: Border.all(
                    color: color.withValues(alpha: isDark ? 0.42 : 0.28),
                  ),
                ),
                child: Icon(focus.icon, color: color, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      focus.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.15,
                        color: disabled
                            ? ThemeHelpers.textSecondaryColor(context)
                            : ThemeHelpers.textColor(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      focus.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        fontWeight: FontWeight.w500,
                        fontSize: 11.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Indicador de seleção — radio customizado
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? color : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? color
                        : ThemeHelpers.borderColor(context),
                    width: 2,
                  ),
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 14,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// PORTFOLIO METRICS SHEET — Métricas detalhadas fluidas com gráficos
// ============================================================================

/// Bottom sheet "Métricas detalhadas". Sheet quase full-screen com layout
/// editorial: títulos grandes, hierarquia tipográfica clara, **um único
/// gráfico de destaque** (a barra de distribuição) e demais seções
/// puramente tipográficas pra criar balanço visual.
class _PortfolioMetricsSheet extends StatelessWidget {
  final _ListedPropertyMetrics listed;
  final PropertyStats? global;
  final int listedCount;
  final int totalFiltered;
  final bool gatedGlobal;

  const _PortfolioMetricsSheet({
    required this.listed,
    required this.global,
    required this.listedCount,
    required this.totalFiltered,
    required this.gatedGlobal,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mq = MediaQuery.of(context);

    return SafeArea(
      top: false,
      child: Container(
        // Full-width sheet com bordas só no topo. Altura quase total da
        // tela (92%) — a tela "Métricas detalhadas" pede espaço pra
        // respirar e exibir hierarquia tipográfica grande.
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.92),
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(28),
          ),
          border: Border(
            top: BorderSide(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.10),
              blurRadius: 22,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Drag handle ──────────────────────────────────────────
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: ThemeHelpers.textSecondaryColor(context)
                        .withValues(alpha: 0.32),
                  ),
                ),
              ),
              // ── Header editorial — eyebrow + título grande ───────────
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 10, 14, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'PORTFÓLIO · ANÁLISE',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.primary.primary,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.6,
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Métricas detalhadas',
                            style:
                                theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.6,
                              height: 1.05,
                              color: ThemeHelpers.textColor(context),
                              fontSize: 26,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            gatedGlobal
                                ? 'Panorama completo do portfólio'
                                : 'Recorte filtrado da seleção atual',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: ThemeHelpers.textSecondaryColor(
                                context,
                              ),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      iconSize: 26,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              // ── Conteúdo scrollável ──────────────────────────────────
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    22,
                    4,
                    22,
                    24 + mq.padding.bottom * 0.4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildDistributionSection(context, theme, isDark),
                      const SizedBox(height: 36),
                      _buildHighlightsSection(context, theme, isDark),
                      const SizedBox(height: 36),
                      _buildAveragesSection(context, theme, isDark),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // SEÇÃO 1: DISTRIBUIÇÃO — total grande + barra stacked + legenda
  //
  // É a única seção com gráfico visual. As outras são tipográficas pra
  // não saturar a tela.
  // ──────────────────────────────────────────────────────────────────────
  Widget _buildDistributionSection(
    BuildContext context,
    ThemeData theme,
    bool isDark,
  ) {
    final useGlobal = global != null && gatedGlobal;
    final available = useGlobal ? global!.available : listed.available;
    final rented = useGlobal ? global!.rented : listed.rented;
    final sold = useGlobal ? global!.sold : listed.sold;
    final pending = listed.pendingReview;
    final total = useGlobal
        ? global!.total
        : (available + rented + sold + pending);

    final segments = <_MetricSegment>[
      _MetricSegment(
        label: 'Disponíveis',
        value: available,
        color: const Color(0xFF10B981),
      ),
      _MetricSegment(
        label: 'Locação',
        value: rented,
        color: const Color(0xFF6366F1),
      ),
      _MetricSegment(
        label: 'Vendas',
        value: sold,
        color: const Color(0xFFEC4899),
      ),
      if (pending > 0)
        _MetricSegment(
          label: 'Em revisão',
          value: pending,
          color: const Color(0xFFF59E0B),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          eyebrow: useGlobal ? 'NO CRM' : 'NA SELEÇÃO',
          title: 'Distribuição',
        ),
        const SizedBox(height: 18),
        // Total HERO — número gigante à esquerda, label "imóveis" à direita
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                _compactIntFormatter.format(total),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.2,
                  height: 1,
                  color: ThemeHelpers.textColor(context),
                  fontSize: 44,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                total == 1 ? 'imóvel' : 'imóveis',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        // Gráfico — único da tela, estilizado.
        _StackedBar(segments: segments, total: total, isDark: isDark),
        const SizedBox(height: 18),
        // Legenda — bullets coloridos com label, valor e %
        Column(
          children: [
            for (var i = 0; i < segments.length; i++) ...[
              if (i > 0)
                Divider(
                  color: ThemeHelpers.borderColor(context)
                      .withValues(alpha: 0.4),
                  height: 18,
                  thickness: 0.5,
                ),
              _LegendRow(
                segment: segments[i],
                total: total,
                theme: theme,
              ),
            ],
          ],
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // SEÇÃO 2: DESTAQUES — puramente tipográfica (números grandes + label)
  //
  // Em vez de 4 barras horizontais (que somavam ao gráfico da Seção 1 e
  // poluíam visualmente), apresentamos 4 destaques como "stats blocks"
  // tipográficos: número grande + label uppercase + porcentagem ao lado.
  // O bullet colorido pequeno carrega a identidade da intent sem virar
  // mais um gráfico.
  // ──────────────────────────────────────────────────────────────────────
  Widget _buildHighlightsSection(
    BuildContext context,
    ThemeData theme,
    bool isDark,
  ) {
    final base = listedCount > 0 ? listedCount : totalFiltered;
    if (base <= 0) {
      return const SizedBox.shrink();
    }

    final stats = <_HighlightStat>[
      _HighlightStat(
        label: 'Publicados online',
        value: listed.publishedOnline,
        max: base,
        color: const Color(0xFF0891B2),
        icon: Icons.public_rounded,
      ),
      _HighlightStat(
        label: 'Em destaque',
        value: listed.featuredHighlights,
        max: base,
        color: const Color(0xFFF59E0B),
        icon: Icons.workspace_premium_rounded,
      ),
      _HighlightStat(
        label: 'Abertos a negociação',
        value: listed.negotiationFriendly,
        max: base,
        color: const Color(0xFF10B981),
        icon: Icons.handshake_rounded,
      ),
      _HighlightStat(
        label: 'Ativos',
        value: listed.active,
        max: base,
        color: const Color(0xFF8B5CF6),
        icon: Icons.verified_rounded,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          eyebrow: 'NESTA PÁGINA',
          title: 'Destaques',
          rightHint:
              '${_compactIntFormatter.format(base)} ${base == 1 ? "imóvel" : "imóveis"}',
        ),
        const SizedBox(height: 22),
        // Layout 2x2 — números grandes
        for (var i = 0; i < stats.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 22),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _highlightBlock(context, theme, isDark, stats[i]),
                ),
                if (i + 1 < stats.length) ...[
                  Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 14),
                    color: ThemeHelpers.borderColor(context)
                        .withValues(alpha: 0.4),
                  ),
                  Expanded(
                    child: _highlightBlock(
                      context,
                      theme,
                      isDark,
                      stats[i + 1],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _highlightBlock(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    _HighlightStat s,
  ) {
    final pct = s.max > 0 ? (s.value / s.max) * 100 : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            // Bullet colorido (carrega a identidade da intent sem virar
            // gráfico/barra).
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: s.color,
                boxShadow: [
                  BoxShadow(
                    color: s.color.withValues(alpha: isDark ? 0.55 : 0.32),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                s.label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  fontSize: 9.5,
                  height: 1.1,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Número grande — protagonista (evita usar gráfico aqui).
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            _compactIntFormatter.format(s.value),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
              height: 1,
              fontSize: 32,
              color: ThemeHelpers.textColor(context),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${pct.toStringAsFixed(0)}% da seleção',
          style: theme.textTheme.bodySmall?.copyWith(
            color: s.color,
            fontWeight: FontWeight.w800,
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // SEÇÃO 3: MÉDIAS — tipográfica, valores grandes
  // ──────────────────────────────────────────────────────────────────────
  Widget _buildAveragesSection(
    BuildContext context,
    ThemeData theme,
    bool isDark,
  ) {
    final hasAny = listed.avgRentPrice != null ||
        listed.avgSalePriceOnly != null ||
        listed.avgAreaSqm != null;
    if (!hasAny) return const SizedBox.shrink();

    final lines = <_MetricLine>[
      if (listed.avgRentPrice != null)
        _MetricLine(
          label: 'Locação',
          value: _currencyFormatter.format(listed.avgRentPrice),
          icon: Icons.key_rounded,
          color: const Color(0xFF6366F1),
        ),
      if (listed.avgSalePriceOnly != null)
        _MetricLine(
          label: 'Venda',
          value: _currencyFormatter.format(listed.avgSalePriceOnly),
          icon: Icons.sell_outlined,
          color: const Color(0xFFEC4899),
        ),
      if (listed.avgAreaSqm != null)
        _MetricLine(
          label: 'Área',
          value: '${listed.avgAreaSqm!.toStringAsFixed(0)} m²',
          icon: Icons.square_foot_rounded,
          color: const Color(0xFF0891B2),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle(
          eyebrow: 'TICKET',
          title: 'Médias',
          subtitle: 'Valores médios da seleção atual',
        ),
        const SizedBox(height: 22),
        for (var i = 0; i < lines.length; i++) ...[
          if (i > 0)
            Divider(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.35),
              height: 26,
              thickness: 0.5,
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  color: lines[i].color.withValues(alpha: isDark ? 0.18 : 0.12),
                  border: Border.all(
                    color: lines[i].color.withValues(
                      alpha: isDark ? 0.32 : 0.22,
                    ),
                  ),
                ),
                child: Icon(lines[i].icon, color: lines[i].color, size: 17),
              ),
              const SizedBox(width: 14),
              Text(
                lines[i].label.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    lines[i].value,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                      color: ThemeHelpers.textColor(context),
                      fontSize: 22,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Título de seção editorial — eyebrow uppercase pequena + título grande
/// (titleLarge w900) + subtítulo opcional + hint à direita opcional. Cria
/// hierarquia tipográfica consistente entre as 3 seções.
class _SectionTitle extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String? subtitle;
  final String? rightHint;

  const _SectionTitle({
    required this.eyebrow,
    required this.title,
    this.subtitle,
    this.rightHint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                eyebrow,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.primary.primary,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.6,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                  color: ThemeHelpers.textColor(context),
                  height: 1.05,
                  fontSize: 22,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (rightHint != null) ...[
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              rightHint!,
              style: theme.textTheme.labelMedium?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
                fontWeight: FontWeight.w700,
                letterSpacing: -0.1,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Bloco tipográfico de destaque — usado na seção "Destaques" das métricas.
/// Carrega cor da intent via bullet (não barra), pra não duplicar gráficos.
class _HighlightStat {
  final String label;
  final int value;
  final int max;
  final Color color;
  final IconData icon;
  const _HighlightStat({
    required this.label,
    required this.value,
    required this.max,
    required this.color,
    required this.icon,
  });
}

class _MetricSegment {
  final String label;
  final int value;
  final Color color;
  const _MetricSegment({
    required this.label,
    required this.value,
    required this.color,
  });
}

class _StackedBar extends StatelessWidget {
  final List<_MetricSegment> segments;
  final int total;
  final bool isDark;
  const _StackedBar({
    required this.segments,
    required this.total,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (total <= 0) {
      return Container(
        height: 12,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.4),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 12,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 750),
          curve: Curves.easeOutCubic,
          builder: (_, t, _) => Row(
            children: [
              for (final s in segments)
                if (s.value > 0)
                  Expanded(
                    flex: (s.value * 1000).round(),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            s.color.withValues(alpha: 0.85),
                            s.color,
                          ],
                        ),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final _MetricSegment segment;
  final int total;
  final ThemeData theme;
  const _LegendRow({
    required this.segment,
    required this.total,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (segment.value / total) * 100 : 0;
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: segment.color,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            segment.label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: ThemeHelpers.textSecondaryColor(context),
              fontSize: 11.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${segment.value} · ${pct.toStringAsFixed(0)}%',
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: segment.color,
            fontSize: 11,
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
  }
}

class _MetricLine {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _MetricLine({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}

// ============================================================================
// PROPERTY QUICK ACTIONS SHEET — modal de long-press do card de imóvel
// ============================================================================

/// Bottom sheet de ações rápidas do imóvel (acionado por long-press no card).
///
/// Refino sobre a versão antiga:
/// - **Sem `DraggableScrollableSheet`**: o conteúdo cabe naturalmente com
///   `MainAxisSize.min`. Antes abria preso em 46% da tela.
/// - **Header sem thumbnail redundante** — o card já mostra a imagem; aqui
///   priorizamos contexto: eyebrow + título grande + linha localização/preço.
/// - **Cada ação tem cor própria** (cyan, roxo, indigo, vermelho) — quebra
///   a tela "preto-e-vermelho" mantendo intent semântica.
/// - **Tiles fluidos**: borda fina, sem fundo cheio. Cor da intent só
///   destaca o ícone e o título — não enche a tile inteira.
/// - **Sem chevron + ícone duplicados**: só ícone à esquerda; o tap é
///   evidente pelo InkWell ripple.
class _PropertyQuickActionsSheet extends StatelessWidget {
  final Property property;
  final bool canMatches;
  final bool canEdit;
  final bool canDelete;
  final String compactLocation;
  final String? priceLine;
  final VoidCallback onOpenDetails;
  final VoidCallback onOpenMatches;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PropertyQuickActionsSheet({
    required this.property,
    required this.canMatches,
    required this.canEdit,
    required this.canDelete,
    required this.compactLocation,
    required this.priceLine,
    required this.onOpenDetails,
    required this.onOpenMatches,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mq = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        // Sheet "atracado" no rodapé — bordas só no topo, sem margens
        // laterais (full width). Sombra projetando pra cima coerente com
        // a posição.
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(28),
          ),
          border: Border(
            top: BorderSide(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.10),
              blurRadius: 22,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(28),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: ThemeHelpers.textSecondaryColor(context)
                          .withValues(alpha: 0.32),
                    ),
                  ),
                ),
                // ── Header editorial — eyebrow + título + meta ─────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 12, 14, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'AÇÕES RÁPIDAS',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.primary.primary,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.6,
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              property.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.4,
                                color: ThemeHelpers.textColor(context),
                                height: 1.15,
                                fontSize: 19,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.place_outlined,
                                      size: 13,
                                      color: ThemeHelpers.textSecondaryColor(
                                        context,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 220,
                                      ),
                                      child: Text(
                                        compactLocation,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          color: ThemeHelpers
                                                  .textSecondaryColor(
                                                context,
                                              ),
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (priceLine != null &&
                                    priceLine!.trim().isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius:
                                          BorderRadius.circular(999),
                                      color: AppColors.primary.primary
                                          .withValues(
                                        alpha: isDark ? 0.18 : 0.10,
                                      ),
                                      border: Border.all(
                                        color: AppColors.primary.primary
                                            .withValues(
                                          alpha: isDark ? 0.32 : 0.22,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      priceLine!,
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color: AppColors.primary.primary,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 10.5,
                                        letterSpacing: -0.05,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                // Divisor gradient sutil
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 22),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        ThemeHelpers.borderColor(context),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
                // ── Tiles de ação ──────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PropertyQuickActionTile(
                        icon: LucideIcons.layoutGrid,
                        label: 'Abrir ficha',
                        subtitle:
                            'Detalhes, fotos, documentos e histórico',
                        color: const Color(0xFF0891B2), // cyan
                        onTap: onOpenDetails,
                      ),
                      if (canMatches)
                        _PropertyQuickActionTile(
                          icon: LucideIcons.sparkles,
                          label: 'Matches',
                          subtitle:
                              'Clientes compatíveis com este imóvel',
                          color: const Color(0xFF8B5CF6), // roxo
                          onTap: onOpenMatches,
                        ),
                      if (canEdit)
                        _PropertyQuickActionTile(
                          icon: LucideIcons.pencil,
                          label: 'Editar imóvel',
                          subtitle:
                              'Dados, valores, proprietário e galeria',
                          color: const Color(0xFF6366F1), // indigo
                          onTap: onEdit,
                        ),
                      if (canDelete)
                        _PropertyQuickActionTile(
                          icon: LucideIcons.trash2,
                          label: 'Excluir permanentemente',
                          subtitle:
                              'Remove o imóvel do portfólio da empresa',
                          color: theme.colorScheme.error,
                          isDestructive: true,
                          onTap: onDelete,
                        ),
                    ],
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

/// Tile fluida de ação rápida do imóvel — sem fundo cheio nem chevron.
/// Estado idle: borda 1px neutra, ícone tinted na cor da intent.
/// Estado pressionado: tint da cor da intent via InkWell.
class _PropertyQuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool isDestructive;

  const _PropertyQuickActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: color.withValues(alpha: 0.16),
        highlightColor: color.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: color.withValues(alpha: isDark ? 0.18 : 0.12),
                  border: Border.all(
                    color: color.withValues(alpha: isDark ? 0.34 : 0.22),
                  ),
                ),
                child: Icon(icon, size: 19, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.15,
                        color: isDestructive
                            ? color
                            : ThemeHelpers.textColor(context),
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: muted,
                        fontSize: 11.5,
                        height: 1.3,
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

// ──────────────────────────────────────────────────────────────────────────
// Atalhos do corretor: chip strip de escopo + toggles utilitários.
// ──────────────────────────────────────────────────────────────────────────

class _ScopeChipData {
  const _ScopeChipData({
    required this.label,
    required this.icon,
    required this.active,
    required this.tone,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool active;
  final Color tone;
  final VoidCallback onTap;
}

class _PortfolioScopeChip extends StatelessWidget {
  const _PortfolioScopeChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.tone,
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final Color tone;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? tone : ThemeHelpers.textColor(context);
    final bg = active
        ? tone.withValues(alpha: isDark ? 0.18 : 0.12)
        : ThemeHelpers.cardBackgroundColor(context);
    final border = active
        ? tone.withValues(alpha: isDark ? 0.50 : 0.42)
        : ThemeHelpers.borderColor(context).withValues(alpha: 0.55);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        splashColor: tone.withValues(alpha: 0.14),
        highlightColor: tone.withValues(alpha: 0.07),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pareamento (ícone, label) usado dentro do row CRM para specs (quartos,
/// banheiros, área, vagas).
class _SpecBit {
  const _SpecBit({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

/// Thumbnail do row CRM — 92×92 com borda fina e fallback gracioso quando
/// não há `mainImage`. Inclui um chip pequeno no canto inferior direito com
/// o contador total de imagens, útil pro corretor saber qual ficha tem mais
/// material visual.
class _BrokerRowThumbnail extends StatelessWidget {
  const _BrokerRowThumbnail({
    required this.property,
    required this.fallback,
  });

  final Property property;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final imageCount = property.imageCount ?? property.images?.length ?? 0;
    final hasMain = (property.mainImage?.url ?? '').trim().isNotEmpty;
    final borderColor = ThemeHelpers.borderColor(context);

    return SizedBox(
      width: 92,
      height: 92,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: borderColor.withValues(alpha: 0.5),
                ),
              ),
              child: hasMain
                  ? ShimmerImage(
                      imageUrl: property.mainImage!.url,
                      width: 92,
                      height: 92,
                      fit: BoxFit.cover,
                      errorWidget: fallback,
                    )
                  : fallback,
            ),
            if (imageCount > 1)
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.photo_library_outlined,
                        size: 9,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '$imageCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 9.5,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (!hasMain)
              const Positioned(
                top: 6,
                left: 6,
                child: Icon(
                  Icons.image_not_supported_rounded,
                  size: 14,
                  color: Colors.white70,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Toggle 100% flat — ícone + label + hint + switch. Sem background, sem
/// borda, sem sombra: o conteúdo vive direto no fundo do hero. Tap area
/// preservada via `InkWell` com splash sutil.
class _FlatToggleRow extends StatelessWidget {
  const _FlatToggleRow({
    required this.icon,
    required this.inactiveIcon,
    required this.label,
    required this.hint,
    required this.active,
    required this.tone,
    required this.onTap,
  });

  final IconData icon;
  final IconData inactiveIcon;
  final String label;
  final String hint;
  final bool active;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondaryColor = ThemeHelpers.textSecondaryColor(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        splashColor: tone.withValues(alpha: 0.10),
        highlightColor: tone.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: Icon(
                  active ? icon : inactiveIcon,
                  key: ValueKey<bool>(active),
                  size: 19,
                  color: active ? tone : secondaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: active ? tone : textColor,
                        letterSpacing: -0.15,
                        height: 1.1,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondaryColor,
                        fontWeight: FontWeight.w500,
                        fontSize: 11.5,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _PillSwitch(active: active, tone: tone),
            ],
          ),
        ),
      ),
    );
  }
}

/// Switch tipo "pill" — versão premium: track com gradient quando ativo,
/// glow colorido em volta do thumb, ícone de check dentro do thumb quando
/// ligado, e ponto sutil quando desligado. Curva e durações coreografadas.
class _PillSwitch extends StatelessWidget {
  const _PillSwitch({required this.active, required this.tone});

  final bool active;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = ThemeHelpers.borderColor(context);
    final toneDeep = HSLColor.fromColor(tone)
        .withLightness((HSLColor.fromColor(tone).lightness * 0.78)
            .clamp(0.0, 1.0))
        .toColor();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      width: 48,
      height: 28,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        gradient: active
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [tone, toneDeep],
              )
            : null,
        color: active
            ? null
            : (isDark
                ? Colors.white.withValues(alpha: 0.08)
                : borderColor.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? toneDeep.withValues(alpha: 0.45)
              : borderColor.withValues(alpha: isDark ? 0.30 : 0.30),
          width: 1,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: tone.withValues(alpha: isDark ? 0.45 : 0.30),
                  blurRadius: 10,
                  spreadRadius: 0.2,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: active ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 5,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: anim,
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: active
                    ? Icon(
                        Icons.check_rounded,
                        key: const ValueKey('on'),
                        size: 13,
                        color: toneDeep,
                      )
                    : Container(
                        key: const ValueKey('off'),
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: borderColor.withValues(alpha: 0.65),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
