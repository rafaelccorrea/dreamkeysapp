import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../services/appointment_schedule_service.dart';

/// Accent da seção "Regras da agenda".
const Color _kIndigo = Color(0xFF6366F1);

/// Accent da seção "Grade semanal".
const Color _kGreen = Color(0xFF3FA66B);

/// Verde de confirmação do botão salvar (regra do app: confirmar = verde).
const Color _kSaveGreen = Color(0xFF059669);

/// Vermelho de ação destrutiva (lixeira de faixa / faixa inválida).
const Color _kDanger = Color(0xFFDC2626);

/// "Meus horários" — regra de horários da agenda do usuário logado.
/// Paridade com o `ScheduleSettingsPanel` do imobx-front: grade semanal
/// (dias + faixas HH:mm), intervalo mínimo entre compromissos e confirmação
/// de convites.
class ScheduleSettingsPage extends StatefulWidget {
  const ScheduleSettingsPage({super.key});

  @override
  State<ScheduleSettingsPage> createState() => _ScheduleSettingsPageState();
}

class _ScheduleSettingsPageState extends State<ScheduleSettingsPage> {
  bool _loading = true;
  String? _loadError;
  bool _saving = false;

  bool _enforceWorkingHours = true;
  int _gapMinutes = 0;
  bool _requireInviteConfirmation = false;
  List<ScheduleDay> _week = defaultWeeklyHours();

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ---------------------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------------------
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    final res =
        await AppointmentScheduleService.instance.getScheduleSettings();
    if (!mounted) return;

    if (res.success && res.data != null) {
      final settings = res.data!;
      setState(() {
        _loading = false;
        if (settings.configured) {
          _enforceWorkingHours = settings.enforceWorkingHours;
          _gapMinutes = settings.gapMinutes;
          _requireInviteConfirmation = settings.requireInviteConfirmation;
          _week = _normalizeWeek(settings.weeklyHours);
        } else {
          // Primeira visita: semeia com a grade padrão do web.
          _enforceWorkingHours = true;
          _gapMinutes = 0;
          _requireInviteConfirmation = false;
          _week = defaultWeeklyHours();
        }
      });
    } else {
      setState(() {
        _loading = false;
        _loadError = res.message ?? 'Erro ao carregar horários';
      });
    }
  }

  /// Garante os 7 dias no estado mesmo se a API vier incompleta.
  List<ScheduleDay> _normalizeWeek(List<ScheduleDay> source) {
    final byDay = {for (final d in source) d.weekday: d};
    final defaults = defaultWeeklyHours();
    return [
      for (var w = 0; w <= 6; w++)
        byDay[w] ?? defaults.firstWhere((d) => d.weekday == w),
    ];
  }

  ScheduleDay _dayOf(int weekday) =>
      _week.firstWhere((d) => d.weekday == weekday);

  void _updateDay(int weekday, ScheduleDay Function(ScheduleDay) transform) {
    setState(() {
      _week = _week
          .map((d) => d.weekday == weekday ? transform(d) : d)
          .toList();
    });
  }

  // ---------------------------------------------------------------------------
  // Mutations da grade
  // ---------------------------------------------------------------------------
  void _toggleDay(int weekday, bool value) {
    _updateDay(weekday, (d) {
      final intervals = value && d.intervals.isEmpty
          ? const [ScheduleInterval(start: '08:00', end: '18:00')]
          : d.intervals;
      return d.copyWith(enabled: value, intervals: intervals);
    });
  }

  void _addInterval(int weekday) {
    _updateDay(weekday, (d) {
      final next = d.intervals.isEmpty
          ? const ScheduleInterval(start: '08:00', end: '12:00')
          : const ScheduleInterval(start: '13:30', end: '18:00');
      return d.copyWith(intervals: [...d.intervals, next]);
    });
  }

  void _removeInterval(int weekday, int index) {
    _updateDay(weekday, (d) {
      final list = List.of(d.intervals)..removeAt(index);
      return d.copyWith(intervals: list);
    });
  }

  /// Replica a grade do dia [weekday] em todos os dias úteis (seg–sex).
  void _applyToWorkdays(int weekday) {
    final source = _dayOf(weekday);
    setState(() {
      _week = _week.map((d) {
        if (d.weekday < 1 || d.weekday > 5) return d;
        return d.copyWith(
          enabled: source.enabled,
          intervals: List.of(source.intervals),
        );
      }).toList();
    });
    HapticFeedback.selectionClick();
    _snack('Grade aplicada de segunda a sexta');
  }

  Future<void> _pickIntervalTime(
    int weekday,
    int index, {
    required bool isStart,
  }) async {
    final interval = _dayOf(weekday).intervals[index];
    final minutes =
        ScheduleInterval.minutesOf(isStart ? interval.start : interval.end);

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: Theme.of(ctx)
                .colorScheme
                .copyWith(primary: AppColors.primary.primary),
          ),
          child: child!,
        ),
      ),
    );
    if (picked == null || !mounted) return;

    final hhmm = '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    _updateDay(weekday, (d) {
      final list = List.of(d.intervals);
      list[index] = isStart
          ? list[index].copyWith(start: hhmm)
          : list[index].copyWith(end: hhmm);
      return d.copyWith(intervals: list);
    });
  }

  // ---------------------------------------------------------------------------
  // Copiar grade (WhatsApp)
  // ---------------------------------------------------------------------------
  void _copyGrid() {
    final lines = <String>[];
    for (final w in kWeekdayOrder) {
      final day = _dayOf(w);
      if (!day.enabled || day.intervals.isEmpty) continue;
      final ranges =
          day.intervals.map((i) => '${i.start} às ${i.end}').join(' e ');
      lines.add('${kWeekdayLabels[w]}: $ranges');
    }
    if (lines.isEmpty) {
      _snack('Ative pelo menos um dia pra copiar a grade', error: true);
      return;
    }
    Clipboard.setData(ClipboardData(text: lines.join('\n')));
    _snack('Grade copiada — cole no WhatsApp');
  }

  // ---------------------------------------------------------------------------
  // Salvar
  // ---------------------------------------------------------------------------
  Future<void> _save() async {
    // 1. Faixa com término antes do início (nomeia o dia, ordem seg→dom).
    for (final w in kWeekdayOrder) {
      final day = _dayOf(w);
      if (!day.enabled) continue;
      if (day.intervals.any((i) => !i.isValid)) {
        _snack(
          '${kWeekdayLabels[w]} tem uma faixa com término antes do início',
          error: true,
        );
        return;
      }
    }

    // 2. Regra de grade ligada sem nenhum dia ativo.
    if (_enforceWorkingHours && !_week.any((d) => d.enabled)) {
      _snack(
        'Ative pelo menos um dia da semana ou desligue a regra de grade',
        error: true,
      );
      return;
    }

    setState(() => _saving = true);
    HapticFeedback.lightImpact();

    final res = await AppointmentScheduleService.instance.saveScheduleSettings(
      SaveScheduleSettingsPayload(
        enforceWorkingHours: _enforceWorkingHours,
        gapMinutes: _gapMinutes,
        requireInviteConfirmation: _requireInviteConfirmation,
        weeklyHours: _week,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (res.success) {
      HapticFeedback.mediumImpact();
      _snack('Horários salvos');
      Navigator.pop(context, true);
    } else {
      _snack(res.message ?? 'Erro ao salvar horários', error: true);
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor:
            error ? AppColors.status.error : AppColors.status.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Meus horários',
      showBottomNavigation: false,
      showDrawer: false,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _buildErrorState()
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        children: [
                          _sectionHeader(
                            accent: _kIndigo,
                            overline: 'REGRAS DA AGENDA',
                            title: 'Como aceitar novos compromissos',
                          ),
                          const SizedBox(height: 6),
                          _switchRow(
                            accent: _kIndigo,
                            title:
                                'Só aceitar agendamentos dentro da minha grade',
                            helper:
                                'Quem tentar marcar fora dos seus horários será bloqueado',
                            value: _enforceWorkingHours,
                            onChanged: (v) =>
                                setState(() => _enforceWorkingHours = v),
                          ),
                          _hairline(),
                          _buildGapPicker(),
                          _hairline(),
                          _switchRow(
                            accent: _kIndigo,
                            title:
                                'Quero confirmar os compromissos marcados na minha agenda',
                            helper:
                                'Desligado: quem marcar na sua agenda agenda direto. '
                                'Ligado: vira convite pendente pra você aceitar.',
                            value: _requireInviteConfirmation,
                            onChanged: (v) => setState(
                                () => _requireInviteConfirmation = v),
                          ),
                          const SizedBox(height: 24),
                          _sectionHeader(
                            accent: _kGreen,
                            overline: 'GRADE SEMANAL',
                            title: 'Dias e horários de atendimento',
                            action: TextButton.icon(
                              onPressed: _copyGrid,
                              style: TextButton.styleFrom(
                                // Trap conhecida: o tema global pinta
                                // TextButton de vermelho — forçar a cor.
                                foregroundColor: _kGreen,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              icon: const Icon(Icons.copy_rounded, size: 14),
                              label: const Text(
                                'Copiar grade',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildWeekList(),
                        ],
                      ),
                    ),
                    _buildFooter(),
                  ],
                ),
    );
  }

  // ---------------------------------------------------------------------------
  // Estados de carga
  // ---------------------------------------------------------------------------
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: 40,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
            const SizedBox(height: 14),
            Text(
              'Não deu pra carregar seus horários',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: ThemeHelpers.textColor(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _loadError ?? '',
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: ThemeHelpers.textSecondaryColor(context),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _load,
              style: OutlinedButton.styleFrom(
                foregroundColor: ThemeHelpers.textColor(context),
                side: BorderSide(color: ThemeHelpers.borderColor(context)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text(
                'Tentar novamente',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header de seção flush (barrinha + overline + título)
  // ---------------------------------------------------------------------------
  Widget _sectionHeader({
    required Color accent,
    required String overline,
    required String title,
    Widget? action,
  }) {
    return Row(
      children: [
        Container(
          width: 3.5,
          height: 24,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                overline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: accent,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
            ],
          ),
        ),
        if (action != null) ...[
          const SizedBox(width: 8),
          action,
        ],
      ],
    );
  }

  Widget _hairline() {
    return Container(
      height: 1,
      color: ThemeHelpers.borderColor(context).withValues(alpha: 0.65),
    );
  }

  // ---------------------------------------------------------------------------
  // Seção 1 — regras
  // ---------------------------------------------------------------------------
  Widget _switchRow({
    required Color accent,
    required String title,
    required String helper,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    helper,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Switch.adaptive(
              value: value,
              activeColor: accent,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGapPicker() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'INTERVALO MÍNIMO ENTRE COMPROMISSOS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in kGapOptions) _gapChip(option),
            ],
          ),
        ],
      ),
    );
  }

  Widget _gapChip(int option) {
    final selected = _gapMinutes == option;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () {
        if (selected) return;
        HapticFeedback.selectionClick();
        setState(() => _gapMinutes = option);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? _kIndigo : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? _kIndigo : ThemeHelpers.borderColor(context),
          ),
        ),
        child: Text(
          formatGapLabel(option),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected
                ? Colors.white
                : ThemeHelpers.textSecondaryColor(context),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Seção 2 — grade semanal
  // ---------------------------------------------------------------------------
  Widget _buildWeekList() {
    final children = <Widget>[];
    for (var i = 0; i < kWeekdayOrder.length; i++) {
      if (i > 0) children.add(_hairline());
      children.add(_dayBlock(_dayOf(kWeekdayOrder[i])));
    }
    return Column(children: children);
  }

  Widget _dayBlock(ScheduleDay day) {
    final enabled = day.enabled;
    final isWorkday = day.weekday >= 1 && day.weekday <= 5;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Transform.scale(
                scale: 0.8,
                alignment: Alignment.centerLeft,
                child: Switch.adaptive(
                  value: enabled,
                  activeColor: _kGreen,
                  onChanged: (v) => _toggleDay(day.weekday, v),
                ),
              ),
              Expanded(
                child: Text(
                  kWeekdayLabels[day.weekday] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: enabled
                        ? ThemeHelpers.textColor(context)
                        : ThemeHelpers.textSecondaryColor(context)
                            .withValues(alpha: 0.6),
                  ),
                ),
              ),
              if (enabled && isWorkday)
                IconButton(
                  onPressed: () => _applyToWorkdays(day.weekday),
                  tooltip: 'Aplicar aos dias úteis',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 34, minHeight: 34),
                  icon: Icon(
                    Icons.layers_rounded,
                    size: 16,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
            ],
          ),
          if (enabled) ...[
            for (var i = 0; i < day.intervals.length; i++)
              _intervalRow(day, i),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _addInterval(day.weekday),
                style: TextButton.styleFrom(
                  // Tema global pinta TextButton de vermelho — forçar verde.
                  foregroundColor: _kGreen,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text(
                  'Adicionar faixa',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  Widget _intervalRow(ScheduleDay day, int index) {
    final interval = day.intervals[index];
    final invalid = !interval.isValid;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: _timeTile(
              interval.start,
              onTap: () =>
                  _pickIntervalTime(day.weekday, index, isStart: true),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '–',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
          ),
          Expanded(
            child: _timeTile(
              interval.end,
              onTap: () =>
                  _pickIntervalTime(day.weekday, index, isStart: false),
              // Feedback vivo: término antes do início acende a borda.
              borderColor:
                  invalid ? _kDanger.withValues(alpha: 0.55) : null,
            ),
          ),
          const SizedBox(width: 2),
          IconButton(
            onPressed: () => _removeInterval(day.weekday, index),
            tooltip: 'Remover faixa',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: const Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: _kDanger,
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeTile(
    String value, {
    required VoidCallback onTap,
    Color? borderColor,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor ?? ThemeHelpers.borderColor(context),
          ),
        ),
        child: Text(
          value,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: ThemeHelpers.textColor(context),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Rodapé fixo
  // ---------------------------------------------------------------------------
  Widget _buildFooter() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.8),
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: _kSaveGreen,
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  _kSaveGreen.withValues(alpha: 0.45),
              disabledForegroundColor:
                  Colors.white.withValues(alpha: 0.9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'Salvar horários',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.1,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
