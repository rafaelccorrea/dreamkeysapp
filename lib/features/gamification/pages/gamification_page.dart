import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/gamification_models.dart';
import '../services/gamification_service.dart';
import '../widgets/achievement_card.dart';
import '../widgets/gamification_ui.dart';
import '../widgets/podium.dart';
import '../widgets/ranking_tile.dart';
import 'gamification_settings_page.dart';

final NumberFormat _pts = NumberFormat.decimalPattern('pt_BR');
final NumberFormat _compact = NumberFormat.compactCurrency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 1,
);

/// Dashboard de **Gamificação** — pontos, posição, conquistas e rankings
/// (individual + equipes) da empresa. Paridade `GamificationPage.tsx`.
class GamificationPage extends StatefulWidget {
  const GamificationPage({super.key});

  @override
  State<GamificationPage> createState() => _GamificationPageState();
}

enum _RankTab { individual, teams }

class _GamificationPageState extends State<GamificationPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const double _kSectionGap = 12;

  ScorePeriod _period = ScorePeriod.monthly;
  _RankTab _activeTab = _RankTab.individual;

  bool _loading = true;
  String? _error;
  GamificationConfig? _config;
  GamificationDashboard? _dashboard;
  List<GamificationScore> _individualRankings = const [];
  List<TeamScore> _teamRankings = const [];

  bool get _canView => ModuleAccessService.instance
      .hasPermission('gamification:view');
  bool get _canConfigure => ModuleAccessService.instance
      .hasPermission('gamification:configure');

  String? get _myUserId =>
      _dashboard?.myScore.userId.isNotEmpty == true
          ? _dashboard!.myScore.userId
          : ModuleAccessService.instance.userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    // Config primeiro — se a gamificação estiver desativada, nem carrega o resto.
    final configRes = await GamificationService.instance.getConfig();
    if (!mounted) return;
    if (configRes.success && configRes.data != null) {
      _config = configRes.data;
      if (!_config!.isEnabled) {
        setState(() => _loading = false);
        return;
      }
    }

    final results = await Future.wait([
      GamificationService.instance.getDashboard(period: _period),
      GamificationService.instance.getIndividualRankings(period: _period),
      GamificationService.instance.getTeamRankings(period: _period),
    ]);
    if (!mounted) return;

    final dashRes = results[0] as dynamic;
    final indRes = results[1] as dynamic;
    final teamRes = results[2] as dynamic;

    setState(() {
      _loading = false;
      if (dashRes.success && dashRes.data != null) {
        _dashboard = dashRes.data as GamificationDashboard;
      } else if (_dashboard == null) {
        _error = dashRes.message ?? 'Erro ao carregar gamificação';
      }
      if (indRes.success && indRes.data != null) {
        _individualRankings = (indRes.data as List<GamificationScore>);
      }
      if (teamRes.success && teamRes.data != null) {
        _teamRankings = (teamRes.data as List<TeamScore>);
      }
    });
  }

  void _selectPeriod(ScorePeriod p) {
    if (p == _period) return;
    setState(() => _period = p);
    _load();
  }

  void _openSettings() {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => const GamificationSettingsPage(),
          ),
        )
        .then((_) => _load());
  }

  /// Lista de rankings: usa a lista completa quando existir, senão o top 5.
  List<GamificationScore> get _rankList =>
      _individualRankings.isNotEmpty ? _individualRankings : (_dashboard?.top5 ?? const []);

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canView) {
      return const AppScaffold(
        title: 'Gamificação',
        showBottomNavigation: false,
        body: GamDeniedView(
          what: 'gamificação',
          permission: 'gamification:view',
        ),
      );
    }

    return AppScaffold(
      title: 'Gamificação',
      showBottomNavigation: false,
      actions: [
        if (_canConfigure)
          IconButton(
            tooltip: 'Configurar gamificação',
            icon: const Icon(LucideIcons.settings2, size: 20),
            onPressed: _openSettings,
          ),
      ],
      body: RefreshIndicator(
        color: gamAccentColor(context),
        onRefresh: _load,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: _buildContent(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loading) return _buildSkeleton(context);

    if (_config != null && !_config!.isEnabled) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
            _kPagePadH, 60, _kPagePadH, _kPagePadBottom),
        child: GamEmptyState(
          icon: LucideIcons.gamepad2,
          title: 'Gamificação desativada',
          body: 'O sistema de gamificação não está ativado para sua empresa. '
              '${_canConfigure ? 'Ative nas configurações para começar.' : 'Fale com o administrador para ativar.'}',
          tone: gamAmber(context),
          action: _canConfigure
              ? FilledButton.icon(
                  onPressed: _openSettings,
                  style: FilledButton.styleFrom(
                    backgroundColor: gamAccentColor(context),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(LucideIcons.settings2, size: 16),
                  label: const Text('Configurar Gamificação'),
                )
              : null,
        ),
      );
    }

    if (_error != null && _dashboard == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
            _kPagePadH, 60, _kPagePadH, _kPagePadBottom),
        child: GamErrorState(message: _error!, onRetry: _load),
      );
    }

    final dash = _dashboard;
    if (dash == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
            _kPagePadH, 60, _kPagePadH, _kPagePadBottom),
        child: GamEmptyState(
          icon: LucideIcons.trophy,
          title: 'Sem dados ainda',
          body: 'Assim que houver atividade pontuada, seu placar aparece aqui.',
          tone: gamAccentColor(context),
        ),
      );
    }

    final showAchievements =
        (_config?.showAchievements ?? true) && dash.recentAchievements.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              _kPagePadH, _kPagePadTop, _kPagePadH, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHero(context, dash),
              const SizedBox(height: 14),
              _buildPeriodChips(context),
              const SizedBox(height: 18),
              _buildPointsBreakdown(context, dash.myScore),
              if (showAchievements) ...[
                const SizedBox(height: 22),
                _buildAchievements(context, dash),
              ],
              const SizedBox(height: 22),
            ],
          ),
        ),
        _buildRankTabs(context),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              _kPagePadH, _kSectionGap, _kPagePadH, _kPagePadBottom),
          child: _buildActiveRankingPanel(context, dash),
        ),
      ],
    );
  }

  // ─── Hero editorial ──────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context, GamificationDashboard dash) {
    final theme = Theme.of(context);
    final accent = gamAccentColor(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final emerald = gamGreen(context);
    final amber = gamAmber(context);
    final blue = gamBlue(context);

    final score = dash.myScore;
    final hasPosition = dash.myPosition > 0 && dash.totalParticipants > 0;
    final dot = hasPosition && dash.myPosition <= 3 ? emerald : amber;

    final welcome = (_config?.welcomeMessage ?? '').trim();
    final subtitle = welcome.isNotEmpty
        ? welcome
        : hasPosition
            ? 'Você está em ${dash.myPosition}º lugar de '
                '${dash.totalParticipants} participante${dash.totalParticipants == 1 ? '' : 's'} — ${_period.longLabel.toLowerCase()}.'
            : 'Pontue vendendo, atendendo clientes e concluindo atividades.';

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
              Text(
                'GAMIFICAÇÃO',
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _pts.format(score.totalPoints),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: textColor,
                  height: 1.0,
                  letterSpacing: -1.0,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  score.totalPoints == 1 ? 'ponto' : 'pontos',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (hasPosition) ...[
                const Spacer(),
                _buildPositionBadge(context, dash.myPosition),
              ],
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
          _buildKpiStrip(context, score, emerald, blue, amber),
        ],
      ),
    );
  }

  Widget _buildPositionBadge(BuildContext context, int position) {
    final tone = gamRankColor(context, position);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(colors: [
          tone.withValues(alpha: isDark ? 0.26 : 0.16),
          tone.withValues(alpha: isDark ? 0.12 : 0.07),
        ]),
        border: Border.all(color: tone.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            position == 1 ? LucideIcons.crown : LucideIcons.medal,
            size: 14,
            color: tone,
          ),
          const SizedBox(width: 5),
          Text(
            '$positionº',
            style: TextStyle(
              color: tone,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiStrip(BuildContext context, GamificationScore score,
      Color emerald, Color blue, Color amber) {
    final divider = ThemeHelpers.borderColor(context).withValues(alpha: 0.45);
    final blocks = <Widget>[
      _heroKpiBlock(
        context,
        LucideIcons.badgeDollarSign,
        'VENDAS',
        '${score.propertiesSold}',
        _compact.format(score.totalSalesValue),
        emerald,
      ),
      _heroKpiBlock(
        context,
        LucideIcons.users,
        'CLIENTES',
        '${score.newClientsCreated}',
        '${score.clientsContacted} contato${score.clientsContacted == 1 ? '' : 's'}',
        blue,
      ),
      _heroKpiBlock(
        context,
        LucideIcons.circleCheckBig,
        'ATIVIDADES',
        '${score.tasksCompleted}',
        '${score.inspectionsCompleted} vistoria${score.inspectionsCompleted == 1 ? '' : 's'}',
        amber,
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

  // ─── Seletor de período ──────────────────────────────────────────────────

  Widget _buildPeriodChips(BuildContext context) {
    final accent = gamAccentColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final p in ScorePeriod.values) ...[
            GestureDetector(
              onTap: () => _selectPeriod(p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                margin: const EdgeInsets.only(right: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: p == _period
                      ? accent.withValues(alpha: isDark ? 0.22 : 0.1)
                      : Colors.transparent,
                  border: Border.all(
                    color: p == _period
                        ? accent.withValues(alpha: 0.5)
                        : ThemeHelpers.borderColor(context)
                            .withValues(alpha: 0.6),
                  ),
                ),
                child: Text(
                  p.label,
                  style: TextStyle(
                    color: p == _period ? accent : secondary,
                    fontWeight:
                        p == _period ? FontWeight.w900 : FontWeight.w600,
                    fontSize: 12.5,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Composição dos pontos ───────────────────────────────────────────────

  Widget _buildPointsBreakdown(BuildContext context, GamificationScore score) {
    final total = score.totalPoints <= 0 ? 1 : score.totalPoints;
    final rows = <(String, int, Color, IconData)>[
      ('Vendas', score.salesPoints, gamGreen(context),
          LucideIcons.badgeDollarSign),
      ('Relacionamento', score.relationshipPoints, gamBlue(context),
          LucideIcons.heartHandshake),
      ('Atividade', score.activityPoints, gamAmber(context),
          LucideIcons.zap),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const GamSubsectionHeader(
          label: 'Composição dos pontos',
          icon: LucideIcons.chartBar,
        ),
        const SizedBox(height: 12),
        for (final (label, value, tone, icon) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _pointsBar(context, label, value, total, tone, icon),
          ),
      ],
    );
  }

  Widget _pointsBar(BuildContext context, String label, int value, int total,
      Color tone, IconData icon) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final fraction = (value / total).clamp(0.0, 1.0);

    return Row(
      children: [
        Icon(icon, size: 14, color: tone),
        const SizedBox(width: 8),
        SizedBox(
          width: 108,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 7,
              color: tone.withValues(alpha: 0.14),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fraction,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: LinearGradient(colors: [
                      tone.withValues(alpha: 0.75),
                      tone,
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 62,
          child: Text(
            '${_pts.format(value)} pts',
            textAlign: TextAlign.right,
            style: theme.textTheme.labelSmall?.copyWith(
              color: secondary,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }

  // ─── Conquistas recentes ─────────────────────────────────────────────────

  Widget _buildAchievements(BuildContext context, GamificationDashboard dash) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GamSubsectionHeader(
          label: 'Conquistas recentes',
          icon: LucideIcons.award,
          count: dash.achievementsTotal,
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: dash.recentAchievements.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) => GamAchievementCard(
              userAchievement: dash.recentAchievements[i],
              width: 230,
            )
                .animate(key: ValueKey('ach-${dash.recentAchievements[i].id}'))
                .fadeIn(
                  delay: Duration(milliseconds: 40 * i.clamp(0, 8)),
                  duration: 220.ms,
                ),
          ),
        ),
      ],
    );
  }

  // ─── Rankings ────────────────────────────────────────────────────────────

  Widget _buildRankTabs(BuildContext context) {
    final showIndividual = _config?.showIndividualRanking ?? true;
    final showTeams = _config?.showTeamRanking ?? true;
    if (!showIndividual && !showTeams) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: _kPagePadH - 8),
      child: Row(
        children: [
          if (showIndividual)
            Expanded(
              child: GamFlushTab(
                icon: LucideIcons.user,
                label: 'Individual',
                count: _rankList.length,
                tone: gamAccentColor(context),
                selected: _activeTab == _RankTab.individual,
                onTap: () =>
                    setState(() => _activeTab = _RankTab.individual),
              ),
            ),
          if (showTeams)
            Expanded(
              child: GamFlushTab(
                icon: LucideIcons.users2,
                label: 'Equipes',
                count: _teamRankings.length,
                tone: gamPurple(context),
                selected: _activeTab == _RankTab.teams,
                onTap: () => setState(() => _activeTab = _RankTab.teams),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActiveRankingPanel(
      BuildContext context, GamificationDashboard dash) {
    final showIndividual = _config?.showIndividualRanking ?? true;
    final showTeams = _config?.showTeamRanking ?? true;
    if (!showIndividual && !showTeams) return const SizedBox.shrink();

    final tab = !showIndividual
        ? _RankTab.teams
        : !showTeams
            ? _RankTab.individual
            : _activeTab;

    final rankingMessage = (_config?.rankingMessage ?? '').trim();
    final child = tab == _RankTab.individual
        ? _buildIndividualRanking(context, dash)
        : _buildTeamRanking(context);

    return Column(
      key: ValueKey('rank-panel-${tab.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GamPanelHeader(
          icon: tab == _RankTab.individual
              ? LucideIcons.trophy
              : LucideIcons.shield,
          eyebrow: tab == _RankTab.individual ? 'RANKING' : 'EQUIPES',
          title: tab == _RankTab.individual
              ? 'Ranking individual'
              : 'Ranking de equipes',
          hint: rankingMessage.isNotEmpty
              ? rankingMessage
              : tab == _RankTab.individual
                  ? 'Quem mais pontuou no período — ${_period.longLabel.toLowerCase()}.'
                  : 'Pontuação somada por equipe — ${_period.longLabel.toLowerCase()}.',
          tone: tab == _RankTab.individual
              ? gamAccentColor(context)
              : gamPurple(context),
        ),
        const SizedBox(height: 16),
        child,
      ],
    ).animate(key: ValueKey('rank-panel-${tab.name}')).fadeIn(duration: 240.ms);
  }

  Widget _buildIndividualRanking(
      BuildContext context, GamificationDashboard dash) {
    final list = _rankList;
    if (list.isEmpty) {
      return GamEmptyState(
        icon: LucideIcons.trophy,
        title: 'Ranking vazio',
        body: 'Ninguém pontuou neste período ainda. Seja o primeiro!',
        tone: gamAccentColor(context),
      );
    }

    final myId = _myUserId;
    final podiumEntries = <PodiumEntry>[];
    final rest = <GamificationScore>[];
    for (var i = 0; i < list.length; i++) {
      final s = list[i];
      final pos = s.rankPosition ?? (i + 1);
      if (pos <= 3 && podiumEntries.length < 3) {
        podiumEntries.add(PodiumEntry(
          title: s.user?.name ?? 'Corretor',
          subtitle: '${s.propertiesSold} venda${s.propertiesSold == 1 ? '' : 's'}',
          points: s.totalPoints,
          position: pos,
          isMe: myId != null && s.userId == myId,
        ));
      } else {
        rest.add(s);
      }
    }

    var animIndex = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (podiumEntries.isNotEmpty) ...[
          GamPodium(entries: podiumEntries)
              .animate()
              .fadeIn(duration: 300.ms)
              .slideY(begin: 0.04, end: 0, duration: 300.ms),
          const SizedBox(height: 18),
        ],
        for (var i = 0; i < rest.length; i++)
          GamRankingTile(
            position: rest[i].rankPosition ?? (podiumEntries.length + i + 1),
            title: rest[i].user?.name ?? 'Corretor',
            subtitle: rest[i].user?.email ?? '',
            metrics:
                '${rest[i].propertiesSold} venda${rest[i].propertiesSold == 1 ? '' : 's'} · '
                '${rest[i].newClientsCreated} cliente${rest[i].newClientsCreated == 1 ? '' : 's'} · '
                '${rest[i].tasksCompleted} tarefa${rest[i].tasksCompleted == 1 ? '' : 's'}',
            points: rest[i].totalPoints,
            isMe: myId != null && rest[i].userId == myId,
          ).animate(key: ValueKey('rk-${rest[i].id}')).fadeIn(
                delay: Duration(milliseconds: 30 * (animIndex++).clamp(0, 12)),
                duration: 220.ms,
              ),
      ],
    );
  }

  Widget _buildTeamRanking(BuildContext context) {
    if (_teamRankings.isEmpty) {
      return GamEmptyState(
        icon: LucideIcons.users2,
        title: 'Sem equipes no ranking',
        body: 'Quando as equipes pontuarem no período, elas aparecem aqui.',
        tone: gamPurple(context),
      );
    }

    final podiumEntries = <PodiumEntry>[];
    final rest = <TeamScore>[];
    for (var i = 0; i < _teamRankings.length; i++) {
      final t = _teamRankings[i];
      final pos = t.rankPosition ?? (i + 1);
      if (pos <= 3 && podiumEntries.length < 3) {
        podiumEntries.add(PodiumEntry(
          title: t.teamName ?? 'Equipe',
          subtitle:
              '${t.totalMembers} membro${t.totalMembers == 1 ? '' : 's'}',
          points: t.totalPoints,
          position: pos,
        ));
      } else {
        rest.add(t);
      }
    }

    var animIndex = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (podiumEntries.isNotEmpty) ...[
          GamPodium(entries: podiumEntries)
              .animate()
              .fadeIn(duration: 300.ms)
              .slideY(begin: 0.04, end: 0, duration: 300.ms),
          const SizedBox(height: 18),
        ],
        for (var i = 0; i < rest.length; i++)
          GamRankingTile(
            position: rest[i].rankPosition ?? (podiumEntries.length + i + 1),
            title: rest[i].teamName ?? 'Equipe',
            subtitle: '',
            metrics:
                '${rest[i].totalMembers} membro${rest[i].totalMembers == 1 ? '' : 's'} · '
                'média ${rest[i].averagePointsPerMember.toStringAsFixed(0)} pts/membro',
            points: rest[i].totalPoints,
          ).animate(key: ValueKey('tk-${rest[i].id}')).fadeIn(
                delay: Duration(milliseconds: 30 * (animIndex++).clamp(0, 12)),
                duration: 220.ms,
              ),
      ],
    );
  }

  // ─── Skeleton fiel ───────────────────────────────────────────────────────

  Widget _buildSkeleton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          _kPagePadH, _kPagePadTop + 4, _kPagePadH, _kPagePadBottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonText(width: 130, height: 12, borderRadius: 999),
          const SizedBox(height: 14),
          const SkeletonText(width: 170, height: 34, borderRadius: 10),
          const SizedBox(height: 10),
          const SkeletonText(width: double.infinity, height: 13),
          const SizedBox(height: 20),
          Row(
            children: const [
              Expanded(child: SkeletonBox(height: 64, borderRadius: 12)),
              SizedBox(width: 10),
              Expanded(child: SkeletonBox(height: 64, borderRadius: 12)),
              SizedBox(width: 10),
              Expanded(child: SkeletonBox(height: 64, borderRadius: 12)),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: const [
              SkeletonBox(width: 72, height: 30, borderRadius: 999),
              SizedBox(width: 8),
              SkeletonBox(width: 72, height: 30, borderRadius: 999),
              SizedBox(width: 8),
              SkeletonBox(width: 72, height: 30, borderRadius: 999),
            ],
          ),
          const SizedBox(height: 24),
          for (var i = 0; i < 3; i++) ...[
            const SkeletonText(width: double.infinity, height: 10),
            const SizedBox(height: 14),
          ],
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: const [
              Expanded(child: SkeletonBox(height: 120, borderRadius: 14)),
              SizedBox(width: 8),
              Expanded(child: SkeletonBox(height: 150, borderRadius: 14)),
              SizedBox(width: 8),
              Expanded(child: SkeletonBox(height: 100, borderRadius: 14)),
            ],
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < 3; i++) ...[
            const SkeletonBox(
                width: double.infinity, height: 62, borderRadius: 16),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
