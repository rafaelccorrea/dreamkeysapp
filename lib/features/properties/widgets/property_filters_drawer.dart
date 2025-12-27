import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../shared/services/property_service.dart';
import '../../../../shared/services/cep_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/widgets/custom_text_field.dart';

/// Widget de filtros para propriedades
class PropertyFiltersDrawer extends StatefulWidget {
  final PropertyFilters? initialFilters;
  final Function(PropertyFilters?) onFiltersChanged;

  const PropertyFiltersDrawer({
    super.key,
    this.initialFilters,
    required this.onFiltersChanged,
  });

  @override
  State<PropertyFiltersDrawer> createState() => _PropertyFiltersDrawerState();
}

class _PropertyFiltersDrawerState extends State<PropertyFiltersDrawer> {
  // Controllers
  final _minPriceController = TextEditingController();
  final _maxPriceController = TextEditingController();
  final _minAreaController = TextEditingController();
  final _maxAreaController = TextEditingController();
  final _zipCodeController = TextEditingController();
  final _cityController = TextEditingController();
  final _neighborhoodController = TextEditingController();
  final _stateController = TextEditingController();

  // Seleções
  PropertyType? _selectedType;
  PropertyStatus? _selectedStatus;

  // Serviços
  final CepService _cepService = CepService.instance;
  bool _isSearchingCep = false;

  @override
  void initState() {
    super.initState();
    _loadInitialFilters();
  }

  void _loadInitialFilters() {
    final filters = widget.initialFilters;
    if (filters == null) return;

    _minPriceController.text = filters.minPrice?.toString() ?? '';
    _maxPriceController.text = filters.maxPrice?.toString() ?? '';
    _minAreaController.text = filters.minArea?.toString() ?? '';
    _maxAreaController.text = filters.maxArea?.toString() ?? '';
    _zipCodeController.text = '';
    _cityController.text = filters.city ?? '';
    _neighborhoodController.text = filters.neighborhood ?? '';
    _stateController.text = '';
    _selectedType = filters.type;
    _selectedStatus = filters.status;
  }

  @override
  void dispose() {
    _minPriceController.dispose();
    _maxPriceController.dispose();
    _minAreaController.dispose();
    _maxAreaController.dispose();
    _zipCodeController.dispose();
    _cityController.dispose();
    _neighborhoodController.dispose();
    _stateController.dispose();
    super.dispose();
  }

  Future<void> _searchCep() async {
    final cep = _zipCodeController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (cep.length != 8) {
      return;
    }

    setState(() {
      _isSearchingCep = true;
    });

    try {
      final address = await _cepService.searchCep(cep);
      if (address != null && mounted) {
        setState(() {
          _cityController.text = address.city ?? '';
          _neighborhoodController.text = address.neighborhood ?? '';
          _stateController.text = address.state ?? '';
        });
      }
    } catch (e) {
      debugPrint('Erro ao buscar CEP: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSearchingCep = false;
        });
      }
    }
  }

  void _applyFilters() {
    final filters = PropertyFilters(
      type: _selectedType,
      status: _selectedStatus,
      minPrice: _minPriceController.text.trim().isEmpty
          ? null
          : double.tryParse(_minPriceController.text),
      maxPrice: _maxPriceController.text.trim().isEmpty
          ? null
          : double.tryParse(_maxPriceController.text),
      minArea: _minAreaController.text.trim().isEmpty
          ? null
          : double.tryParse(_minAreaController.text),
      maxArea: _maxAreaController.text.trim().isEmpty
          ? null
          : double.tryParse(_maxAreaController.text),
      city: _cityController.text.trim().isEmpty
          ? null
          : _cityController.text.trim(),
      neighborhood: _neighborhoodController.text.trim().isEmpty
          ? null
          : _neighborhoodController.text.trim(),
    );

    widget.onFiltersChanged(filters);
    Navigator.of(context).pop();
  }

  void _clearFilters() {
    setState(() {
      _minPriceController.clear();
      _maxPriceController.clear();
      _zipCodeController.clear();
      _minAreaController.clear();
      _maxAreaController.clear();
      _cityController.clear();
      _neighborhoodController.clear();
      _stateController.clear();
      _selectedType = null;
      _selectedStatus = null;
    });
    widget.onFiltersChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.filter_list, color: AppColors.primary.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Filtros',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Conteúdo
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tipo
                    Text(
                      'Tipo de Imóvel',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Todos'),
                          selected: _selectedType == null,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _selectedType = null;
                              });
                            }
                          },
                        ),
                        ...PropertyType.values.map((type) {
                          final isSelected = _selectedType == type;
                          return ChoiceChip(
                            label: Text(type.label),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                _selectedType = selected ? type : null;
                              });
                            },
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Status
                    Text(
                      'Status',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Todos'),
                          selected: _selectedStatus == null,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _selectedStatus = null;
                              });
                            }
                          },
                        ),
                        ...PropertyStatus.values.map((status) {
                          final isSelected = _selectedStatus == status;
                          return ChoiceChip(
                            label: Text(status.label),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                _selectedStatus = selected ? status : null;
                              });
                            },
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Preço
                    Text(
                      'Preço',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: CustomTextField(
                            controller: _minPriceController,
                            label: 'Mínimo',
                            hint: 'R\$ 0,00',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: CustomTextField(
                            controller: _maxPriceController,
                            label: 'Máximo',
                            hint: 'R\$ 0,00',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Área
                    Text(
                      'Área (m²)',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: CustomTextField(
                            controller: _minAreaController,
                            label: 'Mínima',
                            hint: '0',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: CustomTextField(
                            controller: _maxAreaController,
                            label: 'Máxima',
                            hint: '0',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Localização
                    Text(
                      'Localização',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CEP',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _zipCodeController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(8),
                            TextInputFormatter.withFunction((
                              oldValue,
                              newValue,
                            ) {
                              final text = newValue.text;
                              if (text.length <= 5) {
                                return newValue;
                              }
                              return TextEditingValue(
                                text:
                                    '${text.substring(0, 5)}-${text.substring(5)}',
                                selection: TextSelection.collapsed(
                                  offset: newValue.selection.end + 1,
                                ),
                              );
                            }),
                          ],
                          onChanged: (value) {
                            final cep = value.replaceAll(RegExp(r'[^0-9]'), '');
                            if (cep.length == 8) {
                              _searchCep();
                            }
                          },
                          decoration: InputDecoration(
                            hintText: '00000-000',
                            border: const OutlineInputBorder(),
                            suffixIcon: _isSearchingCep
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.search),
                                    onPressed: _searchCep,
                                    tooltip: 'Buscar CEP',
                                  ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: CustomTextField(
                            controller: _cityController,
                            label: 'Cidade',
                            hint: 'Nome da cidade',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Estado',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _stateController,
                                decoration: const InputDecoration(
                                  hintText: 'UF',
                                  border: OutlineInputBorder(),
                                ),
                                maxLength: 2,
                                textCapitalization:
                                    TextCapitalization.characters,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      controller: _neighborhoodController,
                      label: 'Bairro',
                      hint: 'Nome do bairro',
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Botões de ação
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: ThemeHelpers.borderColor(context)),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _applyFilters,
                      icon: const Icon(Icons.filter_alt),
                      label: const Text('Aplicar Filtros'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _clearFilters,
                      icon: const Icon(Icons.clear),
                      label: const Text('Limpar Filtros'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
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
}
