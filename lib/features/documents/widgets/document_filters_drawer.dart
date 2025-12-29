import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/custom_button.dart';
import '../models/document_model.dart';
import '../services/document_service.dart';

/// Widget de filtros avançados para documentos
class DocumentFiltersDrawer extends StatefulWidget {
  final DocumentFilters? initialFilters;
  final Function(DocumentFilters?) onFiltersChanged;

  const DocumentFiltersDrawer({
    super.key,
    this.initialFilters,
    required this.onFiltersChanged,
  });

  @override
  State<DocumentFiltersDrawer> createState() => _DocumentFiltersDrawerState();
}

class _DocumentFiltersDrawerState extends State<DocumentFiltersDrawer> {
  // Seleções
  DocumentType? _selectedType;
  DocumentStatus? _selectedStatus;
  String? _sortBy;
  String? _sortOrder;

  @override
  void initState() {
    super.initState();
    _loadInitialFilters();
  }

  void _loadInitialFilters() {
    if (widget.initialFilters != null) {
      setState(() {
        _selectedType = widget.initialFilters!.type;
        _selectedStatus = widget.initialFilters!.status;
        _sortBy = widget.initialFilters!.sortBy;
        _sortOrder = widget.initialFilters!.sortOrder;
      });
    }
  }

  void _applyFilters() {
    final filters = DocumentFilters(
      type: _selectedType,
      status: _selectedStatus,
      sortBy: _sortBy,
      sortOrder: _sortOrder,
    );

    widget.onFiltersChanged(filters);
    Navigator.of(context).pop();
  }

  void _clearFilters() {
    setState(() {
      _selectedType = null;
      _selectedStatus = null;
      _sortBy = null;
      _sortOrder = null;
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
                    DropdownButtonFormField<DocumentType>(
                      value: _selectedType,
                      decoration: InputDecoration(
                        labelText: 'Tipo de Documento',
                        prefixIcon: const Icon(Icons.description_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Todos'),
                        ),
                        ...DocumentType.values.map((type) {
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
                    DropdownButtonFormField<DocumentStatus>(
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
                        ...DocumentStatus.values.map((status) {
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
                    
                    // Ordenação
                    _buildSectionTitle(context, theme, 'Ordenação'),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _sortBy,
                      decoration: InputDecoration(
                        labelText: 'Ordenar por',
                        prefixIcon: const Icon(Icons.sort),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('Padrão')),
                        DropdownMenuItem(value: 'createdAt', child: Text('Data de Criação')),
                        DropdownMenuItem(value: 'updatedAt', child: Text('Data de Atualização')),
                        DropdownMenuItem(value: 'expiryDate', child: Text('Data de Vencimento')),
                        DropdownMenuItem(value: 'originalName', child: Text('Nome')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _sortBy = value;
                        });
                      },
                    ),
                    if (_sortBy != null) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _sortOrder ?? 'asc',
                        decoration: InputDecoration(
                          labelText: 'Ordem',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'asc', child: Text('Crescente')),
                          DropdownMenuItem(value: 'desc', child: Text('Decrescente')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _sortOrder = value;
                          });
                        },
                      ),
                    ],
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

