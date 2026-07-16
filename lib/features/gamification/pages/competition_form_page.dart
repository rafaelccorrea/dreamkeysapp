import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/competition_models.dart';
import '../services/competition_service.dart';
import '../widgets/competition_card.dart';
import '../widgets/gamification_ui.dart';

final DateFormat _dateTime = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

/// Formulário de **Competição** (criar/editar). Paridade
/// `CreateCompetitionPage.tsx` / `EditCompetitionPage.tsx` — mesmas
/// validações e payload (`POST/PUT /competitions`).
class CompetitionFormPage extends StatefulWidget {
  /// `null` = criação; senão edição.
  final String? competitionId;

  const CompetitionFormPage({super.key, this.competitionId});

  @override
  State<CompetitionFormPage> createState() => _CompetitionFormPageState();
}

class _CompetitionFormPageState extends State<CompetitionFormPage> {
  static const double _padH = 16;

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _minController = TextEditingController();
  final _maxController = TextEditingController();

  bool _loadingCompetition = false;
  bool _saving = false;
  String? _loadError;
  Competition? _competition;

  CompetitionType _type = CompetitionType.individual;
  CompetitionStatus _initialStatus = CompetitionStatus.scheduled;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _useCompanyPointsConfig = true;
  bool _autoStart = true;
  bool _autoEnd = true;

  bool _limitUsers = false;
  bool _limitTeams = false;
  Set<String> _selectedUserIds = {};
  Set<String> _selectedTeamIds = {};

  List<ParticipantUser> _users = const [];
  List<ParticipantTeam> _teams = const [];
  bool _participantsLoaded = false;

  bool get _isEdit => widget.competitionId != null;

  bool get _hasPermission => ModuleAccessService.instance
      .hasPermission(_isEdit ? 'competition:edit' : 'competition:create');

  @override
  void initState() {
    super.initState();
    if (_isEdit) _loadCompetition();
    _loadParticipantSources();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  Future<void> _loadCompetition() async {
    setState(() {
      _loadingCompetition = true;
      _loadError = null;
    });
    final res =
        await CompetitionService.instance.getById(widget.competitionId!);
    if (!mounted) return;
    setState(() {
      _loadingCompetition = false;
      if (res.success && res.data != null) {
        final c = res.data!;
        _competition = c;
        _nameController.text = c.name;
        _descriptionController.text = c.description ?? '';
        _type = c.type;
        _startDate = c.startDate?.toLocal();
        _endDate = c.endDate?.toLocal();
        _useCompanyPointsConfig = c.useCompanyPointsConfig;
        _autoStart = c.autoStart;
        _autoEnd = c.autoEnd;
        _minController.text =
            c.minParticipants != null ? '${c.minParticipants}' : '';
        _maxController.text =
            c.maxParticipants != null ? '${c.maxParticipants}' : '';
        _selectedUserIds = Set.from(c.participantUserIds ?? const []);
        _selectedTeamIds = Set.from(c.participantTeamIds ?? const []);
        _limitUsers = _selectedUserIds.isNotEmpty;
        _limitTeams = _selectedTeamIds.isNotEmpty;
      } else {
        _loadError = res.message ?? 'Erro ao carregar competição';
      }
    });
  }

  Future<void> _loadParticipantSources() async {
    final results = await Future.wait([
      CompetitionService.instance.getSelectableUsers(),
      CompetitionService.instance.getSelectableTeams(),
    ]);
    if (!mounted) return;
    setState(() {
      _participantsLoaded = true;
      final usersRes = results[0] as dynamic;
      final teamsRes = results[1] as dynamic;
      if (usersRes.success && usersRes.data != null) {
        _users = usersRes.data as List<ParticipantUser>;
      }
      if (teamsRes.success && teamsRes.data != null) {
        _teams = teamsRes.data as List<ParticipantTeam>;
      }
    });
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? gamDanger(context) : null,
      ),
    );
  }

  // ─── Datas ─────────────────────────────────────────────────────────────────

  Future<void> _pickDateTime({required bool isStart}) async {
    final now = DateTime.now();
    final initial = (isStart ? _startDate : _endDate) ??
        (isStart ? now : now.add(const Duration(days: 7)));

    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      locale: const Locale('pt', 'BR'),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (!mounted) return;

    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? 0,
      time?.minute ?? 0,
    );
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  // ─── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_saving) return;

    final name = _nameController.text.trim();
    if (name.isEmpty || _startDate == null || _endDate == null) {
      _snack('Preencha todos os campos obrigatórios!', error: true);
      return;
    }

    final now = DateTime.now();
    final status = _competition?.status;

    // Criação: início não pode ser no passado. Edição: só valida se agendada.
    final validateStartInFuture =
        !_isEdit || status == CompetitionStatus.scheduled;
    if (validateStartInFuture && _startDate!.isBefore(now)) {
      _snack('A data de início não pode ser anterior à data atual!',
          error: true);
      return;
    }

    if (!_endDate!.isAfter(_startDate!)) {
      _snack('A data de término deve ser posterior à data de início!',
          error: true);
      return;
    }

    if (_endDate!.difference(_startDate!).inHours < 24) {
      _snack('A competição deve ter duração mínima de 1 dia!', error: true);
      return;
    }

    if (_isEdit &&
        status == CompetitionStatus.active &&
        _startDate!.isAfter(now)) {
      _snack(
        'Não é possível alterar a data de início de uma competição em '
        'andamento para o futuro!',
        error: true,
      );
      return;
    }

    final minPart = int.tryParse(_minController.text.trim());
    final maxPart = int.tryParse(_maxController.text.trim());
    if (minPart != null && minPart < 1) {
      _snack('O mínimo de participantes deve ser pelo menos 1!', error: true);
      return;
    }
    if (maxPart != null && maxPart < 1) {
      _snack('O máximo de participantes deve ser pelo menos 1!', error: true);
      return;
    }
    if (minPart != null && maxPart != null && maxPart < minPart) {
      _snack('O máximo de participantes deve ser maior ou igual ao mínimo!',
          error: true);
      return;
    }

    final includesUsers = _type != CompetitionType.team;
    final includesTeams = _type != CompetitionType.individual;

    if (includesUsers && _limitUsers && _selectedUserIds.isEmpty) {
      _snack('Selecione ao menos um corretor participante.', error: true);
      return;
    }
    if (includesTeams && _limitTeams && _selectedTeamIds.isEmpty) {
      _snack('Selecione ao menos uma equipe participante.', error: true);
      return;
    }

    final payload = CompetitionPayload(
      name: name,
      description: _descriptionController.text,
      type: _type,
      startDate: _startDate!,
      endDate: _endDate!,
      useCompanyPointsConfig: _useCompanyPointsConfig,
      autoStart: _autoStart,
      autoEnd: _autoEnd,
      minParticipants: minPart,
      maxParticipants: maxPart,
      participantUserIds:
          includesUsers && _limitUsers ? _selectedUserIds.toList() : null,
      participantTeamIds:
          includesTeams && _limitTeams ? _selectedTeamIds.toList() : null,
    );

    setState(() => _saving = true);

    if (_isEdit) {
      final res = await CompetitionService.instance
          .update(widget.competitionId!, payload);
      if (!mounted) return;
      setState(() => _saving = false);
      if (res.success) {
        _snack('Competição atualizada com sucesso!');
        Navigator.of(context).pop(true);
      } else {
        _snack(res.message ?? 'Erro ao atualizar competição', error: true);
      }
      return;
    }

    final res = await CompetitionService.instance.create(payload);
    if (!mounted) return;

    if (!res.success || res.data == null) {
      setState(() => _saving = false);
      _snack(res.message ?? 'Erro ao criar competição', error: true);
      return;
    }

    final created = res.data!;

    // Status inicial diferente de rascunho → muda após criar (paridade web).
    if (_initialStatus != CompetitionStatus.draft && created.id.isNotEmpty) {
      final statusRes = await CompetitionService.instance
          .changeStatus(created.id, _initialStatus);
      if (!mounted) return;
      if (!statusRes.success) {
        _snack(
          statusRes.message ??
              'Competição criada, mas não foi possível alterar o status inicial.',
          error: true,
        );
      }
    }

    setState(() => _saving = false);
    _snack('Competição criada com sucesso!');

    // Segue direto para o cadastro de prêmios (paridade web).
    if (created.id.isNotEmpty &&
        ModuleAccessService.instance.hasPermission('prize:create')) {
      Navigator.of(context)
          .pushReplacementNamed('/competitions/${created.id}/prizes');
    } else {
      Navigator.of(context).pop(true);
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final title = _isEdit ? 'Editar Competição' : 'Nova Competição';

    if (!_hasPermission) {
      return AppScaffold(
        title: title,
        showBottomNavigation: false,
        body: GamDeniedView(
          what: _isEdit ? 'edição de competições' : 'criação de competições',
          permission: _isEdit ? 'competition:edit' : 'competition:create',
        ),
      );
    }

    return AppScaffold(
      title: title,
      showBottomNavigation: false,
      body: _loadingCompetition
          ? _buildSkeleton(context)
          : _loadError != null
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(_padH, 60, _padH, 24),
                  child: GamErrorState(
                      message: _loadError!, onRetry: _loadCompetition),
                )
              : _buildForm(context),
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final accent = gamAccentColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final green = gamGreen(context);
    final blue = gamBlue(context);
    final purple = gamPurple(context);

    final includesUsers = _type != CompetitionType.team;
    final includesTeams = _type != CompetitionType.individual;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(_padH, 12, _padH, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Eyebrow + status atual (edição)
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration:
                          BoxDecoration(color: accent, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      _isEdit ? 'EDITAR COMPETIÇÃO' : 'NOVA COMPETIÇÃO',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.0,
                        fontSize: 10.5,
                      ),
                    ),
                    const Spacer(),
                    if (_competition != null)
                      GamMiniPill(
                        label: _competition!.status.label,
                        color: competitionStatusColor(
                            context, _competition!.status),
                        icon: competitionStatusIcon(_competition!.status),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _isEdit
                      ? 'Atualize as informações da competição.'
                      : 'Preencha as informações para criar uma nova competição.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),

                // ── Identificação ────────────────────────────────────────
                const GamSubsectionHeader(
                  label: 'Identificação',
                  icon: LucideIcons.flag,
                ),
                const SizedBox(height: 12),
                _textField(
                  context,
                  controller: _nameController,
                  label: 'Nome da competição *',
                  hint: 'Ex.: Campeonato de Vendas Q1 2026',
                  maxLength: 100,
                ),
                const SizedBox(height: 12),
                _textField(
                  context,
                  controller: _descriptionController,
                  label: 'Descrição',
                  hint: 'Regras, objetivos e prêmios da competição…',
                  maxLength: 300,
                  lines: 3,
                ),
                const SizedBox(height: 14),

                // Tipo
                Text(
                  'Tipo de competição *',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in CompetitionType.values)
                      _choiceChip(
                        context,
                        label: t.longLabel,
                        icon: t == CompetitionType.team
                            ? LucideIcons.users2
                            : t == CompetitionType.mixed
                                ? LucideIcons.blend
                                : LucideIcons.user,
                        selected: _type == t,
                        tone: t == CompetitionType.team
                            ? purple
                            : t == CompetitionType.mixed
                                ? blue
                                : accent,
                        onTap: () => setState(() {
                          _type = t;
                          // Espelha o efeito do web ao trocar o tipo.
                          if (t == CompetitionType.individual) {
                            _limitTeams = false;
                            _selectedTeamIds.clear();
                          } else if (t == CompetitionType.team) {
                            _limitUsers = false;
                            _selectedUserIds.clear();
                          }
                        }),
                      ),
                  ],
                ),

                if (!_isEdit) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Status inicial',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in const [
                        CompetitionStatus.draft,
                        CompetitionStatus.scheduled,
                        CompetitionStatus.active,
                      ])
                        _choiceChip(
                          context,
                          label: s.label,
                          icon: competitionStatusIcon(s),
                          selected: _initialStatus == s,
                          tone: competitionStatusColor(context, s),
                          onTap: () => setState(() => _initialStatus = s),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 22),

                // ── Período ──────────────────────────────────────────────
                const GamSubsectionHeader(
                  label: 'Período',
                  icon: LucideIcons.calendarRange,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _dateField(
                        context,
                        label: 'Início *',
                        value: _startDate,
                        onTap: () => _pickDateTime(isStart: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _dateField(
                        context,
                        label: 'Término *',
                        value: _endDate,
                        onTap: () => _pickDateTime(isStart: false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _numberField(
                        context,
                        controller: _minController,
                        label: 'Mín. de participantes',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _numberField(
                        context,
                        controller: _maxController,
                        label: 'Máx. de participantes',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                // ── Automação ────────────────────────────────────────────
                const GamSubsectionHeader(
                  label: 'Regras e automação',
                  icon: LucideIcons.zap,
                ),
                const SizedBox(height: 6),
                _switchRow(
                  context,
                  icon: LucideIcons.settings2,
                  label: 'Usar configuração de pontos da empresa',
                  value: _useCompanyPointsConfig,
                  tone: green,
                  onChanged: (v) =>
                      setState(() => _useCompanyPointsConfig = v),
                ),
                _switchRow(
                  context,
                  icon: LucideIcons.play,
                  label: 'Início automático na data',
                  value: _autoStart,
                  tone: blue,
                  onChanged: (v) => setState(() => _autoStart = v),
                ),
                _switchRow(
                  context,
                  icon: LucideIcons.flagTriangleRight,
                  label: 'Finalização automática na data',
                  value: _autoEnd,
                  tone: blue,
                  onChanged: (v) => setState(() => _autoEnd = v),
                ),
                const SizedBox(height: 22),

                // ── Participantes ────────────────────────────────────────
                if (includesUsers) ...[
                  const GamSubsectionHeader(
                    label: 'Participantes individuais',
                    icon: LucideIcons.users,
                  ),
                  const SizedBox(height: 6),
                  _switchRow(
                    context,
                    icon: LucideIcons.listFilter,
                    label: 'Selecionar corretores específicos',
                    value: _limitUsers,
                    tone: accent,
                    onChanged: (v) => setState(() {
                      _limitUsers = v;
                      if (!v) _selectedUserIds.clear();
                    }),
                  ),
                  if (!_limitUsers)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Todos os corretores da empresa participarão '
                        'automaticamente.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: secondary, fontSize: 11.5),
                      ),
                    )
                  else
                    _participantPicker(
                      context,
                      tone: accent,
                      emptyLabel: 'Nenhum corretor selecionado',
                      count: _selectedUserIds.length,
                      names: [
                        for (final u in _users)
                          if (_selectedUserIds.contains(u.id)) u.name,
                      ],
                      onTap: () => _openUserPicker(context),
                    ),
                  const SizedBox(height: 18),
                ],
                if (includesTeams) ...[
                  const GamSubsectionHeader(
                    label: 'Equipes participantes',
                    icon: LucideIcons.shield,
                  ),
                  const SizedBox(height: 6),
                  _switchRow(
                    context,
                    icon: LucideIcons.listFilter,
                    label: 'Selecionar equipes específicas',
                    value: _limitTeams,
                    tone: purple,
                    onChanged: (v) => setState(() {
                      _limitTeams = v;
                      if (!v) _selectedTeamIds.clear();
                    }),
                  ),
                  if (!_limitTeams)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Todas as equipes da empresa participarão '
                        'automaticamente.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: secondary, fontSize: 11.5),
                      ),
                    )
                  else
                    _participantPicker(
                      context,
                      tone: purple,
                      emptyLabel: 'Nenhuma equipe selecionada',
                      count: _selectedTeamIds.length,
                      names: [
                        for (final t in _teams)
                          if (_selectedTeamIds.contains(t.id)) t.name,
                      ],
                      onTap: () => _openTeamPicker(context),
                    ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),

        // ── Barra de ação ─────────────────────────────────────────────────
        Container(
          padding: EdgeInsets.fromLTRB(
            _padH,
            10,
            _padH,
            10 + MediaQuery.of(context).padding.bottom,
          ),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            border: Border(
              top: BorderSide(color: ThemeHelpers.borderLightColor(context)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _saving ? null : () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(LucideIcons.save, size: 16),
                  label: Text(
                    _saving
                        ? (_isEdit ? 'Salvando…' : 'Criando…')
                        : (_isEdit ? 'Salvar alterações' : 'Criar competição'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Campos ────────────────────────────────────────────────────────────────

  Color _fill(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.background.backgroundTertiaryDarkMode
          : AppColors.background.backgroundTertiary;

  InputDecoration _decoration(BuildContext context,
      {String? hint, Widget? suffixIcon}) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return InputDecoration(
      hintText: hint,
      hintStyle: Theme.of(context)
          .textTheme
          .bodySmall
          ?.copyWith(color: secondary),
      isDense: true,
      filled: true,
      fillColor: _fill(context),
      counterText: '',
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: gamAccentColor(context).withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _fieldLabel(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
      ),
    );
  }

  Widget _textField(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    String? hint,
    int? maxLength,
    int lines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(context, label),
        TextField(
          controller: controller,
          maxLength: maxLength,
          maxLines: lines,
          textCapitalization: TextCapitalization.sentences,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: ThemeHelpers.textColor(context)),
          decoration: _decoration(context, hint: hint),
        ),
      ],
    );
  }

  Widget _numberField(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(context, label),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(5),
          ],
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
              ),
          decoration: _decoration(context, hint: 'Opcional'),
        ),
      ],
    );
  }

  Widget _dateField(
    BuildContext context, {
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(context, label),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12.5),
            decoration: BoxDecoration(
              color: _fill(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.calendarClock, size: 15, color: secondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    value != null ? _dateTime.format(value) : 'Selecionar…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: value != null
                          ? ThemeHelpers.textColor(context)
                          : secondary,
                      fontWeight:
                          value != null ? FontWeight.w800 : FontWeight.w500,
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

  Widget _choiceChip(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool selected,
    required Color tone,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected
              ? tone.withValues(alpha: isDark ? 0.22 : 0.1)
              : Colors.transparent,
          border: Border.all(
            color: selected
                ? tone.withValues(alpha: 0.55)
                : ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: selected ? tone : secondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? tone : secondary,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _switchRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool value,
    required Color tone,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon,
              size: 16,
              color:
                  value ? tone : ThemeHelpers.textSecondaryColor(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            activeThumbColor: tone,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _participantPicker(
    BuildContext context, {
    required Color tone,
    required String emptyLabel,
    required int count,
    required List<String> names,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final preview = names.take(3).join(', ');
    final more = names.length > 3 ? ' +${names.length - 3}' : '';

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: _fill(context),
            borderRadius: BorderRadius.circular(12),
            border: count > 0
                ? Border.all(color: tone.withValues(alpha: 0.4))
                : null,
          ),
          child: Row(
            children: [
              Icon(LucideIcons.users, size: 15, color: count > 0 ? tone : secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  count > 0 ? '$preview$more' : emptyLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: count > 0
                        ? ThemeHelpers.textColor(context)
                        : secondary,
                    fontWeight:
                        count > 0 ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 8),
                GamMiniPill(label: '$count', color: tone),
              ],
              const SizedBox(width: 6),
              Icon(LucideIcons.chevronRight, size: 15, color: secondary),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Pickers (bottom sheet multi-seleção) ──────────────────────────────────

  void _openUserPicker(BuildContext context) {
    _openMultiPicker<ParticipantUser>(
      context: context,
      title: 'Corretores participantes',
      tone: gamAccentColor(context),
      items: _users,
      idOf: (u) => u.id,
      titleOf: (u) => u.name,
      subtitleOf: (u) => u.email,
      selected: _selectedUserIds,
      maxSelections: 100,
      onDone: (ids) => setState(() => _selectedUserIds = ids),
    );
  }

  void _openTeamPicker(BuildContext context) {
    _openMultiPicker<ParticipantTeam>(
      context: context,
      title: 'Equipes participantes',
      tone: gamPurple(context),
      items: _teams,
      idOf: (t) => t.id,
      titleOf: (t) => t.name,
      subtitleOf: (_) => '',
      selected: _selectedTeamIds,
      maxSelections: 50,
      onDone: (ids) => setState(() => _selectedTeamIds = ids),
    );
  }

  void _openMultiPicker<T>({
    required BuildContext context,
    required String title,
    required Color tone,
    required List<T> items,
    required String Function(T) idOf,
    required String Function(T) titleOf,
    required String Function(T) subtitleOf,
    required Set<String> selected,
    required int maxSelections,
    required ValueChanged<Set<String>> onDone,
  }) {
    final working = Set<String>.from(selected);
    final searchController = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final secondary = ThemeHelpers.textSecondaryColor(sheetContext);

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final term = searchController.text.trim().toLowerCase();
            final visible = items.where((item) {
              if (term.isEmpty) return true;
              return titleOf(item).toLowerCase().contains(term) ||
                  subtitleOf(item).toLowerCase().contains(term);
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.78,
              decoration: BoxDecoration(
                color: ThemeHelpers.backgroundColor(context),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 4),
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                    child: Row(
                      children: [
                        Icon(LucideIcons.users, size: 17, color: tone),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: ThemeHelpers.textColor(context),
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        GamMiniPill(
                          label: '${working.length}/$maxSelections',
                          color: tone,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: TextField(
                      controller: searchController,
                      onChanged: (_) => setSheetState(() {}),
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: ThemeHelpers.textColor(context)),
                      decoration: _decoration(
                        context,
                        hint: 'Buscar…',
                      ).copyWith(
                        prefixIcon: Icon(LucideIcons.search,
                            size: 16, color: secondary),
                      ),
                    ),
                  ),
                  Expanded(
                    child: !_participantsLoaded
                        ? const Center(
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : visible.isEmpty
                            ? Center(
                                child: Text(
                                  'Nada encontrado.',
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: secondary),
                                ),
                              )
                            : ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 0, 12, 16),
                                itemCount: visible.length,
                                itemBuilder: (context, i) {
                                  final item = visible[i];
                                  final id = idOf(item);
                                  final isSelected = working.contains(id);
                                  final subtitle = subtitleOf(item);
                                  return CheckboxListTile(
                                    value: isSelected,
                                    dense: true,
                                    activeColor: tone,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    title: Text(
                                      titleOf(item),
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                        color:
                                            ThemeHelpers.textColor(context),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: subtitle.isEmpty
                                        ? null
                                        : Text(
                                            subtitle,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: secondary,
                                              fontSize: 11.5,
                                            ),
                                          ),
                                    onChanged: (checked) {
                                      setSheetState(() {
                                        if (checked == true) {
                                          if (working.length <
                                              maxSelections) {
                                            working.add(id);
                                          }
                                        } else {
                                          working.remove(id);
                                        }
                                      });
                                    },
                                  );
                                },
                              ),
                  ),
                  Container(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      10,
                      20,
                      12 + MediaQuery.of(context).padding.bottom,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: ThemeHelpers.borderLightColor(context),
                        ),
                      ),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: FilledButton(
                        onPressed: () {
                          onDone(working);
                          Navigator.of(context).pop();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: tone,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          'Confirmar seleção (${working.length})',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(searchController.dispose);
  }

  // ─── Skeleton fiel ─────────────────────────────────────────────────────────

  Widget _buildSkeleton(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(_padH, 16, _padH, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonText(width: 150, height: 11, borderRadius: 999),
          const SizedBox(height: 10),
          const SkeletonText(width: double.infinity, height: 12),
          const SizedBox(height: 22),
          const SkeletonText(width: 130, height: 11),
          const SizedBox(height: 12),
          const SkeletonBox(width: double.infinity, height: 46, borderRadius: 12),
          const SizedBox(height: 12),
          const SkeletonBox(width: double.infinity, height: 88, borderRadius: 12),
          const SizedBox(height: 16),
          Row(
            children: const [
              SkeletonBox(width: 110, height: 34, borderRadius: 999),
              SizedBox(width: 8),
              SkeletonBox(width: 110, height: 34, borderRadius: 999),
              SizedBox(width: 8),
              SkeletonBox(width: 90, height: 34, borderRadius: 999),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: const [
              Expanded(child: SkeletonBox(height: 46, borderRadius: 12)),
              SizedBox(width: 10),
              Expanded(child: SkeletonBox(height: 46, borderRadius: 12)),
            ],
          ),
        ],
      ),
    );
  }
}
