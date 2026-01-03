import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/services/api_service.dart';
import '../../documents/widgets/entity_selector.dart';
import '../models/inspection_model.dart';

/// Widget de filtros avançados para vistorias
class InspectionFiltersDrawer extends StatefulWidget {
  final InspectionFilters? initialFilters;
  final Function(InspectionFilters?) onFiltersChanged;

  const InspectionFiltersDrawer({
    super.key,
    this.initialFilters,
    required this.onFiltersChanged,
  });

  @override
  State<InspectionFiltersDrawer> createState() => _InspectionFiltersDrawerState();
}

class _InspectionFiltersDrawerState extends State<InspectionFiltersDrawer> {
  // Seleções
  InspectionType? _selectedType;
  InspectionStatus? _selectedStatus;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _selectedPropertyId;
  String? _selectedPropertyName;
  String? _selectedInspectorId;
  String? _selectedInspectorName;
  bool _onlyMyData = false;

  // Usuários para seleção de vistoriador
  List<Map<String, dynamic>> _users = [];
  bool _isLoadingUsers = false;

  @override
  void initState() {
    super.initState();
    _loadInitialFilters();
    _loadUsers();
  }

  void _loadInitialFilters() {
    if (widget.initialFilters != null) {
      setState(() {
        _selectedType = widget.initialFilters!.type;
        _selectedStatus = widget.initialFilters!.status;
        _startDate = widget.initialFilters!.startDate;
        _endDate = widget.initialFilters!.endDate;
        _selectedPropertyId = widget.initialFilters!.propertyId;
        _selectedInspectorId = widget.initialFilters!.inspectorId;
        _onlyMyData = widget.initialFilters!.onlyMyData ?? false;
      });
    }
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoadingUsers = true;
    });

    try {
      final response = await ApiService.instance.get<dynamic>(
        '/chat/company/users',
      );

      if (mounted && response.success && response.data != null) {
        List<Map<String, dynamic>> users = [];
        if (response.data is List) {
          users = (response.data as List)
              .map((e) => e as Map<String, dynamic>)
              .toList();
        }
        setState(() {
          _users = users;
          // Se já temos um inspectorId selecionado, buscar o nome
          if (_selectedInspectorId != null) {
            final user = users.firstWhere(
              (u) => u['id']?.toString() == _selectedInspectorId,
              orElse: () => {},
            );
            if (user.isNotEmpty) {
              _selectedInspectorName = user['name']?.toString();
            }
          }
          _isLoadingUsers = false;
        });
      } else {
        setState(() {
          _isLoadingUsers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingUsers = false;
        });
      }
    }
  }

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('pt', 'BR'),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
      });
    }
  }

  Future<void> _selectEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate ?? DateTime.now(),
      firstDate: _startDate ?? DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('pt', 'BR'),
    );
    if (picked != null) {
      setState(() {
        _endDate = picked;
      });
    }
  }

  Future<void> _selectInspector() async {
    if (_isLoadingUsers) return;

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ThemeHelpers.textSecondaryColor(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Icon(Icons.person),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Selecionar Vistoriador',
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
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _users.length,
                itemBuilder: (context, index) {
                  final user = _users[index];
                  final userName = user['name']?.toString() ?? 'Sem nome';
                  final userId = user['id']?.toString() ?? '';
                  final isSelected = userId == _selectedInspectorId;

                  return ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                      ),
                    ),
                    title: Text(userName),
                    subtitle: user['email'] != null
                        ? Text(user['email'].toString())
                        : null,
                    selected: isSelected,
                    selectedTileColor:
                        AppColors.primary.primary.withValues(alpha: 0.1),
                    onTap: () {
                      Navigator.pop(context, {
                        'id': userId,
                        'name': userName,
                      });
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
      setState(() {
        _selectedInspectorId = selected['id'];
        _selectedInspectorName = selected['name'];
      });
    }
  }

  void _applyFilters() {
    final filters = InspectionFilters(
      type: _selectedType,
      status: _selectedStatus,
      propertyId: _selectedPropertyId,
      inspectorId: _selectedInspectorId,
      startDate: _startDate,
      endDate: _endDate,
      onlyMyData: _onlyMyData ? true : null,
    );

    widget.onFiltersChanged(filters);
    Navigator.of(context).pop();
  }

  void _clearFilters() {
    setState(() {
      _selectedType = null;
      _selectedStatus = null;
      _startDate = null;
      _endDate = null;
      _selectedPropertyId = null;
      _selectedPropertyName = null;
      _selectedInspectorId = null;
      _selectedInspectorName = null;
      _onlyMyData = false;
    });
    widget.onFiltersChanged(null);
    Navigator.of(context).pop();
  }

  Widget _buildSectionTitle(BuildContext context, ThemeData theme, String title) {
    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: ThemeHelpers.textColor(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('dd/MM/yyyy');

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ThemeHelpers.textSecondaryColor(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
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
                      'Filtros',
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
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tipo
                    _buildSectionTitle(context, theme, 'Tipo'),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<InspectionType>(
                      value: _selectedType,
                      decoration: InputDecoration(
                        labelText: 'Tipo de Vistoria',
                        prefixIcon: const Icon(Icons.checklist_rtl_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Todos'),
                        ),
                        ...InspectionType.values.map((type) {
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
                    const SizedBox(height: 24),

                    // Status
                    _buildSectionTitle(context, theme, 'Status'),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<InspectionStatus>(
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
                        ...InspectionStatus.values.map((status) {
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

                    // Propriedade
                    _buildSectionTitle(context, theme, 'Propriedade'),
                    const SizedBox(height: 12),
                    EntitySelector(
                      type: 'property',
                      selectedId: _selectedPropertyId,
                      selectedName: _selectedPropertyName,
                      onSelected: (id, name) {
                        setState(() {
                          _selectedPropertyId = id;
                          _selectedPropertyName = name;
                        });
                      },
                    ),
                    const SizedBox(height: 24),

                    // Vistoriador
                    _buildSectionTitle(context, theme, 'Vistoriador'),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: _isLoadingUsers ? null : _selectInspector,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Vistoriador',
                          hintText: 'Selecione um vistoriador',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.person),
                          suffixIcon: _isLoadingUsers
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: Padding(
                                    padding: EdgeInsets.all(12),
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              : const Icon(Icons.arrow_drop_down),
                        ),
                        child: Text(
                          _selectedInspectorName ?? 'Selecione um vistoriador',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: _selectedInspectorName != null
                                ? Theme.of(context).colorScheme.onSurface
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Período
                    _buildSectionTitle(context, theme, 'Período'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _selectStartDate,
                            icon: const Icon(Icons.calendar_today, size: 18),
                            label: Text(
                              _startDate != null
                                  ? dateFormat.format(_startDate!)
                                  : 'Data inicial',
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _selectEndDate,
                            icon: const Icon(Icons.calendar_today, size: 18),
                            label: Text(
                              _endDate != null
                                  ? dateFormat.format(_endDate!)
                                  : 'Data final',
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Apenas minhas vistorias
                    CheckboxListTile(
                      title: const Text('Apenas minhas vistorias'),
                      value: _onlyMyData,
                      onChanged: (value) {
                        setState(() {
                          _onlyMyData = value ?? false;
                        });
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    const SizedBox(height: 32),

                    // Botões
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _clearFilters,
                            icon: const Icon(Icons.clear),
                            label: const Text('Limpar'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: CustomButton(
                            onPressed: _applyFilters,
                            text: 'Aplicar Filtros',
                            icon: Icons.check,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


