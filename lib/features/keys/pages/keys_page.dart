import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../services/key_service.dart';
import '../models/key_model.dart' as key_models;
import '../widgets/key_card.dart';
import '../widgets/key_control_card.dart';
import '../widgets/key_filters_drawer.dart';

/// Página de listagem de chaves
class KeysPage extends StatefulWidget {
  const KeysPage({super.key});

  @override
  State<KeysPage> createState() => _KeysPageState();
}

class _KeysPageState extends State<KeysPage>
    with SingleTickerProviderStateMixin {
  final KeyService _keyService = KeyService.instance;
  late TabController _tabController;

  // Estado geral
  String? _errorMessage;
  key_models.KeyFilters? _filters;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Tab 0: Todas as Chaves
  List<key_models.Key> _keys = [];
  bool _isLoadingKeys = false;

  // Tab 1: Controles de Chave
  List<key_models.KeyControl> _allControls = [];
  bool _isLoadingControls = false;
  String? _controlStatusFilter;

  // Tab 2: Minhas Chaves
  List<key_models.KeyControl> _userControls = [];
  bool _isLoadingUserControls = false;

  // Estatísticas
  key_models.KeyStatistics? _statistics;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      _loadDataForCurrentTab();
    }
  }

  Future<void> _loadData() async {
    await Future.wait([_loadStatistics(), _loadDataForCurrentTab()]);
  }

  Future<void> _loadDataForCurrentTab() async {
    switch (_tabController.index) {
      case 0:
        await _loadKeys();
        break;
      case 1:
        await _loadAllControls();
        break;
      case 2:
        await _loadUserControls();
        break;
    }
  }

  Future<void> _loadKeys({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _keys.clear();
      });
    }

    setState(() {
      _isLoadingKeys = true;
      _errorMessage = null;
    });

    try {
      final filters =
          _filters?.copyWith(
            search: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
          ) ??
          key_models.KeyFilters(
            search: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
          );

      final response = await _keyService.getKeys(filters: filters);

      if (mounted) {
        if (response.success && response.data != null) {
          setState(() {
            if (refresh) {
              _keys = response.data!;
            } else {
              _keys = response.data!;
            }
            _isLoadingKeys = false;
          });
        } else {
          setState(() {
            _errorMessage = response.message ?? 'Erro ao carregar chaves';
            _isLoadingKeys = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro ao conectar com o servidor';
          _isLoadingKeys = false;
        });
      }
    }
  }

  Future<void> _loadAllControls({String? status}) async {
    setState(() {
      _isLoadingControls = true;
      _errorMessage = null;
      _controlStatusFilter = status;
    });

    try {
      final response = await _keyService.getAllControls(status: status);

      if (mounted) {
        if (response.success && response.data != null) {
          setState(() {
            _allControls = response.data!;
            _isLoadingControls = false;
          });
        } else {
          setState(() {
            _errorMessage = response.message ?? 'Erro ao carregar controles';
            _isLoadingControls = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro ao conectar com o servidor';
          _isLoadingControls = false;
        });
      }
    }
  }

  Future<void> _loadUserControls({String? status}) async {
    setState(() {
      _isLoadingUserControls = true;
      _errorMessage = null;
    });

    try {
      final response = await _keyService.getUserControls(status: status);

      if (mounted) {
        if (response.success && response.data != null) {
          setState(() {
            _userControls = response.data!;
            _isLoadingUserControls = false;
          });
        } else {
          setState(() {
            _errorMessage = response.message ?? 'Erro ao carregar suas chaves';
            _isLoadingUserControls = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro ao conectar com o servidor';
          _isLoadingUserControls = false;
        });
      }
    }
  }

  Future<void> _loadStatistics() async {
    try {
      final response = await _keyService.getStatistics();

      if (mounted) {
        if (response.success && response.data != null) {
          setState(() {
            _statistics = response.data!;
          });
        }
      }
    } catch (e) {
      // Ignorar erros de estatísticas
    }
  }

  bool _hasActiveFilters() {
    return _filters != null &&
        (_filters!.status != null ||
            _filters!.propertyId != null ||
            _filters!.search != null ||
            _filters!.onlyMyData == true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) {
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
        }
      },
      child: AppScaffold(
        title: 'Chaves',
        actions: [
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.filter_list),
                if (_hasActiveFilters())
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
                builder: (context) => KeyFiltersDrawer(
                  initialFilters: _filters,
                  onFiltersChanged: (filters) {
                    setState(() {
                      _filters = filters;
                    });
                    _loadDataForCurrentTab();
                  },
                ),
              );
            },
            tooltip: 'Filtros',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.of(context).pushNamed(AppRoutes.keyCreate);
            },
            tooltip: 'Criar Chave',
          ),
        ],
        body: Column(
          children: [
            // Tabs
            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: ThemeHelpers.borderColor(context),
                    width: 1,
                  ),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: AppColors.primary.primary,
                unselectedLabelColor: ThemeHelpers.textSecondaryColor(context),
                indicatorColor: AppColors.primary.primary,
                dividerColor: Colors.transparent,
                overlayColor: WidgetStateProperty.all(Colors.transparent),
                isScrollable: false,
                tabAlignment: TabAlignment.fill,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.vpn_key_outlined, size: 20),
                    text: 'Todas',
                  ),
                  Tab(
                    icon: Icon(Icons.swap_horiz_outlined, size: 20),
                    text: 'Controles',
                  ),
                  Tab(
                    icon: Icon(Icons.person_outline, size: 20),
                    text: 'Minhas',
                  ),
                ],
              ),
            ),

            // Conteúdo das tabs
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildKeysTab(theme),
                  _buildControlsTab(theme),
                  _buildUserControlsTab(theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsCards(ThemeData theme) {
    if (_statistics == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          bottom: BorderSide(
            color: ThemeHelpers.borderColor(context),
            width: 1,
          ),
        ),
      ),
      child: GridView.count(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.1,
        children: [
          _buildStatCard(
            theme,
            'Total',
            '${_statistics!.totalKeys}',
            Icons.vpn_key,
            AppColors.primary.primary,
          ),
          _buildStatCard(
            theme,
            'Disponíveis',
            '${_statistics!.availableKeys}',
            Icons.check_circle,
            AppColors.status.success,
          ),
          _buildStatCard(
            theme,
            'Em Uso',
            '${_statistics!.inUseKeys}',
            Icons.schedule,
            AppColors.status.warning,
          ),
          _buildStatCard(
            theme,
            'Em Atraso',
            '${_statistics!.overdueCount}',
            Icons.warning,
            AppColors.status.error,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    ThemeData theme,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 22,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w500,
              fontSize: 10,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildKeysTab(ThemeData theme) {
    if (_isLoadingKeys) {
      return _buildSkeleton();
    }

    if (_errorMessage != null) {
      return Center(
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
              _errorMessage!,
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _loadKeys(refresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar Novamente'),
            ),
          ],
        ),
      );
    }

    if (_keys.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.vpn_key_outlined,
              size: 64,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
            const SizedBox(height: 16),
            Text('Nenhuma chave cadastrada', style: theme.textTheme.bodyLarge),
            const SizedBox(height: 8),
            Text(
              'Clique no botão + para criar uma nova chave',
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadKeys(refresh: true),
      child: CustomScrollView(
        slivers: [
          // Estatísticas no topo
          if (_statistics != null)
            SliverToBoxAdapter(child: _buildStatisticsCards(theme)),
          // Lista de chaves
          if (_keys.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.vpn_key_outlined,
                      size: 64,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Nenhuma chave cadastrada',
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Clique no botão + para criar uma nova chave',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final key = _keys[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: KeyCard(
                      keyData: key,
                      onTap: () {
                        _showKeyDetailsModal(context, key);
                      },
                      onCheckout: () {
                        _showCheckoutModal(context, key);
                      },
                      onReturn: null,
                      onEdit: () {
                        _navigateToEditKey(key);
                      },
                      onDelete: () {
                        _deleteKey(context, key);
                      },
                    ),
                  );
                }, childCount: _keys.length),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControlsTab(ThemeData theme) {
    if (_isLoadingControls) {
      return _buildSkeleton();
    }

    if (_errorMessage != null) {
      return Center(
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
              _errorMessage!,
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _loadAllControls(),
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar Novamente'),
            ),
          ],
        ),
      );
    }

    if (_allControls.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.swap_horiz_outlined,
              size: 64,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
            const SizedBox(height: 16),
            Text('Nenhum controle de chave', style: theme.textTheme.bodyLarge),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadAllControls(status: _controlStatusFilter),
      child: CustomScrollView(
        slivers: [
          // Estatísticas no topo
          if (_statistics != null)
            SliverToBoxAdapter(child: _buildStatisticsCards(theme)),
          // Filtro de status
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildStatusChip(theme, null, 'Todos'),
                    const SizedBox(width: 8),
                    _buildStatusChip(theme, 'checked_out', 'Retiradas'),
                    const SizedBox(width: 8),
                    _buildStatusChip(theme, 'returned', 'Devolvidas'),
                    const SizedBox(width: 8),
                    _buildStatusChip(theme, 'overdue', 'Em Atraso'),
                  ],
                ),
              ),
            ),
          ),
          // Lista de controles
          if (_allControls.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.swap_horiz_outlined,
                      size: 64,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Nenhum controle de chave',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final control = _allControls[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: KeyControlCard(
                      control: control,
                      onReturn:
                          control.status ==
                              key_models.KeyControlStatus.checkedOut
                          ? () {
                              _showReturnModal(context, control);
                            }
                          : null,
                      onViewHistory: () {
                        if (control.key != null) {
                          _showKeyHistoryModal(context, control.key!);
                        }
                      },
                    ),
                  );
                }, childCount: _allControls.length),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUserControlsTab(ThemeData theme) {
    if (_isLoadingUserControls) {
      return _buildSkeleton();
    }

    if (_errorMessage != null) {
      return Center(
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
              _errorMessage!,
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _loadUserControls(),
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar Novamente'),
            ),
          ],
        ),
      );
    }

    if (_userControls.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_outline,
              size: 64,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
            const SizedBox(height: 16),
            Text(
              'Você não possui chaves retiradas',
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadUserControls(),
      child: CustomScrollView(
        slivers: [
          // Estatísticas no topo
          if (_statistics != null)
            SliverToBoxAdapter(child: _buildStatisticsCards(theme)),
          // Lista de controles do usuário
          if (_userControls.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 64,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Você não possui chaves retiradas',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final control = _userControls[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: KeyControlCard(
                      control: control,
                      onReturn:
                          control.status ==
                              key_models.KeyControlStatus.checkedOut
                          ? () {
                              _showReturnModal(context, control);
                            }
                          : null,
                      onViewHistory: () {
                        if (control.key != null) {
                          _showKeyHistoryModal(context, control.key!);
                        }
                      },
                    ),
                  );
                }, childCount: _userControls.length),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(ThemeData theme, String? status, String label) {
    final isSelected = _controlStatusFilter == status;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _controlStatusFilter = selected ? status : null;
        });
        _loadAllControls(status: _controlStatusFilter);
      },
    );
  }

  Widget _buildSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SkeletonBox(height: 120, borderRadius: 12),
        );
      },
    );
  }

  Future<void> _showCheckoutModal(
    BuildContext context,
    key_models.Key key,
  ) async {
    if (key.status != key_models.KeyStatus.available) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Esta chave não está disponível para retirada'),
          backgroundColor: AppColors.status.error,
        ),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    final reasonController = TextEditingController();
    final notesController = TextEditingController();
    key_models.KeyControlType? selectedType;
    DateTime? expectedReturnDate;
    TimeOfDay? expectedReturnTime;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: ThemeHelpers.textSecondaryColor(context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Retirar Chave',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context, false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    key.name,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Tipo de Uso *',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: key_models.KeyControlType.values.map((type) {
                      final isSelected = selectedType == type;
                      return ChoiceChip(
                        label: Text(type.label),
                        selected: isSelected,
                        onSelected: (selected) {
                          setModalState(() {
                            selectedType = selected ? type : null;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: reasonController,
                    decoration: const InputDecoration(
                      labelText: 'Motivo da Retirada *',
                      hintText: 'Ex: Visita de cliente interessado',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Motivo é obrigatório';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: notesController,
                    decoration: const InputDecoration(
                      labelText: 'Observações (opcional)',
                      hintText: 'Observações adicionais',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Data Prevista de Devolução (opcional)',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: 'Data',
                            hintText: 'DD/MM/AAAA',
                            border: const OutlineInputBorder(),
                            suffixIcon: const Icon(Icons.calendar_today),
                          ),
                          controller: TextEditingController(
                            text: expectedReturnDate != null
                                ? DateFormat(
                                    'dd/MM/yyyy',
                                  ).format(expectedReturnDate!)
                                : '',
                          ),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: expectedReturnDate ?? DateTime.now(),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                              locale: const Locale('pt', 'BR'),
                            );
                            if (picked != null) {
                              setModalState(() {
                                expectedReturnDate = picked;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: 'Hora',
                            hintText: 'HH:MM',
                            border: const OutlineInputBorder(),
                            suffixIcon: const Icon(Icons.access_time),
                          ),
                          controller: TextEditingController(
                            text: expectedReturnTime != null
                                ? '${expectedReturnTime!.hour.toString().padLeft(2, '0')}:${expectedReturnTime!.minute.toString().padLeft(2, '0')}'
                                : '',
                          ),
                          onTap: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime:
                                  expectedReturnTime ?? TimeOfDay.now(),
                            );
                            if (picked != null) {
                              setModalState(() {
                                expectedReturnTime = picked;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (formKey.currentState!.validate()) {
                              if (selectedType == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                      'Por favor, selecione o tipo de uso',
                                    ),
                                    backgroundColor: AppColors.status.error,
                                  ),
                                );
                                return;
                              }
                              Navigator.pop(context, true);
                            }
                          },
                          icon: const Icon(Icons.logout),
                          label: const Text('Retirar Chave'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context, false),
                          icon: const Icon(Icons.close),
                          label: const Text('Cancelar'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
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

    if (result != true || selectedType == null) {
      reasonController.dispose();
      notesController.dispose();
      return;
    }

    try {
      String? expectedReturnDateStr;
      if (expectedReturnDate != null) {
        final dateTime = DateTime(
          expectedReturnDate!.year,
          expectedReturnDate!.month,
          expectedReturnDate!.day,
          expectedReturnTime?.hour ?? 18,
          expectedReturnTime?.minute ?? 0,
        );
        expectedReturnDateStr = dateTime.toIso8601String();
      }

      final dto = key_models.CreateKeyControlDto(
        keyId: key.id,
        type: selectedType!.value,
        reason: reasonController.text.trim(),
        notes: notesController.text.trim().isEmpty
            ? null
            : notesController.text.trim(),
        expectedReturnDate: expectedReturnDateStr,
      );

      final response = await _keyService.checkoutKey(dto);

      if (mounted) {
        if (response.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Chave retirada com sucesso'),
              backgroundColor: AppColors.status.success,
            ),
          );
          _loadDataForCurrentTab();
          _loadStatistics();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao retirar chave'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    } finally {
      reasonController.dispose();
      notesController.dispose();
    }
  }

  Future<void> _showReturnModal(
    BuildContext context,
    key_models.KeyControl control,
  ) async {
    if (control.status != key_models.KeyControlStatus.checkedOut) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Este controle já foi devolvido'),
          backgroundColor: AppColors.status.error,
        ),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    final returnNotesController = TextEditingController();

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: ThemeHelpers.textSecondaryColor(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Devolver Chave',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context, false),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  control.key?.name ?? 'Chave',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: returnNotesController,
                  decoration: const InputDecoration(
                    labelText: 'Observações da Devolução (opcional)',
                    hintText: 'Ex: Chave devolvida em perfeito estado',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 24),
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context, true);
                        },
                        icon: const Icon(Icons.login),
                        label: const Text('Devolver Chave'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context, false),
                        icon: const Icon(Icons.close),
                        label: const Text('Cancelar'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
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
    );

    if (result != true) {
      returnNotesController.dispose();
      return;
    }

    try {
      final dto = key_models.ReturnKeyDto(
        returnNotes: returnNotesController.text.trim().isEmpty
            ? null
            : returnNotesController.text.trim(),
      );

      final response = await _keyService.returnKey(control.id, dto);

      if (mounted) {
        if (response.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Chave devolvida com sucesso'),
              backgroundColor: AppColors.status.success,
            ),
          );
          _loadDataForCurrentTab();
          _loadStatistics();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao devolver chave'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    } finally {
      returnNotesController.dispose();
    }
  }

  Future<void> _showKeyHistoryModal(
    BuildContext context,
    key_models.Key key,
  ) async {
    bool isLoading = true;
    List<key_models.KeyHistoryRecord> history = [];
    String? errorMessage;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          if (isLoading) {
            _keyService.getKeyHistory(key.id).then((response) {
              if (mounted) {
                setModalState(() {
                  isLoading = false;
                  if (response.success && response.data != null) {
                    history = response.data!;
                  } else {
                    errorMessage =
                        response.message ?? 'Erro ao carregar histórico';
                  }
                });
              }
            });
          }

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.9,
            ),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: ThemeHelpers.cardBackgroundColor(context),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: ThemeHelpers.textSecondaryColor(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Histórico da Chave',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  key.name,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
                const SizedBox(height: 20),
                Flexible(
                  child: isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : errorMessage != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 48,
                                color: ThemeHelpers.textSecondaryColor(context),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                errorMessage!,
                                style: Theme.of(context).textTheme.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : history.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.history,
                                size: 48,
                                color: ThemeHelpers.textSecondaryColor(context),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Nenhum histórico encontrado',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: history.length,
                          itemBuilder: (context, index) {
                            final record = history[index];
                            return _buildHistoryItem(context, record);
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHistoryItem(
    BuildContext context,
    key_models.KeyHistoryRecord record,
  ) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.primary.withValues(alpha: 0.1),
          child: Icon(
            _getHistoryIcon(record.action),
            color: AppColors.primary.primary,
            size: 20,
          ),
        ),
        title: Text(record.description),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (record.user != null) Text('Por: ${record.user!.name}'),
            Text(
              dateFormat.format(DateTime.parse(record.createdAt)),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }

  IconData _getHistoryIcon(String action) {
    switch (action) {
      case 'create':
        return Icons.add;
      case 'update':
        return Icons.edit;
      case 'delete':
        return Icons.delete;
      case 'checkout':
        return Icons.logout;
      case 'return':
        return Icons.login;
      default:
        return Icons.history;
    }
  }

  void _navigateToEditKey(key_models.Key key) {
    Navigator.of(context).pushNamed(AppRoutes.keyEdit(key.id)).then((result) {
      if (result == true) {
        _loadDataForCurrentTab();
      }
    });
  }

  Future<void> _showKeyDetailsModal(
    BuildContext context,
    key_models.Key key,
  ) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: ThemeHelpers.textSecondaryColor(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      key.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildDetailRow(context, 'Tipo', key.type.label, Icons.category),
              _buildDetailRow(context, 'Status', key.status.label, Icons.info),
              if (key.property != null)
                _buildDetailRow(
                  context,
                  'Propriedade',
                  key.property!.title,
                  Icons.home,
                ),
              if (key.location != null && key.location!.isNotEmpty)
                _buildDetailRow(
                  context,
                  'Localização',
                  key.location!,
                  Icons.location_on,
                ),
              if (key.description != null && key.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Descrição',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  key.description!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              if (key.notes != null && key.notes!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Observações',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(key.notes!, style: Theme.of(context).textTheme.bodyMedium),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _navigateToEditKey(key);
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('Editar'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showCheckoutModal(context, key);
                      },
                      icon: const Icon(Icons.logout),
                      label: const Text('Retirar'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: ThemeHelpers.textSecondaryColor(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteKey(BuildContext context, key_models.Key key) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.status.error),
            const SizedBox(width: 12),
            const Expanded(child: Text('Confirmar Exclusão')),
          ],
        ),
        content: Text(
          'Tem certeza que deseja excluir a chave "${key.name}"? Esta ação não pode ser desfeita.',
        ),
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

    if (confirmed != true) return;

    try {
      final response = await _keyService.deleteKey(key.id);

      if (mounted) {
        if (response.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Chave excluída com sucesso'),
              backgroundColor: AppColors.status.success,
            ),
          );
          _loadKeys(refresh: true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao excluir chave'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    }
  }
}
