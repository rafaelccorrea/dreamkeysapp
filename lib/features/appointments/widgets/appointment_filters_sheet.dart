import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/appointment_model.dart';
import 'appointment_helpers.dart';

/// Estado dos filtros aplicáveis na agenda.
class CalendarFiltersState {
  final AppointmentStatus? status;
  final AppointmentType? type;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool onlyMyData;

  const CalendarFiltersState({
    this.status,
    this.type,
    this.startDate,
    this.endDate,
    this.onlyMyData = false,
  });

  bool get hasActiveFilters =>
      status != null ||
      type != null ||
      startDate != null ||
      endDate != null ||
      onlyMyData;

  int get activeFilterCount {
    int n = 0;
    if (status != null) n++;
    if (type != null) n++;
    if (startDate != null || endDate != null) n++;
    if (onlyMyData) n++;
    return n;
  }

  CalendarFiltersState copyWith({
    Object? status = _unset,
    Object? type = _unset,
    Object? startDate = _unset,
    Object? endDate = _unset,
    bool? onlyMyData,
  }) {
    return CalendarFiltersState(
      status: identical(status, _unset)
          ? this.status
          : status as AppointmentStatus?,
      type: identical(type, _unset) ? this.type : type as AppointmentType?,
      startDate: identical(startDate, _unset)
          ? this.startDate
          : startDate as DateTime?,
      endDate:
          identical(endDate, _unset) ? this.endDate : endDate as DateTime?,
      onlyMyData: onlyMyData ?? this.onlyMyData,
    );
  }
}

const _unset = Object();

/// Bottom-sheet de filtros da agenda — paridade visual com os modais de filtro
/// da casa (ver `kanban_filters_drawer.dart`): seções *flush* (sem cards)
/// separadas por filete tracejado + eyebrow com dot de cor; controles em pill
/// com roundel de ícone; chips com *tint* (nunca sólido); cor usada só como
/// sinal (dot/ícone/ativo), nunca preenchendo blocos. Rodapé com Limpar (cinza,
/// não é destrutivo) + Aplicar (verde de confirmação, com contador).
class AppointmentFiltersSheet extends StatefulWidget {
  final CalendarFiltersState initial;
  final ValueChanged<CalendarFiltersState> onApply;

  const AppointmentFiltersSheet({
    super.key,
    required this.initial,
    required this.onApply,
  });

  @override
  State<AppointmentFiltersSheet> createState() =>
      _AppointmentFiltersSheetState();
}

class _AppointmentFiltersSheetState extends State<AppointmentFiltersSheet> {
  late CalendarFiltersState _state;

  @override
  void initState() {
    super.initState();
    _state = widget.initial;
  }

  Color _fieldFill(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
          ? AppColors.background.backgroundTertiaryDarkMode
          : AppColors.background.backgroundTertiary;

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isQuickRange(int days) {
    if (_state.startDate == null || _state.endDate == null) return false;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(Duration(days: days - 1));
    return _sameDay(_state.startDate!, start) && _sameDay(_state.endDate!, end);
  }

  void _quickRange(int days) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(Duration(days: days - 1));
    final already = _isQuickRange(days);
    setState(() {
      _state = already
          ? _state.copyWith(startDate: null, endDate: null)
          : _state.copyWith(startDate: start, endDate: end);
    });
  }

  Future<void> _pickRange(Color accent) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      initialDateRange: (_state.startDate != null && _state.endDate != null)
          ? DateTimeRange(start: _state.startDate!, end: _state.endDate!)
          : null,
      locale: const Locale('pt', 'BR'),
      saveText: 'Aplicar',
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: accent),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _state = _state.copyWith(startDate: picked.start, endDate: picked.end);
      });
    }
  }

  void _apply() {
    widget.onApply(_state);
    Navigator.of(context).pop();
  }

  void _clear() => setState(() => _state = const CalendarFiltersState());

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Acento da marca (header + contador).
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    // Acento por seção — só sinal (dot + ícone + ativo), em tons refinados.
    final cPeriodo =
        isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final cStatus =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final cTipo =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    final cView = accent;
    final mq = MediaQuery.of(context);
    final activeCount = _state.activeFilterCount;

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
                      accent: cPeriodo,
                      label: 'Período',
                      hint: 'Recorte o intervalo mostrado no calendário.',
                      first: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _ChipChoice(
                                label: 'Hoje',
                                icon: Icons.today_rounded,
                                selected: _isQuickRange(1),
                                accent: cPeriodo,
                                onTap: () => _quickRange(1),
                              ),
                              _ChipChoice(
                                label: '7 dias',
                                icon: Icons.view_week_rounded,
                                selected: _isQuickRange(7),
                                accent: cPeriodo,
                                onTap: () => _quickRange(7),
                              ),
                              _ChipChoice(
                                label: '30 dias',
                                icon: Icons.calendar_view_month_rounded,
                                selected: _isQuickRange(30),
                                accent: cPeriodo,
                                onTap: () => _quickRange(30),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _rangeControl(context, cPeriodo),
                        ],
                      ),
                    ),
                    _section(
                      context,
                      accent: cStatus,
                      label: 'Status',
                      hint: 'Estágio do compromisso.',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ChipChoice(
                            label: 'Todos',
                            icon: Icons.all_inclusive_rounded,
                            selected: _state.status == null,
                            accent: cStatus,
                            onTap: () => setState(
                              () => _state = _state.copyWith(status: null),
                            ),
                          ),
                          for (final s in AppointmentStatus.values)
                            _ChipChoice(
                              label: s.label,
                              icon: AppointmentVisuals.iconForStatus(s),
                              selected: _state.status == s,
                              accent: AppointmentVisuals.colorForStatus(s),
                              onTap: () => setState(
                                () => _state = _state.copyWith(
                                  status: _state.status == s ? null : s,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    _section(
                      context,
                      accent: cTipo,
                      label: 'Tipo',
                      hint: 'Natureza do agendamento.',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ChipChoice(
                            label: 'Todos',
                            icon: Icons.apps_rounded,
                            selected: _state.type == null,
                            accent: cTipo,
                            onTap: () => setState(
                              () => _state = _state.copyWith(type: null),
                            ),
                          ),
                          for (final t in AppointmentType.values)
                            _ChipChoice(
                              label: t.label,
                              icon: AppointmentVisuals.iconFor(t),
                              selected: _state.type == t,
                              accent: cTipo,
                              onTap: () => setState(
                                () => _state = _state.copyWith(
                                  type: _state.type == t ? null : t,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    _section(
                      context,
                      accent: cView,
                      label: 'Visualização',
                      hint: 'Quem aparece na agenda.',
                      child: _filterControl(
                        context,
                        icon: Icons.person_outline_rounded,
                        accent: cView,
                        onTap: () => setState(
                          () => _state = _state.copyWith(
                            onlyMyData: !_state.onlyMyData,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Apenas meus agendamentos',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.1,
                                          color: ThemeHelpers.textColor(context),
                                        ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    'Esconde os criados por outros corretores.',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: ThemeHelpers
                                              .textSecondaryColor(context),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Switch.adaptive(
                              value: _state.onlyMyData,
                              activeColor: cView,
                              onChanged: (v) => setState(
                                () => _state = _state.copyWith(onlyMyData: v),
                              ),
                            ),
                          ],
                        ),
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
            alignment: Alignment.center,
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
                  'Filtros da agenda',
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
            alignment: Alignment.center,
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

  Widget _rangeControl(BuildContext context, Color accent) {
    final filled = _state.startDate != null && _state.endDate != null;
    final label = filled
        ? '${DateFormat('dd MMM', 'pt_BR').format(_state.startDate!)} → ${DateFormat('dd MMM', 'pt_BR').format(_state.endDate!)}'
        : 'Selecionar intervalo personalizado';
    return _filterControl(
      context,
      icon: Icons.date_range_rounded,
      accent: accent,
      onTap: () => _pickRange(accent),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
          const SizedBox(width: 6),
          if (filled)
            GestureDetector(
              onTap: () => setState(
                () => _state = _state.copyWith(startDate: null, endDate: null),
              ),
              child: Icon(
                Icons.close_rounded,
                size: 18,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            )
          else
            Icon(Icons.chevron_right_rounded, size: 19, color: accent),
        ],
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
              child: TextButton(
                onPressed: _clear,
                style: TextButton.styleFrom(
                  // "Limpar" NUNCA em vermelho: o tema global pinta TextButton
                  // de vermelho, então forçamos o cinza — não é ação
                  // destrutiva, só volta ao estado inicial.
                  foregroundColor: ThemeHelpers.textSecondaryColor(context),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                  textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Limpar filtros'),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            flex: activeCount > 0 ? 2 : 1,
            child: FilledButton.icon(
              onPressed: _apply,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  activeCount == 0 ? 'Aplicar' : 'Aplicar ($activeCount)',
                ),
              ),
              style: FilledButton.styleFrom(
                // VERDE de confirmação — como em todo sheet do app. O vermelho
                // da marca aqui só caberia em erro/ação destrutiva.
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
                elevation: 0,
                textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip de seleção — ativo usa *tint* (fundo translúcido + borda + texto na
/// cor), nunca preenchimento sólido com texto branco (evita o visual "candy").
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
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
