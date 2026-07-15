import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/minimal_body_chrome.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/sdr_dashboard_filters.dart';
import '../models/sdr_metrics_model.dart';
import '../services/sdr_service.dart';
import '../widgets/sdr_dashboard_filters_drawer.dart';

final NumberFormat _int = NumberFormat.decimalPattern('pt_BR');
final NumberFormat _compactMoney = NumberFormat.compactCurrency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 1,
);

/// Rota das configurações (fiação central em `AppRoutes.sdrSettings`).
const String _kSdrSettingsRoute = '/sdr/settings';

/// Abas do dashboard SDR.
enum _SdrTab { overview, team, sources }

/// Dashboard do **SDR com IA** — KPIs do pré-atendimento (paridade com a
/// `SDRDashboardPage.tsx`, recortada para mobile): hero editorial com os
/// números do período, abas flush com sublinhado (Visão geral / Equipe /
/// Origens), listas com barras de conversão e SLA de WhatsApp.
///
/// Gating: módulo `whatsapp_ai` + permissão `whatsapp:manage_config`.
class SdrDashboardPage extends StatefulWidget {
  const SdrDashboardPage({super.key});

  @override
  State<SdrDashboardPage> createState() => _SdrDashboardPageState();
}

class _SdrDashboardPageState extends State<SdrDashboardPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const double _kSectionGap = 12;

  bool _isLoading = true;
  String? _errorMessage;
  SdrMetrics _metrics = SdrMetrics.empty;
  SdrDashboardFilters _filters = SdrDashboardFilters.initial;
  List<SdrTeamOption> _teams = const [];
  _SdrTab _activeTab = _SdrTab.overview;

  bool get _hasAccess =>
      ModuleAccessService.instance.hasCompanyModule('whatsapp_ai') &&
      ModuleAccessService.instance.hasPermission('whatsapp:manage_config');

  @override
  void initState() {
    super.initState();
    _loadMetrics();
    unawaited(_loadTeams());
  }

  // ─── Cores semânticas ──────────────────────────────────────────────────────

  Color _accent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.primary.primaryDarkMode
          : AppColors.primary.primary;

  Color _green(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.status.greenDarkMode
          : AppColors.status.green;

  Color _amber(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;

  Color _red(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.status.errorDarkMode
          : AppColors.status.error;

  Color _blue(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.status.blueDarkMode
          : AppColors.status.blue;

  Color _purple(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.status.purpleDarkMode
          : AppColors.status.purple;

  // ─── Dados ─────────────────────────────────────────────────────────────────

  Future<void> _loadMetrics() async {
    if (!_hasAccess) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final res = await SdrService.instance.getMetrics(filters: _filters);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (res.success && res.data != null) {
        _metrics = res.data!;
        _errorMessage = null;
      } else {
        _errorMessage = res.message ?? 'Erro ao carregar métricas do SDR';
      }
    });
  }

  Future<void> _loadTeams() async {
    if (!_hasAccess) return;
    final res = await SdrService.instance.getTeams();
    if (!mounted || !res.success || res.data == null) return;
    setState(() => _teams = res.data!);
  }

  void _openFilters() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black54,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SdrDashboardFiltersDrawer(
        initialFilters: _filters,
        teams: _teams,
        onApply: (f) {
          setState(() => _filters = f);
          _loadMetrics();
        },
        onClear: () {
          setState(() => _filters = SdrDashboardFilters.initial);
          _loadMetrics();
        },
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).pushNamed(_kSdrSettingsRoute);
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_hasAccess) {
      return const AppScaffold(
        title: 'SDR com IA',
        showBottomNavigation: false,
        body: _DeniedView(),
      );
    }

    return AppScaffold(
      title: 'SDR com IA',
      showBottomNavigation: false,
      actions: [
        ChromeToolbarIconButton(
          icon: Icons.settings_outlined,
          tooltip: 'Configurações do SDR',
          onPressed: _openSettings,
        ),
        ChromeToolbarIconButton(
          icon: Icons.tune_rounded,
          tooltip: 'Filtros',
          onPressed: _openFilters,
        ),
      ],
      body: _isLoading
          ? _buildSkeleton(context)
          : _errorMessage != null
              ? _buildError(context)
              : RefreshIndicator(
                  color: _accent(context),
                  onRefresh: _loadMetrics,
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(minHeight: constraints.maxHeight),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  _kPagePadH, _kPagePadTop, _kPagePadH, 0),
                              child: _buildHero(context),
                            ),
                            const SizedBox(height: _kSectionGap),
                            _buildTabsRail(context),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  _kPagePadH,
                                  _kSectionGap,
                                  _kPagePadH,
                                  _kPagePadBottom),
                              child: _buildActivePanel(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }

  // ─── Hero editorial ────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accent(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final green = _green(context);
    final amber = _amber(context);
    final red = _red(context);

    final s = _metrics.summary;
    final awaiting = _metrics.whatsapp?.awaitingReplyCount ?? 0;
    final dot = awaiting > 0 ? amber : green;

    final convLabel =
        '${s.conversionRate.toStringAsFixed(1).replaceAll('.', ',')}%';
    final subtitle = s.totalLeads == 0
        ? 'Nenhum lead no período selecionado.'
        : awaiting > 0
            ? '$convLabel de conversão · $awaiting conversa${awaiting == 1 ? '' : 's'} aguardando resposta'
            : '$convLabel de conversão · nenhuma conversa aguardando resposta';

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
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
                  color: dot,
                  boxShadow: [
                    BoxShadow(
                      color: dot.withValues(alpha: 0.55),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'SDR COM IA · PRÉ-ATENDIMENTO',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.2,
                    fontSize: 11,
                  ),
                ),
              ),
              _periodChip(context),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _int.format(s.totalLeads),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: textColor,
                  height: 1.0,
                  letterSpacing: -1.0,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    s.totalLeads == 1
                        ? 'lead no período'
                        : 'leads no período',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
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
          _buildKpiStrip(context, green, amber, red),
        ],
      ),
    );
  }

  Widget _periodChip(BuildContext context) {
    final accent = _accent(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final active = _filters.activeCount > 0;
    return InkWell(
      onTap: _openFilters,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: isDark ? 0.16 : 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: accent.withValues(alpha: active ? 0.55 : 0.28),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.calendarRange, size: 12, color: accent),
            const SizedBox(width: 5),
            Text(
              _filters.periodLabel(),
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiStrip(
      BuildContext context, Color green, Color amber, Color red) {
    final s = _metrics.summary;
    final divider = ThemeHelpers.borderColor(context).withValues(alpha: 0.45);
    final blocks = <Widget>[
      _heroKpiBlock(
        context,
        LucideIcons.arrowRightLeft,
        'TRANSFERIDOS',
        _int.format(s.transferred),
        'para corretores',
        green,
      ),
      _heroKpiBlock(
        context,
        LucideIcons.hourglass,
        'QUALIFICANDO',
        _int.format(s.inQualification),
        'em andamento',
        amber,
      ),
      _heroKpiBlock(
        context,
        LucideIcons.circleX,
        'PERDIDOS',
        _int.format(s.lost),
        'no período',
        red,
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

  Widget _heroKpiBlock(BuildContext context, IconData icon, String label,
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

  // ─── Abas flush (sublinhado) ───────────────────────────────────────────────

  Widget _buildTabsRail(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: _kPagePadH - 8),
      child: Row(
        children: [
          Expanded(
            child: _FlushTab(
              icon: LucideIcons.activity,
              label: 'Visão geral',
              tone: _accent(context),
              selected: _activeTab == _SdrTab.overview,
              onTap: () => setState(() => _activeTab = _SdrTab.overview),
            ),
          ),
          Expanded(
            child: _FlushTab(
              icon: LucideIcons.users,
              label: 'Equipe',
              count: _metrics.byAgent.length,
              tone: _green(context),
              selected: _activeTab == _SdrTab.team,
              onTap: () => setState(() => _activeTab = _SdrTab.team),
            ),
          ),
          Expanded(
            child: _FlushTab(
              icon: LucideIcons.megaphone,
              label: 'Origens',
              count: _metrics.bySource.length,
              tone: _purple(context),
              selected: _activeTab == _SdrTab.sources,
              onTap: () => setState(() => _activeTab = _SdrTab.sources),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivePanel(BuildContext context) {
    final child = switch (_activeTab) {
      _SdrTab.overview => _buildOverviewPanel(context),
      _SdrTab.team => _buildTeamPanel(context),
      _SdrTab.sources => _buildSourcesPanel(context),
    };
    return child
        .animate(key: ValueKey('sdr-panel-${_activeTab.name}'))
        .fadeIn(duration: 240.ms);
  }

  Widget _panelHeader(
    BuildContext context, {
    required IconData icon,
    required String eyebrow,
    required String title,
    required String hint,
    required Color tone,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: tone.withValues(alpha: isDark ? 0.2 : 0.12),
          ),
          child: Icon(icon, color: tone, size: 20),
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
                    eyebrow,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  height: 1.32,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _subsectionHeader(
      BuildContext context, String label, IconData icon, int count) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Row(
      children: [
        Icon(icon, size: 14, color: secondary),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: secondary,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
        ),
        if (count > 0) ...[
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
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Container(
              height: 1,
              color:
                  ThemeHelpers.borderLightColor(context).withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Painel: Visão geral ───────────────────────────────────────────────────

  Widget _buildOverviewPanel(BuildContext context) {
    final s = _metrics.summary;
    final nodes = <Widget>[
      _panelHeader(
        context,
        icon: LucideIcons.activity,
        eyebrow: 'VISÃO GERAL',
        title: 'Como está o pré-atendimento',
        hint: 'Funil do período, atendimento no WhatsApp e entrada de leads.',
        tone: _accent(context),
      ),
      const SizedBox(height: 16),
    ];

    if (s.totalLeads == 0) {
      nodes.add(_emptyState(
        context,
        icon: LucideIcons.inbox,
        tone: _accent(context),
        title: 'Sem leads no período',
        body: 'Ajuste o período ou os filtros para ver as métricas do SDR.',
      ));
      return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: nodes);
    }

    // Funil resumido — barras proporcionais com cor por significado.
    nodes.add(_subsectionHeader(
        context, 'Funil do período', LucideIcons.filter, 0));
    nodes.add(const SizedBox(height: 12));
    final funnelTotal = max(1, s.totalLeads);
    nodes.add(_funnelRow(context, 'Transferidos', s.transferred, funnelTotal,
        _green(context)));
    nodes.add(_funnelRow(context, 'Em qualificação', s.inQualification,
        funnelTotal, _amber(context)));
    nodes.add(
        _funnelRow(context, 'Perdidos', s.lost, funnelTotal, _red(context)));
    if (s.duplicateLeads > 0) {
      nodes.add(_funnelRow(context, 'Duplicados', s.duplicateLeads,
          max(1, s.totalEntries), ThemeHelpers.textSecondaryColor(context)));
    }

    // WhatsApp (atendimento).
    final w = _metrics.whatsapp;
    if (w != null) {
      nodes.add(const SizedBox(height: 18));
      nodes.add(_subsectionHeader(
          context, 'WhatsApp · atendimento', LucideIcons.messageCircle, 0));
      nodes.add(const SizedBox(height: 12));
      nodes.add(_whatsappBand(context, w));
    }

    // Entrada de leads por dia (mini gráfico de barras).
    final days = _metrics.leadsByDay.where((d) => d.date != null).toList();
    if (days.isNotEmpty) {
      nodes.add(const SizedBox(height: 18));
      nodes.add(_subsectionHeader(
          context, 'Entrada de leads por dia', LucideIcons.chartColumn, 0));
      nodes.add(const SizedBox(height: 12));
      nodes.add(_leadsByDayChart(context, days));
    }

    // Motivos de perda.
    final losses = [..._metrics.lossReasons]
      ..sort((a, b) => b.count.compareTo(a.count));
    if (losses.isNotEmpty) {
      final top = losses.take(6).toList();
      final maxCount = max(1, top.first.count);
      nodes.add(const SizedBox(height: 18));
      nodes.add(_subsectionHeader(context, 'Principais motivos de perda',
          LucideIcons.circleX, losses.length));
      nodes.add(const SizedBox(height: 12));
      for (final l in top) {
        nodes.add(_funnelRow(
            context, l.reason, l.count, maxCount, _red(context)));
      }
    }

    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: nodes);
  }

  Widget _funnelRow(BuildContext context, String label, int value, int total,
      Color tone) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final frac = (value / total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _int.format(value),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '· ${(frac * 100).toStringAsFixed(0)}%',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  Container(
                    color: ThemeHelpers.borderLightColor(context)
                        .withValues(alpha: 0.7),
                  ),
                  FractionallySizedBox(
                    widthFactor: frac == 0 ? 0.005 : frac,
                    child: Container(
                      decoration: BoxDecoration(
                        color: tone,
                        borderRadius: BorderRadius.circular(999),
                      ),
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

  /// Faixa de SLA do WhatsApp — três medidores em card único, sem borda
  /// lateral, sombra neutra. Âmbar quando há conversas esperando resposta.
  Widget _whatsappBand(BuildContext context, SdrWhatsappMetrics w) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final amber = _amber(context);
    final green = _green(context);
    final blue = _blue(context);
    final awaitingTone = w.awaitingReplyCount > 0 ? amber : green;

    Widget cell(IconData icon, String label, String value, String sub,
        Color tone) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 15, color: tone),
            const SizedBox(height: 7),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: -0.4,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 2,
              style: theme.textTheme.labelSmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
                fontWeight: FontWeight.w700,
                fontSize: 10,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context)
                    .withValues(alpha: 0.8),
                fontSize: 9.5,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: awaitingTone.withValues(alpha: isDark ? 0.28 : 0.2),
        ),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cell(
            LucideIcons.clock3,
            'Aguardando resposta',
            _int.format(w.awaitingReplyCount),
            w.awaitingReplyCount > 0 ? 'precisa de atenção' : 'tudo em dia',
            awaitingTone,
          ),
          const SizedBox(width: 10),
          cell(
            LucideIcons.timer,
            'Tempo médio 1ª resposta',
            _latencyLabel(w.avgFirstResponseMinutes),
            w.firstResponseSampleSize > 0
                ? '${_int.format(w.firstResponseSampleSize)} respostas'
                : 'sem amostras',
            blue,
          ),
          const SizedBox(width: 10),
          cell(
            LucideIcons.gauge,
            'Mediana 1ª resposta',
            _latencyLabel(w.medianFirstResponseMinutes),
            'no período',
            blue,
          ),
        ],
      ),
    );
  }

  /// Minutos → rótulo humano (min ou h), paridade com
  /// `fmtSdrWhatsappLatencyMinutes` do web.
  String _latencyLabel(double? minutes) {
    if (minutes == null) return '—';
    if (minutes < 60) {
      return '${minutes.toStringAsFixed(0)} min';
    }
    final hours = minutes / 60;
    return '${hours.toStringAsFixed(1).replaceAll('.', ',')} h';
  }

  /// Gráfico de barras simples (sem lib) — entrada de leads por dia.
  Widget _leadsByDayChart(BuildContext context, List<SdrDayPoint> days) {
    final theme = Theme.of(context);
    final accent = _accent(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final data = days.length > 31 ? days.sublist(days.length - 31) : days;
    final maxTotal = data.fold<int>(0, (m, d) => max(m, d.total));
    if (maxTotal == 0) return const SizedBox.shrink();
    final fmtDay = DateFormat('dd/MM', 'pt_BR');
    final first = data.first.date;
    final last = data.last.date;
    final peak = data.reduce((a, b) => b.total >= a.total ? b : a);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 72,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < data.length; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(
                    child: Tooltip(
                      message: data[i].date == null
                          ? '${data[i].total}'
                          : '${fmtDay.format(data[i].date!)} · ${data[i].total} lead${data[i].total == 1 ? '' : 's'}',
                      child: Container(
                        height: max(3, 72.0 * data[i].total / maxTotal),
                        decoration: BoxDecoration(
                          color: data[i] == peak
                              ? accent
                              : accent.withValues(alpha: 0.38),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3)),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                first != null ? fmtDay.format(first) : '',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: secondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Icon(LucideIcons.trendingUp, size: 11, color: accent),
              const SizedBox(width: 4),
              Text(
                'pico: ${_int.format(peak.total)}'
                '${peak.date != null ? ' em ${fmtDay.format(peak.date!)}' : ''}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: secondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                last != null ? fmtDay.format(last) : '',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: secondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Painel: Equipe ────────────────────────────────────────────────────────

  Widget _buildTeamPanel(BuildContext context) {
    final green = _green(context);
    final agents = [..._metrics.byAgent]
      ..sort((a, b) => b.transferred.compareTo(a.transferred));

    final nodes = <Widget>[
      _panelHeader(
        context,
        icon: LucideIcons.users,
        eyebrow: 'EQUIPE SDR',
        title: 'Desempenho por atendente',
        hint: 'Leads, transferências e conversão de cada pessoa no período.',
        tone: green,
      ),
      const SizedBox(height: 16),
    ];

    if (agents.isEmpty) {
      nodes.add(_emptyState(
        context,
        icon: LucideIcons.userX,
        tone: green,
        title: 'Sem atendentes no período',
        body: 'Nenhum lead foi atribuído a atendentes neste recorte.',
      ));
    } else {
      var animIndex = 0;
      for (var i = 0; i < agents.length; i++) {
        nodes.add(
          _AgentRow(rank: i + 1, agent: agents[i])
              .animate(key: ValueKey('agent-${agents[i].agentId}-$i'))
              .fadeIn(
                delay: Duration(milliseconds: 30 * (animIndex++).clamp(0, 12)),
                duration: 220.ms,
              ),
        );
      }
    }

    final brokers = [..._metrics.topBrokers]
      ..sort((a, b) => b.received.compareTo(a.received));
    if (brokers.isNotEmpty) {
      final maxReceived = max(1, brokers.first.received);
      nodes.add(const SizedBox(height: 18));
      nodes.add(_subsectionHeader(context, 'Corretores que mais receberam',
          LucideIcons.award, brokers.length));
      nodes.add(const SizedBox(height: 12));
      for (final b in brokers.take(8)) {
        nodes.add(_funnelRow(
            context, b.brokerName, b.received, maxReceived, _blue(context)));
      }
    }

    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: nodes);
  }

  // ─── Painel: Origens ───────────────────────────────────────────────────────

  Widget _buildSourcesPanel(BuildContext context) {
    final purple = _purple(context);
    final sources = [..._metrics.bySource]
      ..sort((a, b) => b.totalLeads.compareTo(a.totalLeads));

    final nodes = <Widget>[
      _panelHeader(
        context,
        icon: LucideIcons.megaphone,
        eyebrow: 'ORIGENS & CAMPANHAS',
        title: 'De onde vêm os leads',
        hint: 'Volume e conversão por mídia, campanha e qualificação.',
        tone: purple,
      ),
      const SizedBox(height: 16),
    ];

    if (sources.isEmpty) {
      nodes.add(_emptyState(
        context,
        icon: LucideIcons.searchX,
        tone: purple,
        title: 'Sem origens no período',
        body: 'Nenhum lead com origem registrada neste recorte.',
      ));
    } else {
      var animIndex = 0;
      for (final src in sources.take(10)) {
        nodes.add(
          _SourceRow(source: src)
              .animate(key: ValueKey('src-${src.source}'))
              .fadeIn(
                delay: Duration(milliseconds: 30 * (animIndex++).clamp(0, 12)),
                duration: 220.ms,
              ),
        );
      }
    }

    final campaigns = [..._metrics.byCampaign]
      ..sort((a, b) => b.totalLeads.compareTo(a.totalLeads));
    if (campaigns.isNotEmpty) {
      final maxLeads = max(1, campaigns.first.totalLeads);
      nodes.add(const SizedBox(height: 18));
      nodes.add(_subsectionHeader(
          context, 'Campanhas', LucideIcons.flag, campaigns.length));
      nodes.add(const SizedBox(height: 12));
      for (final c in campaigns.take(8)) {
        nodes.add(_funnelRow(
            context, c.campaign, c.totalLeads, maxLeads, purple));
      }
    }

    final quals = [..._metrics.byQualification]
      ..sort((a, b) => b.totalLeads.compareTo(a.totalLeads));
    if (quals.isNotEmpty) {
      final maxLeads = max(1, quals.first.totalLeads);
      nodes.add(const SizedBox(height: 18));
      nodes.add(_subsectionHeader(
          context, 'Por qualificação', LucideIcons.thermometer, quals.length));
      nodes.add(const SizedBox(height: 12));
      for (final q in quals) {
        nodes.add(_funnelRow(context, _qualificationLabel(q.qualification),
            q.totalLeads, maxLeads, _amber(context)));
      }
    }

    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: nodes);
  }

  String _qualificationLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'hot':
        return 'Quente';
      case 'warm':
        return 'Morno';
      case 'cold':
        return 'Frio';
      case 'unqualified':
        return 'Não qualificado';
      default:
        return raw;
    }
  }

  // ─── Estados ───────────────────────────────────────────────────────────────

  Widget _emptyState(
    BuildContext context, {
    required IconData icon,
    required Color tone,
    required String title,
    required String body,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 4),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [
                tone.withValues(alpha: 0.18),
                tone.withValues(alpha: 0.06),
              ]),
              border: Border.all(color: tone.withValues(alpha: 0.32)),
            ),
            child: Icon(icon, color: tone, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final theme = Theme.of(context);
    final danger = _red(context);
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
              _errorMessage ?? 'Erro ao carregar métricas do SDR',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loadMetrics,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  /// Skeleton fiel ao layout real: hero (eyebrow + número + KPIs), rail de
  /// abas e linhas com barras.
  Widget _buildSkeleton(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            _kPagePadH, _kPagePadTop + 4, _kPagePadH, _kPagePadBottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                SkeletonBox(width: 9, height: 9, borderRadius: 999),
                SizedBox(width: 9),
                SkeletonText(width: 180, height: 11, borderRadius: 4),
                Spacer(),
                SkeletonBox(width: 84, height: 26, borderRadius: 999),
              ],
            ),
            const SizedBox(height: 12),
            const SkeletonText(width: 120, height: 34, borderRadius: 8),
            const SizedBox(height: 8),
            const SkeletonText(width: 260, height: 13, borderRadius: 4),
            const SizedBox(height: 20),
            Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SkeletonText(width: 80, height: 9, borderRadius: 4),
                        SizedBox(height: 9),
                        SkeletonText(width: 52, height: 22, borderRadius: 6),
                        SizedBox(height: 7),
                        SkeletonText(width: 66, height: 10, borderRadius: 4),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  const Expanded(
                    child: SkeletonBox(height: 40, borderRadius: 10),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: const [
                SkeletonBox(width: 40, height: 40, borderRadius: 14),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonText(width: 90, height: 10, borderRadius: 4),
                      SizedBox(height: 6),
                      SkeletonText(width: 190, height: 14, borderRadius: 4),
                      SizedBox(height: 5),
                      SkeletonText(
                          width: double.infinity, height: 11, borderRadius: 4),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            for (var i = 0; i < 4; i++) ...[
              Row(
                children: const [
                  Expanded(
                    child:
                        SkeletonText(width: 140, height: 12, borderRadius: 4),
                  ),
                  SizedBox(width: 12),
                  SkeletonText(width: 40, height: 12, borderRadius: 4),
                ],
              ),
              const SizedBox(height: 7),
              const SkeletonBox(
                  width: double.infinity, height: 6, borderRadius: 999),
              const SizedBox(height: 14),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Aba flush (sublinhado, mesma gramática de Comissões) ────────────────────

class _FlushTab extends StatelessWidget {
  const _FlushTab({
    required this.icon,
    required this.label,
    required this.tone,
    required this.selected,
    required this.onTap,
    this.count = 0,
  });

  final IconData icon;
  final String label;
  final int count;
  final Color tone;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected ? tone : ThemeHelpers.textSecondaryColor(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: tone.withValues(alpha: 0.12),
        highlightColor: tone.withValues(alpha: 0.06),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: fg),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      maxLines: 1,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: fg,
                        fontWeight:
                            selected ? FontWeight.w900 : FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: tone.withValues(alpha: selected ? 0.18 : 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: selected
                                ? tone
                                : ThemeHelpers.textSecondaryColor(context),
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              height: 2.5,
              decoration: BoxDecoration(
                color: selected ? tone : Colors.transparent,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Linha de atendente ──────────────────────────────────────────────────────

class _AgentRow extends StatelessWidget {
  const _AgentRow({required this.rank, required this.agent});

  final int rank;
  final SdrAgentMetric agent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final red = isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final convFrac = (agent.conversionRate / 100).clamp(0.0, 1.0);
    final isTop = rank == 1 && agent.transferred > 0;
    final rankTone = isTop ? accent : secondary;

    Widget stat(String value, String label, Color tone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              color: tone,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: secondary,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: rankTone.withValues(alpha: isDark ? 0.18 : 0.1),
                  border: Border.all(
                    color: rankTone.withValues(alpha: isTop ? 0.5 : 0.25),
                  ),
                ),
                child: Center(
                  child: isTop
                      ? Icon(LucideIcons.crown, size: 14, color: rankTone)
                      : Text(
                          '$rank',
                          style: TextStyle(
                            color: rankTone,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      agent.agentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: ThemeHelpers.textColor(context),
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_int.format(agent.totalLeads)} lead${agent.totalLeads == 1 ? '' : 's'} no período',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: secondary,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              stat(_int.format(agent.transferred), 'transf.', green),
              const SizedBox(width: 12),
              stat(_int.format(agent.inQualification), 'qualif.', amber),
              const SizedBox(width: 12),
              stat(_int.format(agent.lost), 'perdidos', red),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 5,
                    child: Stack(
                      children: [
                        Container(
                          color: ThemeHelpers.borderLightColor(context)
                              .withValues(alpha: 0.7),
                        ),
                        FractionallySizedBox(
                          widthFactor: convFrac == 0 ? 0.005 : convFrac,
                          child: Container(
                            decoration: BoxDecoration(
                              color: green,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${agent.conversionRate.toStringAsFixed(1).replaceAll('.', ',')}%',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: green,
                  fontWeight: FontWeight.w900,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Linha de origem ─────────────────────────────────────────────────────────

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.source});

  final SdrSourceMetric source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final purple =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final convFrac = (source.conversionRate / 100).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  color: purple.withValues(alpha: isDark ? 0.18 : 0.1),
                ),
                child: Icon(LucideIcons.megaphone, size: 14, color: purple),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.source,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: ThemeHelpers.textColor(context),
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_int.format(source.totalLeads)} lead${source.totalLeads == 1 ? '' : 's'}'
                      ' · ${_int.format(source.transferred)} transferido${source.transferred == 1 ? '' : 's'}'
                      '${source.averageValue > 0 ? ' · ticket ${_compactMoney.format(source.averageValue)}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: secondary,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${source.conversionRate.toStringAsFixed(1).replaceAll('.', ',')}%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: green,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 5,
              child: Stack(
                children: [
                  Container(
                    color: ThemeHelpers.borderLightColor(context)
                        .withValues(alpha: 0.7),
                  ),
                  FractionallySizedBox(
                    widthFactor: convFrac == 0 ? 0.005 : convFrac,
                    child: Container(
                      decoration: BoxDecoration(
                        color: green,
                        borderRadius: BorderRadius.circular(999),
                      ),
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
}

// ─── Acesso negado ───────────────────────────────────────────────────────────

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
              'Você não tem acesso ao SDR com IA.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Solicite ao administrador o módulo de IA no WhatsApp e a permissão de gestão do atendimento.',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
