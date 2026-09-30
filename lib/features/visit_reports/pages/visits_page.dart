import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_error_state.dart';
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
  /// Código HTTP da falha — sem ele "sem permissão" e "servidor fora do ar"
  /// viravam a mesma mensagem.
  int errorStatus = 0;
  int visible = _VisitsPageState._pageSize;
}

/// Tela **Visitas** com personalidade de AGENDA: spotlight da próxima visita
/// (folhinha de calendário + faixa de assinaturas pendentes clicável) no topo
/// e lista agrupada por dia, com cabeçalhos de data pt-BR e itens em trilho
/// de timeline. Sem hero editorial — a identidade aqui é o calendário.
///
/// Duas portas no menu, como no web (29/09/2026): "Lista de Visitas"
/// (`/visits`, só as próprias, `visit:view`) e "Gestão de Visitas"
/// (`/visit-reports`, toda a empresa, `visit:manage`). No web são duas telas
/// com a MESMA lista e alcance diferente; aqui é uma tela com as duas abas, e
/// [openManagement] decide em qual delas ela abre.
class VisitsPage extends StatefulWidget {
  const VisitsPage({super.key, this.openManagement = false});

  /// Abre direto na visão da empresa (`scope=all`). Sem `visit:manage` a tela
  /// fica nas próprias visitas — o back recusaria o `scope=all` com 403.
  final bool openManagement;

  @override
  State<VisitsPage> createState() => _VisitsPageState();
}

class _VisitsPageState extends State<VisitsPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  // Folga para o "Nova visita" E o botão flutuante do chat (que fica logo
  // acima dele): com 110 o último item ficava sob o botão do chat.
  static const double _kPagePadBottom = 156;
  static const double _kSectionGap = 12;
  static const int _pageSize = 25;

  /// Coluna máxima em tablet/paisagem: a linha de agenda não estica em
  /// 1000dp (a leitura e as ações ficam perto uma da outra).
  static const double _kMaxContentWidth = 820;

  late _VisitScope _activeScope;
  final Map<_VisitScope, _ScopeState> _state = {
    _VisitScope.mine: _ScopeState(),
    _VisitScope.all: _ScopeState(),
  };

  VisitReportFilters _filters = VisitReportFilters.empty;

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _appliedSearch = '';

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

  /// Entra na tela quem vê as próprias visitas (`visit:view`, rota /visits do
  /// web) OU quem gere as da empresa (`visit:manage`, rota /visit-reports do
  /// web, que não cobra `visit:view`).
  bool get _canOpen => _canView || _canManage;

  /// As duas abas só fazem sentido quando os dois alcances estão liberados.
  bool get _showScopeRail => _canView && _canManage;

  @override
  void initState() {
    super.initState();
    _activeScope = _initialScope();
    if (_canOpen) _loadScope(_activeScope);
  }

  /// Escopo de abertura (29/09/2026): a porta "Gestão de Visitas" do menu cai
  /// direto na visão da empresa; quem só tem `visit:manage` também, porque a
  /// aba "Minhas visitas" é a de `visit:view`.
  _VisitScope _initialScope() {
    if (_canManage && (widget.openManagement || !_canView)) {
      return _VisitScope.all;
    }
    return _VisitScope.mine;
  }

  /// Título da barra acompanha o alcance, com os nomes das telas do web.
  String get _pageTitle =>
      _activeScope == _VisitScope.all ? 'Gestão de Visitas' : 'Visitas';

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
        st.errorStatus = 0;
      } else {
        st.error = res.message ?? 'Erro ao carregar visitas';
        st.errorStatus = res.statusCode;
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

  /// Busca local por cliente/endereço/referência/código/corretor/negociação.
  /// Separada do status (30/09/2026) para a régua contar cada estado DENTRO
  /// da busca — tocar em "Aguardando 3" mostra exatamente 3.
  List<VisitReport> _searched(List<VisitReport> items) {
    final q = _appliedSearch.toLowerCase();
    if (q.isEmpty) return items;
    return items.where((r) {
      if (r.clientLabel.toLowerCase().contains(q)) return true;
      if ((r.createdByName ?? '').toLowerCase().contains(q)) return true;
      if ((r.kanbanTaskTitle ?? '').toLowerCase().contains(q)) return true;
      return r.properties.any((p) =>
          p.address.toLowerCase().contains(q) ||
          (p.reference ?? '').toLowerCase().contains(q) ||
          (p.propertyCode ?? '').toLowerCase().contains(q));
    }).toList();
  }

  /// Refino local: status (paridade com o web, que filtra em memória) sobre
  /// a busca.
  List<VisitReport> _byStatus(List<VisitReport> searched) {
    final status = _filters.status;
    if (status == null) return searched;
    return searched.where((r) => r.signatureStatus == status).toList();
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
        content: SingleChildScrollView(
          child: Text(
            'O relatório de visita de ${r.clientLabel} será excluído. '
            'Esta ação não pode ser desfeita.',
            style: const TextStyle(height: 1.4),
          ),
        ),
        actions: [
          // Cancelar NEUTRO: o tema pinta TextButton de vermelho.
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: ThemeHelpers.textSecondaryColor(ctx),
            ),
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
    if (!_canOpen) {
      return AppScaffold(
        title: _pageTitle,
        showBottomNavigation: false,
        body: const _DeniedView(),
      );
    }
    // Coluna centrada com teto de largura (tablet/paisagem). Os filhos ficam
    // direto no ListView — o RefreshIndicator segue com o scroll como filho
    // imediato (LayoutBuilder no meio quebra o puxar-para-atualizar).
    Widget col(Widget child) => Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
            child: child,
          ),
        );

    return AppScaffold(
      title: _pageTitle,
      showBottomNavigation: false,
      body: Stack(
        children: [
          RefreshIndicator(
            color: _accentColor(context),
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.only(
                  top: _kPagePadTop, bottom: _kPagePadBottom),
              children: [
                col(Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: _kPagePadH),
                  child: _buildSpotlight(context),
                )),
                const SizedBox(height: _kSectionGap),
                col(Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: _kPagePadH),
                  child: _buildSearchRow(context),
                )),
                const SizedBox(height: _kSectionGap),
                if (_showScopeRail) col(_buildScopeRail(context)),
                col(Padding(
                  padding: const EdgeInsets.fromLTRB(
                      _kPagePadH, _kSectionGap, _kPagePadH, 0),
                  child: _buildActivePanel(context),
                )),
              ],
            ),
          ),
          // Some com o teclado aberto: em paisagem ele cobriria a busca.
          if (MediaQuery.viewInsetsOf(context).bottom == 0)
            Positioned(
              right: _kPagePadH,
              bottom: 22,
              child: SafeArea(
                child: _CreateFab(
                  accent: _accentColor(context),
                  // Sem `visit:create` o botão fica à vista, apagado, com
                  // cadeado — o toque explica o motivo (antes sumia).
                  locked: !_canCreate,
                  onTap: _canCreate ? _openCreate : _explainCreateLocked,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _explainCreateLocked() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(
        'Registrar visita exige a permissão de criar relatórios de visita. '
        'Peça ao administrador.',
      ),
    ));
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
    // Campo cheio no molde da busca de Imóveis (cinza sólido de campo, sem
    // brilho colorido — sombra difusa não existe no modo claro).
    final fieldFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final hairline = ThemeHelpers.borderColor(context).withValues(alpha: 0.4);
    final hasText = _searchController.text.isNotEmpty;
    final filtersCount = _filters.activeCount;
    final filtersActive = filtersCount > 0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            decoration: BoxDecoration(
              color: fieldFill,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: hairline),
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(LucideIcons.search, size: 18, color: secondary),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    cursorColor: accent,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Cliente, endereço, código ou corretor',
                      hintMaxLines: 1,
                      hintStyle: TextStyle(
                        color: secondary,
                        fontWeight: FontWeight.w500,
                        fontSize: 13.5,
                      ),
                      // O fill vive no Container (o tema global pintaria
                      // um segundo fundo).
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 13),
                      isDense: true,
                    ),
                    onChanged: (v) {
                      _onSearchChanged(v);
                      setState(() {});
                    },
                  ),
                ),
                if (hasText)
                  IconButton(
                    tooltip: 'Limpar busca',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      _searchController.clear();
                      _onSearchChanged('');
                      setState(() {});
                    },
                    icon: Icon(LucideIcons.x, size: 16, color: secondary),
                  )
                else
                  const SizedBox(width: 8),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Filtros do modal padrão CRM, com a CONTAGEM de filtros ligados (o
        // ponto sozinho não dizia quantos nem quais).
        Tooltip(
          message: !filtersActive
              ? 'Filtros'
              : filtersCount == 1
                  ? '1 filtro ligado'
                  : '$filtersCount filtros ligados',
          child: Material(
            color: filtersActive
                ? accent.withValues(alpha: isDark ? 0.16 : 0.09)
                : fieldFill,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: filtersActive ? accent.withValues(alpha: 0.5) : hairline,
                width: filtersActive ? 1.4 : 1,
              ),
            ),
            child: InkWell(
              onTap: _openFilters,
              customBorder: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Center(
                      child: Icon(
                        LucideIcons.slidersHorizontal,
                        size: 19,
                        color: filtersActive
                            ? visitInk(context, accent)
                            : secondary,
                      ),
                    ),
                    if (filtersActive)
                      Positioned(
                        right: 5,
                        top: 5,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 16),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$filtersCount',
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
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

  // ─── Régua de estado com contagem ────────────────────────────────────────

  /// Estado em palavra COM a contagem (30/09/2026), como a tela aprovada do
  /// web: o número decide para onde o corretor olha primeiro. Antes eram
  /// pílulas soltas numa faixa rolável ("Todas / Aguardando / …") sem
  /// número. Conta dentro da busca; tocar filtra (tocar de novo volta para
  /// Todas). 4 colunas quando cabem (a largura é lida já com a escala do
  /// texto), 2×2 em 320dp ou com fonte grande.
  Widget _buildStatusRuler(BuildContext context, List<VisitReport> searched) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final allTone = _scopeColor(context, _activeScope);

    int count(VisitSignatureStatus s) =>
        searched.where((r) => r.signatureStatus == s).length;

    final segments = <Widget>[
      _StatusSegment(
        label: 'Todas',
        count: searched.length,
        tone: allTone,
        selected: _filters.status == null,
        onTap: () => _setStatusChip(null),
      ),
      _StatusSegment(
        label: 'Aguardando',
        count: count(VisitSignatureStatus.pending),
        tone: amber,
        selected: _filters.status == VisitSignatureStatus.pending,
        onTap: () => _toggleStatus(VisitSignatureStatus.pending),
      ),
      _StatusSegment(
        label: 'Assinadas',
        count: count(VisitSignatureStatus.signed),
        tone: green,
        selected: _filters.status == VisitSignatureStatus.signed,
        onTap: () => _toggleStatus(VisitSignatureStatus.signed),
      ),
      _StatusSegment(
        label: 'Expiradas',
        count: count(VisitSignatureStatus.expired),
        tone: neutral,
        selected: _filters.status == VisitSignatureStatus.expired,
        onTap: () => _toggleStatus(VisitSignatureStatus.expired),
      ),
    ];

    const gap = 6.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final cols = constraints.maxWidth / scale >= 320 ? 4 : 2;
        Widget row(List<Widget> items) => IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const SizedBox(width: gap),
                    Expanded(child: items[i]),
                  ],
                ],
              ),
            );
        if (cols == 4) return row(segments);
        return Column(
          children: [
            row(segments.sublist(0, 2)),
            const SizedBox(height: gap),
            row(segments.sublist(2)),
          ],
        );
      },
    );
  }

  void _toggleStatus(VisitSignatureStatus status) {
    _setStatusChip(_filters.status == status ? null : status);
  }

  // ─── Painel ativo ────────────────────────────────────────────────────────

  Widget _buildActivePanel(BuildContext context) {
    final st = _state[_activeScope]!;
    final searched = _searched(st.items);
    final refined = _byStatus(searched);

    Widget child;
    if (st.loading && st.items.isEmpty) {
      child = _buildSkeleton();
    } else if (st.error != null && st.items.isEmpty) {
      child = _buildError(context, st);
    } else if (refined.isEmpty) {
      child = _buildEmpty(context, st);
    } else {
      child = _buildAgenda(context, st, refined);
    }

    return Column(
      key: ValueKey('panel-${_activeScope.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A atualização falhou mas há lista: avisa sem apagar nada.
        if (st.error != null && st.items.isNotEmpty)
          _buildRefreshFailed(context),
        if (st.items.isNotEmpty) _buildStatusRuler(context, searched),
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
    final pendingByDay = <String, int>{};
    for (final r in ordered) {
      final k = _dayKey(r.visitDate);
      counts.update(k, (v) => v + 1, ifAbsent: () => 1);
      if (r.signatureStatus == VisitSignatureStatus.pending) {
        pendingByDay.update(k, (v) => v + 1, ifAbsent: () => 1);
      }
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
          pending: pendingByDay[key] ?? 0,
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
          canGenerateLink: _canUpdate,
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

    // Rodapé da lista: quantas estão na tela, de quantas, e o próximo passo.
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final remaining = ordered.length - visible.length;
    children.add(
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          remaining > 0
              ? 'Mostrando ${visible.length} de ${ordered.length} visitas'
              : ordered.length == 1
                  ? '1 visita · fim da lista'
                  : '${ordered.length} visitas · fim da lista',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: secondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
    if (remaining > 0) {
      final accent = _accentColor(context);
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Center(
            child: OutlinedButton.icon(
              onPressed: () => setState(() => st.visible += _pageSize),
              style: OutlinedButton.styleFrom(
                foregroundColor: visitInk(context, accent),
                side: BorderSide(color: accent.withValues(alpha: 0.45)),
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(LucideIcons.chevronDown, size: 16),
              label: Text(
                remaining > _pageSize
                    ? 'Mostrar mais $_pageSize'
                    : 'Mostrar mais $remaining',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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

  /// Skeleton fiel à agenda: régua de estado, cabeçalho de dia (bolha de
  /// data + título + filete) e itens em trilho (nó circular + conteúdo).
  Widget _buildSkeleton() {
    Widget header({bool first = false}) => Padding(
          padding: EdgeInsets.only(top: first ? 16 : 22, bottom: 12),
          child: const Row(
            children: [
              SkeletonBox(width: 32, height: 32, borderRadius: 10),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonText(width: 90, height: 13),
                    SizedBox(height: 5),
                    SkeletonText(width: 160, height: 10),
                  ],
                ),
              ),
            ],
          ),
        );

    Widget row() => const Padding(
          padding: EdgeInsets.only(bottom: 18, top: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 28, height: 28, borderRadius: 999),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonText(width: 150, height: 16, borderRadius: 999),
                    SizedBox(height: 9),
                    SkeletonText(width: double.infinity, height: 14),
                    SizedBox(height: 6),
                    SkeletonText(width: 150, height: 12),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        SkeletonBox(width: 140, height: 34, borderRadius: 10),
                        SizedBox(width: 8),
                        SkeletonText(width: 60, height: 12),
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
        const Row(
          children: [
            Expanded(child: SkeletonBox(height: 52, borderRadius: 12)),
            SizedBox(width: 6),
            Expanded(child: SkeletonBox(height: 52, borderRadius: 12)),
            SizedBox(width: 6),
            Expanded(child: SkeletonBox(height: 52, borderRadius: 12)),
            SizedBox(width: 6),
            Expanded(child: SkeletonBox(height: 52, borderRadius: 12)),
          ],
        ),
        header(first: true),
        row(),
        row(),
        header(),
        row(),
      ],
    );
  }

  /// Vazio que ENSINA (30/09/2026): diz por que está vazio e oferece a saída
  /// certa — limpar a busca, limpar os filtros, ver todas ou registrar.
  Widget _buildEmpty(BuildContext context, _ScopeState st) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = _scopeColor(context, _activeScope);
    final ink = visitInk(context, tone);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hasSearch = _appliedSearch.trim().isNotEmpty;
    final status = _filters.status;
    final onlyStatus = status != null && !_filters.hasBackendFilters;
    final hasBackendFilters = _filters.hasBackendFilters;
    final isTeam = _activeScope == _VisitScope.all;

    String statusWord(VisitSignatureStatus s) {
      switch (s) {
        case VisitSignatureStatus.pending:
          return 'aguardando assinatura';
        case VisitSignatureStatus.signed:
          return 'assinada';
        case VisitSignatureStatus.expired:
          return 'com link expirado';
        case VisitSignatureStatus.unknown:
          return 'nesse estado';
      }
    }

    late final IconData icon;
    late final String title;
    late final String body;
    String? actionLabel;
    IconData? actionIcon;
    VoidCallback? onAction;
    var primary = false;

    if (hasSearch) {
      icon = LucideIcons.searchX;
      title = 'Nada encontrado';
      body = 'Nenhuma visita corresponde a "${_appliedSearch.trim()}". '
          'Busque pelo nome do cliente, pelo endereço, pelo código do imóvel '
          'ou pelo corretor.';
      actionLabel = 'Limpar busca';
      actionIcon = LucideIcons.x;
      onAction = () {
        _searchController.clear();
        _onSearchChanged('');
        setState(() {});
      };
    } else if (onlyStatus && st.items.isNotEmpty) {
      icon = LucideIcons.listFilter;
      title = 'Nenhuma visita ${statusWord(status)}';
      body = 'As outras visitas continuam na lista — toque em "Todas" na '
          'régua acima ou no botão abaixo.';
      actionLabel = 'Ver todas';
      actionIcon = LucideIcons.list;
      onAction = () => _setStatusChip(null);
    } else if (hasBackendFilters) {
      icon = LucideIcons.filterX;
      title = 'Nada com esses filtros';
      body = 'Nenhuma visita bate com o cliente ou o período escolhidos. '
          'Ajuste nos filtros ou limpe tudo.';
      actionLabel = 'Limpar filtros';
      actionIcon = LucideIcons.filterX;
      onAction = () => _applyFilters(VisitReportFilters.empty);
    } else if (isTeam) {
      icon = LucideIcons.calendarDays;
      title = 'Nenhuma visita da equipe';
      body = 'Quando os corretores registrarem visitas, elas aparecem aqui '
          'agrupadas por dia, com o estado da assinatura de cada uma.';
    } else {
      icon = LucideIcons.calendarDays;
      title = 'Agenda vazia';
      body = _canCreate
          ? 'Registre a visita depois de mostrar os imóveis: o cliente recebe '
              'um link para conferir e assinar, e o estado aparece aqui.'
          : 'As visitas registradas aparecem aqui, agrupadas por dia. '
              'Registrar visita exige a permissão de criar relatórios — '
              'peça ao administrador.';
      if (_canCreate) {
        actionLabel = 'Registrar visita';
        actionIcon = LucideIcons.plus;
        onAction = _openCreate;
        primary = true;
      }
    }

    final Widget? action;
    if (actionLabel == null || onAction == null) {
      action = null;
    } else if (primary) {
      action = FilledButton.icon(
        onPressed: onAction,
        icon: Icon(actionIcon, size: 16),
        label: Text(actionLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: FilledButton.styleFrom(
          backgroundColor: _accentColor(context),
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
      );
    } else {
      // Saída do vazio (limpar/ver todas) é navegação: neutra.
      action = OutlinedButton.icon(
        onPressed: onAction,
        icon: Icon(actionIcon, size: 16),
        label: Text(actionLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: OutlinedButton.styleFrom(
          foregroundColor: ThemeHelpers.textColor(context),
          side: BorderSide(color: ThemeHelpers.borderColor(context)),
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 4),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tone.withValues(alpha: isDark ? 0.16 : 0.09),
              border: Border.all(color: tone.withValues(alpha: 0.32)),
            ),
            child: Icon(icon, color: ink, size: 28),
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
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondary,
                height: 1.4,
              ),
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 16),
            action,
          ],
        ],
      ),
    );
  }

  /// Atualização falhou com lista na tela: faixa curta com a causa e
  /// "Tentar de novo" (antes a falha passava em silêncio).
  Widget _buildRefreshFailed(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: isDark ? 0.12 : 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.triangleAlert,
            size: 16,
            color: visitInk(context, amber),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Não deu para atualizar agora. Esta é a última lista carregada.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
          TextButton(
            onPressed: _refresh,
            style: TextButton.styleFrom(foregroundColor: textColor),
            child: const Text('Tentar de novo', maxLines: 1),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, _ScopeState st) {
    return AppErrorState.fromApi(
      message: st.error,
      statusCode: st.errorStatus,
      onRetry: () => _loadScope(_activeScope, refresh: true),
      dense: true,
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
    // Texto colorido pela tinta legível (≥ 4,5:1): o warningText (#D97706)
    // dava 3,2:1 no branco e o violeta da Gestão 4,2:1 no rótulo de 11sp.
    final amberText = visitInk(context, amber);
    final blue = visitInk(
      context,
      isDark ? AppColors.status.blueDarkMode : AppColors.status.blue,
    );
    final toneInk = visitInk(context, tone);

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
                          // Wrap: a 320dp/130% "Em 12 dias" desce inteiro
                          // em vez de cortar "Próxima vis…".
                          Wrap(
                            spacing: 7,
                            runSpacing: 3,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                n != null
                                    ? 'Próxima visita'
                                    : 'Agenda de visitas',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: toneInk,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              if (proximity != null)
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
                                    maxLines: 1,
                                    style: TextStyle(
                                      color: proximityTone,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.2,
                                      height: 1.0,
                                    ),
                                  ),
                                ),
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

// ─── Cabeçalho de dia da agenda (data pt-BR + contagem + filete) ────────────

/// Cabeçalho do dia (30/09/2026): "Hoje" / "Quinta" em destaque, a data por
/// extenso embaixo e a contagem do dia ("3 visitas · 1 aguardando") à
/// direita, com filete de largura inteira por baixo. Antes a data dividia a
/// linha meio a meio com um filete decorativo (Flexible + Expanded) e ficava
/// cortada em qualquer largura ("Hoje · quarta-f…").
class _DayHeader extends StatelessWidget {
  final DateTime? date;
  final int count;
  final int pending;
  final Color tone;
  final bool first;

  const _DayHeader({
    required this.date,
    required this.count,
    required this.tone,
    this.pending = 0,
    this.first = false,
  });

  String _sentence(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final ink = visitInk(context, tone);
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;

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

    return Container(
      margin: EdgeInsets.only(top: first ? 14 : 20, bottom: 12),
      padding: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: tone.withValues(alpha: isDark ? 0.18 : 0.1),
            ),
            child: Center(
              child: d == null
                  ? Icon(LucideIcons.calendarDays, size: 15, color: ink)
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Text(
                          '${d.day}',
                          maxLines: 1,
                          style: TextStyle(
                            color: ink,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          // Linha 1: o dia + "N aguardando" (âmbar legível — é o que pede
          // ação) e, à direita, a contagem curta. Linha 2: a data por
          // extenso na largura toda (a 320dp/130% cabe inteira).
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: main,
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                letterSpacing: -0.2,
                              ),
                            ),
                            if (pending > 0)
                              TextSpan(
                                text: '  ·  $pending aguardando',
                                style: TextStyle(
                                  color: visitInk(context, amber),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11.5,
                                ),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(height: 1.2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      count == 1 ? '1 visita' : '$count visitas',
                      maxLines: 1,
                      style: TextStyle(
                        color: secondary,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                if (sub != null)
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: secondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 11.5,
                      height: 1.25,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── FAB "Nova visita" (mesma gramática das fichas de venda) ─────────────────

class _CreateFab extends StatelessWidget {
  const _CreateFab({
    required this.accent,
    required this.onTap,
    this.locked = false,
  });
  final Color accent;
  final VoidCallback onTap;

  /// Sem permissão: pílula neutra com cadeado (o toque explica o motivo).
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color fill;
    final Color fg;
    if (locked) {
      fill = isDark
          ? AppColors.background.backgroundTertiaryDarkMode
          : AppColors.background.backgroundTertiary;
      fg = ThemeHelpers.textSecondaryColor(context);
    } else {
      fill = accent;
      fg = Colors.white;
    }
    return Semantics(
      button: true,
      label: locked ? 'Nova visita, bloqueado' : 'Nova visita',
      excludeSemantics: true,
      child: Material(
        color: fill,
        shape: locked
            ? StadiumBorder(
                side: BorderSide(color: ThemeHelpers.borderColor(context)),
              )
            : const StadiumBorder(),
        elevation: locked ? 1 : 6,
        shadowColor: locked
            ? Colors.black.withValues(alpha: 0.08)
            : accent.withValues(alpha: 0.4),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  locked ? LucideIcons.lock : Icons.add_rounded,
                  color: fg,
                  size: locked ? 17 : 22,
                ),
                const SizedBox(width: 8),
                Text(
                  'Nova visita',
                  maxLines: 1,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    letterSpacing: 0.2,
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
    // Rótulo na tinta legível do tom (o violeta puro dava 4,2:1 no branco);
    // o sublinhado segue no tom.
    final fg = selected
        ? visitInk(context, tone)
        : ThemeHelpers.textSecondaryColor(context);
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
                                ? fg
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

// ─── Segmento da régua de estado (número + rótulo) ──────────────────────────

/// Um estado da régua: o número em destaque (tinta legível do tom quando há
/// algum, cinza quando zero), o ponto do tom e o rótulo. Selecionado ganha
/// fundo e borda no tom. Número e rótulo encolhem em vez de estourar.
class _StatusSegment extends StatelessWidget {
  final String label;
  final int count;
  final Color tone;
  final bool selected;
  final VoidCallback onTap;

  const _StatusSegment({
    required this.label,
    required this.count,
    required this.tone,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final ink = visitInk(context, tone);
    final idleFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;

    return Semantics(
      button: true,
      selected: selected,
      label: '$label: $count',
      excludeSemantics: true,
      child: Material(
        color: selected
            ? tone.withValues(alpha: isDark ? 0.18 : 0.10)
            : idleFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected
                ? tone.withValues(alpha: 0.6)
                : ThemeHelpers.borderColor(context).withValues(alpha: 0.4),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '$count',
                          maxLines: 1,
                          style: TextStyle(
                            color: count > 0 ? ink : secondary,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            height: 1.05,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: tone,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: selected
                          ? ThemeHelpers.textColor(context)
                          : secondary,
                      fontSize: 11.5,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      letterSpacing: -0.1,
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

/// Sem acesso (30/09/2026): diz o que falta e quem libera, e rola em tela
/// baixa (paisagem) — antes era um Column centrado que podia estourar.
class _DeniedView extends StatelessWidget {
  const _DeniedView();
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final purple =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: purple.withValues(alpha: isDark ? 0.16 : 0.1),
                      ),
                      child: Icon(
                        LucideIcons.lock,
                        size: 26,
                        color: visitInk(context, purple),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Você não tem acesso às visitas',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: ThemeHelpers.textColor(context),
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Para ver as suas visitas é preciso a permissão de '
                      'visualizar relatórios de visita; para ver as da '
                      'empresa, a de gerir visitas.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: secondary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.background.backgroundTertiaryDarkMode
                            : AppColors.background.backgroundTertiary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.userRound,
                            size: 15,
                            color: secondary,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Quem libera: o administrador da empresa.',
                              style: TextStyle(
                                color: ThemeHelpers.textColor(context),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
