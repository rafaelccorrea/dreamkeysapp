import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/sdr_dashboard_filters.dart';
import '../models/sdr_metrics_model.dart';

/// Bottom-sheet de filtros do dashboard SDR — gramática do
/// `KanbanFiltersDrawer` (referência dos modais de filtro do app), com o
/// acabamento do painel do agente: cabeçalho com título + descrição curta e
/// pill de filtros ativos, seções agrupadas por **barra tonal** + eyebrow,
/// chips em tint com check de estado, faixa-resumo do recorte vivo e footer
/// com Limpar (neutro) / **Aplicar em verde de confirmação**.
class SdrDashboardFiltersDrawer extends StatefulWidget {
  const SdrDashboardFiltersDrawer({
    super.key,
    required this.initialFilters,
    required this.teams,
    required this.onApply,
    required this.onClear,
  });

  final SdrDashboardFilters initialFilters;
  final List<SdrTeamOption> teams;
  final ValueChanged<SdrDashboardFilters> onApply;
  final VoidCallback onClear;

  @override
  State<SdrDashboardFiltersDrawer> createState() =>
      _SdrDashboardFiltersDrawerState();
}

class _SdrDashboardFiltersDrawerState extends State<SdrDashboardFiltersDrawer> {
  late SdrPeriodPreset _preset;
  DateTime? _customStart;
  DateTime? _customEnd;
  late Set<String> _teamIds;

  @override
  void initState() {
    super.initState();
    final f = widget.initialFilters;
    _preset = f.preset;
    _customStart = f.customStart;
    _customEnd = f.customEnd;
    _teamIds = Set<String>.from(f.teamIds);
  }

  static String _fmt(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

  SdrDashboardFilters _buildFilters() {
    return SdrDashboardFilters(
      preset: _preset,
      customStart: _customStart,
      customEnd: _customEnd,
      teamIds: _teamIds,
    );
  }

  int get _activeCount => _buildFilters().activeCount;

  Future<void> _pickDate({required bool isStart}) async {
    final fallback = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _customStart : _customEnd) ?? fallback,
      firstDate: DateTime(2018),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('pt', 'BR'),
    );
    if (picked == null) return;
    setState(() {
      _preset = SdrPeriodPreset.custom;
      if (isStart) {
        _customStart = picked;
      } else {
        _customEnd = picked;
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
    final cHeader =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    final cPeriodo =
        isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final cEquipes =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final mq = MediaQuery.of(context);
    final activeCount = _activeCount;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.45,
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
              _buildHeader(context, cHeader, activeCount),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                  children: [
                    _section(
                      context,
                      accent: cPeriodo,
                      icon: LucideIcons.calendarRange,
                      label: 'Período',
                      hint: 'Recorte de datas das métricas de pré-atendimento.',
                      first: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final p in SdrPeriodPreset.values)
                                if (p != SdrPeriodPreset.custom)
                                  _ChipChoice(
                                    label: p.label,
                                    selected: _preset == p,
                                    accent: cPeriodo,
                                    onTap: () =>
                                        setState(() => _preset = p),
                                  ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _dateControl(
                                  context,
                                  accent: cPeriodo,
                                  value: _preset == SdrPeriodPreset.custom
                                      ? _customStart
                                      : null,
                                  placeholder: 'De',
                                  onTap: () => _pickDate(isStart: true),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _dateControl(
                                  context,
                                  accent: cPeriodo,
                                  value: _preset == SdrPeriodPreset.custom
                                      ? _customEnd
                                      : null,
                                  placeholder: 'Até',
                                  onTap: () => _pickDate(isStart: false),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _rangeSummary(context, cPeriodo),
                        ],
                      ),
                    ),
                    if (widget.teams.isNotEmpty)
                      _section(
                        context,
                        accent: cEquipes,
                        icon: LucideIcons.users,
                        label: 'Equipes',
                        hint:
                            'Vazio considera todas as equipes com funil SDR.',
                        trailing: _teamIds.isEmpty
                            ? null
                            : _sectionStateChip(
                                context,
                                cEquipes,
                                '${_teamIds.length} de ${widget.teams.length}',
                              ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final t in widget.teams)
                                  _ChipChoice(
                                    label: t.name,
                                    selected: _teamIds.contains(t.id),
                                    accent: cEquipes,
                                    onTap: () => setState(() {
                                      if (!_teamIds.remove(t.id)) {
                                        _teamIds.add(t.id);
                                      }
                                    }),
                                  ),
                              ],
                            ),
                            if (_teamIds.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: InkWell(
                                  onTap: () =>
                                      setState(() => _teamIds.clear()),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 3),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          LucideIcons.rotateCcw,
                                          size: 12,
                                          color:
                                              ThemeHelpers.textSecondaryColor(
                                                  context),
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          'Limpar seleção de equipes',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color:
                                                ThemeHelpers
                                                    .textSecondaryColor(
                                                        context),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              _buildFooter(context, activeCount, mq),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.20 : 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.30)),
            ),
            child:
                Icon(LucideIcons.slidersHorizontal, color: accent, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        'Filtrar métricas',
                        softWrap: true,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                    ),
                    if (activeCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: accent.withValues(
                              alpha: isDark ? 0.18 : 0.10),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: accent.withValues(alpha: 0.40)),
                        ),
                        child: Text(
                          '$activeCount ativo${activeCount == 1 ? '' : 's'}',
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w900,
                            fontSize: 10.5,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Recorte de período e equipes do funil do agente.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 20),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Fechar',
          ),
        ],
      ),
    );
  }

  /// Seção com **barra tonal** + eyebrow (título de seção nunca trunca) e
  /// hint curta; `trailing` mostra o estado atual da seção (ex.: `2 de 5`).
  Widget _section(
    BuildContext context, {
    required Color accent,
    required IconData icon,
    required String label,
    String? hint,
    Widget? trailing,
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  width: 18,
                  height: 3,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, size: 13, color: accent),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  softWrap: true,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                    height: 1.4,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing,
              ],
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

  Widget _sectionStateChip(BuildContext context, Color accent, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.16 : 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.w900,
          fontSize: 10.5,
          height: 1.2,
        ),
      ),
    );
  }

  /// Faixa-resumo viva do recorte: sempre mostra o intervalo efetivo que será
  /// aplicado (estado claro, sem surpresa ao tocar em Aplicar).
  Widget _rangeSummary(BuildContext context, Color accent) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final r = _buildFilters().resolvedRange();
    final days = r.end.difference(r.start).inDays + 1;
    final fmt = DateFormat('dd/MM/yy', 'pt_BR');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.calendarCheck2, size: 15, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${fmt.format(r.start)} — ${fmt.format(r.end)}',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: ThemeHelpers.textColor(context),
                letterSpacing: -0.1,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$days dia${days == 1 ? '' : 's'}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateControl(
    BuildContext context, {
    required Color accent,
    required DateTime? value,
    required String placeholder,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final filled = value != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
        decoration: BoxDecoration(
          color: fieldFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: filled
                ? accent.withValues(alpha: 0.55)
                : ThemeHelpers.borderLightColor(context),
            width: filled ? 1.2 : 1,
          ),
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
              child: Icon(LucideIcons.calendar, size: 16, color: accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                filled ? _fmt(value) : placeholder,
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
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(
    BuildContext context,
    int activeCount,
    MediaQueryData mq,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Verde = confirmação (Aplicar). Limpar é sempre neutro — nunca vermelho.
    final confirm =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
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
                icon: const Icon(LucideIcons.filterX, size: 17),
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
              icon: const Icon(LucideIcons.check, size: 18),
              label: Text(
                activeCount == 0 ? 'Aplicar' : 'Aplicar ($activeCount)',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: confirm,
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
}

/// Chip de seleção em tint — igual ao do modal de filtros do CRM, com check
/// explícito quando selecionado (estado claro sem depender só da cor).
class _ChipChoice extends StatelessWidget {
  const _ChipChoice({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.accent,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;

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
            if (selected) ...[
              Icon(LucideIcons.check, size: 13, color: fg),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontSize: 12.5,
                  color: fg,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Filete tracejado fino — separa seções como no modal do CRM.
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
