import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/purchase_proposals_service.dart';
import '../../../core/routes/app_routes.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../sale_forms/widgets/fichas_filters_kit.dart';
import '../widgets/proposal_card.dart';
import '../widgets/proposal_row_actions.dart';
import '../widgets/proposal_signatures_sheet.dart';
import '../widgets/proposals_filters_sheet.dart';
import 'proposals_dashboard_page.dart';
import 'create_proposal_page.dart';

const double _kPadH = 16;
const double _kFabBottom = 96;

/// Coluna de leitura em tela larga (tablet/paisagem).
const double _kMaxW = 720;

Color _accent(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;
}

/// Listagem de fichas de proposta — espelha `PurchaseProposalsPage.tsx` do
/// imobx-front (mobile view).
///
/// Superfície do dia a dia: a contagem responde "quantas", a frase de
/// recorte responde "quais e em que ordem", os filtros ativos viram
/// etiquetas que se tiram com um toque, e cada card traz a ação da etapa.
class ProposalsPage extends StatefulWidget {
  const ProposalsPage({super.key});

  @override
  State<ProposalsPage> createState() => _ProposalsPageState();
}

class _ProposalsPageState extends State<ProposalsPage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();

  ProposalListResult? _data;
  ProposalStats? _stats;
  ProposalFilters _filters = const ProposalFilters(limit: 20);
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _errorStatus = 0;
  bool _showDeletedOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || _loading) return;
    if (_data == null) return;
    if (_data!.page >= _data!.totalPages) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 280) {
      _loadMore();
    }
  }

  ProposalFilters _withSearchAndDeleted(ProposalFilters base) {
    final s = _search.text.trim();
    return base.copyWith(
      search: s.isEmpty ? null : s,
      listDeletedOnly: _showDeletedOnly ? true : null,
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final f = _withSearchAndDeleted(_filters.copyWith(page: 1));
    final statsFut = PurchaseProposalsService.instance.getStats();
    final res = await PurchaseProposalsService.instance.list(filters: f);
    final statsRes = await statsFut;
    if (!mounted) return;
    setState(() {
      _filters = f;
      _loading = false;
      if (res.success && res.data != null) {
        _data = res.data;
        _error = null;
        _errorStatus = 0;
      } else {
        _error = res.message ?? 'Não foi possível carregar as propostas.';
        _errorStatus = res.statusCode;
      }
      if (statsRes.success && statsRes.data != null) {
        _stats = statsRes.data;
      }
    });
  }

  Future<void> _loadMore() async {
    if (_data == null) return;
    setState(() => _loadingMore = true);
    final next = _filters.copyWith(page: _data!.page + 1);
    final res = await PurchaseProposalsService.instance.list(
      filters: _withSearchAndDeleted(next),
    );
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (res.success && res.data != null) {
        _filters = next;
        _data = ProposalListResult(
          items: [..._data!.items, ...res.data!.items],
          total: res.data!.total,
          page: res.data!.page,
          limit: res.data!.limit,
          totalPages: res.data!.totalPages,
        );
      }
    });
  }

  /// Modal "Filtros" (paridade com o drawer do web). Limpar também desliga
  /// "Apenas excluídas", como o `clearDrawerFilters` do web.
  Future<void> _openFilters(bool canViewAll) async {
    final out = await showProposalsFiltersSheet(
      context,
      initial: _filters,
      canViewAll: canViewAll,
    );
    if (out == null || !mounted) return;
    setState(() {
      _filters = out.filters;
      if (out.cleared) _showDeletedOnly = false;
    });
    _load();
  }

  // ─── Recorte ativo (etiquetas removíveis) ────────────────────────────────

  /// Busca APLICADA (a do último carregamento), não o que está sendo
  /// digitado — a frase de recorte não pode mentir sobre a lista.
  String get _appliedSearch => (_filters.search ?? '').trim();

  bool get _hasAnyFilter =>
      _filters.drawerFilterCount > 0 ||
      _showDeletedOnly ||
      _appliedSearch.isNotEmpty;

  void _patch(ProposalFilters next) {
    setState(() => _filters = next);
    _load();
  }

  void _clearSearch() {
    _search.clear();
    _load();
  }

  /// "Limpar tudo": o mesmo recorte do "Limpar filtros" do modal (que
  /// também desliga "Apenas excluídas") + a busca.
  void _clearAll() {
    _search.clear();
    setState(() {
      _filters = _filters.withoutListFilters();
      _showDeletedOnly = false;
    });
    _load();
  }

  static final DateFormat _dmy = DateFormat('dd/MM/yy');

  String _periodLabel(DateTime? from, DateTime? to) {
    if (from != null && to != null) {
      return 'Criadas de ${_dmy.format(from)} a ${_dmy.format(to)}';
    }
    if (from != null) return 'Criadas desde ${_dmy.format(from)}';
    return 'Criadas até ${_dmy.format(to!)}';
  }

  /// Filtros do modal que não aparecem na grade de status (o status já está
  /// à vista ali) — cada um vira etiqueta com "x".
  List<_ActiveFilter> _activeFilters() {
    final f = _filters;
    final out = <_ActiveFilter>[];
    final q = _appliedSearch;
    if (q.isNotEmpty) {
      out.add(
        _ActiveFilter(
          icon: LucideIcons.search,
          label: '"$q"',
          onRemove: _clearSearch,
        ),
      );
    }
    final etapa = f.etapa;
    if (etapa != null) {
      out.add(
        _ActiveFilter(
          icon: LucideIcons.penLine,
          label: 'Etapa ${etapa.number} · ${etapa.label}',
          onRemove: () => _patch(f.copyWith(etapa: null)),
        ),
      );
    }
    final unit = f.saleUnit?.trim();
    if (unit != null && unit.isNotEmpty) {
      out.add(
        _ActiveFilter(
          icon: LucideIcons.building2,
          label: unit,
          onRemove: () => _patch(f.copyWith(saleUnit: null)),
        ),
      );
    }
    if (f.dateFrom != null || f.dateTo != null) {
      out.add(
        _ActiveFilter(
          icon: LucideIcons.calendarRange,
          label: _periodLabel(f.dateFrom, f.dateTo),
          onRemove: () => _patch(f.copyWith(dateFrom: null, dateTo: null)),
        ),
      );
    }
    if ((f.userId ?? '').isNotEmpty) {
      out.add(
        _ActiveFilter(
          icon: LucideIcons.userRound,
          label: 'Autor escolhido',
          onRemove: () => _patch(f.copyWith(userId: null)),
        ),
      );
    }
    return out;
  }

  String _orderLabel(ProposalFilters f) {
    final desc = f.sortOrder.toUpperCase() != 'ASC';
    switch (f.sortBy) {
      case 'proposalNumber':
        return desc ? 'maior número primeiro' : 'menor número primeiro';
      case 'status':
        return 'ordenadas por status';
      case 'proponentName':
        return desc ? 'comprador de Z a A' : 'comprador de A a Z';
      case 'proposedPrice':
        return desc ? 'maior valor primeiro' : 'menor valor primeiro';
      case 'validityDays':
        return desc ? 'maior validade primeiro' : 'menor validade primeiro';
      case 'creatorName':
        return desc ? 'autor de Z a A' : 'autor de A a Z';
      default:
        return desc ? 'mais recentes primeiro' : 'mais antigas primeiro';
    }
  }

  // ─── Navegação ───────────────────────────────────────────────────────────

  Future<void> _openCreate() async {
    final created = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const CreateProposalPage()));
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Proposta criada com sucesso.')),
      );
      _load();
    }
  }

  Future<void> _openDetail(PurchaseProposal p) async {
    final canUpdate = ModuleAccessService.instance.hasPermission(
      'proposal:update',
    );
    final isOpen =
        p.status == ProposalStatus.processing &&
        p.deletedAt == null &&
        canUpdate;
    if (!isOpen) {
      _openSignatures(p, showHistorico: true);
      return;
    }
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CreateProposalPage(proposalId: p.id)),
    );
    if (updated == true && mounted) {
      _load();
    }
  }

  void _openSignatures(
    PurchaseProposal p, {
    bool showHistorico = false,
    int? etapaOverride,
  }) {
    final etapa = etapaOverride ?? p.etapa.number;
    showProposalSignaturesSheet(
      context,
      proposalId: p.id,
      proposalNumber: p.proposalNumber,
      etapa: etapa,
      initialHistorico: showHistorico,
      defaultSigners: [
        if (p.proponentName != null && p.proponentEmail != null)
          ProposalSignerInput(
            email: p.proponentEmail!,
            name: p.proponentName!,
            phone: p.proponentPhone,
          ),
        if (etapa >= 2 && p.ownerName != null && p.ownerEmail != null)
          ProposalSignerInput(
            email: p.ownerEmail!,
            name: p.ownerName!,
            phone: p.ownerPhone,
          ),
      ],
      onChanged: _load,
    );
  }

  /// Menu da linha (espelho do web). Navegação fica aqui; o resto no
  /// despachante compartilhado.
  Future<void> _onAction(PurchaseProposal p, ProposalRowAction a) async {
    switch (a) {
      case ProposalRowAction.assinaturas:
        _openSignatures(p);
        return;
      case ProposalRowAction.historico:
        _openSignatures(p, showHistorico: true);
        return;
      case ProposalRowAction.editar:
        final updated = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => CreateProposalPage(proposalId: p.id),
          ),
        );
        if (updated == true && mounted) _load();
        return;
      default:
        if (await runProposalRowAction(context, p, a) && mounted) _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ModuleAccessService.instance,
      builder: (context, _) {
        final canView = ModuleAccessService.instance.hasPermission(
          'proposal:view',
        );
        if (!canView) {
          return const AppScaffold(
            title: 'Fichas de proposta',
            currentBottomNavIndex: -1,
            showBottomNavigation: false,
            body: _LockedState(),
          );
        }
        return _buildBody(context);
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    final accent = _accent(context);
    final canCreate = ModuleAccessService.instance.hasPermission(
      'proposal:create',
    );
    final canViewAll = ModuleAccessService.instance.hasPermission(
      'proposal:view_all',
    );
    // Tela larga: coluna centrada de até 720 (sem LayoutBuilder entre o
    // RefreshIndicator e a lista — isso quebra o pull-to-refresh).
    final width = MediaQuery.sizeOf(context).width;
    final padH = math.max(_kPadH, (width - _kMaxW) / 2);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final active = _activeFilters();
    final showClearAll =
        active.length > 1 ||
        (active.isNotEmpty &&
            (_filters.status != null || _showDeletedOnly));

    return AppScaffold(
      title: 'Fichas de proposta',
      currentBottomNavIndex: -1,
      showBottomNavigation: false,
      actions: [
        // Painel de propostas (web: /fichas-proposta/dashboard).
        if (ProposalsDashboardPage.canOpen())
          IconButton(
            tooltip: 'Dashboard de propostas',
            icon: const Icon(LucideIcons.chartColumn, size: 19),
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.proposalsDashboard),
          ),
      ],
      body: Stack(
        children: [
          RefreshIndicator(
            color: accent,
            onRefresh: _load,
            child: CustomScrollView(
              controller: _scroll,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(padH, 14, padH, 0),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ListHeader(
                          total: _stats?.total,
                          result: _data?.total,
                          filtered: _hasAnyFilter,
                          deletedOnly: _showDeletedOnly,
                          orderLabel: _orderLabel(_filters),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _SearchBar(
                                controller: _search,
                                accent: accent,
                                onSubmitted: _load,
                                onClear: _clearSearch,
                              ),
                            ),
                            const SizedBox(width: 8),
                            FichasFiltersButton(
                              count: _filters.drawerFilterCount,
                              onTap: () => _openFilters(canViewAll),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _StatusChips(
                          current: _filters.status,
                          accent: accent,
                          onChanged: (status) {
                            setState(() {
                              _filters = _filters.copyWith(status: status);
                            });
                            _load();
                          },
                        ),
                        if (canViewAll) ...[
                          const SizedBox(height: 10),
                          _DeletedToggle(
                            value: _showDeletedOnly,
                            accent: accent,
                            onChanged: (v) {
                              setState(() => _showDeletedOnly = v);
                              _load();
                            },
                          ),
                        ],
                        if (active.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _ActiveFiltersRow(
                            filters: active,
                            onClearAll: showClearAll ? _clearAll : null,
                          ),
                        ],
                        const SizedBox(height: 14),
                      ],
                    ),
                  ),
                ),
                if (_loading)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(padH, 0, padH, _kFabBottom),
                    sliver: SliverList.separated(
                      itemCount: 6,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, _) => const ProposalCardSkeleton(),
                    ),
                  )
                else if (_error != null)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(padH, 8, padH, _kFabBottom),
                    sliver: SliverToBoxAdapter(
                      child: AppErrorState.fromApi(
                        message: _error,
                        statusCode: _errorStatus,
                        onRetry: _load,
                        dense: true,
                      ),
                    ),
                  )
                else if (_data == null || _data!.items.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(
                      filtered: _hasAnyFilter,
                      deletedOnly: _showDeletedOnly,
                      canCreate: canCreate,
                      onClear: _clearAll,
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(padH, 0, padH, _kFabBottom),
                    sliver: SliverList.separated(
                      itemCount: _data!.items.length + (_loadingMore ? 1 : 0),
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        // Próxima página: esqueleto do card, não spinner.
                        if (i >= _data!.items.length) {
                          return const ProposalCardSkeleton();
                        }
                        final p = _data!.items[i];
                        return ProposalCard(
                          proposal: p,
                          accent: accent,
                          onTap: () => _openDetail(p),
                          onContinue: () => _openSignatures(p),
                          onShowHistorico: () =>
                              _openSignatures(p, showHistorico: true),
                          onAction: (a) => _onAction(p, a),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          // Com o teclado aberto (busca), o botão sairia flutuando sobre a
          // lista — some até o teclado fechar.
          if (canCreate && !keyboardOpen)
            Positioned(
              right: padH,
              bottom: 22,
              child: SafeArea(
                child: _CreateFab(accent: accent, onTap: _openCreate),
              ),
            ),
        ],
      ),
    );
  }
}

/// Cabeçalho da lista: a contagem responde "quantas", a frase ao lado
/// responde "quais e em que ordem". Sem eyebrow, sem ponto luminoso, sem
/// faixa de KPI — a lista é a estrela.
class _ListHeader extends StatelessWidget {
  const _ListHeader({
    required this.total,
    required this.result,
    required this.filtered,
    required this.deletedOnly,
    required this.orderLabel,
  });

  /// Base inteira (`/stats`).
  final int? total;

  /// Resultado do recorte atual (`total` da listagem).
  final int? result;
  final bool filtered;
  final bool deletedOnly;
  final String orderLabel;

  static final NumberFormat _int = NumberFormat.decimalPattern('pt_BR');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final shown = filtered ? result : (total ?? result);
    final n = shown ?? 0;
    final noun = deletedOnly
        ? (n == 1 ? 'proposta excluída' : 'propostas excluídas')
        : (n == 1 ? 'proposta' : 'propostas');
    final String scope;
    if (deletedOnly) {
      scope = 'Em auditoria, fora da lista normal · $orderLabel';
    } else if (filtered) {
      scope = total != null
          ? 'No recorte, de ${_int.format(total)} no total · $orderLabel'
          : 'No recorte · $orderLabel';
    } else {
      scope = 'Todas as fichas · $orderLabel';
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              shown == null ? '—' : _int.format(n),
              maxLines: 1,
              softWrap: false,
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: textColor,
                height: 1.0,
                letterSpacing: -1.0,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  noun,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  scope,
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
        ),
      ],
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.accent,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final Color accent;
  final VoidCallback onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hairline = ThemeHelpers.borderLightColor(context);
    final fill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return TextField(
          controller: controller,
          textInputAction: TextInputAction.search,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          onSubmitted: (_) {
            FocusScope.of(context).unfocus();
            onSubmitted();
          },
          decoration: InputDecoration(
            hintText: 'Buscar nº, comprador, ficha…',
            hintStyle: TextStyle(
              color: secondary.withValues(alpha: 0.9),
              fontWeight: FontWeight.w500,
            ),
            isDense: true,
            prefixIcon: Icon(Icons.search_rounded, color: accent, size: 22),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    icon: Icon(Icons.close_rounded, size: 19, color: secondary),
                    onPressed: onClear,
                    tooltip: 'Limpar busca',
                  ),
            filled: true,
            fillColor: fill,
            contentPadding: const EdgeInsets.symmetric(vertical: 13),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: hairline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: hairline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: accent.withValues(alpha: 0.65),
                width: 1.4,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusChips extends StatelessWidget {
  const _StatusChips({
    required this.current,
    required this.accent,
    required this.onChanged,
  });

  final ProposalStatus? current;
  final Color accent;
  final ValueChanged<ProposalStatus?> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final items = <(ProposalStatus?, String, Color)>[
      (null, 'Todas', accent),
      (
        ProposalStatus.processing,
        'Em andamento',
        dark ? AppColors.status.infoDarkMode : AppColors.status.info,
      ),
      (
        ProposalStatus.finalized,
        'Finalizadas',
        dark ? AppColors.status.successDarkMode : AppColors.status.success,
      ),
      (
        ProposalStatus.canceled,
        'Canceladas',
        dark ? AppColors.status.errorDarkMode : AppColors.status.error,
      ),
    ];

    // Grid de largura uniforme (2 colunas) — alinhado, sem scroll horizontal.
    // Item ímpar final ocupa a linha inteira para não deixar célula órfã.
    return LayoutBuilder(
      builder: (ctx, c) {
        const gap = 8.0;
        final half = (c.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < items.length; i++)
              SizedBox(
                width: (items.length.isOdd && i == items.length - 1)
                    ? c.maxWidth
                    : half,
                child: _StatusChip(
                  label: items[i].$2,
                  tone: items[i].$3,
                  selected: items[i].$1 == current,
                  onTap: () => onChanged(items[i].$1),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.tone,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color tone;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? tone.withValues(alpha: 0.13) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minHeight: 42),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? tone.withValues(alpha: 0.55)
                    : tone.withValues(alpha: 0.3),
                width: 1.4,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? tone : tone.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: selected
                          ? tone
                          : ThemeHelpers.textSecondaryColor(context),
                      letterSpacing: 0.1,
                    ),
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

class _DeletedToggle extends StatelessWidget {
  const _DeletedToggle({
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      button: true,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: value
                  ? accent.withValues(alpha: 0.55)
                  : ThemeHelpers.borderColor(context),
            ),
            color: value ? accent.withValues(alpha: 0.06) : null,
          ),
          child: Row(
            children: [
              Icon(
                value ? Icons.toggle_on_rounded : Icons.toggle_off_outlined,
                size: 22,
                color: value
                    ? accent
                    : ThemeHelpers.textSecondaryColor(context),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Apenas excluídas',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: value
                        ? accent
                        : ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Um recorte ativo que vira etiqueta removível.
class _ActiveFilter {
  final IconData icon;
  final String label;
  final VoidCallback onRemove;

  const _ActiveFilter({
    required this.icon,
    required this.label,
    required this.onRemove,
  });
}

/// Etiquetas do recorte: o que está filtrando a lista, à vista, cada uma
/// com "x" — sem precisar abrir o modal para descobrir.
class _ActiveFiltersRow extends StatelessWidget {
  const _ActiveFiltersRow({required this.filters, this.onClearAll});

  final List<_ActiveFilter> filters;
  final VoidCallback? onClearAll;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final fill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final f in filters)
          Semantics(
            button: true,
            label: 'Remover filtro ${f.label}',
            child: Material(
              color: fill,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: f.onRemove,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 36),
                  padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: ThemeHelpers.borderLightColor(context),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(f.icon, size: 14, color: secondary),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 210),
                        child: Text(
                          f.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: text,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.close_rounded, size: 15, color: secondary),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (onClearAll != null)
          TextButton(
            onPressed: onClearAll,
            style: TextButton.styleFrom(
              // Nunca vermelho: limpar não é destrutivo.
              foregroundColor: secondary,
              minimumSize: const Size(48, 36),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              textStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            child: const Text('Limpar tudo'),
          ),
      ],
    );
  }
}

/// Vazio que ENSINA: o que aparece aqui e como chegar lá.
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.filtered,
    required this.deletedOnly,
    required this.canCreate,
    required this.onClear,
  });

  final bool filtered;
  final bool deletedOnly;
  final bool canCreate;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final accent = _accent(context);
    final String title;
    final String body;
    final IconData icon;
    if (deletedOnly) {
      icon = LucideIcons.archive;
      title = 'Nenhuma proposta excluída';
      body = 'Propostas excluídas saem da lista normal e ficam aqui para '
          'auditoria, com o motivo registrado.';
    } else if (filtered) {
      icon = LucideIcons.searchX;
      title = 'Nenhuma proposta neste recorte';
      body = 'Tire uma etiqueta acima ou limpe tudo para voltar a ver as '
          'outras propostas.';
    } else {
      icon = LucideIcons.fileSignature;
      title = 'Nenhuma proposta ainda';
      body = canCreate
          ? 'Aqui ficam as fichas de proposta de compra. Registre a primeira '
              'em "Nova proposta": o comprador assina primeiro, depois o '
              'proprietário e, por fim, o corretor.'
          : 'Aqui ficam as fichas de proposta de compra que você pode ver. '
              'Quando alguém registrar uma proposta com você, ela aparece '
              'nesta lista.';
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 112),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.16 : 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accent.withValues(alpha: 0.22)),
                ),
                child: Icon(icon, size: 24, color: accent),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: muted,
                  height: 1.45,
                ),
              ),
              if (filtered || deletedOnly) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: onClear,
                  icon: const Icon(LucideIcons.filterX, size: 16),
                  label: const Text('Limpar filtros'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: muted,
                    side: BorderSide(color: ThemeHelpers.borderColor(context)),
                    minimumSize: const Size(48, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Sem `proposal:view`: a tela diz o motivo e quem resolve (não some).
class _LockedState extends StatelessWidget {
  const _LockedState();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = ThemeHelpers.textColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: muted.withValues(alpha: isDark ? 0.16 : 0.08),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: muted.withValues(alpha: 0.25)),
                ),
                child: Icon(LucideIcons.lock, size: 25, color: muted),
              ),
              const SizedBox(height: 16),
              Text(
                'Sem acesso às fichas de proposta',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                  color: text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sua conta não tem a permissão de ver propostas. Peça ao '
                'administrador da empresa para liberar o acesso.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                  color: muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateFab extends StatelessWidget {
  const _CreateFab({required this.accent, required this.onTap});

  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accent,
      shape: const StadiumBorder(),
      elevation: 4,
      // Sombra neutra: a cor da marca na sombra vira mancha no claro.
      shadowColor: Colors.black.withValues(alpha: 0.35),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, color: Colors.white, size: 22),
              SizedBox(width: 8),
              Text(
                'Nova proposta',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
