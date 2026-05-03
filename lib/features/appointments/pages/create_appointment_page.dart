import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../controllers/appointment_controller.dart';
import '../models/appointment_model.dart';
import '../widgets/appointment_helpers.dart';

/// Página premium de criação de agendamento — possui pré-visualização
/// em tempo real, atalhos inteligentes (hoje/amanhã, durações pré-definidas),
/// e formulário em seções com hierarquia clara.
class CreateAppointmentPage extends StatefulWidget {
  final DateTime? initialStartDate;
  final DateTime? initialEndDate;

  const CreateAppointmentPage({
    super.key,
    this.initialStartDate,
    this.initialEndDate,
  });

  @override
  State<CreateAppointmentPage> createState() => _CreateAppointmentPageState();
}

class _CreateAppointmentPageState extends State<CreateAppointmentPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();

  AppointmentType _type = AppointmentType.visit;
  AppointmentVisibility _visibility = AppointmentVisibility.private;
  String _color = '#D32F2F';
  late DateTime _start;
  late DateTime _end;
  bool _allDay = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = widget.initialStartDate ??
        DateTime(now.year, now.month, now.day, now.hour + 1, 0);
    _end = widget.initialEndDate ?? _start.add(const Duration(hours: 1));
    _titleController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Validations
  // ---------------------------------------------------------------------------
  String? _dateError() {
    if (_end.isBefore(_start) || _end.isAtSameMomentAs(_start)) {
      return 'O término deve ser após o início';
    }
    return null;
  }

  bool get _formValid {
    if (_titleController.text.trim().isEmpty) return false;
    if (_descriptionController.text.length > 300) return false;
    if (_notesController.text.length > 300) return false;
    if (_dateError() != null) return false;
    return true;
  }

  // ---------------------------------------------------------------------------
  // Date / Time helpers
  // ---------------------------------------------------------------------------
  Future<void> _pickDate({required bool isStart}) async {
    final base = isStart ? _start : _end;
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      locale: const Locale('pt', 'BR'),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx)
              .colorScheme
              .copyWith(primary: AppColors.primary.primary),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        final duration = _end.difference(_start);
        _start = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _start.hour,
          _start.minute,
        );
        _end = _start.add(duration.isNegative ? const Duration(hours: 1) : duration);
      } else {
        _end = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _end.hour,
          _end.minute,
        );
      }
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final base = isStart ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx)
              .colorScheme
              .copyWith(primary: AppColors.primary.primary),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        final duration = _end.difference(_start);
        _start = DateTime(
          _start.year,
          _start.month,
          _start.day,
          picked.hour,
          picked.minute,
        );
        _end = _start.add(duration.isNegative ? const Duration(hours: 1) : duration);
      } else {
        _end = DateTime(
          _end.year,
          _end.month,
          _end.day,
          picked.hour,
          picked.minute,
        );
      }
    });
  }

  void _quickDate(DateTime date) {
    setState(() {
      final duration = _end.difference(_start);
      _start = DateTime(
        date.year,
        date.month,
        date.day,
        _allDay ? 0 : _start.hour,
        _allDay ? 0 : _start.minute,
      );
      _end = _start.add(
        duration.isNegative || duration.inMinutes == 0
            ? const Duration(hours: 1)
            : duration,
      );
    });
  }

  void _quickDuration(Duration d) {
    setState(() {
      _end = _start.add(d);
    });
  }

  void _toggleAllDay(bool value) {
    setState(() {
      _allDay = value;
      if (value) {
        _start = DateTime(_start.year, _start.month, _start.day, 0, 0);
        _end = DateTime(_start.year, _start.month, _start.day, 23, 59);
      } else {
        final now = DateTime.now();
        _start = DateTime(_start.year, _start.month, _start.day,
            now.hour + 1, 0);
        _end = _start.add(const Duration(hours: 1));
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------------------
  Future<void> _save() async {
    if (!_formValid) {
      _formKey.currentState?.validate();
      return;
    }

    setState(() => _saving = true);
    HapticFeedback.lightImpact();

    final ctrl = context.read<AppointmentController>();
    final ok = await ctrl.createAppointment(
      CreateAppointmentData(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        type: _type,
        visibility: _visibility,
        startDate: _start,
        endDate: _end,
        location: _locationController.text.trim().isEmpty
            ? null
            : _locationController.text.trim(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        color: _color,
      ),
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (ok) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.status.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white),
              SizedBox(width: 10),
              Text('Agendamento criado com sucesso'),
            ],
          ),
        ),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.status.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          content: Text(ctrl.error ?? 'Erro ao criar agendamento'),
        ),
      );
    }
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Novo agendamento',
      showBottomNavigation: false,
      showDrawer: false,
      body: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
              children: [
                _buildLivePreview(theme),
                const SizedBox(height: 18),
                _buildSection(
                  theme,
                  icon: Icons.title_rounded,
                  title: 'Identificação',
                  child: Column(
                    children: [
                      CustomTextField(
                        label: 'Título *',
                        hint: 'Ex.: Visita ao apartamento de João',
                        controller: _titleController,
                        textInputAction: TextInputAction.next,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty)
                                ? 'Informe um título'
                                : null,
                      ),
                      const SizedBox(height: 14),
                      CustomTextField(
                        label: 'Descrição',
                        hint: 'O que precisa ser feito? Quem participa?',
                        controller: _descriptionController,
                        maxLines: 3,
                        maxLength: 300,
                        validator: (v) =>
                            (v != null && v.length > 300)
                                ? 'Máximo de 300 caracteres'
                                : null,
                      ),
                      _CharCounter(
                        current: _descriptionController.text.length,
                        max: 300,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _buildSection(
                  theme,
                  icon: Icons.category_rounded,
                  title: 'Tipo de compromisso',
                  subtitle: 'Define o ícone exibido na agenda',
                  child: _buildTypeGrid(theme),
                ),
                const SizedBox(height: 18),
                _buildSection(
                  theme,
                  icon: Icons.event_rounded,
                  title: 'Quando?',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Dia inteiro',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Switch.adaptive(
                        activeColor: AppColors.primary.primary,
                        value: _allDay,
                        onChanged: _toggleAllDay,
                      ),
                    ],
                  ),
                  child: _buildWhenSection(theme),
                ),
                const SizedBox(height: 18),
                _buildSection(
                  theme,
                  icon: Icons.place_rounded,
                  title: 'Localização',
                  subtitle: 'Endereço, link da videochamada, etc.',
                  child: CustomTextField(
                    hint: 'Ex.: Av. Paulista, 1000 — sala 12',
                    controller: _locationController,
                    prefixIcon: Icon(
                      Icons.location_on_outlined,
                      color: AppColors.primary.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _buildSection(
                  theme,
                  icon: Icons.sticky_note_2_rounded,
                  title: 'Observações',
                  subtitle: 'Anotações privadas que só você verá',
                  child: Column(
                    children: [
                      CustomTextField(
                        controller: _notesController,
                        maxLines: 4,
                        maxLength: 300,
                        hint: 'Documentos a levar, contexto do cliente...',
                        validator: (v) =>
                            (v != null && v.length > 300)
                                ? 'Máximo de 300 caracteres'
                                : null,
                      ),
                      _CharCounter(
                        current: _notesController.text.length,
                        max: 300,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _buildSection(
                  theme,
                  icon: Icons.visibility_rounded,
                  title: 'Visibilidade',
                  child: _buildVisibilityList(theme),
                ),
                const SizedBox(height: 18),
                _buildSection(
                  theme,
                  icon: Icons.palette_rounded,
                  title: 'Cor de identificação',
                  subtitle: 'Aparece no marcador do calendário e nos cards',
                  child: _buildColorPalette(theme),
                ),
                const SizedBox(height: 8),
              ],
            ),
            // Sticky bottom bar
            Align(
              alignment: Alignment.bottomCenter,
              child: _buildBottomBar(theme),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SECTION WRAPPER
  // ---------------------------------------------------------------------------
  Widget _buildSection(
    ThemeData theme, {
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ThemeHelpers.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon,
                    color: AppColors.primary.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // LIVE PREVIEW (Hero card showing how the appointment will look)
  // ---------------------------------------------------------------------------
  Widget _buildLivePreview(ThemeData theme) {
    final accent = AppointmentVisuals.colorFromHex(_color);
    final hasTitle = _titleController.text.trim().isNotEmpty;
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withOpacity(isDark ? 0.18 : 0.12),
            accent.withOpacity(isDark ? 0.05 : 0.03),
          ],
        ),
        border: Border.all(color: accent.withOpacity(0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  AppointmentVisuals.iconFor(_type),
                  color: accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PRÉ-VISUALIZAÇÃO',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        fontSize: 10.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasTitle
                          ? _titleController.text.trim()
                          : 'Título do agendamento',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: hasTitle
                            ? ThemeHelpers.textColor(context)
                            : ThemeHelpers.textSecondaryColor(context)
                                .withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _previewMeta(
                Icons.event_rounded,
                AppointmentVisuals.formattedShortDate(_start),
                accent,
              ),
              _previewMeta(
                Icons.schedule_rounded,
                _allDay
                    ? 'Dia inteiro'
                    : '${AppointmentVisuals.formattedTime(_start)} – ${AppointmentVisuals.formattedTime(_end)}',
                accent,
              ),
              _previewMeta(
                Icons.timer_outlined,
                AppointmentVisuals.durationLabel(_start, _end),
                accent,
              ),
              if (_locationController.text.trim().isNotEmpty)
                _previewMeta(
                  Icons.place_outlined,
                  _locationController.text.trim(),
                  accent,
                  maxWidth: 200,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _previewMeta(
    IconData icon,
    String text,
    Color color, {
    double? maxWidth,
  }) {
    final widget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ),
      ],
    );
    if (maxWidth != null) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: widget,
      );
    }
    return widget;
  }

  // ---------------------------------------------------------------------------
  // TYPE GRID
  // ---------------------------------------------------------------------------
  Widget _buildTypeGrid(ThemeData theme) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: AppointmentType.values.map((t) {
        final selected = _type == t;
        final color = AppColors.primary.primary;
        return InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _type = t);
          },
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? color.withOpacity(0.10) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? color.withOpacity(0.55)
                    : ThemeHelpers.borderColor(context),
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  AppointmentVisuals.iconFor(t),
                  size: 18,
                  color: selected
                      ? color
                      : ThemeHelpers.textSecondaryColor(context),
                ),
                const SizedBox(width: 8),
                Text(
                  t.label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected
                        ? color
                        : ThemeHelpers.textColor(context),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // WHEN SECTION (datas + horas + atalhos)
  // ---------------------------------------------------------------------------
  Widget _buildWhenSection(ThemeData theme) {
    final today = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));
    final monday = today.add(Duration(days: (8 - today.weekday) % 7 == 0 ? 7 : (8 - today.weekday) % 7));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _quickPill(
                  theme, 'Hoje', _isSameDay(_start, today), () => _quickDate(today)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _quickPill(theme, 'Amanhã', _isSameDay(_start, tomorrow),
                  () => _quickDate(tomorrow)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _quickPill(
                  theme, 'Próx. Seg', _isSameDay(_start, monday), () => _quickDate(monday)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _dateTimeTile(
          theme,
          label: 'Início',
          date: _start,
          onPickDate: () => _pickDate(isStart: true),
          onPickTime: _allDay ? null : () => _pickTime(isStart: true),
        ),
        const SizedBox(height: 10),
        _dateTimeTile(
          theme,
          label: 'Término',
          date: _end,
          onPickDate: () => _pickDate(isStart: false),
          onPickTime: _allDay ? null : () => _pickTime(isStart: false),
        ),
        if (!_allDay) ...[
          const SizedBox(height: 14),
          Text(
            'DURAÇÃO RÁPIDA',
            style: theme.textTheme.labelSmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
              fontSize: 10.5,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _durationChip(theme, '15 min', const Duration(minutes: 15)),
              _durationChip(theme, '30 min', const Duration(minutes: 30)),
              _durationChip(theme, '45 min', const Duration(minutes: 45)),
              _durationChip(theme, '1 h', const Duration(hours: 1)),
              _durationChip(theme, '1h 30', const Duration(hours: 1, minutes: 30)),
              _durationChip(theme, '2 h', const Duration(hours: 2)),
              _durationChip(theme, '4 h', const Duration(hours: 4)),
            ],
          ),
        ],
        if (_dateError() != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.status.error.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.status.error.withOpacity(0.32)),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded,
                    color: AppColors.status.error, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _dateError()!,
                    style: TextStyle(
                      color: AppColors.status.error,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ]
      ],
    );
  }

  Widget _quickPill(
    ThemeData theme,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    final primary = AppColors.primary.primary;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? primary.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? primary.withOpacity(0.50)
                : ThemeHelpers.borderColor(context),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? primary : ThemeHelpers.textColor(context),
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _durationChip(ThemeData theme, String label, Duration d) {
    final selected = _end.difference(_start) == d;
    final primary = AppColors.primary.primary;
    return InkWell(
      onTap: () => _quickDuration(d),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? primary.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? primary.withOpacity(0.55)
                : ThemeHelpers.borderColor(context),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? primary : ThemeHelpers.textColor(context),
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }

  Widget _dateTimeTile(
    ThemeData theme, {
    required String label,
    required DateTime date,
    required VoidCallback onPickDate,
    VoidCallback? onPickTime,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.03)
            : AppColors.background.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ThemeHelpers.borderColor(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            alignment: Alignment.center,
            child: Text(
              label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
                fontWeight: FontWeight.w800,
                fontSize: 9.5,
                letterSpacing: 1.0,
              ),
            ),
          ),
          Container(
            width: 1,
            height: 28,
            color: ThemeHelpers.borderColor(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: onPickDate,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Row(
                  children: [
                    Icon(Icons.event_rounded,
                        size: 16, color: AppColors.primary.primary),
                    const SizedBox(width: 6),
                    Text(
                      AppointmentVisuals.formattedShortDate(date),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (onPickTime != null) ...[
            Container(
              width: 1,
              height: 28,
              color: ThemeHelpers.borderColor(context),
            ),
            const SizedBox(width: 10),
            InkWell(
              onTap: onPickTime,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Row(
                  children: [
                    Icon(Icons.schedule_rounded,
                        size: 16, color: AppColors.primary.primary),
                    const SizedBox(width: 6),
                    Text(
                      AppointmentVisuals.formattedTime(date),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
          ]
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // VISIBILITY LIST
  // ---------------------------------------------------------------------------
  Widget _buildVisibilityList(ThemeData theme) {
    return Column(
      children: AppointmentVisibility.values.map((v) {
        final selected = _visibility == v;
        final isLast = v == AppointmentVisibility.values.last;
        return Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _visibility = v);
            },
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.primary.withOpacity(0.06)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? AppColors.primary.primary.withOpacity(0.55)
                      : ThemeHelpers.borderColor(context),
                  width: selected ? 1.4 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.primary.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      AppointmentVisuals.iconForVisibility(v),
                      color: AppColors.primary.primary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          v.label,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          AppointmentVisuals.visibilityDescription(v),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected
                          ? AppColors.primary.primary
                          : Colors.transparent,
                      border: Border.all(
                        color: selected
                            ? AppColors.primary.primary
                            : ThemeHelpers.borderColor(context),
                        width: selected ? 1.5 : 1.2,
                      ),
                    ),
                    child: selected
                        ? const Icon(Icons.check_rounded,
                            color: Colors.white, size: 14)
                        : null,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // COLOR PALETTE
  // ---------------------------------------------------------------------------
  Widget _buildColorPalette(ThemeData theme) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: AppointmentVisuals.palette.map((opt) {
        final selected = _color == opt.hex;
        final color = opt.color;
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _color = opt.hex);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.45),
                  blurRadius: selected ? 12 : 6,
                  spreadRadius: selected ? 2 : 0,
                  offset: const Offset(0, 3),
                ),
              ],
              border: Border.all(
                color: selected
                    ? Colors.white
                    : color.withOpacity(0.0),
                width: selected ? 3 : 0,
              ),
            ),
            child: selected
                ? const Icon(Icons.check_rounded,
                    color: Colors.white, size: 20)
                : null,
          ),
        );
      }).toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // BOTTOM BAR
  // ---------------------------------------------------------------------------
  Widget _buildBottomBar(ThemeData theme) {
    final primary = AppColors.primary.primary;
    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor.withOpacity(0.96),
        border: Border(
          top: BorderSide(color: ThemeHelpers.borderColor(context)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Cancelar'),
              onPressed: _saving ? null : () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(_saving ? 'Salvando…' : 'Criar agendamento'),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _formValid && !_saving ? primary : null,
              ),
              onPressed: _formValid && !_saving ? _save : null,
            ),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Contador discreto de caracteres para textos com limite.
class _CharCounter extends StatelessWidget {
  final int current;
  final int max;
  const _CharCounter({required this.current, required this.max});

  @override
  Widget build(BuildContext context) {
    final c = current > max
        ? AppColors.status.error
        : ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, right: 4),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          '$current/$max',
          style: TextStyle(
            color: c,
            fontWeight: FontWeight.w600,
            fontSize: 11.5,
          ),
        ),
      ),
    );
  }
}
