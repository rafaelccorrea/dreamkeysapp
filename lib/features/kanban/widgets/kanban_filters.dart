import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/kanban_models.dart';
import '../controllers/kanban_controller.dart';

/// Widget de filtros do Kanban
class KanbanFilters extends StatefulWidget {
  const KanbanFilters({super.key});

  @override
  State<KanbanFilters> createState() => _KanbanFiltersState();
}

class _KanbanFiltersState extends State<KanbanFilters> {
  final _searchController = TextEditingController();
  KanbanPriority? _selectedPriority;
  String? _selectedAssigneeId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<KanbanController>();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          bottom: BorderSide(
            color: ThemeHelpers.borderColor(context),
          ),
        ),
      ),
      child: Column(
        children: [
          // Busca
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar tarefas...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _applyFilters(controller);
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: ThemeHelpers.cardBackgroundColor(context),
            ),
            onChanged: (value) {
              setState(() {});
              _applyFilters(controller);
            },
          ),
          const SizedBox(height: 12),
          // Filtros
          Row(
            children: [
              // Filtro de prioridade
              Expanded(
                child: DropdownButtonFormField<KanbanPriority?>(
                  value: _selectedPriority,
                  decoration: InputDecoration(
                    labelText: 'Prioridade',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: ThemeHelpers.cardBackgroundColor(context),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<KanbanPriority?>(
                      value: null,
                      child: Text('Todas'),
                    ),
                    ...KanbanPriority.values.map((priority) {
                      return DropdownMenuItem(
                        value: priority,
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: Color(int.parse(
                                  priority.color.replaceFirst('#', '0xFF'),
                                )),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(priority.label),
                          ],
                        ),
                      );
                    }),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedPriority = value;
                    });
                    _applyFilters(controller);
                  },
                ),
              ),
              const SizedBox(width: 12),
              // Botão limpar filtros
              if (_hasActiveFilters())
                IconButton(
                  icon: const Icon(Icons.clear_all),
                  onPressed: () {
                    _clearFilters(controller);
                  },
                  tooltip: 'Limpar filtros',
                ),
            ],
          ),
        ],
      ),
    );
  }

  bool _hasActiveFilters() {
    return _searchController.text.isNotEmpty ||
        _selectedPriority != null ||
        _selectedAssigneeId != null;
  }

  void _applyFilters(KanbanController controller) {
    controller.applyFilters(
      searchQuery: _searchController.text.trim().isEmpty
          ? null
          : _searchController.text.trim(),
      priority: _selectedPriority,
      assigneeId: _selectedAssigneeId,
    );
  }

  void _clearFilters(KanbanController controller) {
    setState(() {
      _searchController.clear();
      _selectedPriority = null;
      _selectedAssigneeId = null;
    });
    controller.clearFilters();
  }
}

