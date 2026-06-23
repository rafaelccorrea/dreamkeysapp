import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/kanban_models.dart';

/// Bottom-sheet de filtros do board do Kanban — paridade visual com os modais
/// de filtro da web: seções *flush* (sem cards), separadas por filete tracejado
/// + eyebrow com dot de cor; campos em pill com chip de ícone discreto; cor
/// usada apenas como sinal (dot/ícone/ativo), nunca preenchendo blocos.
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

  Color _fieldFill(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
          ? AppColors.background.backgroundTertiaryDarkMode
          : AppColors.background.backgroundTertiary;

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Acento da marca (header, contador, botão Aplicar).
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    // Acento por seção — usado só como sinal (dot + ícone + ativo), em tons
    // refinados (sem candy/arco-íris).
    final cBusca =
        isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final cResp =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final cTags =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    final cResult =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final cPeriodo =
        isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final mq = MediaQuery.of(context);
    final activeCount = _activeCount;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: ThemeHelpers.backgroundColor(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.40),
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Center(
                  child: Container(
                    width: 40,
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
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                  children: [
                    _section(
                      context,
                      accent: cBusca,
                      label: 'Busca',
                      hint: 'Nome, telefone, cliente ou título do lead.',
                      first: true,
                      child: _searchControl(context, cBusca),
                    ),
                    _section(
                      context,
                      accent: cResp,
                      label: 'Responsável',
                      hint: 'Filtre por um ou mais corretores.',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ChipChoice(
                            label: 'Sem responsável',
                            icon: Icons.person_off_outlined,
                            selected: _unassigned,
                            accent: cResp,
                            onTap: () => setState(() {
                              _unassigned = !_unassigned;
                              if (_unassigned) _assignedToIds.clear();
                            }),
                          ),
                          for (final u in widget.assignees)
                            _ChipChoice(
                              label: _firstName(u.name),
                              selected: _assignedToIds.contains(u.id),
                              accent: cResp,
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
                    _section(
                      context,
                      accent: cTags,
                      label: 'Tags',
                      hint: 'Filtre por etiquetas do CRM.',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final t in widget.tags)
                            _ChipChoice(
                              label: t.name,
                              selected: _tagIds.contains(t.id),
                              accent: _hex(t.color) ?? cTags,
                              dot: true,
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
                    _section(
                      context,
                      accent: cResult,
                      label: 'Resultado',
                      hint: 'Estágio do negócio.',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ChipChoice(
                            label: 'Todos',
                            selected: _result == null,
                            accent: cResult,
                            onTap: () => setState(() => _result = null),
                          ),
                          for (final r in KanbanResultFilter.values)
                            _ChipChoice(
                              label: r.label,
                              selected: _result == r,
                              accent: cResult,
                              onTap: () => setState(() => _result = r),
                            ),
                        ],
                      ),
                    ),
                    _section(
                      context,
                      accent: cPeriodo,
                      label: 'Período de criação',
                      hint: 'Leads criados entre as datas.',
                      child: Row(
                        children: [
                          Expanded(
                            child: _dateControl(
                              context,
                              accent: cPeriodo,
                              controller: _createdFromController,
                              placeholder: 'De',
                              onTap: () => _pickDate(isStart: true),
                              onClear: () => setState(() {
                                _createdAfter = null;
                                _createdFromController.clear();
                              }),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _dateControl(
                              context,
                              accent: cPeriodo,
                              controller: _createdToController,
                              placeholder: 'Até',
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
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 4, 10, 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: ThemeHelpers.borderLightColor(context),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.20 : 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.tune_rounded, color: accent, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filtrar leads',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
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

  /// Seção *flush*: filete tracejado (exceto a primeira) + eyebrow com dot de
  /// cor + hint + conteúdo. Sem card, sem sombra, sem preenchimento.
  Widget _section(
    BuildContext context, {
    required Color accent,
    required String label,
    String? hint,
    required Widget child,
    bool first = false,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: first ? 16 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!first) ...[
            _DashedLine(color: ThemeHelpers.borderLightColor(context)),
            const SizedBox(height: 18),
          ],
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.45),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
              ),
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(
              hint,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                height: 1.3,
                color: ThemeHelpers.textSecondaryColor(context)
                    .withValues(alpha: 0.85),
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  /// Shell de campo no padrão da web (FilterControl): pill com chip de ícone
  /// discreto + conteúdo bare.
  Widget _filterControl(
    BuildContext context, {
    required IconData icon,
    required Color accent,
    required Widget child,
    VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final control = Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
      decoration: BoxDecoration(
        color: _fieldFill(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ThemeHelpers.borderLightColor(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.20 : 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
    if (onTap == null) return control;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: control,
    );
  }

  Widget _searchControl(BuildContext context, Color accent) {
    final hasText = _searchController.text.isNotEmpty;
    return _filterControl(
      context,
      icon: Icons.search_rounded,
      accent: accent,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              textAlignVertical: TextAlignVertical.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ThemeHelpers.textColor(context),
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'Nome, telefone, cliente…',
                hintStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: ThemeHelpers.textSecondaryColor(context)
                      .withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
          if (hasText)
            GestureDetector(
              onTap: () => setState(() => _searchController.clear()),
              child: Icon(
                Icons.close_rounded,
                size: 18,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dateControl(
    BuildContext context, {
    required Color accent,
    required TextEditingController controller,
    required String placeholder,
    required VoidCallback onTap,
    required VoidCallback onClear,
  }) {
    final filled = controller.text.isNotEmpty;
    return _filterControl(
      context,
      icon: Icons.calendar_today_outlined,
      accent: accent,
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Text(
              filled ? controller.text : placeholder,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: filled
                    ? ThemeHelpers.textColor(context)
                    : ThemeHelpers.textSecondaryColor(context)
                        .withValues(alpha: 0.9),
              ),
            ),
          ),
          if (filled)
            GestureDetector(
              onTap: onClear,
              child: Icon(
                Icons.close_rounded,
                size: 18,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
        ],
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
          if (activeCount > 0) ...[
            Expanded(
              flex: 3,
              child: OutlinedButton.icon(
                onPressed: _clear,
                icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                label: const Text(
                  'Limpar',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ThemeHelpers.textSecondaryColor(context),
                  side: BorderSide(color: ThemeHelpers.borderColor(context)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            flex: activeCount > 0 ? 4 : 1,
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

/// Chip de seleção — ativo usa *tint* (fundo translúcido + borda + texto na cor),
/// nunca preenchimento sólido com texto branco (evita o visual "candy").
class _ChipChoice extends StatelessWidget {
  const _ChipChoice({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.accent,
    this.icon,
    this.dot = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;
  final IconData? icon;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fieldFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final fg = selected
        ? accent
        : ThemeHelpers.textColor(context).withValues(alpha: 0.82);
    final bg = selected
        ? accent.withValues(alpha: isDark ? 0.18 : 0.10)
        : fieldFill;
    final border =
        selected ? accent : ThemeHelpers.borderLightColor(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border, width: selected ? 1.2 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
            ] else if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontSize: 12.5,
                color: fg,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Filete tracejado fino — separa seções como na web (1px dashed borderLight).
class _DashedLine extends StatelessWidget {
  const _DashedLine({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      width: double.infinity,
      child: CustomPaint(painter: _DashedPainter(color)),
    );
  }
}

class _DashedPainter extends CustomPainter {
  _DashedPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const dash = 5.0;
    const gap = 4.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dash, 0), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPainter oldDelegate) =>
      oldDelegate.color != color;
}
