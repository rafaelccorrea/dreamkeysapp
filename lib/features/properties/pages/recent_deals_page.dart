import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/property_service.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/shimmer_image.dart';

/// "Vendidos e locados recentemente" — paridade com `RecentDealsPage.tsx`
/// do web, sobre `GET /properties/recent-deals`.
///
/// O back devolve de propósito um recorte mínimo (código, foto, tipo,
/// finalidade, bairro/cidade, situação e data da conclusão) — sem preço,
/// endereço nem proprietário — e aplica as mesmas regras de visibilidade da
/// carteira. Tocar no card abre a ficha (que tem as próprias permissões).
class RecentDealsPage extends StatefulWidget {
  const RecentDealsPage({super.key});

  @override
  State<RecentDealsPage> createState() => _RecentDealsPageState();
}

enum _DealKind { all, sold, rented }

extension on _DealKind {
  String get apiValue => switch (this) {
        _DealKind.all => 'all',
        _DealKind.sold => 'sold',
        _DealKind.rented => 'rented',
      };

  String get label => switch (this) {
        _DealKind.all => 'Todos',
        _DealKind.sold => 'Vendidos',
        _DealKind.rented => 'Locados',
      };
}

class _RecentDealsPageState extends State<RecentDealsPage> {
  static const int _pageSize = 24;

  final ScrollController _scroll = ScrollController();
  _DealKind _kind = _DealKind.all;
  bool _onlyMine = false;

  final List<RecentDeal> _items = [];
  int _page = 1;
  int _totalPages = 1;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _errorStatus = 0;
  Object? _errorDetail;
  int _ticket = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 240 &&
        !_loadingMore &&
        !_loading &&
        _page < _totalPages) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    final ticket = ++_ticket;
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await PropertyService.instance.getRecentDeals(
      page: 1,
      limit: _pageSize,
      kind: _kind.apiValue,
      onlyMyData: _onlyMine,
    );
    if (!mounted || ticket != _ticket) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _items
          ..clear()
          ..addAll(res.data!.items);
        _page = res.data!.page;
        _totalPages = res.data!.totalPages;
        _total = res.data!.total;
      } else {
        _error = res.message ?? 'Erro ao carregar os negócios recentes';
        _errorStatus = res.statusCode;
        _errorDetail = res.error;
      }
    });
  }

  Future<void> _loadMore() async {
    final ticket = _ticket;
    setState(() => _loadingMore = true);
    final res = await PropertyService.instance.getRecentDeals(
      page: _page + 1,
      limit: _pageSize,
      kind: _kind.apiValue,
      onlyMyData: _onlyMine,
    );
    if (!mounted || ticket != _ticket) return;
    setState(() {
      _loadingMore = false;
      if (res.success && res.data != null) {
        _items.addAll(res.data!.items);
        _page = res.data!.page;
        _totalPages = res.data!.totalPages;
      }
    });
  }

  void _setKind(_DealKind kind) {
    if (kind == _kind) return;
    setState(() => _kind = kind);
    _load();
  }

  void _toggleMine() {
    setState(() => _onlyMine = !_onlyMine);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Vendidos e locados',
      showBottomNavigation: false,
      actions: [
        IconButton(
          tooltip: 'Atualizar',
          onPressed: _loading ? null : _load,
          icon: const Icon(LucideIcons.refreshCw, size: 20),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _header(context)),
            ..._content(context),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final accent = AppColors.primary.primary;
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'NEGÓCIOS FECHADOS',
            style: theme.textTheme.labelSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
              fontSize: 10.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _loading
                ? 'Carregando…'
                : (_total == 1
                    ? '1 imóvel concluído'
                    : '${NumberFormat.decimalPattern('pt_BR').format(_total)} '
                        'imóveis concluídos'),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Mais recentes primeiro, pela data da venda ou da locação.',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final k in _DealKind.values)
                ChoiceChip(
                  label: Text(k.label),
                  selected: _kind == k,
                  onSelected: (_) => _setKind(k),
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _kind == k ? accent : ThemeHelpers.textColor(context),
                  ),
                  selectedColor: accent.withValues(alpha: isDark ? 0.22 : 0.12),
                  side: BorderSide(
                    color: _kind == k
                        ? accent.withValues(alpha: 0.5)
                        : ThemeHelpers.borderColor(context),
                  ),
                ),
              FilterChip(
                label: const Text('Só os meus'),
                avatar: Icon(
                  _onlyMine ? LucideIcons.userCheck : LucideIcons.user,
                  size: 15,
                  color: _onlyMine ? accent : muted,
                ),
                selected: _onlyMine,
                onSelected: (_) => _toggleMine(),
                showCheckmark: false,
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _onlyMine ? accent : ThemeHelpers.textColor(context),
                ),
                selectedColor: accent.withValues(alpha: isDark ? 0.22 : 0.12),
                side: BorderSide(
                  color: _onlyMine
                      ? accent.withValues(alpha: 0.5)
                      : ThemeHelpers.borderColor(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _content(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_error != null && _items.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: AppErrorState.fromApi(
            message: _error,
            statusCode: _errorStatus,
            error: _errorDetail,
            onRetry: _load,
          ),
        ),
      ];
    }
    if (_items.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _EmptyDeals(kind: _kind),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        sliver: SliverList.separated(
          itemCount: _items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) => _DealCard(
            deal: _items[i],
            onTap: () => Navigator.of(context)
                .pushNamed(AppRoutes.propertyDetails(_items[i].id)),
          ),
        ),
      ),
      if (_loadingMore)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
    ];
  }
}

class _DealCard extends StatelessWidget {
  const _DealCard({required this.deal, required this.onTap});

  final RecentDeal deal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final sold = deal.isSold;
    final tone = sold
        ? (isDark ? AppColors.status.errorDarkMode : AppColors.status.error)
        : (isDark ? AppColors.status.successDarkMode : AppColors.status.success);
    final date = deal.concludedAt ?? (sold ? deal.soldAt : deal.rentedAt);
    final dateLabel =
        date == null ? null : DateFormat('dd/MM/yyyy', 'pt_BR').format(date);
    final place = [deal.neighborhood, deal.city]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' · ');
    final typeLabel =
        deal.type == null ? null : PropertyType.labelOf(deal.type!);
    final specs = [
      if (typeLabel != null && typeLabel.isNotEmpty) typeLabel,
      if ((deal.bedrooms ?? 0) > 0)
        '${deal.bedrooms} quarto${deal.bedrooms == 1 ? '' : 's'}',
      if ((deal.totalArea ?? 0) > 0)
        '${NumberFormat.decimalPattern('pt_BR').format(deal.totalArea)} m²',
    ].join(' · ');

    return Material(
      color: ThemeHelpers.cardBackgroundColor(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 76,
                  height: 76,
                  child: (deal.imageUrl ?? '').isEmpty
                      ? Container(
                          color: tone.withValues(alpha: isDark ? 0.16 : 0.10),
                          child: Icon(LucideIcons.house, color: tone, size: 26),
                        )
                      : ShimmerImage(imageUrl: deal.imageUrl!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: tone.withValues(alpha: isDark ? 0.2 : 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            sold ? 'VENDIDO' : 'LOCADO',
                            style: TextStyle(
                              color: tone,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                        if (dateLabel != null) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'em $dateLabel',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: muted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      (deal.code ?? '').isNotEmpty
                          ? 'Imóvel ${deal.code}'
                          : 'Imóvel sem código',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                    if (place.isNotEmpty)
                      Text(
                        place,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    if (specs.isNotEmpty)
                      Text(
                        specs,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronRight, size: 18, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyDeals extends StatelessWidget {
  const _EmptyDeals({required this.kind});

  final _DealKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final what = switch (kind) {
      _DealKind.all => 'Nenhuma venda ou locação concluída',
      _DealKind.sold => 'Nenhuma venda concluída',
      _DealKind.rented => 'Nenhuma locação concluída',
    };
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.handshake, size: 40, color: muted),
          const SizedBox(height: 12),
          Text(
            what,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Quando um imóvel for marcado como vendido ou alugado, ele aparece '
            'aqui.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}
