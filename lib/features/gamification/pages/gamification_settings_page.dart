import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/gamification_models.dart';
import '../services/gamification_service.dart';
import '../widgets/gamification_ui.dart';

/// Configuração da **Gamificação** da empresa — ativação, pontuação por
/// ação, visibilidade, mensagens e notificações.
/// Paridade `GamificationSettingsPage.tsx` (`PUT /gamification/config`).
class GamificationSettingsPage extends StatefulWidget {
  const GamificationSettingsPage({super.key});

  @override
  State<GamificationSettingsPage> createState() =>
      _GamificationSettingsPageState();
}

class _GamificationSettingsPageState extends State<GamificationSettingsPage> {
  static const double _padH = 16;

  bool _loading = true;
  bool _saving = false;
  String? _error;
  GamificationConfig? _config;

  final _welcomeController = TextEditingController();
  final _rankingController = TextEditingController();
  final Map<String, TextEditingController> _pointControllers = {};

  bool get _canConfigure =>
      ModuleAccessService.instance.hasPermission('gamification:configure');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _welcomeController.dispose();
    _rankingController.dispose();
    for (final c in _pointControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _pointsCtrl(String key, String initial) {
    return _pointControllers.putIfAbsent(
      key,
      () => TextEditingController(text: initial),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await GamificationService.instance.getConfig();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _config = res.data;
        _welcomeController.text = _config!.welcomeMessage ?? '';
        _rankingController.text = _config!.rankingMessage ?? '';
        for (final c in _pointControllers.values) {
          c.dispose();
        }
        _pointControllers.clear();
      } else {
        _error = res.message ?? 'Erro ao carregar configuração';
      }
    });
  }

  int _intFrom(String key, int fallback) {
    final c = _pointControllers[key];
    if (c == null) return fallback;
    return int.tryParse(c.text.trim()) ?? fallback;
  }

  double _doubleFrom(String key, double fallback) {
    final c = _pointControllers[key];
    if (c == null) return fallback;
    final raw = c.text.trim().replaceAll(',', '.');
    return double.tryParse(raw) ?? fallback;
  }

  Future<void> _save() async {
    final base = _config;
    if (base == null || _saving) return;

    final updated = base.copyWith(
      pointsPropertySale: _intFrom('propertySale', base.pointsPropertySale),
      pointsRentalCreated: _intFrom('rentalCreated', base.pointsRentalCreated),
      pointsCommissionMultiplier:
          _doubleFrom('commissionMultiplier', base.pointsCommissionMultiplier),
      pointsNewClient: _intFrom('newClient', base.pointsNewClient),
      pointsClientContact: _intFrom('clientContact', base.pointsClientContact),
      pointsMeetingScheduled:
          _intFrom('meetingScheduled', base.pointsMeetingScheduled),
      pointsPropertyCreated:
          _intFrom('propertyCreated', base.pointsPropertyCreated),
      pointsInspectionCompleted:
          _intFrom('inspectionCompleted', base.pointsInspectionCompleted),
      pointsTaskCompleted: _intFrom('taskCompleted', base.pointsTaskCompleted),
      pointsKeyDelivered: _intFrom('keyDelivered', base.pointsKeyDelivered),
      welcomeMessage: _welcomeController.text.trim(),
      rankingMessage: _rankingController.text.trim(),
    );

    setState(() => _saving = true);
    final res = await GamificationService.instance.updateConfig(updated);
    if (!mounted) return;
    setState(() => _saving = false);

    if (res.success) {
      setState(() => _config = res.data ?? updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuração salva com sucesso!')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message ?? 'Erro ao salvar configuração'),
          backgroundColor: gamDanger(context),
        ),
      );
    }
  }

  void _patch(GamificationConfig Function(GamificationConfig) fn) {
    final base = _config;
    if (base == null) return;
    setState(() => _config = fn(base));
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canConfigure) {
      return const AppScaffold(
        title: 'Configurar Gamificação',
        showBottomNavigation: false,
        body: GamDeniedView(
          what: 'configuração da gamificação',
          permission: 'gamification:configure',
        ),
      );
    }

    return AppScaffold(
      title: 'Configurar Gamificação',
      showBottomNavigation: false,
      body: _loading
          ? _buildSkeleton(context)
          : _error != null
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(_padH, 60, _padH, 24),
                  child: GamErrorState(message: _error!, onRetry: _load),
                )
              : _buildForm(context),
    );
  }

  Widget _buildForm(BuildContext context) {
    final config = _config!;
    final theme = Theme.of(context);
    final accent = gamAccentColor(context);
    final green = gamGreen(context);
    final blue = gamBlue(context);
    final amber = gamAmber(context);
    final purple = gamPurple(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(_padH, 12, _padH, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Hero editorial ────────────────────────────────────────
                Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: config.isEnabled ? green : amber,
                        boxShadow: [
                          BoxShadow(
                            color: (config.isEnabled ? green : amber)
                                .withValues(alpha: 0.55),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      'CONFIGURAÇÃO',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.2,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Regras do jogo',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Defina quanto vale cada ação, o que aparece para a equipe '
                  'e como todos são avisados.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: secondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),

                // ── Ativação ─────────────────────────────────────────────
                _masterSwitchCard(context, config),
                const SizedBox(height: 24),

                // ── Pontuação ────────────────────────────────────────────
                const GamSubsectionHeader(
                  label: 'Pontos de vendas',
                  icon: LucideIcons.badgeDollarSign,
                ),
                const SizedBox(height: 12),
                _pointsGrid(context, green, [
                  _PointField('propertySale', 'Venda de imóvel',
                      '${config.pointsPropertySale}'),
                  _PointField('rentalCreated', 'Aluguel criado',
                      '${config.pointsRentalCreated}'),
                ]),
                const SizedBox(height: 10),
                _pointField(
                  context,
                  tone: green,
                  field: _PointField(
                    'commissionMultiplier',
                    'Multiplicador de comissão',
                    _fmtMultiplier(config.pointsCommissionMultiplier),
                    suffix: 'pts/R\$',
                    decimal: true,
                    hint: 'Pontos por cada R\$ 1 de comissão',
                  ),
                ),
                const SizedBox(height: 22),
                const GamSubsectionHeader(
                  label: 'Pontos de relacionamento',
                  icon: LucideIcons.heartHandshake,
                ),
                const SizedBox(height: 12),
                _pointsGrid(context, blue, [
                  _PointField(
                      'newClient', 'Novo cliente', '${config.pointsNewClient}'),
                  _PointField('clientContact', 'Contato com cliente',
                      '${config.pointsClientContact}'),
                ]),
                const SizedBox(height: 10),
                _pointField(
                  context,
                  tone: blue,
                  field: _PointField('meetingScheduled', 'Reunião agendada',
                      '${config.pointsMeetingScheduled}'),
                ),
                const SizedBox(height: 22),
                const GamSubsectionHeader(
                  label: 'Pontos de atividade',
                  icon: LucideIcons.zap,
                ),
                const SizedBox(height: 12),
                _pointsGrid(context, amber, [
                  _PointField('propertyCreated', 'Imóvel cadastrado',
                      '${config.pointsPropertyCreated}'),
                  _PointField('inspectionCompleted', 'Vistoria concluída',
                      '${config.pointsInspectionCompleted}'),
                ]),
                const SizedBox(height: 10),
                _pointsGrid(context, amber, [
                  _PointField('taskCompleted', 'Tarefa completada',
                      '${config.pointsTaskCompleted}'),
                  _PointField('keyDelivered', 'Chave entregue',
                      '${config.pointsKeyDelivered}'),
                ]),
                const SizedBox(height: 24),

                // ── Visibilidade ─────────────────────────────────────────
                const GamSubsectionHeader(
                  label: 'Visibilidade',
                  icon: LucideIcons.eye,
                ),
                const SizedBox(height: 6),
                _switchRow(
                  context,
                  icon: LucideIcons.user,
                  label: 'Mostrar ranking individual',
                  value: config.showIndividualRanking,
                  tone: accent,
                  onChanged: (v) =>
                      _patch((c) => c.copyWith(showIndividualRanking: v)),
                ),
                _switchRow(
                  context,
                  icon: LucideIcons.users2,
                  label: 'Mostrar ranking de equipes',
                  value: config.showTeamRanking,
                  tone: purple,
                  onChanged: (v) =>
                      _patch((c) => c.copyWith(showTeamRanking: v)),
                ),
                _switchRow(
                  context,
                  icon: LucideIcons.award,
                  label: 'Mostrar conquistas',
                  value: config.showAchievements,
                  tone: amber,
                  onChanged: (v) =>
                      _patch((c) => c.copyWith(showAchievements: v)),
                ),
                const SizedBox(height: 22),

                // ── Mensagens ────────────────────────────────────────────
                const GamSubsectionHeader(
                  label: 'Mensagens personalizadas',
                  icon: LucideIcons.messageSquareText,
                ),
                const SizedBox(height: 12),
                _messageField(
                  context,
                  controller: _welcomeController,
                  label: 'Mensagem de boas-vindas',
                  hint: 'Exibida no topo da página de gamificação…',
                  lines: 3,
                ),
                const SizedBox(height: 12),
                _messageField(
                  context,
                  controller: _rankingController,
                  label: 'Mensagem no ranking',
                  hint: 'Exibida no topo do ranking…',
                  lines: 2,
                ),
                const SizedBox(height: 22),

                // ── Notificações ─────────────────────────────────────────
                const GamSubsectionHeader(
                  label: 'Notificações',
                  icon: LucideIcons.bell,
                ),
                const SizedBox(height: 6),
                _switchRow(
                  context,
                  icon: LucideIcons.partyPopper,
                  label: 'Notificar ao desbloquear conquista',
                  value: config.notifyNewAchievement,
                  tone: green,
                  onChanged: (v) =>
                      _patch((c) => c.copyWith(notifyNewAchievement: v)),
                ),
                _switchRow(
                  context,
                  icon: LucideIcons.trendingUp,
                  label: 'Notificar mudança de posição no ranking',
                  value: config.notifyRankChange,
                  tone: blue,
                  onChanged: (v) =>
                      _patch((c) => c.copyWith(notifyRankChange: v)),
                ),
                _switchRow(
                  context,
                  icon: LucideIcons.calendarClock,
                  label: 'Enviar resumo semanal',
                  value: config.notifyWeeklySummary,
                  tone: purple,
                  onChanged: (v) =>
                      _patch((c) => c.copyWith(notifyWeeklySummary: v)),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        // ── Barra de salvar ───────────────────────────────────────────────
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
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(LucideIcons.save, size: 17),
              label: Text(
                _saving ? 'Salvando…' : 'Salvar configuração',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.1,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _fmtMultiplier(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toString().replaceAll('.', ',');
  }

  // ─── Blocos ────────────────────────────────────────────────────────────────

  Widget _masterSwitchCard(BuildContext context, GamificationConfig config) {
    final theme = Theme.of(context);
    final green = gamGreen(context);
    final amber = gamAmber(context);
    final tone = config.isEnabled ? green : amber;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: tone.withValues(alpha: isDark ? 0.2 : 0.12),
            ),
            child: Icon(
              config.isEnabled ? LucideIcons.gamepad2 : LucideIcons.pause,
              color: tone,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  config.isEnabled
                      ? 'Gamificação ativada'
                      : 'Gamificação desativada',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  config.isEnabled
                      ? 'Pontos, rankings e conquistas visíveis para a equipe.'
                      : 'Ninguém acessa a página de gamificação enquanto '
                          'estiver desativada.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: config.isEnabled,
            activeThumbColor: green,
            onChanged: (v) => _patch((c) => c.copyWith(isEnabled: v)),
          ),
        ],
      ),
    );
  }

  Widget _pointsGrid(
      BuildContext context, Color tone, List<_PointField> fields) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < fields.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: _pointField(context, tone: tone, field: fields[i])),
        ],
      ],
    );
  }

  Widget _pointField(
    BuildContext context, {
    required Color tone,
    required _PointField field,
  }) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final isDark = theme.brightness == Brightness.dark;
    final fill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final controller = _pointsCtrl(field.key, field.initial);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          field.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: secondary,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: field.decimal
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.number,
          inputFormatters: [
            if (field.decimal)
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
            else
              FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(8),
          ],
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: ThemeHelpers.textColor(context),
          ),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: fill,
            suffixText: field.suffix ?? 'pts',
            suffixStyle: theme.textTheme.labelSmall?.copyWith(
              color: tone,
              fontWeight: FontWeight.w900,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: tone.withValues(alpha: 0.55)),
            ),
          ),
        ),
        if (field.hint != null) ...[
          const SizedBox(height: 4),
          Text(
            field.hint!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: secondary,
              fontSize: 10.5,
            ),
          ),
        ],
      ],
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
          Icon(icon, size: 16, color: value ? tone : ThemeHelpers.textSecondaryColor(context)),
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

  Widget _messageField(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required String hint,
    required int lines,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: secondary,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: lines,
          maxLength: 300,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: ThemeHelpers.textColor(context)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: theme.textTheme.bodySmall?.copyWith(color: secondary),
            filled: true,
            fillColor: fill,
            counterText: '',
            contentPadding: const EdgeInsets.all(12),
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
          ),
        ),
      ],
    );
  }

  // ─── Skeleton fiel ─────────────────────────────────────────────────────────

  Widget _buildSkeleton(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(_padH, 16, _padH, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonText(width: 120, height: 11, borderRadius: 999),
          const SizedBox(height: 12),
          const SkeletonText(width: 180, height: 26, borderRadius: 8),
          const SizedBox(height: 8),
          const SkeletonText(width: double.infinity, height: 13),
          const SizedBox(height: 20),
          const SkeletonBox(width: double.infinity, height: 74, borderRadius: 16),
          const SizedBox(height: 24),
          for (var s = 0; s < 3; s++) ...[
            const SkeletonText(width: 160, height: 11),
            const SizedBox(height: 12),
            Row(
              children: const [
                Expanded(child: SkeletonBox(height: 48, borderRadius: 12)),
                SizedBox(width: 10),
                Expanded(child: SkeletonBox(height: 48, borderRadius: 12)),
              ],
            ),
            const SizedBox(height: 22),
          ],
        ],
      ),
    );
  }
}

class _PointField {
  final String key;
  final String label;
  final String initial;
  final String? suffix;
  final bool decimal;
  final String? hint;

  const _PointField(
    this.key,
    this.label,
    this.initial, {
    this.suffix,
    this.decimal = false,
    this.hint,
  });
}
