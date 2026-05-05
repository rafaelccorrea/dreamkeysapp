import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/kanban_models.dart';
import '../controllers/kanban_controller.dart';

/// Widget de filtros do Kanban
class KanbanFilters extends StatefulWidget {
  /// Quando [true], omite o cartão externo (uso dentro do painel agrupado na [KanbanPage]).
  final bool embedded;

  const KanbanFilters({
    super.key,
    this.embedded = false,
  });

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

  static const double _kWideBreak = 520;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<KanbanController>();
    final theme = Theme.of(context);

    InputDecoration searchDecoration({required bool inCard}) {
      return InputDecoration(
        hintText: 'Buscar leads, título ou descrição…',
        hintStyle: theme.textTheme.bodyMedium?.copyWith(
          color: ThemeHelpers.textSecondaryColor(context),
          fontWeight: FontWeight.w500,
        ),
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
      ).applyDefaults(theme.inputDecorationTheme);
    }

    InputDecoration priorityDecoration() {
      return InputDecoration(
        labelText: 'Prioridade',
        alignLabelWithHint: true,
      ).applyDefaults(theme.inputDecorationTheme);
    }

    void onSearchChanged(String _) {
      setState(() {});
      _applyFilters(controller);
    }

    Widget searchField({required bool inCard}) {
      return TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        decoration: widget.embedded
            ? searchDecoration(inCard: inCard)
            : InputDecoration(
                hintText: 'Buscar leads, título ou descrição…',
                prefixIcon: const Icon(Icons.search_rounded),
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                filled: true,
                fillColor: ThemeHelpers.cardBackgroundColor(context),
              ),
        onChanged: onSearchChanged,
      );
    }

    final priorityField = DropdownButtonFormField<KanbanPriority?>(
      value: _selectedPriority,
      isExpanded: true,
      decoration: widget.embedded
          ? priorityDecoration()
          : InputDecoration(
              labelText: 'Prioridade',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
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
    );

    final clearBtn = !_hasActiveFilters()
        ? const SizedBox.shrink()
        : IconButton(
            onPressed: () => _clearFilters(controller),
            icon: Icon(
              Icons.clear_all_rounded,
              size: 20,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
            tooltip: 'Limpar filtros',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          );

    Widget narrowStack() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          searchField(inCard: true),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: priorityField),
              if (_hasActiveFilters()) clearBtn,
            ],
          ),
        ],
      );
    }

    Widget wideRow() {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 58,
            child: searchField(inCard: true),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 42,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: priorityField),
                if (_hasActiveFilters()) clearBtn,
              ],
            ),
          ),
        ],
      );
    }

    Widget innerFields(double maxWidth) {
      if (maxWidth >= _kWideBreak) {
        return wideRow();
      }
      return narrowStack();
    }

    if (widget.embedded) {
      return LayoutBuilder(
        builder: (context, c) => innerFields(c.maxWidth),
      );
    }

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        searchField(inCard: false),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < _kWideBreak) {
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
