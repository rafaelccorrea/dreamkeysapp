import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';

/// Modelo de filtros do dashboard
class DashboardFilters {
  final String? dateRange; // 'today' | '7d' | '30d' | '90d' | '1y' | 'custom'
  final String? compareWith; // 'previous_period' | 'previous_year' | 'none'
  final String? metric; // 'all' | 'properties' | 'clients' | 'inspections' | 'appointments' | 'commissions' | 'tasks' | 'matches'
  final String? startDate; // YYYY-MM-DD
  final String? endDate; // YYYY-MM-DD
  final int activitiesLimit;
  final int appointmentsLimit;

  DashboardFilters({
    this.dateRange,
    this.compareWith,
    this.metric,
    this.startDate,
    this.endDate,
    this.activitiesLimit = 10,
    this.appointmentsLimit = 5,
  });

  DashboardFilters copyWith({
    String? dateRange,
    String? compareWith,
    String? metric,
    String? startDate,
    String? endDate,
    int? activitiesLimit,
    int? appointmentsLimit,
  }) {
    return DashboardFilters(
      dateRange: dateRange ?? this.dateRange,
      compareWith: compareWith ?? this.compareWith,
      metric: metric ?? this.metric,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      activitiesLimit: activitiesLimit ?? this.activitiesLimit,
      appointmentsLimit: appointmentsLimit ?? this.appointmentsLimit,
    );
  }

  /// Retorna os filtros padrão (primeiro dia do mês até hoje)
  static DashboardFilters defaultFilters() {
    final now = DateTime.now();
    final firstDayOfMonth = DateTime(now.year, now.month, 1);
    
    return DashboardFilters(
      dateRange: 'custom',
      startDate: '${firstDayOfMonth.year}-${firstDayOfMonth.month.toString().padLeft(2, '0')}-${firstDayOfMonth.day.toString().padLeft(2, '0')}',
      endDate: '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      compareWith: 'none',
      metric: 'all',
      activitiesLimit: 10,
      appointmentsLimit: 5,
    );
  }
}

/// Widget de filtros do dashboard
class DashboardFiltersDrawer extends StatefulWidget {
  final DashboardFilters initialFilters;
  final Function(DashboardFilters) onFiltersChanged;

  const DashboardFiltersDrawer({
    super.key,
    required this.initialFilters,
    required this.onFiltersChanged,
  });

  @override
  State<DashboardFiltersDrawer> createState() => _DashboardFiltersDrawerState();
}

class _DashboardFiltersDrawerState extends State<DashboardFiltersDrawer> {
  late DashboardFilters _filters;
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;

  @override
  void initState() {
    super.initState();
    _filters = widget.initialFilters;
    
    // Parse das datas se existirem
    if (_filters.startDate != null) {
      try {
        _selectedStartDate = DateTime.parse(_filters.startDate!);
      } catch (e) {
        debugPrint('Erro ao parsear startDate: $e');
      }
    }
    if (_filters.endDate != null) {
      try {
        _selectedEndDate = DateTime.parse(_filters.endDate!);
      } catch (e) {
        debugPrint('Erro ao parsear endDate: $e');
      }
    }
  }

  Future<void> _selectStartDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedStartDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('pt', 'BR'),
    );
    if (picked != null) {
      setState(() {
        _selectedStartDate = picked;
        _filters = _filters.copyWith(
          startDate: '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}',
        );
      });
    }
  }

  Future<void> _selectEndDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedEndDate ?? DateTime.now(),
      firstDate: _selectedStartDate ?? DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('pt', 'BR'),
    );
    if (picked != null) {
      setState(() {
        _selectedEndDate = picked;
        _filters = _filters.copyWith(
          endDate: '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}',
        );
      });
    }
  }

  void _applyFilters() {
    widget.onFiltersChanged(_filters);
    Navigator.pop(context);
  }

  void _resetFilters() {
    setState(() {
      _filters = DashboardFilters.defaultFilters();
      _selectedStartDate = null;
      _selectedEndDate = null;
      
      // Parse das datas padrão
      if (_filters.startDate != null) {
        try {
          _selectedStartDate = DateTime.parse(_filters.startDate!);
        } catch (e) {
          debugPrint('Erro ao parsear startDate padrão: $e');
        }
      }
      if (_filters.endDate != null) {
        try {
          _selectedEndDate = DateTime.parse(_filters.endDate!);
        } catch (e) {
          debugPrint('Erro ao parsear endDate padrão: $e');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Icons.filter_list,
                    color: AppColors.primary.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Filtros do Dashboard',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: ThemeHelpers.textColor(context),
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
              const SizedBox(height: 24),

              // Período de Análise
              Text(
                'Período de Análise',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _filters.dateRange ?? 'custom',
                decoration: InputDecoration(
                  labelText: 'Período',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: isDark
                      ? AppColors.background.backgroundSecondaryDarkMode
                      : AppColors.background.backgroundSecondary,
                ),
                items: const [
                  DropdownMenuItem(value: 'today', child: Text('Hoje')),
                  DropdownMenuItem(value: '7d', child: Text('Últimos 7 dias')),
                  DropdownMenuItem(value: '30d', child: Text('Últimos 30 dias')),
                  DropdownMenuItem(value: '90d', child: Text('Últimos 90 dias')),
                  DropdownMenuItem(value: '1y', child: Text('Último ano')),
                  DropdownMenuItem(value: 'custom', child: Text('Período Personalizado')),
                ],
                onChanged: (value) {
                  setState(() {
                    _filters = _filters.copyWith(dateRange: value);
                    if (value != 'custom') {
                      _filters = _filters.copyWith(
                        startDate: null,
                        endDate: null,
                      );
                      _selectedStartDate = null;
                      _selectedEndDate = null;
                    }
                  });
                },
              ),

              // Datas customizadas
              if (_filters.dateRange == 'custom') ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _selectStartDate(context),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: ThemeHelpers.borderColor(context),
                            ),
                            borderRadius: BorderRadius.circular(12),
                            color: isDark
                                ? AppColors.background.backgroundSecondaryDarkMode
                                : AppColors.background.backgroundSecondary,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today_outlined,
                                size: 20,
                                color: ThemeHelpers.textSecondaryColor(context),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Data Inicial',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: ThemeHelpers.textSecondaryColor(context),
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _selectedStartDate != null
                                          ? DateFormat('dd/MM/yyyy', 'pt_BR')
                                              .format(_selectedStartDate!)
                                          : 'Selecione a data',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: ThemeHelpers.textColor(context),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () => _selectEndDate(context),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: ThemeHelpers.borderColor(context),
                            ),
                            borderRadius: BorderRadius.circular(12),
                            color: isDark
                                ? AppColors.background.backgroundSecondaryDarkMode
                                : AppColors.background.backgroundSecondary,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today_outlined,
                                size: 20,
                                color: ThemeHelpers.textSecondaryColor(context),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Data Final',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: ThemeHelpers.textSecondaryColor(context),
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _selectedEndDate != null
                                          ? DateFormat('dd/MM/yyyy', 'pt_BR')
                                              .format(_selectedEndDate!)
                                          : 'Selecione a data',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: ThemeHelpers.textColor(context),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 24),

              // Comparação
              Text(
                'Comparação',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _filters.compareWith ?? 'none',
                decoration: InputDecoration(
                  labelText: 'Comparar com',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: isDark
                      ? AppColors.background.backgroundSecondaryDarkMode
                      : AppColors.background.backgroundSecondary,
                ),
                items: const [
                  DropdownMenuItem(value: 'none', child: Text('Sem comparação')),
                  DropdownMenuItem(value: 'previous_period', child: Text('Período anterior')),
                  DropdownMenuItem(value: 'previous_year', child: Text('Mesmo período ano passado')),
                ],
                onChanged: (value) {
                  setState(() {
                    _filters = _filters.copyWith(compareWith: value);
                  });
                },
              ),

              const SizedBox(height: 24),

              // Tipo de Métrica
              Text(
                'Tipo de Métrica',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _filters.metric ?? 'all',
                decoration: InputDecoration(
                  labelText: 'Métrica',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: isDark
                      ? AppColors.background.backgroundSecondaryDarkMode
                      : AppColors.background.backgroundSecondary,
                ),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('Todas as métricas')),
                  DropdownMenuItem(value: 'properties', child: Text('Propriedades')),
                  DropdownMenuItem(value: 'clients', child: Text('Clientes')),
                  DropdownMenuItem(value: 'inspections', child: Text('Vistorias')),
                  DropdownMenuItem(value: 'appointments', child: Text('Agendamentos')),
                  DropdownMenuItem(value: 'commissions', child: Text('Comissões')),
                  DropdownMenuItem(value: 'tasks', child: Text('Tarefas')),
                  DropdownMenuItem(value: 'matches', child: Text('Matches')),
                ],
                onChanged: (value) {
                  setState(() {
                    _filters = _filters.copyWith(metric: value);
                  });
                },
              ),

              const SizedBox(height: 24),

              // Limites
              Text(
                'Limites de Resultados',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: _filters.activitiesLimit.toString(),
                      decoration: InputDecoration(
                        labelText: 'Atividades Recentes',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: isDark
                            ? AppColors.background.backgroundSecondaryDarkMode
                            : AppColors.background.backgroundSecondary,
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        final limit = int.tryParse(value);
                        if (limit != null && limit >= 1 && limit <= 100) {
                          setState(() {
                            _filters = _filters.copyWith(activitiesLimit: limit);
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      initialValue: _filters.appointmentsLimit.toString(),
                      decoration: InputDecoration(
                        labelText: 'Próximos Agendamentos',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: isDark
                            ? AppColors.background.backgroundSecondaryDarkMode
                            : AppColors.background.backgroundSecondary,
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        final limit = int.tryParse(value);
                        if (limit != null && limit >= 1 && limit <= 50) {
                          setState(() {
                            _filters = _filters.copyWith(appointmentsLimit: limit);
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Botões
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _applyFilters,
                      icon: const Icon(Icons.filter_alt),
                      label: const Text('Aplicar Filtros'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _resetFilters,
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
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                          label: const Text('Cancelar'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

