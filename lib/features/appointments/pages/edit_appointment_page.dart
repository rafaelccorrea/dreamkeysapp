import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../controllers/appointment_controller.dart';
import '../models/appointment_model.dart';
import '../models/appointment_tags.dart';
import '../services/appointment_schedule_service.dart';
import '../widgets/appointment_helpers.dart';

// ─── Novo modelo de agenda (paridade com EditAppointmentPage do web) ─────────
const Color _kGuestsAccent = Color(0xFF4A90E2); // seção CONVIDADOS
const Color _kTagsAccent = Color(0xFF64748B); // seção ETIQUETAS
const Color _kApplyGreen = Color(0xFF059669); // botão Aplicar do sheet
const Color _kFreeGreen = Color(0xFF10B981); // "horário livre para todos"
const Color _kOverlapRed = Color(0xFFDC2626); // conflito de agenda
const Color _kScheduleAmber = Color(0xFFE6B84C); // fora da grade / sem gap
const String _kManualTimeChoice = '__manual__';

/// Página premium de edição de agendamento — espelha a UX da criação,
/// mas adiciona controle de Status (fluxo do compromisso).
class EditAppointmentPage extends StatefulWidget {
  final String appointmentId;

  const EditAppointmentPage({super.key, required this.appointmentId});

  @override
  State<EditAppointmentPage> createState() => _EditAppointmentPageState();
}

class _EditAppointmentPageState extends State<EditAppointmentPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();

  AppointmentType _type = AppointmentType.visit;
  AppointmentStatus _status = AppointmentStatus.scheduled;
  AppointmentVisibility _visibility = AppointmentVisibility.private;
  String _color = '#D32F2F';
  DateTime? _start;
  DateTime? _end;
  bool _allDay = false;
  bool _saving = false;
  bool _booting = true;

  // ── Novo modelo: convidados, etiquetas e disponibilidade ──
  final List<_MemberOption> _invited = [];
  bool _invitesTouched = false; // só reenviamos convites se o usuário mexeu
  List<_MemberOption>? _membersCache; // membros da empresa, carregados 1x
  final Set<String> _tags = {};
  Timer? _availabilityDebounce;
  int _availabilitySeq = 0; // descarta resposta atrasada de um check antigo
  bool _checkingAvailability = false;
  bool _availabilityCheckFailed = false;
  AvailabilityCheckResult? _availability;
  bool _loadingSlots = false;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    final ctrl = context.read<AppointmentController>();
    await ctrl.loadAppointmentById(widget.appointmentId);
    final a = ctrl.selectedAppointment;
    if (a != null) {
      _titleController.text = a.title;
      _descriptionController.text = a.description ?? '';
      _locationController.text = a.location ?? '';
      _notesController.text = a.notes ?? '';
      _type = a.type;
      _status = a.status;
      _visibility = a.visibility;
      _color = a.color;
      _start = a.startDate;
      _end = a.endDate;
      _allDay = _isAllDay(a.startDate, a.endDate);
      // Etiquetas existentes pré-selecionadas.
      _tags
        ..clear()
        ..addAll(a.tags);
      // Convidados atuais = convites vivos (pendentes/aceitos).
      final invites = a.invites;
      if (invites != null) {
        for (final inv in invites) {
          if (inv.status != InviteStatus.pending &&
              inv.status != InviteStatus.accepted) {
            continue;
          }
          if (inv.invitedUserId.isEmpty) continue;
          if (_invited.any((m) => m.id == inv.invitedUserId)) continue;
          final name = inv.invitedUser?['name']?.toString() ?? '';
          _invited.add(
            _MemberOption(
              id: inv.invitedUserId,
              name: name.isEmpty ? 'Convidado' : name,
            ),
          );
        }
      }
    }
    if (mounted) {
      setState(() => _booting = false);
      if (a != null) {
        // Check inicial com o horário carregado do compromisso.
        _scheduleAvailabilityCheck();
      }
    }
  }

  bool _isAllDay(DateTime s, DateTime e) {
    return s.hour == 0 &&
        s.minute == 0 &&
        e.day == s.day &&
        e.hour == 23 &&
        e.minute >= 58;
  }

  @override
  void dispose() {
    _availabilityDebounce?.cancel();
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
    if (_start == null || _end == null) return null;
    if (_end!.isBefore(_start!) || _end!.isAtSameMomentAs(_start!)) {
      return 'O término deve ser após o início';
    }
    return null;
  }

  bool get _formValid {
    if (_titleController.text.trim().isEmpty) return false;
    if (_descriptionController.text.length > 300) return false;
    if (_notesController.text.length > 300) return false;
    if (_start == null || _end == null) return false;
    if (_dateError() != null) return false;
    // Novo modelo: não salva com o check em andamento nem com alguém
    // indisponível. Erro de rede NÃO bloqueia (só avisa).
    if (_checkingAvailability) return false;
    final availability = _availability;
    if (availability != null && availability.unavailable.isNotEmpty) {
      return false;
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // Date pickers
  // ---------------------------------------------------------------------------
  Future<void> _pickDate({required bool isStart}) async {
    final base = isStart ? _start! : _end!;
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(DateTime.now().year - 1),
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
        final duration = _end!.difference(_start!);
        _start = DateTime(picked.year, picked.month, picked.day,
            _start!.hour, _start!.minute);
        _end = _start!.add(duration.isNegative ? const Duration(hours: 1) : duration);
      } else {
        _end = DateTime(picked.year, picked.month, picked.day,
            _end!.hour, _end!.minute);
      }
    });
    _scheduleAvailabilityCheck();
  }

  Future<void> _pickTime({required bool isStart}) async {
    final base = isStart ? _start! : _end!;
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
        final duration = _end!.difference(_start!);
        _start = DateTime(_start!.year, _start!.month, _start!.day,
            picked.hour, picked.minute);
        _end = _start!.add(duration.isNegative ? const Duration(hours: 1) : duration);
      } else {
        _end = DateTime(_end!.year, _end!.month, _end!.day,
            picked.hour, picked.minute);
      }
    });
    _scheduleAvailabilityCheck();
  }

  void _quickDuration(Duration d) {
    setState(() => _end = _start!.add(d));
    _scheduleAvailabilityCheck();
  }

  void _toggleAllDay(bool value) {
    setState(() {
      _allDay = value;
      if (value) {
        _start = DateTime(_start!.year, _start!.month, _start!.day, 0, 0);
        _end = DateTime(_start!.year, _start!.month, _start!.day, 23, 59);
      } else {
        final now = DateTime.now();
        _start = DateTime(_start!.year, _start!.month, _start!.day,
            now.hour + 1, 0);
        _end = _start!.add(const Duration(hours: 1));
      }
    });
    _scheduleAvailabilityCheck();
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
    final ok = await ctrl.updateAppointment(
      widget.appointmentId,
      UpdateAppointmentData(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        type: _type,
        status: _status,
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
        tags: _selectedTags(),
        // Convidados só entram no PUT se o usuário mexeu na lista — evita
        // reconciliar (e cancelar) convites por engano quando nada mudou.
        inviteUserIds:
            _invitesTouched ? _invited.map((m) => m.id).toList() : null,
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
              Text('Alterações salvas'),
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
          content: Text(ctrl.error ?? 'Erro ao atualizar agendamento'),
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

    if (_booting) {
      return AppScaffold(
        title: 'Editar agendamento',
        showDrawer: false,
        showBottomNavigation: false,
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
          children: [
            SkeletonBox(height: 110, borderRadius: 22),
            const SizedBox(height: 18),
            for (int i = 0; i < 4; i++) ...[
              SkeletonBox(height: 120, borderRadius: 18),
              const SizedBox(height: 14),
            ],
          ],
        ),
      );
    }

    return AppScaffold(
      title: 'Editar agendamento',
      showDrawer: false,
      showBottomNavigation: false,
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
                        controller: _descriptionController,
                        maxLines: 3,
                        maxLength: 300,
                        validator: (v) =>
                            (v != null && v.length > 300)
                                ? 'Máximo de 300 caracteres'
                                : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _buildSection(
                  theme,
                  icon: Icons.flag_rounded,
                  title: 'Status do compromisso',
                  subtitle: 'Avance pelo fluxo conforme acontece',
                  child: _buildStatusFlow(theme),
                ),
                const SizedBox(height: 18),
                _buildSection(
                  theme,
                  icon: Icons.category_rounded,
                  title: 'Tipo',
                  child: _buildTypeGrid(theme),
                ),
                const SizedBox(height: 18),
                _buildTagsSection(theme),
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
                  child: _buildWhen(theme),
                ),
                const SizedBox(height: 18),
                _buildSection(
                  theme,
                  icon: Icons.place_rounded,
                  title: 'Localização',
                  child: CustomTextField(
                    hint: 'Ex.: Av. Paulista, 1000',
                    controller: _locationController,
                    prefixIcon: Icon(
                      Icons.location_on_outlined,
                      color: AppColors.primary.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _buildGuestsSection(theme),
                const SizedBox(height: 18),
                _buildSection(
                  theme,
                  icon: Icons.sticky_note_2_rounded,
                  title: 'Observações',
                  child: CustomTextField(
                    controller: _notesController,
                    maxLines: 4,
                    maxLength: 300,
                    validator: (v) =>
                        (v != null && v.length > 300)
                            ? 'Máximo de 300 caracteres'
                            : null,
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
                  title: 'Cor',
                  child: _buildColorPalette(theme),
                ),
                const SizedBox(height: 8),
              ],
            ),
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
  // SECTION
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
  // LIVE PREVIEW
  // ---------------------------------------------------------------------------
  Widget _buildLivePreview(ThemeData theme) {
    final accent = AppointmentVisuals.colorFromHex(_color);
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
                      'EDITANDO',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        fontSize: 10.5,
                      ),
                    ),
                    Text(
                      _titleController.text.trim().isEmpty
                          ? 'Sem título'
                          : _titleController.text.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
              _statusPill(theme, _status),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _previewMeta(
                Icons.event_rounded,
                AppointmentVisuals.formattedShortDate(_start ?? DateTime.now()),
                accent,
              ),
              _previewMeta(
                Icons.schedule_rounded,
                _allDay
                    ? 'Dia inteiro'
                    : '${AppointmentVisuals.formattedTime(_start ?? DateTime.now())} – ${AppointmentVisuals.formattedTime(_end ?? DateTime.now())}',
                accent,
              ),
              _previewMeta(
                Icons.timer_outlined,
                AppointmentVisuals.durationLabel(
                  _start ?? DateTime.now(),
                  _end ?? DateTime.now(),
                ),
                accent,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _previewMeta(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
      ],
    );
  }

  Widget _statusPill(ThemeData theme, AppointmentStatus s) {
    final color = AppointmentVisuals.colorForStatus(s);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppointmentVisuals.iconForStatus(s), size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            s.label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // STATUS FLOW (chips coloridos por status)
  // ---------------------------------------------------------------------------
  Widget _buildStatusFlow(ThemeData theme) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: AppointmentStatus.values.map((s) {
        final selected = _status == s;
        final color = AppointmentVisuals.colorForStatus(s);
        return InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _status = s);
          },
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color:
                  selected ? color.withOpacity(0.14) : Colors.transparent,
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
                  AppointmentVisuals.iconForStatus(s),
                  size: 16,
                  color: selected
                      ? color
                      : ThemeHelpers.textSecondaryColor(context),
                ),
                const SizedBox(width: 6),
                Text(
                  s.label,
                  style: TextStyle(
                    color: selected ? color : ThemeHelpers.textColor(context),
                    fontWeight:
                        selected ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 13,
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
  // TYPE / WHEN / VIS / COLOR (clones from create)
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
                    fontWeight:
                        selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? color : ThemeHelpers.textColor(context),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildWhen(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _dateTimeTile(
          theme,
          label: 'Início',
          date: _start ?? DateTime.now(),
          onPickDate: () => _pickDate(isStart: true),
          // Início passa pelos slots reais do dia (picker manual é fallback).
          onPickTime: _allDay ? null : _pickStartTime,
        ),
        const SizedBox(height: 10),
        _dateTimeTile(
          theme,
          label: 'Término',
          date: _end ?? DateTime.now(),
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
        ],
        _buildAvailabilityFeedback(theme),
      ],
    );
  }

  Widget _durationChip(ThemeData theme, String label, Duration d) {
    final selected = _start != null && _end != null && _end!.difference(_start!) == d;
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
          SizedBox(
            width: 48,
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
                color: selected ? Colors.white : color.withOpacity(0.0),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_saveBlockReason != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _checkingAvailability
                        ? Icons.hourglass_top_rounded
                        : Icons.event_busy_rounded,
                    size: 13,
                    color: _blockNoticeColor(context),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _saveBlockReason!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _blockNoticeColor(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Cancelar'),
                  style: TextButton.styleFrom(
                    // Cancelar nunca em vermelho: neutro forçado.
                    foregroundColor: ThemeHelpers.textSecondaryColor(context),
                  ),
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
                      : const Icon(Icons.save_rounded, size: 18),
                  label: Text(_saving ? 'Salvando…' : 'Salvar alterações'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _formValid && !_saving ? primary : null,
                  ),
                  onPressed: _formValid && !_saving ? _save : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DISPONIBILIDADE EM TEMPO REAL (novo modelo de agenda)
  // ---------------------------------------------------------------------------
  /// Reagenda o check com debounce de 350ms sempre que início/fim/convidados
  /// mudarem. O resultado anterior é descartado na hora (ficou obsoleto).
  void _scheduleAvailabilityCheck() {
    _availabilityDebounce?.cancel();
    setState(() {
      _checkingAvailability = true;
      _availability = null;
      _availabilityCheckFailed = false;
    });
    _availabilityDebounce =
        Timer(const Duration(milliseconds: 350), _runAvailabilityCheck);
  }

  Future<void> _runAvailabilityCheck() async {
    if (!mounted) return;
    final start = _start;
    final end = _end;
    if (start == null || end == null || _dateError() != null) {
      // Par ausente/inválido: o próprio formulário já bloqueia o salvar.
      setState(() {
        _checkingAvailability = false;
        _availability = null;
      });
      return;
    }
    final seq = ++_availabilitySeq;
    final fmt = DateFormat("yyyy-MM-dd'T'HH:mm");
    final res = await AppointmentScheduleService.instance.checkAvailability(
      startDate: fmt.format(start),
      endDate: fmt.format(end),
      userIds: _invited.map((m) => m.id).toList(),
      // OBRIGATÓRIO na edição: sem excluir o próprio compromisso, o par
      // início/fim "colide consigo mesmo" e o check reprovaria sempre.
      excludeAppointmentId: widget.appointmentId,
    );
    if (!mounted || seq != _availabilitySeq) return;
    setState(() {
      _checkingAvailability = false;
      if (res.success && res.data != null) {
        _availability = res.data;
        _availabilityCheckFailed = false;
      } else {
        // Erro de rede/API ≠ "livre": avisa, mas NÃO bloqueia o submit.
        _availability = null;
        _availabilityCheckFailed = true;
      }
    });
  }

  /// Motivo (se houver) de o salvar estar travado pelo check de agenda.
  String? get _saveBlockReason {
    if (_checkingAvailability) return 'Verificando disponibilidade…';
    final availability = _availability;
    if (availability != null && availability.unavailable.isNotEmpty) {
      return 'Há conflito de agenda — ajuste o horário para salvar';
    }
    return null;
  }

  Color _blockNoticeColor(BuildContext context) {
    if (_checkingAvailability) return ThemeHelpers.textSecondaryColor(context);
    return _amberInk(context);
  }

  /// Âmbar com tinta legível nos dois temas (o tom claro some no light).
  Color _amberInk(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? _kScheduleAmber
          : const Color(0xFFA16207);

  Color _issueInk(BuildContext context, String code) =>
      code == 'overlap' ? _kOverlapRed : _amberInk(context);

  /// Extrai 'HH:mm' de uma data "relógio de parede" — defensivo: aceita
  /// 'YYYY-MM-DDTHH:mm', 'HH:mm:ss' ou lixo (retorna null quando não dá).
  String? _wallClockHm(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final t = raw.contains('T') ? raw.split('T').last : raw;
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(t);
    if (match == null) return null;
    return '${match.group(1)!.padLeft(2, '0')}:${match.group(2)}';
  }

  Widget _buildAvailabilityFeedback(ThemeData theme) {
    if (_checkingAvailability) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.6),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Verificando disponibilidade…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (_availabilityCheckFailed) {
      // Aviso neutro: rede falhou, mas o salvar segue liberado.
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: InkWell(
          onTap: _scheduleAvailabilityCheck,
          borderRadius: BorderRadius.circular(8),
          child: Row(
            children: [
              Icon(
                Icons.wifi_off_rounded,
                size: 14,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Não foi possível verificar — tente novamente',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final availability = _availability;
    if (availability == null) return const SizedBox.shrink();
    final unavailable = availability.unavailable;
    if (unavailable.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          children: [
            const Icon(Icons.check_rounded, size: 14, color: _kFreeGreen),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Horário livre para todos',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: _kFreeGreen,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final hasOverlap = unavailable
        .any((r) => r.issues.any((issue) => issue.code == 'overlap'));
    final frame = hasOverlap ? _kOverlapRed : _kScheduleAmber;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: frame.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: frame.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < unavailable.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            ..._issueLines(unavailable[i]),
          ],
        ],
      ),
    );
  }

  List<Widget> _issueLines(AvailabilityUserResult r) {
    final issues = r.issues.isEmpty
        ? const [AvailabilityIssue(code: '', message: 'Indisponível')]
        : r.issues;
    final lines = <Widget>[];
    for (int i = 0; i < issues.length; i++) {
      if (i > 0) lines.add(const SizedBox(height: 4));
      lines.add(_issueLine(r, issues[i]));
    }
    return lines;
  }

  Widget _issueLine(AvailabilityUserResult r, AvailabilityIssue issue) {
    final ink = _issueInk(context, issue.code);
    final start = _wallClockHm(issue.conflictStart);
    final end = _wallClockHm(issue.conflictEnd);
    final title = issue.conflictTitle;
    final String? conflict;
    if (title == null || title.isEmpty) {
      conflict = null;
    } else if (start != null && end != null) {
      conflict = 'conflita com $title ($start–$end)';
    } else {
      conflict = 'conflita com $title';
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1.5),
              child: Icon(
                issue.code == 'overlap'
                    ? Icons.event_busy_rounded
                    : Icons.schedule_rounded,
                size: 13,
                color: ink,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${r.userName} — ${issue.label}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ),
          ],
        ),
        if (conflict != null)
          Padding(
            padding: const EdgeInsets.only(left: 19, top: 2),
            child: Text(
              conflict,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: ink.withValues(alpha: 0.85),
              ),
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // SLOTS DO DIA (hora de início)
  // ---------------------------------------------------------------------------
  /// Abre o sheet "Horários do dia" com os slots reais de início. O
  /// showTimePicker antigo vira fallback (rodapé do sheet ou erro no fetch).
  Future<void> _pickStartTime() async {
    final start = _start;
    final end = _end;
    if (start == null || end == null || _loadingSlots) return;
    setState(() => _loadingSlots = true);
    var duration = end.difference(start).inMinutes;
    if (duration <= 0) duration = 60;
    final res = await AppointmentScheduleService.instance.getDaySlots(
      date: AppointmentVisuals.dayKey(start),
      durationMinutes: duration,
      userIds: _invited.map((m) => m.id).toList(),
      // OBRIGATÓRIO na edição: sem excluir o próprio compromisso, os slots
      // que ele ocupa hoje apareceriam bloqueados por ele mesmo.
      excludeAppointmentId: widget.appointmentId,
    );
    if (!mounted) return;
    setState(() => _loadingSlots = false);
    if (!res.success || res.data == null) {
      // Fetch falhou → direto pro picker manual, sem bloquear ninguém.
      await _pickTime(isStart: true);
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DaySlotsSheet(
        result: res.data!,
        dayLabel: AppointmentVisuals.formattedShortDate(start),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == _kManualTimeChoice) {
      await _pickTime(isStart: true);
      return;
    }
    final parts = choice.split(':');
    final hh = int.tryParse(parts.isNotEmpty ? parts[0] : '');
    final mm = int.tryParse(parts.length > 1 ? parts[1] : '');
    if (hh == null || mm == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      final base = _start!;
      final keep = _end!.difference(base);
      _start = DateTime(base.year, base.month, base.day, hh, mm);
      _end = _start!.add(
        keep.isNegative || keep.inMinutes == 0
            ? const Duration(hours: 1)
            : keep,
      );
    });
    _scheduleAvailabilityCheck();
  }

  // ---------------------------------------------------------------------------
  // SEÇÕES FLUSH: ETIQUETAS + CONVIDADOS
  // ---------------------------------------------------------------------------
  Widget _flushHeader(
    ThemeData theme, {
    required Color accent,
    required String title,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Container(
          width: 3.5,
          height: 14,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              fontSize: 11,
            ),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  /// Tags na ordem do catálogo (+ valores desconhecidos preservados no fim).
  /// Lista vazia É enviada — é assim que o usuário limpa as etiquetas.
  List<String> _selectedTags() {
    final ordered = <String>[
      for (final t in kAppointmentTags)
        if (_tags.contains(t.value)) t.value,
    ];
    for (final v in _tags) {
      if (!ordered.contains(v)) ordered.add(v);
    }
    return ordered;
  }

  Widget _buildTagsSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _flushHeader(theme, accent: _kTagsAccent, title: 'ETIQUETAS'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: kAppointmentTags.map((t) {
            final selected = _tags.contains(t.value);
            return InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  if (selected) {
                    _tags.remove(t.value);
                  } else {
                    _tags.add(t.value);
                  }
                });
              },
              borderRadius: BorderRadius.circular(999),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? t.tone.withValues(alpha: 0.14)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected
                        ? t.tone.withValues(alpha: 0.55)
                        : ThemeHelpers.borderColor(context),
                  ),
                ),
                child: Text(
                  t.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color:
                        selected ? t.tone : ThemeHelpers.textColor(context),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildGuestsSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _flushHeader(
          theme,
          accent: _kGuestsAccent,
          title: 'CONVIDADOS',
          trailing: InkWell(
            onTap: _openInvitePicker,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: _kGuestsAccent.withValues(alpha: 0.45),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person_add_alt_1_rounded,
                    size: 14,
                    color: _kGuestsAccent,
                  ),
                  SizedBox(width: 5),
                  Text(
                    'Adicionar',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _kGuestsAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_invited.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _invited.map((m) => _guestChip(theme, m)).toList(),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          'Cada convidado recebe um convite para aceitar ou recusar.',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
        ),
      ],
    );
  }

  Widget _guestChip(ThemeData theme, _MemberOption m) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: _kGuestsAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _kGuestsAccent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              m.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: ThemeHelpers.textColor(context),
              ),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _invited.removeWhere((e) => e.id == m.id);
                _invitesTouched = true;
              });
              _scheduleAvailabilityCheck();
            },
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(
                Icons.close_rounded,
                size: 14,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Membros da empresa — carregados 1x e cacheados no State.
  /// Retorna null em erro (o sheet diferencia "vazio" de "falhou").
  Future<List<_MemberOption>?> _loadMembers() async {
    final cached = _membersCache;
    if (cached != null) return cached;
    try {
      final res = await ApiService.instance
          .get<dynamic>('/users/company-members/simple');
      if (!res.success) return null;
      final raw = res.data;
      final List<dynamic> list;
      if (raw is List) {
        list = raw;
      } else if (raw is Map && raw['data'] is List) {
        list = raw['data'] as List;
      } else {
        list = const [];
      }
      final parsed = <_MemberOption>[];
      for (final e in list) {
        if (e is! Map) continue;
        final id = e['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final name = e['name']?.toString() ?? '';
        parsed.add(
          _MemberOption(id: id, name: name.isEmpty ? 'Sem nome' : name),
        );
      }
      parsed.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      _membersCache = parsed;
      return parsed;
    } catch (e) {
      debugPrint('❌ [EDIT_APPOINTMENT] company-members: $e');
      return null;
    }
  }

  Future<void> _openInvitePicker() async {
    HapticFeedback.selectionClick();
    final result = await showModalBottomSheet<List<_MemberOption>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _InviteMembersSheet(
        membersFuture: _loadMembers(),
        initialMembers: List<_MemberOption>.of(_invited),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _invited
        ..clear()
        ..addAll(result);
      _invitesTouched = true;
    });
    _scheduleAvailabilityCheck();
  }
}

/// Membro da empresa no formato mínimo do endpoint `company-members/simple`.
class _MemberOption {
  final String id;
  final String name;

  const _MemberOption({required this.id, required this.name});

  String get initial {
    final t = name.trim();
    return t.isEmpty ? '?' : t[0].toUpperCase();
  }
}

/// Bottom sheet multi-select de membros — busca por nome, checkboxes e
/// botão Aplicar verde. Devolve a lista final via `Navigator.pop`.
class _InviteMembersSheet extends StatefulWidget {
  final Future<List<_MemberOption>?> membersFuture;
  final List<_MemberOption> initialMembers;

  const _InviteMembersSheet({
    required this.membersFuture,
    required this.initialMembers,
  });

  @override
  State<_InviteMembersSheet> createState() => _InviteMembersSheetState();
}

class _InviteMembersSheetState extends State<_InviteMembersSheet> {
  late final Set<String> _selected = {
    for (final m in widget.initialMembers) m.id,
  };
  final _searchController = TextEditingController();
  String _query = '';
  List<_MemberOption>? _members;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    widget.membersFuture.then((value) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = value == null;
        _members = value;
      });
    });
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggle(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  void _apply() {
    final members = _members ?? const <_MemberOption>[];
    final byId = <String, _MemberOption>{for (final m in members) m.id: m};
    // Preserva convidados que não estão (mais) na lista de membros.
    for (final m in widget.initialMembers) {
      byId.putIfAbsent(m.id, () => m);
    }
    final picked = <_MemberOption>[
      for (final id in _selected)
        if (byId.containsKey(id)) byId[id]!,
    ];
    picked.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    Navigator.pop(context, picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final members = _members ?? const <_MemberOption>[];
    final filtered = _query.isEmpty
        ? members
        : members
            .where((m) => m.name.toLowerCase().contains(_query))
            .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ThemeHelpers.textSecondaryColor(context)
                      .withValues(alpha: 0.30),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      width: 3.5,
                      height: 14,
                      decoration: BoxDecoration(
                        color: _kGuestsAccent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'CONVIDAR MEMBROS',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: _kGuestsAccent,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    Text(
                      _selected.isEmpty
                          ? 'Ninguém selecionado'
                          : '${_selected.length} selecionado${_selected.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: ThemeHelpers.textColor(context),
                  ),
                  decoration: InputDecoration(
                    hintText: 'Buscar por nome…',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    filled: true,
                    fillColor: ThemeHelpers.backgroundColor(context),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: ThemeHelpers.borderColor(context),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _kGuestsAccent),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(child: _buildList(theme, filtered)),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text(
                      _selected.isEmpty
                          ? 'Aplicar'
                          : 'Aplicar (${_selected.length})',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kApplyGreen,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          _kApplyGreen.withValues(alpha: 0.35),
                      disabledForegroundColor:
                          Colors.white.withValues(alpha: 0.85),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _loading || _failed ? null : _apply,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(ThemeData theme, List<_MemberOption> filtered) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_failed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
        child: Text(
          'Não foi possível carregar os membros — feche e tente de novo.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
        ),
      );
    }
    if (filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
        child: Text(
          'Nenhum membro encontrado.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: filtered.length,
      itemBuilder: (ctx, i) {
        final m = filtered[i];
        final selected = _selected.contains(m.id);
        return InkWell(
          onTap: () => _toggle(m.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kGuestsAccent
                        .withValues(alpha: selected ? 0.18 : 0.10),
                  ),
                  child: Text(
                    m.initial,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _kGuestsAccent,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    m.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight:
                          selected ? FontWeight.w800 : FontWeight.w600,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                ),
                Checkbox(
                  value: selected,
                  activeColor: _kGuestsAccent,
                  side: BorderSide(
                    color: ThemeHelpers.borderColor(context),
                    width: 1.4,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  onChanged: (_) => _toggle(m.id),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Sheet "Horários do dia" — grid dos slots reais de início; slot ocupado
/// aparece riscado com tooltip de quem bloqueia. O rodapé devolve
/// [_kManualTimeChoice] para cair no showTimePicker antigo.
class _DaySlotsSheet extends StatelessWidget {
  final AvailabilitySlotsResult result;
  final String dayLabel;

  const _DaySlotsSheet({required this.result, required this.dayLabel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final hasBlocked = result.slots.any((s) => !s.available);

    return Container(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ThemeHelpers.textSecondaryColor(context)
                    .withValues(alpha: 0.30),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 3.5,
                        height: 14,
                        decoration: BoxDecoration(
                          color: _kGuestsAccent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'HORÁRIOS DO DIA',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: _kGuestsAccent,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$dayLabel · compromisso de ${formatGapLabel(result.durationMinutes)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                  ),
                  if (hasBlocked) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Toque em um horário riscado para ver quem está ocupado.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: ThemeHelpers.textSecondaryColor(context)
                            .withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: result.slots.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          'Nenhum horário disponível na grade deste dia.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                        ),
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: result.slots
                            .map((s) => _slotChip(context, s))
                            .toList(),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: TextButton.icon(
                icon: const Icon(Icons.schedule_rounded, size: 16),
                label: const Text(
                  'Escolher outro horário…',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: ThemeHelpers.textSecondaryColor(context),
                ),
                onPressed: () =>
                    Navigator.pop(context, _kManualTimeChoice),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slotChip(BuildContext context, AvailabilitySlot s) {
    if (s.available) {
      return InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.pop(context, s.time);
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: ThemeHelpers.borderColor(context)),
          ),
          child: Text(
            s.time,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: ThemeHelpers.textColor(context),
            ),
          ),
        ),
      );
    }
    final busy = s.blockedFor.isEmpty
        ? ((s.reason == null || s.reason!.isEmpty)
            ? 'horário indisponível'
            : s.reason!)
        : s.blockedFor.join(', ');
    return Tooltip(
      message: 'Ocupado: $busy',
      triggerMode: TooltipTriggerMode.tap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: ThemeHelpers.textSecondaryColor(context)
              .withValues(alpha: 0.07),
          border: Border.all(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
          ),
        ),
        child: Text(
          s.time,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.lineThrough,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: ThemeHelpers.textSecondaryColor(context)
                .withValues(alpha: 0.60),
          ),
        ),
      ),
    );
  }
}
