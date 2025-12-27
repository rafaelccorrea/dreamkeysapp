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

// Formatter de moeda
final _currencyFormatter = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 2,
);

/// Página de listagem de propriedades
class PropertiesPage extends StatefulWidget {
  const PropertiesPage({super.key});

  @override
  State<PropertiesPage> createState() => _PropertiesPageState();
}

class _PropertiesPageState extends State<PropertiesPage> {
  final PropertyService _propertyService = PropertyService.instance;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  List<Property> _properties = [];
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
          setState(() {
            _properties = response.data!.data;
            _totalPages = response.data!.totalPages;
            _total = response.data!.total;
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = response.message ?? 'Erro ao carregar propriedades';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ [PROPERTIES_PAGE] Erro: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro ao conectar com o servidor';
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
                Navigator.of(context).pushNamed('/properties/offers');
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.background.backgroundSecondaryDarkMode
            : AppColors.background.backgroundSecondary,
        border: Border(
          bottom: BorderSide(
            color: ThemeHelpers.borderColor(context),
            width: 1,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Botão Criar
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pushNamed('/properties/create');
              },
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Criar Propriedade'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Botão Busca Inteligente
            OutlinedButton.icon(
              onPressed: () {
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
                            onPressed: () {
                              // TODO: Navegar para página de resultados
                            },
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
              icon: const Icon(Icons.auto_awesome, size: 20),
              label: const Text('Busca Inteligente'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Botão Otimização
            OutlinedButton.icon(
              onPressed: () {
                _showOptimizationDialog(context);
              },
              icon: const Icon(Icons.trending_up, size: 20),
              label: const Text('Otimizar Portfólio'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
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
                              ).pushNamed('/properties/${result.propertyId}');
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
                            ).pushNamed('/properties/${result.propertyId}');
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: AppColors.status.error),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Erro ao carregar propriedades',
              style: theme.textTheme.titleMedium?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _loadProperties(refresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.home_outlined,
                size: 64,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
              const SizedBox(height: 16),
              Text(
                'Nenhuma propriedade encontrada',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Comece criando sua primeira propriedade',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadProperties(refresh: true),
      child: Column(
        children: [
          Expanded(child: _buildListView(context, theme)),
          if (_totalPages > 1) _buildPagination(context),
        ],
      ),
    );
  }

  Widget _buildListView(BuildContext context, ThemeData theme) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(20),
      itemCount: _properties.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _properties.length) {
          // Indicador de carregamento no final
          return const Padding(
            padding: EdgeInsets.all(20.0),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final property = _properties[index];
        return _buildPropertyListCard(context, theme, property);
      },
    );
  }

  Widget _buildPropertyListCard(
    BuildContext context,
    ThemeData theme,
    Property property,
  ) {
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark
              ? AppColors.border.borderDarkMode
              : AppColors.border.border,
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).pushNamed('/properties/${property.id}');
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Imagem em full width com botão de ação
            Stack(
              children: [
                Container(
                  width: double.infinity,
                  height: 200,
                  color: isDark
                      ? AppColors.background.backgroundSecondaryDarkMode
                      : AppColors.background.backgroundSecondary,
                  child: property.mainImage != null
                      ? ShimmerImage(
                          imageUrl: property.mainImage!.url,
                          width: double.infinity,
                          height: 200,
                          fit: BoxFit.cover,
                          errorWidget: Center(
                            child: Icon(
                              Icons.home_outlined,
                              size: 64,
                              color: ThemeHelpers.textSecondaryColor(context),
                            ),
                          ),
                        )
                      : Center(
                          child: Icon(
                            Icons.home_outlined,
                            size: 64,
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                        ),
                ),
                // Badge de contagem de imagens
                if (property.imageCount != null && property.imageCount! > 1)
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.photo_library,
                            size: 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${property.imageCount}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Botão de ação no canto superior direito
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.primary.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_vert,
                        color: Colors.white,
                        size: 20,
                      ),
                      color: theme.scaffoldBackgroundColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      onSelected: (value) async {
                        if (value == 'edit' && mounted) {
                          Navigator.of(
                            context,
                          ).pushNamed('/properties/${property.id}/edit');
                        } else if (value == 'delete') {
                          final confirm = await showModalBottomSheet<bool>(
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
                            builder: (context) => Padding(
                              padding: EdgeInsets.only(
                                bottom: MediaQuery.of(
                                  context,
                                ).viewInsets.bottom,
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(20),
                                child: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Expanded(
                                            child: Text(
                                              'Excluir Propriedade',
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.close),
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Tem certeza que deseja excluir "${property.title}"? Esta ação não pode ser desfeita.',
                                      ),
                                      const SizedBox(height: 24),
                                      Column(
                                        children: [
                                          SizedBox(
                                            width: double.infinity,
                                            child: ElevatedButton.icon(
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              icon: const Icon(Icons.delete),
                                              label: const Text(
                                                'Excluir Propriedade',
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    AppColors.status.error,
                                                foregroundColor: Colors.white,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          SizedBox(
                                            width: double.infinity,
                                            child: OutlinedButton.icon(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
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

                          if (confirm == true && mounted) {
                            final messenger = ScaffoldMessenger.of(context);
                            final response = await _propertyService
                                .deleteProperty(property.id);
                            if (!mounted) return;

                            if (response.success) {
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Propriedade excluída com sucesso',
                                  ),
                                ),
                              );
                              _loadProperties(refresh: true);
                            } else {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    response.message ??
                                        'Erro ao excluir propriedade',
                                  ),
                                  backgroundColor: AppColors.status.error,
                                ),
                              );
                            }
                          }
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(
                                Icons.edit,
                                size: 20,
                                color: ThemeHelpers.textColor(context),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Editar',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: ThemeHelpers.textColor(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              const Icon(
                                Icons.delete,
                                size: 20,
                                color: Colors.red,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Excluir',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Informações abaixo da imagem
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tipo e Status no topo
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.primary.withValues(
                            alpha: 0.1,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          property.type.label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.primary.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _getStatusColor(
                            property.status,
                          ).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          property.status.label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _getStatusColor(property.status),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (property.isAvailableForSite == true)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.status.success.withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.public,
                                size: 14,
                                color: AppColors.status.success,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Publicado',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.status.success,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Título (destaque principal)
                  Text(
                    property.title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: ThemeHelpers.textColor(context),
                      fontSize: 18,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (property.code != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Código: ${property.code}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),

                  // Localização
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 18,
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          property.address.isNotEmpty
                              ? property.address
                              : '${property.street}, ${property.number} - ${property.neighborhood}, ${property.city} - ${property.state}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Características principais
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (property.bedrooms != null)
                        _buildFeatureChip(
                          context,
                          theme,
                          Icons.bed,
                          '${property.bedrooms} quartos',
                        ),
                      if (property.bathrooms != null)
                        _buildFeatureChip(
                          context,
                          theme,
                          Icons.bathtub_outlined,
                          '${property.bathrooms} banheiros',
                        ),
                      if (property.parkingSpaces != null)
                        _buildFeatureChip(
                          context,
                          theme,
                          Icons.local_parking,
                          '${property.parkingSpaces} vagas',
                        ),
                      if (property.totalArea > 0)
                        _buildFeatureChip(
                          context,
                          theme,
                          Icons.square_foot,
                          '${property.totalArea.toInt()}m²',
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Preço (destaque)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.primary.primary.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Preço principal
                        if (property.salePrice != null)
                          Text(
                            _currencyFormatter.format(property.salePrice),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary.primary,
                              fontSize: 24,
                            ),
                          )
                        else if (property.rentPrice != null)
                          Text(
                            '${_currencyFormatter.format(property.rentPrice)}/mês',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary.primary,
                              fontSize: 24,
                            ),
                          ),
                        // Valores adicionais
                        if (property.condominiumFee != null ||
                            property.iptu != null) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 16,
                            runSpacing: 8,
                            children: [
                              if (property.condominiumFee != null)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.apartment,
                                      size: 16,
                                      color: ThemeHelpers.textSecondaryColor(
                                        context,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Condomínio: ${_currencyFormatter.format(property.condominiumFee)}',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color:
                                                ThemeHelpers.textSecondaryColor(
                                                  context,
                                                ),
                                          ),
                                    ),
                                  ],
                                ),
                              if (property.iptu != null)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.receipt,
                                      size: 16,
                                      color: ThemeHelpers.textSecondaryColor(
                                        context,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'IPTU: ${_currencyFormatter.format(property.iptu)}',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color:
                                                ThemeHelpers.textSecondaryColor(
                                                  context,
                                                ),
                                          ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ],
                      ],
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

  Widget _buildFeatureChip(
    BuildContext context,
    ThemeData theme,
    IconData icon,
    String label,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? AppColors.background.backgroundSecondaryDarkMode
            : AppColors.background.backgroundSecondary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ThemeHelpers.borderColor(context), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.primary.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.brightness == Brightness.dark
                ? AppColors.border.borderDarkMode
                : AppColors.border.border,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Página $_currentPage de $_totalPages ($_total itens)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentPage > 1
                    ? () {
                        setState(() {
                          _currentPage--;
                        });
                        _loadProperties();
                      }
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _currentPage < _totalPages
                    ? () {
                        setState(() {
                          _currentPage++;
                        });
                        _loadProperties();
                      }
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
