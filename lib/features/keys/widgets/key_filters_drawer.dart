import 'package:flutter/material.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../documents/widgets/entity_selector.dart';
import '../models/key_model.dart' as key_models;

/// Widget de filtros avançados para chaves
class KeyFiltersDrawer extends StatefulWidget {
  final key_models.KeyFilters? initialFilters;
  final Function(key_models.KeyFilters?) onFiltersChanged;

  const KeyFiltersDrawer({
    super.key,
    this.initialFilters,
    required this.onFiltersChanged,
  });

  @override
  State<KeyFiltersDrawer> createState() => _KeyFiltersDrawerState();
}

class _KeyFiltersDrawerState extends State<KeyFiltersDrawer> {
  key_models.KeyStatus? _selectedStatus;
  String? _selectedPropertyId;
  String? _selectedPropertyName;
  bool _onlyMyData = false;

  @override
  void initState() {
    super.initState();
    _loadInitialFilters();
  }

  void _loadInitialFilters() {
    if (widget.initialFilters != null) {
      setState(() {
        _selectedStatus = widget.initialFilters!.status != null
            ? key_models.KeyStatus.fromString(widget.initialFilters!.status!)
            : null;
        _selectedPropertyId = widget.initialFilters!.propertyId;
        _onlyMyData = widget.initialFilters!.onlyMyData ?? false;
      });
    }
  }

  void _applyFilters() {
    final filters = key_models.KeyFilters(
      status: _selectedStatus?.value,
      propertyId: _selectedPropertyId,
      onlyMyData: _onlyMyData ? true : null,
    );

    widget.onFiltersChanged(filters);
    Navigator.of(context).pop();
  }

  void _clearFilters() {
    setState(() {
      _selectedStatus = null;
      _selectedPropertyId = null;
      _selectedPropertyName = null;
      _onlyMyData = false;
    });
    widget.onFiltersChanged(null);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Icon(Icons.filter_list),
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
                    onPressed: () => Navigator.pop(context),
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
                      children: key_models.KeyStatus.values.map((status) {
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
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    // Propriedade
                    Text(
                      'Propriedade',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
                    // Apenas meus dados
                    Row(
                      children: [
                        Checkbox(
                          value: _onlyMyData,
                          onChanged: (value) {
                            setState(() {
                              _onlyMyData = value ?? false;
                            });
                          },
                        ),
                        Expanded(
                          child: Text(
                            'Apenas minhas chaves',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Botões
                    Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _applyFilters,
                            icon: const Icon(Icons.check),
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
                    const SizedBox(height: 20),
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

