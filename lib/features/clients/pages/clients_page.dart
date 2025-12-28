import 'package:flutter/material.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../core/routes/app_routes.dart';
import '../../../shared/utils/masks.dart';
import '../services/client_service.dart';
import '../models/client_model.dart';
import '../widgets/client_filters_drawer.dart';
import '../widgets/transfer_client_modal.dart';
import '../widgets/async_excel_import_modal.dart';
import '../../matches/widgets/matches_badge.dart';

/// Página de listagem de clientes
class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key});

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  final ClientService _clientService = ClientService.instance;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  List<Client> _clients = [];
  int _currentPage = 1;
  int _totalPages = 1;
  String? _errorMessage;
  ClientSearchFilters? _filters;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  ClientStatistics? _statistics;

  @override
  void initState() {
    super.initState();
    _loadClients();
    _loadStatistics();
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
        _loadMoreClients();
      }
    }
  }

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
      final filters = _filters?.copyWith(
            search: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
            page: _currentPage,
            limit: 50,
          ) ??
          ClientSearchFilters(
            search: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
            page: _currentPage,
            limit: 50,
          );

      final response = await _clientService.getClients(filters: filters);

      if (mounted) {
        if (response.success && response.data != null) {
          setState(() {
            if (refresh) {
              _clients = response.data!.data;
            } else {
              _clients.addAll(response.data!.data);
            }
            _totalPages = response.data!.pagination?.totalPages ?? 1;
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
      if (mounted && response.success && response.data != null) {
        setState(() {
          _statistics = response.data;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar estatísticas: $e');
    }
  }

  Future<void> _handleSearch(String query) async {
    setState(() {
      _searchQuery = query;
      _currentPage = 1;
      _clients.clear();
    });
    await _loadClients(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Clientes',
      currentBottomNavIndex: 3,
      showBottomNavigation: true,
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
              useSafeArea: true,
              backgroundColor: Colors.transparent,
              builder: (context) => ClientFiltersDrawer(
                initialFilters: _filters,
                onFiltersChanged: (filters) {
                  setState(() {
                    _filters = filters;
                  });
                  _loadClients(refresh: true);
                  _loadStatistics();
                },
              ),
            );
          },
          tooltip: 'Filtros',
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            switch (value) {
              case 'import':
                _showImportModal();
                break;
              case 'export':
                _exportClients();
                break;
              case 'new':
                Navigator.pushNamed(context, AppRoutes.clientCreate);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'new',
              child: Row(
                children: [
                  Icon(Icons.add, size: 20),
                  SizedBox(width: 8),
                  Text('Novo Cliente'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'import',
              child: Row(
                children: [
                  Icon(Icons.upload_file, size: 20),
                  SizedBox(width: 8),
                  Text('Importar Excel'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'export',
              child: Row(
                children: [
                  Icon(Icons.download, size: 20),
                  SizedBox(width: 8),
                  Text('Exportar'),
                ],
              ),
            ),
          ],
        ),
      ],
      body: Column(
        children: [
          // Barra de ações
          _buildActionBar(context, theme),
          
          // Conteúdo principal
          Expanded(
            child: _isLoading && _clients.isEmpty
                ? _buildSkeleton(context, theme)
                : _errorMessage != null && _clients.isEmpty
                    ? _buildErrorState(context, theme)
                    : RefreshIndicator(
                        onRefresh: () => _loadClients(refresh: true),
                        child: Column(
                          children: [
                            // Estatísticas
                            if (_statistics != null) _buildStatistics(context, theme),
                            
                            // Busca
                            _buildSearchBar(context, theme),
                            
                            // Lista de clientes
                            Expanded(
                              child: _clients.isEmpty
                                  ? _buildEmptyState(context, theme)
                                  : ListView.builder(
                                      controller: _scrollController,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      itemCount: _clients.length + (_isLoadingMore ? 1 : 0),
                                      itemBuilder: (context, index) {
                                        if (index >= _clients.length) {
                                          return const Center(
                                            child: Padding(
                                              padding: EdgeInsets.all(16),
                                              child: CircularProgressIndicator(),
                                            ),
                                          );
                                        }
                                        return _buildClientCard(context, theme, _clients[index]);
                                      },
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

  Widget _buildSkeleton(BuildContext context, ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          SkeletonBox(width: double.infinity, height: 100, borderRadius: 12),
          const SizedBox(height: 16),
          SkeletonBox(width: double.infinity, height: 60, borderRadius: 12),
          const SizedBox(height: 16),
          ...List.generate(
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
        ],
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
              color: AppColors.status.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Erro ao carregar clientes',
              style: theme.textTheme.titleLarge?.copyWith(
                color: ThemeHelpers.textColor(context),
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
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _loadClients(refresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar Novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar(BuildContext context, ThemeData theme) {
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
      child: Row(
        children: [
          // Botão Criar
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pushNamed(context, AppRoutes.clientCreate);
              },
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Novo Cliente'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatistics(BuildContext context, ThemeData theme) {
    if (_statistics == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ThemeHelpers.borderLightColor(context),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Estatísticas',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                context,
                theme,
                'Total',
                _statistics!.totalClients.toString(),
                Icons.people,
              ),
              _buildStatItem(
                context,
                theme,
                'Ativos',
                _statistics!.activeClients.toString(),
                Icons.check_circle,
                AppColors.status.success,
              ),
              _buildStatItem(
                context,
                theme,
                'Compradores',
                _statistics!.buyers.toString(),
                Icons.shopping_cart,
                AppColors.primary.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    ThemeData theme,
    String label,
    String value,
    IconData icon, [
    Color? color,
  ]) {
    final statColor = color ?? ThemeHelpers.textSecondaryColor(context);
    
    return Column(
      children: [
        Icon(icon, color: statColor, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: statColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar(BuildContext context, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ThemeHelpers.borderLightColor(context),
          width: 1,
        ),
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Buscar por nome, email, telefone ou CPF...',
          prefixIcon: Icon(
            Icons.search,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                  onPressed: () {
                    _searchController.clear();
                    _handleSearch('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        onChanged: (value) {
          _handleSearch(value);
        },
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
              Icons.people_outline,
              size: 64,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhum cliente encontrado',
              style: theme.textTheme.titleLarge?.copyWith(
                color: ThemeHelpers.textColor(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Tente buscar com outros termos'
                  : 'Comece adicionando seu primeiro cliente',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pushNamed(context, AppRoutes.clientCreate);
              },
              icon: const Icon(Icons.add),
              label: const Text('Novo Cliente'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _hasActiveFilters() {
    if (_filters == null) return false;
    return _filters!.name != null ||
        _filters!.email != null ||
        _filters!.phone != null ||
        _filters!.document != null ||
        _filters!.city != null ||
        _filters!.neighborhood != null ||
        _filters!.state != null ||
        _filters!.type != null ||
        _filters!.status != null ||
        _filters!.isActive != null ||
        _filters!.onlyMyData != null ||
        _filters!.createdFrom != null ||
        _filters!.createdTo != null ||
        _filters!.sortBy != null;
  }

  Future<void> _showClientActions(BuildContext context, Client client) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      client.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Editar'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Transferir'),
              onTap: () => Navigator.pop(context, 'transfer'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Excluir', style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (action == 'edit') {
      Navigator.pushNamed(context, AppRoutes.clientEdit(client.id));
    } else if (action == 'transfer') {
      _showTransferModal(context, client);
    } else if (action == 'delete') {
      _showDeleteConfirmation(context, client);
    }
  }

  Future<void> _showTransferModal(BuildContext context, Client client) async {
    final result = await showDialog(
      context: context,
      builder: (context) => TransferClientModal(
        clientId: client.id,
        clientName: client.name,
        currentResponsibleUserId: client.responsibleUserId,
        currentResponsibleName: client.responsibleUser?.name,
      ),
    );

    if (result == true) {
      _loadClients(refresh: true);
      _loadStatistics();
    }
  }

  Future<void> _showDeleteConfirmation(BuildContext context, Client client) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: Text('Tem certeza que deseja excluir o cliente "${client.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.status.error,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final response = await _clientService.deleteClient(client.id);
      if (mounted) {
        if (response.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Cliente excluído com sucesso!'),
              backgroundColor: AppColors.status.success,
            ),
          );
          _loadClients(refresh: true);
          _loadStatistics();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao excluir cliente'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _showImportModal() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
    // Mostrar modal de escolha de formato
    final format = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Exportar Clientes',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.table_chart),
              title: const Text('Excel (.xlsx)'),
              onTap: () => Navigator.pop(context, 'xlsx'),
            ),
            ListTile(
              leading: const Icon(Icons.description),
              title: const Text('CSV (.csv)'),
              onTap: () => Navigator.pop(context, 'csv'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );

    if (format == null || !mounted) return;

    // Mostrar loading
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Text('Exportando clientes...'),
            ],
          ),
          duration: const Duration(seconds: 30),
        ),
      );
    }

    try {
      final response = await _clientService.exportClients(
        filters: _filters,
        format: format,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();

        if (response.success && response.data != null) {
          // TODO: Salvar arquivo usando path_provider ou file_saver
          // Por enquanto, apenas mostra mensagem de sucesso
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Exportação concluída! ${response.data!.length} bytes',
              ),
              backgroundColor: AppColors.status.success,
              action: SnackBarAction(
                label: 'OK',
                textColor: Colors.white,
                onPressed: () {},
              ),
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
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao exportar: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    }
  }

  Widget _buildClientCard(BuildContext context, ThemeData theme, Client client) {
    final typeColor = _getTypeColor(client.type, context);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: ThemeHelpers.borderLightColor(context),
          width: 1,
        ),
      ),
      color: ThemeHelpers.cardBackgroundColor(context),
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(
            context,
            AppRoutes.clientDetails(client.id),
          );
        },
        onLongPress: () {
          _showClientActions(context, client);
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar/Inicial
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      typeColor.withOpacity(0.2),
                      typeColor.withOpacity(0.1),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: typeColor.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    client.name.isNotEmpty ? client.name[0].toUpperCase() : '?',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: typeColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Informações
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nome e Badge de Tipo
                    Row(
                      children: [
                        Expanded(
                          child: MatchesBadge(
                            clientId: client.id,
                            onClick: () {
                              Navigator.pushNamed(
                                context,
                                AppRoutes.matchesByClient(client.id),
                              );
                            },
                            child: Text(
                              client.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: ThemeHelpers.textColor(context),
                                fontSize: 16,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: typeColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: typeColor.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            client.type.label,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: typeColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Email
                    Row(
                      children: [
                        Icon(
                          Icons.email_outlined,
                          size: 16,
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            client.email,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: ThemeHelpers.textSecondaryColor(context),
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Telefone e Cidade
                    Row(
                      children: [
                        Icon(
                          Icons.phone_outlined,
                          size: 16,
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          client.phone.isNotEmpty ? Masks.phone(client.phone) : 'Sem telefone',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                            fontSize: 13,
                          ),
                        ),
                        if (client.city.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          Icon(
                            Icons.location_on_outlined,
                            size: 14,
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${client.city} - ${client.state}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: ThemeHelpers.textSecondaryColor(context),
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Ícone de navegação
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.chevron_right,
                  color: ThemeHelpers.textSecondaryColor(context),
                  size: 24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getTypeColor(ClientType type, BuildContext context) {
    switch (type) {
      case ClientType.buyer:
        return AppColors.status.success;
      case ClientType.seller:
        return AppColors.status.warning;
      case ClientType.renter:
        return AppColors.primary.primary;
      case ClientType.lessor:
        return AppColors.status.info;
      case ClientType.investor:
        return Colors.purple;
      case ClientType.general:
        return ThemeHelpers.textSecondaryColor(context);
    }
  }
}

/// Extensão para copiar filtros
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

