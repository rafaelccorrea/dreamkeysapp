import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/subscription_models.dart';
import '../services/subscriptions_service.dart';
import '../widgets/subscription_widgets.dart';

final NumberFormat _money = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 2,
);

/// **Planos** (`/subscription/plans`) — vitrine com comparação, paridade com
/// o `SubscriptionPlansPage` do web (`/subscription-plans`, AdminRoute).
/// A contratação envolve pagamento → deep-link para o painel web.
class SubscriptionPlansPage extends StatefulWidget {
  const SubscriptionPlansPage({super.key});

  @override
  State<SubscriptionPlansPage> createState() => _SubscriptionPlansPageState();
}

class _SubscriptionPlansPageState extends State<SubscriptionPlansPage> {
  static const double _kPadH = 16;
  static const String _webPanelBase = 'https://intellisysbr.com/sistema';

  bool _loading = true;
  String? _error;
  List<PricingPlan> _plans = const [];
  String _currentPlanKey = '';
  final Set<String> _expandedModules = {};

  bool get _isAdmin {
    final role = ModuleAccessService.instance.userRole?.toLowerCase().trim();
    return role == 'admin' || role == 'master';
  }

  @override
  void initState() {
    super.initState();
    if (_isAdmin) _load();
  }

  Color _accent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.primary.primaryDarkMode
          : AppColors.primary.primary;

  /// Tom por plano — cor com significado: básico = azul (entrada),
  /// profissional = cor da marca (principal/popular), custom = violeta
  /// (sob medida).
  Color _planTone(BuildContext context, PricingPlan plan) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (plan.key) {
      case 'basic':
        return isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
      case 'custom':
        return isDark
            ? AppColors.status.purpleDarkMode
            : AppColors.status.purple;
      default:
        return _accent(context);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final results = await Future.wait([
      SubscriptionsService.instance.getPlansShowcase(),
      SubscriptionsService.instance.getMyUsage(),
    ]);
    if (!mounted) return;

    final plansRes = results[0];
    final usageRes = results[1];

    setState(() {
      _loading = false;
      if (plansRes.success && plansRes.data != null) {
        _plans = (plansRes.data as List<PricingPlan>?) ?? const [];
        _error = null;
      } else {
        _error = plansRes.message ?? 'Erro ao carregar planos';
      }
      // Plano atual (silencioso — 404 significa "sem assinatura").
      final usage =
          usageRes.success ? usageRes.data as SubscriptionUsage? : null;
      _currentPlanKey = _normalizePlanKey(usage?.planType ?? '');
    });
  }

  static String _normalizePlanKey(String type) {
    final t = type.toLowerCase().trim();
    if (t == 'pro') return 'professional';
    return t;
  }

  Future<void> _openCheckout(PricingPlan plan) async {
    final path =
        plan.key == 'custom' ? '/custom-plan' : '/subscription-plans';
    final uri = Uri.parse('$_webPanelBase$path');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o painel web.')),
      );
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return const AppScaffold(
        title: 'Planos',
        showBottomNavigation: false,
        body: SubsDeniedView(
          message: 'A contratação de planos é restrita a administradores.',
        ),
      );
    }

    Widget body;
    if (_loading) {
      body = _buildSkeleton();
    } else if (_error != null) {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(_kPadH, 40, _kPadH, 0),
        child: SubsErrorState(message: _error!, onRetry: _load),
      );
    } else if (_plans.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(_kPadH, 40, _kPadH, 0),
        child: SubsEmptyState(
          icon: LucideIcons.packageOpen,
          title: 'Nenhum plano disponível',
          body: 'A vitrine de planos está vazia no momento.',
          tone: _accent(context),
        ),
      );
    } else {
      body = _buildContent(context);
    }

    return AppScaffold(
      title: 'Planos',
      showBottomNavigation: false,
      body: RefreshIndicator(
        color: _accent(context),
        onRefresh: _load,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: body,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_kPadH, 10, _kPadH, 88),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHero(context),
          const SizedBox(height: 18),
          for (var i = 0; i < _plans.length; i++) ...[
            _buildPlanCard(context, _plans[i])
                .animate(key: ValueKey('plan-${_plans[i].key}'))
                .fadeIn(
                  delay: Duration(milliseconds: 60 * i),
                  duration: 260.ms,
                ),
            const SizedBox(height: 14),
          ],
          const SizedBox(height: 10),
          _buildComparison(context),
        ],
      ),
    );
  }

  // ─── Hero flush ───────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accent(context);
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
                color: accent,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.55),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Text(
              'PLANOS & PREÇOS',
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.2,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Escolha o plano ideal',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: ThemeHelpers.textColor(context),
            height: 1.0,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _currentPlanKey.isEmpty
              ? 'Compare recursos e limites — a contratação é concluída '
                  'no painel web.'
              : 'Seu plano atual está marcado. Upgrades são concluídos '
                  'no painel web.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: secondary,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  // ─── Card de plano ────────────────────────────────────────────────────────

  Widget _buildPlanCard(BuildContext context, PricingPlan plan) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = _planTone(context, plan);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final isCurrent = _currentPlanKey.isNotEmpty && plan.key == _currentPlanKey;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final expanded = _expandedModules.contains(plan.key);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(18),
        boxShadow: ThemeHelpers.cardShadow(context),
        border: plan.popular && !isCurrent
            ? Border.all(color: tone.withValues(alpha: isDark ? 0.5 : 0.35))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  gradient: LinearGradient(
                    colors: [
                      tone.withValues(alpha: isDark ? 0.24 : 0.14),
                      tone.withValues(alpha: isDark ? 0.1 : 0.06),
                    ],
                  ),
                ),
                child: Icon(planTypeIcon(plan.key), color: tone, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            plan.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: ThemeHelpers.textColor(context),
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        if (plan.popular) ...[
                          const SizedBox(width: 8),
                          _miniBadge(context, 'MAIS POPULAR', amber),
                        ],
                        if (isCurrent) ...[
                          const SizedBox(width: 8),
                          _miniBadge(
                            context,
                            'PLANO ATUAL',
                            isDark
                                ? AppColors.status.greenDarkMode
                                : AppColors.status.green,
                          ),
                        ],
                      ],
                    ),
                    if (plan.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        plan.description.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (plan.isBasePrice)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4, right: 6),
                  child: Text(
                    'a partir de',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              Text(
                _money.format(plan.price),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: tone,
                  letterSpacing: -0.6,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 4),
                child: Text(
                  '/mês',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              if (plan.trialDays != null && plan.trialDays! > 0)
                _miniBadge(
                  context,
                  '${plan.trialDays} DIAS GRÁTIS',
                  isDark
                      ? AppColors.status.blueDarkMode
                      : AppColors.status.blue,
                ),
            ],
          ),
          const SizedBox(height: 14),
          _buildLimitsGrid(context, plan, tone),
          if (plan.features.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              height: 1,
              color: ThemeHelpers.borderLightColor(context),
            ),
            const SizedBox(height: 12),
            for (final feature in plan.features
                .where((f) => f.trim().isNotEmpty)
                .take(8))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3.5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1.5),
                      child: Icon(
                        LucideIcons.circleCheck,
                        size: 14,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AppColors.status.greenDarkMode
                            : AppColors.status.green,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        feature.trim(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ThemeHelpers.textColor(context),
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (plan.modules.isNotEmpty) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () => setState(() {
                if (!_expandedModules.remove(plan.key)) {
                  _expandedModules.add(plan.key);
                }
              }),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(LucideIcons.boxes, size: 14, color: tone),
                    const SizedBox(width: 7),
                    Text(
                      '${plan.modules.length} módulo'
                      '${plan.modules.length == 1 ? '' : 's'} '
                      '${plan.key == 'custom' ? 'inclusos na base' : 'inclusos'}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: tone,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        LucideIcons.chevronDown,
                        size: 16,
                        color: secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 220),
              crossFadeState: expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final m in plan.modules)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: tone.withValues(alpha: isDark ? 0.12 : 0.07),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: tone.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          m.name.isNotEmpty ? m.name : moduleLabel(m.code),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: ThemeHelpers.textColor(context),
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (isCurrent)
            OutlinedButton.icon(
              onPressed: null,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              icon: const Icon(LucideIcons.badgeCheck, size: 16),
              label: const Text(
                'Este é o seu plano',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          else
            FilledButton.icon(
              onPressed: () => _openCheckout(plan),
              style: FilledButton.styleFrom(
                backgroundColor: tone,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              icon: Icon(
                plan.key == 'custom'
                    ? LucideIcons.wrench
                    : LucideIcons.externalLink,
                size: 16,
              ),
              label: Text(
                plan.key == 'custom'
                    ? 'Montar plano no painel'
                    : 'Contratar no painel',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }

  Widget _miniBadge(BuildContext context, String label, Color tone) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: tone,
          fontWeight: FontWeight.w900,
          fontSize: 9,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  /// Limites em grade 2×2 alinhada (mesma régua dos filtros em grid).
  Widget _buildLimitsGrid(BuildContext context, PricingPlan plan, Color tone) {
    final items = <(IconData, String, String)>[
      (
        LucideIcons.building2,
        'Empresas',
        _limitLabel(plan.limits.companies),
      ),
      (LucideIcons.users, 'Usuários', _limitLabel(plan.limits.users)),
      (LucideIcons.house, 'Imóveis', _limitLabel(plan.limits.properties)),
      (
        LucideIcons.hardDrive,
        'Armazenamento',
        _limitLabel(plan.limits.storage, unit: 'GB'),
      ),
    ];
    return Column(
      children: [
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) const SizedBox(height: 8),
          Row(
            children: [
              for (var col = 0; col < 2; col++) ...[
                if (col > 0) const SizedBox(width: 8),
                Expanded(
                  child: _limitChip(
                    context,
                    items[row * 2 + col].$1,
                    items[row * 2 + col].$2,
                    items[row * 2 + col].$3,
                    tone,
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  static String _limitLabel(int v, {String? unit}) {
    if (v < 0) return 'Ilimitado';
    if (v == 0) return '—';
    return unit == null ? '$v' : '$v $unit';
  }

  Widget _limitChip(BuildContext context, IconData icon, String label,
      String value, Color tone) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: ThemeHelpers.borderLightColor(context)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: tone),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Comparativo de limites ───────────────────────────────────────────────

  Widget _buildComparison(BuildContext context) {
    if (_plans.length < 2) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    final rows = <(String, String Function(PricingPlan))>[
      ('Empresas', (p) => _limitLabel(p.limits.companies)),
      ('Usuários', (p) => _limitLabel(p.limits.users)),
      ('Imóveis', (p) => _limitLabel(p.limits.properties)),
      ('Armazenamento', (p) => _limitLabel(p.limits.storage, unit: 'GB')),
      ('Módulos', (p) => '${p.modules.length}'),
      (
        'Mensalidade',
        (p) => '${p.isBasePrice ? 'a partir de ' : ''}${_money.format(p.price)}'
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SubsPanelHeader(
          icon: LucideIcons.listFilter,
          eyebrow: 'COMPARATIVO',
          title: 'Planos lado a lado',
          hint: 'Limites e preço de cada plano em uma única régua.',
          tone: _accent(context),
        ),
        const SizedBox(height: 14),
        // Cabeçalho das colunas.
        Row(
          children: [
            const Expanded(flex: 5, child: SizedBox.shrink()),
            for (final plan in _plans)
              Expanded(
                flex: 4,
                child: Column(
                  children: [
                    Icon(
                      planTypeIcon(plan.key),
                      size: 15,
                      color: _planTone(context, plan),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      planTypeLabel(plan.key),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _planTone(context, plan),
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < rows.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: ThemeHelpers.borderLightColor(context)
                      .withValues(alpha: 0.7),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    rows[i].$1,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                for (final plan in _plans)
                  Expanded(
                    flex: 4,
                    child: Text(
                      rows[i].$2(plan),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: ThemeHelpers.textColor(context),
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        height: 1.25,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  // ─── Skeleton (fiel ao card real) ─────────────────────────────────────────

  Widget _buildSkeleton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_kPadH, 14, _kPadH, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonText(width: 130, height: 11, borderRadius: 999),
          const SizedBox(height: 12),
          const SkeletonText(width: 230, height: 28, borderRadius: 8),
          const SizedBox(height: 10),
          const SkeletonText(width: double.infinity, height: 13),
          const SizedBox(height: 20),
          for (var i = 0; i < 2; i++) ...[
            const SkeletonBox(
                height: 320, borderRadius: 18, width: double.infinity),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}
