import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/subscription_service.dart';
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
final DateFormat _date = DateFormat('dd/MM/yyyy', 'pt_BR');

enum _SubsTab { overview, usage, modules }

/// **Minha Assinatura** (`/subscription`) — paridade com o
/// `AdminSubscriptionPage` do web (rota `/my-subscription`, AdminRoute):
/// plano atual, status, próxima cobrança, limites/uso e módulos ativos.
/// Checkout/pagamento acontecem no painel web (deep-link).
class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  static const double _kPadH = 16;
  static const double _kGap = 12;
  static const String _plansRoute = '/subscription/plans';

  /// Painel web em produção (mesma base do deploy Hostinger `/sistema`).
  static const String _webPanelBase = 'https://intellisysbr.com/sistema';

  bool _loading = true;
  String? _error;
  bool _managedExempt = false;
  SubscriptionAccessInfo? _access;
  ActiveSubscription? _active;
  SubscriptionUsage? _usage;

  _SubsTab _tab = _SubsTab.overview;

  /// Gate por papel — a rota é AdminRoute no web (admin | master).
  bool get _isAdmin {
    final role = ModuleAccessService.instance.userRole?.toLowerCase().trim();
    return role == 'admin' || role == 'master';
  }

  bool get _hasSubscription =>
      _active != null || (_usage?.isMeaningful ?? false);

  @override
  void initState() {
    super.initState();
    if (_isAdmin) _load();
  }

  // ─── Cores ────────────────────────────────────────────────────────────────

  Color _accent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.primary.primaryDarkMode
          : AppColors.primary.primary;

  Color _tabTone(BuildContext context, _SubsTab tab) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (tab) {
      case _SubsTab.overview:
        return _accent(context);
      case _SubsTab.usage:
        return isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
      case _SubsTab.modules:
        return isDark
            ? AppColors.status.purpleDarkMode
            : AppColors.status.purple;
    }
  }

  // ─── Dados ────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    // Conta gerenciada isenta não tem assinatura própria — detectamos antes
    // para não tratar os 404 seguintes como erro (paridade com o web).
    final accessRes =
        await SubscriptionService.instance.checkSubscriptionAccess();
    if (!mounted) return;
    final access = accessRes.success ? accessRes.data : null;
    if (access?.status == 'managed_exempt') {
      setState(() {
        _loading = false;
        _managedExempt = true;
        _access = access;
        _active = null;
        _usage = null;
      });
      return;
    }

    final results = await Future.wait([
      SubscriptionsService.instance.getMyActiveSubscription(),
      SubscriptionsService.instance.getMyUsage(),
    ]);
    if (!mounted) return;

    final activeRes = results[0];
    final usageRes = results[1];

    setState(() {
      _loading = false;
      _managedExempt = false;
      _access = access;
      _active = activeRes.success ? activeRes.data as ActiveSubscription? : null;
      _usage = usageRes.success ? usageRes.data as SubscriptionUsage? : null;

      final activeOk = activeRes.success || activeRes.statusCode == 404;
      final usageOk = usageRes.success || usageRes.statusCode == 404;
      // 404 em ambos = simplesmente sem assinatura (estado vazio, não erro).
      _error = (activeOk || usageOk)
          ? null
          : (usageRes.message ?? 'Erro ao carregar sua assinatura');
    });
  }

  Future<void> _openWebPanel(String path) async {
    final uri = Uri.parse('$_webPanelBase$path');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o painel web.')),
      );
    }
  }

  // ─── Derivados ────────────────────────────────────────────────────────────

  String get _planName {
    final fromUsage = _usage?.planName.trim() ?? '';
    if (fromUsage.isNotEmpty) return fromUsage;
    final fromActive = _active?.planName.trim() ?? '';
    return fromActive.isNotEmpty ? fromActive : 'Plano';
  }

  String get _planType =>
      (_usage?.planType.trim().isNotEmpty ?? false)
          ? _usage!.planType
          : (_active?.planType ?? '');

  String get _status {
    final s = _usage?.status.trim() ?? '';
    if (s.isNotEmpty) return s;
    return _active?.status ?? 'inactive';
  }

  double? get _price {
    if (_usage != null && _usage!.monthlyPrice > 0) return _usage!.monthlyPrice;
    if (_active != null && _active!.price > 0) return _active!.price;
    return null;
  }

  int? get _daysRemaining {
    if (_usage != null && _usage!.endDate != null) return _usage!.daysRemaining;
    return _active?.daysUntilExpiry;
  }

  DateTime? get _nextBilling =>
      _active?.nextBillingDate ?? _usage?.endDate ?? _active?.endDate;

  List<String> get _modules {
    final fromUsage = _usage?.activeModules ?? const [];
    if (fromUsage.isNotEmpty) return fromUsage;
    return _active?.modules ?? const [];
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return const AppScaffold(
        title: 'Minha Assinatura',
        showBottomNavigation: false,
        body: SubsDeniedView(
          message: 'A assinatura da conta é visível apenas para '
              'administradores.',
        ),
      );
    }

    Widget body;
    if (_loading) {
      body = _buildSkeleton(context);
    } else if (_error != null) {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(_kPadH, 40, _kPadH, 0),
        child: SubsErrorState(message: _error!, onRetry: _load),
      );
    } else if (_managedExempt) {
      body = _buildManagedExempt(context);
    } else if (!_hasSubscription) {
      body = _buildNoSubscription(context);
    } else {
      body = _buildContent(context);
    }

    return AppScaffold(
      title: 'Minha Assinatura',
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

  // ─── Conteúdo principal ───────────────────────────────────────────────────

  Widget _buildContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(_kPadH, 10, _kPadH, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHero(context),
              const SizedBox(height: _kGap),
              if ((_usage?.alerts ?? const []).isNotEmpty) ...[
                _buildAlerts(context),
                const SizedBox(height: _kGap),
              ],
            ],
          ),
        ),
        _buildTabsRail(context),
        Padding(
          padding: const EdgeInsets.fromLTRB(_kPadH, _kGap, _kPadH, 88),
          child: _buildActivePanel(context),
        ),
      ],
    );
  }

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final statusTone = subscriptionStatusColor(context, _status);

    final next = _nextBilling;
    final days = _daysRemaining;
    String subtitle;
    if (_usage?.isTrialActive == true && _usage?.trialEndsAt != null) {
      subtitle = 'Período de teste até '
          '${_date.format(_usage!.trialEndsAt!.toLocal())}.';
    } else if (next != null) {
      subtitle = 'Próxima cobrança em ${_date.format(next.toLocal())}'
          '${days != null && days > 0 ? ' · $days dia${days == 1 ? '' : 's'} restante${days == 1 ? '' : 's'}' : ''}.';
    } else {
      subtitle = 'Assinatura sem data de término definida.';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusTone,
                  boxShadow: [
                    BoxShadow(
                      color: statusTone.withValues(alpha: 0.55),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              Text(
                'MINHA ASSINATURA',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _accent(context),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.2,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  _planName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: textColor,
                    height: 1.0,
                    letterSpacing: -0.8,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: SubsStatusPill(status: _status, compact: true),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: secondary,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          _buildKpiStrip(context),
        ],
      ),
    );
  }

  Widget _buildKpiStrip(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final divider = ThemeHelpers.borderColor(context).withValues(alpha: 0.45);
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final blue = isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final purple =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;

    final price = _price;
    final days = _daysRemaining;

    final blocks = <Widget>[
      _kpiBlock(
        context,
        LucideIcons.banknote,
        'MENSALIDADE',
        price == null ? '—' : _money.format(price),
        _planType.isEmpty ? 'plano atual' : planTypeLabel(_planType),
        emerald,
      ),
      _kpiBlock(
        context,
        LucideIcons.calendarClock,
        'RENOVAÇÃO',
        days == null ? '—' : '$days d',
        _nextBilling == null
            ? 'sem término'
            : _date.format(_nextBilling!.toLocal()),
        blue,
      ),
      _kpiBlock(
        context,
        LucideIcons.boxes,
        'MÓDULOS',
        '${_modules.length}',
        'ativos no plano',
        purple,
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

  Widget _kpiBlock(BuildContext context, IconData icon, String label,
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: tone,
                    letterSpacing: 1.2,
                    height: 1.0,
                  ),
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: secondary,
              height: 1.0,
            ),
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

  Widget _buildAlerts(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: amber.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final alert in _usage!.alerts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.triangleAlert, size: 14, color: amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      alert,
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
      ),
    );
  }

  // ─── Abas flush ───────────────────────────────────────────────────────────

  Widget _buildTabsRail(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: _kPadH - 8),
      child: Row(
        children: [
          for (final tab in _SubsTab.values)
            Expanded(
              child: SubsFlushTab(
                icon: switch (tab) {
                  _SubsTab.overview => LucideIcons.creditCard,
                  _SubsTab.usage => LucideIcons.gauge,
                  _SubsTab.modules => LucideIcons.boxes,
                },
                label: switch (tab) {
                  _SubsTab.overview => 'Visão geral',
                  _SubsTab.usage => 'Uso & limites',
                  _SubsTab.modules => 'Módulos',
                },
                tone: _tabTone(context, tab),
                selected: _tab == tab,
                onTap: () => setState(() => _tab = tab),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActivePanel(BuildContext context) {
    final tone = _tabTone(context, _tab);
    final (icon, eyebrow, title, hint) = switch (_tab) {
      _SubsTab.overview => (
          LucideIcons.creditCard,
          'PLANO ATUAL',
          'Detalhes da assinatura',
          'Plano contratado, vigência e cobrança da sua conta.',
        ),
      _SubsTab.usage => (
          LucideIcons.gauge,
          'CONSUMO',
          'Uso e limites do plano',
          'Quanto do plano sua operação já consumiu.',
        ),
      _SubsTab.modules => (
          LucideIcons.boxes,
          'RECURSOS',
          'Módulos ativos',
          'Funcionalidades liberadas para sua imobiliária.',
        ),
    };

    final child = switch (_tab) {
      _SubsTab.overview => _buildOverviewPanel(context),
      _SubsTab.usage => _buildUsagePanel(context),
      _SubsTab.modules => _buildModulesPanel(context),
    };

    return Column(
      key: ValueKey('panel-${_tab.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SubsPanelHeader(
          icon: icon,
          eyebrow: eyebrow,
          title: title,
          hint: hint,
          tone: tone,
        ),
        const SizedBox(height: 14),
        child,
      ],
    ).animate(key: ValueKey('panel-${_tab.name}')).fadeIn(duration: 240.ms);
  }

  // ─── Painel: visão geral ──────────────────────────────────────────────────

  Widget _buildOverviewPanel(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accent(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final price = _price;
    final a = _active;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Spotlight do plano — card sem borda lateral, sombra neutra.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: BorderRadius.circular(18),
            boxShadow: ThemeHelpers.cardShadow(context),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    colors: [
                      accent.withValues(alpha: isDark ? 0.24 : 0.14),
                      accent.withValues(alpha: isDark ? 0.1 : 0.06),
                    ],
                  ),
                ),
                child: Icon(planTypeIcon(_planType), color: accent, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _planName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      a?.planDescription.trim().isNotEmpty == true
                          ? a!.planDescription.trim()
                          : 'Plano ${planTypeLabel(_planType)} da sua conta.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    price == null ? '—' : _money.format(price),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: accent,
                      letterSpacing: -0.4,
                    ),
                  ),
                  Text(
                    '/mês',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SubsInfoRow(
          label: 'Status',
          valueWidget: Align(
            alignment: Alignment.centerRight,
            child: SubsStatusPill(status: _status, compact: true),
          ),
        ),
        SubsInfoRow(
          label: 'Tipo de plano',
          value: _planType.isEmpty ? '—' : planTypeLabel(_planType),
          icon: LucideIcons.tag,
        ),
        if (a?.startDate != null)
          SubsInfoRow(
            label: 'Início da vigência',
            value: _date.format(a!.startDate!.toLocal()),
            icon: LucideIcons.calendarPlus,
          ),
        if (_nextBilling != null)
          SubsInfoRow(
            label: a?.nextBillingDate != null
                ? 'Próxima cobrança'
                : 'Término da vigência',
            value: _date.format(_nextBilling!.toLocal()),
            icon: LucideIcons.calendarClock,
            emphasize: true,
          ),
        if (_usage?.isTrialActive == true && _usage?.trialEndsAt != null)
          SubsInfoRow(
            label: 'Teste grátis até',
            value: _date.format(_usage!.trialEndsAt!.toLocal()),
            icon: LucideIcons.rocket,
          ),
        if (a != null && a.maxCompanies != null)
          SubsInfoRow(
            label: 'Empresas',
            value: '${a.currentCompanies} de '
                '${a.maxCompanies! < 0 ? 'ilimitadas' : a.maxCompanies}',
            icon: LucideIcons.building2,
          ),
        if ((a?.notes ?? '').trim().isNotEmpty)
          SubsInfoRow(
            label: 'Observações',
            value: a!.notes!.trim(),
            icon: LucideIcons.notebookPen,
          ),
        const SubsDivider(),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushNamed(_plansRoute),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  side: BorderSide(color: accent.withValues(alpha: 0.45)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                icon: const Icon(LucideIcons.layers, size: 16),
                label: const Text(
                  'Ver planos',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _openWebPanel('/my-subscription'),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                icon: const Icon(LucideIcons.externalLink, size: 16),
                label: const Text(
                  'Gerenciar no painel',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Pagamento, troca de cartão e upgrade/downgrade são concluídos '
          'no painel web.',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: secondary.withValues(alpha: 0.85),
            height: 1.3,
          ),
        ),
      ],
    );
  }

  // ─── Painel: uso & limites ────────────────────────────────────────────────

  Widget _buildUsagePanel(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final u = _usage;
    if (u == null) {
      return SubsEmptyState(
        icon: LucideIcons.gauge,
        title: 'Uso indisponível',
        body: 'Não foi possível obter as métricas de uso desta assinatura.',
        tone: _tabTone(context, _SubsTab.usage),
      );
    }

    final meters = <Widget>[
      if (u.companies != null)
        UsageMeterTile(
          icon: LucideIcons.building2,
          label: 'Empresas',
          metric: u.companies!,
        ),
      if (u.users != null)
        UsageMeterTile(
          icon: LucideIcons.users,
          label: 'Usuários',
          metric: u.users!,
        ),
      if (u.properties != null)
        UsageMeterTile(
          icon: LucideIcons.house,
          label: 'Imóveis',
          metric: u.properties!,
        ),
      if (u.storage != null)
        UsageMeterTile(
          icon: LucideIcons.hardDrive,
          label: 'Armazenamento',
          metric: u.storage!,
          unit: 'GB',
        ),
      if (u.apiCalls != null)
        UsageMeterTile(
          icon: LucideIcons.zap,
          label: 'Chamadas de API no mês',
          metric: u.apiCalls!,
        ),
      if (u.aiTokens != null)
        UsageMeterTile(
          icon: LucideIcons.brainCircuit,
          label: 'Tokens de IA',
          metric: u.aiTokens!,
        ),
    ];

    if (meters.isEmpty) {
      return SubsEmptyState(
        icon: LucideIcons.gauge,
        title: 'Sem métricas',
        body: 'Este plano não expõe limites mensuráveis.',
        tone: _tabTone(context, _SubsTab.usage),
      );
    }

    final seats = u.seats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...meters,
        if (seats != null && seats.additionalUsers > 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ThemeHelpers.cardBackgroundColor(context),
              borderRadius: BorderRadius.circular(16),
              boxShadow: ThemeHelpers.cardShadow(context),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      LucideIcons.userRound,
                      size: 15,
                      color: isDark
                          ? AppColors.status.blueDarkMode
                          : AppColors.status.blue,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'USUÁRIOS ADICIONAIS',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isDark
                            ? AppColors.status.blueDarkMode
                            : AppColors.status.blue,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SubsInfoRow(
                  label: 'Inclusos no plano',
                  value: '${seats.includedUsers}',
                ),
                SubsInfoRow(
                  label: 'Em uso',
                  value: '${seats.currentUsers}',
                ),
                SubsInfoRow(
                  label: 'Adicionais '
                      '(${_money.format(seats.pricePerAdditionalUser)}/mês cada)',
                  value: '${seats.additionalUsers}',
                ),
                SubsInfoRow(
                  label: 'Custo adicional mensal',
                  value: _money.format(seats.additionalCost),
                  emphasize: true,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ─── Painel: módulos ──────────────────────────────────────────────────────

  Widget _buildModulesPanel(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = _tabTone(context, _SubsTab.modules);
    final modules = _modules;

    if (modules.isEmpty) {
      return SubsEmptyState(
        icon: LucideIcons.packageOpen,
        title: 'Nenhum módulo listado',
        body: _active?.isCustomPlan == true
            ? 'Plano personalizado — os módulos são configurados caso a caso.'
            : 'A assinatura não retornou a lista de módulos ativos.',
        tone: tone,
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final code in modules)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: tone.withValues(alpha: isDark ? 0.14 : 0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: tone.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.check, size: 13, color: tone),
                const SizedBox(width: 6),
                Text(
                  moduleLabel(code),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ─── Estados especiais ────────────────────────────────────────────────────

  Widget _buildManagedExempt(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final purple =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    return Padding(
      padding: const EdgeInsets.fromLTRB(_kPadH, 48, _kPadH, 0),
      child: SubsEmptyState(
        icon: LucideIcons.shieldCheck,
        title: 'Conta gerenciada',
        body: 'Sua empresa tem acesso concedido diretamente pela Intellisys — '
            'não há assinatura para gerenciar por aqui.',
        tone: purple,
      ),
    );
  }

  Widget _buildNoSubscription(BuildContext context) {
    final accent = _accent(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(_kPadH, 48, _kPadH, 0),
      child: SubsEmptyState(
        icon: LucideIcons.creditCard,
        title: 'Nenhuma assinatura ativa',
        body: _access?.reason ??
            'Sua conta ainda não possui um plano contratado. Conheça os '
                'planos disponíveis para liberar o acesso completo.',
        tone: accent,
        action: FilledButton.icon(
          onPressed: () => Navigator.of(context).pushNamed(_plansRoute),
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            elevation: 0,
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
          icon: const Icon(LucideIcons.layers, size: 16),
          label: const Text(
            'Conhecer os planos',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }

  // ─── Skeleton (fiel ao layout real) ───────────────────────────────────────

  Widget _buildSkeleton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_kPadH, 14, _kPadH, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonText(width: 140, height: 11, borderRadius: 999),
          const SizedBox(height: 12),
          const SkeletonText(width: 210, height: 30, borderRadius: 8),
          const SizedBox(height: 10),
          const SkeletonText(width: double.infinity, height: 13),
          const SizedBox(height: 20),
          Row(
            children: const [
              Expanded(child: SkeletonBox(height: 62, borderRadius: 10)),
              SizedBox(width: 10),
              Expanded(child: SkeletonBox(height: 62, borderRadius: 10)),
              SizedBox(width: 10),
              Expanded(child: SkeletonBox(height: 62, borderRadius: 10)),
            ],
          ),
          const SizedBox(height: 22),
          const SkeletonBox(height: 44, borderRadius: 12),
          const SizedBox(height: 16),
          const SkeletonBox(height: 92, borderRadius: 18),
          const SizedBox(height: 14),
          for (var i = 0; i < 4; i++) ...[
            const SkeletonText(width: double.infinity, height: 14),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}
