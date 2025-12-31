import 'package:flutter/material.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/theme_helpers.dart';
import '../services/inspection_service.dart';
import '../models/inspection_model.dart';
import '../widgets/inspection_card.dart';
import '../widgets/inspection_filters_drawer.dart';

/// Página de listagem de vistorias
class InspectionsPage extends StatefulWidget {
  const InspectionsPage({super.key});

  @override
  State<InspectionsPage> createState() => _InspectionsPageState();
}

class _InspectionsPageState extends State<InspectionsPage> {
  final InspectionService _inspectionService = InspectionService.instance;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  List<Inspection> _inspections = [];
  int _currentPage = 1;
  int _totalPages = 1;
  String? _errorMessage;
  InspectionFilters? _filters;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadInspections();
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
      if (!_isLoadingMore && _currentPage < _totalPages) {
        _loadMoreInspections();
      }
    }
  }

  Future<void> _loadInspections({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _currentPage = 1;
        _inspections.clear();
      });
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final filters = _filters?.copyWith(
            title: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
            page: _currentPage,
            limit: 20,
          ) ??
          InspectionFilters(
            title: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
            page: _currentPage,
            limit: 20,
          );

      final response = await _inspectionService.listInspections(filters: filters);

      if (mounted) {
        if (response.success && response.data != null) {
          setState(() {
            if (refresh) {
              _inspections = response.data!.inspections;
            } else {
              _inspections.addAll(response.data!.inspections);
            }
            _totalPages = response.data!.totalPages;
            _isLoading = false;
            _isLoadingMore = false;
          });
        } else {
          setState(() {
            _errorMessage = response.message ?? 'Erro ao carregar vistorias';
            _isLoading = false;
            _isLoadingMore = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro ao conectar com o servidor';
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMoreInspections() async {
    if (_isLoadingMore || _currentPage >= _totalPages) return;

    setState(() {
      _isLoadingMore = true;
      _currentPage++;
    });

    await _loadInspections();
  }

  Future<void> _handleSearch(String query) async {
    setState(() {
      _searchQuery = query;
      _currentPage = 1;
      _inspections.clear();
    });
    await _loadInspections(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Vistorias',
      actions: [
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.filter_list),
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
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (context) => InspectionFiltersDrawer(
                  initialFilters: _filters,
                  onFiltersChanged: (filters) {
                    setState(() {
                      _filters = filters;
                    });
                    _loadInspections(refresh: true);
                  },
                ),
              );
            },
            tooltip: 'Filtros',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.of(context).pushNamed(AppRoutes.inspectionCreate);
            },
            tooltip: 'Nova Vistoria',
          ),
        ],
      body: Column(
        children: [
            // Barra de busca
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Buscar vistorias...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _handleSearch('');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (value) {
                  // Debounce será implementado se necessário
                  _handleSearch(value);
                },
              ),
            ),
            // Conteúdo principal
            Expanded(
              child: _isLoading && _inspections.isEmpty
                  ? _buildSkeleton(context, theme)
                  : _errorMessage != null && _inspections.isEmpty
                      ? _buildErrorState(context, theme)
                      : _inspections.isEmpty
                          ? _buildEmptyState(context, theme)
                          : RefreshIndicator(
                              onRefresh: () => _loadInspections(refresh: true),
                              child: CustomScrollView(
                                controller: _scrollController,
                                slivers: [
                                  SliverPadding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    sliver: SliverList(
                                      delegate: SliverChildBuilderDelegate(
                                        (context, index) {
                                          if (index >= _inspections.length) {
                                            return const Center(
                                              child: Padding(
                                                padding: EdgeInsets.all(16),
                                                child: CircularProgressIndicator(),
                                              ),
                                            );
                                          }
                                          return InspectionCard(
                                            inspection: _inspections[index],
                                          );
                                        },
                                        childCount: _inspections.length +
                                            (_isLoadingMore ? 1 : 0),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
            ),
        ],
      ),
    );
  }

  bool _hasActiveFilters() {
    if (_filters == null) return false;
    return _filters!.status != null ||
        _filters!.type != null ||
        _filters!.propertyId != null ||
        _filters!.inspectorId != null ||
        _filters!.startDate != null ||
        _filters!.endDate != null ||
        (_filters!.onlyMyData ?? false);
  }

  Widget _buildSkeleton(BuildContext context, ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: List.generate(
          5,
          (index) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SkeletonBox(
              width: double.infinity,
              height: 120,
              borderRadius: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Erro ao carregar vistorias',
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadInspections,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.home_repair_service_outlined,
              size: 64,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhuma vistoria encontrada',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Comece criando uma nova vistoria',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pushNamed(AppRoutes.inspectionCreate);
              },
              icon: const Icon(Icons.add),
              label: const Text('Nova Vistoria'),
            ),
          ],
        ),
      ),
    );
  }
}
