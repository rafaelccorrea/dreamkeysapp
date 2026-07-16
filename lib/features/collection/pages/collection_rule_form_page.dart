import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/collection_models.dart';
import '../services/collection_service.dart';
import '../widgets/collection_message_card.dart'
    show collectionChannelColor, collectionChannelIcon;
import '../widgets/collection_rule_card.dart'
    show collectionTriggerColor, collectionTriggerIcon;

/// Formulário de régua de cobrança — criação (`/collection/rules/new`) e
/// edição (`/collection/rules/:id`), paridade com a
/// `CollectionRuleFormPage.tsx` do imobx-front no DNA do app: intro editorial,
/// seções flush com dot de cor semântica, campos *filled*, chips de escolha
/// para gatilho/canal e variáveis de template inseríveis com um toque.
class CollectionRuleFormPage extends StatefulWidget {
  /// `null` cria uma régua nova; preenchido edita a existente.
  final String? ruleId;

  const CollectionRuleFormPage({super.key, this.ruleId});

  @override
  State<CollectionRuleFormPage> createState() => _CollectionRuleFormPageState();
}

class _CollectionRuleFormPageState extends State<CollectionRuleFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _days = TextEditingController(text: '1');
  final _priority = TextEditingController(text: '1');
  final _subject = TextEditingController();
  final _message = TextEditingController();

  CollectionTrigger _trigger = CollectionTrigger.daysBeforeDue;
  CollectionChannel _channel = CollectionChannel.email;
  TimeOfDay _sendTime = const TimeOfDay(hour: 9, minute: 0);
  bool _isActive = true;

  CollectionRule? _existing;
  bool _loadingExisting = false;
  String? _loadError;
  bool _saving = false;

  bool get _isEdit => widget.ruleId != null;

  /// Variáveis suportadas pelos templates do backend (mesmas do web).
  static const _templateVars = [
    ('{{nome}}', 'Nome do cliente'),
    ('{{valor}}', 'Valor da parcela'),
    ('{{vencimento}}', 'Data de vencimento'),
    ('{{diasAtraso}}', 'Dias em atraso'),
  ];

  static const _triggers = [
    CollectionTrigger.daysBeforeDue,
    CollectionTrigger.onDueDate,
    CollectionTrigger.daysAfterDue,
  ];

  static const _channels = [
    CollectionChannel.email,
    CollectionChannel.whatsapp,
    CollectionChannel.sms,
  ];

  bool get _canManage =>
      ModuleAccessService.instance.hasPermission(CollectionAccess.manage);

  Color get _accent {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
  }

  @override
  void initState() {
    super.initState();
    if (_isEdit) _loadExisting();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _days.dispose();
    _priority.dispose();
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  // ─── Dados ───────────────────────────────────────────────────────────────

  Future<void> _loadExisting() async {
    setState(() {
      _loadingExisting = true;
      _loadError = null;
    });
    final res = await CollectionService.instance.getRule(widget.ruleId!);
    if (!mounted) return;
    setState(() {
      _loadingExisting = false;
      if (res.success && res.data != null) {
        _prefill(res.data!);
      } else {
        _loadError = res.message ?? 'Erro ao carregar régua';
      }
    });
  }

  void _prefill(CollectionRule r) {
    _existing = r;
    _name.text = r.name;
    _description.text = r.description ?? '';
    _trigger =
        r.trigger == CollectionTrigger.unknown ? _trigger : r.trigger;
    _days.text = '${r.triggerDays.clamp(1, 365)}';
    _channel =
        r.channel == CollectionChannel.unknown ? _channel : r.channel;
    _priority.text = '${r.priority.clamp(1, 999)}';
    _subject.text = r.subjectTemplate ?? '';
    _message.text = r.messageTemplate;
    _isActive = r.isActive;
    _sendTime = _parseTime(r.sendTime) ?? _sendTime;
  }

  static TimeOfDay? _parseTime(String raw) {
    final parts = raw.trim().split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    return TimeOfDay(hour: h, minute: m);
  }

  String get _sendTimeLabel =>
      '${_sendTime.hour.toString().padLeft(2, '0')}:'
      '${_sendTime.minute.toString().padLeft(2, '0')}';

  /// `HH:mm:ss` — mesmo formato do `normalizeTime` do web.
  String get _sendTimePayload => '$_sendTimeLabel:00';

  int _clampedInt(TextEditingController c, int min, int max, int fallback) {
    final n = int.tryParse(c.text.trim());
    if (n == null) return fallback;
    return n.clamp(min, max);
  }

  // ─── Ações ───────────────────────────────────────────────────────────────

  Future<void> _pickSendTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _sendTime,
      helpText: 'Horário de envio',
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _sendTime = picked);
  }

  /// Insere a variável na posição do cursor da mensagem.
  void _insertVariable(String variable) {
    final text = _message.text;
    final sel = _message.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final updated = text.replaceRange(start, end, variable);
    _message.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: start + variable.length),
    );
    setState(() {});
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_channel == CollectionChannel.email &&
        _subject.text.trim().isEmpty) {
      _showSnack('Informe o assunto do e-mail.', success: false);
      return;
    }

    final payload = CollectionRulePayload(
      name: _name.text.trim(),
      description: _description.text.trim(),
      trigger: _trigger,
      triggerDays: _trigger.usesDays ? _clampedInt(_days, 1, 365, 1) : 1,
      channel: _channel,
      messageTemplate: _message.text.trim(),
      subjectTemplate: _subject.text.trim(),
      isActive: _isActive,
      priority: _clampedInt(_priority, 1, 999, 1),
      sendTime: _sendTimePayload,
    );

    setState(() => _saving = true);
    final res = _isEdit
        ? await CollectionService.instance.updateRule(widget.ruleId!, payload)
        : await CollectionService.instance.createRule(payload);
    if (!mounted) return;
    setState(() => _saving = false);

    if (res.success) {
      _showSnack(
        _isEdit ? 'Régua atualizada com sucesso!' : 'Régua criada com sucesso!',
        success: true,
      );
      Navigator.of(context).pop(true);
    } else {
      _showSnack(res.message ?? 'Erro ao salvar régua', success: false);
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
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
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
        border: b(Colors.transparent, 0),
        enabledBorder: b(Colors.transparent, 0),
        focusedBorder: b(_accent, 1.6),
        errorBorder: b(danger, 1.2),
        focusedErrorBorder: b(danger, 1.6),
      ),
    );
  }

  TextStyle _fieldStyle(BuildContext context) => TextStyle(
        color: ThemeHelpers.textColor(context),
        fontWeight: FontWeight.w700,
        fontSize: 14.5,
        letterSpacing: -0.1,
      );

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final title = _isEdit ? 'Editar régua' : 'Nova régua';

    if (!_canManage) {
      return AppScaffold(
        title: title,
        showBottomNavigation: false,
        showDrawer: false,
        body: const _DeniedView(),
      );
    }

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
                          'Nome exibido na lista de regras e no histórico de cobranças.',
                      first: true,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _name,
                            textCapitalization: TextCapitalization.sentences,
                            style: _fieldStyle(context),
                            decoration: const InputDecoration(
                              labelText: 'Nome da régua *',
                              hintText: 'Ex: Lembrete 3 dias antes',
                            ),
                            validator: (v) => (v ?? '').trim().isEmpty
                                ? 'Informe o nome da régua'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _description,
                            textCapitalization: TextCapitalization.sentences,
                            style: _fieldStyle(context),
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Descrição',
                              hintText: 'Descrição opcional da régua',
                              alignLabelWithHint: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _section(
                      context,
                      accent: collectionTriggerColor(context, _trigger),
                      label: 'Gatilho',
                      hint:
                          'Quando a cobrança dispara em relação ao vencimento da parcela.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final t in _triggers)
                                _choiceChip(
                                  context,
                                  label: t.label,
                                  icon: collectionTriggerIcon(t),
                                  selected: _trigger == t,
                                  accent: collectionTriggerColor(context, t),
                                  onTap: () => setState(() => _trigger = t),
                                ),
                            ],
                          ),
                          if (_trigger.usesDays) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _days,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(3),
                              ],
                              style: _fieldStyle(context),
                              decoration: InputDecoration(
                                labelText: _trigger ==
                                        CollectionTrigger.daysBeforeDue
                                    ? 'Dias antes do vencimento *'
                                    : 'Dias após o vencimento *',
                                hintText: '1 a 365',
                                suffixText: 'dias',
                              ),
                              validator: (v) {
                                if (!_trigger.usesDays) return null;
                                final n = int.tryParse((v ?? '').trim());
                                if (n == null || n < 1 || n > 365) {
                                  return 'Informe um valor entre 1 e 365';
                                }
                                return null;
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                    _section(
                      context,
                      accent: collectionChannelColor(context, _channel),
                      label: 'Canal de envio',
                      hint: 'Por onde a mensagem chega ao cliente.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final c in _channels)
                                _choiceChip(
                                  context,
                                  label: c.label,
                                  icon: collectionChannelIcon(c),
                                  selected: _channel == c,
                                  accent: collectionChannelColor(context, c),
                                  onTap: () => setState(() => _channel = c),
                                ),
                            ],
                          ),
                          if (_channel == CollectionChannel.email) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _subject,
                              textCapitalization: TextCapitalization.sentences,
                              style: _fieldStyle(context),
                              decoration: const InputDecoration(
                                labelText: 'Assunto do email *',
                                hintText:
                                    'Ex: Lembrete de pagamento - {{nome}}',
                              ),
                              validator: (v) =>
                                  _channel == CollectionChannel.email &&
                                          (v ?? '').trim().isEmpty
                                      ? 'Informe o assunto do e-mail'
                                      : null,
                            ),
                          ],
                        ],
                      ),
                    ),
                    _section(
                      context,
                      accent: _amber(context),
                      label: 'Mensagem',
                      hint:
                          'Texto enviado ao cliente — toque numa variável para inseri-la.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _message,
                            textCapitalization: TextCapitalization.sentences,
                            style: _fieldStyle(context),
                            maxLines: 6,
                            decoration: const InputDecoration(
                              labelText: 'Mensagem *',
                              hintText:
                                  'Olá {{nome}}, sua parcela de {{valor}} vence em {{vencimento}}…',
                              alignLabelWithHint: true,
                            ),
                            validator: (v) => (v ?? '').trim().isEmpty
                                ? 'Informe a mensagem'
                                : null,
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final (variable, meaning) in _templateVars)
                                _variableChip(context, variable, meaning),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _section(
                      context,
                      accent: _green(context),
                      label: 'Disparo',
                      hint:
                          'Prioridade define a ordem entre regras; o horário é o do envio diário.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _priority,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(3),
                                  ],
                                  style: _fieldStyle(context),
                                  decoration: const InputDecoration(
                                    labelText: 'Prioridade *',
                                    hintText: '1 a 999',
                                  ),
                                  validator: (v) {
                                    final n = int.tryParse((v ?? '').trim());
                                    if (n == null || n < 1 || n > 999) {
                                      return 'Entre 1 e 999';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: InkWell(
                                  onTap: _pickSendTime,
                                  borderRadius: BorderRadius.circular(14),
                                  child: InputDecorator(
                                    decoration: InputDecoration(
                                      labelText: 'Horário de envio *',
                                      suffixIcon: Icon(
                                        LucideIcons.clock3,
                                        size: 17,
                                        color: ThemeHelpers.textSecondaryColor(
                                            context),
                                      ),
                                    ),
                                    child: Text(
                                      _sendTimeLabel,
                                      style: _fieldStyle(context),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          InkWell(
                            onTap: () =>
                                setState(() => _isActive = !_isActive),
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color:
                                        ThemeHelpers.borderLightColor(context)),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    LucideIcons.power,
                                    size: 16,
                                    color: _isActive
                                        ? _green(context)
                                        : ThemeHelpers.textSecondaryColor(
                                            context),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Régua ativa',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color:
                                                ThemeHelpers.textColor(context),
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  Switch.adaptive(
                                    value: _isActive,
                                    activeTrackColor: _green(context),
                                    onChanged: (v) =>
                                        setState(() => _isActive = v),
                                  ),
                                ],
                              ),
                            ),
                          ),
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
              _isEdit ? 'EDITAR RÉGUA' : 'NOVA RÉGUA',
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
              ? (_existing?.name.trim().isNotEmpty ?? false
                  ? _existing!.name.trim()
                  : 'Régua de cobrança')
              : 'Configure quando e como cobrar',
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
              ? 'Altere os dados da régua — as próximas cobranças já saem com a nova configuração.'
              : 'A régua dispara a mensagem automaticamente no gatilho e horário definidos.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: secondary,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  // ─── Chips ───────────────────────────────────────────────────────────────

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
            color: selected ? accent : ThemeHelpers.borderLightColor(context),
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

  /// Chip de variável de template — insere no cursor da mensagem.
  Widget _variableChip(BuildContext context, String variable, String meaning) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone = _amber(context);
    return Tooltip(
      message: meaning,
      child: InkWell(
        onTap: () => _insertVariable(variable),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: tone.withValues(alpha: isDark ? 0.13 : 0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: tone.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.braces, size: 12, color: tone),
              const SizedBox(width: 5),
              Text(
                variable,
                style: TextStyle(
                  color: tone,
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
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
              color:
                  ThemeHelpers.borderLightColor(context).withValues(alpha: 0.7),
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
                        : 'Criar régua',
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
          SkeletonBox(width: double.infinity, height: 72, borderRadius: 14),
          SizedBox(height: 24),
          SkeletonText(width: 130, height: 12, borderRadius: 999),
          SizedBox(height: 12),
          SkeletonBox(width: double.infinity, height: 42, borderRadius: 999),
          SizedBox(height: 24),
          SkeletonText(width: 130, height: 12, borderRadius: 999),
          SizedBox(height: 12),
          SkeletonBox(width: double.infinity, height: 120, borderRadius: 14),
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
              _loadError ?? 'Erro ao carregar régua',
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

  Color _amber(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;

  Color _green(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.status.greenDarkMode
          : AppColors.status.green;
}

class _DeniedView extends StatelessWidget {
  const _DeniedView();

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.lock, size: 38, color: secondary),
            const SizedBox(height: 12),
            Text(
              'Você não tem acesso ao cadastro de réguas.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Solicite ao administrador a permissão de gerenciar cobranças.',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
