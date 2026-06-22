import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../models/kanban_models.dart';

/// Bottom-sheet de filtros do board do Kanban — paridade com os filtros úteis
/// da web (responsável, tags, resultado, período de criação e busca).
///
/// As opções de responsável e tags são derivadas do board atual (passadas via
/// [assignees] / [tags]), evitando endpoints extras.
class KanbanFiltersDrawer extends StatefulWidget {
  final KanbanBoardFilters initialFilters;
  final List<KanbanUser> assignees;
  final List<KanbanTagDetail> tags;
  final ValueChanged<KanbanBoardFilters> onApply;
  final VoidCallback onClear;

  const KanbanFiltersDrawer({
    super.key,
    required this.initialFilters,
    required this.assignees,
    required this.tags,
    required this.onApply,
    required this.onClear,
  });

  @override
  State<KanbanFiltersDrawer> createState() => _KanbanFiltersDrawerState();
}

class _KanbanFiltersDrawerState extends State<KanbanFiltersDrawer> {
  final _searchController = TextEditingController();
  final _createdFromController = TextEditingController();
  final _createdToController = TextEditingController();

  late Set<String> _assignedToIds;
  late bool _unassigned;
  late Set<String> _tagIds;
  KanbanResultFilter? _result;
  DateTime? _createdAfter;
  DateTime? _createdBefore;

  @override
  void initState() {
    super.initState();
    final f = widget.initialFilters;
    _assignedToIds = Set<String>.from(f.assignedToIds);
    _unassigned = f.unassigned;
    _tagIds = Set<String>.from(f.tagIds);
    _result = f.result;
    _createdAfter = f.createdAfter;
    _createdBefore = f.createdBefore;
    _searchController.text = f.search ?? '';
    if (_createdAfter != null) {
      _createdFromController.text = _fmt(_createdAfter!);
    }
    if (_createdBefore != null) {
      _createdToController.text = _fmt(_createdBefore!);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _createdFromController.dispose();
    _createdToController.dispose();
    super.dispose();
  }

  static String _fmt(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

  KanbanBoardFilters _buildFilters() {
    final s = _searchController.text.trim();
    return KanbanBoardFilters(
      assignedToIds: _assignedToIds,
      unassigned: _unassigned,
      tagIds: _tagIds,
      result: _result,
      search: s.isEmpty ? null : s,
      createdAfter: _createdAfter,
      createdBefore: _createdBefore,
    );
  }

  int get _activeCount => _buildFilters().activeCount;

  Future<void> _pickDate({required bool isStart}) async {
    final initial =
        (isStart ? _createdAfter : _createdBefore) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('pt', 'BR'),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _createdAfter = picked;
        _createdFromController.text = _fmt(picked);
      } else {
        _createdBefore = picked;
        _createdToController.text = _fmt(picked);
      }
    });
  }

  void _apply() {
    widget.onApply(_buildFilters());
    Navigator.of(context).pop();
  }

  void _clear() {
    widget.onClear();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Acento da marca/Kanban (igual ao botão "Filtros" e ao board).
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final mq = MediaQuery.of(context);
    final activeCount = _activeCount;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: ThemeHelpers.backgroundColor(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ThemeHelpers.borderColor(context)
                          .withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
              _buildHeader(context, accent, activeCount),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  children: [
                    _buildSection(
                      context,
                      icon: Icons.search_rounded,
                      accent: accent,
                      title: 'Busca',
                      description: 'Nome, telefone, cliente ou título do lead.',
                      child: CustomTextField(
                        controller: _searchController,
                        label: 'Buscar leads',
                        prefixIcon: const Icon(Icons.search_rounded),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildSection(
                      context,
                      icon: Icons.person_outline_rounded,
                      accent: accent,
                      title: 'Responsável',
                      description: 'Filtre por um ou mais corretores.',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ChipChoice(
                            label: 'Sem responsável',
                            icon: Icons.person_off_outlined,
                            selected: _unassigned,
                            accent: accent,
                            onTap: () => setState(() {
                              _unassigned = !_unassigned;
                              if (_unassigned) _assignedToIds.clear();
                            }),
                          ),
                          for (final u in widget.assignees)
                            _ChipChoice(
                              label: _firstName(u.name),
                              selected: _assignedToIds.contains(u.id),
                              accent: accent,
                              onTap: () => setState(() {
                                if (!_assignedToIds.remove(u.id)) {
                                  _assignedToIds.add(u.id);
                                  _unassigned = false;
                                }
                              }),
                            ),
                          if (widget.assignees.isEmpty)
                            _emptyHint(context,
                                'Nenhum responsável nos leads visíveis.'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildSection(
                      context,
                      icon: Icons.sell_outlined,
                      accent: accent,
                      title: 'Tags',
                      description: 'Filtre por etiquetas do CRM.',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final t in widget.tags)
                            _ChipChoice(
                              label: t.name,
                              selected: _tagIds.contains(t.id),
                              accent: _hex(t.color) ?? accent,
                              onTap: () => setState(() {
                                if (!_tagIds.remove(t.id)) _tagIds.add(t.id);
                              }),
                            ),
                          if (widget.tags.isEmpty)
                            _emptyHint(
                                context, 'Nenhuma tag nos leads visíveis.'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildSection(
                      context,
                      icon: Icons.flag_outlined,
                      accent: accent,
                      title: 'Resultado',
                      description: 'Estágio do negócio.',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ChipChoice(
                            label: 'Todos',
                            selected: _result == null,
                            accent: accent,
                            onTap: () => setState(() => _result = null),
                          ),
                          for (final r in KanbanResultFilter.values)
                            _ChipChoice(
                              label: r.label,
                              selected: _result == r,
                              accent: accent,
                              onTap: () => setState(() => _result = r),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildSection(
                      context,
                      icon: Icons.event_outlined,
                      accent: accent,
                      title: 'Período de criação',
                      description: 'Leads criados entre as datas.',
                      child: Row(
                        children: [
                          Expanded(
                            child: _dateField(
                              context,
                              controller: _createdFromController,
                              label: 'De',
                              accent: accent,
                              onTap: () => _pickDate(isStart: true),
                              onClear: () => setState(() {
                                _createdAfter = null;
                                _createdFromController.clear();
                              }),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _dateField(
                              context,
                              controller: _createdToController,
                              label: 'Até',
                              accent: accent,
                              onTap: () => _pickDate(isStart: false),
                              onClear: () => setState(() {
                                _createdBefore = null;
                                _createdToController.clear();
                              }),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _buildFooter(context, accent, activeCount, mq),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, Color accent, int activeCount) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [accent, const Color(0xFF7C3AED)],
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.32),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.tune_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filtrar leads',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  activeCount == 0
                      ? 'Nenhum filtro aplicado'
                      : '$activeCount filtro${activeCount == 1 ? '' : 's'} ativo${activeCount == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: activeCount == 0
                        ? ThemeHelpers.textSecondaryColor(context)
                        : accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Fechar',
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required IconData icon,
    required Color accent,
    required String title,
    required String description,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.42),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                  spreadRadius: -3,
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: accent.withValues(alpha: isDark ? 0.16 : 0.10),
                    border: Border.all(color: accent.withValues(alpha: 0.22)),
                  ),
                  child: Icon(icon, color: accent, size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _emptyHint(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w600,
          ),
    );
  }

  Widget _dateField(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required Color accent,
    required VoidCallback onTap,
    required VoidCallback onClear,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      onTap: onTap,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(Icons.calendar_today_outlined, color: accent, size: 18),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear_rounded, size: 18),
                onPressed: onClear,
              ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildFooter(
    BuildContext context,
    Color accent,
    int activeCount,
    MediaQueryData mq,
  ) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + mq.padding.bottom),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          top: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: activeCount == 0 ? null : _clear,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
              label: const Text('Limpar tudo'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: _apply,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text(
                activeCount == 0 ? 'Aplicar' : 'Aplicar ($activeCount)',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _firstName(String name) {
    final t = name.trim();
    if (t.isEmpty) return '—';
    final i = t.indexOf(' ');
    return i == -1 ? t : t.substring(0, i);
  }

  static Color? _hex(String? hex) {
    final raw = hex?.trim();
    if (raw == null || raw.isEmpty) return null;
    var h = raw.replaceFirst('#', '').toUpperCase();
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return null;
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(v);
  }
}

class _ChipChoice extends StatelessWidget {
  const _ChipChoice({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.accent,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected ? Colors.white : ThemeHelpers.textColor(context);
    final bg = selected ? accent : ThemeHelpers.cardBackgroundColor(context);
    final border =
        selected ? accent : ThemeHelpers.borderLightColor(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.30),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: fg,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
