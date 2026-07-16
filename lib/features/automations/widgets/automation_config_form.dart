import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/automation_models.dart';

/// Formulário de configuração da automação — usado na tela de detalhe e nas
/// etapas do builder de criação. Seções *flush* separadas por filete tracejado
/// + eyebrow com dot de cor (mesma gramática do modal de filtros do CRM):
/// quando/timing, quem/destinatários, como/canais e mensagem personalizada.
///
/// O widget é a fonte da verdade dos campos: recebe [initialConfig] e emite
/// [onChanged] com o config atualizado a cada interação (round-trip preservado
/// pelo próprio [AutomationConfig]).
class AutomationConfigForm extends StatefulWidget {
  final AutomationConfig initialConfig;
  final ValueChanged<AutomationConfig> onChanged;

  /// Quais grupos de seção exibir — permite quebrar o form em etapas no
  /// builder de criação (condições vs. ações).
  final bool showTiming;
  final bool showRecipients;
  final bool showChannels;
  final bool showMessage;

  const AutomationConfigForm({
    super.key,
    required this.initialConfig,
    required this.onChanged,
    this.showTiming = true,
    this.showRecipients = true,
    this.showChannels = true,
    this.showMessage = true,
  });

  @override
  State<AutomationConfigForm> createState() => _AutomationConfigFormState();
}

class _AutomationConfigFormState extends State<AutomationConfigForm> {
  late AutomationConfig _config;
  late final TextEditingController _daysController;
  late final TextEditingController _hoursController;
  late final TextEditingController _messageController;

  static const int _kMessageMax = 500;

  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig;
    _daysController =
        TextEditingController(text: _config.timingDays.join(', '));
    _hoursController =
        TextEditingController(text: _config.timingHours.join(', '));
    _messageController = TextEditingController(text: _config.customMessage);
  }

  @override
  void dispose() {
    _daysController.dispose();
    _hoursController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _emit(AutomationConfig next) {
    setState(() => _config = next);
    widget.onChanged(next);
  }

  List<int> _parseIntList(String raw) {
    return raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map(int.tryParse)
        .whereType<int>()
        .toList();
  }

  Color _fieldFill(BuildContext c) => Theme.of(c).brightness == Brightness.dark
      ? AppColors.background.backgroundTertiaryDarkMode
      : AppColors.background.backgroundTertiary;

  InputDecoration _fieldDecoration(
    BuildContext context, {
    required String hint,
    Widget? prefixIcon,
  }) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: secondary.withValues(alpha: 0.9),
      ),
      prefixIcon: prefixIcon,
      filled: true,
      fillColor: _fieldFill(context),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: ThemeHelpers.borderLightColor(context)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: ThemeHelpers.borderLightColor(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Theme.of(context).brightness == Brightness.dark
              ? AppColors.primary.primaryDarkMode
              : AppColors.primary.primary,
          width: 1.4,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cTiming =
        isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final cRecipients =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final cChannels =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    final cMessage =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;

    var first = true;
    final sections = <Widget>[];

    void add(Widget section) {
      sections.add(section);
      first = false;
    }

    if (widget.showTiming) {
      add(_section(
        context,
        accent: cTiming,
        label: 'Quando disparar',
        hint: 'Dias/horas de antecedência do evento. Ex.: 7, 3, 1 notifica '
            '7, 3 e 1 dia antes.',
        first: first,
        child: _buildTiming(context, cTiming),
      ));
    }
    if (widget.showRecipients) {
      add(_section(
        context,
        accent: cRecipients,
        label: 'Destinatários',
        hint: 'Quem recebe as notificações desta automação.',
        first: first,
        child: _buildRecipients(context, cRecipients),
      ));
    }
    if (widget.showChannels) {
      add(_section(
        context,
        accent: cChannels,
        label: 'Canais',
        hint: 'Por onde as notificações são enviadas.',
        first: first,
        child: _buildChannels(context, cChannels),
      ));
    }
    if (widget.showMessage) {
      add(_section(
        context,
        accent: cMessage,
        label: 'Mensagem personalizada',
        hint: 'Use variáveis: {days}, {name}, {property}, {value}.',
        first: first,
        child: _buildMessage(context),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: sections,
    );
  }

  // ─── Seções ─────────────────────────────────────────────────────────────

  Widget _buildTiming(BuildContext context, Color accent) {
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final fieldStyle = TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w700,
      color: textColor,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Campos filled em 2 colunas (dias | horas).
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _fieldLabel(context, 'Dias antes'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _daysController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9,\s]')),
                    ],
                    style: fieldStyle,
                    decoration: _fieldDecoration(
                      context,
                      hint: 'Ex: 7, 3, 1',
                      prefixIcon: Icon(LucideIcons.calendarDays,
                          size: 17, color: accent),
                    ),
                    onChanged: (v) => _emit(
                      _config.copyWith(timingDays: _parseIntList(v)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _fieldLabel(context, 'Horas antes'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _hoursController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9,\s]')),
                    ],
                    style: fieldStyle,
                    decoration: _fieldDecoration(
                      context,
                      hint: 'Ex: 24, 1',
                      prefixIcon:
                          Icon(LucideIcons.timer, size: 17, color: accent),
                    ),
                    onChanged: (v) => _emit(
                      _config.copyWith(timingHours: _parseIntList(v)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Imediato — switch no próprio item.
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _emit(_config.copyWith(immediate: !_config.immediate)),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(
              color: _fieldFill(context),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: ThemeHelpers.borderLightColor(context)),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.zap, size: 17, color: accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Imediato após evento',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Dispara assim que o evento acontecer.',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 26,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Switch.adaptive(
                      value: _config.immediate,
                      activeTrackColor: accent,
                      onChanged: (v) =>
                          _emit(_config.copyWith(immediate: v)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecipients(BuildContext context, Color accent) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final key in kAutomationRecipientKeys)
          _ChipChoice(
            label: automationRecipientLabel(key),
            icon: _recipientIcon(key),
            selected: _config.recipients[key] ?? false,
            accent: accent,
            onTap: () {
              final next = Map<String, bool>.from(_config.recipients);
              next[key] = !(next[key] ?? false);
              _emit(_config.copyWith(recipients: next));
            },
          ),
      ],
    );
  }

  IconData _recipientIcon(String key) {
    switch (key) {
      case 'corretor':
        return LucideIcons.briefcase;
      case 'cliente':
        return LucideIcons.user;
      case 'proprietario':
        return LucideIcons.house;
      case 'admin':
        return LucideIcons.shield;
      case 'manager':
        return LucideIcons.userCog;
      case 'lead':
        return LucideIcons.userPlus;
      default:
        return LucideIcons.user;
    }
  }

  Widget _buildChannels(BuildContext context, Color accent) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final key in kAutomationChannelKeys)
          _ChipChoice(
            label: automationChannelLabel(key),
            icon: key == 'email' ? LucideIcons.mail : LucideIcons.bellRing,
            selected: _config.channels[key] ?? false,
            accent: accent,
            onTap: () {
              final next = Map<String, bool>.from(_config.channels);
              next[key] = !(next[key] ?? false);
              _emit(_config.copyWith(channels: next));
            },
          ),
      ],
    );
  }

  Widget _buildMessage(BuildContext context) {
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final length = _messageController.text.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _messageController,
          maxLines: 4,
          maxLength: _kMessageMax,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: textColor,
            height: 1.45,
          ),
          decoration: _fieldDecoration(
            context,
            hint: 'Ex: Olá {name}, o pagamento do imóvel {property} vence '
                'em {days} dias. Valor: {value}.',
          ).copyWith(counterText: ''),
          onChanged: (v) {
            _emit(_config.copyWith(customMessage: v));
          },
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '$length/$_kMessageMax caracteres',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: secondary,
            ),
          ),
        ),
      ],
    );
  }

  // ─── Blocos base ────────────────────────────────────────────────────────

  Widget _fieldLabel(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
        color: ThemeHelpers.textSecondaryColor(context),
      ),
    );
  }

  /// Seção flush: filete tracejado (exceto a primeira) + eyebrow com dot de
  /// cor + hint + conteúdo — espelha o modal de filtros do CRM.
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
      padding: EdgeInsets.only(top: first ? 4 : 22),
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
}

/// Chip de seleção — ativo usa tint (fundo translúcido + borda + texto na
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
            if (selected) ...[
              const SizedBox(width: 5),
              Icon(LucideIcons.check, size: 13, color: fg),
            ],
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
