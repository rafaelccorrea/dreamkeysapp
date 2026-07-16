import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/whatsapp_models.dart';

/// Bottom-sheet de filtros do WhatsApp Inbox — espelha o modal de filtros do
/// CRM (kanban_filters_drawer.dart): seções *flush* separadas por filete
/// tracejado + eyebrow com dot de cor; chips em *tint* (nunca sólido); campos
/// em pill com chip de ícone discreto. Cor usada apenas como sinal.
class WhatsAppFiltersDrawer extends StatefulWidget {
  final WhatsAppInboxFilters initialFilters;
  final ValueChanged<WhatsAppInboxFilters> onApply;
  final VoidCallback onClear;

  const WhatsAppFiltersDrawer({
    super.key,
    required this.initialFilters,
    required this.onApply,
    required this.onClear,
  });

  @override
  State<WhatsAppFiltersDrawer> createState() => _WhatsAppFiltersDrawerState();
}

class _WhatsAppFiltersDrawerState extends State<WhatsAppFiltersDrawer> {
  final _startController = TextEditingController();
  final _endController = TextEditingController();

  late bool _unreadOnly;
  bool? _hasTask;
  WhatsAppMessageType? _messageType;
  DateTime? _startDate;
  DateTime? _endDate;

  /// Tipos oferecidos no filtro (paridade com o select do painel web).
  static const _filterableTypes = [
    WhatsAppMessageType.text,
    WhatsAppMessageType.image,
    WhatsAppMessageType.video,
    WhatsAppMessageType.audio,
    WhatsAppMessageType.document,
    WhatsAppMessageType.location,
    WhatsAppMessageType.contact,
    WhatsAppMessageType.sticker,
  ];

  @override
  void initState() {
    super.initState();
    final f = widget.initialFilters;
    _unreadOnly = f.unreadOnly;
    _hasTask = f.hasTask;
    _messageType = f.messageType;
    _startDate = f.startDate;
    _endDate = f.endDate;
    if (_startDate != null) _startController.text = _fmt(_startDate!);
    if (_endDate != null) _endController.text = _fmt(_endDate!);
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  static String _fmt(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

  WhatsAppInboxFilters _buildFilters() {
    return WhatsAppInboxFilters(
      unreadOnly: _unreadOnly,
      hasTask: _hasTask,
      messageType: _messageType,
      startDate: _startDate,
      endDate: _endDate,
    );
  }

  int get _activeCount => _buildFilters().activeCount;

  Future<void> _pickDate({required bool isStart}) async {
    final initial = (isStart ? _startDate : _endDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2018),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('pt', 'BR'),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        _startController.text = _fmt(picked);
      } else {
        _endDate = picked;
        _endController.text = _fmt(picked);
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
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final cUnread =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final cTask =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final cType =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    final cPeriodo =
        isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final mq = MediaQuery.of(context);
    final activeCount = _activeCount;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
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
                      accent: cUnread,
                      label: 'Leitura',
                      hint: 'Mostre apenas conversas com mensagens não lidas.',
                      first: true,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ChipChoice(
                            label: 'Todas',
                            icon: LucideIcons.inbox,
                            selected: !_unreadOnly,
                            accent: cUnread,
                            onTap: () => setState(() => _unreadOnly = false),
                          ),
                          _ChipChoice(
                            label: 'Só não lidas',
                            icon: LucideIcons.mailCheck,
                            selected: _unreadOnly,
                            accent: cUnread,
                            onTap: () => setState(() => _unreadOnly = true),
                          ),
                        ],
                      ),
                    ),
                    _section(
                      context,
                      accent: cTask,
                      label: 'Negociação no CRM',
                      hint: 'Contatos com ou sem negociação vinculada.',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ChipChoice(
                            label: 'Todas',
                            selected: _hasTask == null,
                            accent: cTask,
                            onTap: () => setState(() => _hasTask = null),
                          ),
                          _ChipChoice(
                            label: 'Com negociação',
                            icon: LucideIcons.clipboardCheck,
                            selected: _hasTask == true,
                            accent: cTask,
                            onTap: () => setState(() => _hasTask = true),
                          ),
                          _ChipChoice(
                            label: 'Sem negociação',
                            icon: LucideIcons.circleDashed,
                            selected: _hasTask == false,
                            accent: cTask,
                            onTap: () => setState(() => _hasTask = false),
                          ),
                        ],
                      ),
                    ),
                    _section(
                      context,
                      accent: cType,
                      label: 'Tipo da última mensagem',
                      hint: 'Filtre por texto, mídia, documento…',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ChipChoice(
                            label: 'Todos',
                            selected: _messageType == null,
                            accent: cType,
                            onTap: () => setState(() => _messageType = null),
                          ),
                          for (final t in _filterableTypes)
                            _ChipChoice(
                              label: t.label,
                              selected: _messageType == t,
                              accent: cType,
                              onTap: () => setState(() => _messageType = t),
                            ),
                        ],
                      ),
                    ),
                    _section(
                      context,
                      accent: cPeriodo,
                      label: 'Período',
                      hint: 'Mensagens recebidas entre as datas.',
                      child: Row(
                        children: [
                          Expanded(
                            child: _dateControl(
                              context,
                              accent: cPeriodo,
                              controller: _startController,
                              placeholder: 'De',
                              onTap: () => _pickDate(isStart: true),
                              onClear: () => setState(() {
                                _startDate = null;
                                _startController.clear();
                              }),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _dateControl(
                              context,
                              accent: cPeriodo,
                              controller: _endController,
                              placeholder: 'Até',
                              onTap: () => _pickDate(isStart: false),
                              onClear: () => setState(() {
                                _endDate = null;
                                _endController.clear();
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
            child: Icon(LucideIcons.listFilter, color: accent, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filtrar conversas',
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

  Color _fieldFill(BuildContext c) => Theme.of(c).brightness == Brightness.dark
      ? AppColors.background.backgroundTertiaryDarkMode
      : AppColors.background.backgroundTertiary;

  Widget _dateControl(
    BuildContext context, {
    required Color accent,
    required TextEditingController controller,
    required String placeholder,
    required VoidCallback onTap,
    required VoidCallback onClear,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filled = controller.text.isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
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
              child: Icon(Icons.calendar_today_outlined,
                  size: 17, color: accent),
            ),
            const SizedBox(width: 10),
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
