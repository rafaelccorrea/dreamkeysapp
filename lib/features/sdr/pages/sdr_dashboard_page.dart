import 'dart:async';
import 'dart:math' as math;

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
import '../models/sdr_settings_model.dart';
import '../services/sdr_service.dart';
import '../widgets/sdr_config_sheet.dart';
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

/// Dashboard do **SDR com IA** — painel de agente. O protagonista do topo é o
/// console de identidade do assistente (glyph de bot, nome, estado
/// ativo/pausado e horário de atendimento vindos das configurações reais),
/// seguido de um placar composto: número dominante de leads, mostrador de
/// conversão e barra de funil empilhada — nada de fileira de pills.
/// Violeta é o acento identitário (agente de IA); verde/âmbar/vermelho marcam
/// estados. Abas flush com sublinhado (Visão geral / Equipe / Origens).
///
/// Regras da tela:
/// - Título de seção NUNCA trunca com reticências — cabeçalhos quebram linha
///   e o contador flui como sufixo compacto.
/// - Listas longas (atendentes, corretores, origens, campanhas) renderizam em
///   lotes com "Carregar mais": o endpoint devolve os agregados completos de
///   uma vez (sem page/limit no backend), então a paginação é client-side.
/// - Appbar: Config abre o sheet de ajustes rápidos do agente
///   ([SdrConfigSheet]); Filtros abre o [SdrDashboardFiltersDrawer] com badge
///   de filtros ativos no botão.
///
/// Gating: módulo `whatsapp_ai` + permissão `whatsapp:manage_config`.
class SdrDashboardPage extends StatefulWidget {
  const SdrDashboardPage({super.key});

  @override
  State<SdrDashboardPage> createState() => _SdrDashboardPageState();
}

class _SdrDashboardPageState extends State<SdrDashboardPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 12;
  static const double _kPagePadBottom = 88;

  // Paginação client-side dos painéis. O endpoint `sdr/metrics` devolve os
  // agregados completos de uma vez (sem page/limit no backend) — renderizar
  // tudo trava a tela em empresas grandes. Cada lista cresce em lotes via
  // "Carregar mais" e volta ao lote inicial a cada recarga de métricas.
  static const int _kTeamPageSize = 12;
  static const int _kBrokersPageSize = 8;
  static const int _kSourcesPageSize = 10;
  static const int _kCampaignsPageSize = 8;
  int _teamVisible = _kTeamPageSize;
  int _brokersVisible = _kBrokersPageSize;
  int _sourcesVisible = _kSourcesPageSize;
  int _campaignsVisible = _kCampaignsPageSize;

  bool _isLoading = true;
  String? _errorMessage;
  SdrMetrics _metrics = SdrMetrics.empty;
  SdrDashboardFilters _filters = SdrDashboardFilters.initial;
  List<SdrTeamOption> _teams = const [];
  _SdrTab _activeTab = _SdrTab.overview;

  /// Configurações do assistente — alimentam o console de identidade
  /// (ativo/pausado + janela de atendimento). Falha aqui não bloqueia a tela.
  SdrSettings? _agentSettings;

  bool get _hasAccess =>
      ModuleAccessService.instance.hasCompanyModule('whatsapp_ai') &&
      ModuleAccessService.instance.hasPermission('whatsapp:manage_config');

  @override
  void initState() {
    super.initState();
    _loadMetrics();
    unawaited(_loadTeams());
    unawaited(_loadAgentStatus());
  }

  // ─── Cores semânticas ──────────────────────────────────────────────────────
  // Violeta = identidade do agente de IA; verde = sucesso/ativo; âmbar =
  // atenção; vermelho = perda; azul = informação/origens.

  Color _violet(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.status.purpleDarkMode
          : AppColors.status.purple;

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
        _teamVisible = _kTeamPageSize;
        _brokersVisible = _kBrokersPageSize;
        _sourcesVisible = _kSourcesPageSize;
        _campaignsVisible = _kCampaignsPageSize;
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

  Future<void> _loadAgentStatus() async {
    if (!_hasAccess) return;
    final res = await SdrService.instance.getSettings();
    if (!mounted || !res.success || res.data == null) return;
    setState(() => _agentSettings = res.data);
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadMetrics(), _loadAgentStatus()]);
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

  /// Sheet de configurações rápidas do agente (botão de Config da appbar).
  /// Salvar atualiza o console do agente na hora; "Todas as opções" leva à
  /// página completa de configurações.
  void _openConfigSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black54,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SdrConfigSheet(
        initial: _agentSettings,
        onSaved: (s) {
          if (!mounted) return;
          setState(() => _agentSettings = s);
        },
        onOpenFullSettings: _openSettings,
      ),
    );
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
          icon: LucideIcons.settings2,
          tooltip: 'Configurações do agente',
          onPressed: _openConfigSheet,
        ),
        _BadgedToolbarAction(
          count: _filters.activeCount,
          child: ChromeToolbarIconButton(
            icon: LucideIcons.slidersHorizontal,
            tooltip: 'Filtros',
            onPressed: _openFilters,
          ),
        ),
      ],
      body: _isLoading
          ? _buildSkeleton(context)
          : _errorMessage != null
              ? _buildError(context)
              : RefreshIndicator(
                  color: _violet(context),
                  onRefresh: _refreshAll,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                        0, _kPagePadTop, 0, _kPagePadBottom),
                    children: [
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: _kPagePadH),
                        child: _buildAgentConsole(context),
                      ),
                      const SizedBox(height: 18),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: _kPagePadH),
                        child: _buildScoreboard(context),
                      ),
                      const SizedBox(height: 16),
                      _buildTabsRail(context),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            _kPagePadH, 14, _kPagePadH, 0),
                        child: _buildActivePanel(context),
                      ),
                    ],
                  ),
                ),
    );
  }

  // ─── Console do agente (protagonista do topo) ──────────────────────────────
  // Identidade do assistente: glyph de bot com badge de estado, nome, papel e
  // janela de atendimento real (das configurações). Tap leva às configurações.

  Widget _buildAgentConsole(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final violet = _violet(context);
    final green = _green(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final s = _agentSettings;
    final bool? active = s?.enabled;
    final statusTone = (active ?? false) ? green : secondary;

    return InkWell(
      onTap: _openSettings,
      borderRadius: BorderRadius.circular(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      violet.withValues(alpha: isDark ? 0.30 : 0.18),
                      violet.withValues(alpha: isDark ? 0.10 : 0.06),
                    ],
                  ),
                  border: Border.all(
                    color: violet.withValues(alpha: isDark ? 0.45 : 0.32),
                  ),
                  boxShadow: ThemeHelpers.cardShadow(context),
                ),
                alignment: Alignment.center,
                child: Icon(
                  active == false ? LucideIcons.botOff : LucideIcons.bot,
                  color: violet,
                  size: 26,
                ),
              ),
              if (active != null)
                Positioned(
                  right: -3,
                  bottom: -3,
                  child: Container(
                    width: 19,
                    height: 19,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: statusTone,
                      border: Border.all(
                        color: ThemeHelpers.backgroundColor(context),
                        width: 2.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      active ? LucideIcons.check : LucideIcons.pause,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Zezin',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: ThemeHelpers.textColor(context),
                          letterSpacing: -0.5,
                          height: 1.0,
                        ),
                      ),
                    ),
                    if (active != null) ...[
                      const SizedBox(width: 8),
                      _agentStatusChip(context, active),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Agente SDR · pré-atendimento com IA',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    height: 1.2,
                  ),
                ),
                if (s != null) ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(LucideIcons.clock3, size: 11.5, color: secondary),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          _scheduleLabel(s),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: secondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            LucideIcons.chevronRight,
            size: 16,
            color: secondary.withValues(alpha: 0.7),
          ),
        ],
      ),
    );
  }

  String _scheduleLabel(SdrSettings s) {
    final start = SdrSettings.hourLabel(s.businessHoursStart);
    final end = SdrSettings.hourLabel(s.businessHoursEnd);
    final days = s.workOnWeekends ? 'todos os dias' : 'seg a sex';
    return 'Atende das $start às $end · $days';
  }

  Widget _agentStatusChip(BuildContext context, bool active) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone =
        active ? _green(context) : ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.38)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? LucideIcons.zap : LucideIcons.pause,
            size: 10.5,
            color: tone,
          ),
          const SizedBox(width: 4),
          Text(
            active ? 'Ativo' : 'Pausado',
            style: TextStyle(
              color: tone,
              fontWeight: FontWeight.w900,
              fontSize: 10.5,
              letterSpacing: 0.2,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Placar do período (composição, não fileira de pills) ──────────────────
  // Número dominante de leads + mostrador de conversão + barra de funil
  // empilhada com legenda + pulso do WhatsApp.

  Widget _buildScoreboard(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final green = _green(context);
    final amber = _amber(context);
    final red = _red(context);
    final s = _metrics.summary;
    final total = s.totalLeads;

    final captionParts = <String>[];
    if (total > 0) {
      captionParts.add(
          '${_int.format(s.uniqueLeads)} único${s.uniqueLeads == 1 ? '' : 's'}');
      if (s.duplicateLeads > 0) {
        captionParts.add(
            '${_int.format(s.duplicateLeads)} duplicado${s.duplicateLeads == 1 ? '' : 's'}');
      }
    }
    final caption = total == 0
        ? 'Nenhum lead captado no recorte atual.'
        : captionParts.join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Título de seção nunca trunca nesta tela — quebra em linhas.
            Expanded(
              child: Text(
                'LEADS NO PERÍODO',
                softWrap: true,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: secondary,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                  fontSize: 10,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _periodChip(context),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _int.format(total),
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -1.2,
                        height: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (total > 0) ...[
              const SizedBox(width: 14),
              _ConversionDial(
                rate: s.conversionRate,
                tone: green,
                track: ThemeHelpers.borderLightColor(context)
                    .withValues(alpha: 0.8),
              ),
            ],
          ],
        ),
        if (total > 0) ...[
          const SizedBox(height: 16),
          _funnelCompositionBar(context, s, green, amber, red),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              if (s.transferred > 0)
                _legendItem(context, green, 'transferidos', s.transferred),
              if (s.inQualification > 0)
                _legendItem(
                    context, amber, 'qualificando', s.inQualification),
              if (s.lost > 0) _legendItem(context, red, 'perdidos', s.lost),
              if (_funnelRest(s) > 0)
                _legendItem(
                  context,
                  secondary.withValues(alpha: 0.6),
                  'outros',
                  _funnelRest(s),
                ),
            ],
          ),
        ],
        if (_metrics.whatsapp != null) ...[
          const SizedBox(height: 14),
          _awaitingPulseLine(context, _metrics.whatsapp!),
        ],
      ],
    );
  }

  int _funnelRest(SdrSummary s) {
    final known = s.transferred + s.inQualification + s.lost;
    return math.max(0, s.totalLeads - known);
  }

  Widget _funnelCompositionBar(BuildContext context, SdrSummary s, Color green,
      Color amber, Color red) {
    final track =
        ThemeHelpers.borderLightColor(context).withValues(alpha: 0.7);
    final rest = _funnelRest(s);
    final segments = <({int value, Color color})>[
      (value: s.transferred, color: green),
      (value: s.inQualification, color: amber),
      (value: s.lost, color: red),
      (value: rest, color: track),
    ].where((seg) => seg.value > 0).toList(growable: false);

    if (segments.isEmpty) {
      return Container(
        height: 10,
        decoration: BoxDecoration(
          color: track,
          borderRadius: BorderRadius.circular(999),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 10,
        child: Row(
          children: [
            for (var i = 0; i < segments.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                flex: segments[i].value,
                child: Container(color: segments[i].color),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _legendItem(
      BuildContext context, Color tone, String label, int value) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: tone,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          _int.format(value),
          style: theme.textTheme.labelSmall?.copyWith(
            color: tone,
            fontWeight: FontWeight.w900,
            fontSize: 11.5,
            height: 1.0,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w600,
            fontSize: 11,
            height: 1.0,
          ),
        ),
      ],
    );
  }

  Widget _awaitingPulseLine(BuildContext context, SdrWhatsappMetrics w) {
    final theme = Theme.of(context);
    final awaiting = w.awaitingReplyCount;
    final tone = awaiting > 0 ? _amber(context) : _green(context);
    final label = awaiting > 0
        ? '$awaiting conversa${awaiting == 1 ? '' : 's'} aguardando resposta no WhatsApp'
        : 'Nenhuma conversa aguardando resposta no WhatsApp';
    return Row(
      children: [
        Icon(
          awaiting > 0 ? LucideIcons.clockAlert : LucideIcons.circleCheckBig,
          size: 13,
          color: tone,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: tone,
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
              height: 1.1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _periodChip(BuildContext context) {
    final violet = _violet(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final active = _filters.activeCount > 0;
    return InkWell(
      onTap: _openFilters,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: violet.withValues(alpha: isDark ? 0.16 : 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: violet.withValues(alpha: active ? 0.55 : 0.28),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.calendarRange, size: 12, color: violet),
            const SizedBox(width: 5),
            Text(
              _filters.periodLabel(),
              style: TextStyle(
                color: violet,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          ],
        ),
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
              tone: _violet(context),
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
              tone: _blue(context),
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

  /// Cabeçalho sóbrio de painel: barra tonal curta + título w900 + hint.
  /// Regra da tela: título de seção NUNCA trunca — quebra em quantas linhas
  /// precisar (a barra tonal fica alinhada à primeira linha).
  Widget _panelHeader(
    BuildContext context, {
    required String title,
    required String hint,
    required Color tone,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Container(
                width: 20,
                height: 3,
                decoration: BoxDecoration(
                  color: tone,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                softWrap: true,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: -0.4,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Padding(
          padding: const EdgeInsets.only(left: 28),
          child: Text(
            hint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  /// Eyebrow de subseção. Regra da tela: o rótulo NUNCA trunca — quebra em
  /// quantas linhas precisar, e o contador flui como sufixo compacto colado à
  /// última palavra (nunca disputa espaço com o texto). O filete separador
  /// desce para a própria linha, abaixo do rótulo.
  Widget _subsectionHeader(
      BuildContext context, String label, IconData icon, int count) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 14, color: secondary),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: label.toUpperCase()),
                    if (count > 0)
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: ThemeHelpers.borderLightColor(context)
                                  .withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _int.format(count),
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                fontSize: 10,
                                letterSpacing: 0.2,
                                height: 1.0,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                softWrap: true,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: secondary,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 1,
          color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.5),
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
        title: 'Como está o pré-atendimento',
        hint: 'Atendimento no WhatsApp, entrada de leads e motivos de perda.',
        tone: _violet(context),
      ),
      const SizedBox(height: 16),
    ];

    if (s.totalLeads == 0) {
      nodes.add(_emptyState(
        context,
        icon: LucideIcons.inbox,
        tone: _violet(context),
        title: 'Sem leads no período',
        body: 'Ajuste o período ou os filtros para ver as métricas do SDR.',
      ));
      return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: nodes);
    }

    // WhatsApp (atendimento).
    final w = _metrics.whatsapp;
    if (w != null) {
      nodes.add(_subsectionHeader(
          context, 'WhatsApp · atendimento', LucideIcons.messageCircle, 0));
      nodes.add(const SizedBox(height: 12));
      nodes.add(_whatsappBand(context, w));
    }

    // Entrada de leads por dia (mini gráfico de barras).
    final days = _metrics.leadsByDay.where((d) => d.date != null).toList();
    if (days.isNotEmpty) {
      if (w != null) nodes.add(const SizedBox(height: 18));
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
      final maxCount = math.max(1, top.first.count);
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
    final violet = _violet(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final data = days.length > 31 ? days.sublist(days.length - 31) : days;
    final maxTotal = data.fold<int>(0, (m, d) => math.max(m, d.total));
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
                        height: math.max(3, 72.0 * data[i].total / maxTotal),
                        decoration: BoxDecoration(
                          color: data[i] == peak
                              ? violet
                              : violet.withValues(alpha: 0.38),
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
              Icon(LucideIcons.trendingUp, size: 11, color: violet),
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
      // Renderização incremental: o payload chega completo do backend, mas a
      // lista cresce em lotes para não travar a tela em equipes grandes.
      final visible =
          agents.length > _teamVisible ? agents.sublist(0, _teamVisible) : agents;
      var animIndex = 0;
      for (var i = 0; i < visible.length; i++) {
        nodes.add(
          _AgentRow(rank: i + 1, agent: visible[i])
              .animate(key: ValueKey('agent-${visible[i].agentId}-$i'))
              .fadeIn(
                delay: Duration(milliseconds: 30 * (animIndex++).clamp(0, 12)),
                duration: 220.ms,
              ),
        );
      }
      if (agents.length > visible.length) {
        nodes.add(_loadMoreControl(
          context,
          tone: green,
          shown: visible.length,
          total: agents.length,
          step: _kTeamPageSize,
          noun: 'atendentes',
          onMore: () => setState(() => _teamVisible += _kTeamPageSize),
        ));
      } else if (agents.length > _kTeamPageSize) {
        nodes.add(_collapseControl(
          context,
          onCollapse: () => setState(() => _teamVisible = _kTeamPageSize),
        ));
      }
    }

    final brokers = [..._metrics.topBrokers]
      ..sort((a, b) => b.received.compareTo(a.received));
    if (brokers.isNotEmpty) {
      final maxReceived = math.max(1, brokers.first.received);
      nodes.add(const SizedBox(height: 18));
      nodes.add(_subsectionHeader(context, 'Corretores que mais receberam',
          LucideIcons.award, brokers.length));
      nodes.add(const SizedBox(height: 12));
      final visibleBrokers = brokers.length > _brokersVisible
          ? brokers.sublist(0, _brokersVisible)
          : brokers;
      for (final b in visibleBrokers) {
        nodes.add(_funnelRow(
            context, b.brokerName, b.received, maxReceived, _blue(context)));
      }
      if (brokers.length > visibleBrokers.length) {
        nodes.add(_loadMoreControl(
          context,
          tone: _blue(context),
          shown: visibleBrokers.length,
          total: brokers.length,
          step: _kBrokersPageSize,
          noun: 'corretores',
          onMore: () => setState(() => _brokersVisible += _kBrokersPageSize),
        ));
      } else if (brokers.length > _kBrokersPageSize) {
        nodes.add(_collapseControl(
          context,
          onCollapse: () =>
              setState(() => _brokersVisible = _kBrokersPageSize),
        ));
      }
    }

    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: nodes);
  }

  // ─── Painel: Origens ───────────────────────────────────────────────────────

  Widget _buildSourcesPanel(BuildContext context) {
    final blue = _blue(context);
    final sources = [..._metrics.bySource]
      ..sort((a, b) => b.totalLeads.compareTo(a.totalLeads));

    final nodes = <Widget>[
      _panelHeader(
        context,
        title: 'De onde vêm os leads',
        hint: 'Volume e conversão por mídia, campanha e qualificação.',
        tone: blue,
      ),
      const SizedBox(height: 16),
    ];

    if (sources.isEmpty) {
      nodes.add(_emptyState(
        context,
        icon: LucideIcons.searchX,
        tone: blue,
        title: 'Sem origens no período',
        body: 'Nenhum lead com origem registrada neste recorte.',
      ));
    } else {
      final visibleSources = sources.length > _sourcesVisible
          ? sources.sublist(0, _sourcesVisible)
          : sources;
      var animIndex = 0;
      for (final src in visibleSources) {
        nodes.add(
          _SourceRow(source: src)
              .animate(key: ValueKey('src-${src.source}'))
              .fadeIn(
                delay: Duration(milliseconds: 30 * (animIndex++).clamp(0, 12)),
                duration: 220.ms,
              ),
        );
      }
      if (sources.length > visibleSources.length) {
        nodes.add(_loadMoreControl(
          context,
          tone: blue,
          shown: visibleSources.length,
          total: sources.length,
          step: _kSourcesPageSize,
          noun: 'origens',
          onMore: () => setState(() => _sourcesVisible += _kSourcesPageSize),
        ));
      } else if (sources.length > _kSourcesPageSize) {
        nodes.add(_collapseControl(
          context,
          onCollapse: () =>
              setState(() => _sourcesVisible = _kSourcesPageSize),
        ));
      }
    }

    final campaigns = [..._metrics.byCampaign]
      ..sort((a, b) => b.totalLeads.compareTo(a.totalLeads));
    if (campaigns.isNotEmpty) {
      final maxLeads = math.max(1, campaigns.first.totalLeads);
      nodes.add(const SizedBox(height: 18));
      nodes.add(_subsectionHeader(
          context, 'Campanhas', LucideIcons.flag, campaigns.length));
      nodes.add(const SizedBox(height: 12));
      final visibleCampaigns = campaigns.length > _campaignsVisible
          ? campaigns.sublist(0, _campaignsVisible)
          : campaigns;
      for (final c in visibleCampaigns) {
        nodes.add(_funnelRow(
            context, c.campaign, c.totalLeads, maxLeads, blue));
      }
      if (campaigns.length > visibleCampaigns.length) {
        nodes.add(_loadMoreControl(
          context,
          tone: blue,
          shown: visibleCampaigns.length,
          total: campaigns.length,
          step: _kCampaignsPageSize,
          noun: 'campanhas',
          onMore: () =>
              setState(() => _campaignsVisible += _kCampaignsPageSize),
        ));
      } else if (campaigns.length > _kCampaignsPageSize) {
        nodes.add(_collapseControl(
          context,
          onCollapse: () =>
              setState(() => _campaignsVisible = _kCampaignsPageSize),
        ));
      }
    }

    final quals = [..._metrics.byQualification]
      ..sort((a, b) => b.totalLeads.compareTo(a.totalLeads));
    if (quals.isNotEmpty) {
      final maxLeads = math.max(1, quals.first.totalLeads);
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

  // ─── Paginação client-side (Carregar mais / Recolher) ──────────────────────

  /// Controle de "Carregar mais" no padrão do app (outlined tonal + chevron),
  /// com legenda de progresso — deixa claro quanto da lista já está visível.
  Widget _loadMoreControl(
    BuildContext context, {
    required Color tone,
    required int shown,
    required int total,
    required int step,
    required String noun,
    required VoidCallback onMore,
  }) {
    final theme = Theme.of(context);
    final next = math.min(step, total - shown);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Column(
        children: [
          Text(
            'Mostrando ${_int.format(shown)} de ${_int.format(total)} $noun',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w600,
              fontSize: 10.5,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onMore,
            style: OutlinedButton.styleFrom(
              foregroundColor: tone,
              side: BorderSide(color: tone.withValues(alpha: 0.45)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            icon: const Icon(LucideIcons.chevronDown, size: 16),
            label: Text('Carregar mais (+${_int.format(next)})'),
          ),
        ],
      ),
    );
  }

  /// Volta a lista ao lote inicial depois de totalmente expandida.
  Widget _collapseControl(
    BuildContext context, {
    required VoidCallback onCollapse,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Center(
        child: TextButton.icon(
          onPressed: onCollapse,
          style: TextButton.styleFrom(
            foregroundColor: ThemeHelpers.textSecondaryColor(context),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
          icon: const Icon(LucideIcons.chevronUp, size: 15),
          label: const Text(
            'Recolher lista',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ),
      ),
    );
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

  /// Skeleton fiel ao layout novo: console do agente (glyph + nome + status),
  /// placar (número dominante + mostrador + barra empilhada), rail de abas e
  /// linhas de painel.
  Widget _buildSkeleton(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            _kPagePadH, _kPagePadTop, _kPagePadH, _kPagePadBottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Console do agente.
            Row(
              children: const [
                SkeletonBox(width: 56, height: 56, borderRadius: 18),
                SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonText(width: 110, height: 17, borderRadius: 5),
                      SizedBox(height: 7),
                      SkeletonText(width: 190, height: 11, borderRadius: 4),
                      SizedBox(height: 6),
                      SkeletonText(width: 160, height: 10, borderRadius: 4),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            // Placar.
            Row(
              children: const [
                SkeletonText(width: 120, height: 10, borderRadius: 4),
                Spacer(),
                SkeletonBox(width: 88, height: 26, borderRadius: 999),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: const [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonText(width: 110, height: 36, borderRadius: 8),
                      SizedBox(height: 8),
                      SkeletonText(width: 150, height: 11, borderRadius: 4),
                    ],
                  ),
                ),
                SizedBox(width: 14),
                SkeletonBox(width: 74, height: 74, borderRadius: 999),
              ],
            ),
            const SizedBox(height: 16),
            const SkeletonBox(
                width: double.infinity, height: 10, borderRadius: 999),
            const SizedBox(height: 10),
            Row(
              children: const [
                SkeletonText(width: 86, height: 10, borderRadius: 4),
                SizedBox(width: 14),
                SkeletonText(width: 86, height: 10, borderRadius: 4),
                SizedBox(width: 14),
                SkeletonText(width: 70, height: 10, borderRadius: 4),
              ],
            ),
            const SizedBox(height: 22),
            // Rail de abas.
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
            // Cabeçalho de painel.
            Row(
              children: const [
                SkeletonBox(width: 20, height: 3, borderRadius: 2),
                SizedBox(width: 8),
                SkeletonText(width: 200, height: 15, borderRadius: 4),
              ],
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.only(left: 28),
              child: SkeletonText(
                  width: double.infinity, height: 11, borderRadius: 4),
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

// ─── Mostrador de conversão (arco custom, sem lib) ───────────────────────────

class _ConversionDial extends StatelessWidget {
  const _ConversionDial({
    required this.rate,
    required this.tone,
    required this.track,
    this.size = 74,
  });

  /// Percentual 0–100.
  final double rate;
  final Color tone;
  final Color track;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final frac = (rate / 100).clamp(0.0, 1.0).toDouble();
    final label = rate >= 99.95
        ? '100%'
        : '${rate.toStringAsFixed(1).replaceAll('.', ',')}%';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: frac),
            duration: const Duration(milliseconds: 750),
            curve: Curves.easeOutCubic,
            builder: (context, anim, _) => CustomPaint(
              painter: _DialPainter(progress: anim, tone: tone, track: track),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.4,
                        fontSize: 15,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'CONVERSÃO',
          style: theme.textTheme.labelSmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            fontSize: 8.5,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.progress,
    required this.tone,
    required this.track,
  });

  final double progress;
  final Color tone;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(rect, 0, math.pi * 2, false, trackPaint);

    if (progress > 0) {
      final progressPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = tone;
      canvas.drawArc(
          rect, -math.pi / 2, math.pi * 2 * progress, false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DialPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.tone != tone ||
      oldDelegate.track != track;
}

// ─── Aba flush (sublinhado, gramática compartilhada do app) ──────────────────

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
    final violet =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    final convFrac = (agent.conversionRate / 100).clamp(0.0, 1.0);
    final isTop = rank == 1 && agent.transferred > 0;
    final rankTone = isTop ? violet : secondary;

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
    final blue = isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
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
                  color: blue.withValues(alpha: isDark ? 0.18 : 0.1),
                ),
                child: Icon(LucideIcons.megaphone, size: 14, color: blue),
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

// ─── Ação da appbar com badge de filtros ativos ──────────────────────────────

/// Envolve um [ChromeToolbarIconButton] com um badge sutil no canto — contador
/// de filtros ativos do dashboard. Some quando `count == 0`.
class _BadgedToolbarAction extends StatelessWidget {
  const _BadgedToolbarAction({required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (count > 0)
          Positioned(
            top: 5,
            right: 4,
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(minWidth: 15),
                height: 15,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: tone,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: ThemeHelpers.backgroundColor(context)
                        .withValues(alpha: 0.9),
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
      ],
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
