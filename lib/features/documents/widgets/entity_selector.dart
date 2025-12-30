import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../clients/services/client_service.dart';
import '../../clients/models/client_model.dart';
import '../../../shared/services/property_service.dart' as property_service;
import '../../../shared/services/property_service.dart';

/// Widget para selecionar cliente ou propriedade
class EntitySelector extends StatefulWidget {
  final String type; // 'client' ou 'property'
  final String? selectedId;
  final String? selectedName;
  final Function(String id, String name) onSelected;

  const EntitySelector({
    super.key,
    required this.type,
    this.selectedId,
    this.selectedName,
    required this.onSelected,
  });

  @override
  State<EntitySelector> createState() => _EntitySelectorState();
}

class _EntitySelectorState extends State<EntitySelector> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;
  
  // Para clientes
  List<Client> _clients = [];
  bool _isLoadingClients = false;
  int _clientsPage = 1;
  int _clientsTotalPages = 1;
  bool _hasMoreClients = true;
  final ScrollController _clientsScrollController = ScrollController();
  
  // Para propriedades
  List<property_service.Property> _properties = [];
  bool _isLoadingProperties = false;
  int _propertiesPage = 1;
  int _propertiesTotalPages = 1;
  bool _hasMoreProperties = true;
  final ScrollController _propertiesScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.selectedName ?? '';
    _clientsScrollController.addListener(_onClientsScroll);
    _propertiesScrollController.addListener(_onPropertiesScroll);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _clientsScrollController.removeListener(_onClientsScroll);
    _clientsScrollController.dispose();
    _propertiesScrollController.removeListener(_onPropertiesScroll);
    _propertiesScrollController.dispose();
    super.dispose();
  }

  void _onClientsScroll() {
    if (_clientsScrollController.position.pixels >=
        _clientsScrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingClients && _hasMoreClients && _clientsPage < _clientsTotalPages) {
        _loadMoreClients();
      }
    }
  }

  void _onPropertiesScroll() {
    if (_propertiesScrollController.position.pixels >=
        _propertiesScrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingProperties && _hasMoreProperties && _propertiesPage < _propertiesTotalPages) {
        _loadMoreProperties();
      }
    }
  }

  Future<void> _loadClients({bool reset = false}) async {
    if (reset) {
      setState(() {
        _clientsPage = 1;
        _clients.clear();
      });
    }

    setState(() => _isLoadingClients = true);

    try {
      final filters = ClientSearchFilters(
        search: _searchController.text.trim().isEmpty 
            ? null 
            : _searchController.text.trim(),
        page: _clientsPage,
        limit: 50,
      );

      final response = await ClientService.instance.getClients(filters: filters);
      
      if (mounted && response.success && response.data != null) {
        setState(() {
          if (reset) {
            _clients = response.data!.data;
          } else {
            _clients.addAll(response.data!.data);
          }
          _clientsTotalPages = response.data!.pagination?.totalPages ?? 1;
          _hasMoreClients = _clientsPage < _clientsTotalPages;
          _isLoadingClients = false;
        });
      } else {
        setState(() => _isLoadingClients = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingClients = false);
      }
    }
  }

  Future<void> _loadMoreClients() async {
    if (_isLoadingClients || !_hasMoreClients) return;
    
    setState(() => _clientsPage++);
    await _loadClients();
  }

  Future<void> _loadProperties({bool reset = false}) async {
    if (reset) {
      setState(() {
        _propertiesPage = 1;
        _properties.clear();
      });
    }

    setState(() => _isLoadingProperties = true);

    try {
      final filters = property_service.PropertyFilters(
        search: _searchController.text.trim().isEmpty 
            ? null 
            : _searchController.text.trim(),
      );

      final response = await PropertyService.instance.getProperties(
        page: _propertiesPage,
        limit: 50,
        filters: filters,
      );
      
      if (mounted && response.success && response.data != null) {
        setState(() {
          if (reset) {
            _properties = response.data!.data;
          } else {
            _properties.addAll(response.data!.data);
          }
          _propertiesTotalPages = response.data!.totalPages;
          _hasMoreProperties = _propertiesPage < _propertiesTotalPages;
          _isLoadingProperties = false;
        });
      } else {
        setState(() => _isLoadingProperties = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingProperties = false);
      }
    }
  }

  Future<void> _loadMoreProperties() async {
    if (_isLoadingProperties || !_hasMoreProperties) return;
    
    setState(() => _propertiesPage++);
    await _loadProperties();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (widget.type == 'client') {
        _loadClients(reset: true);
      } else {
        _loadProperties(reset: true);
      }
    });
  }

  Future<void> _selectEntity() async {
    if (widget.type == 'client') {
      await _showClientSelector();
    } else {
      await _showPropertySelector();
    }
  }

  Future<void> _showClientSelector() async {
    debugPrint('🔍 [ENTITY_SELECTOR] _showClientSelector - Abrindo modal de seleção de clientes');
    // Resetar busca ao abrir
    _searchController.clear();
    // Carregar clientes ao abrir o modal
    debugPrint('🔍 [ENTITY_SELECTOR] Carregando clientes...');
    await _loadClients(reset: true);
    debugPrint('🔍 [ENTITY_SELECTOR] Clientes carregados: ${_clients.length}');

    final selected = await showModalBottomSheet<Client>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Selecionar Cliente',
                      style: TextStyle(
                        fontSize: 20,
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
            ),
            // Busca
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Buscar cliente...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: _onSearchChanged,
              ),
            ),
            const SizedBox(height: 16),
            // Lista
            Flexible(
              child: _isLoadingClients && _clients.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _clients.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(40),
                            child: Text(
                              _searchController.text.trim().isEmpty
                                  ? 'Nenhum cliente encontrado'
                                  : 'Nenhum cliente encontrado para "${_searchController.text.trim()}"',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: ThemeHelpers.textSecondaryColor(context),
                                  ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _clientsScrollController,
                          shrinkWrap: true,
                          itemCount: _clients.length + (_isLoadingClients ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= _clients.length) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            final client = _clients[index];
                            final isSelected = client.id == widget.selectedId;
                            return ListTile(
                              leading: CircleAvatar(
                                child: Text(client.name.isNotEmpty
                                    ? client.name[0].toUpperCase()
                                    : '?'),
                              ),
                              title: Text(client.name),
                              subtitle: client.email.isNotEmpty
                                  ? Text(client.email)
                                  : null,
                              selected: isSelected,
                              selectedTileColor: AppColors.primary.primary.withValues(alpha: 0.1),
                              onTap: () {
                                debugPrint('🔍 [ENTITY_SELECTOR] Cliente clicado:');
                                debugPrint('   - ID: ${client.id}');
                                debugPrint('   - Name: ${client.name}');
                                debugPrint('   - ID length: ${client.id.length}');
                                Navigator.pop(context, client);
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );

    if (selected != null) {
      debugPrint('🔍 [ENTITY_SELECTOR] Cliente selecionado:');
      debugPrint('   - ID: ${selected.id}');
      debugPrint('   - Name: ${selected.name}');
      if (selected.id.isEmpty || selected.id.trim().isEmpty) {
        debugPrint('❌ [ENTITY_SELECTOR] ID do cliente está vazio!');
      }
      widget.onSelected(selected.id.trim(), selected.name);
    }
  }

  Future<void> _showPropertySelector() async {
    // Resetar busca ao abrir
    _searchController.clear();
    // Carregar propriedades ao abrir o modal
    await _loadProperties(reset: true);

    final selected = await showModalBottomSheet<property_service.Property>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Selecionar Propriedade',
                      style: TextStyle(
                        fontSize: 20,
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
            ),
            // Busca
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Buscar propriedade...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: _onSearchChanged,
              ),
            ),
            const SizedBox(height: 16),
            // Lista
            Flexible(
              child: _isLoadingProperties && _properties.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _properties.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(40),
                            child: Text(
                              _searchController.text.trim().isEmpty
                                  ? 'Nenhuma propriedade encontrada'
                                  : 'Nenhuma propriedade encontrada para "${_searchController.text.trim()}"',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: ThemeHelpers.textSecondaryColor(context),
                                  ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _propertiesScrollController,
                          shrinkWrap: true,
                          itemCount: _properties.length + (_isLoadingProperties ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= _properties.length) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            final property = _properties[index];
                            final isSelected = property.id == widget.selectedId;
                            return ListTile(
                              leading: const Icon(Icons.home),
                              title: Text(property.title),
                              subtitle: property.code != null
                                  ? Text('Código: ${property.code}')
                                  : Text(property.address),
                              selected: isSelected,
                              selectedTileColor: AppColors.primary.primary.withValues(alpha: 0.1),
                              onTap: () {
                                Navigator.pop(context, property);
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );

    if (selected != null) {
      widget.onSelected(selected.id, selected.title);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    debugPrint('🔍 [ENTITY_SELECTOR] build - type: ${widget.type}');
    debugPrint('   - selectedId: ${widget.selectedId}');
    debugPrint('   - selectedName: ${widget.selectedName}');
    
    return InkWell(
      onTap: () {
        debugPrint('🔍 [ENTITY_SELECTOR] InkWell onTap - Abrindo seletor');
        _selectEntity();
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: widget.type == 'client' ? 'Cliente *' : 'Propriedade *',
          hintText: widget.type == 'client'
              ? 'Selecione um cliente'
              : 'Selecione uma propriedade',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          prefixIcon: Icon(
            widget.type == 'client' ? Icons.person : Icons.home,
          ),
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          widget.selectedName ?? 
              (widget.type == 'client' ? 'Selecione um cliente' : 'Selecione uma propriedade'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: widget.selectedName != null
                ? ThemeHelpers.textColor(context)
                : ThemeHelpers.textSecondaryColor(context),
          ),
        ),
      ),
    );
  }
}

