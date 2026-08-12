import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/utils/input_formatters.dart';
import '../../../shared/utils/masks.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../clients/services/client_service.dart';
import '../models/kanban_models.dart';
import '../services/kanban_service.dart';

// =============================================================================
// SHEETS DE EDIÇÃO DO CARD (ficha viva da tela de detalhes)
// =============================================================================
//
// Todos os editores da `TaskDetailsPage` moram aqui — a tela já passava de
// 5 mil linhas e cada sheet novo (prioridade, prazo, valor, responsável,
// vínculos, contatos, tags) traz estado próprio. A tela continua dona das
// ESCRITAS: estes sheets só coletam a intenção e devolvem via
// `Navigator.pop`, do mesmo jeito que o `_MoveStageSheet` já fazia.
//
// Anatomia da casa (inegociável): grabber 42×4 · eyebrow + título + fechar ·
// divisor gradient · conteúdo rolável com teto de 85% da tela · rodapé com a
// ação verde. Cancelar NUNCA é vermelho.

/// Verde de confirmar/salvar da casa.
const Color kTaskEditGreen = Color(0xFF059669);

/// Cor estável derivada do nome — cada pessoa tem a sua. Mesma mecânica do
/// avatar da tela de detalhes (hash simples sobre o nome normalizado).
Color taskPersonColor(String? name) {
  if (name == null || name.trim().isEmpty) return const Color(0xFF64748B);
  const palette = [
    Color(0xFF0EA5E9),
    Color(0xFF14B8A6),
    Color(0xFF6366F1),
    Color(0xFFF97316),
    Color(0xFF22C55E),
    Color(0xFFEC4899),
    Color(0xFFA855F7),
    Color(0xFF0891B2),
  ];
  var h = 0;
  for (final c in name.trim().toLowerCase().codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return palette[h % palette.length];
}

String taskInitials(String? name) {
  if (name == null || name.trim().isEmpty) return '?';
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

/// Máscara de exibição do telefone (tira o DDI 55 quando presente).
String taskMaskPhone(String s) {
  var digits = s.replaceAll(RegExp(r'\D'), '');
  if ((digits.length == 12 || digits.length == 13) && digits.startsWith('55')) {
    digits = digits.substring(2);
  }
  if (digits.length < 10) return s.trim();
  return Masks.phone(digits);
}

/// `1.234,56` → `1234.56`. O app não tem um parser central de moeda
/// (o único vive em analytics), então a conversão fica aqui, junto do
/// formatter que a produziu.
double? taskParseCurrency(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  return double.tryParse(t.replaceAll('.', '').replaceAll(',', '.'));
}

/// Pickers nativos SEMPRE com primária verde + 24h (nada de vermelho
/// default nem AM/PM).
Widget taskPickerTheme(BuildContext ctx, Widget? child) {
  return MediaQuery(
    data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
    child: Theme(
      data: Theme.of(ctx).copyWith(
        colorScheme:
            Theme.of(ctx).colorScheme.copyWith(primary: kTaskEditGreen),
      ),
      child: child!,
    ),
  );
}

InputDecoration taskFieldDecoration(
  BuildContext context, {
  String? label,
  String? hint,
  IconData? prefixIcon,
  String? prefixText,
  Color tone = kTaskEditGreen,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final border = ThemeHelpers.borderColor(context);
  final secondary = ThemeHelpers.textSecondaryColor(context);
  OutlineInputBorder shell(Color c, double w) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: w),
      );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: prefixIcon == null
        ? null
        : Icon(prefixIcon, size: 18, color: secondary),
    prefixText: prefixText,
    prefixStyle: TextStyle(
      color: ThemeHelpers.textColor(context),
      fontWeight: FontWeight.w800,
    ),
    filled: true,
    fillColor: border.withValues(alpha: isDark ? 0.16 : 0.1),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    labelStyle: TextStyle(
      color: secondary,
      fontWeight: FontWeight.w700,
      fontSize: 13,
    ),
    floatingLabelStyle: TextStyle(color: tone, fontWeight: FontWeight.w800),
    hintStyle: TextStyle(color: secondary.withValues(alpha: 0.8)),
    border: shell(border.withValues(alpha: 0.5), 1),
    enabledBorder: shell(border.withValues(alpha: 0.5), 1),
    focusedBorder: shell(tone.withValues(alpha: 0.75), 1.5),
    errorBorder: shell(const Color(0xFFDC2626).withValues(alpha: 0.6), 1),
    focusedErrorBorder: shell(const Color(0xFFDC2626), 1.5),
  );
}

// =============================================================================
// CASCA DO SHEET — grabber · eyebrow/título/fechar · divisor · corpo · rodapé
// =============================================================================

class TaskEditSheetShell extends StatelessWidget {
  const TaskEditSheetShell({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.tone,
    required this.child,
    this.footer,
    this.maxHeightFactor = 0.85,
  });

  final String eyebrow;
  final String title;
  final Color tone;

  /// Conteúdo rolável (o shell já o coloca dentro de um `Flexible`).
  final Widget child;

  /// Ação principal do rodapé — o shell cuida da hairline e do safe area.
  final Widget? footer;

  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mq = MediaQuery.of(context);
    final border = ThemeHelpers.borderColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: mq.size.height * maxHeightFactor),
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: ThemeHelpers.cardBackgroundColor(context),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(26)),
              border: Border.all(color: border.withValues(alpha: 0.45)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.14),
                  blurRadius: 44,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  child: Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: border.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 4, 10, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              eyebrow.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.35,
                                color: tone,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.65,
                                height: 1.02,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close_rounded, color: muted),
                        tooltip: 'Fechar',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        tone.withValues(alpha: 0.55),
                        tone.withValues(alpha: 0.08),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                Flexible(child: child),
                if (footer != null)
                  Container(
                    padding: EdgeInsets.fromLTRB(
                      18,
                      12,
                      18,
                      14 + mq.padding.bottom,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: border.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                    child: footer!,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ação principal (verde) do rodapé dos sheets.
class TaskSheetPrimaryButton extends StatelessWidget {
  const TaskSheetPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: kTaskEditGreen,
        foregroundColor: Colors.white,
        disabledBackgroundColor: kTaskEditGreen.withValues(alpha: 0.35),
        disabledForegroundColor: Colors.white.withValues(alpha: 0.75),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 14.5,
          letterSpacing: 0.1,
        ),
      ),
      child: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Colors.white,
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 17),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
    );
  }
}

/// Linha de opção dos sheets: dot/avatar + título + helper + check.
class TaskSheetOptionRow extends StatelessWidget {
  const TaskSheetOptionRow({
    super.key,
    required this.title,
    required this.tone,
    required this.selected,
    required this.onTap,
    this.helper,
    this.leading,
    this.trailing,
  });

  final String title;
  final String? helper;
  final Color tone;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: selected
                ? tone.withValues(alpha: isDark ? 0.14 : 0.08)
                : Colors.transparent,
            border: Border.all(
              color: selected
                  ? tone.withValues(alpha: 0.4)
                  : ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            children: [
              leading ??
                  Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tone,
                      boxShadow: [
                        BoxShadow(
                          color: tone.withValues(alpha: 0.4),
                          blurRadius: 7,
                        ),
                      ],
                    ),
                  ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        letterSpacing: -0.2,
                        height: 1.2,
                      ),
                    ),
                    if (helper != null && helper!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        helper!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: secondary,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              trailing ??
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.arrow_forward_rounded,
                    size: selected ? 20 : 18,
                    color: selected ? tone : secondary,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Estados compartilhados (carregando / vazio / erro) dentro dos sheets.
class TaskSheetStatus extends StatelessWidget {
  const TaskSheetStatus({
    super.key,
    required this.icon,
    required this.message,
    this.tone,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final Color? tone;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final c = tone ?? secondary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 30, color: c),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: secondary,
              fontWeight: FontWeight.w700,
              height: 1.4,
              fontSize: 13,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Tentar novamente'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SheetLoader extends StatelessWidget {
  const _SheetLoader({required this.tone});

  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44),
      child: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.6, color: tone),
        ),
      ),
    );
  }
}

// =============================================================================
// PRIORIDADE
// =============================================================================

/// Chips de prioridade com a COR REAL de cada uma (a mesma que o backend
/// manda e que o card usa). Escolha de um toque — sem rodapé.
class TaskPrioritySheet extends StatelessWidget {
  const TaskPrioritySheet({super.key, required this.current});

  final KanbanPriority? current;

  static Future<KanbanPriority?> show(
    BuildContext context, {
    KanbanPriority? current,
  }) {
    return showModalBottomSheet<KanbanPriority>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => TaskPrioritySheet(current: current),
    );
  }

  static Color colorOf(KanbanPriority p) =>
      Color(int.parse(p.color.replaceFirst('#', '0xFF')));

  static String helperOf(KanbanPriority p) {
    switch (p) {
      case KanbanPriority.low:
        return 'Pode esperar — sem pressão de tempo';
      case KanbanPriority.medium:
        return 'Ritmo normal de atendimento';
      case KanbanPriority.high:
        return 'Precisa de atenção nos próximos dias';
      case KanbanPriority.urgent:
        return 'Trate hoje — risco de perder o lead';
    }
  }

  @override
  Widget build(BuildContext context) {
    return TaskEditSheetShell(
      eyebrow: 'Prioridade',
      title: 'Qual o peso deste lead?',
      tone: const Color(0xFFF59E0B),
      maxHeightFactor: 0.72,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          14,
          12,
          14,
          16 + MediaQuery.of(context).padding.bottom,
        ),
        physics: const BouncingScrollPhysics(),
        shrinkWrap: true,
        children: [
          for (final p in KanbanPriority.values) ...[
            TaskSheetOptionRow(
              title: p.label,
              helper: helperOf(p),
              tone: colorOf(p),
              selected: p == current,
              onTap: () => Navigator.of(context).pop(p),
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// PRAZO
// =============================================================================

/// Resultado do sheet de prazo: uma data nova ou a remoção do prazo.
class TaskDeadlineChoice {
  const TaskDeadlineChoice.date(this.date) : clear = false;
  const TaskDeadlineChoice.clear()
      : date = null,
        clear = true;

  final DateTime? date;
  final bool clear;
}

class TaskDeadlineSheet extends StatelessWidget {
  const TaskDeadlineSheet({super.key, required this.current});

  final DateTime? current;

  static const Color tone = Color(0xFF0891B2);

  static Future<TaskDeadlineChoice?> show(
    BuildContext context, {
    DateTime? current,
  }) {
    return showModalBottomSheet<TaskDeadlineChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => TaskDeadlineSheet(current: current),
    );
  }

  static DateTime _atNoon(DateTime d) => DateTime(d.year, d.month, d.day, 12);

  Future<void> _openCalendar(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 3)),
      locale: const Locale('pt', 'BR'),
      helpText: 'Prazo do lead',
      cancelText: 'Cancelar',
      confirmText: 'Definir',
      builder: taskPickerTheme,
    );
    if (picked == null || !context.mounted) return;
    Navigator.of(context).pop(TaskDeadlineChoice.date(_atNoon(picked)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final fmt = DateFormat("EEEE, d 'de' MMMM", 'pt_BR');

    final atalhos = <(String, DateTime)>[
      ('Hoje', today),
      ('Amanhã', today.add(const Duration(days: 1))),
      ('Em 3 dias', today.add(const Duration(days: 3))),
      ('Em 1 semana', today.add(const Duration(days: 7))),
      ('Em 15 dias', today.add(const Duration(days: 15))),
    ];

    return TaskEditSheetShell(
      eyebrow: 'Prazo',
      title: 'Quando este lead vence?',
      tone: tone,
      maxHeightFactor: 0.78,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          18 + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.event_rounded, size: 15, color: secondary),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    current == null
                        ? 'Sem prazo definido'
                        : 'Hoje: ${fmt.format(current!.toLocal())}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: secondary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in atalhos)
                  _DeadlineChip(
                    label: a.$1,
                    helper: DateFormat('d MMM', 'pt_BR').format(a.$2),
                    onTap: () => Navigator.of(context)
                        .pop(TaskDeadlineChoice.date(_atNoon(a.$2))),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            TaskSheetOptionRow(
              title: 'Escolher no calendário',
              helper: 'Data específica',
              tone: tone,
              selected: false,
              leading: Icon(Icons.calendar_month_rounded, size: 20, color: tone),
              onTap: () => _openCalendar(context),
            ),
            if (current != null) ...[
              const SizedBox(height: 8),
              TaskSheetOptionRow(
                title: 'Remover prazo',
                helper: 'O lead fica sem data de vencimento',
                tone: secondary,
                selected: false,
                leading: Icon(
                  Icons.event_busy_rounded,
                  size: 20,
                  color: secondary,
                ),
                trailing: Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: secondary,
                ),
                onTap: () =>
                    Navigator.of(context).pop(const TaskDeadlineChoice.clear()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeadlineChip extends StatelessWidget {
  const _DeadlineChip({
    required this.label,
    required this.helper,
    required this.onTap,
  });

  final String label;
  final String helper;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    const tone = TaskDeadlineSheet.tone;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: tone.withValues(alpha: isDark ? 0.14 : 0.08),
            border: Border.all(color: tone.withValues(alpha: 0.32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  height: 1,
                  color: tone,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                helper,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  height: 1,
                  color: secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// VALOR DA NEGOCIAÇÃO
// =============================================================================

class TaskValueSheet extends StatefulWidget {
  const TaskValueSheet({super.key, required this.current});

  final double? current;

  static Future<double?> show(BuildContext context, {double? current}) {
    return showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => TaskValueSheet(current: current),
    );
  }

  @override
  State<TaskValueSheet> createState() => _TaskValueSheetState();
}

class _TaskValueSheetState extends State<TaskValueSheet> {
  late final TextEditingController _controller;
  bool _valid = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.current == null
          ? ''
          : CurrencyInputFormatter.format(widget.current),
    );
    _valid = taskParseCurrency(_controller.text) != null;
    _controller.addListener(() {
      final ok = taskParseCurrency(_controller.text) != null;
      if (ok != _valid && mounted) setState(() => _valid = ok);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = taskParseCurrency(_controller.text);
    if (v == null) return;
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return TaskEditSheetShell(
      eyebrow: 'Valor',
      title: 'Potencial da negociação',
      tone: kTaskEditGreen,
      maxHeightFactor: 0.6,
      footer: TaskSheetPrimaryButton(
        label: 'Salvar valor',
        icon: Icons.check_rounded,
        onPressed: _valid ? _submit : null,
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [CurrencyInputFormatter()],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (_valid) _submit();
              },
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.6,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              decoration: taskFieldDecoration(
                context,
                label: 'Valor estimado',
                hint: '0,00',
                prefixText: 'R\$ ',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 13, color: secondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Entra no VGV do funil e nos relatórios. Para zerar, '
                    'informe 0,00.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// RESPONSÁVEL
// =============================================================================

class TaskAssigneeSheet extends StatefulWidget {
  const TaskAssigneeSheet({
    super.key,
    required this.projectId,
    required this.currentUserId,
  });

  final String projectId;
  final String? currentUserId;

  static Future<KanbanUser?> show(
    BuildContext context, {
    required String projectId,
    String? currentUserId,
  }) {
    return showModalBottomSheet<KanbanUser>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => TaskAssigneeSheet(
        projectId: projectId,
        currentUserId: currentUserId,
      ),
    );
  }

  @override
  State<TaskAssigneeSheet> createState() => _TaskAssigneeSheetState();
}

class _TaskAssigneeSheetState extends State<TaskAssigneeSheet> {
  static const Color _tone = Color(0xFF8B5CF6);

  final TextEditingController _search = TextEditingController();
  List<ProjectMember> _members = const [];
  bool _loading = true;
  String? _error;
  // Guardar o código HTTP é o que separa "você não tem acesso a este funil"
  // (403) de "o servidor caiu" (5xx) — antes os dois caíam no mesmo aviso.
  int _errorStatus = 0;
  Object? _errorDetail;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      if (mounted) setState(() => _query = _search.text.trim().toLowerCase());
    });
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _errorStatus = 0;
      _errorDetail = null;
    });
    final r = await KanbanService.instance.getProjectMembers(widget.projectId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.success && r.data != null) {
        _members = r.data!;
        _error = null;
        _errorStatus = 0;
        _errorDetail = null;
      } else {
        _error = r.message ?? 'Não foi possível carregar a equipe do funil.';
        _errorStatus = r.statusCode;
        _errorDetail = r.error;
      }
    });
  }

  List<ProjectMember> get _filtered {
    if (_query.isEmpty) return _members;
    return _members.where((m) {
      final n = m.user.name.toLowerCase();
      final e = m.user.email.toLowerCase();
      return n.contains(_query) || e.contains(_query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final visible = _filtered;

    return TaskEditSheetShell(
      eyebrow: 'Responsável',
      title: 'Quem cuida deste lead?',
      tone: _tone,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: taskFieldDecoration(
                context,
                hint: 'Buscar por nome ou e-mail',
                prefixIcon: Icons.search_rounded,
                tone: _tone,
              ),
            ),
          ),
          Flexible(
            child: _loading
                ? const _SheetLoader(tone: _tone)
                : _error != null
                    ? SingleChildScrollView(
                        child: AppErrorState.fromApi(
                          message: _error,
                          statusCode: _errorStatus,
                          error: _errorDetail,
                          dense: true,
                          onRetry: _load,
                        ),
                      )
                    : visible.isEmpty
                        ? const TaskSheetStatus(
                            icon: Icons.person_search_rounded,
                            message: 'Nenhuma pessoa encontrada no funil.',
                          )
                        : ListView.separated(
                            padding: EdgeInsets.fromLTRB(
                              14,
                              8,
                              14,
                              16 + mq.padding.bottom,
                            ),
                            physics: const BouncingScrollPhysics(),
                            shrinkWrap: true,
                            itemCount: visible.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, i) {
                              final m = visible[i];
                              final tone = taskPersonColor(m.user.name);
                              return TaskSheetOptionRow(
                                title: m.user.name,
                                helper: m.role == 'leader'
                                    ? 'Líder do funil · ${m.user.email}'
                                    : m.user.email,
                                tone: tone,
                                selected: m.user.id == widget.currentUserId,
                                leading: TaskInitialAvatar(
                                  name: m.user.name,
                                  size: 34,
                                ),
                                onTap: () =>
                                    Navigator.of(context).pop(m.user),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

/// Avatar-inicial em cor estável por nome.
class TaskInitialAvatar extends StatelessWidget {
  const TaskInitialAvatar({super.key, required this.name, this.size = 34});

  final String? name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tone = taskPersonColor(name);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: tone),
      alignment: Alignment.center,
      child: Text(
        taskInitials(name),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: size * 0.4,
          height: 1,
        ),
      ),
    );
  }
}

// =============================================================================
// VÍNCULOS — cliente e imóvel
// =============================================================================

/// O que o seletor devolve: id + rótulo já resolvido (a tela não tem como
/// buscar o nome depois — a API do card não devolve o imóvel vinculado).
class TaskLinkSelection {
  const TaskLinkSelection({required this.id, required this.label});

  final String id;
  final String label;
}

enum TaskLinkKind { client, property }

class TaskLinkPickerSheet extends StatefulWidget {
  const TaskLinkPickerSheet({
    super.key,
    required this.kind,
    required this.projectId,
    this.currentId,
    this.suggestedName,
    this.suggestedPhone,
  });

  final TaskLinkKind kind;
  final String projectId;
  final String? currentId;

  /// Contato avulso do lead — habilita o atalho "Cadastrar como cliente".
  final String? suggestedName;
  final String? suggestedPhone;

  static Future<TaskLinkSelection?> show(
    BuildContext context, {
    required TaskLinkKind kind,
    required String projectId,
    String? currentId,
    String? suggestedName,
    String? suggestedPhone,
  }) {
    return showModalBottomSheet<TaskLinkSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => TaskLinkPickerSheet(
        kind: kind,
        projectId: projectId,
        currentId: currentId,
        suggestedName: suggestedName,
        suggestedPhone: suggestedPhone,
      ),
    );
  }

  @override
  State<TaskLinkPickerSheet> createState() => _TaskLinkPickerSheetState();
}

class _TaskLinkPickerSheetState extends State<TaskLinkPickerSheet> {
  static const Color _tone = Color(0xFF0EA5E9);

  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  String? _error;
  // Código HTTP junto: sem ele, "sem permissão na carteira de clientes" e
  // "servidor fora do ar" chegam idênticos na busca.
  int _errorStatus = 0;
  Object? _errorDetail;
  List<TaskLinkSelection> _items = const [];
  List<String?> _helpers = const [];

  bool get _isClient => widget.kind == TaskLinkKind.client;

  bool get _canQuickCreate =>
      _isClient &&
      (widget.suggestedPhone?.replaceAll(RegExp(r'\D'), '').length ?? 0) >= 10;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 380), _load);
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _errorStatus = 0;
      _errorDetail = null;
    });
    final term = _search.text.trim();
    final search = term.isEmpty ? null : term;

    if (_isClient) {
      final r = await KanbanService.instance
          .getProjectClients(widget.projectId, search: search);
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (r.success && r.data != null) {
          _items = [
            for (final c in r.data!)
              TaskLinkSelection(id: c.id, label: c.name),
          ];
          _helpers = [
            for (final c in r.data!)
              [
                if ((c.phone ?? '').trim().isNotEmpty)
                  taskMaskPhone(c.phone!.trim()),
                if ((c.email ?? '').trim().isNotEmpty) c.email!.trim(),
              ].join(' · '),
          ];
          _error = null;
          _errorStatus = 0;
          _errorDetail = null;
        } else {
          _error = r.message ?? 'Não foi possível carregar os clientes.';
          _errorStatus = r.statusCode;
          _errorDetail = r.error;
        }
      });
      return;
    }

    final r = await KanbanService.instance
        .getProjectProperties(widget.projectId, search: search);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.success && r.data != null) {
        _items = [
          for (final p in r.data!)
            TaskLinkSelection(id: p.id, label: p.title),
        ];
        _helpers = [
          for (final p in r.data!)
            [
              if ((p.code ?? '').trim().isNotEmpty) 'Cód. ${p.code!.trim()}',
              if ((p.city ?? '').trim().isNotEmpty) p.city!.trim(),
            ].join(' · '),
        ];
        _error = null;
        _errorStatus = 0;
        _errorDetail = null;
      } else {
        _error = r.message ?? 'Não foi possível carregar os imóveis.';
        _errorStatus = r.statusCode;
        _errorDetail = r.error;
      }
    });
  }

  Future<void> _quickCreate() async {
    final created = await TaskQuickClientSheet.show(
      context,
      name: widget.suggestedName,
      phone: widget.suggestedPhone,
    );
    if (created == null || !mounted) return;
    Navigator.of(context).pop(created);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return TaskEditSheetShell(
      eyebrow: _isClient ? 'Cliente' : 'Imóvel',
      title: _isClient ? 'Vincular cliente' : 'Vincular imóvel',
      tone: _tone,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: taskFieldDecoration(
                context,
                hint: _isClient
                    ? 'Buscar cliente por nome'
                    : 'Buscar por título, código ou cidade',
                prefixIcon: Icons.search_rounded,
                tone: _tone,
              ),
            ),
          ),
          if (_canQuickCreate)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
              child: TaskSheetOptionRow(
                title: 'Cadastrar como cliente',
                helper:
                    '${widget.suggestedName?.trim().isNotEmpty == true ? widget.suggestedName!.trim() : 'Contato do lead'} · ${taskMaskPhone(widget.suggestedPhone!)}',
                tone: kTaskEditGreen,
                selected: false,
                leading: const Icon(
                  Icons.person_add_alt_1_rounded,
                  size: 20,
                  color: kTaskEditGreen,
                ),
                onTap: _quickCreate,
              ),
            ),
          Flexible(
            child: _loading
                ? const _SheetLoader(tone: _tone)
                : _error != null
                    ? SingleChildScrollView(
                        child: AppErrorState.fromApi(
                          message: _error,
                          statusCode: _errorStatus,
                          error: _errorDetail,
                          dense: true,
                          onRetry: _load,
                        ),
                      )
                    : _items.isEmpty
                        ? TaskSheetStatus(
                            icon: _isClient
                                ? Icons.person_search_rounded
                                : Icons.home_work_outlined,
                            message: _isClient
                                ? 'Nenhum cliente encontrado neste funil.'
                                : 'Nenhum imóvel encontrado neste funil.',
                          )
                        : ListView.separated(
                            padding: EdgeInsets.fromLTRB(
                              14,
                              8,
                              14,
                              16 + mq.padding.bottom,
                            ),
                            physics: const BouncingScrollPhysics(),
                            shrinkWrap: true,
                            itemCount: _items.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, i) {
                              final item = _items[i];
                              final helper =
                                  i < _helpers.length ? _helpers[i] : null;
                              return TaskSheetOptionRow(
                                title: item.label,
                                helper: (helper == null || helper.isEmpty)
                                    ? null
                                    : helper,
                                tone: _tone,
                                selected: item.id == widget.currentId,
                                leading: _isClient
                                    ? TaskInitialAvatar(
                                        name: item.label,
                                        size: 34,
                                      )
                                    : Icon(
                                        Icons.home_work_rounded,
                                        size: 20,
                                        color: _tone,
                                      ),
                                onTap: () =>
                                    Navigator.of(context).pop(item),
                              );
                            },
                          ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12 + mq.padding.bottom),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded, size: 12, color: secondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'É possível trocar o vínculo, mas não removê-lo por aqui.',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                      color: secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Cadastro-relâmpago de cliente a partir do contato avulso do lead.
class TaskQuickClientSheet extends StatefulWidget {
  const TaskQuickClientSheet({super.key, this.name, this.phone});

  final String? name;
  final String? phone;

  static Future<TaskLinkSelection?> show(
    BuildContext context, {
    String? name,
    String? phone,
  }) {
    return showModalBottomSheet<TaskLinkSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => TaskQuickClientSheet(name: name, phone: phone),
    );
  }

  @override
  State<TaskQuickClientSheet> createState() => _TaskQuickClientSheetState();
}

class _TaskQuickClientSheetState extends State<TaskQuickClientSheet> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.name?.trim() ?? '');
    final digits = (widget.phone ?? '').replaceAll(RegExp(r'\D'), '');
    final local = (digits.length == 12 || digits.length == 13) &&
            digits.startsWith('55')
        ? digits.substring(2)
        : digits;
    _phone = TextEditingController(
      text: local.length >= 10 ? Masks.phone(local) : local,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (name.length < 3) {
      setState(() => _error = 'Informe o nome completo (mínimo 3 letras).');
      return;
    }
    if (digits.length < 10) {
      setState(() => _error = 'Informe um telefone com DDD.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final r = await ClientService.instance
        .createQuickClient(name: name, phone: digits);
    if (!mounted) return;
    if (r.success && r.data != null && r.data!.isNotEmpty) {
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(TaskLinkSelection(id: r.data!, label: name));
      return;
    }
    setState(() {
      _saving = false;
      _error = r.message ?? 'Não foi possível cadastrar o cliente.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return TaskEditSheetShell(
      eyebrow: 'Novo cliente',
      title: 'Cadastrar e vincular',
      tone: kTaskEditGreen,
      maxHeightFactor: 0.7,
      footer: TaskSheetPrimaryButton(
        label: 'Cadastrar e vincular',
        icon: Icons.person_add_alt_1_rounded,
        loading: _saving,
        onPressed: _save,
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: taskFieldDecoration(
                context,
                label: 'Nome do cliente',
                prefixIcon: Icons.person_outline_rounded,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [PhoneInputFormatter()],
              decoration: taskFieldDecoration(
                context,
                label: 'Telefone',
                prefixIcon: Icons.phone_rounded,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 14,
                    color: Color(0xFFDC2626),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFDC2626),
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 13, color: secondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'O cliente entra na sua carteira e já fica vinculado a '
                    'esta negociação.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// CONTATOS DO LEAD
// =============================================================================

/// Gerência da lista de contatos do card. Trabalha numa CÓPIA local e só
/// devolve a lista final no rodapé — nada é gravado enquanto a pessoa
/// mexe, então excluir sem querer não custa nada.
class TaskContactsSheet extends StatefulWidget {
  const TaskContactsSheet({super.key, required this.contacts});

  final List<KanbanTaskContactInput> contacts;

  static Future<List<KanbanTaskContactInput>?> show(
    BuildContext context, {
    required List<KanbanTaskContactInput> contacts,
  }) {
    return showModalBottomSheet<List<KanbanTaskContactInput>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => TaskContactsSheet(contacts: contacts),
    );
  }

  @override
  State<TaskContactsSheet> createState() => _TaskContactsSheetState();
}

class _TaskContactsSheetState extends State<TaskContactsSheet> {
  static const Color _tone = Color(0xFF059669);

  late List<KanbanTaskContactInput> _list;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _list = [
      for (final c in widget.contacts)
        KanbanTaskContactInput(
          name: c.name,
          phone: c.phone,
          email: c.email,
          jobTitle: c.jobTitle,
          birthDate: c.birthDate,
        ),
    ];
  }

  Future<void> _edit({int? index}) async {
    final result = await TaskContactFormSheet.show(
      context,
      contact: index == null ? null : _list[index],
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        _list.add(result);
      } else {
        _list[index] = result;
      }
      _dirty = true;
    });
  }

  void _remove(int index) {
    setState(() {
      _list.removeAt(index);
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return TaskEditSheetShell(
      eyebrow: 'Lead',
      title: 'Contatos da negociação',
      tone: _tone,
      footer: TaskSheetPrimaryButton(
        label: 'Salvar contatos',
        icon: Icons.check_rounded,
        onPressed: _dirty ? () => Navigator.of(context).pop(_list) : null,
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        physics: const BouncingScrollPhysics(),
        shrinkWrap: true,
        children: [
          if (_list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Row(
                children: [
                  Icon(
                    Icons.contacts_outlined,
                    size: 16,
                    color: secondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Nenhum contato cadastrado neste lead.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        fontWeight: FontWeight.w600,
                        fontStyle: FontStyle.italic,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            for (var i = 0; i < _list.length; i++) ...[
              _ContactManagerRow(
                contact: _list[i],
                onEdit: () => _edit(index: i),
                onRemove: () => _remove(i),
              ),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 4),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _edit(),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _tone.withValues(alpha: 0.42),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.person_add_alt_1_rounded,
                      size: 18,
                      color: _tone,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Adicionar contato',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: _tone,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 12, color: secondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'As mudanças só valem depois de salvar.',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                    color: secondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContactManagerRow extends StatelessWidget {
  const _ContactManagerRow({
    required this.contact,
    required this.onEdit,
    required this.onRemove,
  });

  final KanbanTaskContactInput contact;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final name = contact.name?.trim();
    final phone = contact.phone?.trim();
    final email = contact.email?.trim();
    final role = contact.jobTitle?.trim();

    final subtitle = [
      if (phone != null && phone.isNotEmpty) taskMaskPhone(phone),
      if (email != null && email.isNotEmpty) email,
      if (role != null && role.isNotEmpty) role,
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          TaskInitialAvatar(name: name, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  (name != null && name.isNotEmpty) ? name : 'Contato sem nome',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                    height: 1.2,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: secondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onEdit,
            icon: Icon(Icons.edit_rounded, size: 18, color: secondary),
            tooltip: 'Editar contato',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: Color(0xFFDC2626),
            ),
            tooltip: 'Excluir contato',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class TaskContactFormSheet extends StatefulWidget {
  const TaskContactFormSheet({super.key, this.contact});

  final KanbanTaskContactInput? contact;

  static Future<KanbanTaskContactInput?> show(
    BuildContext context, {
    KanbanTaskContactInput? contact,
  }) {
    return showModalBottomSheet<KanbanTaskContactInput>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => TaskContactFormSheet(contact: contact),
    );
  }

  @override
  State<TaskContactFormSheet> createState() => _TaskContactFormSheetState();
}

class _TaskContactFormSheetState extends State<TaskContactFormSheet> {
  static const Color _tone = Color(0xFF059669);

  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _role;
  String? _error;

  @override
  void initState() {
    super.initState();
    final c = widget.contact;
    _name = TextEditingController(text: c?.name?.trim() ?? '');
    final digits = (c?.phone ?? '').replaceAll(RegExp(r'\D'), '');
    final local = (digits.length == 12 || digits.length == 13) &&
            digits.startsWith('55')
        ? digits.substring(2)
        : digits;
    _phone = TextEditingController(
      text: local.length >= 10 ? Masks.phone(local) : local,
    );
    _email = TextEditingController(text: c?.email?.trim() ?? '');
    _role = TextEditingController(text: c?.jobTitle?.trim() ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _role.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    final email = _email.text.trim();
    if (name.isEmpty && digits.isEmpty) {
      setState(() => _error = 'Informe ao menos o nome ou o telefone.');
      return;
    }
    if (digits.isNotEmpty && digits.length < 10) {
      setState(() => _error = 'Telefone incompleto — inclua o DDD.');
      return;
    }
    if (email.isNotEmpty && !email.contains('@')) {
      setState(() => _error = 'E-mail inválido.');
      return;
    }
    Navigator.of(context).pop(
      KanbanTaskContactInput(
        name: name.isEmpty ? null : name,
        phone: digits.isEmpty ? null : digits,
        email: email.isEmpty ? null : email,
        jobTitle: _role.text.trim().isEmpty ? null : _role.text.trim(),
        birthDate: widget.contact?.birthDate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = widget.contact != null;

    return TaskEditSheetShell(
      eyebrow: editing ? 'Editar contato' : 'Novo contato',
      title: editing ? 'Dados do contato' : 'Adicionar contato',
      tone: _tone,
      maxHeightFactor: 0.8,
      footer: TaskSheetPrimaryButton(
        label: editing ? 'Salvar contato' : 'Adicionar',
        icon: Icons.check_rounded,
        onPressed: _submit,
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: taskFieldDecoration(
                context,
                label: 'Nome',
                prefixIcon: Icons.person_outline_rounded,
                tone: _tone,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [PhoneInputFormatter()],
              decoration: taskFieldDecoration(
                context,
                label: 'Telefone',
                prefixIcon: Icons.phone_rounded,
                tone: _tone,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: taskFieldDecoration(
                context,
                label: 'E-mail',
                prefixIcon: Icons.mail_outline_rounded,
                tone: _tone,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _role,
              textCapitalization: TextCapitalization.sentences,
              decoration: taskFieldDecoration(
                context,
                label: 'Cargo / relação',
                hint: 'Ex.: esposa, sócio, procurador',
                prefixIcon: Icons.badge_outlined,
                tone: _tone,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 14,
                    color: Color(0xFFDC2626),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFDC2626),
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// TAGS
// =============================================================================

class TaskTagsSheet extends StatefulWidget {
  const TaskTagsSheet({
    super.key,
    required this.teamId,
    required this.selected,
  });

  final String? teamId;
  final List<String> selected;

  static Future<List<String>?> show(
    BuildContext context, {
    String? teamId,
    required List<String> selected,
  }) {
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => TaskTagsSheet(teamId: teamId, selected: selected),
    );
  }

  @override
  State<TaskTagsSheet> createState() => _TaskTagsSheetState();
}

class _TaskTagsSheetState extends State<TaskTagsSheet> {
  static const Color _tone = Color(0xFFD97706);

  final TextEditingController _input = TextEditingController();
  late List<String> _selected;
  List<String> _available = const [];
  bool _loading = true;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _selected = [...widget.selected];
    _input.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final teamId = widget.teamId;
    if (teamId == null || teamId.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final r = await KanbanService.instance.listTags(teamId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.success && r.data != null) _available = r.data!;
    });
  }

  void _toggle(String tag) {
    setState(() {
      if (_selected.any((t) => t.toLowerCase() == tag.toLowerCase())) {
        _selected.removeWhere((t) => t.toLowerCase() == tag.toLowerCase());
      } else {
        _selected.add(tag);
      }
      _dirty = true;
    });
  }

  void _addTyped() {
    final t = _input.text.trim();
    if (t.isEmpty) return;
    if (!_selected.any((s) => s.toLowerCase() == t.toLowerCase())) {
      setState(() {
        _selected.add(t);
        _dirty = true;
      });
    }
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final sugestoes = _available
        .where(
          (t) => !_selected.any((s) => s.toLowerCase() == t.toLowerCase()),
        )
        .toList();

    return TaskEditSheetShell(
      eyebrow: 'Categorias',
      title: 'Tags do card',
      tone: _tone,
      footer: TaskSheetPrimaryButton(
        label: 'Salvar tags',
        icon: Icons.check_rounded,
        onPressed: _dirty ? () => Navigator.of(context).pop(_selected) : null,
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'NO CARD',
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1.6,
                fontWeight: FontWeight.w900,
                color: secondary,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 10),
            if (_selected.isEmpty)
              Text(
                'Nenhuma tag no card.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: secondary,
                  fontWeight: FontWeight.w600,
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in _selected)
                    TaskTagChip(
                      label: t,
                      selected: true,
                      onTap: () => _toggle(t),
                    ),
                ],
              ),
            const SizedBox(height: 20),
            TextField(
              controller: _input,
              textCapitalization: TextCapitalization.none,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _addTyped(),
              decoration: taskFieldDecoration(
                context,
                label: 'Nova tag',
                hint: 'Ex.: financiamento',
                prefixIcon: Icons.sell_outlined,
                tone: _tone,
              ).copyWith(
                suffixIcon: IconButton(
                  onPressed: _input.text.trim().isEmpty ? null : _addTyped,
                  icon: Icon(
                    Icons.add_circle_rounded,
                    color: _input.text.trim().isEmpty ? secondary : _tone,
                  ),
                  tooltip: 'Adicionar tag',
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'JÁ USADAS NA EQUIPE',
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1.6,
                fontWeight: FontWeight.w900,
                color: secondary,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 10),
            if (_loading)
              const _SheetLoader(tone: _tone)
            else if (sugestoes.isEmpty)
              Text(
                'Sem outras tags por aqui.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: secondary,
                  fontWeight: FontWeight.w600,
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in sugestoes)
                    TaskTagChip(
                      label: t,
                      selected: false,
                      onTap: () => _toggle(t),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Chip de tag do seletor — selecionado mostra × (remove), disponível
/// mostra + (adiciona). Cor estável por nome, igual à da ficha.
class TaskTagChip extends StatelessWidget {
  const TaskTagChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  static Color colorOf(String tag) {
    const palette = [
      Color(0xFF0EA5E9),
      Color(0xFF14B8A6),
      Color(0xFF6366F1),
      Color(0xFFF97316),
      Color(0xFF22C55E),
      Color(0xFFEC4899),
      Color(0xFFA855F7),
    ];
    if (tag.isEmpty) return palette.first;
    var h = 0;
    for (final c in tag.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return palette[h % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = colorOf(label);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: selected
                ? color.withValues(alpha: isDark ? 0.18 : 0.12)
                : Colors.transparent,
            border: Border.all(
              color: color.withValues(alpha: selected ? 0.45 : 0.28),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                ),
              ),
              const SizedBox(width: 7),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color,
                    fontSize: 11.5,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                selected ? Icons.close_rounded : Icons.add_rounded,
                size: 14,
                color: color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// AÇÕES DO CARD (menu ⋯ do chrome)
// =============================================================================

enum TaskCardAction { delete }

class TaskCardActionsSheet extends StatelessWidget {
  const TaskCardActionsSheet({super.key, required this.canDelete});

  final bool canDelete;

  static Future<TaskCardAction?> show(
    BuildContext context, {
    required bool canDelete,
  }) {
    return showModalBottomSheet<TaskCardAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => TaskCardActionsSheet(canDelete: canDelete),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    const danger = Color(0xFFDC2626);

    return TaskEditSheetShell(
      eyebrow: 'Card',
      title: 'Mais ações',
      tone: const Color(0xFF64748B),
      maxHeightFactor: 0.5,
      child: ListView(
        padding: EdgeInsets.fromLTRB(14, 14, 14, 16 + mq.padding.bottom),
        physics: const BouncingScrollPhysics(),
        shrinkWrap: true,
        children: [
          if (!canDelete)
            const TaskSheetStatus(
              icon: Icons.lock_outline_rounded,
              message: 'Você não tem permissão para excluir este card.',
            )
          else
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () =>
                    Navigator.of(context).pop(TaskCardAction.delete),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: danger.withValues(alpha: 0.38),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.delete_outline_rounded,
                        size: 20,
                        color: danger,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Excluir card',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: danger,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Remove a negociação do funil. Não dá para '
                              'desfazer.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: secondary,
                                height: 1.3,
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
    );
  }
}

// =============================================================================
// PESSOAS — seleção múltipla (envolvidos do card · convidados da agenda)
// =============================================================================

/// Multi-seleção de pessoas da empresa, reaproveitada por DOIS donos:
/// as **pessoas envolvidas** no card (`PUT /kanban/tasks/:id/involved-users`)
/// e os **convidados** de um compromisso criado a partir do card.
///
/// Coerência ≠ uniformidade: a casca e a mecânica são as mesmas, mas quem
/// chama define eyebrow, título, tom e rótulo do rodapé — cada uso continua
/// falando na cor da sua seção.
class TaskPeopleMultiSelectSheet extends StatefulWidget {
  const TaskPeopleMultiSelectSheet({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.tone,
    required this.confirmLabel,
    this.initialSelected = const [],
    this.preloaded,
    this.excludeUserId,
    this.emptyHint = 'Nenhuma pessoa selecionada ainda.',
    this.maxSelections = 50,
  });

  final String eyebrow;
  final String title;
  final Color tone;
  final String confirmLabel;
  final List<KanbanUser> initialSelected;

  /// Lista já carregada pela tela (evita uma segunda ida à rede). Nulo faz o
  /// sheet buscar sozinho.
  final List<KanbanUser>? preloaded;

  /// Normalmente o próprio usuário (não se convida / não se auto-menciona).
  final String? excludeUserId;

  final String emptyHint;

  /// Teto do web (`InvolvedUsersManager`, `maxSelections = 50`).
  final int maxSelections;

  static Future<List<KanbanUser>?> show(
    BuildContext context, {
    required String eyebrow,
    required String title,
    required Color tone,
    required String confirmLabel,
    List<KanbanUser> initialSelected = const [],
    List<KanbanUser>? preloaded,
    String? excludeUserId,
    String emptyHint = 'Nenhuma pessoa selecionada ainda.',
    int maxSelections = 50,
  }) {
    return showModalBottomSheet<List<KanbanUser>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => TaskPeopleMultiSelectSheet(
        eyebrow: eyebrow,
        title: title,
        tone: tone,
        confirmLabel: confirmLabel,
        initialSelected: initialSelected,
        preloaded: preloaded,
        excludeUserId: excludeUserId,
        emptyHint: emptyHint,
        maxSelections: maxSelections,
      ),
    );
  }

  @override
  State<TaskPeopleMultiSelectSheet> createState() =>
      _TaskPeopleMultiSelectSheetState();
}

class _TaskPeopleMultiSelectSheetState
    extends State<TaskPeopleMultiSelectSheet> {
  final TextEditingController _search = TextEditingController();

  List<KanbanUser> _members = const [];
  final List<KanbanUser> _selected = [];
  bool _loading = true;
  String? _error;
  // Idem: o código HTTP é o que diferencia falta de permissão na lista de
  // pessoas da empresa de uma indisponibilidade do servidor.
  int _errorStatus = 0;
  Object? _errorDetail;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.initialSelected);
    _search.addListener(() {
      if (mounted) setState(() => _query = _normalize(_search.text));
    });
    final pre = widget.preloaded;
    if (pre != null && pre.isNotEmpty) {
      _members = pre;
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static String _normalize(String v) => v.trim().toLowerCase();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _errorStatus = 0;
      _errorDetail = null;
    });
    final r = await KanbanService.instance.getCompanyMembersSimple();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.success && r.data != null) {
        _members = r.data!;
        _error = null;
        _errorStatus = 0;
        _errorDetail = null;
      } else {
        _error = r.message ?? 'Não foi possível carregar as pessoas.';
        _errorStatus = r.statusCode;
        _errorDetail = r.error;
      }
    });
  }

  bool _isSelected(KanbanUser u) => _selected.any((s) => s.id == u.id);

  void _toggle(KanbanUser u) {
    setState(() {
      final i = _selected.indexWhere((s) => s.id == u.id);
      if (i >= 0) {
        _selected.removeAt(i);
      } else {
        if (_selected.length >= widget.maxSelections) return;
        _selected.add(u);
      }
    });
  }

  List<KanbanUser> get _filtered {
    final exclude = widget.excludeUserId;
    return _members.where((m) {
      if (exclude != null && m.id == exclude) return false;
      if (_query.isEmpty) return true;
      return _normalize(m.name).contains(_query) ||
          _normalize(m.email).contains(_query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final visible = _filtered;
    final full = _selected.length >= widget.maxSelections;

    return TaskEditSheetShell(
      eyebrow: widget.eyebrow,
      title: widget.title,
      tone: widget.tone,
      footer: TaskSheetPrimaryButton(
        label: widget.confirmLabel,
        icon: Icons.check_rounded,
        onPressed: () => Navigator.of(context).pop(List<KanbanUser>.from(_selected)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Selecionados em pílulas — remover é um toque no X da própria
          // pílula (o padrão da casa: a ação mora no item).
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
            child: _selected.isEmpty
                ? Row(
                    children: [
                      Icon(
                        Icons.group_outlined,
                        size: 15,
                        color: secondary,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          widget.emptyHint,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: secondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  )
                : Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final u in _selected)
                        _SelectedPersonPill(
                          user: u,
                          onRemove: () => _toggle(u),
                        ),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: taskFieldDecoration(
                context,
                hint: 'Buscar por nome ou e-mail',
                prefixIcon: Icons.search_rounded,
                tone: widget.tone,
              ),
            ),
          ),
          if (full)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 13,
                    color: widget.tone,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Máximo de ${widget.maxSelections} pessoas atingido.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: widget.tone,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Flexible(
            child: _loading
                ? _SheetLoader(tone: widget.tone)
                : _error != null
                    ? SingleChildScrollView(
                        child: AppErrorState.fromApi(
                          message: _error,
                          statusCode: _errorStatus,
                          error: _errorDetail,
                          dense: true,
                          onRetry: _load,
                        ),
                      )
                    : visible.isEmpty
                        ? const TaskSheetStatus(
                            icon: Icons.person_search_rounded,
                            message: 'Nenhuma pessoa encontrada.',
                          )
                        : ListView.separated(
                            padding: EdgeInsets.fromLTRB(
                              14,
                              8,
                              14,
                              16 + mq.padding.bottom,
                            ),
                            physics: const BouncingScrollPhysics(),
                            shrinkWrap: true,
                            itemCount: visible.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, i) {
                              final u = visible[i];
                              final on = _isSelected(u);
                              return TaskSheetOptionRow(
                                title: u.name,
                                helper: u.email.isEmpty ? null : u.email,
                                tone: taskPersonColor(u.name),
                                selected: on,
                                leading:
                                    TaskInitialAvatar(name: u.name, size: 34),
                                trailing: Icon(
                                  on
                                      ? Icons.check_circle_rounded
                                      : Icons.add_circle_outline_rounded,
                                  size: on ? 21 : 19,
                                  color: on
                                      ? taskPersonColor(u.name)
                                      : (full ? secondary.withValues(alpha: 0.4) : secondary),
                                ),
                                onTap: (!on && full) ? null : () => _toggle(u),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

/// Pílula da pessoa já escolhida — avatar + nome + remover.
class _SelectedPersonPill extends StatelessWidget {
  const _SelectedPersonPill({required this.user, required this.onRemove});

  final KanbanUser user;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = taskPersonColor(user.name);
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: tone.withValues(alpha: isDark ? 0.16 : 0.09),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TaskInitialAvatar(name: user.name, size: 22),
          const SizedBox(width: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 148),
            child: Text(
              user.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: ThemeHelpers.textColor(context),
              ),
            ),
          ),
          const SizedBox(width: 2),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, size: 14, color: tone),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// AGENDA — novo compromisso a partir do card
// =============================================================================

/// Intenção coletada pelo sheet de agenda. Quem grava (`POST /appointments`)
/// é a tela — o sheet só devolve o que a pessoa escolheu.
class TaskAppointmentDraft {
  const TaskAppointmentDraft({
    required this.title,
    required this.start,
    required this.end,
    required this.inviteUserIds,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final List<String> inviteUserIds;
}

/// Marca um compromisso ligado ao card (o `kanbanTaskId` é colado pela tela).
///
/// O web fixa 30 minutos; aqui a duração é escolhível (30/60/90) porque no
/// telefone o compromisso costuma ser criado JÁ no lugar do atendimento —
/// é acréscimo, nunca divergência: 30 continua sendo o padrão.
class TaskAppointmentSheet extends StatefulWidget {
  const TaskAppointmentSheet({
    super.key,
    required this.suggestedTitle,
    this.members,
    this.currentUserId,
  });

  /// Título do card — vira sugestão do campo (a pessoa sobrescreve).
  final String suggestedTitle;
  final List<KanbanUser>? members;
  final String? currentUserId;

  /// Magenta — família livre na tela (violeta é de PESSOAS, azul de conversa,
  /// âmbar de jornada). Agenda = compromisso marcado no tempo.
  static const Color tone = Color(0xFFDB2777);

  static Future<TaskAppointmentDraft?> show(
    BuildContext context, {
    required String suggestedTitle,
    List<KanbanUser>? members,
    String? currentUserId,
  }) {
    return showModalBottomSheet<TaskAppointmentDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => TaskAppointmentSheet(
        suggestedTitle: suggestedTitle,
        members: members,
        currentUserId: currentUserId,
      ),
    );
  }

  @override
  State<TaskAppointmentSheet> createState() => _TaskAppointmentSheetState();
}

class _TaskAppointmentSheetState extends State<TaskAppointmentSheet> {
  static const Color _tone = TaskAppointmentSheet.tone;

  final TextEditingController _title = TextEditingController();
  DateTime? _date;
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);
  int _durationMinutes = 30;
  final List<KanbanUser> _guests = [];
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    final t = widget.suggestedTitle.trim();
    _title.text = t.isEmpty ? 'Agendamento' : t;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final base = _date ?? DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: base.isBefore(DateTime(now.year, now.month, now.day))
          ? DateTime(now.year, now.month, now.day)
          : base,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 3),
      locale: const Locale('pt', 'BR'),
      helpText: 'Data do compromisso',
      builder: taskPickerTheme,
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      helpText: 'Horário',
      builder: taskPickerTheme,
    );
    if (picked != null && mounted) setState(() => _time = picked);
  }

  Future<void> _pickGuests() async {
    final chosen = await TaskPeopleMultiSelectSheet.show(
      context,
      eyebrow: 'Agenda',
      title: 'Quem você quer convidar?',
      tone: _tone,
      confirmLabel: 'Confirmar convidados',
      initialSelected: List<KanbanUser>.from(_guests),
      preloaded: widget.members,
      excludeUserId: widget.currentUserId,
      emptyHint: 'Sem convidados — o compromisso fica só seu.',
    );
    if (chosen != null && mounted) {
      setState(() {
        _guests
          ..clear()
          ..addAll(chosen);
      });
    }
  }

  void _confirm() {
    setState(() => _submitted = true);
    final d = _date;
    if (d == null) return;
    // Relógio de parede: o app manda a data LOCAL sem `Z` (mesma regra do
    // módulo de agenda — o backend interpreta em horário de Brasília).
    final start = DateTime(d.year, d.month, d.day, _time.hour, _time.minute);
    final title = _title.text.trim();
    Navigator.of(context).pop(
      TaskAppointmentDraft(
        title: title.isEmpty ? 'Agendamento' : title,
        start: start,
        end: start.add(Duration(minutes: _durationMinutes)),
        inviteUserIds: _guests.map((g) => g.id).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final dateMissing = _submitted && _date == null;
    final dateLabel = _date == null
        ? 'Escolher data'
        : DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(_date!);

    return TaskEditSheetShell(
      eyebrow: 'Agenda',
      title: 'Novo compromisso',
      tone: _tone,
      footer: TaskSheetPrimaryButton(
        label: 'Agendar',
        icon: Icons.event_available_rounded,
        onPressed: _confirm,
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: taskFieldDecoration(
                context,
                label: 'Título',
                prefixIcon: Icons.title_rounded,
                tone: _tone,
              ).copyWith(counterText: ''),
            ),
            const SizedBox(height: 14),
            _AppointmentPickerTile(
              icon: Icons.calendar_today_rounded,
              label: 'Data',
              value: dateLabel,
              tone: _tone,
              filled: _date != null,
              error: dateMissing,
              onTap: _pickDate,
            ),
            if (dateMissing) ...[
              const SizedBox(height: 6),
              Text(
                'Escolha uma data para agendar.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: const Color(0xFFDC2626),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(height: 10),
            _AppointmentPickerTile(
              icon: Icons.schedule_rounded,
              label: 'Horário',
              value:
                  '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
              tone: _tone,
              filled: true,
              onTap: _pickTime,
            ),
            const SizedBox(height: 16),
            Text(
              'DURAÇÃO',
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1.4,
                fontWeight: FontWeight.w800,
                color: secondary,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final m in const [30, 60, 90]) ...[
                  Expanded(
                    child: _DurationChip(
                      minutes: m,
                      selected: _durationMinutes == m,
                      tone: _tone,
                      onTap: () => setState(() => _durationMinutes = m),
                    ),
                  ),
                  if (m != 90) const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 18),
            _AppointmentPickerTile(
              icon: Icons.group_add_outlined,
              label: 'Convidados',
              value: _guests.isEmpty
                  ? 'Ninguém convidado'
                  : _guests.map((g) => g.name).join(', '),
              tone: _tone,
              filled: _guests.isNotEmpty,
              onTap: _pickGuests,
            ),
            if (_guests.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.mark_email_unread_outlined,
                      size: 13, color: secondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Convidado não entra confirmado: recebe o convite e '
                      'decide.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: secondary,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Linha de escolha do sheet de agenda — ícone + rótulo + valor + seta.
class _AppointmentPickerTile extends StatelessWidget {
  const _AppointmentPickerTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
    required this.filled,
    required this.onTap,
    this.error = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tone;
  final bool filled;
  final bool error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final border = error
        ? const Color(0xFFDC2626).withValues(alpha: 0.6)
        : filled
            ? tone.withValues(alpha: 0.4)
            : ThemeHelpers.borderColor(context).withValues(alpha: 0.5);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(13, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: filled
                ? tone.withValues(alpha: isDark ? 0.12 : 0.06)
                : Colors.transparent,
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 17, color: filled ? tone : secondary),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 9.5,
                        letterSpacing: 1.3,
                        fontWeight: FontWeight.w800,
                        color: filled ? tone : secondary,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        height: 1.25,
                        color: filled
                            ? ThemeHelpers.textColor(context)
                            : secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded, size: 16, color: secondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _DurationChip extends StatelessWidget {
  const _DurationChip({
    required this.minutes,
    required this.selected,
    required this.tone,
    required this.onTap,
  });

  final int minutes;
  final bool selected;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: selected
                ? tone.withValues(alpha: isDark ? 0.18 : 0.1)
                : Colors.transparent,
            border: Border.all(
              color: selected
                  ? tone.withValues(alpha: 0.5)
                  : ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              minutes >= 60
                  ? '${(minutes / 60).toStringAsFixed(minutes % 60 == 0 ? 0 : 1)} h'
                  : '$minutes min',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                color: selected ? tone : secondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

