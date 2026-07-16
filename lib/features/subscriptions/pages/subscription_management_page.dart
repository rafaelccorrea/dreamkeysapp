import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/subscription_models.dart';
import '../services/subscriptions_service.dart';
import '../widgets/admin_subscription_card.dart';
import '../widgets/subscription_filters_sheet.dart';
import '../widgets/subscription_widgets.dart';

final NumberFormat _compact = NumberFormat.compactCurrency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 1,
);

/// Abas por status — espelha os filtros de status do
/// `SubscriptionManagementPage` do web. `null` = todas.
enum _StatusTab {
  all(null, 'Todas', LucideIcons.layers),
  active('active', 'Ativas', LucideIcons.circleCheck),
  suspended('suspended', 'Suspensas', LucideIcons.pause),
  expired('expired', 'Expiradas', LucideIcons.clock),
  cancelled('cancelled', 'Canceladas', LucideIcons.ban);

  const _StatusTab(this.status, this.label, this.icon);
  final String? status;
  final String label;
  final IconData icon;
}

/// **Gerenciar assinaturas** (`/subscription/manage`) — visão master da
/// carteira de assinaturas do sistema (paridade com `/subscription-management`
/// + endpoint `GET /subscriptions/admin/all-subscriptions`).
class SubscriptionManagementPage extends StatefulWidget {
  const SubscriptionManagementPage({super.key});

  @override
  State<SubscriptionManagementPage> createState() =>
      _SubscriptionManagementPageState();
}

class _SubscriptionManagementPageState
    extends State<SubscriptionManagementPage> {
  static const double _kPadH = 16;
  static const double _kGap = 12;
  static const int _pageSize = 20;

  _StatusTab _tab = _StatusTab.all;
  AdminSubscriptionFilters _filters =
      const AdminSubscriptionFilters(limit: _pageSize);

  AdminSubscriptionsResult _result = AdminSubscriptionsResult.empty;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _appliedSearch = '';
  bool _searchFocused = false;

  /// Gate por papel — o detalhe e as ações são MasterRoute no web; a gestão
  /// no app é restrita a master.
  bool get _isMaster =>
      ModuleAccessService.instance.userRole?.toLowerCase().trim() == 'master';

  @override
  void initState() {
    super.initState();
    if (_isMaster) _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Color _accent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.primary.primaryDarkMode
          : AppColors.primary.primary;

  Color _tabTone(BuildContext context, _StatusTab tab) {
    if (tab == _StatusTab.all) return _accent(context);
    return subscriptionStatusColor(context, tab.status!);
  }

  int? _tabCount(_StatusTab tab) {
    final s = _result.summary;
    switch (tab) {
      case _StatusTab.all:
        return s.totalSubscriptions;
      case _StatusTab.active:
        return s.activeSubscriptions;
      case _StatusTab.expired:
        return s.expiredSubscriptions;
      case _StatusTab.cancelled:
        return s.cancelledSubscriptions;
      case _StatusTab.suspended:
        return null; // o summary do backend não expõe contagem de suspensas
    }
  }

  // ─── Dados ────────────────────────────────────────────────────────────────

  AdminSubscriptionFilters _effectiveFilters(int page) {
    final search = _appliedSearch.trim();
    return AdminSubscriptionFilters(
      companyName: search.isNotEmpty ? search : _filters.companyName,
      companyCnpj: _filters.companyCnpj,
      userName: _filters.userName,
      userEmail: _filters.userEmail,
      status: _tab.status,
      planType: _filters.planType,
      page: page,
      limit: _pageSize,
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await SubscriptionsService.instance
        .getAllSubscriptions(filters: _effectiveFilters(1));
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _result = res.data!;
        _error = null;
      } else {
        _error = res.message ?? 'Erro ao carregar assinaturas';
      }
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _result.page >= _result.totalPages) return;
    setState(() => _loadingMore = true);
    final res = await SubscriptionsService.instance
        .getAllSubscriptions(filters: _effectiveFilters(_result.page + 1));
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (res.success && res.data != null) {
        _result = AdminSubscriptionsResult(
          items: [..._result.items, ...res.data!.items],
          total: res.data!.total,
          page: res.data!.page,
          totalPages: res.data!.totalPages,
          summary: res.data!.summary,
        );
      }
    });
  }

  void _selectTab(_StatusTab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    _load();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final v = value.trim();
      if (v == _appliedSearch) return;
      setState(() => _appliedSearch = v);
      _load();
    });
  }

  void _openFilters() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => SubscriptionFiltersSheet(
        initialFilters: _filters,
        onApply: (f) {
          setState(() => _filters = f);
          _load();
        },
        onClear: () {
          setState(
              () => _filters = const AdminSubscriptionFilters(limit: _pageSize));
          _load();
        },
      ),
    );
  }

  Future<void> _openDetails(AdminSubscriptionItem item) async {
    await Navigator.of(context).pushNamed(
      '/subscription/manage/${item.id}',
      arguments: item,
    );
    // O detalhe permite estender/suspender/cancelar — recarrega ao voltar.
    if (mounted) _load();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_isMaster) {
      return const AppScaffold(
        title: 'Gerenciar Assinaturas',
        showBottomNavigation: false,
        body: SubsDeniedView(
          message: 'A gestão de assinaturas é exclusiva do perfil master.',
        ),
      );
    }

    return AppScaffold(
      title: 'Gerenciar Assinaturas',
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
                    padding: const EdgeInsets.fromLTRB(_kPadH, 10, _kPadH, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHero(context),
                        const SizedBox(height: _kGap),
                        _buildSearchRow(context),
                        const SizedBox(height: _kGap),
                      ],
                    ),
                  ),
                  _buildTabsRail(context),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        _kPadH, _kGap, _kPadH, 88),
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

  // ─── Hero ─────────────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accent(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final blue = isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;

    final s = _result.summary;
    final total = s.totalSubscriptions;
    final subtitle = _loading
        ? 'Carregando a carteira de assinaturas…'
        : total == 0
            ? 'Nenhuma assinatura encontrada com os critérios atuais.'
            : '${s.activeSubscriptions} ativa${s.activeSubscriptions == 1 ? '' : 's'} · '
                '${_compact.format(s.totalRevenue)} de receita mensal';

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
                'GESTÃO MASTER',
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
                _loading ? '—' : '$total',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  height: 1.0,
                  letterSpacing: -1.0,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  total == 1 ? 'assinatura' : 'assinaturas',
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
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _kpiBlock(
                    context,
                    LucideIcons.circleCheck,
                    'ATIVAS',
                    _loading ? '—' : '${s.activeSubscriptions}',
                    'gerando receita',
                    emerald,
                  ),
                ),
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: ThemeHelpers.borderColor(context)
                      .withValues(alpha: 0.45),
                ),
                Expanded(
                  child: _kpiBlock(
                    context,
                    LucideIcons.banknote,
                    'RECEITA/MÊS',
                    _loading ? '—' : _compact.format(s.totalRevenue),
                    'somando ativas',
                    accent,
                  ),
                ),
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: ThemeHelpers.borderColor(context)
                      .withValues(alpha: 0.45),
                ),
                Expanded(
                  child: _kpiBlock(
                    context,
                    LucideIcons.building2,
                    'EMPRESAS',
                    _loading ? '—' : '${s.totalCompanies}',
                    'na carteira',
                    blue,
                  ),
                ),
              ],
            ),
          ),
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

  // ─── Busca + filtros ──────────────────────────────────────────────────────

  Widget _buildSearchRow(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accent(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final cardColor = ThemeHelpers.cardBackgroundColor(context);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final hasText = _searchController.text.isNotEmpty;
    final showAccent = _searchFocused || hasText;
    final filterCount = _filters.activeCount;

    return Row(
      children: [
        Expanded(
          child: Focus(
            onFocusChange: (f) => setState(() => _searchFocused = f),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              height: 50,
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: showAccent
                      ? accent.withValues(alpha: isDark ? 0.5 : 0.42)
                      : borderColor,
                  width: showAccent ? 1.4 : 1,
                ),
                boxShadow: showAccent
                    ? [
                        BoxShadow(
                          color:
                              accent.withValues(alpha: isDark ? 0.18 : 0.12),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                          spreadRadius: -4,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  Icon(LucideIcons.search,
                      size: 18, color: showAccent ? accent : secondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      cursorColor: accent,
                      style: TextStyle(
                        color: ThemeHelpers.textColor(context),
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Buscar por empresa…',
                        hintStyle: TextStyle(
                          color: secondary.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w500,
                          fontSize: 13.5,
                        ),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                      onChanged: (v) {
                        _onSearchChanged(v);
                        setState(() {});
                      },
                    ),
                  ),
                  if (hasText)
                    InkResponse(
                      radius: 18,
                      onTap: () {
                        _searchController.clear();
                        _onSearchChanged('');
                        setState(() {});
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(LucideIcons.x, size: 15, color: secondary),
                      ),
                    ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Botão de filtros — badge com contagem de filtros "de gaveta".
        InkWell(
          onTap: _openFilters,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: filterCount > 0
                  ? accent.withValues(alpha: isDark ? 0.18 : 0.1)
                  : cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: filterCount > 0
                    ? accent.withValues(alpha: 0.5)
                    : borderColor,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  LucideIcons.slidersHorizontal,
                  size: 19,
                  color: filterCount > 0 ? accent : secondary,
                ),
                if (filterCount > 0)
                  Positioned(
                    top: 9,
                    right: 9,
                    child: Container(
                      width: 15,
                      height: 15,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: ThemeHelpers.cardBackgroundColor(context),
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '$filterCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── Abas flush (roláveis — 5 status) ─────────────────────────────────────

  Widget _buildTabsRail(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: _kPadH - 8),
        child: Row(
          children: [
            for (final tab in _StatusTab.values)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: SubsFlushTab(
                  icon: tab.icon,
                  label: tab.label,
                  count: _tabCount(tab),
                  tone: _tabTone(context, tab),
                  selected: _tab == tab,
                  onTap: () => _selectTab(tab),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Painel ativo ─────────────────────────────────────────────────────────

  Widget _buildActivePanel(BuildContext context) {
    final tone = _tabTone(context, _tab);
    Widget child;
    if (_loading && _result.items.isEmpty) {
      child = _buildSkeleton();
    } else if (_error != null && _result.items.isEmpty) {
      child = SubsErrorState(message: _error!, onRetry: _load);
    } else if (_result.items.isEmpty) {
      child = _buildEmpty(context, tone);
    } else {
      child = _buildList(context);
    }

    return Column(
      key: ValueKey('panel-${_tab.name}-$_appliedSearch'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SubsPanelHeader(
          icon: _tab.icon,
          eyebrow: _tab.label.toUpperCase(),
          title: switch (_tab) {
            _StatusTab.all => 'Carteira completa',
            _StatusTab.active => 'Assinaturas ativas',
            _StatusTab.suspended => 'Assinaturas suspensas',
            _StatusTab.expired => 'Assinaturas expiradas',
            _StatusTab.cancelled => 'Assinaturas canceladas',
          },
          hint: switch (_tab) {
            _StatusTab.all =>
              'Todas as assinaturas do sistema, com uso e cobrança.',
            _StatusTab.active => 'Contas em dia — a receita recorrente vem daqui.',
            _StatusTab.suspended =>
              'Acesso pausado — reative pelo detalhe da assinatura.',
            _StatusTab.expired => 'Vigência encerrada — estenda ou renegocie.',
            _StatusTab.cancelled => 'Contas encerradas em definitivo.',
          },
          tone: tone,
        ),
        const SizedBox(height: 14),
        child,
      ],
    ).animate(key: ValueKey('panel-${_tab.name}')).fadeIn(duration: 240.ms);
  }

  Widget _buildList(BuildContext context) {
    final accent = _accent(context);
    var animIndex = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in _result.items)
          AdminSubscriptionCard(
            item: item,
            onTap: () => _openDetails(item),
          ).animate(key: ValueKey('sub-${item.id}')).fadeIn(
                delay: Duration(milliseconds: 30 * (animIndex++).clamp(0, 12)),
                duration: 220.ms,
              ),
        if (_result.page < _result.totalPages)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: _loadingMore
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: accent),
                    )
                  : OutlinedButton.icon(
                      onPressed: _loadMore,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: accent,
                        side:
                            BorderSide(color: accent.withValues(alpha: 0.45)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(LucideIcons.chevronDown, size: 16),
                      label: const Text('Carregar mais'),
                    ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context, Color tone) {
    final hasSearch = _appliedSearch.trim().isNotEmpty;
    final hasFilters = _filters.activeCount > 0;
    return SubsEmptyState(
      icon: hasSearch || hasFilters
          ? LucideIcons.searchX
          : LucideIcons.packageOpen,
      title: hasSearch || hasFilters
          ? 'Nada encontrado'
          : 'Nenhuma assinatura aqui',
      body: hasSearch
          ? 'Nenhuma assinatura corresponde a "${_appliedSearch.trim()}".'
          : hasFilters
              ? 'Nenhuma assinatura corresponde aos filtros aplicados.'
              : 'Quando houver assinaturas neste status, elas aparecem aqui.',
      tone: tone,
    );
  }

  Widget _buildSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(
        5,
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ThemeHelpers.cardBackgroundColor(context),
              borderRadius: BorderRadius.circular(16),
              boxShadow: ThemeHelpers.cardShadow(context),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonBox(width: 42, height: 42, borderRadius: 13),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      SkeletonText(width: 130, height: 15, borderRadius: 999),
                      SizedBox(height: 8),
                      SkeletonText(width: double.infinity, height: 12),
                      SizedBox(height: 8),
                      SkeletonText(width: 140, height: 11),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
