import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/reward_model.dart';
import '../services/rewards_service.dart';
import '../widgets/redemption_card.dart';
import '../widgets/rewards_ui.dart';

/// Aba da tela Meus Resgates — `null` = todos os status.
enum _MyRedemptionsTab { all, pending, approved, rejected, delivered }

/// Tela **Meus Resgates** (`/rewards/mine`) — acompanhamento das solicitações
/// do usuário com abas flush por status (filtro no cliente, paridade com
/// `MyRedemptionsPage.tsx`). Gated `reward:redeem`.
class MyRedemptionsPage extends StatefulWidget {
  const MyRedemptionsPage({super.key});

  @override
  State<MyRedemptionsPage> createState() => _MyRedemptionsPageState();
}

class _MyRedemptionsPageState extends State<MyRedemptionsPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const double _kSectionGap = 12;

  List<RewardRedemption> _redemptions = const [];
  bool _loading = true;
  String? _error;
  _MyRedemptionsTab _activeTab = _MyRedemptionsTab.all;

  bool get _canView =>
      ModuleAccessService.instance.hasPermission('reward:redeem');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Color _accent(BuildContext context) => rewardsAccent(context);

  // ─── Dados ───────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await RewardsService.instance.getMyRedemptions();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _redemptions = res.data!;
      } else {
        _error = res.message ?? 'Erro ao carregar seus resgates';
      }
    });
  }

  RedemptionStatus? _statusOf(_MyRedemptionsTab tab) {
    switch (tab) {
      case _MyRedemptionsTab.all:
        return null;
      case _MyRedemptionsTab.pending:
        return RedemptionStatus.pending;
      case _MyRedemptionsTab.approved:
        return RedemptionStatus.approved;
      case _MyRedemptionsTab.rejected:
        return RedemptionStatus.rejected;
      case _MyRedemptionsTab.delivered:
        return RedemptionStatus.delivered;
    }
  }

  List<RewardRedemption> _itemsOf(_MyRedemptionsTab tab) {
    final status = _statusOf(tab);
    if (status == null) return _redemptions;
    return _redemptions.where((r) => r.status == status).toList();
  }

  int _countOf(_MyRedemptionsTab tab) => _itemsOf(tab).length;

  Color _tabColor(BuildContext context, _MyRedemptionsTab tab) {
    final status = _statusOf(tab);
    if (status == null) return _accent(context);
    return redemptionStatusColor(context, status);
  }

  String _tabLabel(_MyRedemptionsTab tab) {
    switch (tab) {
      case _MyRedemptionsTab.all:
        return 'Todos';
      case _MyRedemptionsTab.pending:
        return 'Pendentes';
      case _MyRedemptionsTab.approved:
        return 'Aprovados';
      case _MyRedemptionsTab.rejected:
        return 'Rejeitados';
      case _MyRedemptionsTab.delivered:
        return 'Entregues';
    }
  }

  IconData _tabIcon(_MyRedemptionsTab tab) {
    final status = _statusOf(tab);
    if (status == null) return LucideIcons.history;
    return redemptionStatusIcon(status);
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canView) {
      return const AppScaffold(
        title: 'Meus Resgates',
        showBottomNavigation: false,
        body: RewardsDeniedView(
          message: 'Você não tem acesso aos resgates de prêmios.',
          permission: 'reward:redeem',
        ),
      );
    }
    return AppScaffold(
      title: 'Meus Resgates',
      showBottomNavigation: false,
      body: RefreshIndicator(
        color: _accent(context),
        onRefresh: _load,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        _kPagePadH, _kPagePadTop, _kPagePadH, 0),
                    child: _buildHero(context),
                  ),
                  const SizedBox(height: _kSectionGap + 4),
                  _buildTabsRail(context),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        _kPagePadH, _kSectionGap, _kPagePadH, _kPagePadBottom),
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

  // ─── Hero editorial ──────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accent(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final blue = isDark ? AppColors.status.infoDarkMode : AppColors.status.info;

    final total = _redemptions.length;
    final pending = _countOf(_MyRedemptionsTab.pending);
    final dot = pending > 0 ? amber : emerald;
    final subtitle = total == 0
        ? 'Suas solicitações de resgate aparecem aqui.'
        : pending > 0
            ? '$pending solicitaç${pending == 1 ? 'ão aguarda' : 'ões aguardam'} '
                'aprovação do gestor.'
            : 'Nenhuma solicitação pendente no momento.';

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
                'MEUS RESGATES',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.2,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              // Ação no hero: voltar ao catálogo.
              InkResponse(
                radius: 22,
                onTap: () =>
                    Navigator.of(context).pushNamed('/rewards'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.gift, size: 14, color: accent),
                    const SizedBox(width: 5),
                    Text(
                      'Catálogo',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$total',
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
                  total == 1 ? 'resgate' : 'resgates',
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
          _buildKpiStrip(context, amber, emerald, blue),
        ],
      ),
    );
  }

  Widget _buildKpiStrip(
      BuildContext context, Color amber, Color emerald, Color blue) {
    final divider = ThemeHelpers.borderColor(context).withValues(alpha: 0.45);
    final pending = _countOf(_MyRedemptionsTab.pending);
    final approved = _countOf(_MyRedemptionsTab.approved);
    final delivered = _countOf(_MyRedemptionsTab.delivered);
    final blocks = <Widget>[
      _heroKpiBlock(context, LucideIcons.hourglass, 'PENDENTES',
          _loading ? '—' : '$pending', 'em análise', amber),
      _heroKpiBlock(context, LucideIcons.circleCheck, 'APROVADOS',
          _loading ? '—' : '$approved', 'a entregar', emerald),
      _heroKpiBlock(context, LucideIcons.gift, 'ENTREGUES',
          _loading ? '—' : '$delivered', 'recebidos', blue),
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
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: tone,
              letterSpacing: -0.6,
              height: 1.0,
              fontSize: 22,
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

  // ─── Abas flush (rolagem horizontal — 5 status) ──────────────────────────

  Widget _buildTabsRail(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: _kPagePadH - 8),
        child: Row(
          children: [
            for (final tab in _MyRedemptionsTab.values)
              RewardsFlushTab(
                icon: _tabIcon(tab),
                label: _tabLabel(tab),
                count: _countOf(tab),
                tone: _tabColor(context, tab),
                selected: _activeTab == tab,
                expanded: false,
                onTap: () => setState(() => _activeTab = tab),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Painel ativo ────────────────────────────────────────────────────────

  Widget _buildActivePanel(BuildContext context) {
    final items = _itemsOf(_activeTab);
    Widget child;
    if (_loading && _redemptions.isEmpty) {
      child = _buildSkeleton();
    } else if (_error != null && _redemptions.isEmpty) {
      child = RewardsErrorState(message: _error!, onRetry: _load);
    } else if (items.isEmpty) {
      child = _buildEmpty(context);
    } else {
      child = _buildList(context, items);
    }

    return Column(
      key: ValueKey('panel-${_activeTab.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPanelHeader(context),
        const SizedBox(height: 14),
        child,
      ],
    ).animate(key: ValueKey('panel-${_activeTab.name}')).fadeIn(
          duration: 240.ms,
        );
  }

  Widget _buildPanelHeader(BuildContext context) {
    final tone = _tabColor(context, _activeTab);
    final meta = switch (_activeTab) {
      _MyRedemptionsTab.all => (
          eyebrow: 'HISTÓRICO',
          title: 'Todas as solicitações',
          hint: 'Seu histórico completo de resgates, do mais recente ao '
              'mais antigo.',
        ),
      _MyRedemptionsTab.pending => (
          eyebrow: 'EM ANÁLISE',
          title: 'Aguardando aprovação',
          hint: 'Os pontos só são debitados quando o gestor aprovar.',
        ),
      _MyRedemptionsTab.approved => (
          eyebrow: 'APROVADOS',
          title: 'Prontos para entrega',
          hint: 'Aprovados pelo gestor — combine a retirada do prêmio.',
        ),
      _MyRedemptionsTab.rejected => (
          eyebrow: 'REJEITADOS',
          title: 'Solicitações rejeitadas',
          hint: 'Nenhum ponto foi debitado nestas solicitações.',
        ),
      _MyRedemptionsTab.delivered => (
          eyebrow: 'ENTREGUES',
          title: 'Prêmios recebidos',
          hint: 'Tudo que você já resgatou e recebeu.',
        ),
    };
    return RewardsPanelHeader(
      icon: _tabIcon(_activeTab),
      eyebrow: meta.eyebrow,
      title: meta.title,
      hint: meta.hint,
      tone: tone,
    );
  }

  Widget _buildList(BuildContext context, List<RewardRedemption> items) {
    final nodes = <Widget>[];
    var animIndex = 0;
    for (final group in _groupByMonth(items)) {
      if (nodes.isNotEmpty) nodes.add(const SizedBox(height: 14));
      nodes.add(RewardsSubsectionHeader(
        label: group.label,
        icon: LucideIcons.calendarDays,
        count: group.items.length,
      ));
      nodes.add(const SizedBox(height: 8));
      for (final r in group.items) {
        nodes.add(
          RedemptionCard(redemption: r)
              .animate(key: ValueKey('rd-${r.id}'))
              .fadeIn(
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

  /// Agrupa por mês preservando a ordem (lista vem desc por data).
  List<({String label, List<RewardRedemption> items})> _groupByMonth(
      List<RewardRedemption> list) {
    final fmt = DateFormat('MMMM yyyy', 'pt_BR');
    final map = <String, List<RewardRedemption>>{};
    for (final r in list) {
      final d = r.createdAt?.toLocal();
      final key = d == null ? 'Sem data' : fmt.format(d);
      map.putIfAbsent(key, () => []).add(r);
    }
    return map.entries
        .map((e) => (label: e.key, items: e.value))
        .toList(growable: false);
  }

  Widget _buildEmpty(BuildContext context) {
    final tone = _tabColor(context, _activeTab);
    final isAll = _activeTab == _MyRedemptionsTab.all;
    final (icon, title, body) = switch (_activeTab) {
      _MyRedemptionsTab.all => (
          LucideIcons.gift,
          'Nenhuma solicitação ainda',
          'Você ainda não solicitou nenhum resgate. '
              'Visite o catálogo para escolher um prêmio!',
        ),
      _MyRedemptionsTab.pending => (
          LucideIcons.partyPopper,
          'Nada em análise',
          'Você não tem solicitações aguardando aprovação.',
        ),
      _MyRedemptionsTab.approved => (
          LucideIcons.circleCheck,
          'Nenhum aprovado',
          'Quando uma solicitação for aprovada, ela aparece aqui.',
        ),
      _MyRedemptionsTab.rejected => (
          LucideIcons.xCircle,
          'Nenhum rejeitado',
          'Você não tem solicitações rejeitadas.',
        ),
      _MyRedemptionsTab.delivered => (
          LucideIcons.gift,
          'Nenhum entregue ainda',
          'Os prêmios entregues aparecem aqui.',
        ),
    };
    return RewardsEmptyState(
      icon: icon,
      title: title,
      body: body,
      tone: tone,
      actionLabel: isAll ? 'Ver catálogo de prêmios' : null,
      onAction: isAll
          ? () => Navigator.of(context).pushNamed('/rewards')
          : null,
    );
  }

  // ─── Skeleton fiel à linha flush ─────────────────────────────────────────

  Widget _buildSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(
        5,
        (_) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBox(width: 44, height: 44, borderRadius: 13),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonText(width: 120, height: 16, borderRadius: 999),
                    SizedBox(height: 9),
                    SkeletonText(width: double.infinity, height: 14),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const SkeletonText(width: 64, height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
