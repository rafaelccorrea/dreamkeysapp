import 'package:flutter/material.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../core/routes/app_routes.dart';
import '../services/match_service.dart';
import '../models/match_model.dart';
import '../widgets/match_card.dart';
import '../widgets/match_filters_drawer.dart';
import '../widgets/ignore_match_modal.dart';

/// Página principal de matches
class MatchesPage extends StatefulWidget {
  final String? propertyId;
  final String? clientId;

  const MatchesPage({
    super.key,
    this.propertyId,
    this.clientId,
  });

  @override
  State<MatchesPage> createState() => _MatchesPageState();
}

class _MatchesPageState extends State<MatchesPage> {
  final MatchService _matchService = MatchService.instance;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  List<Match> _matches = [];
  int _currentPage = 1;
  int _totalPages = 1;
  String? _errorMessage;
  MatchStatus? _statusFilter;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadMatches();
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
        _loadMoreMatches();
      }
    }
  }

  Future<void> _loadMatches({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _currentPage = 1;
        _matches.clear();
      });
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _matchService.getMatches(
        status: _statusFilter,
        page: _currentPage,
        limit: 20,
        propertyId: widget.propertyId,
        clientId: widget.clientId,
      );

      if (mounted) {
        if (response.success && response.data != null) {
          setState(() {
            if (refresh) {
              _matches = response.data!.matches;
            } else {
              _matches.addAll(response.data!.matches);
            }
            _totalPages = response.data!.totalPages;
            _isLoading = false;
            _isLoadingMore = false;
          });
        } else {
          setState(() {
            _errorMessage = response.message ?? 'Erro ao carregar matches';
            _isLoading = false;
            _isLoadingMore = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro de conexão: $e';
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMoreMatches() async {
    if (_isLoadingMore || _currentPage >= _totalPages) return;

    setState(() {
      _isLoadingMore = true;
      _currentPage++;
    });

    await _loadMatches();
  }

  Future<void> _handleAccept(Match match) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aceitar Match'),
        content: Text(
          'Deseja aceitar este match? Uma task e uma nota serão criadas automaticamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Aceitar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final response = await _matchService.acceptMatch(match.id);

    if (mounted) {
      if (response.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Match aceito! Task e nota criadas.'),
            action: SnackBarAction(
              label: 'Workspace',
              onPressed: () {
                // Navegar para workspace
              },
            ),
          ),
        );
        _loadMatches(refresh: true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.message ?? 'Erro ao aceitar match'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleIgnore(Match match) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => IgnoreMatchModal(
        match: match,
        onIgnore: (reason, notes) async {
          final response = await _matchService.ignoreMatch(
            match.id,
            reason,
            notes: notes,
          );

          if (mounted) {
            if (response.success) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Match ignorado')),
              );
              _loadMatches(refresh: true);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(response.message ?? 'Erro ao ignorar match'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _handleView(Match match) async {
    await _matchService.viewMatch(match.id);
    // Navegar para detalhes da propriedade ou cliente
    if (match.property.id.isNotEmpty) {
      Navigator.pushNamed(
        context,
        AppRoutes.propertyDetails(match.property.id),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      title: widget.propertyId != null || widget.clientId != null
          ? 'Matches'
          : 'Matches',
      currentBottomNavIndex: 0,
      showBottomNavigation: widget.propertyId == null && widget.clientId == null,
      actions: [
        IconButton(
          icon: Stack(
            children: [
              const Icon(Icons.filter_list),
              if (_statusFilter != null)
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
              useSafeArea: true,
              backgroundColor: Colors.transparent,
              builder: (context) => MatchFiltersDrawer(
                statusFilter: _statusFilter,
                onFiltersChanged: (status) {
                  setState(() {
                    _statusFilter = status;
                  });
                  _loadMatches(refresh: true);
                },
              ),
            );
          },
          tooltip: 'Filtros',
        ),
      ],
      body: Column(
        children: [
          // Busca
          _buildSearchBar(context, theme),

          // Conteúdo principal
          Expanded(
            child: _isLoading && _matches.isEmpty
                ? _buildSkeleton(context, theme)
                : _errorMessage != null && _matches.isEmpty
                    ? _buildErrorState(context, theme)
                    : RefreshIndicator(
                        onRefresh: () => _loadMatches(refresh: true),
                        child: _matches.isEmpty
                            ? _buildEmptyState(context, theme)
                            : ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                itemCount:
                                    _matches.length + (_isLoadingMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index >= _matches.length) {
                                    return const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(16),
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  }
                                  return MatchCard(
                                    match: _matches[index],
                                    onAccept: () => _handleAccept(_matches[index]),
                                    onIgnore: () => _handleIgnore(_matches[index]),
                                    onView: () => _handleView(_matches[index]),
                                  );
                                },
                              ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: ThemeHelpers.cardBackgroundColor(context),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Buscar por cliente ou propriedade...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                    _loadMatches(refresh: true);
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: ThemeHelpers.borderLightColor(context),
            ),
          ),
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
        onSubmitted: (value) {
          _loadMatches(refresh: true);
        },
      ),
    );
  }

  Widget _buildSkeleton(BuildContext context, ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SkeletonBox(width: 100, height: 20),
                    const Spacer(),
                    SkeletonBox(width: 60, height: 20),
                  ],
                ),
                const SizedBox(height: 16),
                SkeletonBox(width: double.infinity, height: 150),
                const SizedBox(height: 16),
                SkeletonBox(width: double.infinity, height: 20),
                const SizedBox(height: 8),
                SkeletonBox(width: 200, height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildErrorState(BuildContext context, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Erro ao carregar matches',
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => _loadMatches(refresh: true),
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhum match encontrado',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Não há matches disponíveis no momento.',
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
}

