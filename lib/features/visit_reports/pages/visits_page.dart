import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
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

/// Tela **Relatórios de Visita** — mesmo DNA refinado de Comissões/Aprovações:
/// hero editorial com KPIs, busca flush, abas flush (Minhas · Gestão), chips
/// de status e cards com ações no próprio item (WhatsApp / link / editar).
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

  // ─── Dados ───────────────────────────────────────────────────────────────

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
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minHeight: constraints.maxHeight),
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
                      if (_canManage) _buildScopeRail(context),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(_kPagePadH,
                            _kSectionGap, _kPagePadH, _kPagePadBottom),
                        child: _buildActivePanel(context),
                      ),
                    ],
                  ),
                ),
              ),
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

  // ─── Hero editorial ──────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accentColor(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;

    final st = _state[_activeScope]!;
    final items = st.items;
    final total = items.length;
    final pending = items
        .where((r) => r.signatureStatus == VisitSignatureStatus.pending)
        .length;
    final signed = items
        .where((r) => r.signatureStatus == VisitSignatureStatus.signed)
        .length;
    final expired = items
        .where((r) => r.signatureStatus == VisitSignatureStatus.expired)
        .length;

    final dot = pending > 0 ? amber : emerald;
    final subtitle = total == 0
        ? 'Registre as visitas e envie o link de assinatura ao cliente.'
        : pending > 0
            ? '$pending aguardando assinatura · $signed assinado${signed == 1 ? '' : 's'}'
            : 'Tudo assinado — nenhuma pendência de assinatura.';

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
                'RELATÓRIOS DE VISITA',
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
                st.loaded ? '$total' : '—',
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
                  total == 1 ? 'visita' : 'visitas',
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
          _buildKpiStrip(context,
              pending: pending,
              signed: signed,
              expired: expired,
              amber: amber,
              emerald: emerald,
              loading: !st.loaded),
        ],
      ),
    );
  }

  Widget _buildKpiStrip(
    BuildContext context, {
    required int pending,
    required int signed,
    required int expired,
    required Color amber,
    required Color emerald,
    required bool loading,
  }) {
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final divider = ThemeHelpers.borderColor(context).withValues(alpha: 0.45);
    final blocks = <Widget>[
      _heroKpiBlock(context, LucideIcons.clock3, 'AGUARDANDO',
          loading ? '—' : '$pending', 'assinatura pendente', amber),
      _heroKpiBlock(context, LucideIcons.circleCheckBig, 'ASSINADOS',
          loading ? '—' : '$signed', 'confirmados pelo cliente', emerald),
      _heroKpiBlock(context, LucideIcons.circleAlert, 'EXPIRADOS',
          loading ? '—' : '$expired', 'link vencido', neutral),
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
      child = _buildList(context, st, refined);
    }

    return Column(
      key: ValueKey('panel-${_activeScope.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPanelHeader(context),
        const SizedBox(height: 12),
        _buildStatusChips(context),
        const SizedBox(height: 14),
        child,
      ],
    ).animate(key: ValueKey('panel-${_activeScope.name}')).fadeIn(
          duration: 240.ms,
        );
  }

  Widget _buildPanelHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = _scopeColor(context, _activeScope);
    final meta = _activeScope == _VisitScope.mine
        ? (
            icon: LucideIcons.clipboardList,
            eyebrow: 'MINHAS VISITAS',
            title: 'Relatórios que você criou',
            hint:
                'Registre a visita, gere o link e envie ao cliente para assinar.',
          )
        : (
            icon: LucideIcons.users,
            eyebrow: 'GESTÃO',
            title: 'Todas as visitas da empresa',
            hint: 'Visão completa dos relatórios de todos os corretores.',
          );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: tone.withValues(alpha: isDark ? 0.2 : 0.12),
          ),
          child: Icon(meta.icon, color: tone, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: tone,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: tone.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    meta.eyebrow,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                meta.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                meta.hint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  height: 1.32,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildList(
    BuildContext context,
    _ScopeState st,
    List<VisitReport> refined,
  ) {
    final visible = refined.take(st.visible).toList();
    final showBroker = _activeScope == _VisitScope.all;
    var animIndex = 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in visible)
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
        if (refined.length > st.visible)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Center(
              child: OutlinedButton.icon(
                onPressed: () =>
                    setState(() => st.visible += _pageSize),
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
                  'Carregar mais (${refined.length - st.visible})',
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ─── Estados ─────────────────────────────────────────────────────────────

  /// Skeleton fiel ao layout do `VisitReportCard` (glyph + pill + duas linhas
  /// + coluna de data + faixa de ações).
  Widget _buildSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(
        5,
        (_) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 44, height: 44, borderRadius: 13),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SkeletonText(width: 96, height: 16, borderRadius: 999),
                        SizedBox(height: 9),
                        SkeletonText(width: double.infinity, height: 14),
                        SizedBox(height: 6),
                        SkeletonText(width: 150, height: 12),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: const [
                      SkeletonText(width: 58, height: 16),
                      SizedBox(height: 6),
                      SkeletonText(width: 44, height: 10),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: const [
                  SizedBox(width: 56),
                  SkeletonText(width: 74, height: 12),
                  SizedBox(width: 14),
                  SkeletonText(width: 74, height: 12),
                ],
              ),
            ],
          ),
        ),
      ),
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
                LucideIcons.clipboardList,
                'Nenhuma visita ainda',
                'Registre a primeira visita e envie o link de assinatura ao cliente.',
              );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 4),
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
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 4),
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
