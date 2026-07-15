import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/utils/input_formatters.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/goal_model.dart';
import '../services/goal_service.dart';
import '../widgets/goal_card.dart';

/// Formulário de meta — criação e edição (paridade com NewGoalPage /
/// EditGoalPage do imobx-front). Na edição, tipo/período/escopo não são
/// editáveis (regra do `UpdateGoalDto`); status e ativação passam a ser.
/// Campos *filled* em 2 colunas quando couber, máscara monetária via
/// [CurrencyInputFormatter] e datas com DateFormat pt_BR.
class GoalFormPage extends StatefulWidget {
  final String? goalId;

  const GoalFormPage({super.key, this.goalId});

  @override
  State<GoalFormPage> createState() => _GoalFormPageState();
}

class _GoalFormPageState extends State<GoalFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _target = TextEditingController();

  GoalType _type = GoalType.salesValue;
  GoalPeriod _period = GoalPeriod.monthly;
  GoalScope _scope = GoalScope.company;
  GoalStatus _status = GoalStatus.active;
  bool _isActive = true;

  String? _userId;
  String? _userName;
  String? _teamId;
  String? _teamName;

  DateTime? _startDate;
  DateTime? _endDate;
  bool _datesTouched = false;

  String _color = kGoalColors.first;
  String _icon = kGoalIcons.first;

  GoalFormOptions _options = GoalFormOptions.empty;
  bool _optionsLoading = false;

  Goal? _existing;
  bool _loadingExisting = false;
  String? _loadError;
  bool _saving = false;

  bool get _isEdit => widget.goalId != null;

  Color get _accent {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
  }

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _loadExisting();
    } else {
      _applyDefaultDates();
      _loadOptions();
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _target.dispose();
    super.dispose();
  }

  // ─── Dados ───────────────────────────────────────────────────────────────

  Future<void> _loadExisting() async {
    setState(() {
      _loadingExisting = true;
      _loadError = null;
    });
    final res = await GoalService.instance.getGoalById(widget.goalId!);
    if (!mounted) return;
    setState(() {
      _loadingExisting = false;
      if (res.success && res.data != null) {
        _prefill(res.data!);
      } else {
        _loadError = res.message ?? 'Erro ao carregar meta';
      }
    });
  }

  void _prefill(Goal g) {
    _existing = g;
    _title.text = g.title;
    _description.text = g.description ?? '';
    _type = g.type;
    _period = g.period;
    _scope = g.scope;
    _status = g.status == GoalStatus.unknown ? GoalStatus.active : g.status;
    _isActive = g.isActive;
    _userId = g.userId;
    _userName = g.userName;
    _teamId = g.teamId;
    _teamName = g.teamName;
    _startDate = g.startDate?.toLocal();
    _endDate = g.endDate?.toLocal();
    if ((g.color ?? '').isNotEmpty) _color = g.color!;
    if ((g.icon ?? '').isNotEmpty) _icon = g.icon!;
    _target.text = _formatTargetForInput(g.targetValue);
  }

  Future<void> _loadOptions() async {
    setState(() => _optionsLoading = true);
    final res = await GoalService.instance.getFormOptions();
    if (!mounted) return;
    setState(() {
      _optionsLoading = false;
      if (res.success && res.data != null) _options = res.data!;
    });
  }

  // ─── Datas por período ───────────────────────────────────────────────────

  /// Sugere início/fim conforme o período (o backend exige as duas datas).
  void _applyDefaultDates() {
    final now = DateTime.now();
    switch (_period) {
      case GoalPeriod.daily:
        _startDate = DateTime(now.year, now.month, now.day);
        _endDate = DateTime(now.year, now.month, now.day);
        break;
      case GoalPeriod.weekly:
        final monday = now.subtract(Duration(days: now.weekday - 1));
        _startDate = DateTime(monday.year, monday.month, monday.day);
        _endDate = _startDate!.add(const Duration(days: 6));
        break;
      case GoalPeriod.monthly:
      case GoalPeriod.unknown:
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = DateTime(now.year, now.month + 1, 0);
        break;
      case GoalPeriod.quarterly:
        final qStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
        _startDate = DateTime(now.year, qStartMonth, 1);
        _endDate = DateTime(now.year, qStartMonth + 3, 0);
        break;
      case GoalPeriod.yearly:
        _startDate = DateTime(now.year, 1, 1);
        _endDate = DateTime(now.year, 12, 31);
        break;
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = (isStart ? _startDate : _endDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
      locale: const Locale('pt', 'BR'),
    );
    if (picked == null) return;
    setState(() {
      _datesTouched = true;
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) _endDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  // ─── Valor alvo (máscara por tipo) ───────────────────────────────────────

  List<TextInputFormatter> get _targetFormatters {
    if (_type.isCurrency) return [CurrencyInputFormatter()];
    if (_type.isPercent) {
      return [FilteringTextInputFormatter.allow(RegExp(r'[0-9,]'))];
    }
    return [NumericInputFormatter()];
  }

  String _formatTargetForInput(double v) {
    if (v <= 0) return '';
    if (_type.isCurrency) return CurrencyInputFormatter.format(v);
    if (_type.isPercent) {
      return NumberFormat('#,##0.##', 'pt_BR').format(v);
    }
    return v.round().toString();
  }

  double _parseTarget() {
    final raw = _target.text.trim();
    if (raw.isEmpty) return 0;
    if (_type.isCurrency) {
      final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isEmpty) return 0;
      return (int.tryParse(digits) ?? 0) / 100.0;
    }
    return double.tryParse(raw.replaceAll('.', '').replaceAll(',', '.')) ?? 0;
  }

  void _onTypeChanged(GoalType t) {
    final value = _parseTarget();
    setState(() {
      _type = t;
      _target.text = value > 0 ? _formatTargetForInput(value) : '';
    });
  }

  // ─── Submit ──────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final target = _parseTarget();
    if (target <= 0) {
      _showSnack('O valor alvo deve ser maior que zero.', success: false);
      return;
    }
    if (!_isEdit) {
      if (_scope == GoalScope.user && (_userId ?? '').isEmpty) {
        _showSnack('Selecione o corretor responsável pela meta.',
            success: false);
        return;
      }
      if (_scope == GoalScope.team && (_teamId ?? '').isEmpty) {
        _showSnack('Selecione a equipe responsável pela meta.',
            success: false);
        return;
      }
      if (_startDate == null || _endDate == null) {
        _showSnack('Informe as datas de início e término.', success: false);
        return;
      }
      if (_endDate!.isBefore(_startDate!)) {
        _showSnack('A data de término deve ser após a de início.',
            success: false);
        return;
      }
    }

    setState(() => _saving = true);

    if (_isEdit) {
      final res = await GoalService.instance.updateGoal(
        id: widget.goalId!,
        title: _title.text.trim(),
        description: _description.text.trim(),
        targetValue: target,
        status: _status,
        isActive: _isActive,
        color: _color,
        icon: _icon,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      if (res.success) {
        Navigator.of(context).pop(true);
      } else {
        _showSnack(res.message ?? 'Erro ao atualizar meta', success: false);
      }
      return;
    }

    final start = _startDate!;
    final end = _endDate!;
    final res = await GoalService.instance.createGoal(
      title: _title.text.trim(),
      description: _description.text.trim(),
      type: _type,
      period: _period,
      scope: _scope,
      targetValue: target,
      startDate: DateTime(start.year, start.month, start.day),
      endDate: DateTime(end.year, end.month, end.day, 23, 59, 59),
      userId: _scope == GoalScope.user ? _userId : null,
      teamId: _scope == GoalScope.team ? _teamId : null,
      color: _color,
      icon: _icon,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.success) {
      Navigator.of(context).pop(true);
    } else {
      _showSnack(res.message ?? 'Erro ao criar meta', success: false);
    }
  }

  void _showSnack(String message, {required bool success}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone = success
        ? (isDark ? AppColors.status.greenDarkMode : AppColors.status.green)
        : (isDark ? AppColors.status.errorDarkMode : AppColors.status.error);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: tone,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content:
            Text(message, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  // ─── Tema local dos campos (filled) ──────────────────────────────────────

  ThemeData _formTheme(BuildContext context) {
    final base = Theme.of(context);
    final isDark = base.brightness == Brightness.dark;
    final fill = isDark
        ? Colors.white.withValues(alpha: 0.045)
        : Colors.black.withValues(alpha: 0.025);
    final muted = ThemeHelpers.textSecondaryColor(context);
    OutlineInputBorder b(Color c, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: w == 0 ? BorderSide.none : BorderSide(color: c, width: w),
        );
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(primary: _accent),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: _accent,
        selectionColor: _accent.withValues(alpha: 0.18),
        selectionHandleColor: _accent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fill,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        labelStyle: TextStyle(
            color: muted, fontWeight: FontWeight.w600, fontSize: 13.5),
        floatingLabelStyle: TextStyle(
            color: _accent, fontWeight: FontWeight.w700, fontSize: 13.5),
        hintStyle: TextStyle(
            color: muted.withValues(alpha: 0.7), fontWeight: FontWeight.w500),
        prefixStyle: TextStyle(
            color: ThemeHelpers.textColor(context),
            fontWeight: FontWeight.w700),
        border: b(Colors.transparent, 0),
        enabledBorder: b(Colors.transparent, 0),
        focusedBorder: b(_accent, 1.6),
        errorBorder: b(
            Theme.of(context).brightness == Brightness.dark
                ? AppColors.status.errorDarkMode
                : AppColors.status.error,
            1.2),
        focusedErrorBorder: b(
            Theme.of(context).brightness == Brightness.dark
                ? AppColors.status.errorDarkMode
                : AppColors.status.error,
            1.6),
      ),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final title = _isEdit ? 'Editar meta' : 'Nova meta';

    Widget body;
    if (_loadingExisting) {
      body = _buildSkeleton(context);
    } else if (_loadError != null) {
      body = _buildLoadError(context);
    } else {
      body = _buildForm(context);
    }

    return AppScaffold(
      title: title,
      showBottomNavigation: false,
      showDrawer: false,
      body: body,
    );
  }

  Widget _buildForm(BuildContext context) {
    return Theme(
      data: _formTheme(context),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildIntro(context),
                    const SizedBox(height: 18),
                    _section(
                      context,
                      accent: _accent,
                      label: 'Identificação',
                      hint:
                          'Nome exibido em dashboards e relatórios para identificar a meta.',
                      first: true,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _title,
                            textCapitalization: TextCapitalization.sentences,
                            style: _fieldStyle(context),
                            decoration: const InputDecoration(
                              labelText: 'Título da meta *',
                              hintText: 'Ex: Meta de Vendas Novembro 2025',
                            ),
                            validator: (v) => (v ?? '').trim().isEmpty
                                ? 'Informe o título da meta'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _description,
                            textCapitalization: TextCapitalization.sentences,
                            style: _fieldStyle(context),
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Descrição',
                              hintText:
                                  'Objetivos, critérios de sucesso, observações…',
                              alignLabelWithHint: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_isEdit)
                      _buildCreateOnlyConfig(context)
                    else
                      _buildEditOnlyConfig(context),
                    _section(
                      context,
                      accent: _statusColor(context),
                      label: 'Valor alvo',
                      hint: _type.isCurrency
                          ? 'Valor monetário que deve ser atingido no período.'
                          : _type.isPercent
                              ? 'Percentual alvo (ex: 35,5).'
                              : 'Quantidade que deve ser atingida no período.',
                      child: TextFormField(
                        controller: _target,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: _targetFormatters,
                        style: _fieldStyle(context),
                        decoration: InputDecoration(
                          labelText: 'Valor alvo *',
                          prefixText: _type.isCurrency ? 'R\$ ' : null,
                          suffixText: _type.isPercent ? '%' : null,
                          hintText: _type.isCurrency ? '1.000.000,00' : null,
                        ),
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Informe o valor alvo'
                            : null,
                      ),
                    ),
                    if (!_isEdit)
                      _section(
                        context,
                        accent: _blue(context),
                        label: 'Período de vigência',
                        hint:
                            'Sugerido automaticamente pelo período — ajuste se necessário.',
                        child: Row(
                          children: [
                            Expanded(
                              child: _dateField(
                                context,
                                label: 'Início *',
                                value: _startDate,
                                onTap: () => _pickDate(isStart: true),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _dateField(
                                context,
                                label: 'Término *',
                                value: _endDate,
                                onTap: () => _pickDate(isStart: false),
                              ),
                            ),
                          ],
                        ),
                      ),
                    _section(
                      context,
                      accent: _purple(context),
                      label: 'Aparência',
                      hint: 'Cor e ícone exibidos nos cards e gráficos.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _colorPicker(context),
                          const SizedBox(height: 14),
                          _iconPicker(context),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  // ─── Intro editorial ─────────────────────────────────────────────────────

  Widget _buildIntro(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accent,
                boxShadow: [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.55),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Text(
              _isEdit ? 'EDITAR META' : 'NOVA META',
              style: theme.textTheme.labelSmall?.copyWith(
                color: _accent,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.2,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _isEdit
              ? (_existing?.title ?? 'Meta')
              : 'Defina o objetivo e acompanhe o progresso',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            color: ThemeHelpers.textColor(context),
            letterSpacing: -0.5,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          _isEdit
              ? 'Tipo, período e escopo não podem ser alterados após a criação.'
              : 'O progresso é calculado automaticamente a partir dos dados do CRM.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: secondary,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  // ─── Configuração (criação): tipo, período, escopo, responsável ──────────

  Widget _buildCreateOnlyConfig(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(
          context,
          accent: _blue(context),
          label: 'Tipo da meta',
          hint: 'Indicador que será acompanhado.',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in GoalType.selectable)
                _choiceChip(
                  context,
                  label: t.label,
                  icon: goalTypeIcon(t),
                  selected: _type == t,
                  accent: _blue(context),
                  onTap: () => _onTypeChanged(t),
                ),
            ],
          ),
        ),
        _section(
          context,
          accent: _purple(context),
          label: 'Período',
          hint: 'Recorrência da meta — define também as datas sugeridas.',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in GoalPeriod.selectable)
                _choiceChip(
                  context,
                  label: p.label,
                  selected: _period == p,
                  accent: _purple(context),
                  onTap: () => setState(() {
                    _period = p;
                    if (!_datesTouched) _applyDefaultDates();
                  }),
                ),
            ],
          ),
        ),
        _section(
          context,
          accent: _amber(context),
          label: 'Escopo',
          hint: 'Meta para a empresa inteira, uma equipe ou um corretor.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in GoalScope.selectable)
                    _choiceChip(
                      context,
                      label: s.label,
                      icon: s == GoalScope.user
                          ? LucideIcons.user
                          : s == GoalScope.team
                              ? LucideIcons.users2
                              : LucideIcons.building2,
                      selected: _scope == s,
                      accent: _amber(context),
                      onTap: () => setState(() {
                        _scope = s;
                        _userId = null;
                        _userName = null;
                        _teamId = null;
                        _teamName = null;
                      }),
                    ),
                ],
              ),
              if (_scope == GoalScope.user) ...[
                const SizedBox(height: 12),
                _pickerField(
                  context,
                  label: 'Corretor responsável *',
                  icon: LucideIcons.user,
                  value: _userName,
                  placeholder: _optionsLoading
                      ? 'Carregando corretores…'
                      : 'Selecionar corretor',
                  onTap: () => _openOptionPicker(
                    context,
                    title: 'Selecionar corretor',
                    options: _options.users,
                    selectedId: _userId,
                    onSelect: (o) => setState(() {
                      _userId = o.id;
                      _userName = o.name;
                    }),
                  ),
                ),
              ],
              if (_scope == GoalScope.team) ...[
                const SizedBox(height: 12),
                _pickerField(
                  context,
                  label: 'Equipe responsável *',
                  icon: LucideIcons.users2,
                  value: _teamName,
                  placeholder: _optionsLoading
                      ? 'Carregando equipes…'
                      : 'Selecionar equipe',
                  onTap: () => _openOptionPicker(
                    context,
                    title: 'Selecionar equipe',
                    options: _options.teams,
                    selectedId: _teamId,
                    onSelect: (o) => setState(() {
                      _teamId = o.id;
                      _teamName = o.name;
                    }),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ─── Configuração (edição): resumo fixo + status/ativação ────────────────

  Widget _buildEditOnlyConfig(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final dateFmt = DateFormat('dd/MM/yyyy', 'pt_BR');
    final g = _existing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(
          context,
          accent: _blue(context),
          label: 'Configuração',
          hint: 'Definida na criação — não pode ser alterada.',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _lockedChip(context, goalTypeIcon(_type), _type.label),
              _lockedChip(context, LucideIcons.calendarSync, _period.label),
              _lockedChip(
                context,
                _scope == GoalScope.user
                    ? LucideIcons.user
                    : _scope == GoalScope.team
                        ? LucideIcons.users2
                        : LucideIcons.building2,
                g?.ownerLabel ?? _scope.label,
              ),
              if (g?.startDate != null && g?.endDate != null)
                _lockedChip(
                  context,
                  LucideIcons.calendarRange,
                  '${dateFmt.format(g!.startDate!.toLocal())} – '
                  '${dateFmt.format(g.endDate!.toLocal())}',
                ),
            ],
          ),
        ),
        _section(
          context,
          accent: _statusColor(context),
          label: 'Status',
          hint: 'Situação atual da meta.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in GoalStatus.selectable)
                    _choiceChip(
                      context,
                      label: s.label,
                      selected: _status == s,
                      accent: goalStatusColor(context, s),
                      onTap: () => setState(() => _status = s),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () => setState(() => _isActive = !_isActive),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: ThemeHelpers.borderLightColor(context)),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.power,
                          size: 16,
                          color: _isActive
                              ? _statusColor(context)
                              : secondary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Meta ativa',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: ThemeHelpers.textColor(context),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Switch.adaptive(
                        value: _isActive,
                        activeTrackColor: _statusColor(context),
                        onChanged: (v) => setState(() => _isActive = v),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Pickers ─────────────────────────────────────────────────────────────

  void _openOptionPicker(
    BuildContext context, {
    required String title,
    required List<GoalOption> options,
    required String? selectedId,
    required ValueChanged<GoalOption> onSelect,
  }) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (ctx, scrollController) => Container(
            decoration: BoxDecoration(
              color: ThemeHelpers.backgroundColor(ctx),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border.all(
                color:
                    ThemeHelpers.borderColor(ctx).withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ThemeHelpers.borderColor(ctx)
                          .withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: ThemeHelpers.textColor(ctx),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: options.isEmpty
                      ? Center(
                          child: Text(
                            'Nenhuma opção disponível.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: ThemeHelpers.textSecondaryColor(ctx),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                          itemCount: options.length,
                          itemBuilder: (ctx, i) {
                            final o = options[i];
                            final selected = o.id == selectedId;
                            return ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor:
                                    _accent.withValues(alpha: 0.12),
                                child: Text(
                                  o.name.isNotEmpty
                                      ? o.name[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    color: _accent,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              title: Text(
                                o.name,
                                style: TextStyle(
                                  color: ThemeHelpers.textColor(ctx),
                                  fontWeight: selected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              trailing: selected
                                  ? Icon(LucideIcons.check,
                                      size: 18, color: _accent)
                                  : null,
                              onTap: () {
                                onSelect(o);
                                Navigator.of(ctx).pop();
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Controles auxiliares ────────────────────────────────────────────────

  TextStyle _fieldStyle(BuildContext context) => TextStyle(
        color: ThemeHelpers.textColor(context),
        fontWeight: FontWeight.w700,
        fontSize: 14.5,
        letterSpacing: -0.1,
      );

  Widget _dateField(
    BuildContext context, {
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    final fmt = DateFormat('dd/MM/yyyy', 'pt_BR');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: Icon(
            LucideIcons.calendarDays,
            size: 17,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
        ),
        child: Text(
          value == null ? 'Selecionar' : fmt.format(value),
          style: _fieldStyle(context),
        ),
      ),
    );
  }

  Widget _pickerField(
    BuildContext context, {
    required String label,
    required IconData icon,
    required String? value,
    required String placeholder,
    required VoidCallback onTap,
  }) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hasValue = (value ?? '').isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 17, color: secondary),
          suffixIcon:
              Icon(LucideIcons.chevronRight, size: 17, color: secondary),
        ),
        child: Text(
          hasValue ? value! : placeholder,
          style: hasValue
              ? _fieldStyle(context)
              : TextStyle(
                  color: secondary.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
        ),
      ),
    );
  }

  Widget _choiceChip(
    BuildContext context, {
    required String label,
    IconData? icon,
    required bool selected,
    required Color accent,
    required VoidCallback onTap,
  }) {
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

  Widget _lockedChip(BuildContext context, IconData icon, String label) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ThemeHelpers.borderLightColor(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: secondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: secondary,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _colorPicker(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final hex in kGoalColors)
          _ColorDot(
            color: parseGoalHex(hex)!,
            selected: _color.toUpperCase() == hex.toUpperCase(),
            onTap: () => setState(() => _color = hex),
          ),
      ],
    );
  }

  Widget _iconPicker(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final emoji in kGoalIcons)
          InkWell(
            onTap: () => setState(() => _icon = emoji),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: _icon == emoji
                    ? _accent.withValues(alpha: isDark ? 0.18 : 0.1)
                    : (isDark
                        ? AppColors.background.backgroundTertiaryDarkMode
                        : AppColors.background.backgroundTertiary),
                border: Border.all(
                  color: _icon == emoji
                      ? _accent
                      : ThemeHelpers.borderLightColor(context),
                  width: _icon == emoji ? 1.4 : 1,
                ),
              ),
              child: Text(emoji, style: const TextStyle(fontSize: 19)),
            ),
          ),
      ],
    );
  }

  // ─── Seções flush ────────────────────────────────────────────────────────

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
      padding: EdgeInsets.only(top: first ? 0 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!first) ...[
            Container(
              height: 1,
              color: ThemeHelpers.borderLightColor(context)
                  .withValues(alpha: 0.7),
            ),
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

  // ─── Footer com ações ────────────────────────────────────────────────────

  Widget _buildFooter(BuildContext context) {
    final mq = MediaQuery.of(context);
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
            child: OutlinedButton(
              onPressed:
                  _saving ? null : () => Navigator.of(context).pop(false),
              style: OutlinedButton.styleFrom(
                foregroundColor: ThemeHelpers.textSecondaryColor(context),
                side: BorderSide(color: ThemeHelpers.borderColor(context)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Cancelar'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: FilledButton.icon(
              onPressed: _saving ? null : _submit,
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
                _saving
                    ? 'Salvando…'
                    : _isEdit
                        ? 'Salvar alterações'
                        : 'Criar meta',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
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

  // ─── Estados de carga (edição) ───────────────────────────────────────────

  Widget _buildSkeleton(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          SkeletonText(width: 110, height: 12, borderRadius: 999),
          SizedBox(height: 10),
          SkeletonText(width: 240, height: 22),
          SizedBox(height: 24),
          SkeletonBox(width: double.infinity, height: 52, borderRadius: 14),
          SizedBox(height: 12),
          SkeletonBox(width: double.infinity, height: 84, borderRadius: 14),
          SizedBox(height: 24),
          SkeletonText(width: 130, height: 12, borderRadius: 999),
          SizedBox(height: 12),
          SkeletonBox(width: double.infinity, height: 52, borderRadius: 14),
          SizedBox(height: 24),
          SkeletonText(width: 130, height: 12, borderRadius: 999),
          SizedBox(height: 12),
          SkeletonBox(width: double.infinity, height: 42, borderRadius: 999),
        ],
      ),
    );
  }

  Widget _buildLoadError(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: danger.withValues(alpha: 0.12),
                border: Border.all(color: danger.withValues(alpha: 0.32)),
              ),
              child: Icon(LucideIcons.cloudOff, color: danger, size: 28),
            ),
            const SizedBox(height: 14),
            Text(
              _loadError ?? 'Erro ao carregar meta',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loadExisting,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Cores auxiliares ────────────────────────────────────────────────────

  Color _blue(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.status.blueDarkMode
          : AppColors.status.blue;

  Color _purple(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.status.purpleDarkMode
          : AppColors.status.purple;

  Color _amber(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;

  Color _statusColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.status.greenDarkMode
          : AppColors.status.green;
}

/// Bolinha de cor do picker — anel quando selecionada.
class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: selected
                ? ThemeHelpers.textColor(context)
                : Colors.transparent,
            width: 2.4,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.45),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: selected
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
            : null,
      ),
    );
  }
}
