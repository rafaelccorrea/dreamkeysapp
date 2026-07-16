import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/visit_report_access.dart';
import '../models/visit_report_model.dart';
import '../services/visit_report_service.dart';
import '../widgets/visit_report_card.dart';
import '../widgets/visit_report_filters_sheet.dart';
import '../widgets/visit_signature_link_sheet.dart';

/// Escopo da lista — "minhas visitas" ou visão gestão (`scope=all`,
/// gated por `visit:manage`).
enum _VisitScope { mine, all }

/// Estado de um escopo (lista completa + paginação incremental local — o
/// backend devolve o array inteiro, sem paginação).
class _ScopeState {
  List<VisitReport> items = const [];
  bool loading = false;
  bool loaded = false;
  String? error;
  int visible = _VisitsPageState._pageSize;
}

/// Tela **Visitas** com personalidade de AGENDA: spotlight da próxima visita
/// (folhinha de calendário + faixa de assinaturas pendentes clicável) no topo
/// e lista agrupada por dia, com cabeçalhos de data pt-BR e itens em trilho
/// de timeline. Sem hero editorial — a identidade aqui é o calendário.
class VisitsPage extends StatefulWidget {
  const VisitsPage({super.key});

  @override
  State<VisitsPage> createState() => _VisitsPageState();
}

class _VisitsPageState extends State<VisitsPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 110;
  static const double _kSectionGap = 12;
  static const int _pageSize = 25;

  _VisitScope _activeScope = _VisitScope.mine;
  final Map<_VisitScope, _ScopeState> _state = {
    _VisitScope.mine: _ScopeState(),
    _VisitScope.all: _ScopeState(),
  };

  VisitReportFilters _filters = VisitReportFilters.empty;

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _appliedSearch = '';
  bool _searchFocused = false;

  /// Id do relatório com ação de link em andamento.
  String? _linkBusyId;

  bool get _canView =>
      ModuleAccessService.instance.hasPermission(VisitReportAccess.view);
  bool get _canCreate =>
      ModuleAccessService.instance.hasPermission(VisitReportAccess.create);
  bool get _canUpdate =>
      ModuleAccessService.instance.hasPermission(VisitReportAccess.update);
  bool get _canDelete =>
      ModuleAccessService.instance.hasPermission(VisitReportAccess.delete);
  bool get _canManage =>
      ModuleAccessService.instance.hasPermission(VisitReportAccess.manage);

  @override
  void initState() {
    super.initState();
    _loadScope(_VisitScope.mine);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ─── Cores ───────────────────────────────────────────────────────────────

  Color _accentColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
  }

  /// Tom por escopo: vermelho da marca = minhas visitas (tela principal),
  /// violeta = visão gestão (secundária).
  Color _scopeColor(BuildContext context, _VisitScope scope) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (scope) {
      case _VisitScope.mine:
        return _accentColor(context);
      case _VisitScope.all:
        return isDark
            ? AppColors.status.purpleDarkMode
            : AppColors.status.purple;
    }
  }

  /// Tom do cabeçalho de dia: hoje/futuro na cor do escopo, passado e "sem
  /// data" neutros — leitura temporal da agenda.
  Color _dayTone(BuildContext context, DateTime? d) {
    if (d == null) return ThemeHelpers.textSecondaryColor(context);
    return d.isBefore(_todayStart)
        ? ThemeHelpers.textSecondaryColor(context)
        : _scopeColor(context, _activeScope);
  }

  // ─── Dados ───────────────────────────────────────────────────────────────

  DateTime get _todayStart {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Próxima visita (hoje ou à frente) — a mais próxima no tempo.
  VisitReport? _nextUpcoming(List<VisitReport> items) {
    VisitReport? best;
    final today = _todayStart;
    for (final r in items) {
      final d = r.visitDate;
      if (d == null || d.isBefore(today)) continue;
      if (best == null || d.isBefore(best.visitDate!)) best = r;
    }
    return best;
  }

  Future<void> _loadScope(_VisitScope scope, {bool refresh = false}) async {
    final st = _state[scope]!;
    setState(() {
      st.loading = true;
      if (refresh) st.error = null;
    });
    final res = await VisitReportService.instance.list(
      filters: _filters,
      scopeAll: scope == _VisitScope.all,
    );
    if (!mounted) return;
    setState(() {
      st.loading = false;
      st.loaded = true;
      if (res.success && res.data != null) {
        st.items = res.data!;
        st.visible = _pageSize;
        st.error = null;
      } else {
        st.error = res.message ?? 'Erro ao carregar visitas';
      }
    });
  }

  Future<void> _refresh() => _loadScope(_activeScope, refresh: true);

  void _selectScope(_VisitScope scope) {
    if (scope == _activeScope) return;
    setState(() => _activeScope = scope);
    final st = _state[scope]!;
    if (!st.loaded && !st.loading) _loadScope(scope);
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final v = value.trim();
      if (v == _appliedSearch) return;
      setState(() {
        _appliedSearch = v;
        for (final st in _state.values) {
          st.visible = _pageSize;
        }
      });
    });
  }

  void _applyFilters(VisitReportFilters filters) {
    setState(() {
      _filters = filters;
      for (final st in _state.values) {
        st.loaded = false;
        st.visible = _pageSize;
      }
    });
    _loadScope(_activeScope, refresh: true);
  }

  void _setStatusChip(VisitSignatureStatus? status) {
    setState(() {
      _filters = _filters.copyWith(
        status: status,
        resetStatus: status == null,
      );
      for (final st in _state.values) {
        st.visible = _pageSize;
      }
    });
  }

  /// Refino local: status (paridade com o web, que filtra em memória) + busca
  /// por cliente/endereço/referência/corretor/negociação.
  List<VisitReport> _refined(List<VisitReport> items) {
    var out = items;
    if (_filters.status != null) {
      out = out.where((r) => r.signatureStatus == _filters.status).toList();
    }
    final q = _appliedSearch.toLowerCase();
    if (q.isNotEmpty) {
      out = out.where((r) {
        if (r.clientLabel.toLowerCase().contains(q)) return true;
        if ((r.createdByName ?? '').toLowerCase().contains(q)) return true;
        if ((r.kanbanTaskTitle ?? '').toLowerCase().contains(q)) return true;
        return r.properties.any((p) =>
            p.address.toLowerCase().contains(q) ||
            (p.reference ?? '').toLowerCase().contains(q) ||
            (p.propertyCode ?? '').toLowerCase().contains(q));
      }).toList();
    }
    return out;
  }

  // ─── Navegação / ações ───────────────────────────────────────────────────

  Future<void> _openCreate() async {
    final changed = await Navigator.of(context)
        .pushNamed(VisitReportRoutes.createReport);
    if (changed == true && mounted) _refresh();
  }

  Future<void> _openDetail(VisitReport r) async {
    await Navigator.of(context).pushNamed(VisitReportRoutes.details(r.id));
    if (mounted) _refresh();
  }

  Future<void> _openEdit(VisitReport r) async {
    final changed =
        await Navigator.of(context).pushNamed(VisitReportRoutes.edit(r.id));
    if (changed == true && mounted) _refresh();
  }

  Future<void> _confirmDelete(VisitReport r) async {
    final theme = Theme.of(context);
    final danger = theme.brightness == Brightness.dark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Excluir relatório',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.3),
        ),
        content: Text(
          'O relatório de visita de ${r.clientLabel} será excluído. '
          'Esta ação não pode ser desfeita.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final res = await VisitReportService.instance.remove(r.id);
    if (!mounted) return;
    if (res.success) {
      messenger.showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Relatório excluído.'),
      ));
      _refresh();
    } else {
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(res.message ?? 'Erro ao excluir.'),
      ));
    }
  }

  Future<void> _generateLink(VisitReport r) async {
    if (r.isSigned) return;
    setState(() => _linkBusyId = r.id);
    final messenger = ScaffoldMessenger.of(context);
    final res = await VisitReportService.instance.generateSignatureLink(r.id);
    if (!mounted) return;
    setState(() => _linkBusyId = null);
    if (res.success && res.data != null && res.data!.url.isNotEmpty) {
      await VisitSignatureLinkSheet.show(context, report: r, link: res.data!);
      if (mounted) _refresh();
    } else {
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(res.message ?? 'Erro ao gerar link.'),
      ));
    }
  }

  Future<VisitSignatureLink?> _fetchActiveLink(VisitReport r) async {
    setState(() => _linkBusyId = r.id);
    final res = await VisitReportService.instance.getSignatureLink(r.id);
    if (mounted) setState(() => _linkBusyId = null);
    if (res.success && res.data != null && res.data!.url.isNotEmpty) {
      return res.data;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(res.message ?? 'Link expirado ou não encontrado.'),
      ));
    }
    return null;
  }

  Future<void> _copyLink(VisitReport r) async {
    final messenger = ScaffoldMessenger.of(context);
    final link = await _fetchActiveLink(r);
    if (link == null || !mounted) return;
    await Clipboard.setData(ClipboardData(text: link.url));
    messenger.showSnackBar(const SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text('Link copiado!'),
    ));
  }

  Future<void> _shareWhatsApp(VisitReport r) async {
    final messenger = ScaffoldMessenger.of(context);
    final link = await _fetchActiveLink(r);
    if (link == null || !mounted) return;
    final ok = await shareVisitLinkOnWhatsApp(r, link.url);
    if (!ok && mounted) {
      messenger.showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Não foi possível abrir o WhatsApp.'),
      ));
    }
  }

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => VisitReportFiltersSheet(
        initialFilters: _filters,
        onApply: _applyFilters,
        onClear: () => _applyFilters(VisitReportFilters.empty),
      ),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canView) {
      return const AppScaffold(
        title: 'Visitas',
        showBottomNavigation: false,
        body: _DeniedView(),
      );
    }
    return AppScaffold(
      title: 'Visitas',
      showBottomNavigation: false,
      body: Stack(
        children: [
          RefreshIndicator(
            color: _accentColor(context),
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(
                  top: _kPagePadTop, bottom: _kPagePadBottom),
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: _kPagePadH),
                  child: _buildSpotlight(context),
                ),
                const SizedBox(height: _kSectionGap),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: _kPagePadH),
                  child: _buildSearchRow(context),
                ),
                const SizedBox(height: _kSectionGap),
                if (_canManage) _buildScopeRail(context),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      _kPagePadH, _kSectionGap, _kPagePadH, 0),
                  child: _buildActivePanel(context),
                ),
              ],
            ),
          ),
          if (_canCreate)
            Positioned(
              right: _kPagePadH,
              bottom: 22,
              child: SafeArea(
                child: _CreateFab(
                  accent: _accentColor(context),
                  onTap: _openCreate,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Spotlight de agenda (próxima visita + pendências) ──────────────────

  Widget _buildSpotlight(BuildContext context) {
    final st = _state[_activeScope]!;
    if (!st.loaded) return _buildSpotlightSkeleton(context);
    if (st.error != null && st.items.isEmpty) return const SizedBox.shrink();

    final next = _nextUpcoming(st.items);
    final pending = st.items
        .where((r) => r.signatureStatus == VisitSignatureStatus.pending)
        .length;

    return _AgendaSpotlight(
      tone: _scopeColor(context, _activeScope),
      next: next,
      pendingCount: pending,
      onOpenNext: next == null ? null : () => _openDetail(next),
      onFilterPending: () => _setStatusChip(VisitSignatureStatus.pending),
    )
        .animate(key: ValueKey('spotlight-${_activeScope.name}'))
        .fadeIn(duration: 260.ms)
        .slideY(
          begin: 0.03,
          end: 0,
          duration: 280.ms,
          curve: Curves.easeOutCubic,
        );
  }

  Widget _buildSpotlightSkeleton(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.05),
        ),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          SkeletonBox(width: 56, height: 62, borderRadius: 14),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonText(width: 92, height: 10),
                SizedBox(height: 9),
                SkeletonText(width: 170, height: 16),
                SizedBox(height: 8),
                SkeletonText(width: double.infinity, height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Busca flush + filtros ───────────────────────────────────────────────

  Widget _buildSearchRow(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accentColor(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final cardColor = ThemeHelpers.cardBackgroundColor(context);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final hasText = _searchController.text.isNotEmpty;
    final showAccent = _searchFocused || hasText;
    final filtersActive = _filters.activeCount > 0;

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
                        hintText: 'Buscar por cliente, imóvel…',
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
        // Botão de filtros (modal padrão CRM) com dot quando há filtro ativo.
        InkWell(
          onTap: _openFilters,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: filtersActive
                  ? accent.withValues(alpha: isDark ? 0.16 : 0.09)
                  : cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: filtersActive
                    ? accent.withValues(alpha: 0.5)
                    : borderColor,
                width: filtersActive ? 1.4 : 1,
              ),
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(
                    Icons.tune_rounded,
                    size: 21,
                    color: filtersActive ? accent : secondary,
                  ),
                ),
                if (filtersActive)
                  Positioned(
                    right: 9,
                    top: 9,
                    child: Container(
                      width: 7,
                      height: 7,
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

  // ─── Abas flush de escopo ────────────────────────────────────────────────

  Widget _buildScopeRail(BuildContext context) {
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
              icon: LucideIcons.userRound,
              label: 'Minhas visitas',
              count: _state[_VisitScope.mine]!.loaded
                  ? _state[_VisitScope.mine]!.items.length
                  : 0,
              tone: _scopeColor(context, _VisitScope.mine),
              selected: _activeScope == _VisitScope.mine,
              onTap: () => _selectScope(_VisitScope.mine),
            ),
          ),
          Expanded(
            child: _FlushTab(
              icon: LucideIcons.users,
              label: 'Gestão',
              count: _state[_VisitScope.all]!.loaded
                  ? _state[_VisitScope.all]!.items.length
                  : 0,
              tone: _scopeColor(context, _VisitScope.all),
              selected: _activeScope == _VisitScope.all,
              onTap: () => _selectScope(_VisitScope.all),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Chips de status ─────────────────────────────────────────────────────

  Widget _buildStatusChips(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final accent = _accentColor(context);

    Widget chip(String label, VisitSignatureStatus? status, Color tone) {
      final selected = _filters.status == status;
      return _StatusChip(
        label: label,
        tone: tone,
        selected: selected,
        onTap: () => _setStatusChip(status),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          chip('Todas', null, accent),
          const SizedBox(width: 8),
          chip('Aguardando', VisitSignatureStatus.pending, amber),
          const SizedBox(width: 8),
          chip('Assinadas', VisitSignatureStatus.signed, green),
          const SizedBox(width: 8),
          chip('Expiradas', VisitSignatureStatus.expired, neutral),
        ],
      ),
    );
  }

  // ─── Painel ativo ────────────────────────────────────────────────────────

  Widget _buildActivePanel(BuildContext context) {
    final st = _state[_activeScope]!;
    final refined = _refined(st.items);

    Widget child;
    if (st.loading && st.items.isEmpty) {
      child = _buildSkeleton();
    } else if (st.error != null && st.items.isEmpty) {
      child = _buildError(context, st.error!);
    } else if (refined.isEmpty) {
      child = _buildEmpty(context);
    } else {
      child = _buildAgenda(context, st, refined);
    }

    return Column(
      key: ValueKey('panel-${_activeScope.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStatusChips(context),
        child,
      ],
    ).animate(key: ValueKey('panel-${_activeScope.name}')).fadeIn(
          duration: 240.ms,
        );
  }

  // ─── Lista em formato de agenda (agrupada por dia) ───────────────────────

  String _dayKey(DateTime? d) =>
      d == null ? 'sem-data' : '${d.year}-${d.month}-${d.day}';

  Widget _buildAgenda(
    BuildContext context,
    _ScopeState st,
    List<VisitReport> refined,
  ) {
    // Visitas sem data iriam parar no meio da ordenação (fallback por
    // createdAt) — agrupa todas no fim, sob o cabeçalho "Sem data definida".
    final dated = <VisitReport>[];
    final undated = <VisitReport>[];
    for (final r in refined) {
      (r.visitDate == null ? undated : dated).add(r);
    }
    final ordered = [...dated, ...undated];
    final visible = ordered.take(st.visible).toList();

    final counts = <String, int>{};
    for (final r in ordered) {
      counts.update(_dayKey(r.visitDate), (v) => v + 1, ifAbsent: () => 1);
    }

    final showBroker = _activeScope == _VisitScope.all;
    final children = <Widget>[];
    String? lastKey;
    var animIndex = 0;
    var firstHeader = true;

    for (final r in visible) {
      final key = _dayKey(r.visitDate);
      if (key != lastKey) {
        children.add(_DayHeader(
          date: r.visitDate,
          count: counts[key] ?? 0,
          tone: _dayTone(context, r.visitDate),
          first: firstHeader,
        ));
        firstHeader = false;
        lastKey = key;
      }
      children.add(
        VisitReportCard(
          report: r,
          showBroker: showBroker,
          canEdit: _canUpdate,
          canDelete: _canDelete,
          linkBusy: _linkBusyId == r.id,
          onTap: () => _openDetail(r),
          onShareWhatsApp: () => _shareWhatsApp(r),
          onCopyLink: () => _copyLink(r),
          onGenerateLink: _canUpdate ? () => _generateLink(r) : null,
          onEdit: () => _openEdit(r),
          onDelete: () => _confirmDelete(r),
        ).animate(key: ValueKey('v-${r.id}')).fadeIn(
              delay: Duration(milliseconds: 30 * (animIndex++).clamp(0, 12)),
              duration: 220.ms,
            ),
      );
    }

    if (ordered.length > st.visible) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Center(
            child: OutlinedButton.icon(
              onPressed: () => setState(() => st.visible += _pageSize),
              style: OutlinedButton.styleFrom(
                foregroundColor: _accentColor(context),
                side: BorderSide(
                  color: _accentColor(context).withValues(alpha: 0.45),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(LucideIcons.chevronDown, size: 16),
              label: Text(
                'Carregar mais (${ordered.length - st.visible})',
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  // ─── Estados ─────────────────────────────────────────────────────────────

  /// Skeleton fiel à agenda nova: cabeçalho de dia (bolha de data + linha)
  /// seguido de itens em trilho (nó circular + conteúdo).
  Widget _buildSkeleton() {
    Widget header({bool first = false}) => Padding(
          padding: EdgeInsets.only(top: first ? 16 : 22, bottom: 12),
          child: Row(
            children: const [
              SkeletonBox(width: 30, height: 30, borderRadius: 10),
              SizedBox(width: 10),
              SkeletonText(width: 140, height: 13),
              Spacer(),
              SkeletonText(width: 48, height: 10),
            ],
          ),
        );

    Widget row() => Padding(
          padding: const EdgeInsets.only(bottom: 18, top: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              SkeletonBox(width: 28, height: 28, borderRadius: 999),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonText(width: 88, height: 16, borderRadius: 999),
                    SizedBox(height: 9),
                    SkeletonText(width: double.infinity, height: 14),
                    SizedBox(height: 6),
                    SkeletonText(width: 150, height: 12),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        SkeletonText(width: 72, height: 12),
                        SizedBox(width: 14),
                        SkeletonText(width: 72, height: 12),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header(first: true),
        row(),
        row(),
        header(),
        row(),
        row(),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    final tone = _scopeColor(context, _activeScope);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hasSearch = _appliedSearch.trim().isNotEmpty;
    final hasFilters = _filters.activeCount > 0;
    final (icon, title, body) = hasSearch
        ? (
            LucideIcons.searchX,
            'Nada encontrado',
            'Nenhuma visita corresponde a "${_appliedSearch.trim()}".',
          )
        : hasFilters
            ? (
                LucideIcons.listFilter,
                'Nada com esses filtros',
                'Ajuste ou limpe os filtros para ver mais visitas.',
              )
            : (
                LucideIcons.calendarDays,
                'Agenda vazia',
                'Registre a primeira visita e envie o link de assinatura ao cliente.',
              );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 4),
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
              color: secondary,
              height: 1.4,
            ),
          ),
          if (!hasSearch && !hasFilters && _canCreate) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _openCreate,
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('Registrar visita'),
              style: FilledButton.styleFrom(
                backgroundColor: _accentColor(context),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, String message) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 4),
      child: Column(
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
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _loadScope(_activeScope, refresh: true),
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}

// ─── Spotlight de agenda (próxima visita + faixa de pendências) ──────────────

class _AgendaSpotlight extends StatelessWidget {
  final Color tone;
  final VisitReport? next;
  final int pendingCount;
  final VoidCallback? onOpenNext;
  final VoidCallback onFilterPending;

  const _AgendaSpotlight({
    required this.tone,
    required this.next,
    required this.pendingCount,
    required this.onOpenNext,
    required this.onFilterPending,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final amberText = isDark
        ? AppColors.message.warningTextDarkMode
        : AppColors.message.warningText;
    final blue =
        isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;

    final n = next;
    final d = n?.visitDate;

    // Proximidade da próxima visita — hoje pede atenção (âmbar), o resto é
    // informação (azul).
    String? proximity;
    var proximityTone = blue;
    if (d != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final diff =
          DateTime(d.year, d.month, d.day).difference(today).inDays;
      if (diff <= 0) {
        proximity = 'Hoje';
        proximityTone = amberText;
      } else if (diff == 1) {
        proximity = 'Amanhã';
      } else {
        proximity = 'Em $diff dias';
      }
    }

    final String subtitle;
    if (n == null) {
      subtitle = 'As próximas visitas agendadas aparecem aqui.';
    } else {
      final addr = n.firstAddress ?? 'Endereço não informado';
      final extra = n.properties.length - 1;
      subtitle = extra > 0
          ? '$addr · +$extra imóve${extra == 1 ? 'l' : 'is'}'
          : addr;
    }

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.05),
        ),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onOpenNext,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Folhinha: a data da próxima visita (ou o dia de hoje,
                    // quando a agenda está livre à frente).
                    VisitDateLeaf(
                      date: d ?? DateTime.now(),
                      tone: tone,
                      width: 56,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  n != null
                                      ? 'Próxima visita'
                                      : 'Agenda de visitas',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: tone,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                              if (proximity != null) ...[
                                const SizedBox(width: 7),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: proximityTone.withValues(
                                        alpha: isDark ? 0.16 : 0.1),
                                    borderRadius:
                                        BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    proximity,
                                    style: TextStyle(
                                      color: proximityTone,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.2,
                                      height: 1.0,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            n?.clientLabel ?? 'Nenhuma visita à frente',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: textColor,
                              letterSpacing: -0.3,
                              fontSize: 15.5,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              if (n != null) ...[
                                Icon(LucideIcons.mapPin,
                                    size: 12, color: secondary),
                                const SizedBox(width: 5),
                              ],
                              Expanded(
                                child: Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      theme.textTheme.bodySmall?.copyWith(
                                    color: secondary,
                                    fontWeight: FontWeight.w600,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (onOpenNext != null) ...[
                      const SizedBox(width: 6),
                      Icon(LucideIcons.chevronRight,
                          size: 18, color: secondary),
                    ],
                  ],
                ),
              ),
            ),
          ),
          // Faixa fina de pendências — âmbar (atenção), aplica o filtro
          // "Aguardando" da própria lista.
          if (pendingCount > 0)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onFilterPending,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: amber.withValues(alpha: isDark ? 0.12 : 0.1),
                    border: Border(
                      top: BorderSide(
                        color:
                            amber.withValues(alpha: isDark ? 0.3 : 0.25),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.signature,
                          size: 14, color: amberText),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          pendingCount == 1
                              ? '1 assinatura pendente'
                              : '$pendingCount assinaturas pendentes',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: amberText,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ),
                      Text(
                        'Filtrar',
                        style: TextStyle(
                          color: amberText,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(LucideIcons.chevronRight,
                          size: 13, color: amberText),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Cabeçalho de dia da agenda (data pt-BR + divisor + contagem) ────────────

class _DayHeader extends StatelessWidget {
  final DateTime? date;
  final int count;
  final Color tone;
  final bool first;

  const _DayHeader({
    required this.date,
    required this.count,
    required this.tone,
    this.first = false,
  });

  String _sentence(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    String main;
    String? sub;
    final d = date;
    if (d == null) {
      main = 'Sem data definida';
    } else {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final diff = DateTime(d.year, d.month, d.day).difference(today).inDays;
      final dayFmt = DateFormat(
        d.year == now.year ? "d 'de' MMMM" : "d 'de' MMMM 'de' y",
        'pt_BR',
      );
      final weekday = DateFormat('EEEE', 'pt_BR').format(d);
      if (diff == 0) {
        main = 'Hoje';
        sub = '$weekday, ${dayFmt.format(d)}';
      } else if (diff == 1) {
        main = 'Amanhã';
        sub = '$weekday, ${dayFmt.format(d)}';
      } else if (diff == -1) {
        main = 'Ontem';
        sub = '$weekday, ${dayFmt.format(d)}';
      } else {
        main = _sentence(weekday);
        sub = dayFmt.format(d);
      }
    }

    return Padding(
      padding: EdgeInsets.only(top: first ? 16 : 22, bottom: 12),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: tone.withValues(alpha: isDark ? 0.18 : 0.1),
            ),
            child: Center(
              child: d == null
                  ? Icon(LucideIcons.calendarDays, size: 14, color: tone)
                  : Text(
                      '${d.day}',
                      style: TextStyle(
                        color: tone,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        height: 1.0,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: main,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (sub != null)
                    TextSpan(
                      text: '  ·  $sub',
                      style: TextStyle(
                        color: secondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 11.5,
                      ),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: ThemeHelpers.borderLightColor(context),
            ),
          ),
          Text(
            count == 1 ? '1 visita' : '$count visitas',
            style: TextStyle(
              color: secondary,
              fontWeight: FontWeight.w800,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── FAB "Nova visita" (mesma gramática das fichas de venda) ─────────────────

class _CreateFab extends StatelessWidget {
  const _CreateFab({required this.accent, required this.onTap});
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accent,
      shape: const StadiumBorder(),
      elevation: 6,
      shadowColor: accent.withValues(alpha: 0.4),
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
                'Nova visita',
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

// ─── Aba flush (ícone + rótulo + contagem + sublinhado) ──────────────────────

class _FlushTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color tone;
  final bool selected;
  final VoidCallback onTap;

  const _FlushTab({
    required this.icon,
    required this.label,
    required this.count,
    required this.tone,
    required this.selected,
    required this.onTap,
  });

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

// ─── Chip de status (tint — nunca preenchimento sólido) ──────────────────────

class _StatusChip extends StatelessWidget {
  final String label;
  final Color tone;
  final bool selected;
  final VoidCallback onTap;

  const _StatusChip({
    required this.label,
    required this.tone,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? tone.withValues(alpha: isDark ? 0.18 : 0.11)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? tone.withValues(alpha: 0.5)
                : ThemeHelpers.borderColor(context),
            width: selected ? 1.3 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color:
                selected ? tone : ThemeHelpers.textSecondaryColor(context),
            letterSpacing: -0.1,
          ),
        ),
      ),
    );
  }
}

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
              'Você não tem acesso aos relatórios de visita.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Solicite ao administrador a permissão de visualizar visitas.',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
