import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../shared/widgets/custom_button.dart';
import '../models/client_model.dart';

/// Widget de filtros avançados para clientes
class ClientFiltersDrawer extends StatefulWidget {
  final ClientSearchFilters? initialFilters;
  final Function(ClientSearchFilters?) onFiltersChanged;

  const ClientFiltersDrawer({
    super.key,
    this.initialFilters,
    required this.onFiltersChanged,
  });

  @override
  State<ClientFiltersDrawer> createState() => _ClientFiltersDrawerState();
}

class _ClientFiltersDrawerState extends State<ClientFiltersDrawer> {
  // Controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _documentController = TextEditingController();
  final _cityController = TextEditingController();
  final _neighborhoodController = TextEditingController();
  final _stateController = TextEditingController();
  final _createdFromController = TextEditingController();
  final _createdToController = TextEditingController();

  // Seleções
  ClientType? _selectedType;
  ClientStatus? _selectedStatus;
  bool? _isActive;
  bool? _onlyMyData;
  String? _sortBy;
  String? _sortOrder;

  @override
  void initState() {
    super.initState();
    _loadInitialFilters();
  }

  void _loadInitialFilters() {
    final filters = widget.initialFilters;
    if (filters == null) return;

    _nameController.text = filters.name ?? '';
    _emailController.text = filters.email ?? '';
    _phoneController.text = filters.phone ?? '';
    _documentController.text = filters.document ?? '';
    _cityController.text = filters.city ?? '';
    _neighborhoodController.text = filters.neighborhood ?? '';
    _stateController.text = filters.state ?? '';
    _createdFromController.text = filters.createdFrom ?? '';
    _createdToController.text = filters.createdTo ?? '';
    _selectedType = filters.type;
    _selectedStatus = filters.status;
    _isActive = filters.isActive;
    _onlyMyData = filters.onlyMyData;
    _sortBy = filters.sortBy;
    _sortOrder = filters.sortOrder;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _documentController.dispose();
    _cityController.dispose();
    _neighborhoodController.dispose();
    _stateController.dispose();
    _createdFromController.dispose();
    _createdToController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context, TextEditingController controller) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      locale: const Locale('pt', 'BR'),
    );
    if (picked != null) {
      controller.text = DateFormat('yyyy-MM-dd').format(picked);
    }
  }

  void _applyFilters() {
    final filters = ClientSearchFilters(
      name: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
      email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
      phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      document: _documentController.text.trim().isEmpty ? null : _documentController.text.trim(),
      city: _cityController.text.trim().isEmpty ? null : _cityController.text.trim(),
      neighborhood: _neighborhoodController.text.trim().isEmpty ? null : _neighborhoodController.text.trim(),
      state: _stateController.text.trim().isEmpty ? null : _stateController.text.trim().toUpperCase(),
      type: _selectedType,
      status: _selectedStatus,
      isActive: _isActive,
      onlyMyData: _onlyMyData,
      createdFrom: _createdFromController.text.trim().isEmpty ? null : _createdFromController.text.trim(),
      createdTo: _createdToController.text.trim().isEmpty ? null : _createdToController.text.trim(),
      sortBy: _sortBy,
      sortOrder: _sortOrder,
    );

    widget.onFiltersChanged(filters);
    Navigator.of(context).pop();
  }

  void _clearFilters() {
    setState(() {
      _nameController.clear();
      _emailController.clear();
      _phoneController.clear();
      _documentController.clear();
      _cityController.clear();
      _neighborhoodController.clear();
      _stateController.clear();
      _createdFromController.clear();
      _createdToController.clear();
      _selectedType = null;
      _selectedStatus = null;
      _isActive = null;
      _onlyMyData = null;
      _sortBy = null;
      _sortOrder = null;
    });
    widget.onFiltersChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.85,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: ThemeHelpers.cardBackgroundColor(context),
                border: Border(
                  bottom: BorderSide(
                    color: ThemeHelpers.borderLightColor(context),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.filter_list,
                    color: AppColors.primary.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Filtros Avançados',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Conteúdo
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Busca por texto
                    _buildSectionTitle(context, theme, 'Busca'),
                    const SizedBox(height: 12),
                    CustomTextField(
                      controller: _nameController,
                      label: 'Nome',
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                    const SizedBox(height: 12),
                    CustomTextField(
                      controller: _emailController,
                      label: 'Email',
                      prefixIcon: const Icon(Icons.email_outlined),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                    CustomTextField(
                      controller: _phoneController,
                      label: 'Telefone',
                      prefixIcon: const Icon(Icons.phone_outlined),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    CustomTextField(
                      controller: _documentController,
                      label: 'CPF',
                      prefixIcon: const Icon(Icons.badge_outlined),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 24),
                    // Localização
                    _buildSectionTitle(context, theme, 'Localização'),
                    const SizedBox(height: 12),
                    CustomTextField(
                      controller: _cityController,
                      label: 'Cidade',
                      prefixIcon: const Icon(Icons.location_city_outlined),
                    ),
                    const SizedBox(height: 12),
                    CustomTextField(
                      controller: _neighborhoodController,
                      label: 'Bairro',
                      prefixIcon: const Icon(Icons.place_outlined),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _stateController,
                      decoration: InputDecoration(
                        labelText: 'Estado (UF)',
                        prefixIcon: const Icon(Icons.map_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      maxLength: 2,
                      textCapitalization: TextCapitalization.characters,
                    ),
                    const SizedBox(height: 24),
                    // Classificações
                    _buildSectionTitle(context, theme, 'Classificações'),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<ClientType>(
                      value: _selectedType,
                      decoration: InputDecoration(
                        labelText: 'Tipo de Cliente',
                        prefixIcon: const Icon(Icons.category_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Todos'),
                        ),
                        ...ClientType.values.map((type) {
                          return DropdownMenuItem(
                            value: type,
                            child: Text(type.label),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedType = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<ClientStatus>(
                      value: _selectedStatus,
                      decoration: InputDecoration(
                        labelText: 'Status',
                        prefixIcon: const Icon(Icons.info_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Todos'),
                        ),
                        ...ClientStatus.values.map((status) {
                          return DropdownMenuItem(
                            value: status,
                            child: Text(status.label),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedStatus = value;
                        });
                      },
                    ),
                    const SizedBox(height: 24),
                    // Estado e Escopo
                    _buildSectionTitle(context, theme, 'Estado e Escopo'),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Apenas Ativos'),
                      value: _isActive ?? false,
                      onChanged: (value) {
                        setState(() {
                          _isActive = value;
                        });
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Apenas Meus Clientes'),
                      value: _onlyMyData ?? false,
                      onChanged: (value) {
                        setState(() {
                          _onlyMyData = value;
                        });
                      },
                    ),
                    const SizedBox(height: 24),
                    // Período de Criação
                    _buildSectionTitle(context, theme, 'Período de Criação'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _createdFromController,
                      decoration: InputDecoration(
                        labelText: 'Data Inicial',
                        prefixIcon: const Icon(Icons.calendar_today_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      readOnly: true,
                      onTap: () => _selectDate(context, _createdFromController),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _createdToController,
                      decoration: InputDecoration(
                        labelText: 'Data Final',
                        prefixIcon: const Icon(Icons.calendar_today_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      readOnly: true,
                      onTap: () => _selectDate(context, _createdToController),
                    ),
                    const SizedBox(height: 24),
                    // Ordenação
                    _buildSectionTitle(context, theme, 'Ordenação'),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _sortBy,
                      decoration: InputDecoration(
                        labelText: 'Ordenar por',
                        prefixIcon: const Icon(Icons.sort_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('Padrão')),
                        DropdownMenuItem(value: 'name', child: Text('Nome')),
                        DropdownMenuItem(value: 'createdAt', child: Text('Data de Criação')),
                        DropdownMenuItem(value: 'status', child: Text('Status')),
                        DropdownMenuItem(value: 'type', child: Text('Tipo')),
                        DropdownMenuItem(value: 'city', child: Text('Cidade')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _sortBy = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    if (_sortBy != null)
                      DropdownButtonFormField<String>(
                        value: _sortOrder ?? 'ASC',
                        decoration: InputDecoration(
                          labelText: 'Direção',
                          prefixIcon: const Icon(Icons.arrow_upward_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'ASC', child: Text('Crescente')),
                          DropdownMenuItem(value: 'DESC', child: Text('Decrescente')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _sortOrder = value;
                          });
                        },
                      ),
                  ],
                ),
              ),
            ),
            // Botões de ação
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: ThemeHelpers.cardBackgroundColor(context),
                border: Border(
                  top: BorderSide(
                    color: ThemeHelpers.borderLightColor(context),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _clearFilters,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Limpar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: CustomButton(
                      text: 'Aplicar Filtros',
                      icon: Icons.check,
                      onPressed: _applyFilters,
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

  Widget _buildSectionTitle(BuildContext context, ThemeData theme, String title) {
    return Text(
      title,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: ThemeHelpers.textColor(context),
        letterSpacing: 0.5,
      ),
    );
  }
}

