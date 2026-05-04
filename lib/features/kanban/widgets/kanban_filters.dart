import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/kanban_models.dart';
import '../controllers/kanban_controller.dart';

/// Widget de filtros do Kanban
class KanbanFilters extends StatefulWidget {
  /// Quando [true], omiti o cartão externo (uso dentro do painel agrupado na [KanbanPage]).
  final bool embedded;

  const KanbanFilters({super.key, this.embedded = false});

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

    InputDecoration fluxSearchDecoration() {
      return InputDecoration(
        hintText: 'Buscar leads, título ou descrição...',
        prefixIcon: Icon(
          Icons.search_rounded,
          color: ThemeHelpers.textSecondaryColor(context),
        ),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded),
                onPressed: () {
                  _searchController.clear();
                  _applyFilters(controller);
                  setState(() {});
                },
              )
            : null,
      ).applyDefaults(Theme.of(context).inputDecorationTheme);
    }

    InputDecoration fluxPriorityDecoration() {
      return const InputDecoration(
        labelText: 'Prioridade',
      ).applyDefaults(Theme.of(context).inputDecorationTheme);
    }

    final body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Busca
          TextField(
            controller: _searchController,
            decoration: widget.embedded
                ? fluxSearchDecoration()
                : InputDecoration(
                    hintText: 'Buscar leads, título ou descrição...',
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
          SizedBox(height: widget.embedded ? 14 : 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrowRow = constraints.maxWidth < 520;
              final priorityDeco = widget.embedded
                  ? fluxPriorityDecoration()
                  : InputDecoration(
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
                    );

              final priorityField =
                  DropdownButtonFormField<KanbanPriority?>(
                initialValue: _selectedPriority,
                isExpanded: true,
                decoration: priorityDeco,
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
              );

              final clearBtn = !_hasActiveFilters()
                  ? const SizedBox.shrink()
                  : IconButton(
                      icon: const Icon(Icons.clear_all_rounded),
                      onPressed: () => _clearFilters(controller),
                      tooltip: 'Limpar filtros',
                    );

              if (narrowRow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    priorityField,
                    if (_hasActiveFilters())
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: clearBtn,
                        ),
                      ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: priorityField),
                  clearBtn,
                ],
              );
            },
          ),
        ],
    );

    if (widget.embedded) {
      return body;
    }

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
      child: body,
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

