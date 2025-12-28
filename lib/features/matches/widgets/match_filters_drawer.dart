import 'package:flutter/material.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/match_model.dart';

/// Drawer de filtros para matches
class MatchFiltersDrawer extends StatefulWidget {
  final MatchStatus? statusFilter;
  final Function(MatchStatus?) onFiltersChanged;

  const MatchFiltersDrawer({
    super.key,
    this.statusFilter,
    required this.onFiltersChanged,
  });

  @override
  State<MatchFiltersDrawer> createState() => _MatchFiltersDrawerState();
}

class _MatchFiltersDrawerState extends State<MatchFiltersDrawer> {
  MatchStatus? _selectedStatus;

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.statusFilter;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
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
              color: ThemeHelpers.borderLightColor(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Filtros',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Filtro por status
                Text(
                  'Status',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                ...MatchStatus.values.map((status) {
                  return RadioListTile<MatchStatus?>(
                    title: Text(status.label),
                    value: status,
                    groupValue: _selectedStatus,
                    onChanged: (value) {
                      setState(() {
                        _selectedStatus = value;
                      });
                    },
                    contentPadding: EdgeInsets.zero,
                  );
                }),
                RadioListTile<MatchStatus?>(
                  title: const Text('Todos'),
                  value: null,
                  groupValue: _selectedStatus,
                  onChanged: (value) {
                    setState(() {
                      _selectedStatus = value;
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                ),

                const SizedBox(height: 24),

                // Botões
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _selectedStatus = null;
                          });
                        },
                        child: const Text('Limpar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () {
                          widget.onFiltersChanged(_selectedStatus);
                          Navigator.pop(context);
                        },
                        child: const Text('Aplicar'),
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
    );
  }
}

