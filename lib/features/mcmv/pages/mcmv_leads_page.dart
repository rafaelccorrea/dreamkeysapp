import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/mcmv_models.dart';
import '../services/mcmv_service.dart';
import '../widgets/mcmv_common.dart';
import '../widgets/mcmv_lead_card.dart';
import '../widgets/mcmv_leads_filters_drawer.dart';

/// Tela **Leads MCMV** — mesmo DNA refinado de Comissões/Aprovações: hero
/// editorial com KPIs, busca flush, chips de status (filtro da API) e faixa de
/// renda, modal de filtros no padrão do Kanban e lista flush paginada com
/// ações de contato no próprio item.
class McmvLeadsPage extends StatefulWidget {
  const McmvLeadsPage({super.key});

  @override
  State<McmvLeadsPage> createState() => _McmvLeadsPageState();
}

class _McmvLeadsPageState extends State<McmvLeadsPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const double _kSectionGap = 12;
  static const int _pageSize = 20;

  List<McmvLead> _items = const [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _total = 0;
  int _page = 1;
  bool _hasNext = false;

  McmvLeadFilters _filters = const McmvLeadFilters(limit: _pageSize);
  McmvIncomeRange? _rangeFilter; // client-side (a API não filtra por faixa)

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _appliedSearch = '';
  bool _searchFocused = false;

  bool get _canView =>
      mcmvModuleEnabled() &&
      ModuleAccessService.instance.hasPermission(McmvPermissions.leadView);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ─── Dados ───────────────────────────────────────────────────────────────

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      if (refresh) _error = null;
    });
    final res = await McmvService.instance.listLeads(
      filters: _filters.copyWith(page: 1),
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _items = res.data!.items;
        _total = res.data!.total;
        _page = res.data!.page;
        _hasNext = res.data!.hasNext;
        _error = null;
      } else {
        _error = res.message ?? 'Erro ao carregar leads';
      }
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasNext) return;
    setState(() => _loadingMore = true);
    final res = await McmvService.instance.listLeads(
      filters: _filters.copyWith(page: _page + 1),
    );
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (res.success && res.data != null) {
        _items = [..._items, ...res.data!.items];
        _page = res.data!.page;
        _hasNext = res.data!.hasNext;
        _total = res.data!.total;
      }
    });
  }

  Future<void> _refresh() => _load(refresh: true);

  void _selectStatus(McmvLeadStatus? status) {
    if (_filters.status == status) return;
    setState(() {
      _filters = _filters.copyWith(
        status: status,
        clearStatus: status == null,
        page: 1,
      );
    });
    _load(refresh: true);
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final v = value.trim();
      if (v == _appliedSearch) return;
      setState(() => _appliedSearch = v);
    });
  }

  void _openFilters() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => McmvLeadsFiltersDrawer(
        initialFilters: _filters,
        onApply: (f) {
          setState(() => _filters = f);
          _load(refresh: true);
        },
        onClear: () {
          setState(() {
            _filters = McmvLeadFilters(
              status: _filters.status,
              limit: _pageSize,
            );
          });
          _load(refresh: true);
        },
      ),
    );
  }

  Future<void> _openDetails(McmvLead lead) async {
    await Navigator.of(context).pushNamed(
      McmvRoutes.leadDetails(lead.id),
      arguments: lead,
    );
    if (!mounted) return;
    // Detalhe pode capturar/mudar status/converter — recarrega ao voltar.
    _load(refresh: true);
  }

  /// Refino no cliente: busca (nome/email/telefone/CPF/cidade) + faixa de
  /// renda — a API não expõe esses filtros.
  List<McmvLead> get _visibleItems {
    Iterable<McmvLead> out = _items;
    if (_rangeFilter != null) {
      out = out.where((l) => l.incomeRange == _rangeFilter);
    }
    final q = _appliedSearch.toLowerCase().trim();
    if (q.isNotEmpty) {
      final qDigits = mcmvOnlyDigits(q);
      out = out.where((l) {
        if (l.name.toLowerCase().contains(q)) return true;
        if (l.email.toLowerCase().contains(q)) return true;
        if (l.city.toLowerCase().contains(q)) return true;
        if (qDigits.isNotEmpty) {
          if (mcmvOnlyDigits(l.phone).contains(qDigits)) return true;
          if (mcmvOnlyDigits(l.cpf).contains(qDigits)) return true;
        }
        return false;
      });
    }
    return out.toList();
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canView) {
      return const AppScaffold(
        title: 'Leads MCMV',
        showBottomNavigation: false,
        body: McmvDeniedView(
          message: 'Você não tem acesso aos leads do MCMV.',
          permission: McmvPermissions.leadView,
        ),
      );
    }
    return AppScaffold(
      title: 'Leads MCMV',
      showBottomNavigation: false,
      body: RefreshIndicator(
        color: mcmvAccentColor(context),
        onRefresh: _refresh,
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHero(context),
                        const SizedBox(height: _kSectionGap),
                        _buildSearchRow(context),
                        const SizedBox(height: _kSectionGap),
                      ],
                    ),
                  ),
                  _buildStatusChips(context),
                  const SizedBox(height: 8),
                  _buildRangeChips(context),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        _kPagePadH, _kSectionGap + 4, _kPagePadH,
                        _kPagePadBottom),
                    child: _buildPanel(context),
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
    final accent = mcmvAccentColor(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final blue =
        isDark ? AppColors.status.infoDarkMode : AppColors.status.info;

    final available = _items.where((l) => !l.isCaptured).length;
    final eligible = _items.where((l) => l.eligible).length;
    final avgScore = _items.isEmpty
        ? 0
        : (_items.fold<int>(0, (sum, l) => sum + l.score) / _items.length)
            .round();

    final dot = available > 0 ? blue : emerald;
    final subtitle = _total == 0
        ? 'Leads do programa Minha Casa Minha Vida aparecem aqui.'
        : available > 0
            ? '$available dispon${available == 1 ? 'ível' : 'íveis'} para '
                'captura nesta lista'
            : 'Todos os leads da lista já foram capturados.';

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
                'MINHA CASA MINHA VIDA',
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
                '$_total',
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
                  _total == 1 ? 'lead' : 'leads',
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
          _buildKpiStrip(
            context,
            blue: blue,
            emerald: emerald,
            amber: amber,
            available: available,
            eligible: eligible,
            avgScore: avgScore,
          ),
        ],
      ),
    );
  }

  Widget _buildKpiStrip(
    BuildContext context, {
    required Color blue,
    required Color emerald,
    required Color amber,
    required int available,
    required int eligible,
    required int avgScore,
  }) {
    final divider = ThemeHelpers.borderColor(context).withValues(alpha: 0.45);
    final blocks = <Widget>[
      _heroKpiBlock(context, LucideIcons.userPlus, 'DISPONÍVEIS',
          _loading ? '—' : '$available', 'para captura', blue),
      _heroKpiBlock(context, LucideIcons.circleCheckBig, 'ELEGÍVEIS',
          _loading ? '—' : '$eligible', 'na lista atual', emerald),
      _heroKpiBlock(context, LucideIcons.target, 'SCORE MÉDIO',
          _loading ? '—' : '$avgScore%', 'dos leads listados', amber),
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

  // ─── Busca flush + botão de filtros ─────────────────────────────────────

  Widget _buildSearchRow(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = mcmvAccentColor(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final cardColor = ThemeHelpers.cardBackgroundColor(context);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final hasText = _searchController.text.isNotEmpty;
    final showAccent = _searchFocused || hasText;
    final advancedCount = _filters.advancedCount;

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
                        color: textColor,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Buscar por nome, telefone, CPF…',
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
        // Botão de filtros avançados (cidade/UF/elegível/score) com badge.
        InkWell(
          onTap: _openFilters,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: advancedCount > 0
                    ? accent.withValues(alpha: 0.5)
                    : borderColor,
                width: advancedCount > 0 ? 1.4 : 1,
              ),
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(
                    LucideIcons.slidersHorizontal,
                    size: 19,
                    color: advancedCount > 0 ? accent : secondary,
                  ),
                ),
                if (advancedCount > 0)
                  Positioned(
                    right: 7,
                    top: 7,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
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

  // ─── Chips de status (filtro da API) ─────────────────────────────────────

  Widget _buildStatusChips(BuildContext context) {
    final options = <(McmvLeadStatus?, String)>[
      (null, 'Todos'),
      (McmvLeadStatus.newLead, 'Novos'),
      (McmvLeadStatus.contacted, 'Contactados'),
      (McmvLeadStatus.qualified, 'Qualificados'),
      (McmvLeadStatus.converted, 'Convertidos'),
      (McmvLeadStatus.lost, 'Perdidos'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: _kPagePadH),
      child: Row(
        children: [
          for (final (status, label) in options) ...[
            McmvFilterChip(
              label: label,
              icon: status == null ? null : mcmvLeadStatusIcon(status),
              selected: _filters.status == status,
              accent: status == null
                  ? mcmvAccentColor(context)
                  : mcmvLeadStatusColor(context, status),
              onTap: () => _selectStatus(status),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  // ─── Chips de faixa de renda (refino no cliente) ─────────────────────────

  Widget _buildRangeChips(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    final options = <(McmvIncomeRange?, String)>[
      (null, 'Todas as faixas'),
      (McmvIncomeRange.faixa1, 'Faixa 1'),
      (McmvIncomeRange.faixa2, 'Faixa 2'),
      (McmvIncomeRange.faixa3, 'Faixa 3'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: _kPagePadH),
      child: Row(
        children: [
          for (final (range, label) in options) ...[
            McmvFilterChip(
              label: label,
              selected: _rangeFilter == range,
              accent: tone,
              onTap: () => setState(() => _rangeFilter = range),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  // ─── Painel (header + lista/estados) ─────────────────────────────────────

  Widget _buildPanel(BuildContext context) {
    final status = _filters.status;
    final tone = status == null
        ? mcmvAccentColor(context)
        : mcmvLeadStatusColor(context, status);
    final visible = _visibleItems;

    Widget child;
    if (_loading && _items.isEmpty) {
      child = _buildSkeleton();
    } else if (_error != null && _items.isEmpty) {
      child = McmvErrorState(
        message: _error!,
        onRetry: () => _load(refresh: true),
      );
    } else if (visible.isEmpty) {
      child = _buildEmpty(context);
    } else {
      child = _buildList(context, visible);
    }

    final key = ValueKey(
        'panel-${status?.name ?? 'all'}-${_rangeFilter?.name ?? 'all'}');
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        McmvPanelHeader(
          icon: status == null ? LucideIcons.contact : mcmvLeadStatusIcon(status),
          eyebrow: status == null
              ? 'TODOS OS LEADS'
              : '${status.label.toUpperCase()}S',
          title: status == null
              ? 'Leads do programa'
              : 'Leads ${status.label.toLowerCase()}s',
          hint: status == null
              ? 'Leads disponíveis e capturados pela sua empresa.'
              : 'Filtrando pelo status "${status.label}".',
          tone: tone,
          trailing: visible.length != _items.length
              ? _RefineBadge(count: visible.length)
              : null,
        ),
        const SizedBox(height: 14),
        child,
      ],
    ).animate(key: key).fadeIn(duration: 240.ms);
  }

  Widget _buildList(BuildContext context, List<McmvLead> visible) {
    var animIndex = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final lead in visible)
          McmvLeadCard(
            lead: lead,
            onTap: () => _openDetails(lead),
          ).animate(key: ValueKey('lead-${lead.id}')).fadeIn(
                delay: Duration(milliseconds: 30 * (animIndex++).clamp(0, 12)),
                duration: 220.ms,
              ),
        if (_hasNext) _buildLoadMore(context),
      ],
    );
  }

  Widget _buildLoadMore(BuildContext context) {
    final accent = mcmvAccentColor(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Center(
        child: _loadingMore
            ? SizedBox(
                width: 22,
                height: 22,
                child:
                    CircularProgressIndicator(strokeWidth: 2.2, color: accent),
              )
            : OutlinedButton.icon(
                onPressed: _loadMore,
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  side: BorderSide(color: accent.withValues(alpha: 0.45)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(LucideIcons.chevronDown, size: 16),
                label: Text(
                  'Carregar mais · página ${_page + 1}',
                ),
              ),
      ),
    );
  }

  // ─── Estados ─────────────────────────────────────────────────────────────

  /// Skeleton fiel ao [McmvLeadCard]: glyph + pílulas + nome + specs + barra
  /// de ações de contato.
  Widget _buildSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(
        4,
        (_) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonBox(width: 44, height: 44, borderRadius: 13),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Row(
                          children: [
                            SkeletonText(width: 62, height: 18,
                                borderRadius: 999),
                            SizedBox(width: 6),
                            SkeletonText(width: 56, height: 18,
                                borderRadius: 999),
                            SizedBox(width: 6),
                            SkeletonText(width: 66, height: 18,
                                borderRadius: 999),
                          ],
                        ),
                        SizedBox(height: 9),
                        SkeletonText(width: double.infinity, height: 15),
                        SizedBox(height: 6),
                        SkeletonText(width: 140, height: 12),
                        SizedBox(height: 6),
                        SkeletonText(width: 180, height: 11),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: const [
                      SkeletonText(width: 42, height: 16),
                      SizedBox(height: 6),
                      SkeletonText(width: 34, height: 9),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const SkeletonBox(
                  width: double.infinity, height: 34, borderRadius: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final hasSearch = _appliedSearch.trim().isNotEmpty;
    final status = _filters.status;
    final tone = status == null
        ? mcmvAccentColor(context)
        : mcmvLeadStatusColor(context, status);
    if (hasSearch) {
      return McmvEmptyState(
        icon: LucideIcons.searchX,
        title: 'Nada encontrado',
        body: 'Nenhum lead corresponde a "${_appliedSearch.trim()}".',
        tone: tone,
      );
    }
    if (_rangeFilter != null) {
      return McmvEmptyState(
        icon: LucideIcons.wallet,
        title: 'Nenhum lead na ${_rangeFilter!.label}',
        body: 'Tente outra faixa de renda ou limpe os filtros.',
        tone: tone,
      );
    }
    return McmvEmptyState(
      icon: LucideIcons.contact,
      title: status == null
          ? 'Nenhum lead disponível'
          : 'Nenhum lead "${status.label}"',
      body: status == null
          ? 'Quando houver novos leads do programa, eles aparecerão aqui.'
          : 'Você não possui leads com esse status no momento.',
      tone: tone,
    );
  }
}

/// Badge "n em exibição" — sinaliza refino local (busca/faixa) sobre a lista.
class _RefineBadge extends StatelessWidget {
  final int count;

  const _RefineBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count em exibição',
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          fontSize: 10.5,
          color: ThemeHelpers.textSecondaryColor(context),
        ),
      ),
    );
  }
}