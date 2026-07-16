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
import '../widgets/pending_redemption_card.dart';
import '../widgets/review_redemption_sheet.dart';
import '../widgets/rewards_ui.dart';

/// Aba da tela Aprovar Resgates — paridade com o filtro do web
/// (`pending` / `approved` / `all`).
enum _ApproveTab { pending, approved, all }

/// Tela **Aprovar Resgates** (`/rewards/approve`) — fila de solicitações da
/// empresa com **Aprovar / Rejeitar no próprio item** e, para quem tem
/// `reward:deliver`, a entrega dos aprovados. Paridade com
/// `ApproveRedemptionsPage.tsx` (gated `reward:approve`).
class ApproveRedemptionsPage extends StatefulWidget {
  const ApproveRedemptionsPage({super.key});

  @override
  State<ApproveRedemptionsPage> createState() => _ApproveRedemptionsPageState();
}

class _ApproveRedemptionsPageState extends State<ApproveRedemptionsPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const double _kSectionGap = 12;

  List<RewardRedemption> _redemptions = const [];
  bool _loading = true;
  String? _error;
  _ApproveTab _activeTab = _ApproveTab.pending;

  /// Id da solicitação sendo processada (trava as ações do card).
  String? _busyId;

  bool get _canApprove =>
      ModuleAccessService.instance.hasPermission('reward:approve');
  bool get _canDeliver =>
      ModuleAccessService.instance.hasPermission('reward:deliver');

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
    // Sem status → todas as solicitações da empresa (contagens das abas).
    final res = await RewardsService.instance.getPendingRedemptions();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _redemptions = res.data!.redemptions;
      } else {
        _error = res.message ?? 'Erro ao carregar as solicitações';
      }
    });
  }

  Future<void> _review(RewardRedemption redemption,
      {required bool approve}) async {
    final notes = await showReviewRedemptionSheet(
      context,
      redemption: redemption,
      approve: approve,
    );
    if (notes == null || !mounted) return;

    setState(() => _busyId = redemption.id);
    final res = await RewardsService.instance.reviewRedemption(
      id: redemption.id,
      approve: approve,
      reviewNotes: notes,
    );
    if (!mounted) return;
    setState(() => _busyId = null);

    if (res.success) {
      _snack(
        approve
            ? 'Resgate aprovado! Os pontos foram debitados do colaborador.'
            : 'Resgate rejeitado. Nenhum ponto foi debitado.',
        success: true,
      );
      _load();
    } else {
      _snack(res.message ?? 'Erro ao processar a solicitação', success: false);
    }
  }

  Future<void> _deliver(RewardRedemption redemption) async {
    final confirmed = await _confirmDeliver(redemption);
    if (confirmed != true || !mounted) return;

    setState(() => _busyId = redemption.id);
    final res =
        await RewardsService.instance.deliverRedemption(id: redemption.id);
    if (!mounted) return;
    setState(() => _busyId = null);

    if (res.success) {
      _snack('Prêmio marcado como entregue!', success: true);
      _load();
    } else {
      _snack(res.message ?? 'Erro ao marcar como entregue', success: false);
    }
  }

  Future<bool?> _confirmDeliver(RewardRedemption redemption) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final blue = isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    final userName = (redemption.userName ?? '').trim().isNotEmpty
        ? redemption.userName!.trim()
        : 'o colaborador';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ThemeHelpers.cardBackgroundColor(ctx),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Confirmar entrega',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: ThemeHelpers.textColor(ctx),
            letterSpacing: -0.3,
          ),
        ),
        content: Text(
          'Marcar "${redemption.rewardName}" como entregue para $userName?',
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
              backgroundColor: blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(LucideIcons.packageCheck, size: 16),
            label: const Text('Entregar'),
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

  RedemptionStatus? _statusOf(_ApproveTab tab) {
    switch (tab) {
      case _ApproveTab.pending:
        return RedemptionStatus.pending;
      case _ApproveTab.approved:
        return RedemptionStatus.approved;
      case _ApproveTab.all:
        return null;
    }
  }

  List<RewardRedemption> _itemsOf(_ApproveTab tab) {
    final status = _statusOf(tab);
    if (status == null) return _redemptions;
    return _redemptions.where((r) => r.status == status).toList();
  }

  int _countOf(_ApproveTab tab) => _itemsOf(tab).length;

  Color _tabColor(BuildContext context, _ApproveTab tab) {
    final status = _statusOf(tab);
    if (status == null) return _accent(context);
    return redemptionStatusColor(context, status);
  }

  String _tabLabel(_ApproveTab tab) {
    switch (tab) {
      case _ApproveTab.pending:
        return 'Pendentes';
      case _ApproveTab.approved:
        return 'Aprovados';
      case _ApproveTab.all:
        return 'Todos';
    }
  }

  IconData _tabIcon(_ApproveTab tab) {
    final status = _statusOf(tab);
    if (status == null) return LucideIcons.listChecks;
    return redemptionStatusIcon(status);
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canApprove) {
      return const AppScaffold(
        title: 'Aprovar Resgates',
        showBottomNavigation: false,
        body: RewardsDeniedView(
          message: 'Você não tem acesso à aprovação de resgates.',
          permission: 'reward:approve',
        ),
      );
    }
    return AppScaffold(
      title: 'Aprovar Resgates',
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

    final pending = _countOf(_ApproveTab.pending);
    final dot = pending > 0 ? amber : emerald;
    final subtitle = _loading && _redemptions.isEmpty
        ? 'Carregando as solicitações da equipe…'
        : pending > 0
            ? '$pending solicitaç${pending == 1 ? 'ão aguarda' : 'ões aguardam'} '
                'sua análise — os pontos só são debitados na aprovação.'
            : 'Tudo em dia! Nenhuma solicitação aguardando análise.';

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
                'APROVAR RESGATES',
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
                _loading && _redemptions.isEmpty ? '—' : '$pending',
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
                  pending == 1 ? 'pendente' : 'pendentes',
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
        ],
      ),
    );
  }

  Widget _buildKpiStrip(
      BuildContext context, Color amber, Color emerald, Color accent) {
    final divider = ThemeHelpers.borderColor(context).withValues(alpha: 0.45);
    final pending = _countOf(_ApproveTab.pending);
    final approved = _countOf(_ApproveTab.approved);
    final pointsPending = _itemsOf(_ApproveTab.pending)
        .fold<int>(0, (sum, r) => sum + r.pointsSpent);
    final blocks = <Widget>[
      _heroKpiBlock(context, LucideIcons.hourglass, 'PENDENTES',
          _loading ? '—' : '$pending', 'para analisar', amber),
      _heroKpiBlock(context, LucideIcons.circleCheck, 'APROVADOS',
          _loading ? '—' : '$approved', 'a entregar', emerald),
      _heroKpiBlock(
          context,
          LucideIcons.sparkles,
          'PONTOS',
          _loading ? '—' : rewardsPointsFormat.format(pointsPending),
          'em análise',
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
            for (final tab in _ApproveTab.values)
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
      _ApproveTab.pending => (
          eyebrow: 'FILA DE ANÁLISE',
          title: 'Aguardando sua decisão',
          hint: 'Aprove para debitar os pontos do colaborador ou rejeite '
              'sem custo algum.',
        ),
      _ApproveTab.approved => (
          eyebrow: 'APROVADOS',
          title: 'Prontos para entrega',
          hint: _canDeliver
              ? 'Combine a entrega e marque como entregue quando concluir.'
              : 'Aprovados — aguardando a entrega do prêmio.',
        ),
      _ApproveTab.all => (
          eyebrow: 'HISTÓRICO',
          title: 'Todas as solicitações',
          hint: 'Histórico completo de resgates da equipe, do mais recente '
              'ao mais antigo.',
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
      nodes.add(const SizedBox(height: 10));
      for (final r in group.items) {
        nodes.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PendingRedemptionCard(
              redemption: r,
              busy: _busyId == r.id,
              onApprove: _busyId == null
                  ? () => _review(r, approve: true)
                  : null,
              onReject: _busyId == null
                  ? () => _review(r, approve: false)
                  : null,
              onDeliver: _canDeliver && _busyId == null && r.canDeliver
                  ? () => _deliver(r)
                  : null,
            ),
          ).animate(key: ValueKey('pr-${r.id}')).fadeIn(
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
    final (icon, title, body) = switch (_activeTab) {
      _ApproveTab.pending => (
          LucideIcons.partyPopper,
          'Tudo em dia!',
          'Não há solicitações pendentes de aprovação. '
              'Novas solicitações aparecem aqui.',
        ),
      _ApproveTab.approved => (
          LucideIcons.circleCheck,
          'Nenhum aprovado',
          'As solicitações aprovadas aguardando entrega aparecem aqui.',
        ),
      _ApproveTab.all => (
          LucideIcons.inbox,
          'Nenhuma solicitação',
          'Quando a equipe solicitar resgates, eles aparecem aqui.',
        ),
    };
    return RewardsEmptyState(icon: icon, title: title, body: body, tone: tone);
  }

  // ─── Skeleton fiel ao card de solicitação ────────────────────────────────

  Widget _buildSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(
        3,
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
                  SkeletonBox(width: 40, height: 40, borderRadius: 999),
                  SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonText(width: 130, height: 15),
                        SizedBox(height: 6),
                        SkeletonText(width: 180, height: 11),
                      ],
                    ),
                  ),
                  SizedBox(width: 8),
                  SkeletonBox(width: 80, height: 24, borderRadius: 999),
                ],
              ),
              const SizedBox(height: 12),
              const SkeletonBox(
                  width: double.infinity, height: 76, borderRadius: 14),
              const SizedBox(height: 12),
              Row(
                children: const [
                  Expanded(
                    child:
                        SkeletonBox(width: double.infinity, height: 40, borderRadius: 12),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child:
                        SkeletonBox(width: double.infinity, height: 40, borderRadius: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
