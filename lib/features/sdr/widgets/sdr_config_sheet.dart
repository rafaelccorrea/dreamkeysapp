import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/sdr_settings_model.dart';
import '../services/sdr_service.dart';

/// Bottom-sheet de **configurações rápidas do agente** — abre pelo botão de
/// Config da appbar do dashboard SDR. Mesma gramática dos modais de filtro do
/// app (cabeçalho com título + descrição curta, seções com barra tonal,
/// filete tracejado entre grupos), com controles de estado claro: toggles com
/// ícone, janela de atendimento com pickers de hora e tom de conversa em
/// chips. Footer com **Salvar em verde de confirmação** e atalho neutro para
/// as configurações completas.
///
/// O PUT exige o DTO completo — o sheet parte das configurações reais
/// (`initial` ou `GET /sdr-settings`) e só altera os campos rápidos.
class SdrConfigSheet extends StatefulWidget {
  const SdrConfigSheet({
    super.key,
    this.initial,
    required this.onSaved,
    required this.onOpenFullSettings,
  });

  /// Configurações já carregadas pela página (evita novo fetch). Se `null`,
  /// o sheet busca sozinho ao abrir.
  final SdrSettings? initial;

  /// Chamado após salvar com sucesso — a página atualiza o console do agente.
  final ValueChanged<SdrSettings> onSaved;

  /// Abre a página de configurações completas (o sheet se fecha antes).
  final VoidCallback onOpenFullSettings;

  @override
  State<SdrConfigSheet> createState() => _SdrConfigSheetState();
}

class _SdrConfigSheetState extends State<SdrConfigSheet> {
  SdrSettings? _settings;
  SdrSettings? _original;
  bool _loading = false;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _settings = widget.initial;
      _original = widget.initial;
    } else {
      _fetch();
    }
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final res = await SdrService.instance.getSettings();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _settings = res.data;
        _original = res.data;
      } else {
        _loadError =
            res.message ?? 'Erro ao carregar configurações do agente';
      }
    });
  }

  bool get _dirty {
    final s = _settings;
    final o = _original;
    if (s == null || o == null) return false;
    return s.enabled != o.enabled ||
        s.autoRespond != o.autoRespond ||
        s.businessHoursStart != o.businessHoursStart ||
        s.businessHoursEnd != o.businessHoursEnd ||
        s.workOnWeekends != o.workOnWeekends ||
        s.tone != o.tone;
  }

  void _patch(SdrSettings Function(SdrSettings) fn) {
    final s = _settings;
    if (s == null || _saving) return;
    setState(() => _settings = fn(s));
  }

  Future<void> _save() async {
    final s = _settings;
    if (s == null || _saving || !_dirty) return;
    setState(() => _saving = true);
    final res = await SdrService.instance.updateSettings(s);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.success && res.data != null) {
      widget.onSaved(res.data!);
      Navigator.of(context).pop();
    } else {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor:
              isDark ? AppColors.status.errorDarkMode : AppColors.status.error,
          content: Text(
            res.message ?? 'Erro ao salvar configurações do agente',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _pickHour({required bool isStart}) async {
    final s = _settings;
    if (s == null || _saving) return;
    final raw = isStart ? s.businessHoursStart : s.businessHoursEnd;
    final parts = raw.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 8,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: isStart ? 'Início do atendimento' : 'Fim do atendimento',
    );
    if (picked == null) return;
    final hms = '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}:00';
    _patch((s) => isStart
        ? s.copyWith(businessHoursStart: hms)
        : s.copyWith(businessHoursEnd: hms));
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final violet =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    final mq = MediaQuery.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
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
              _buildHeader(context, violet),
              Expanded(
                child: _loading
                    ? _buildSkeleton(context, scrollController)
                    : _loadError != null
                        ? _buildLoadError(context, scrollController)
                        : _buildBody(context, scrollController),
              ),
              _buildFooter(context, mq),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, Color violet) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final s = _settings;
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final statusTone =
        (s?.enabled ?? false) ? green : ThemeHelpers.textSecondaryColor(context);

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
              color: violet.withValues(alpha: isDark ? 0.20 : 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: violet.withValues(alpha: 0.30)),
            ),
            child: Icon(
              (s?.enabled ?? true) ? LucideIcons.bot : LucideIcons.botOff,
              color: violet,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Configurações do agente',
                        softWrap: true,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                    ),
                    if (s != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: statusTone.withValues(
                              alpha: isDark ? 0.16 : 0.10),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: statusTone.withValues(alpha: 0.38)),
                        ),
                        child: Text(
                          s.enabled ? 'Ativo' : 'Pausado',
                          style: TextStyle(
                            color: statusTone,
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
                  'Ajustes rápidos do Zezin — estado, atendimento e tom.',
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

  Widget _buildBody(BuildContext context, ScrollController controller) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final violet =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final blue = isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final s = _settings!;

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        _section(
          context,
          accent: violet,
          icon: LucideIcons.bot,
          label: 'Estado do agente',
          hint: 'Liga/desliga o pré-atendimento com IA no WhatsApp.',
          first: true,
          child: Column(
            children: [
              _toggleRow(
                context,
                icon: s.enabled ? LucideIcons.bot : LucideIcons.botOff,
                accent: violet,
                title: 'Agente ativo',
                subtitle: s.enabled
                    ? 'Atendendo novas conversas automaticamente.'
                    : 'Pausado — nenhuma conversa é atendida pela IA.',
                value: s.enabled,
                onChanged: (v) => _patch((s) => s.copyWith(enabled: v)),
              ),
              const SizedBox(height: 10),
              _toggleRow(
                context,
                icon: LucideIcons.zap,
                accent: violet,
                title: 'Resposta automática',
                subtitle: 'Responde novas mensagens sem ação humana.',
                value: s.autoRespond,
                onChanged: (v) => _patch((s) => s.copyWith(autoRespond: v)),
              ),
            ],
          ),
        ),
        _section(
          context,
          accent: amber,
          icon: LucideIcons.clock3,
          label: 'Janela de atendimento',
          hint: 'Fora do horário o agente não inicia atendimento.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _hourControl(
                      context,
                      accent: amber,
                      label: 'Início',
                      value: SdrSettings.hourLabel(s.businessHoursStart),
                      onTap: () => _pickHour(isStart: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _hourControl(
                      context,
                      accent: amber,
                      label: 'Fim',
                      value: SdrSettings.hourLabel(s.businessHoursEnd),
                      onTap: () => _pickHour(isStart: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _toggleRow(
                context,
                icon: LucideIcons.calendarDays,
                accent: amber,
                title: 'Fins de semana',
                subtitle: s.workOnWeekends
                    ? 'Atende todos os dias, incluindo sábado e domingo.'
                    : 'Atende apenas de segunda a sexta.',
                value: s.workOnWeekends,
                onChanged: (v) => _patch((s) => s.copyWith(workOnWeekends: v)),
              ),
            ],
          ),
        ),
        _section(
          context,
          accent: blue,
          icon: LucideIcons.messageSquareText,
          label: 'Tom de conversa',
          hint: 'Como o agente escreve com os leads.',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tone in SdrTone.values)
                _ToneChoice(
                  label: tone.label,
                  selected: s.tone == tone,
                  accent: blue,
                  onTap: () => _patch((s) => s.copyWith(tone: tone)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Seção com barra tonal (título nunca trunca) ───────────────────────────

  Widget _section(
    BuildContext context, {
    required Color accent,
    required IconData icon,
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

  // ─── Controles ─────────────────────────────────────────────────────────────

  Widget _toggleRow(
    BuildContext context, {
    required IconData icon,
    required Color accent,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fieldFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: fieldFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value
              ? accent.withValues(alpha: 0.35)
              : ThemeHelpers.borderLightColor(context),
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
            child: Icon(icon, size: 16, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 1.5),
                Text(
                  subtitle,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontSize: 10.5,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Switch.adaptive(
            value: value,
            activeTrackColor: accent,
            onChanged: _saving ? null : onChanged,
          ),
        ],
      ),
    );
  }

  Widget _hourControl(
    BuildContext context, {
    required Color accent,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fieldFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    return InkWell(
      onTap: _saving ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
        decoration: BoxDecoration(
          color: fieldFill,
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
              child: Icon(LucideIcons.clock, size: 16, color: accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    value,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              LucideIcons.chevronDown,
              size: 14,
              color: ThemeHelpers.textSecondaryColor(context)
                  .withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Estados de carga ──────────────────────────────────────────────────────

  Widget _buildSkeleton(BuildContext context, ScrollController controller) {
    return ListView(
      controller: controller,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: const [
        SkeletonText(width: 140, height: 11, borderRadius: 4),
        SizedBox(height: 14),
        SkeletonBox(width: double.infinity, height: 54, borderRadius: 12),
        SizedBox(height: 10),
        SkeletonBox(width: double.infinity, height: 54, borderRadius: 12),
        SizedBox(height: 24),
        SkeletonText(width: 170, height: 11, borderRadius: 4),
        SizedBox(height: 14),
        SkeletonBox(width: double.infinity, height: 48, borderRadius: 12),
        SizedBox(height: 10),
        SkeletonBox(width: double.infinity, height: 54, borderRadius: 12),
        SizedBox(height: 24),
        SkeletonText(width: 120, height: 11, borderRadius: 4),
        SizedBox(height: 14),
        Row(
          children: [
            SkeletonBox(width: 96, height: 34, borderRadius: 999),
            SizedBox(width: 8),
            SkeletonBox(width: 88, height: 34, borderRadius: 999),
            SizedBox(width: 8),
            SkeletonBox(width: 76, height: 34, borderRadius: 999),
          ],
        ),
      ],
    );
  }

  Widget _buildLoadError(BuildContext context, ScrollController controller) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 40),
      children: [
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: danger.withValues(alpha: 0.12),
              border: Border.all(color: danger.withValues(alpha: 0.32)),
            ),
            child: Icon(LucideIcons.cloudOff, color: danger, size: 24),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          _loadError ?? 'Erro ao carregar configurações do agente',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: ThemeHelpers.textColor(context),
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: OutlinedButton.icon(
            onPressed: _fetch,
            icon: const Icon(LucideIcons.refreshCw, size: 15),
            label: const Text('Tentar novamente'),
          ),
        ),
      ],
    );
  }

  // ─── Footer ────────────────────────────────────────────────────────────────

  Widget _buildFooter(BuildContext context, MediaQueryData mq) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Verde = confirmação (Salvar). O atalho para as opções completas é neutro.
    final confirm =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final canSave = _settings != null && _dirty && !_saving;

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
            flex: 3,
            child: OutlinedButton.icon(
              onPressed: _saving
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      widget.onOpenFullSettings();
                    },
              icon: const Icon(LucideIcons.settings2, size: 17),
              label: const Text(
                'Todas as opções',
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
          Expanded(
            flex: 4,
            child: FilledButton.icon(
              onPressed: canSave ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(LucideIcons.check, size: 18),
              label: Text(
                _saving ? 'Salvando…' : 'Salvar',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: confirm,
                foregroundColor: Colors.white,
                disabledBackgroundColor: confirm.withValues(alpha: 0.35),
                disabledForegroundColor: Colors.white70,
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

/// Chip de tom de conversa — tint + check quando selecionado.
class _ToneChoice extends StatelessWidget {
  const _ToneChoice({
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: isDark ? 0.18 : 0.10)
              : fieldFill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color:
                selected ? accent : ThemeHelpers.borderLightColor(context),
            width: selected ? 1.2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(LucideIcons.check, size: 13, color: fg),
              const SizedBox(width: 5),
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

/// Filete tracejado fino — mesmo separador dos modais de filtro.
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
