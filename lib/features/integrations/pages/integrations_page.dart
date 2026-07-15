import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/integration_model.dart';
import '../services/integrations_service.dart';
import '../widgets/integration_card.dart';
import '../widgets/integration_progress_ring.dart';

/// Filtro do hub (paridade com Todas/Conectadas/Pendentes do web).
enum _HubFilter { all, connected, pending }

/// **Central de Integrações** — hub mobile do `/integrations` do painel web.
/// Hero flush com anel "X/Y ativas", busca, abas flush com sublinhado
/// (Todas/Conectadas/Pendentes) e cards agrupados por categoria. Cada card
/// abre o detalhe da integração (`/integrations/:key`).
class IntegrationsPage extends StatefulWidget {
  const IntegrationsPage({super.key});

  @override
  State<IntegrationsPage> createState() => _IntegrationsPageState();
}

class _IntegrationsPageState extends State<IntegrationsPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const double _kSectionGap = 12;

  final IntegrationsService _service = IntegrationsService.instance;

  bool _loading = true;
  String? _error;
  Map<String, IntegrationStatusData> _statuses = {};

  _HubFilter _filter = _HubFilter.all;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _appliedSearch = '';
  bool _searchFocused = false;

  // ─── Gating (paridade com integrations.routes.tsx) ───────────────────────

  bool get _hasModuleAccess {
    final svc = ModuleAccessService.instance;
    return IntegrationPermissions.hubModules.any(svc.hasCompanyModule);
  }

  bool get _hasPermissionAccess {
    return ModuleAccessService.instance
        .hasAnyPermission(IntegrationPermissions.hubRoute);
  }

  bool get _hasAccess =>
      _hasModuleAccess && _hasPermissionAccess && _visibleDefs.isNotEmpty;

  /// Integrações visíveis para o usuário (gating por card, como no web).
  List<IntegrationDef> get _visibleDefs {
    final svc = ModuleAccessService.instance;
    return IntegrationCatalog.all
        .where((def) => svc.hasAnyPermission(def.viewPermissions))
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _loadStatuses();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Color _accentColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
  }

  // ─── Dados ────────────────────────────────────────────────────────────────

  Future<void> _loadStatuses() async {
    final defs = _visibleDefs;
    if (defs.isEmpty) {
      setState(() {
        _loading = false;
        _statuses = {};
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final map =
          await _service.fetchStatuses(defs.map((d) => d.key).toList());
      if (!mounted) return;
      setState(() {
        _statuses = map;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao carregar o status das integrações';
        _loading = false;
      });
    }
  }

  int get _configuredCount =>
      _statuses.values.where((s) => s.configured).length;

  int get _pendingCount => _visibleDefs.length - _configuredCount;

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final v = value.trim();
      if (v == _appliedSearch) return;
      setState(() => _appliedSearch = v);
    });
  }

  List<IntegrationDef> get _filteredDefs {
    final q = _appliedSearch.toLowerCase();
    return _visibleDefs.where((def) {
      final st = _statuses[def.key];
      final configured = st?.configured ?? false;
      if (_filter == _HubFilter.connected && !configured) return false;
      if (_filter == _HubFilter.pending && configured) return false;
      if (q.isEmpty) return true;
      return def.name.toLowerCase().contains(q) ||
          def.tagline.toLowerCase().contains(q) ||
          def.description.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  void _openDetails(IntegrationDef def) {
    Navigator.of(context)
        .pushNamed('/integrations/${def.key}')
        .then((_) => _loadStatuses());
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_hasAccess) {
      return const AppScaffold(
        title: 'Integrações',
        showBottomNavigation: false,
        body: _DeniedView(),
      );
    }
    return AppScaffold(
      title: 'Integrações',
      showBottomNavigation: false,
      body: RefreshIndicator(
        color: _accentColor(context),
        onRefresh: _loadStatuses,
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
                        _buildSearchField(context),
                        const SizedBox(height: _kSectionGap),
                      ],
                    ),
                  ),
                  _buildTabsRail(context),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        _kPagePadH, _kSectionGap, _kPagePadH, _kPagePadBottom),
                    child: _buildBody(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Hero editorial (eyebrow + contagem + anel de progresso) ─────────────

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

    final total = _visibleDefs.length;
    final connected = _configuredCount;
    final allConnected = !_loading && total > 0 && connected == total;
    final dot = allConnected ? emerald : amber;
    final subtitle = _loading
        ? 'Verificando as conexões da sua empresa…'
        : allConnected
            ? 'Tudo conectado — seu funil está recebendo de todos os canais.'
            : connected == 0
                ? 'Nenhuma integração ativa ainda. Toque em uma para começar.'
                : '$connected conectada${connected == 1 ? '' : 's'} · '
                    '$_pendingCount pendente${_pendingCount == 1 ? '' : 's'}';

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
                'CENTRAL DE INTEGRAÇÕES',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.2,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$total',
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
                            total == 1 ? 'integração' : 'integrações',
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
                    const SizedBox(height: 14),
                    _buildKpiStrip(context, emerald, amber),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              IntegrationProgressRing(
                value: connected,
                total: total,
                accent: accent,
                loading: _loading,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiStrip(BuildContext context, Color emerald, Color amber) {
    final accent = _accentColor(context);
    final divider = ThemeHelpers.borderColor(context).withValues(alpha: 0.45);
    final blocks = <Widget>[
      _heroKpiBlock(context, LucideIcons.plugZap, 'DISPONÍVEIS',
          _loading ? '—' : '${_visibleDefs.length}', 'no plano', accent),
      _heroKpiBlock(context, LucideIcons.circleCheckBig, 'CONECTADAS',
          _loading ? '—' : '$_configuredCount', 'ativas agora', emerald),
      _heroKpiBlock(context, LucideIcons.hourglass, 'PENDENTES',
          _loading ? '—' : '$_pendingCount', 'a configurar', amber),
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

  // ─── Busca flush ──────────────────────────────────────────────────────────

  Widget _buildSearchField(BuildContext context) {
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

    return Focus(
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
                    color: accent.withValues(alpha: isDark ? 0.18 : 0.12),
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
                  hintText: 'Buscar integração…',
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
    );
  }

  // ─── Abas flush (sublinhado) ──────────────────────────────────────────────

  Color _filterColor(BuildContext context, _HubFilter f) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (f) {
      case _HubFilter.all:
        return _accentColor(context);
      case _HubFilter.connected:
        return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
      case _HubFilter.pending:
        return isDark
            ? AppColors.status.warningDarkMode
            : AppColors.status.warning;
    }
  }

  IconData _filterIcon(_HubFilter f) {
    switch (f) {
      case _HubFilter.all:
        return LucideIcons.plugZap;
      case _HubFilter.connected:
        return LucideIcons.circleCheckBig;
      case _HubFilter.pending:
        return LucideIcons.hourglass;
    }
  }

  String _filterLabel(_HubFilter f) {
    switch (f) {
      case _HubFilter.all:
        return 'Todas';
      case _HubFilter.connected:
        return 'Conectadas';
      case _HubFilter.pending:
        return 'Pendentes';
    }
  }

  int _filterCount(_HubFilter f) {
    if (_loading) return 0;
    switch (f) {
      case _HubFilter.all:
        return _visibleDefs.length;
      case _HubFilter.connected:
        return _configuredCount;
      case _HubFilter.pending:
        return _pendingCount;
    }
  }

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
          for (final f in _HubFilter.values)
            Expanded(
              child: _FlushTab(
                icon: _filterIcon(f),
                label: _filterLabel(f),
                count: _filterCount(f),
                tone: _filterColor(context, f),
                selected: _filter == f,
                onTap: () => setState(() => _filter = f),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Corpo (agrupado por categoria) ──────────────────────────────────────

  Widget _buildBody(BuildContext context) {
    if (_loading) return _buildSkeleton();
    if (_error != null) return _buildError(context, _error!);

    final defs = _filteredDefs;
    if (defs.isEmpty) return _buildEmpty(context);

    final nodes = <Widget>[];
    var animIndex = 0;

    for (final category in kIntegrationCategoryOrder) {
      final items =
          defs.where((d) => d.category == category).toList(growable: false);
      if (items.isEmpty) continue;

      if (nodes.isNotEmpty) nodes.add(const SizedBox(height: 18));
      nodes.add(_CategoryHeader(category: category, count: items.length));
      nodes.add(const SizedBox(height: 4));

      for (final def in items) {
        nodes.add(
          IntegrationCard(
            def: def,
            status: _statuses[def.key],
            onTap: () => _openDetails(def),
          ).animate(key: ValueKey('i-${def.key}')).fadeIn(
                delay: Duration(milliseconds: 25 * (animIndex++).clamp(0, 12)),
                duration: 220.ms,
              ),
        );
      }
    }

    nodes.add(const SizedBox(height: 22));
    nodes.add(_buildHelpHint(context));

    return Column(
      key: ValueKey('hub-${_filter.name}-$_appliedSearch'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: nodes,
    ).animate(key: ValueKey('hub-${_filter.name}')).fadeIn(duration: 240.ms);
  }

  Widget _buildHelpHint(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final accent = _accentColor(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: ThemeHelpers.cardBackgroundColor(context),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              color: accent.withValues(alpha: isDark ? 0.18 : 0.1),
            ),
            child: Icon(LucideIcons.info, color: accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Como funciona?',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'O selo CONECTADO indica que já existe conexão salva para a '
                  'sua empresa. Toque em uma integração para ver o status da '
                  'conexão e as ações disponíveis — configurações completas '
                  'são feitas pelo painel web.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Estados ──────────────────────────────────────────────────────────────

  Widget _buildSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 10),
          child: SkeletonText(width: 150, height: 12, borderRadius: 999),
        ),
        ...List.generate(
          6,
          (_) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonBox(width: 44, height: 44, borderRadius: 13),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      SkeletonBox(width: 88, height: 20, borderRadius: 999),
                      SizedBox(height: 9),
                      SkeletonText(width: 170, height: 15),
                      SizedBox(height: 6),
                      SkeletonText(width: double.infinity, height: 12),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: SkeletonBox(width: 16, height: 16, borderRadius: 6),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    final tone = _filterColor(context, _filter);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hasSearch = _appliedSearch.trim().isNotEmpty;
    final (icon, title, body) = hasSearch
        ? (
            LucideIcons.searchX,
            'Nenhuma integração encontrada',
            'Nada corresponde a "${_appliedSearch.trim()}". Ajuste a busca ou limpe os filtros.',
          )
        : switch (_filter) {
            _HubFilter.connected => (
                LucideIcons.unplug,
                'Nada conectado ainda',
                'Nenhuma integração ativa no momento. As conexões são feitas pelo painel web.',
              ),
            _HubFilter.pending => (
                LucideIcons.partyPopper,
                'Tudo conectado',
                'Todas as integrações disponíveis já estão ativas. Excelente!',
              ),
            _HubFilter.all => (
                LucideIcons.plugZap,
                'Nenhuma integração disponível',
                'Seu perfil não tem acesso a nenhuma integração nesta empresa.',
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
            onPressed: _loadStatuses,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}

// ─── Cabeçalho de categoria (dot na cor da categoria + label + count) ────────

class _CategoryHeader extends StatelessWidget {
  final IntegrationCategory category;
  final int count;

  const _CategoryHeader({required this.category, required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final tone = category.color;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: tone,
            borderRadius: BorderRadius.circular(2.5),
            boxShadow: [
              BoxShadow(color: tone.withValues(alpha: 0.35), blurRadius: 6),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          category.label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: secondary,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: 0.2,
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Container(
              height: 1,
              color:
                  ThemeHelpers.borderLightColor(context).withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
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

// ─── Sem acesso ───────────────────────────────────────────────────────────────

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
              'Você não tem acesso à Central de Integrações.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Solicite ao administrador acesso ao módulo de integrações da empresa.',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
