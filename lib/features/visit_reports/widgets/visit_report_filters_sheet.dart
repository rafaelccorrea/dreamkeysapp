import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/visit_report_model.dart';
import 'visit_report_pickers.dart';

/// Bottom-sheet de filtros das visitas — espelha o padrão do modal de filtros
/// do CRM (`kanban_filters_drawer.dart`): seções *flush* separadas por filete
/// tracejado + eyebrow com dot de cor; campos em pill com chip de ícone; cor
/// usada apenas como sinal, nunca preenchendo blocos.
class VisitReportFiltersSheet extends StatefulWidget {
  final VisitReportFilters initialFilters;
  final ValueChanged<VisitReportFilters> onApply;
  final VoidCallback onClear;

  const VisitReportFiltersSheet({
    super.key,
    required this.initialFilters,
    required this.onApply,
    required this.onClear,
  });

  @override
  State<VisitReportFiltersSheet> createState() =>
      _VisitReportFiltersSheetState();
}

class _VisitReportFiltersSheetState extends State<VisitReportFiltersSheet> {
  String? _clientId;
  String? _clientLabel;
  DateTime? _fromDate;
  DateTime? _toDate;
  VisitSignatureStatus? _status;

  @override
  void initState() {
    super.initState();
    final f = widget.initialFilters;
    _clientId = f.clientId;
    _clientLabel = f.clientLabel;
    _fromDate = f.fromDate;
    _toDate = f.toDate;
    _status = f.status;
  }

  static String _fmt(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

  Color _fieldFill(BuildContext c) => Theme.of(c).brightness == Brightness.dark
      ? AppColors.background.backgroundTertiaryDarkMode
      : AppColors.background.backgroundTertiary;

  VisitReportFilters _buildFilters() => VisitReportFilters(
        clientId: _clientId,
        clientLabel: _clientLabel,
        fromDate: _fromDate,
        toDate: _toDate,
        status: _status,
      );

  int get _activeCount => _buildFilters().activeCount;

  Future<void> _pickDate({required bool isStart}) async {
    final initial = (isStart ? _fromDate : _toDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('pt', 'BR'),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _fromDate = picked;
      } else {
        _toDate = picked;
      }
    });
  }

  Future<void> _pickClient() async {
    final selected = await showClientPicker(context);
    if (selected == null) return;
    setState(() {
      _clientId = selected.id;
      _clientLabel = selected.name;
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
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final cCliente =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final cPeriodo =
        isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final cStatus =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final mq = MediaQuery.of(context);
    final activeCount = _activeCount;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
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
                      accent: cCliente,
                      label: 'Cliente',
                      hint: 'Mostre só as visitas de um cliente.',
                      first: true,
                      child: _clientControl(context, cCliente),
                    ),
                    _section(
                      context,
                      accent: cPeriodo,
                      label: 'Período da visita',
                      hint: 'Visitas realizadas entre as datas.',
                      child: Row(
                        children: [
                          Expanded(
                            child: _dateControl(
                              context,
                              accent: cPeriodo,
                              value: _fromDate,
                              placeholder: 'De',
                              onTap: () => _pickDate(isStart: true),
                              onClear: () => setState(() => _fromDate = null),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _dateControl(
                              context,
                              accent: cPeriodo,
                              value: _toDate,
                              placeholder: 'Até',
                              onTap: () => _pickDate(isStart: false),
                              onClear: () => setState(() => _toDate = null),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _section(
                      context,
                      accent: cStatus,
                      label: 'Status da assinatura',
                      hint: 'Aguardando, assinado ou link expirado.',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ChipChoice(
                            label: 'Todos',
                            selected: _status == null,
                            accent: cStatus,
                            onTap: () => setState(() => _status = null),
                          ),
                          for (final s in const [
                            VisitSignatureStatus.pending,
                            VisitSignatureStatus.signed,
                            VisitSignatureStatus.expired,
                          ])
                            _ChipChoice(
                              label: s.shortLabel,
                              selected: _status == s,
                              accent: cStatus,
                              onTap: () => setState(() => _status = s),
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
                  'Filtrar visitas',
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

  Widget _clientControl(BuildContext context, Color accent) {
    final filled = _clientId != null;
    return _filterControl(
      context,
      icon: LucideIcons.userRound,
      accent: accent,
      onTap: _pickClient,
      child: Row(
        children: [
          Expanded(
            child: Text(
              filled ? (_clientLabel ?? 'Cliente') : 'Todos os clientes',
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
          if (filled)
            GestureDetector(
              onTap: () => setState(() {
                _clientId = null;
                _clientLabel = null;
              }),
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
    required DateTime? value,
    required String placeholder,
    required VoidCallback onTap,
    required VoidCallback onClear,
  }) {
    final filled = value != null;
    return _filterControl(
      context,
      icon: Icons.calendar_today_outlined,
      accent: accent,
      onTap: onTap,
      child: Row(
        children: [
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
}

/// Chip de seleção — ativo usa *tint* (fundo translúcido + borda + texto na
/// cor), nunca preenchimento sólido (mesma gramática do modal do CRM).
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = selected ? accent : ThemeHelpers.textSecondaryColor(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: isDark ? 0.18 : 0.11)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.5)
                : ThemeHelpers.borderColor(context),
            width: selected ? 1.3 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: fg,
            letterSpacing: -0.1,
          ),
        ),
      ),
    );
  }
}

/// Filete tracejado — separador das seções flush.
class _DashedLine extends StatelessWidget {
  const _DashedLine({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dashWidth = 5.0;
        const gap = 4.0;
        final count = (constraints.maxWidth / (dashWidth + gap)).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            count,
            (_) => Container(width: dashWidth, height: 1, color: color),
          ),
        );
      },
    );
  }
}
