import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/theme_helpers.dart';
import '../controllers/kanban_controller.dart';
import '../models/kanban_models.dart';

/// Bottom sheet editorial: resultado do negócio (ganho / perda / reabrir).
class MarkTaskResultSheet extends StatefulWidget {
  const MarkTaskResultSheet({
    super.key,
    required this.task,
    this.quickEntry,
  });

  final KanbanTask task;
  final String? quickEntry;

  @override
  State<MarkTaskResultSheet> createState() => _MarkTaskResultSheetState();
}

class _MarkTaskResultSheetState extends State<MarkTaskResultSheet> {
  late final TextEditingController _notes = TextEditingController();
  KanbanLossReason? _lossReason;
  String? _mode;
  bool _submitting = false;
  String? _localError;

  KanbanTask get task => widget.task;

  static const Color _inkWin = Color(0xFF15803D);
  static const Color _inkLoss = Color(0xFFB91C1C);
  static const Color _inkNeutral = Color(0xFF6366F1);

  @override
  void initState() {
    super.initState();
    _notes.text = task.resultNotes?.trim() ?? '';
    _lossReason = KanbanLossReason.tryParse(task.lossReason);
    final q = widget.quickEntry?.trim().toLowerCase();
    if (!task.hasClosedResult && (q == 'won' || q == 'lost')) {
      _mode = q;
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  String _resultLabel() {
    switch (task.normalizedResult) {
      case 'won':
        return 'Vendido';
      case 'lost':
        return 'Perdido';
      case 'cancelled':
        return 'Cancelado';
      default:
        return 'Em aberto';
    }
  }

  Future<void> _submit({
    required String result,
    String? lossReasonApi,
  }) async {
    setState(() {
      _localError = null;
      _submitting = true;
    });
    final controller = context.read<KanbanController>();
    final ok = await controller.markTaskResult(
      task.id,
      result: result,
      lossReason: lossReasonApi,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Resultado atualizado.')),
      );
    } else {
      final msg = controller.error ?? 'Não foi possível atualizar o resultado.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _onConfirmWon() async => _submit(result: 'won');

  Future<void> _onConfirmLost() async {
    if (_lossReason == null) {
      setState(() => _localError = 'Selecione o motivo da perda.');
      return;
    }
    await _submit(result: 'lost', lossReasonApi: _lossReason!.apiValue);
  }

  Future<void> _onReopen() async => _submit(result: 'open');

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
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.9),
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: ThemeHelpers.cardBackgroundColor(context),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
              border: Border.all(color: border.withValues(alpha: 0.45)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                  blurRadius: 40,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SheetGrabber(color: border),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 6, 22, 8),
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _EditorialKicker(
                          text: 'CRM · NEGOCIAÇÃO',
                          color: muted,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Resultado do card',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _LeadTitlePanel(
                          title: task.title,
                          borderColor: border,
                          accent: _accentForSheet(),
                        ),
                        const SizedBox(height: 22),
                        if (task.hasClosedResult) ...[
                          _OutcomeManifest(
                            label: _resultLabel(),
                            won: task.normalizedResult == 'won',
                            lost: task.normalizedResult == 'lost',
                          ),
                          const SizedBox(height: 20),
                          _EditorialInset(
                            borderColor: border,
                            child: Text(
                              'Reabrir devolve o card ao funil em andamento, limpando '
                              'resultado e motivo de perda. O histórico permanece auditável.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: muted,
                                height: 1.5,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _PrimaryRailButton(
                            onPressed: _submitting ? null : _onReopen,
                            submitting: _submitting,
                            icon: Icons.restart_alt_rounded,
                            label: 'Reabrir negociação',
                            foreground: Colors.white,
                            background: _inkNeutral,
                          ),
                        ] else if (_mode == null) ...[
                          Text(
                            'Como este lead encerra neste funil?',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Escolha uma linha editorial: vitória fecha o ciclo com registro '
                            'opcional; perda exige motivo — alinhado ao CRM web.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: muted,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _OutcomePathCard(
                            title: 'Vitória',
                            subtitle: 'Marcar como vendido',
                            icon: Icons.emoji_events_outlined,
                            accent: _inkWin,
                            isDark: isDark,
                            onTap: _submitting
                                ? null
                                : () => setState(() => _mode = 'won'),
                          ),
                          const SizedBox(height: 12),
                          _OutcomePathCard(
                            title: 'Perda',
                            subtitle: 'Encerrar com motivo',
                            icon: Icons.south_west_rounded,
                            accent: _inkLoss,
                            isDark: isDark,
                            onTap: _submitting
                                ? null
                                : () => setState(() => _mode = 'lost'),
                          ),
                        ] else ...[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: _submitting
                                  ? null
                                  : () => setState(() {
                                        _mode = null;
                                        _localError = null;
                                      }),
                              icon: Icon(
                                Icons.arrow_back_ios_new_rounded,
                                size: 14,
                                color: theme.colorScheme.primary,
                              ),
                              label: Text(
                                'Outra decisão',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_mode == 'won') ...[
                            _EditorialInset(
                              borderColor: border,
                              accent: _inkWin,
                              child: Text(
                                'Confirme a venda. As observações alimentam o histórico '
                                'e relatórios — seja objetivo.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: muted,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ] else ...[
                            _EditorialInset(
                              borderColor: border,
                              accent: _inkLoss,
                              child: Text(
                                'A perda exige motivo catalogado. Isso alimenta dashboards '
                                'e evita ruído em exportações.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: muted,
                                  height: 1.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Motivo da perda',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 10),
                            LayoutBuilder(
                              builder: (context, c) {
                                final col = c.maxWidth < 360 ? 1 : 2;
                                final w = col == 1
                                    ? c.maxWidth
                                    : (c.maxWidth - 10) / 2;
                                return Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    for (final e in KanbanLossReason.values)
                                      SizedBox(
                                        width: w,
                                        child: _LossReasonTile(
                                          reason: e,
                                          selected: _lossReason == e,
                                          enabled: !_submitting,
                                          onTap: () => setState(() {
                                            _lossReason = e;
                                            _localError = null;
                                          }),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ],
                          const SizedBox(height: 18),
                          _EditorialNotesField(
                            controller: _notes,
                            enabled: !_submitting,
                            label: 'Observações',
                            hint: _mode == 'won'
                                ? 'Forma de pagamento, permuta, próximos passos…'
                                : 'Contexto adicional para o time (opcional)',
                          ),
                          if (_localError != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              _localError!,
                              style: const TextStyle(
                                color: _inkLoss,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          _PrimaryRailButton(
                            onPressed: _submitting
                                ? null
                                : () async {
                                    if (_mode == 'won') {
                                      await _onConfirmWon();
                                    } else {
                                      await _onConfirmLost();
                                    }
                                  },
                            submitting: _submitting,
                            icon: _mode == 'won'
                                ? Icons.verified_rounded
                                : Icons.gavel_rounded,
                            label: _mode == 'won'
                                ? 'Confirmar venda'
                                : 'Confirmar perda',
                            foreground: Colors.white,
                            background:
                                _mode == 'won' ? _inkWin : _inkLoss,
                          ),
                        ],
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    10,
                    20,
                    12 + mq.padding.bottom,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: border.withValues(alpha: 0.35),
                      ),
                    ),
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: isDark ? 0.2 : 0.35),
                  ),
                  child: TextButton(
                    onPressed:
                        _submitting ? null : () => Navigator.of(context).pop(),
                    child: Text(
                      'Fechar sem alterar',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: muted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _accentForSheet() {
    if (task.hasClosedResult) {
      if (task.normalizedResult == 'won') return _inkWin;
      if (task.normalizedResult == 'lost') return _inkLoss;
    }
    if (_mode == 'won') return _inkWin;
    if (_mode == 'lost') return _inkLoss;
    return _inkNeutral;
  }
}

// ── Editorial primitives ─────────────────────────────────────────────────

class _SheetGrabber extends StatelessWidget {
  const _SheetGrabber({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Center(
        child: Container(
          width: 44,
          height: 4,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

class _EditorialKicker extends StatelessWidget {
  const _EditorialKicker({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.35,
        color: color,
        height: 1.2,
      ),
    );
  }
}

class _LeadTitlePanel extends StatelessWidget {
  const _LeadTitlePanel({
    required this.title,
    required this.borderColor,
    required this.accent,
  });

  final String title;
  final Color borderColor;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor.withValues(alpha: 0.4)),
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: theme.brightness == Brightness.dark ? 0.22 : 0.4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  accent,
                  accent.withValues(alpha: 0.45),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Card',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OutcomeManifest extends StatelessWidget {
  const _OutcomeManifest({
    required this.label,
    required this.won,
    required this.lost,
  });

  final String label;
  final bool won;
  final bool lost;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = won
        ? const Color(0xFF15803D)
        : lost
            ? const Color(0xFFB91C1C)
            : ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.38)),
        color: color.withValues(alpha: 0.08),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.16),
            ),
            child: Icon(
              won ? Icons.emoji_events_rounded : Icons.flag_rounded,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Situação registrada',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: color,
                    letterSpacing: -0.4,
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

class _EditorialInset extends StatelessWidget {
  const _EditorialInset({
    required this.borderColor,
    required this.child,
    this.accent,
  });

  final Color borderColor;
  final Widget child;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = accent ?? theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: theme.brightness == Brightness.dark ? 0.18 : 0.32),
        border: Border.all(color: borderColor.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            margin: const EdgeInsets.only(top: 2),
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: a,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _OutcomePathCard extends StatelessWidget {
  const _OutcomePathCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.isDark,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final bool isDark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = ThemeHelpers.borderColor(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accent.withValues(alpha: onTap == null ? 0.2 : 0.42),
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: isDark ? 0.14 : 0.07),
                accent.withValues(alpha: isDark ? 0.06 : 0.02),
              ],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: accent.withValues(alpha: 0.18),
                  border: Border.all(color: accent.withValues(alpha: 0.35)),
                ),
                child: Icon(icon, color: accent, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: border.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LossReasonTile extends StatelessWidget {
  const _LossReasonTile({
    required this.reason,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final KanbanLossReason reason;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = ThemeHelpers.borderColor(context);
    final accent = const Color(0xFFB91C1C);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.75)
                  : border.withValues(alpha: 0.35),
              width: selected ? 1.4 : 1,
            ),
            color: selected
                ? accent.withValues(alpha: 0.1)
                : theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.25),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 18,
                color: selected ? accent : border,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  reason.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    height: 1.25,
                    fontSize: 12.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorialNotesField extends StatelessWidget {
  const _EditorialNotesField({
    required this.controller,
    required this.enabled,
    required this.label,
    required this.hint,
  });

  final TextEditingController controller;
  final bool enabled;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = ThemeHelpers.borderColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: enabled,
          minLines: 3,
          maxLines: 5,
          style: theme.textTheme.bodyMedium?.copyWith(
            height: 1.45,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.35),
            contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: border.withValues(alpha: 0.35)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: border.withValues(alpha: 0.35)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: 0.65),
                width: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PrimaryRailButton extends StatelessWidget {
  const _PrimaryRailButton({
    required this.onPressed,
    required this.submitting,
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
  });

  final VoidCallback? onPressed;
  final bool submitting;
  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: background.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (submitting)
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: foreground,
                    ),
                  )
                else ...[
                  Icon(icon, color: foreground, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
