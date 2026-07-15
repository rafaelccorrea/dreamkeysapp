import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/goal_model.dart';

/// Bottom-sheet de filtros das Metas — espelha o padrão do modal de filtros
/// do CRM (`kanban_filters_drawer.dart`): seções *flush* separadas por filete
/// tracejado + eyebrow com dot de cor, chips de seleção em tint, footer com
/// Limpar/Aplicar. Filtros de tipo/período/escopo/corretor/equipe/só ativas
/// (paridade com o `GoalsFilters` do web).
class GoalsFiltersSheet extends StatefulWidget {
  final GoalFilters initialFilters;
  final GoalFormOptions options;
  final ValueChanged<GoalFilters> onApply;
  final VoidCallback onClear;

  const GoalsFiltersSheet({
    super.key,
    required this.initialFilters,
    required this.options,
    required this.onApply,
    required this.onClear,
  });

  @override
  State<GoalsFiltersSheet> createState() => _GoalsFiltersSheetState();
}

class _GoalsFiltersSheetState extends State<GoalsFiltersSheet> {
  GoalType? _type;
  GoalPeriod? _period;
  GoalScope? _scope;
  String? _userId;
  String? _teamId;
  bool _onlyActive = false;

  @override
  void initState() {
    super.initState();
    final f = widget.initialFilters;
    _type = f.type;
    _period = f.period;
    _scope = f.scope;
    _userId = f.userId;
    _teamId = f.teamId;
    _onlyActive = f.onlyActive ?? false;
  }

  GoalFilters _buildFilters() {
    return GoalFilters(
      type: _type,
      period: _period,
      scope: _scope,
      userId: _userId,
      teamId: _teamId,
      onlyActive: _onlyActive ? true : null,
      // Busca e status (aba) são controlados pela página — preservados.
      search: widget.initialFilters.search,
      status: widget.initialFilters.status,
    );
  }

  int get _activeCount => _buildFilters().activeCount;

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
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final cTipo =
        isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final cPeriodo =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    final cEscopo =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final cResp =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
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
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
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
                      accent: cTipo,
                      label: 'Tipo da meta',
                      hint: 'Indicador acompanhado pela meta.',
                      first: true,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ChipChoice(
                            label: 'Todos',
                            selected: _type == null,
                            accent: cTipo,
                            onTap: () => setState(() => _type = null),
                          ),
                          for (final t in GoalType.selectable)
                            _ChipChoice(
                              label: t.label,
                              selected: _type == t,
                              accent: cTipo,
                              onTap: () => setState(() => _type = t),
                            ),
                        ],
                      ),
                    ),
                    _section(
                      context,
                      accent: cPeriodo,
                      label: 'Período',
                      hint: 'Recorrência da meta.',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ChipChoice(
                            label: 'Todos',
                            selected: _period == null,
                            accent: cPeriodo,
                            onTap: () => setState(() => _period = null),
                          ),
                          for (final p in GoalPeriod.selectable)
                            _ChipChoice(
                              label: p.label,
                              selected: _period == p,
                              accent: cPeriodo,
                              onTap: () => setState(() => _period = p),
                            ),
                        ],
                      ),
                    ),
                    _section(
                      context,
                      accent: cEscopo,
                      label: 'Escopo',
                      hint: 'Empresa, equipe ou corretor individual.',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ChipChoice(
                            label: 'Todos',
                            selected: _scope == null,
                            accent: cEscopo,
                            onTap: () => setState(() => _scope = null),
                          ),
                          for (final s in GoalScope.selectable)
                            _ChipChoice(
                              label: s.label,
                              selected: _scope == s,
                              accent: cEscopo,
                              onTap: () => setState(() => _scope = s),
                            ),
                        ],
                      ),
                    ),
                    _section(
                      context,
                      accent: cResp,
                      label: 'Corretor',
                      hint: 'Corretores que possuem metas.',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ChipChoice(
                            label: 'Todos',
                            selected: _userId == null,
                            accent: cResp,
                            onTap: () => setState(() => _userId = null),
                          ),
                          for (final u in widget.options.users)
                            _ChipChoice(
                              label: _firstName(u.name),
                              selected: _userId == u.id,
                              accent: cResp,
                              onTap: () => setState(() {
                                _userId = _userId == u.id ? null : u.id;
                              }),
                            ),
                          if (widget.options.users.isEmpty)
                            _emptyHint(
                                context, 'Nenhum corretor com metas.'),
                        ],
                      ),
                    ),
                    _section(
                      context,
                      accent: cResp,
                      label: 'Equipe',
                      hint: 'Equipes que possuem metas.',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ChipChoice(
                            label: 'Todas',
                            selected: _teamId == null,
                            accent: cResp,
                            onTap: () => setState(() => _teamId = null),
                          ),
                          for (final t in widget.options.teams)
                            _ChipChoice(
                              label: t.name,
                              selected: _teamId == t.id,
                              accent: cResp,
                              onTap: () => setState(() {
                                _teamId = _teamId == t.id ? null : t.id;
                              }),
                            ),
                          if (widget.options.teams.isEmpty)
                            _emptyHint(context, 'Nenhuma equipe com metas.'),
                        ],
                      ),
                    ),
                    _section(
                      context,
                      accent: accent,
                      label: 'Situação',
                      hint: 'Restringir a metas marcadas como ativas.',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ChipChoice(
                            label: 'Somente ativas',
                            icon: LucideIcons.circleCheck,
                            selected: _onlyActive,
                            accent: accent,
                            onTap: () =>
                                setState(() => _onlyActive = !_onlyActive),
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
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
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
                  'Filtrar metas',
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
}

/// Chip de seleção — ativo usa *tint* (fundo translúcido + borda + texto na
/// cor), nunca preenchimento sólido.
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
    final isDark = theme.brightness == Brightness.dark;
    final fieldFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final fg = selected
        ? accent
        : ThemeHelpers.textColor(context).withValues(alpha: 0.82);
    final bg =
        selected ? accent.withValues(alpha: isDark ? 0.18 : 0.10) : fieldFill;
    final border = selected ? accent : ThemeHelpers.borderLightColor(context);
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
            if (icon != null) ...[
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

/// Filete tracejado fino — separa seções como na web.
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
