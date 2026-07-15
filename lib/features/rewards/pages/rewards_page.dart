import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/reward_model.dart';
import '../services/rewards_service.dart';
import '../widgets/redeem_sheet.dart';
import '../widgets/reward_card.dart';
import '../widgets/rewards_ui.dart';

/// Tela **Catálogo de Resgates** (`/rewards`) — vitrine dos prêmios ativos com
/// os pontos do usuário no hero e a ação **Resgatar** no próprio card.
/// Paridade com `RewardsPage.tsx` do web (gated `reward:redeem`).
class RewardsPage extends StatefulWidget {
  const RewardsPage({super.key});

  @override
  State<RewardsPage> createState() => _RewardsPageState();
}

class _RewardsPageState extends State<RewardsPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const double _kSectionGap = 12;

  List<Reward> _rewards = const [];
  bool _loading = true;
  String? _error;

  int _myPoints = 0;
  bool _pointsLoading = true;

  String? _redeemingId;

  bool get _canRedeem =>
      ModuleAccessService.instance.hasPermission('reward:redeem');

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Color _accent(BuildContext context) => rewardsAccent(context);

  // ─── Dados ───────────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    await Future.wait([_loadPoints(), _loadRewards()]);
  }

  Future<void> _loadPoints() async {
    setState(() => _pointsLoading = true);
    final res = await RewardsService.instance.getMyPoints();
    if (!mounted) return;
    setState(() {
      _pointsLoading = false;
      if (res.success && res.data != null) _myPoints = res.data!;
    });
  }

  Future<void> _loadRewards() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await RewardsService.instance.getAvailableRewards();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _rewards = res.data!;
      } else {
        _error = res.message ?? 'Erro ao carregar o catálogo de prêmios';
      }
    });
  }

  Future<void> _redeem(Reward reward) async {
    final notes = await showRedeemSheet(
      context,
      reward: reward,
      myPoints: _myPoints,
    );
    if (notes == null || !mounted) return;

    setState(() => _redeemingId = reward.id);
    final res = await RewardsService.instance.redeemReward(
      rewardId: reward.id,
      userNotes: notes,
    );
    if (!mounted) return;
    setState(() => _redeemingId = null);

    final messenger = ScaffoldMessenger.of(context);
    if (res.success) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text(
            'Solicitação enviada! Aguarde a aprovação do gestor '
            'para debitar os pontos.',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor:
              Theme.of(context).brightness == Brightness.dark
                  ? AppColors.status.greenDarkMode
                  : AppColors.status.green,
        ),
      );
      _loadRewards();
      Navigator.of(context).pushNamed('/rewards/mine');
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(res.message ?? 'Erro ao solicitar o resgate'),
          behavior: SnackBarBehavior.floating,
          backgroundColor:
              Theme.of(context).brightness == Brightness.dark
                  ? AppColors.status.errorDarkMode
                  : AppColors.status.error,
        ),
      );
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canRedeem) {
      return const AppScaffold(
        title: 'Catálogo de Resgates',
        showBottomNavigation: false,
        body: RewardsDeniedView(
          message: 'Você não tem acesso ao catálogo de resgates.',
          permission: 'reward:redeem',
        ),
      );
    }
    return AppScaffold(
      title: 'Catálogo de Resgates',
      showBottomNavigation: false,
      body: RefreshIndicator(
        color: _accent(context),
        onRefresh: _loadAll,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    _kPagePadH, _kPagePadTop, _kPagePadH, _kPagePadBottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHero(context),
                    const SizedBox(height: _kSectionGap + 6),
                    _buildBody(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Hero editorial (pontos + KPIs) ──────────────────────────────────────

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accent(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final blue = isDark ? AppColors.status.infoDarkMode : AppColors.status.info;

    final affordable =
        _rewards.where((r) => r.hasStock && r.canAfford(_myPoints)).length;
    final subtitle = _rewards.isEmpty
        ? 'Use seus pontos para resgatar prêmios da sua empresa.'
        : affordable > 0
            ? '$affordable prêmio${affordable == 1 ? '' : 's'} ao seu alcance '
                'agora — escolha e solicite o resgate.'
            : 'Continue somando pontos para alcançar o próximo prêmio.';

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
                'CATÁLOGO DE PRÊMIOS',
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
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _pointsLoading
                        ? '—'
                        : rewardsPointsFormat.format(_myPoints),
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: textColor,
                      height: 1.0,
                      letterSpacing: -1.0,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  _myPoints == 1 ? 'ponto' : 'pontos',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                    letterSpacing: -0.2,
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
          _buildKpiStrip(context, accent, blue, emerald),
          const SizedBox(height: 16),
          // Atalho para acompanhar as solicitações — ação clara no hero.
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: () =>
                  Navigator.of(context).pushNamed('/rewards/mine'),
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  letterSpacing: -0.1,
                ),
              ),
              icon: const Icon(LucideIcons.history, size: 16),
              label: const Text('Acompanhar meus resgates'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiStrip(
      BuildContext context, Color accent, Color blue, Color emerald) {
    final divider = ThemeHelpers.borderColor(context).withValues(alpha: 0.45);
    final affordable =
        _rewards.where((r) => r.hasStock && r.canAfford(_myPoints)).length;
    final blocks = <Widget>[
      _heroKpiBlock(
        context,
        LucideIcons.sparkles,
        'SEUS PONTOS',
        _pointsLoading ? '—' : rewardsPointsFormat.format(_myPoints),
        'acumulados',
        accent,
      ),
      _heroKpiBlock(
        context,
        LucideIcons.gift,
        'PRÊMIOS',
        _loading ? '—' : '${_rewards.length}',
        'no catálogo',
        blue,
      ),
      _heroKpiBlock(
        context,
        LucideIcons.circleCheckBig,
        'AO ALCANCE',
        _loading || _pointsLoading ? '—' : '$affordable',
        'para resgatar',
        emerald,
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

  // ─── Corpo (catálogo agrupado por categoria) ─────────────────────────────

  Widget _buildBody(BuildContext context) {
    if (_loading && _rewards.isEmpty) return _buildSkeleton();
    if (_error != null && _rewards.isEmpty) {
      return RewardsErrorState(message: _error!, onRetry: _loadRewards);
    }
    if (_rewards.isEmpty) {
      return RewardsEmptyState(
        icon: LucideIcons.gift,
        title: 'Nenhum prêmio disponível',
        body: 'Não há prêmios no catálogo no momento. '
            'Aguarde novos prêmios da sua empresa!',
        tone: _accent(context),
      );
    }

    final nodes = <Widget>[
      RewardsPanelHeader(
        icon: LucideIcons.gift,
        eyebrow: 'CATÁLOGO',
        title: 'Prêmios disponíveis',
        hint: 'Escolha o prêmio e solicite o resgate — os pontos são '
            'debitados após a aprovação do gestor.',
        tone: _accent(context),
      ),
      const SizedBox(height: 14),
    ];

    var animIndex = 0;
    for (final group in _groupByCategory(_rewards)) {
      if (animIndex > 0) nodes.add(const SizedBox(height: 16));
      nodes.add(RewardsSubsectionHeader(
        label: group.category.label,
        icon: _categoryIcon(group.category),
        count: group.items.length,
      ));
      nodes.add(const SizedBox(height: 10));
      for (final reward in group.items) {
        nodes.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: RewardCard(
              reward: reward,
              myPoints: _myPoints,
              onRedeem:
                  _redeemingId == null ? () => _redeem(reward) : null,
            ),
          ).animate(key: ValueKey('r-${reward.id}')).fadeIn(
                delay: Duration(milliseconds: 30 * (animIndex++).clamp(0, 12)),
                duration: 220.ms,
              ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: nodes,
    );
  }

  /// Agrupa por categoria preservando a ordem do catálogo (displayOrder).
  List<({RewardCategory category, List<Reward> items})> _groupByCategory(
      List<Reward> list) {
    final map = <RewardCategory, List<Reward>>{};
    for (final r in list) {
      map.putIfAbsent(r.category, () => []).add(r);
    }
    return map.entries
        .map((e) => (category: e.key, items: e.value))
        .toList(growable: false);
  }

  IconData _categoryIcon(RewardCategory category) {
    switch (category) {
      case RewardCategory.monetary:
        return LucideIcons.banknote;
      case RewardCategory.timeOff:
        return LucideIcons.calendarDays;
      case RewardCategory.gift:
        return LucideIcons.gift;
      case RewardCategory.experience:
        return LucideIcons.star;
      case RewardCategory.recognition:
        return LucideIcons.trophy;
      case RewardCategory.other:
        return LucideIcons.box;
    }
  }

  // ─── Skeleton fiel ao card do catálogo ───────────────────────────────────

  Widget _buildSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(
        4,
        (_) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: BorderRadius.circular(18),
            boxShadow: ThemeHelpers.cardShadow(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBox(width: 52, height: 52, borderRadius: 15),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonText(width: double.infinity, height: 16),
                        SizedBox(height: 8),
                        SkeletonText(width: 110, height: 12),
                      ],
                    ),
                  ),
                  SizedBox(width: 10),
                  SkeletonBox(width: 84, height: 26, borderRadius: 999),
                ],
              ),
              const SizedBox(height: 12),
              const SkeletonText(width: double.infinity, height: 12),
              const SizedBox(height: 6),
              const SkeletonText(width: 180, height: 12),
              const SizedBox(height: 14),
              const SkeletonBox(
                  width: double.infinity, height: 42, borderRadius: 13),
            ],
          ),
        ),
      ),
    );
  }
}
