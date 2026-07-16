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
import '../widgets/manage_reward_card.dart';
import '../widgets/rewards_ui.dart';

/// Aba da tela Configurar Resgates — filtro por situação do prêmio.
enum _ManageTab { active, inactive, all }

/// Tela **Configurar Resgates** (`/rewards/manage`) — administração do
/// catálogo: estatísticas de resgates, lista de prêmios (ativos e inativos) e
/// ações **no próprio item** (editar, ativar/desativar, excluir) + criação.
/// Paridade com `ManageRewardsPage.tsx` (gated `reward:view`).
class ManageRewardsPage extends StatefulWidget {
  const ManageRewardsPage({super.key});

  @override
  State<ManageRewardsPage> createState() => _ManageRewardsPageState();
}

class _ManageRewardsPageState extends State<ManageRewardsPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const double _kSectionGap = 12;

  List<Reward> _rewards = const [];
  bool _loading = true;
  String? _error;

  RewardStats _stats = RewardStats.zero;
  bool _statsLoading = true;

  _ManageTab _activeTab = _ManageTab.active;

  /// Id do prêmio sendo processado (trava as ações do card).
  String? _busyId;

  bool get _canView =>
      ModuleAccessService.instance.hasPermission('reward:view');
  bool get _canCreate =>
      ModuleAccessService.instance.hasPermission('reward:create');
  bool get _canUpdate =>
      ModuleAccessService.instance.hasPermission('reward:update');
  bool get _canDelete =>
      ModuleAccessService.instance.hasPermission('reward:delete');

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Color _accent(BuildContext context) => rewardsAccent(context);

  // ─── Dados ───────────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    await Future.wait([_loadRewards(), _loadStats()]);
  }

  Future<void> _loadRewards() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res =
        await RewardsService.instance.getAllRewards(includeInactive: true);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _rewards = res.data!;
      } else {
        _error = res.message ?? 'Erro ao carregar os prêmios';
      }
    });
  }

  Future<void> _loadStats() async {
    setState(() => _statsLoading = true);
    final res = await RewardsService.instance.getRedemptionStats();
    if (!mounted) return;
    setState(() {
      _statsLoading = false;
      if (res.success && res.data != null) _stats = res.data!;
    });
  }

  // ─── Ações ───────────────────────────────────────────────────────────────

  Future<void> _openCreate() async {
    final changed =
        await Navigator.of(context).pushNamed('/rewards/create');
    if (changed == true && mounted) _loadRewards();
  }

  Future<void> _openEdit(Reward reward) async {
    final changed =
        await Navigator.of(context).pushNamed('/rewards/${reward.id}/edit');
    if (changed == true && mounted) _loadRewards();
  }

  Future<void> _toggleActive(Reward reward) async {
    final confirmed = await _confirmToggle(reward);
    if (confirmed != true || !mounted) return;

    setState(() => _busyId = reward.id);
    final res = await RewardsService.instance.updateReward(
      reward.id,
      {'isActive': !reward.isActive},
    );
    if (!mounted) return;
    setState(() => _busyId = null);

    if (res.success) {
      _snack(
        reward.isActive
            ? 'Prêmio desativado — ele some do catálogo de resgates.'
            : 'Prêmio ativado — já disponível no catálogo!',
        success: true,
      );
      _loadRewards();
    } else {
      _snack(res.message ?? 'Erro ao atualizar o prêmio', success: false);
    }
  }

  Future<void> _delete(Reward reward) async {
    final confirmed = await _confirmDelete(reward);
    if (confirmed != true || !mounted) return;

    setState(() => _busyId = reward.id);
    final res = await RewardsService.instance.deleteReward(reward.id);
    if (!mounted) return;
    setState(() => _busyId = null);

    if (res.success) {
      _snack('Prêmio excluído do catálogo.', success: true);
      _loadRewards();
    } else {
      _snack(res.message ?? 'Erro ao excluir o prêmio', success: false);
    }
  }

  Future<bool?> _confirmToggle(Reward reward) {
    final deactivating = reward.isActive;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone = deactivating
        ? (isDark ? AppColors.status.warningDarkMode : AppColors.status.warning)
        : (isDark ? AppColors.status.greenDarkMode : AppColors.status.green);
    return _confirmDialog(
      title: deactivating ? 'Desativar prêmio' : 'Ativar prêmio',
      body: deactivating
          ? 'Deseja desativar "${reward.name}"? Ele deixa de aparecer no '
              'catálogo, mas resgates já feitos não são afetados.'
          : 'Deseja ativar "${reward.name}"? Ele volta a aparecer no '
              'catálogo de resgates.',
      confirmLabel: deactivating ? 'Desativar' : 'Ativar',
      confirmIcon: deactivating ? LucideIcons.eyeOff : LucideIcons.eye,
      tone: tone,
    );
  }

  Future<bool?> _confirmDelete(Reward reward) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    return _confirmDialog(
      title: 'Excluir prêmio',
      body: 'Tem certeza que deseja excluir "${reward.name}"? '
          'Esta ação não pode ser desfeita.',
      confirmLabel: 'Excluir',
      confirmIcon: LucideIcons.trash2,
      tone: danger,
    );
  }

  Future<bool?> _confirmDialog({
    required String title,
    required String body,
    required String confirmLabel,
    required IconData confirmIcon,
    required Color tone,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ThemeHelpers.cardBackgroundColor(ctx),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: ThemeHelpers.textColor(ctx),
            letterSpacing: -0.3,
          ),
        ),
        content: Text(
          body,
          style: TextStyle(
            color: ThemeHelpers.textSecondaryColor(ctx),
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: ThemeHelpers.textSecondaryColor(ctx),
            ),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: tone,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: Icon(confirmIcon, size: 16),
            label: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  void _snack(String message, {required bool success}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: success
            ? (isDark ? AppColors.status.greenDarkMode : AppColors.status.green)
            : (isDark ? AppColors.status.errorDarkMode : AppColors.status.error),
      ),
    );
  }

  // ─── Abas ────────────────────────────────────────────────────────────────

  List<Reward> _itemsOf(_ManageTab tab) {
    switch (tab) {
      case _ManageTab.active:
        return _rewards.where((r) => r.isActive).toList();
      case _ManageTab.inactive:
        return _rewards.where((r) => !r.isActive).toList();
      case _ManageTab.all:
        return _rewards;
    }
  }

  int _countOf(_ManageTab tab) => _itemsOf(tab).length;

  Color _tabColor(BuildContext context, _ManageTab tab) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (tab) {
      case _ManageTab.active:
        return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
      case _ManageTab.inactive:
        return ThemeHelpers.textSecondaryColor(context);
      case _ManageTab.all:
        return _accent(context);
    }
  }

  String _tabLabel(_ManageTab tab) {
    switch (tab) {
      case _ManageTab.active:
        return 'Ativos';
      case _ManageTab.inactive:
        return 'Inativos';
      case _ManageTab.all:
        return 'Todos';
    }
  }

  IconData _tabIcon(_ManageTab tab) {
    switch (tab) {
      case _ManageTab.active:
        return LucideIcons.circleCheck;
      case _ManageTab.inactive:
        return LucideIcons.circleOff;
      case _ManageTab.all:
        return LucideIcons.gift;
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canView) {
      return const AppScaffold(
        title: 'Configurar Resgates',
        showBottomNavigation: false,
        body: RewardsDeniedView(
          message: 'Você não tem acesso à configuração de resgates.',
          permission: 'reward:view',
        ),
      );
    }
    return AppScaffold(
      title: 'Configurar Resgates',
      showBottomNavigation: false,
      body: RefreshIndicator(
        color: _accent(context),
        onRefresh: _loadAll,
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

    final activeCount = _countOf(_ManageTab.active);
    final subtitle = _loading && _rewards.isEmpty
        ? 'Carregando o catálogo da empresa…'
        : _stats.pending > 0
            ? '${_stats.pending} solicitaç${_stats.pending == 1 ? 'ão' : 'ões'} '
                'de resgate aguardando aprovação.'
            : 'Monte o catálogo e acompanhe os resgates da equipe.';

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
                'CONFIGURAR RESGATES',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.2,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              // Atalho para a fila de aprovação.
              if (ModuleAccessService.instance
                  .hasPermission('reward:approve'))
                InkResponse(
                  radius: 22,
                  onTap: () =>
                      Navigator.of(context).pushNamed('/rewards/approve'),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.listChecks, size: 14, color: accent),
                      const SizedBox(width: 5),
                      Text(
                        'Aprovar',
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
                _loading && _rewards.isEmpty ? '—' : '$activeCount',
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
                  activeCount == 1
                      ? 'prêmio no catálogo'
                      : 'prêmios no catálogo',
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
          _buildKpiStrip(context, amber, emerald, accent),
          if (_canCreate) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton.icon(
                onPressed: _openCreate,
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    letterSpacing: -0.1,
                  ),
                ),
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('Criar novo prêmio'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKpiStrip(
      BuildContext context, Color amber, Color emerald, Color accent) {
    final divider = ThemeHelpers.borderColor(context).withValues(alpha: 0.45);
    final blocks = <Widget>[
      _heroKpiBlock(context, LucideIcons.hourglass, 'PENDENTES',
          _statsLoading ? '—' : '${_stats.pending}', 'para aprovar', amber),
      _heroKpiBlock(context, LucideIcons.circleCheck, 'APROVADOS',
          _statsLoading ? '—' : '${_stats.approved}', 'resgates', emerald),
      _heroKpiBlock(
          context,
          LucideIcons.sparkles,
          'PONTOS',
          _statsLoading
              ? '—'
              : rewardsPointsFormat.format(_stats.totalPointsSpent),
          'já resgatados',
          accent),
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

  // ─── Abas flush (sublinhado) ─────────────────────────────────────────────

  Widget _buildTabsRail(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _kPagePadH - 8),
        child: Row(
          children: [
            for (final tab in _ManageTab.values)
              Expanded(
                child: RewardsFlushTab(
                  icon: _tabIcon(tab),
                  label: _tabLabel(tab),
                  count: _countOf(tab),
                  tone: _tabColor(context, tab),
                  selected: _activeTab == tab,
                  onTap: () => setState(() => _activeTab = tab),
                ),
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
    if (_loading && _rewards.isEmpty) {
      child = _buildSkeleton();
    } else if (_error != null && _rewards.isEmpty) {
      child = RewardsErrorState(message: _error!, onRetry: _loadRewards);
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
      _ManageTab.active => (
          eyebrow: 'NO CATÁLOGO',
          title: 'Prêmios ativos',
          hint: 'Visíveis para a equipe no catálogo de resgates.',
        ),
      _ManageTab.inactive => (
          eyebrow: 'FORA DO CATÁLOGO',
          title: 'Prêmios inativos',
          hint: 'Ocultos do catálogo — reative quando quiser oferecê-los '
              'novamente.',
        ),
      _ManageTab.all => (
          eyebrow: 'TUDO',
          title: 'Todos os prêmios',
          hint: 'Catálogo completo da empresa, ativos e inativos.',
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

  Widget _buildList(BuildContext context, List<Reward> items) {
    final nodes = <Widget>[];
    var animIndex = 0;
    for (final reward in items) {
      nodes.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ManageRewardCard(
            reward: reward,
            busy: _busyId == reward.id,
            onEdit: _canUpdate && _busyId == null
                ? () => _openEdit(reward)
                : null,
            onToggleActive: _canUpdate && _busyId == null
                ? () => _toggleActive(reward)
                : null,
            onDelete: _canDelete && _busyId == null
                ? () => _delete(reward)
                : null,
          ),
        ).animate(key: ValueKey('mr-${reward.id}')).fadeIn(
              delay: Duration(milliseconds: 30 * (animIndex++).clamp(0, 12)),
              duration: 220.ms,
            ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: nodes,
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final tone = _tabColor(context, _activeTab);
    final (icon, title, body) = switch (_activeTab) {
      _ManageTab.active => (
          LucideIcons.gift,
          'Nenhum prêmio ativo',
          'Crie o primeiro prêmio para a equipe começar a resgatar pontos!',
        ),
      _ManageTab.inactive => (
          LucideIcons.circleOff,
          'Nenhum prêmio inativo',
          'Prêmios desativados aparecem aqui e podem ser reativados.',
        ),
      _ManageTab.all => (
          LucideIcons.gift,
          'Catálogo vazio',
          'Nenhum prêmio cadastrado ainda. Crie o primeiro!',
        ),
    };
    final showCreate = _canCreate && _activeTab != _ManageTab.inactive;
    return RewardsEmptyState(
      icon: icon,
      title: title,
      body: body,
      tone: tone,
      actionLabel: showCreate ? 'Criar novo prêmio' : null,
      onAction: showCreate ? _openCreate : null,
    );
  }

  // ─── Skeleton fiel ao card de gestão ─────────────────────────────────────

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
                children: const [
                  SkeletonBox(width: 48, height: 48, borderRadius: 14),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonText(width: double.infinity, height: 15),
                        SizedBox(height: 6),
                        SkeletonText(width: 100, height: 11),
                      ],
                    ),
                  ),
                  SizedBox(width: 10),
                  SkeletonBox(width: 70, height: 24, borderRadius: 999),
                ],
              ),
              const SizedBox(height: 12),
              const SkeletonText(width: 220, height: 12),
              const SizedBox(height: 12),
              Row(
                children: const [
                  Expanded(
                    child: SkeletonBox(
                        width: double.infinity, height: 38, borderRadius: 11),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: SkeletonBox(
                        width: double.infinity, height: 38, borderRadius: 11),
                  ),
                  SizedBox(width: 8),
                  SkeletonBox(width: 38, height: 38, borderRadius: 11),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
