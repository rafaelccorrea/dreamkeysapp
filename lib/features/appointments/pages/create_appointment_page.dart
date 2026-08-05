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
import '../controllers/appointment_controller.dart';
import '../models/appointment_model.dart';
import '../models/appointment_tags.dart';
import '../services/appointment_schedule_service.dart';
import '../widgets/appointment_helpers.dart';

// ─── Acentos de seção (página flush: barrinha + overline na cor da seção) ────
const Color _kTypeAccent = Color(0xFF6366F1); // TIPO — índigo
const Color _kSlateAccent = Color(0xFF64748B); // ETIQUETAS / OBSERVAÇÕES
const Color _kWhenAccent = Color(0xFF3FA66B); // QUANDO — verde da agenda
const Color _kGuestsAccent = Color(0xFF4A90E2); // CONVIDADOS
const Color _kPlaceAccent = Color(0xFF0D9488); // LOCAL — teal
const Color _kVisibilityAccent = Color(0xFF8B5CF6); // VISIBILIDADE — violeta

// ─── Cores semânticas (regra do app) ─────────────────────────────────────────
const Color _kApplyGreen = Color(0xFF059669); // confirmar/salvar = verde
const Color _kFreeGreen = Color(0xFF10B981); // "horário livre para todos"
const Color _kOverlapRed = Color(0xFFDC2626); // conflito de agenda
const Color _kScheduleAmber = Color(0xFFE6B84C); // fora da grade / sem gap
const String _kManualTimeChoice = '__manual__';

/// Paleta estável de avatar — 8 tons que funcionam como *tint* nos dois temas.
/// A cor de cada pessoa sai de um hash simples do nome (estável entre builds).
const List<Color> _kAvatarPalette = [
  Color(0xFFE11D48), // rosa
  Color(0xFFD97706), // âmbar queimado
  Color(0xFF059669), // esmeralda
  Color(0xFF0D9488), // teal
  Color(0xFF0284C7), // azul céu
  Color(0xFF6366F1), // índigo
  Color(0xFF8B5CF6), // violeta
  Color(0xFFC026D3), // fúcsia
];

Color _avatarColorFor(String name) {
  var h = 0;
  for (final c in name.trim().toLowerCase().codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return _kAvatarPalette[h % _kAvatarPalette.length];
}

/// Fill terciário para controles "pill" (padrão dos filtros do Kanban).
Color _fieldFillOf(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;

/// Página de criação de agendamento — layout FLUSH (sem card dentro de card):
/// faixa de pré-visualização compacta, seções com header canônico
/// (barrinha + overline + título) separadas por hairline, sheet de horários
/// agrupado por período com indisponíveis riscados e rodapé verde fixo.
class CreateAppointmentPage extends StatefulWidget {
  final DateTime? initialStartDate;
  final DateTime? initialEndDate;
  final String? initialTitle;
  final String? initialLocation;
  final String? propertyId;
  final String? clientId;
  final AppointmentType? initialType;

  const CreateAppointmentPage({
    super.key,
    this.initialStartDate,
    this.initialEndDate,
    this.initialTitle,
    this.initialLocation,
    this.propertyId,
    this.clientId,
    this.initialType,
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
  // Defaults do novo modelo (paridade web): nasce público e azul.
  AppointmentVisibility _visibility = AppointmentVisibility.public;
  String _color = '#3B82F6';
  late DateTime _start;
  late DateTime _end;
  bool _allDay = false;
  bool _saving = false;

  // ── Novo modelo: convidados, etiquetas e disponibilidade ──
  final List<_MemberOption> _invited = [];
  List<_MemberOption>? _membersCache; // membros da empresa, carregados 1x
  final Set<String> _tags = {};
  Timer? _availabilityDebounce;
  int _availabilitySeq = 0; // descarta resposta atrasada de um check antigo
  bool _checkingAvailability = false;
  bool _availabilityCheckFailed = false;
  AvailabilityCheckResult? _availability;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = widget.initialStartDate ??
        DateTime(now.year, now.month, now.day, now.hour + 1, 0);
    _end = widget.initialEndDate ?? _start.add(const Duration(hours: 1));
    if (widget.initialTitle != null && widget.initialTitle!.trim().isNotEmpty) {
      _titleController.text = widget.initialTitle!.trim();
    }
    if (widget.initialLocation != null &&
        widget.initialLocation!.trim().isNotEmpty) {
      _locationController.text = widget.initialLocation!.trim();
    }
    if (widget.initialType != null) {
      _type = widget.initialType!;
    }
    // Preview + contadores + motivo do rodapé acompanham a digitação.
    _titleController.addListener(() => setState(() {}));
    _descriptionController.addListener(() => setState(() {}));
    _locationController.addListener(() => setState(() {}));
    _notesController.addListener(() => setState(() {}));
    // Check inicial do horário default (sem setState: ainda no initState).
    _checkingAvailability = true;
    _availabilityDebounce =
        Timer(const Duration(milliseconds: 350), _runAvailabilityCheck);
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
  // Date / Time helpers
  // ---------------------------------------------------------------------------
  /// Pickers nativos SEMPRE com primária verde + 24h (nada de vermelho
  /// default nem AM/PM).
  Widget _pickerTheme(BuildContext ctx, Widget? child) {
    return MediaQuery(
      data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
      child: Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme:
              Theme.of(ctx).colorScheme.copyWith(primary: _kApplyGreen),
        ),
        child: child!,
      ),
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final base = isStart ? _start : _end;
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      locale: const Locale('pt', 'BR'),
      builder: _pickerTheme,
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
        _end =
            _start.add(duration.isNegative ? const Duration(hours: 1) : duration);
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
    _scheduleAvailabilityCheck();
  }

  Future<void> _pickTime({required bool isStart}) async {
    final base = isStart ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
      builder: _pickerTheme,
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
        _end =
            _start.add(duration.isNegative ? const Duration(hours: 1) : duration);
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
    _scheduleAvailabilityCheck();
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
    _scheduleAvailabilityCheck();
  }

  void _quickDuration(Duration d) {
    setState(() {
      _end = _start.add(d);
    });
    _scheduleAvailabilityCheck();
  }

  void _toggleAllDay(bool value) {
    setState(() {
      _allDay = value;
      if (value) {
        _start = DateTime(_start.year, _start.month, _start.day, 0, 0);
        _end = DateTime(_start.year, _start.month, _start.day, 23, 59);
      } else {
        final now = DateTime.now();
        _start =
            DateTime(_start.year, _start.month, _start.day, now.hour + 1, 0);
        _end = _start.add(const Duration(hours: 1));
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
        tags: _selectedTags(),
        propertyId: widget.propertyId,
        clientId: widget.clientId,
        // Convidados vão no próprio POST — o backend cria os convites junto.
        inviteUserIds:
            _invited.isEmpty ? null : _invited.map((m) => m.id).toList(),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
    final previewAccent = AppointmentVisuals.colorFromHex(_color);

    return AppScaffold(
      title: 'Novo agendamento',
      showBottomNavigation: false,
      showDrawer: false,
      body: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                children: [
                  _buildPreviewStrip(theme, previewAccent),
                  const SizedBox(height: 22),

                  // ── IDENTIFICAÇÃO ─────────────────────────────────────
                  _sectionHeader(
                    accent: AppColors.primary.primary,
                    overline: 'IDENTIFICAÇÃO',
                    title: 'Do que se trata?',
                  ),
                  const SizedBox(height: 14),
                  _fieldLabel('TÍTULO *'),
                  CustomTextField(
                    hint: 'Ex.: Visita ao apartamento de João',
                    controller: _titleController,
                    textInputAction: TextInputAction.next,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Informe um título'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  _fieldLabel('DESCRIÇÃO'),
                  CustomTextField(
                    hint: 'O que precisa ser feito? Quem participa?',
                    controller: _descriptionController,
                    maxLines: 3,
                    maxLength: 300,
                    validator: (v) => (v != null && v.length > 300)
                        ? 'Máximo de 300 caracteres'
                        : null,
                  ),
                  _CharCounter(
                    current: _descriptionController.text.length,
                    max: 300,
                  ),
                  _sectionDivider(),

                  // ── TIPO ──────────────────────────────────────────────
                  _sectionHeader(
                    accent: _kTypeAccent,
                    overline: 'TIPO',
                    title: 'Categoria do compromisso',
                  ),
                  const SizedBox(height: 14),
                  _buildTypeChips(theme),
                  _sectionDivider(),

                  // ── ETIQUETAS ─────────────────────────────────────────
                  _sectionHeader(
                    accent: _kSlateAccent,
                    overline: 'ETIQUETAS',
                    title: 'Preparativos do compromisso',
                  ),
                  const SizedBox(height: 14),
                  _buildTagChips(theme),
                  _sectionDivider(),

                  // ── QUANDO ────────────────────────────────────────────
                  _sectionHeader(
                    accent: _kWhenAccent,
                    overline: 'QUANDO',
                    title: 'Data, hora e duração',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Dia inteiro',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Transform.scale(
                          scale: 0.8,
                          alignment: Alignment.centerRight,
                          child: Switch.adaptive(
                            activeColor: _kWhenAccent,
                            value: _allDay,
                            onChanged: _toggleAllDay,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildWhenSection(theme),
                  _sectionDivider(),

                  // ── CONVIDADOS ────────────────────────────────────────
                  _sectionHeader(
                    accent: _kGuestsAccent,
                    overline: 'CONVIDADOS',
                    title: 'Quem participa',
                    trailing: _addGuestsButton(),
                  ),
                  const SizedBox(height: 12),
                  _buildGuestsContent(theme),
                  _sectionDivider(),

                  // ── LOCAL ─────────────────────────────────────────────
                  _sectionHeader(
                    accent: _kPlaceAccent,
                    overline: 'LOCAL',
                    title: 'Onde acontece',
                  ),
                  const SizedBox(height: 14),
                  CustomTextField(
                    hint: 'Endereço, sala ou link da videochamada',
                    controller: _locationController,
                    prefixIcon: const Icon(
                      Icons.location_on_outlined,
                      color: _kPlaceAccent,
                    ),
                  ),
                  _sectionDivider(),

                  // ── VISIBILIDADE ──────────────────────────────────────
                  _sectionHeader(
                    accent: _kVisibilityAccent,
                    overline: 'VISIBILIDADE',
                    title: 'Quem pode ver',
                  ),
                  const SizedBox(height: 8),
                  // Paridade web: só Particular e Pública — sem "Equipe".
                  _visibilityRow(theme, AppointmentVisibility.private),
                  _visibilityRow(theme, AppointmentVisibility.public),
                  _sectionDivider(),

                  // ── COR ───────────────────────────────────────────────
                  _sectionHeader(
                    accent: previewAccent,
                    overline: 'COR',
                    title: 'Cor de identificação',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Aparece no marcador do calendário e nos cards.',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildColorPalette(theme),
                  _sectionDivider(),

                  // ── OBSERVAÇÕES ───────────────────────────────────────
                  _sectionHeader(
                    accent: _kSlateAccent,
                    overline: 'OBSERVAÇÕES',
                    title: 'Notas só para você',
                  ),
                  const SizedBox(height: 14),
                  CustomTextField(
                    controller: _notesController,
                    maxLines: 4,
                    maxLength: 300,
                    hint: 'Documentos a levar, contexto do cliente...',
                    validator: (v) => (v != null && v.length > 300)
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
            _buildFooter(theme),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Gramática flush: header canônico + hairline
  // ---------------------------------------------------------------------------
  Widget _sectionHeader({
    required Color accent,
    required String overline,
    required String title,
    Widget? trailing,
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
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing,
        ],
      ],
    );
  }

  Widget _hairline({double alpha = 0.65}) {
    return Container(
      height: 1,
      color: ThemeHelpers.borderColor(context).withValues(alpha: alpha),
    );
  }

  /// Separador entre seções: respiro + hairline + respiro.
  Widget _sectionDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: _hairline(),
    );
  }

  /// Label small caps acima de um campo de texto.
  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7, left: 2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: ThemeHelpers.textSecondaryColor(context),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PRÉ-VISUALIZAÇÃO — faixa flush compacta (hairline em cima e embaixo)
  // ---------------------------------------------------------------------------
  Widget _buildPreviewStrip(ThemeData theme, Color accent) {
    final hasTitle = _titleController.text.trim().isNotEmpty;
    final isDark = theme.brightness == Brightness.dark;
    final location = _locationController.text.trim();
    final meta = [
      AppointmentVisuals.formattedShortDate(_start),
      _allDay
          ? 'Dia inteiro'
          : '${AppointmentVisuals.formattedTime(_start)}–${AppointmentVisuals.formattedTime(_end)}',
      if (!_allDay) AppointmentVisuals.durationLabel(_start, _end),
      if (location.isNotEmpty) location,
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _hairline(alpha: 0.45),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.20 : 0.13),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  AppointmentVisuals.iconFor(_type),
                  color: accent,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PRÉ-VISUALIZAÇÃO',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hasTitle
                          ? _titleController.text.trim()
                          : 'Título do agendamento',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: hasTitle
                            ? ThemeHelpers.textColor(context)
                            : ThemeHelpers.textSecondaryColor(context)
                                .withValues(alpha: 0.55),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _hairline(alpha: 0.45),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TIPO — chips com ícone
  // ---------------------------------------------------------------------------
  Widget _buildTypeChips(ThemeData theme) {
    return Wrap(
      spacing: 9,
      runSpacing: 9,
      children: AppointmentType.values.map((t) {
        final selected = _type == t;
        return InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _type = t);
          },
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: selected
                  ? _kTypeAccent.withValues(alpha: 0.11)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? _kTypeAccent.withValues(alpha: 0.55)
                    : ThemeHelpers.borderColor(context),
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  AppointmentVisuals.iconFor(t),
                  size: 17,
                  color: selected
                      ? _kTypeAccent
                      : ThemeHelpers.textSecondaryColor(context),
                ),
                const SizedBox(width: 7),
                Text(
                  t.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected
                        ? _kTypeAccent
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
  // ETIQUETAS — chips no tom semântico de cada tag
  // ---------------------------------------------------------------------------
  /// Tags selecionadas na ordem do catálogo (null = campo fora do POST).
  List<String>? _selectedTags() {
    if (_tags.isEmpty) return null;
    return [
      for (final t in kAppointmentTags)
        if (_tags.contains(t.value)) t.value,
    ];
  }

  Widget _buildTagChips(ThemeData theme) {
    return Wrap(
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                color: selected ? t.tone : ThemeHelpers.textColor(context),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // QUANDO — atalhos + datas/horas tipográficas + duração + disponibilidade
  // ---------------------------------------------------------------------------
  Widget _buildWhenSection(ThemeData theme) {
    final today = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));
    final monday = today.add(Duration(
        days: (8 - today.weekday) % 7 == 0 ? 7 : (8 - today.weekday) % 7));

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
              child: _quickPill(theme, 'Próx. Seg', _isSameDay(_start, monday),
                  () => _quickDate(monday)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _dateTimeRow(
          theme,
          label: 'INÍCIO',
          date: _start,
          onPickDate: () => _pickDate(isStart: true),
          // Início passa pelos slots reais do dia (picker manual é fallback).
          onPickTime: _allDay ? null : _pickStartTime,
        ),
        _hairline(alpha: 0.4),
        _dateTimeRow(
          theme,
          label: 'TÉRMINO',
          date: _end,
          onPickDate: () => _pickDate(isStart: false),
          onPickTime: _allDay ? null : () => _pickTime(isStart: false),
        ),
        if (!_allDay) ...[
          const SizedBox(height: 16),
          Text(
            'DURAÇÃO RÁPIDA',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
          const SizedBox(height: 9),
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
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: _kOverlapRed,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _dateError()!,
                    style: const TextStyle(
                      color: _kOverlapRed,
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

  Widget _quickPill(
    ThemeData theme,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? _kWhenAccent.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? _kWhenAccent.withValues(alpha: 0.55)
                : ThemeHelpers.borderColor(context),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected ? _kWhenAccent : ThemeHelpers.textColor(context),
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }

  Widget _durationChip(ThemeData theme, String label, Duration d) {
    final selected = _end.difference(_start) == d;
    return InkWell(
      onTap: () => _quickDuration(d),
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? _kWhenAccent.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? _kWhenAccent.withValues(alpha: 0.55)
                : ThemeHelpers.borderColor(context),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? _kWhenAccent : ThemeHelpers.textColor(context),
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            fontSize: 12.5,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }

  /// Linha tipográfica de data/hora — texto com sublinhado editável
  /// (linguagem do "Meus horários"), sem caixa nenhuma.
  Widget _dateTimeRow(
    ThemeData theme, {
    required String label,
    required DateTime date,
    required VoidCallback onPickDate,
    VoidCallback? onPickTime,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _tapText(
                AppointmentVisuals.formattedShortDate(date),
                fontSize: 14.5,
                onTap: onPickDate,
              ),
            ),
          ),
          if (onPickTime != null)
            _tapText(
              AppointmentVisuals.formattedTime(date),
              fontSize: 16,
              tabular: true,
              onTap: onPickTime,
            )
          else
            Text(
              'Dia inteiro',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontStyle: FontStyle.italic,
                color: ThemeHelpers.textSecondaryColor(context)
                    .withValues(alpha: 0.7),
              ),
            ),
        ],
      ),
    );
  }

  /// Texto tocável com sublinhado de acento — o affordance de edição.
  Widget _tapText(
    String value, {
    required VoidCallback onTap,
    required double fontSize,
    bool tabular = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.1,
                  fontFeatures:
                      tabular ? const [FontFeature.tabularFigures()] : null,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                height: 1.5,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: _kWhenAccent.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CONVIDADOS
  // ---------------------------------------------------------------------------
  Widget _addGuestsButton() {
    return InkWell(
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
    );
  }

  Widget _buildGuestsContent(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_invited.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _invited.map((m) => _guestChip(theme, m)).toList(),
          ),
          const SizedBox(height: 10),
        ],
        Text(
          _invited.isEmpty
              ? 'Só você por enquanto. Cada convidado recebe um convite '
                  'para aceitar ou recusar.'
              : 'Cada convidado recebe um convite para aceitar ou recusar.',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            height: 1.4,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
        ),
      ],
    );
  }

  /// Chip do convidado na cor estável da pessoa (inicial + nome + remover).
  Widget _guestChip(ThemeData theme, _MemberOption m) {
    final tone = _avatarColorFor(m.name);
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.fromLTRB(5, 4, 6, 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tone.withValues(alpha: 0.18),
            ),
            child: Text(
              m.initial,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: tone,
              ),
            ),
          ),
          const SizedBox(width: 7),
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
              setState(() => _invited.removeWhere((e) => e.id == m.id));
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

  // ---------------------------------------------------------------------------
  // VISIBILIDADE — opções flush (sem caixa), rádio + roundel
  // ---------------------------------------------------------------------------
  Widget _visibilityRow(ThemeData theme, AppointmentVisibility v) {
    final selected = _visibility == v;
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _visibility = v);
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: selected
                    ? _kVisibilityAccent.withValues(alpha: isDark ? 0.20 : 0.13)
                    : secondary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                AppointmentVisuals.iconForVisibility(v),
                color: selected ? _kVisibilityAccent : secondary,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    v == AppointmentVisibility.private
                        ? 'Particular'
                        : 'Pública',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight:
                          selected ? FontWeight.w800 : FontWeight.w700,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    AppointmentVisuals.visibilityDescription(v),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: secondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 21,
              height: 21,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    selected ? _kVisibilityAccent : Colors.transparent,
                border: Border.all(
                  color: selected
                      ? _kVisibilityAccent
                      : ThemeHelpers.borderColor(context),
                  width: selected ? 1.5 : 1.2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 13)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // COR
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
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: selected ? 0.40 : 0.22),
                  blurRadius: selected ? 12 : 6,
                  spreadRadius: selected ? 1.5 : 0,
                  offset: const Offset(0, 3),
                ),
              ],
              border: Border.all(
                color: selected ? Colors.white : Colors.transparent,
                width: selected ? 3 : 0,
              ),
            ),
            child: selected
                ? const Icon(Icons.check_rounded,
                    color: Colors.white, size: 19)
                : null,
          ),
        );
      }).toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // RODAPÉ FIXO — salvar verde full-width + motivo do bloqueio
  // ---------------------------------------------------------------------------
  _FooterNotice? _footerNotice() {
    if (_titleController.text.trim().isEmpty) {
      return const _FooterNotice(
        'Dê um título ao compromisso para salvar',
        Icons.edit_note_rounded,
        amber: false,
      );
    }
    if (_descriptionController.text.length > 300) {
      return const _FooterNotice(
        'Descrição passou de 300 caracteres',
        Icons.notes_rounded,
        amber: false,
      );
    }
    if (_notesController.text.length > 300) {
      return const _FooterNotice(
        'Observações passaram de 300 caracteres',
        Icons.notes_rounded,
        amber: false,
      );
    }
    final dateErr = _dateError();
    if (dateErr != null) {
      return _FooterNotice(dateErr, Icons.event_busy_rounded, amber: false);
    }
    if (_checkingAvailability) {
      return const _FooterNotice(
        'Verificando disponibilidade…',
        Icons.hourglass_top_rounded,
        amber: false,
      );
    }
    final availability = _availability;
    if (availability != null && availability.unavailable.isNotEmpty) {
      return const _FooterNotice(
        'Há conflito de agenda — ajuste o horário para salvar',
        Icons.event_busy_rounded,
        amber: true,
      );
    }
    return null;
  }

  Widget _buildFooter(ThemeData theme) {
    final notice = _footerNotice();
    final canSave = _formValid && !_saving;
    final noticeColor = notice != null && notice.amber
        ? _amberInk(context)
        : ThemeHelpers.textSecondaryColor(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.8),
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (notice != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(notice.icon, size: 13, color: noticeColor),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        notice.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: noticeColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: canSave ? _save : null,
                style: FilledButton.styleFrom(
                  backgroundColor: _kApplyGreen,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      _kApplyGreen.withValues(alpha: 0.38),
                  disabledForegroundColor:
                      Colors.white.withValues(alpha: 0.9),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _saving
                    ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Salvando…',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      )
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_rounded, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Criar agendamento',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

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
    if (_dateError() != null) {
      // Par inválido: o erro de data já bloqueia o salvar sozinho.
      setState(() {
        _checkingAvailability = false;
        _availability = null;
      });
      return;
    }
    final seq = ++_availabilitySeq;
    final fmt = DateFormat("yyyy-MM-dd'T'HH:mm");
    final res = await AppointmentScheduleService.instance.checkAvailability(
      startDate: fmt.format(_start),
      endDate: fmt.format(_end),
      userIds: _invited.map((m) => m.id).toList(),
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
    // Conflitos: régua lateral de 3px na cor do problema — nada encaixotado.
    final hasOverlap = unavailable
        .any((r) => r.issues.any((issue) => issue.code == 'overlap'));
    final frame = hasOverlap ? _kOverlapRed : _kScheduleAmber;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: frame.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < unavailable.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    ..._issueLines(unavailable[i]),
                  ],
                ],
              ),
            ),
          ],
        ),
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
  /// Abre o sheet "Horários do dia" com os slots reais de início — o sheet
  /// carrega com skeleton e, se o fetch falhar, cai sozinho no picker manual.
  Future<void> _pickStartTime() async {
    var duration = _end.difference(_start).inMinutes;
    if (duration <= 0) duration = 60;
    final future = AppointmentScheduleService.instance.getDaySlots(
      date: AppointmentVisuals.dayKey(_start),
      durationMinutes: duration,
      userIds: _invited.map((m) => m.id).toList(),
    );
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DaySlotsSheet(
        slotsFuture: future,
        dayLabel: AppointmentVisuals.formattedShortDate(_start),
        durationMinutes: duration,
        selectedTime: AppointmentVisuals.formattedTime(_start),
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
    setState(() {
      final keep = _end.difference(_start);
      _start = DateTime(_start.year, _start.month, _start.day, hh, mm);
      _end = _start.add(
        keep.isNegative || keep.inMinutes == 0
            ? const Duration(hours: 1)
            : keep,
      );
    });
    _scheduleAvailabilityCheck();
  }

  // ---------------------------------------------------------------------------
  // Membros da empresa (sheet de convidados)
  // ---------------------------------------------------------------------------
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
      debugPrint('❌ [CREATE_APPOINTMENT] company-members: $e');
      return null;
    }
  }

  Future<void> _openInvitePicker() async {
    HapticFeedback.selectionClick();
    final result = await showModalBottomSheet<List<_MemberOption>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
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
    });
    _scheduleAvailabilityCheck();
  }
}

/// Motivo de bloqueio exibido acima do botão salvar.
class _FooterNotice {
  final String text;
  final IconData icon;
  final bool amber;
  const _FooterNotice(this.text, this.icon, {required this.amber});
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
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
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

/// Bottom sheet multi-select de membros — anatomia da casa (grabber, eyebrow,
/// título, fechar, divisor gradient), busca filled, avatar na cor estável da
/// pessoa e Aplicar verde full-width. Devolve a lista via `Navigator.pop`.
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
    final isDark = theme.brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          border: Border(
            top: BorderSide(
              color:
                  ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.10),
              blurRadius: 22,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grabber
              Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: muted.withValues(alpha: 0.32),
                ),
              ),
              // Header editorial
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'CONVIDADOS',
                            style: TextStyle(
                              color: _kGuestsAccent,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.6,
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Convidar membros',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 18.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.4,
                              color: ThemeHelpers.textColor(context),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _selected.isEmpty
                                ? 'Ninguém selecionado'
                                : '${_selected.length} selecionado${_selected.length == 1 ? '' : 's'}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: muted),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Fechar',
                    ),
                  ],
                ),
              ),
              // Divisor gradient
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 22),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      ThemeHelpers.borderColor(context),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Busca filled
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
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
                      fontWeight: FontWeight.w500,
                      color: muted.withValues(alpha: 0.9),
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: muted,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    filled: true,
                    fillColor: _fieldFillOf(context),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: ThemeHelpers.borderLightColor(context),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: _kGuestsAccent,
                        width: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Flexible(child: _buildList(theme, filtered)),
              // Rodapé: Aplicar verde full-width
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: ThemeHelpers.borderColor(context)
                          .withValues(alpha: 0.45),
                    ),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _kApplyGreen,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          _kApplyGreen.withValues(alpha: 0.35),
                      disabledForegroundColor:
                          Colors.white.withValues(alpha: 0.85),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _loading || _failed ? null : _apply,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_rounded, size: 18),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _selected.isEmpty
                                ? 'Aplicar'
                                : 'Aplicar (${_selected.length})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
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
    final muted = ThemeHelpers.textSecondaryColor(context);
    if (_loading) {
      // Skeleton de linhas (avatar + barra), nada de spinner seco.
      const widths = [150.0, 110.0, 170.0, 120.0, 160.0, 100.0];
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < widths.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: muted.withValues(alpha: 0.10),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: widths[i],
                      height: 11,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: muted.withValues(alpha: 0.10),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }
    if (_failed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        child: Text(
          'Não foi possível carregar os membros — feche e tente de novo.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: muted,
          ),
        ),
      );
    }
    if (filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        child: Text(
          'Nenhum membro encontrado.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: muted,
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: filtered.length,
      itemBuilder: (ctx, i) {
        final m = filtered[i];
        final selected = _selected.contains(m.id);
        final tone = _avatarColorFor(m.name);
        return InkWell(
          onTap: () => _toggle(m.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tone.withValues(alpha: selected ? 0.20 : 0.13),
                    border: selected
                        ? Border.all(
                            color: tone.withValues(alpha: 0.75),
                            width: 1.6,
                          )
                        : null,
                  ),
                  child: Text(
                    m.initial,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: tone,
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

/// Grupo de slots por período do dia (MANHÃ / TARDE / NOITE).
class _SlotPeriod {
  final String label;
  final IconData icon;
  final List<AvailabilitySlot> slots;
  const _SlotPeriod(this.label, this.icon, this.slots);
}

/// Sheet "Horários do dia" — anatomia da casa (grabber, eyebrow, título,
/// fechar, divisor gradient), slots agrupados por período em chips: livre em
/// outline, ocupado riscado e apagado (tap mostra quem bloqueia), selecionado
/// preenchido de verde. Carrega com skeleton de chips; se o fetch falhar,
/// devolve [_kManualTimeChoice] pra cair no showTimePicker.
class _DaySlotsSheet extends StatefulWidget {
  final Future<ApiResponse<AvailabilitySlotsResult>> slotsFuture;
  final String dayLabel;
  final int durationMinutes;
  final String? selectedTime;

  const _DaySlotsSheet({
    required this.slotsFuture,
    required this.dayLabel,
    required this.durationMinutes,
    this.selectedTime,
  });

  @override
  State<_DaySlotsSheet> createState() => _DaySlotsSheetState();
}

class _DaySlotsSheetState extends State<_DaySlotsSheet>
    with SingleTickerProviderStateMixin {
  AvailabilitySlotsResult? _result;
  bool _loading = true;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat(reverse: true);
    widget.slotsFuture.then((res) {
      if (!mounted) return;
      if (!res.success || res.data == null) {
        // Fetch falhou → direto pro picker manual, sem bloquear ninguém.
        Navigator.pop(context, _kManualTimeChoice);
        return;
      }
      _pulse.stop();
      setState(() {
        _loading = false;
        _result = res.data;
      });
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  List<_SlotPeriod> _periods(List<AvailabilitySlot> slots) {
    final morning = <AvailabilitySlot>[];
    final afternoon = <AvailabilitySlot>[];
    final evening = <AvailabilitySlot>[];
    for (final s in slots) {
      final h = int.tryParse(s.time.split(':').first) ?? 0;
      if (h < 12) {
        morning.add(s);
      } else if (h < 18) {
        afternoon.add(s);
      } else {
        evening.add(s);
      }
    }
    return [
      if (morning.isNotEmpty)
        _SlotPeriod('MANHÃ', Icons.wb_sunny_outlined, morning),
      if (afternoon.isNotEmpty)
        _SlotPeriod('TARDE', Icons.light_mode_rounded, afternoon),
      if (evening.isNotEmpty)
        _SlotPeriod('NOITE', Icons.nights_stay_rounded, evening),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final media = MediaQuery.of(context);

    return Container(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(
          top: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.10),
            blurRadius: 22,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Grabber
            Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: muted.withValues(alpha: 0.32),
              ),
            ),
            // Header editorial
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'DISPONIBILIDADE',
                          style: TextStyle(
                            color: _kWhenAccent,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.6,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Horários de ${widget.dayLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                            color: ThemeHelpers.textColor(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Compromisso de '
                          '${formatGapLabel(widget.durationMinutes)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: muted),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Fechar',
                  ),
                ],
              ),
            ),
            // Divisor gradient
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    ThemeHelpers.borderColor(context),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
            // Corpo rolável
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
                child: _loading
                    ? _buildSkeleton(muted)
                    : _buildSlots(theme, muted),
              ),
            ),
            // Legenda + fallback manual
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: ThemeHelpers.borderColor(context)
                        .withValues(alpha: 0.45),
                  ),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(22, 4, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: _kFreeGreen,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            'Livre',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: muted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            'Ocupado',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.lineThrough,
                              decorationColor:
                                  muted.withValues(alpha: 0.6),
                              color: muted.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      // Tema global pinta TextButton de vermelho — forçar.
                      foregroundColor: muted,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () =>
                        Navigator.pop(context, _kManualTimeChoice),
                    child: const Text(
                      'Escolher outro horário…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Skeleton de chips com pulso suave — nada de spinner seco.
  Widget _buildSkeleton(Color muted) {
    Widget ghostChip() => Container(
          width: 62,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: muted.withValues(alpha: 0.10),
          ),
        );
    Widget ghostGroup(double labelWidth, int chips) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: labelWidth,
              height: 9,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                color: muted.withValues(alpha: 0.16),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (var i = 0; i < chips; i++) ghostChip()],
            ),
          ],
        );
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(
        CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ghostGroup(56, 6),
          const SizedBox(height: 20),
          ghostGroup(48, 8),
          const SizedBox(height: 20),
          ghostGroup(46, 4),
        ],
      ),
    );
  }

  Widget _buildSlots(ThemeData theme, Color muted) {
    final result = _result!;
    if (result.slots.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 26),
        child: Column(
          children: [
            Icon(
              Icons.event_busy_rounded,
              size: 34,
              color: muted.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text(
              'Nenhum horário na grade deste dia',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: ThemeHelpers.textColor(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Use "Escolher outro horário…" abaixo para definir manualmente.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                height: 1.4,
                color: muted,
              ),
            ),
          ],
        ),
      );
    }
    final periods = _periods(result.slots);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var p = 0; p < periods.length; p++) ...[
          if (p > 0) const SizedBox(height: 20),
          Row(
            children: [
              Icon(
                periods[p].icon,
                size: 13,
                color: muted.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 6),
              Text(
                periods[p].label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: muted,
                ),
              ),
              const Spacer(),
              Text(
                _freeCountLabel(periods[p].slots),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: muted.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                periods[p].slots.map((s) => _slotChip(context, s)).toList(),
          ),
        ],
      ],
    );
  }

  String _freeCountLabel(List<AvailabilitySlot> slots) {
    final free = slots.where((s) => s.available).length;
    return free == 1 ? '1 livre' : '$free livres';
  }

  Widget _slotChip(BuildContext context, AvailabilitySlot s) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final selected = s.available && s.time == widget.selectedTime;

    if (selected) {
      // Horário atual: preenchido de verde, texto branco.
      return InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.pop(context, s.time);
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _kApplyGreen,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: _kApplyGreen.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_rounded, size: 13, color: Colors.white),
              const SizedBox(width: 5),
              Text(
                s.time,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (s.available) {
      // Livre: outline neutro; tap = seleciona (haptic) e fecha.
      return InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.pop(context, s.time);
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: ThemeHelpers.borderColor(context)),
          ),
          child: Text(
            s.time,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: ThemeHelpers.textColor(context),
            ),
          ),
        ),
      );
    }

    // Ocupado: riscado e apagado, sem borda visível; tap mostra quem bloqueia
    // (tooltip — snackbar ficaria escondido atrás do modal).
    final names = s.blockedFor;
    final tooltipMessage = names.isEmpty
        ? ((s.reason != null && s.reason!.isNotEmpty)
            ? 'Ocupado: ${s.reason}'
            : 'Horário indisponível')
        : 'Ocupado: ${names.join(', ')}';
    final struckColor = muted.withValues(alpha: 0.45);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltipMessage,
      triggerMode: TooltipTriggerMode.tap,
      preferBelow: false,
      decoration: BoxDecoration(
        color: (isDark ? const Color(0xFF1F2937) : const Color(0xFF111827))
            .withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(10),
      ),
      textStyle: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.transparent),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              s.time,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.lineThrough,
                decorationColor: struckColor,
                decorationThickness: 1.4,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: struckColor,
              ),
            ),
            if (names.isNotEmpty) ...[
              const SizedBox(height: 1),
              Text(
                'Ocupado',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: muted.withValues(alpha: 0.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
