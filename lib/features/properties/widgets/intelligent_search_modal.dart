import 'package:flutter/material.dart';
import '../../../../shared/services/property_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/widgets/custom_text_field.dart';
import '../../../../shared/widgets/custom_button.dart';

/// Modal de busca inteligente de propriedades
class IntelligentSearchModal extends StatefulWidget {
  final Function(IntelligentSearchResponse)? onResults;

  const IntelligentSearchModal({
    super.key,
    this.onResults,
  });

  @override
  State<IntelligentSearchModal> createState() => _IntelligentSearchModalState();
}

class _IntelligentSearchModalState extends State<IntelligentSearchModal> {
  final PropertyService _propertyService = PropertyService.instance;
  final _formKey = GlobalKey<FormState>();
  
  // Filtros
  PropertyType? _selectedType;
  String? _selectedOperation; // 'rent' | 'sale'
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _neighborhoodController = TextEditingController();
  final _minValueController = TextEditingController();
  final _maxValueController = TextEditingController();
  final _minBedroomsController = TextEditingController();
  final _minBathroomsController = TextEditingController();
  final _minParkingSpacesController = TextEditingController();
  final _minAreaController = TextEditingController();
  final _maxAreaController = TextEditingController();
  
  bool _onlyMyProperties = false;
  bool _searchInGroupCompanies = false;
  bool _includeOtherBrokers = false;
  
  bool _isSearching = false;
  IntelligentSearchResponse? _results;

  @override
  void dispose() {
    _cityController.dispose();
    _stateController.dispose();
    _neighborhoodController.dispose();
    _minValueController.dispose();
    _maxValueController.dispose();
    _minBedroomsController.dispose();
    _minBathroomsController.dispose();
    _minParkingSpacesController.dispose();
    _minAreaController.dispose();
    _maxAreaController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSearching = true;
      _results = null;
    });

    try {
      final response = await _propertyService.intelligentSearch(
        type: _selectedType,
        operation: _selectedOperation,
        city: _cityController.text.trim().isEmpty ? null : _cityController.text.trim(),
        state: _stateController.text.trim().isEmpty ? null : _stateController.text.trim(),
        neighborhood: _neighborhoodController.text.trim().isEmpty
            ? null
            : _neighborhoodController.text.trim(),
        minValue: _minValueController.text.trim().isEmpty
            ? null
            : double.tryParse(_minValueController.text),
        maxValue: _maxValueController.text.trim().isEmpty
            ? null
            : double.tryParse(_maxValueController.text),
        minBedrooms: _minBedroomsController.text.trim().isEmpty
            ? null
            : int.tryParse(_minBedroomsController.text),
        minBathrooms: _minBathroomsController.text.trim().isEmpty
            ? null
            : int.tryParse(_minBathroomsController.text),
        minParkingSpaces: _minParkingSpacesController.text.trim().isEmpty
            ? null
            : int.tryParse(_minParkingSpacesController.text),
        minArea: _minAreaController.text.trim().isEmpty
            ? null
            : double.tryParse(_minAreaController.text),
        maxArea: _maxAreaController.text.trim().isEmpty
            ? null
            : double.tryParse(_maxAreaController.text),
        onlyMyProperties: _onlyMyProperties,
        searchInGroupCompanies: _searchInGroupCompanies,
        includeOtherBrokers: _includeOtherBrokers,
      );

      if (mounted) {
        if (response.success && response.data != null) {
          setState(() {
            _results = response.data;
          });
          if (widget.onResults != null) {
            widget.onResults!(response.data!);
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro na busca'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Erro na busca inteligente: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao conectar com o servidor')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
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
                  Icon(
                    Icons.auto_awesome,
                    color: AppColors.primary.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Busca Inteligente',
                      style: theme.textTheme.titleLarge?.copyWith(
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
            ),

            // Conteúdo
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Form(
                  key: _formKey,
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
                      const SizedBox(height: 8),
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
                            return ChoiceChip(
                              label: Text(type.label),
                              selected: _selectedType == type,
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

                      // Operação
                      Text(
                        'Operação',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Todas'),
                            selected: _selectedOperation == null,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() {
                                  _selectedOperation = null;
                                });
                              }
                            },
                          ),
                          ChoiceChip(
                            label: const Text('Venda'),
                            selected: _selectedOperation == 'sale',
                            onSelected: (selected) {
                              setState(() {
                                _selectedOperation = selected ? 'sale' : null;
                              });
                            },
                          ),
                          ChoiceChip(
                            label: const Text('Aluguel'),
                            selected: _selectedOperation == 'rent',
                            onSelected: (selected) {
                              setState(() {
                                _selectedOperation = selected ? 'rent' : null;
                              });
                            },
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
                      Row(
                        children: [
                          Expanded(
                            child: CustomTextField(
                              controller: _cityController,
                              label: 'Cidade',
                              hint: 'Nome da cidade',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _stateController,
                              decoration: const InputDecoration(
                                labelText: 'Estado',
                                hintText: 'UF',
                                border: OutlineInputBorder(),
                              ),
                              maxLength: 2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      CustomTextField(
                        controller: _neighborhoodController,
                        label: 'Bairro',
                        hint: 'Nome do bairro',
                      ),
                      const SizedBox(height: 24),

                      // Valores
                      Text(
                        'Valores',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: CustomTextField(
                              controller: _minValueController,
                              label: 'Valor Mínimo',
                              hint: 'R\$ 0,00',
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: CustomTextField(
                              controller: _maxValueController,
                              label: 'Valor Máximo',
                              hint: 'R\$ 0,00',
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Características
                      Text(
                        'Características',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: CustomTextField(
                              controller: _minBedroomsController,
                              label: 'Quartos (mín)',
                              hint: '0',
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: CustomTextField(
                              controller: _minBathroomsController,
                              label: 'Banheiros (mín)',
                              hint: '0',
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: CustomTextField(
                              controller: _minParkingSpacesController,
                              label: 'Vagas (mín)',
                              hint: '0',
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: CustomTextField(
                              controller: _minAreaController,
                              label: 'Área Mínima (m²)',
                              hint: '0',
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: CustomTextField(
                              controller: _maxAreaController,
                              label: 'Área Máxima (m²)',
                              hint: '0',
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Opções avançadas
                      Text(
                        'Opções Avançadas',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        title: const Text('Apenas minhas propriedades'),
                        value: _onlyMyProperties,
                        onChanged: (value) {
                          setState(() {
                            _onlyMyProperties = value;
                          });
                        },
                      ),
                      SwitchListTile(
                        title: const Text('Buscar em empresas do grupo'),
                        value: _searchInGroupCompanies,
                        onChanged: (value) {
                          setState(() {
                            _searchInGroupCompanies = value;
                          });
                        },
                      ),
                      SwitchListTile(
                        title: const Text('Incluir outros corretores'),
                        value: _includeOtherBrokers,
                        onChanged: (value) {
                          setState(() {
                            _includeOtherBrokers = value;
                          });
                        },
                      ),
                      const SizedBox(height: 24),

                      // Botão de busca
                      SizedBox(
                        width: double.infinity,
                        child: CustomButton(
                          text: _isSearching ? 'Buscando...' : 'Buscar',
                          onPressed: _isSearching ? null : _performSearch,
                          icon: Icons.search,
                          isLoading: _isSearching,
                        ),
                      ),

                      // Resultados
                      if (_results != null) ...[
                        const SizedBox(height: 24),
                        Divider(color: ThemeHelpers.borderColor(context)),
                        const SizedBox(height: 16),
                        Text(
                          'Resultados (${_results!.results.length} encontrados)',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ..._results!.results.take(5).map((result) {
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              title: Text(result.property.title),
                              subtitle: Text(
                                'Score: ${result.matchScore.toStringAsFixed(1)}% - ${result.matchReasons.take(2).join(', ')}',
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.arrow_forward),
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  Navigator.of(context).pushNamed(
                                    '/properties/${result.property.id}',
                                  );
                                },
                              ),
                            ),
                          );
                        }),
                        if (_results!.results.length > 5)
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              // TODO: Navegar para página de resultados completos
                            },
                            child: Text('Ver todos os ${_results!.results.length} resultados'),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

