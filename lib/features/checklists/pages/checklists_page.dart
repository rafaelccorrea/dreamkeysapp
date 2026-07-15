import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/checklist_models.dart';
import '../services/checklist_service.dart';
import '../widgets/checklist_card.dart';
import '../widgets/checklist_filters_drawer.dart';

/// Aba ativa da tela de checklists.
enum _ChecklistTab { open, completed, all }

/// Tela **Checklists** — processos de venda/aluguel com itens marcáveis.
/// Mesmo DNA refinado de Comissões: hero editorial com KPIs, busca flush,
/// abas flush com contagem e painel com cabeçalho (eyebrow + título + hint).
/// O backend devolve a lista completa (sem paginação); busca e filtros são
/// aplicados no cliente, em paridade com o web.
class ChecklistsPage extends StatefulWidget {
  const ChecklistsPage({super.key});

  @override
  State<ChecklistsPage> createState() => _ChecklistsPageState();
}

class _ChecklistsPageState extends State<ChecklistsPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 104;
  static const double _kSectionGap = 12;

  static const _tabs = [
    _ChecklistTab.open,
    _ChecklistTab.completed,
    _ChecklistTab.all,
  ];

  _ChecklistTab _activeTab = _ChecklistTab.open;

  List<Checklist> _all = const [];
  bool _loading = true;
  String? _error;

  // Filtros do modal (aplicados no cliente).
  ChecklistType? _filterType;
  ChecklistStatus? _filterStatus;

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _appliedSearch = '';
  bool _searchFocused = false;

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

  // ─── Cores ───────────────────────────────────────────────────────────────

  Color _accentColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
  }

  Color _tabColor(BuildContext context, _ChecklistTab tab) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (tab) {
      case _ChecklistTab.open:
        return isDark
            ? AppColors.status.warningDarkMode
            : AppColors.status.warning;
      case _ChecklistTab.completed:
        return isDark
            ? AppColors.status.greenDarkMode
            : AppColors.status.green;
      case _ChecklistTab.all:
        return _accentColor(context);
    }
  }

  // ─── Dados ───────────────────────────────────────────────────────────────

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final res = await ChecklistService.instance.getChecklists();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _all = res.data!;
        _error = null;
      } else {
        _error = res.message ?? 'Erro ao carregar checklists';
      }
    });
  }

  /// Lista após busca + filtros do modal (antes da aba).
  List<Checklist> get _filtered {
    final q = _appliedSearch.trim().toLowerCase();
    return _all.where((c) {
      if (_filterType != null && c.type != _filterType) return false;
      if (_filterStatus != null && c.status != _filterStatus) return false;
      if (q.isEmpty) return true;
      return (c.propertyTitle ?? '').toLowerCase().contains(q) ||
          (c.propertyCode ?? '').toLowerCase().contains(q) ||
          (c.clientName ?? '').toLowerCase().contains(q) ||
          c.type.label.toLowerCase().contains(q);
    }).toList();
  }

  List<Checklist> _forTab(_ChecklistTab tab) {
    final base = _filtered;
    switch (tab) {
      case _ChecklistTab.open:
        return base.where((c) => c.status.isOpen).toList();
      case _ChecklistTab.completed:
        return base
            .where((c) => c.status == ChecklistStatus.completed)
            .toList();
      case _ChecklistTab.all:
        return base;
    }
  }

  int get _activeFilterCount =>
      (_filterType != null ? 1 : 0) + (_filterStatus != null ? 1 : 0);

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
      builder: (ctx) => ChecklistFiltersDrawer(
        initialType: _filterType,
        initialStatus: _filterStatus,
        onApply: (type, status) {
          setState(() {
            _filterType = type;
            _filterStatus = status;
          });
        },
        onClear: () {
          setState(() {
            _filterType = null;
            _filterStatus = null;
          });
        },
      ),
    );
  }

  Future<void> _openCreate() async {
    await Navigator.of(context).pushNamed('/checklists/create');
    if (mounted) _load(silent: true);
  }

  Future<void> _openDetails(Checklist c) async {
    // Recarrega sempre ao voltar — itens podem ter sido marcados no detalhe.
    await Navigator.of(context).pushNamed('/checklists/${c.id}');
    if (mounted) _load(silent: true);
  }

  Future<void> _confirmDelete(Checklist c) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover checklist'),
        content: Text(
          'Tem certeza que deseja remover o checklist de '
          '"${(c.propertyTitle ?? '').trim().isNotEmpty ? c.propertyTitle!.trim() : 'imóvel'}"? '
          'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final res = await ChecklistService.instance.delete(c.id);
    if (!mounted) return;
    if (res.success) {
      setState(() => _all = _all.where((x) => x.id != c.id).toList());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Checklist removido com sucesso')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message ?? 'Erro ao remover checklist'),
          backgroundColor: AppColors.status.error,
        ),
      );
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final accent = _accentColor(context);
    return AppScaffold(
      title: 'Checklists',
      showBottomNavigation: false,
      body: Stack(
        children: [
          RefreshIndicator(
            color: accent,
            onRefresh: () => _load(silent: true),
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
                      _buildTabsRail(context),
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
          Positioned(
            right: 16,
            bottom: 24,
            child: FloatingActionButton.extended(
              heroTag: 'checklists-fab',
              onPressed: _openCreate,
              backgroundColor: accent,
              foregroundColor: Colors.white,
              elevation: 3,
              icon: const Icon(LucideIcons.plus, size: 19),
              label: const Text(
                'Novo checklist',
                style: TextStyle(fontWeight: FontWeight.w800),
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
    final blue = isDark ? AppColors.status.infoDarkMode : AppColors.status.info;

    final total = _all.length;
    final open = _all.where((c) => c.status.isOpen).length;
    final completed =
        _all.where((c) => c.status == ChecklistStatus.completed).length;
    final avgPct = _all.isEmpty
        ? 0
        : (_all
                    .map((c) => c.stats.completionPercentage)
                    .fold<double>(0, (a, b) => a + b) /
                _all.length)
            .round();

    final dot = open > 0 ? amber : emerald;
    final subtitle = total == 0
        ? 'Crie checklists para acompanhar vendas e aluguéis passo a passo.'
        : open > 0
            ? '$open em aberto · progresso médio de $avgPct%'
            : 'Tudo concluído — nenhum processo em aberto.';

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
                'CHECKLISTS',
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
                _loading && _all.isEmpty ? '—' : '$total',
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
                  total == 1 ? 'processo' : 'processos',
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
              context, open, completed, avgPct, amber, emerald, blue),
        ],
      ),
    );
  }

  Widget _buildKpiStrip(BuildContext context, int open, int completed,
      int avgPct, Color amber, Color emerald, Color blue) {
    final divider = ThemeHelpers.borderColor(context).withValues(alpha: 0.45);
    final blocks = <Widget>[
      _heroKpiBlock(context, LucideIcons.hourglass, 'EM ABERTO', '$open',
          'pendentes e ativos', amber),
      _heroKpiBlock(context, LucideIcons.circleCheckBig, 'CONCLUÍDOS',
          '$completed', 'processos fechados', emerald),
      _heroKpiBlock(context, LucideIcons.listChecks, 'PROGRESSO', '$avgPct%',
          'média dos itens', blue),
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
              _loading && _all.isEmpty ? '—' : value,
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

  // ─── Busca flush + botão de filtros ──────────────────────────────────────

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
    final filterCount = _activeFilterCount;
    final filterActive = filterCount > 0;

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
                        hintText: 'Buscar por imóvel, cliente…',
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
        // Botão de filtros (badge com contagem quando ativo).
        InkWell(
          onTap: _openFilters,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: filterActive
                  ? accent.withValues(alpha: isDark ? 0.18 : 0.1)
                  : cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: filterActive
                    ? accent.withValues(alpha: 0.5)
                    : borderColor,
                width: filterActive ? 1.4 : 1,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  LucideIcons.slidersHorizontal,
                  size: 19,
                  color: filterActive ? accent : secondary,
                ),
                if (filterActive)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(3.5),
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$filterCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          height: 1.0,
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

  // ─── Abas flush ──────────────────────────────────────────────────────────

  Widget _buildTabsRail(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: _kPagePadH - 8),
      child: Row(
        children: [
          for (final tab in _tabs)
            Expanded(
              child: _FlushTab(
                icon: _tabIcon(tab),
                label: _tabLabel(tab),
                count: _forTab(tab).length,
                tone: _tabColor(context, tab),
                selected: _activeTab == tab,
                onTap: () => setState(() => _activeTab = tab),
              ),
            ),
        ],
      ),
    );
  }

  IconData _tabIcon(_ChecklistTab tab) {
    switch (tab) {
      case _ChecklistTab.open:
        return LucideIcons.hourglass;
      case _ChecklistTab.completed:
        return LucideIcons.circleCheckBig;
      case _ChecklistTab.all:
        return LucideIcons.listChecks;
    }
  }

  String _tabLabel(_ChecklistTab tab) {
    switch (tab) {
      case _ChecklistTab.open:
        return 'Em aberto';
      case _ChecklistTab.completed:
        return 'Concluídos';
      case _ChecklistTab.all:
        return 'Todos';
    }
  }

  // ─── Painel ativo ────────────────────────────────────────────────────────

  ({IconData icon, String eyebrow, String title, String hint}) _panelMeta(
      _ChecklistTab tab) {
    switch (tab) {
      case _ChecklistTab.open:
        return (
          icon: LucideIcons.hourglass,
          eyebrow: 'EM ABERTO',
          title: 'Processos em andamento',
          hint: 'Checklists pendentes ou ativos — toque para marcar itens.',
        );
      case _ChecklistTab.completed:
        return (
          icon: LucideIcons.circleCheckBig,
          eyebrow: 'CONCLUÍDOS',
          title: 'Processos finalizados',
          hint: 'Tudo que já foi fechado, do mais recente ao mais antigo.',
        );
      case _ChecklistTab.all:
        return (
          icon: LucideIcons.listChecks,
          eyebrow: 'TODOS',
          title: 'Todos os checklists',
          hint: 'Sua lista completa, incluindo pulados e cancelados.',
        );
    }
  }

  Widget _buildActivePanel(BuildContext context) {
    final items = _forTab(_activeTab);
    Widget child;
    if (_loading && _all.isEmpty) {
      child = _buildSkeleton();
    } else if (_error != null && _all.isEmpty) {
      child = _buildError(context, _error!);
    } else if (items.isEmpty) {
      child = _buildEmpty(context, _activeTab);
    } else {
      var animIndex = 0;
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in items)
            ChecklistCard(
              checklist: c,
              onTap: () => _openDetails(c),
              onDelete: () => _confirmDelete(c),
            ).animate(key: ValueKey('cl-${c.id}')).fadeIn(
                  delay:
                      Duration(milliseconds: 30 * (animIndex++).clamp(0, 12)),
                  duration: 220.ms,
                ),
        ],
      );
    }

    final meta = _panelMeta(_activeTab);
    return Column(
      key: ValueKey('panel-${_activeTab.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPanelHeader(context, meta, _tabColor(context, _activeTab)),
        const SizedBox(height: 14),
        child,
      ],
    ).animate(key: ValueKey('panel-${_activeTab.name}')).fadeIn(
          duration: 240.ms,
        );
  }

  Widget _buildPanelHeader(
      BuildContext context,
      ({IconData icon, String eyebrow, String title, String hint}) meta,
      Color tone) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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

  // ─── Estados ─────────────────────────────────────────────────────────────

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
                    SizedBox(height: 12),
                    SkeletonText(
                        width: double.infinity, height: 5, borderRadius: 999),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, _ChecklistTab tab) {
    final theme = Theme.of(context);
    final tone = _tabColor(context, tab);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hasQuery = _appliedSearch.trim().isNotEmpty || _activeFilterCount > 0;
    final (icon, title, body) = hasQuery
        ? (
            LucideIcons.searchX,
            'Nada encontrado',
            'Nenhum checklist corresponde à busca ou aos filtros aplicados.',
          )
        : switch (tab) {
            _ChecklistTab.open => (
                LucideIcons.partyPopper,
                'Nada em aberto',
                'Você não tem processos aguardando conclusão.',
              ),
            _ChecklistTab.completed => (
                LucideIcons.circleCheckBig,
                'Nenhum concluído ainda',
                'Quando um checklist for finalizado, ele aparece aqui.',
              ),
            _ChecklistTab.all => (
                LucideIcons.listChecks,
                'Sem checklists',
                'Toque em "Novo checklist" para acompanhar uma venda ou aluguel passo a passo.',
              ),
          };
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
            onPressed: () => _load(),
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Tentar novamente'),
          ),
        ],
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
