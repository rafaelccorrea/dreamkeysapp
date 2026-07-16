import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/automation_models.dart';
import '../services/automation_service.dart';
import '../widgets/automation_card.dart';
import '../widgets/automation_config_form.dart';

/// Tela **Nova Automação** (`/automations/create`) — porte mobile-friendly do
/// CreateAutomationPage.tsx: o web cria direto do template com config padrão;
/// aqui viramos um builder em 3 etapas (gatilho → condições → ações) na cor da
/// marca (sem rainbow). No fim: POST do template + PATCH da config ajustada.
///
/// Devolve `true` no pop quando uma automação foi criada.
class CreateAutomationPage extends StatefulWidget {
  const CreateAutomationPage({super.key});

  @override
  State<CreateAutomationPage> createState() => _CreateAutomationPageState();
}

class _CreateAutomationPageState extends State<CreateAutomationPage> {
  static const double _kPagePadH = 16;

  List<AutomationTemplate> _templates = const [];
  Set<String> _existingTypes = const {};
  bool _loading = true;
  String? _error;

  int _step = 0; // 0 = gatilho, 1 = condições, 2 = ações
  AutomationTemplate? _selected;
  AutomationConfig _config = const AutomationConfig();
  bool _creating = false;

  bool get _isPrivileged {
    final role = ModuleAccessService.instance.userRole?.toLowerCase().trim();
    return role == 'admin' || role == 'master';
  }

  bool get _hasModule =>
      ModuleAccessService.instance.hasCompanyModule('automations');

  @override
  void initState() {
    super.initState();
    if (_isPrivileged && _hasModule) {
      _load();
    } else {
      _loading = false;
    }
  }

  Color _accent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.primary.primaryDarkMode
          : AppColors.primary.primary;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // Dispara em paralelo mantendo os tipos estáticos de cada resposta.
    final tplFuture = AutomationService.instance.getTemplates();
    final autoFuture = AutomationService.instance.getAutomations();
    final tplRes = await tplFuture;
    final autoRes = await autoFuture;
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (tplRes.success && tplRes.data != null) {
        _templates = tplRes.data!;
        if (autoRes.success && autoRes.data != null) {
          _existingTypes = autoRes.data!.map((a) => a.type).toSet();
        }
      } else {
        _error = tplRes.message ?? 'Erro ao carregar templates';
      }
    });
  }

  void _selectTemplate(AutomationTemplate template) {
    if (_existingTypes.contains(template.type)) return;
    setState(() {
      _selected = template;
      _config = template.defaultConfig;
    });
  }

  void _next() {
    if (_step == 0 && _selected == null) return;
    if (_step < 2) {
      setState(() => _step += 1);
    } else {
      _create();
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step -= 1);
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _create() async {
    final template = _selected;
    if (template == null || _creating) return;
    setState(() => _creating = true);

    final createRes =
        await AutomationService.instance.createFromTemplate(template.id);
    if (!mounted) return;

    if (!createRes.success || createRes.data == null) {
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(createRes.message ?? 'Erro ao criar automação'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Config ajustada nas etapas 2/3 → PATCH em cima da automação criada.
    final patchRes = await AutomationService.instance
        .updateConfig(createRes.data!.id, _config);
    if (!mounted) return;

    setState(() => _creating = false);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          patchRes.success
              ? 'Automação criada com sucesso!'
              : 'Automação criada, mas houve um erro ao salvar os ajustes. '
                  'Revise a configuração no detalhe.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.of(context).pop(true);
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_isPrivileged || !_hasModule) {
      return AppScaffold(
        title: 'Nova Automação',
        showBottomNavigation: false,
        showDrawer: false,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Text(
              !_isPrivileged
                  ? 'A criação de automações é restrita a administradores '
                      'da empresa.'
                  : 'Seu plano não inclui acesso ao módulo de Automações.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textSecondaryColor(context),
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ),
      );
    }

    return AppScaffold(
      title: 'Nova Automação',
      showBottomNavigation: false,
      showDrawer: false,
      body: Column(
        children: [
          _buildStepRail(context),
          Expanded(
            child: _loading
                ? _buildSkeleton(context)
                : _error != null
                    ? _buildError(context, _error!)
                    : SingleChildScrollView(
                        key: ValueKey('step-$_step'),
                        padding: const EdgeInsets.fromLTRB(
                            _kPagePadH, 14, _kPagePadH, 32),
                        child: _buildStepBody(context)
                            .animate(key: ValueKey('body-$_step'))
                            .fadeIn(duration: 220.ms),
                      ),
          ),
          if (!_loading && _error == null) _buildFooter(context),
        ],
      ),
    );
  }

  // ─── Rail de etapas (cor da marca, flush) ───────────────────────────────

  Widget _buildStepRail(BuildContext context) {
    final accent = _accent(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    const labels = ['Gatilho', 'Condições', 'Ações'];
    const icons = [LucideIcons.zap, LucideIcons.calendarClock, LucideIcons.send];

    return Container(
      padding: const EdgeInsets.fromLTRB(_kPagePadH, 12, _kPagePadH, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: i <= _step
                        ? accent
                        : ThemeHelpers.borderLightColor(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            _StepDot(
              index: i,
              label: labels[i],
              icon: icons[i],
              state: i < _step
                  ? _StepState.done
                  : i == _step
                      ? _StepState.current
                      : _StepState.upcoming,
              accent: accent,
              neutral: secondary,
              onTap: i < _step ? () => setState(() => _step = i) : null,
            ),
          ],
        ],
      ),
    );
  }

  // ─── Corpo por etapa ────────────────────────────────────────────────────

  Widget _buildStepBody(BuildContext context) {
    switch (_step) {
      case 0:
        return _buildTriggerStep(context);
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSelectedSummary(context),
            const SizedBox(height: 16),
            _stepHeader(
              context,
              eyebrow: 'ETAPA 2 · CONDIÇÕES',
              title: 'Quando disparar',
              hint: 'Ajuste a janela de antecedência e o disparo imediato. '
                  'Os valores vêm preenchidos com o padrão do template.',
            ),
            const SizedBox(height: 6),
            if (!_selected!.defaultConfig.hasTiming) _eventHint(context),
            AutomationConfigForm(
              key: ValueKey('cfg-timing-${_selected!.id}'),
              initialConfig: _config,
              onChanged: (c) => _config = c,
              showTiming: true,
              showRecipients: false,
              showChannels: false,
              showMessage: false,
            ),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSelectedSummary(context),
            const SizedBox(height: 16),
            _stepHeader(
              context,
              eyebrow: 'ETAPA 3 · AÇÕES',
              title: 'Quem recebe e como',
              hint: 'Escolha destinatários, canais e personalize a mensagem '
                  'enviada pela automação.',
            ),
            const SizedBox(height: 6),
            AutomationConfigForm(
              key: ValueKey('cfg-actions-${_selected!.id}'),
              initialConfig: _config,
              onChanged: (c) => _config = c,
              showTiming: false,
              showRecipients: true,
              showChannels: true,
              showMessage: true,
            ),
          ],
        );
    }
  }

  Widget _buildTriggerStep(BuildContext context) {
    // Agrupa por categoria preservando a ordem do backend.
    final groups = <AutomationCategory, List<AutomationTemplate>>{};
    for (final t in _templates) {
      groups.putIfAbsent(t.category, () => []).add(t);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepHeader(
          context,
          eyebrow: 'ETAPA 1 · GATILHO',
          title: 'O que dispara a automação',
          hint: 'Cada template já vem com uma configuração padrão pronta — '
              'você ajusta tudo nas próximas etapas.',
        ),
        const SizedBox(height: 8),
        if (_templates.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Text(
              'Nenhum template disponível no momento. Tente novamente mais '
              'tarde.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textSecondaryColor(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          for (final entry in groups.entries) ...[
            const SizedBox(height: 10),
            _categoryHeader(context, entry.key, entry.value.length),
            const SizedBox(height: 4),
            for (final template in entry.value)
              _TemplateRow(
                template: template,
                selected: _selected?.id == template.id,
                alreadyConfigured: _existingTypes.contains(template.type),
                onTap: () => _selectTemplate(template),
              ),
          ],
      ],
    );
  }

  Widget _categoryHeader(
      BuildContext context, AutomationCategory category, int count) {
    final theme = Theme.of(context);
    final tone = automationCategoryColor(context, category);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(
          category.label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: secondary,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color:
                ThemeHelpers.borderLightColor(context).withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w900,
              fontSize: 10,
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Container(
              height: 1,
              color: ThemeHelpers.borderLightColor(context)
                  .withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }

  /// Resumo do gatilho escolhido nas etapas 2/3.
  Widget _buildSelectedSummary(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final template = _selected!;
    final tone = automationCategoryColor(context, template.category);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(14),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: tone.withValues(alpha: isDark ? 0.18 : 0.1),
              border: Border.all(color: tone.withValues(alpha: 0.3)),
            ),
            child: Icon(
              automationIcon(template.icon, template.type),
              color: tone,
              size: 20,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  template.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    AutomationPill(label: template.category.label, color: tone),
                    AutomationPill(
                      label: template.typeLabel,
                      color: ThemeHelpers.textSecondaryColor(context),
                      icon: LucideIcons.zap,
                    ),
                  ],
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _step = 0),
            child: Text(
              'Trocar',
              style: TextStyle(
                color: _accent(context),
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _eventHint(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final blue = isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: blue.withValues(alpha: isDark ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: blue.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.info, size: 16, color: blue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Este gatilho é disparado pelo próprio evento — a janela de '
              'antecedência é opcional aqui.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.35,
                color: ThemeHelpers.textColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepHeader(
    BuildContext context, {
    required String eyebrow,
    required String title,
    required String hint,
  }) {
    final theme = Theme.of(context);
    final accent = _accent(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.5),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 7),
            Text(
              eyebrow,
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: ThemeHelpers.textColor(context),
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          hint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            height: 1.35,
          ),
        ),
      ],
    );
  }

  // ─── Rodapé (Voltar / Continuar / Criar) ────────────────────────────────

  Widget _buildFooter(BuildContext context) {
    final accent = _accent(context);
    final mq = MediaQuery.of(context);
    final canAdvance = _step == 0 ? _selected != null : true;
    final isLast = _step == 2;

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
              onPressed: _creating ? null : _back,
              icon: const Icon(LucideIcons.arrowLeft, size: 17),
              label: Text(_step == 0 ? 'Cancelar' : 'Voltar'),
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
              onPressed: canAdvance && !_creating ? _next : null,
              icon: _creating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      isLast ? LucideIcons.check : LucideIcons.arrowRight,
                      size: 17,
                    ),
              label: Text(
                _creating
                    ? 'Criando…'
                    : isLast
                        ? 'Criar automação'
                        : 'Continuar',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
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

  // ─── Estados ────────────────────────────────────────────────────────────

  /// Skeleton fiel às linhas de template da etapa 1.
  Widget _buildSkeleton(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(_kPagePadH, 20, _kPagePadH, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonText(width: 130, height: 11),
          const SizedBox(height: 8),
          const SkeletonText(width: 220, height: 18),
          const SizedBox(height: 6),
          const SkeletonText(width: double.infinity, height: 12),
          const SizedBox(height: 18),
          ...List.generate(
            5,
            (_) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 44, height: 44, borderRadius: 13),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SkeletonText(width: 160, height: 15),
                        SizedBox(height: 7),
                        SkeletonText(width: double.infinity, height: 12),
                        SizedBox(height: 5),
                        SkeletonText(width: 120, height: 11),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, String message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Bolinha do rail de etapas ───────────────────────────────────────────────

enum _StepState { done, current, upcoming }

class _StepDot extends StatelessWidget {
  final int index;
  final String label;
  final IconData icon;
  final _StepState state;
  final Color accent;
  final Color neutral;
  final VoidCallback? onTap;

  const _StepDot({
    required this.index,
    required this.label,
    required this.icon,
    required this.state,
    required this.accent,
    required this.neutral,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final active = state != _StepState.upcoming;
    final fg = active ? accent : neutral;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: state == _StepState.current
                  ? accent
                  : active
                      ? accent.withValues(alpha: isDark ? 0.2 : 0.12)
                      : ThemeHelpers.borderLightColor(context)
                          .withValues(alpha: 0.6),
              border: Border.all(
                color: active
                    ? accent
                    : ThemeHelpers.borderColor(context)
                        .withValues(alpha: 0.5),
                width: state == _StepState.current ? 0 : 1,
              ),
            ),
            child: Icon(
              state == _StepState.done ? LucideIcons.check : icon,
              size: 16,
              color: state == _StepState.current ? Colors.white : fg,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight:
                  state == _StepState.current ? FontWeight.w900 : FontWeight.w700,
              letterSpacing: 0.2,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Linha de template (etapa 1) ─────────────────────────────────────────────

class _TemplateRow extends StatelessWidget {
  final AutomationTemplate template;
  final bool selected;
  final bool alreadyConfigured;
  final VoidCallback onTap;

  const _TemplateRow({
    required this.template,
    required this.selected,
    required this.alreadyConfigured,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = automationCategoryColor(context, template.category);
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final days = template.defaultConfig.timingDays;

    return Opacity(
      opacity: alreadyConfigured ? 0.55 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: alreadyConfigured ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.symmetric(vertical: 5),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: isDark ? 0.10 : 0.05)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: 0.55)
                    : ThemeHelpers.borderLightColor(context),
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    color: tone.withValues(alpha: isDark ? 0.16 : 0.1),
                    border: Border.all(color: tone.withValues(alpha: 0.28)),
                  ),
                  child: Icon(
                    automationIcon(template.icon, template.type),
                    color: tone,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        template.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: ThemeHelpers.textColor(context),
                          letterSpacing: -0.2,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        template.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: neutral,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        children: [
                          AutomationSpecBit(
                            icon: LucideIcons.zap,
                            text: template.typeLabel,
                            color: neutral,
                          ),
                          if (days.isNotEmpty)
                            AutomationSpecBit(
                              icon: LucideIcons.calendarDays,
                              text: 'Dias: ${days.join(', ')}',
                              color: neutral,
                            ),
                          if (alreadyConfigured)
                            AutomationSpecBit(
                              icon: LucideIcons.circleCheck,
                              text: 'Já configurada',
                              color: green,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.only(top: 11),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? accent : Colors.transparent,
                    border: Border.all(
                      color: selected
                          ? accent
                          : ThemeHelpers.borderColor(context)
                              .withValues(alpha: 0.6),
                      width: selected ? 0 : 1.4,
                    ),
                  ),
                  child: selected
                      ? const Icon(LucideIcons.check,
                          size: 13, color: Colors.white)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
