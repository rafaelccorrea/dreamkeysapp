import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/automation_models.dart';
import '../services/automation_service.dart';
import '../widgets/automation_card.dart';
import '../widgets/automation_config_form.dart';

/// Tela **Configurar Automação** (`/automations/:id`) — paridade com
/// AutomationDetailsPage.tsx: cabeçalho flush com eyebrow da categoria +
/// título + pills, faixa de estatísticas, toggle e histórico como ações no
/// próprio contexto, e o formulário de configuração completo com salvar.
/// A lista recarrega ao voltar (pop sem resultado é suficiente).
class AutomationDetailsPage extends StatefulWidget {
  final String automationId;

  const AutomationDetailsPage({super.key, required this.automationId});

  @override
  State<AutomationDetailsPage> createState() => _AutomationDetailsPageState();
}

class _AutomationDetailsPageState extends State<AutomationDetailsPage> {
  static const double _kPagePadH = 16;

  Automation? _automation;
  AutomationStatistics _stats = AutomationStatistics.zero;
  AutomationConfig _config = const AutomationConfig();
  bool _loading = true;
  String? _error;
  bool _saving = false;
  bool _toggling = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
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
    final detailFuture = AutomationService.instance.getById(widget.automationId);
    final statsFuture =
        AutomationService.instance.getStatistics(widget.automationId);
    final detailRes = await detailFuture;
    final statsRes = await statsFuture;
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (detailRes.success && detailRes.data != null) {
        _automation = detailRes.data;
        _config = detailRes.data!.config;
        _dirty = false;
        if (statsRes.success && statsRes.data != null) {
          _stats = statsRes.data!;
        } else {
          // Fallback: os contadores também vivem na própria automação.
          _stats = AutomationStatistics(
            totalExecutions: detailRes.data!.executionCount,
            successfulExecutions: detailRes.data!.successfulExecutions,
            failedExecutions: detailRes.data!.failedExecutions,
            lastExecution: detailRes.data!.lastExecutionAt,
            averageExecutionTime: 0,
          );
        }
      } else {
        _error = detailRes.message ?? 'Erro ao carregar automação';
      }
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _toggle() async {
    final automation = _automation;
    if (automation == null || _toggling) return;
    setState(() => _toggling = true);
    final res = await AutomationService.instance
        .toggle(automation.id, !automation.isActive);
    if (!mounted) return;
    setState(() {
      _toggling = false;
      if (res.success && res.data != null) {
        _automation = res.data;
      }
    });
    _snack(
      res.success
          ? (res.data!.isActive ? 'Automação ativada' : 'Automação desativada')
          : (res.message ?? 'Erro ao alternar automação'),
    );
  }

  Future<void> _save() async {
    final automation = _automation;
    if (automation == null || _saving) return;
    setState(() => _saving = true);
    final res =
        await AutomationService.instance.updateConfig(automation.id, _config);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (res.success && res.data != null) {
        _automation = res.data;
        _config = res.data!.config;
        _dirty = false;
      }
    });
    _snack(
      res.success
          ? 'Configurações salvas com sucesso'
          : (res.message ?? 'Erro ao salvar configurações'),
    );
  }

  void _openHistory() {
    final automation = _automation;
    if (automation == null) return;
    Navigator.of(context).pushNamed(
      '/automations/${automation.id}/history',
      arguments: {'automationName': automation.name},
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Configurar Automação',
      showBottomNavigation: false,
      showDrawer: false,
      body: _loading
          ? _buildSkeleton(context)
          : _error != null
              ? _buildError(context, _error!)
              : _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final automation = _automation!;
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            color: _accent(context),
            onRefresh: _load,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                  _kPagePadH, 12, _kPagePadH, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context, automation),
                  const SizedBox(height: 16),
                  _buildStatusRow(context, automation),
                  const SizedBox(height: 18),
                  _buildStatsStrip(context),
                  const SizedBox(height: 20),
                  AutomationConfigForm(
                    key: ValueKey('cfg-${automation.id}-${automation.updatedAt}'),
                    initialConfig: _config,
                    onChanged: (c) {
                      _config = c;
                      if (!_dirty) setState(() => _dirty = true);
                    },
                  ),
                ],
              ).animate().fadeIn(duration: 240.ms),
            ),
          ),
        ),
        _buildSaveBar(context),
      ],
    );
  }

  // ─── Cabeçalho flush ────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context, Automation automation) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = automationCategoryColor(context, automation.category);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: tone.withValues(alpha: isDark ? 0.18 : 0.1),
            border: Border.all(color: tone.withValues(alpha: 0.3)),
          ),
          child: Icon(
            automationIcon(automation.icon, automation.type),
            color: tone,
            size: 23,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: tone,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: tone.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    automation.category.label.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                automation.name,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: -0.4,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                automation.description.trim().isNotEmpty
                    ? automation.description.trim()
                    : 'Sem descrição',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: secondary,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  AutomationPill(
                    label: automation.typeLabel,
                    color: secondary,
                    icon: LucideIcons.zap,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Status + ações no próprio item ─────────────────────────────────────

  Widget _buildStatusRow(BuildContext context, Automation automation) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final tone = automation.isActive ? green : neutral;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(14),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Row(
        children: [
          Icon(
            automation.isActive ? LucideIcons.zap : LucideIcons.zapOff,
            size: 18,
            color: tone,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  automation.isActive ? 'Ativa' : 'Inativa',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: tone,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  automation.isActive
                      ? 'Enviando notificações'
                      : 'Não enviará notificações',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: neutral,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _openHistory,
            icon: Icon(LucideIcons.history, size: 16, color: _accent(context)),
            label: Text(
              'Histórico',
              style: TextStyle(
                color: _accent(context),
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(width: 2),
          _toggling
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : SizedBox(
                  height: 26,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Switch.adaptive(
                      value: automation.isActive,
                      activeTrackColor: green,
                      onChanged: (_) => _toggle(),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  // ─── Estatísticas ───────────────────────────────────────────────────────

  Widget _buildStatsStrip(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final blue = isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final divider = ThemeHelpers.borderColor(context).withValues(alpha: 0.45);

    final blocks = <Widget>[
      _statBlock(
        context,
        LucideIcons.activity,
        'EXECUÇÕES',
        '${_stats.totalExecutions}',
        automationLastRunLabel(_stats.lastExecution),
        blue,
      ),
      _statBlock(
        context,
        LucideIcons.circleCheck,
        'SUCESSOS',
        '${_stats.successfulExecutions}',
        _stats.totalExecutions == 0
            ? 'sem execuções'
            : '${_stats.successRate.toStringAsFixed(0)}% de acerto',
        emerald,
      ),
      _statBlock(
        context,
        LucideIcons.circleX,
        'FALHAS',
        '${_stats.failedExecutions}',
        _stats.failedExecutions == 0 ? 'nenhuma falha' : 'para investigar',
        danger,
      ),
    ];

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < blocks.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: divider,
              ),
            Expanded(child: blocks[i]),
          ],
        ],
      ),
    );
  }

  Widget _statBlock(BuildContext context, IconData icon, String label,
      String value, String sub, Color tone) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: tone),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: tone,
                    letterSpacing: 1.2,
                    height: 1.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: tone,
                letterSpacing: -0.6,
                height: 1.0,
                fontSize: 22,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            sub,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: secondary,
              height: 1.0,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 7),
          Container(
            height: 2,
            width: 18,
            decoration: BoxDecoration(
              color: tone,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Barra de salvar ────────────────────────────────────────────────────

  Widget _buildSaveBar(BuildContext context) {
    final accent = _accent(context);
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
            child: FilledButton.icon(
              onPressed: _dirty && !_saving ? _save : null,
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
                _saving
                    ? 'Salvando…'
                    : _dirty
                        ? 'Salvar configurações'
                        : 'Tudo salvo',
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

  /// Skeleton fiel: cabeçalho + card de status + faixa de stats + campos.
  Widget _buildSkeleton(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(_kPagePadH, 12, _kPagePadH, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 48, height: 48, borderRadius: 14),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonText(width: 90, height: 10),
                    SizedBox(height: 8),
                    SkeletonText(width: 220, height: 20),
                    SizedBox(height: 7),
                    SkeletonText(width: double.infinity, height: 12),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SkeletonBox(width: double.infinity, height: 60, borderRadius: 14),
          const SizedBox(height: 18),
          Row(
            children: const [
              Expanded(child: SkeletonText(width: double.infinity, height: 48)),
              SizedBox(width: 12),
              Expanded(child: SkeletonText(width: double.infinity, height: 48)),
              SizedBox(width: 12),
              Expanded(child: SkeletonText(width: double.infinity, height: 48)),
            ],
          ),
          const SizedBox(height: 24),
          const SkeletonText(width: 140, height: 11),
          const SizedBox(height: 12),
          Row(
            children: const [
              Expanded(
                  child: SkeletonBox(
                      width: double.infinity, height: 46, borderRadius: 12)),
              SizedBox(width: 10),
              Expanded(
                  child: SkeletonBox(
                      width: double.infinity, height: 46, borderRadius: 12)),
            ],
          ),
          const SizedBox(height: 24),
          const SkeletonText(width: 120, height: 11),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(
              6,
              (_) => SkeletonBox(width: 96, height: 34, borderRadius: 999),
            ),
          ),
          const SizedBox(height: 24),
          const SkeletonText(width: 160, height: 11),
          const SizedBox(height: 12),
          SkeletonBox(width: double.infinity, height: 110, borderRadius: 12),
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
