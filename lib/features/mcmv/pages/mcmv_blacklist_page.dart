import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/utils/masks.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/mcmv_models.dart';
import '../services/mcmv_service.dart';
import '../widgets/mcmv_blacklist_add_sheet.dart';
import '../widgets/mcmv_common.dart';

/// Tela **Blacklist MCMV** — hero editorial, busca flush, chips de vigência
/// (Todos/Permanentes/Temporários/Expirados) e lista flush com a ação de
/// remover no próprio item. Botão fixo "Adicionar" (gated por
/// `mcmv:blacklist:manage`) abre o bottom-sheet de inclusão.
class McmvBlacklistPage extends StatefulWidget {
  const McmvBlacklistPage({super.key});

  @override
  State<McmvBlacklistPage> createState() => _McmvBlacklistPageState();
}

enum _BlacklistScope { all, permanent, temporary, expired }

class _McmvBlacklistPageState extends State<McmvBlacklistPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 120;
  static const double _kSectionGap = 12;

  List<McmvBlacklistEntry> _items = const [];
  bool _loading = true;
  String? _error;
  String? _removingId;

  _BlacklistScope _scope = _BlacklistScope.all;

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _appliedSearch = '';
  bool _searchFocused = false;

  bool get _canView =>
      mcmvModuleEnabled() &&
      ModuleAccessService.instance.hasPermission(McmvPermissions.blacklistView);
  bool get _canManage => ModuleAccessService.instance
      .hasPermission(McmvPermissions.blacklistManage);

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

  McmvBlacklistFilters get _apiFilters {
    switch (_scope) {
      case _BlacklistScope.all:
        return const McmvBlacklistFilters();
      case _BlacklistScope.permanent:
        return const McmvBlacklistFilters(isPermanent: true);
      case _BlacklistScope.temporary:
        return const McmvBlacklistFilters(isPermanent: false);
      case _BlacklistScope.expired:
        return const McmvBlacklistFilters(expired: true);
    }
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      if (refresh) _error = null;
    });
    final res =
        await McmvService.instance.listBlacklist(filters: _apiFilters);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _items = res.data!;
        _error = null;
      } else {
        _error = res.message ?? 'Erro ao carregar blacklist';
      }
    });
  }

  void _selectScope(_BlacklistScope scope) {
    if (_scope == scope) return;
    setState(() => _scope = scope);
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

  /// Busca no cliente (CPF/email/telefone/motivo) — evita idas à API a cada
  /// tecla; os filtros de vigência usam os query params reais.
  List<McmvBlacklistEntry> get _visibleItems {
    final q = _appliedSearch.toLowerCase().trim();
    if (q.isEmpty) return _items;
    final qDigits = mcmvOnlyDigits(q);
    return _items.where((e) {
      if ((e.email ?? '').toLowerCase().contains(q)) return true;
      if (e.reason.toLowerCase().contains(q)) return true;
      if (qDigits.isNotEmpty) {
        if (mcmvOnlyDigits(e.cpf ?? '').contains(qDigits)) return true;
        if (mcmvOnlyDigits(e.phone ?? '').contains(qDigits)) return true;
      }
      return false;
    }).toList();
  }

  Future<void> _openAddSheet() async {
    final request = await showModalBottomSheet<McmvBlacklistCreateRequest>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => const McmvBlacklistAddSheet(),
    );
    if (request == null || !mounted) return;
    final res = await McmvService.instance.addToBlacklist(request);
    if (!mounted) return;
    if (res.success) {
      _snack('Entrada adicionada à blacklist com sucesso!');
      _load(refresh: true);
    } else {
      _snack(res.message ?? 'Erro ao adicionar à blacklist', error: true);
    }
  }

  Future<void> _remove(McmvBlacklistEntry entry) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remover da blacklist?'),
        content: Text(
          'O contato ${_entryTitle(entry)} volta a poder receber leads do '
          'MCMV.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _removingId = entry.id);
    final res = await McmvService.instance.removeFromBlacklist(entry.id);
    if (!mounted) return;
    setState(() => _removingId = null);
    if (res.success) {
      setState(() => _items = _items.where((e) => e.id != entry.id).toList());
      _snack('Entrada removida da blacklist com sucesso!');
    } else {
      _snack(res.message ?? 'Erro ao remover da blacklist', error: true);
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? danger : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static String _entryTitle(McmvBlacklistEntry e) {
    if ((e.cpf ?? '').isNotEmpty) return Masks.cpf(e.cpf!);
    if ((e.email ?? '').isNotEmpty) return e.email!;
    if ((e.phone ?? '').isNotEmpty) return Masks.phone(e.phone!);
    return 'sem identificador';
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canView) {
      return const AppScaffold(
        title: 'Blacklist MCMV',
        showBottomNavigation: false,
        body: McmvDeniedView(
          message: 'Você não tem acesso à blacklist do MCMV.',
          permission: McmvPermissions.blacklistView,
        ),
      );
    }
    return AppScaffold(
      title: 'Blacklist MCMV',
      showBottomNavigation: false,
      body: Stack(
        children: [
          RefreshIndicator(
            color: mcmvAccentColor(context),
            onRefresh: () => _load(refresh: true),
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
                            _buildSearchField(context),
                            const SizedBox(height: _kSectionGap),
                          ],
                        ),
                      ),
                      _buildScopeChips(context),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(_kPagePadH,
                            _kSectionGap + 4, _kPagePadH, _kPagePadBottom),
                        child: _buildPanel(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_canManage)
            Positioned(
              right: 16,
              bottom: 20,
              child: _buildAddButton(context),
            ),
        ],
      ),
    );
  }

  Widget _buildAddButton(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    return FilledButton.icon(
      onPressed: _openAddSheet,
      icon: const Icon(LucideIcons.plus, size: 18),
      label: const Text('Adicionar',
          style: TextStyle(fontWeight: FontWeight.w800)),
      style: FilledButton.styleFrom(
        backgroundColor: danger,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 0,
      ),
    );
  }

  // ─── Hero ────────────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = mcmvAccentColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;

    final permanent = _items.where((e) => e.isPermanent).length;
    final temporary = _items.length - permanent;
    final expired = _items.where((e) => e.isExpired).length;
    final total = _items.length;

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
                  color: danger,
                  boxShadow: [
                    BoxShadow(
                      color: danger.withValues(alpha: 0.55),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              Text(
                'BLACKLIST MCMV',
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
                '$total',
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
                  total == 1 ? 'bloqueio' : 'bloqueios',
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
            total == 0
                ? 'Contatos bloqueados deixam de receber leads do programa.'
                : '$permanent permanente${permanent == 1 ? '' : 's'} · '
                    '$temporary temporário${temporary == 1 ? '' : 's'}'
                    '${expired > 0 ? ' · $expired expirado${expired == 1 ? '' : 's'}' : ''}',
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
                  child: _kpiBlock(context, LucideIcons.lock, 'PERMANENTES',
                      _loading ? '—' : '$permanent', 'sem prazo', danger),
                ),
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color:
                      ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
                ),
                Expanded(
                  child: _kpiBlock(context, LucideIcons.timer, 'TEMPORÁRIOS',
                      _loading ? '—' : '$temporary', 'com expiração', amber),
                ),
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color:
                      ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
                ),
                Expanded(
                  child: _kpiBlock(context, LucideIcons.calendarCheck,
                      'EXPIRADOS', _loading ? '—' : '$expired',
                      'prazo vencido', emerald),
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
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: tone,
              letterSpacing: -0.6,
              height: 1.0,
              fontSize: 22,
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

  // ─── Busca flush ─────────────────────────────────────────────────────────

  Widget _buildSearchField(BuildContext context) {
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
                  hintText: 'Buscar por CPF, email, telefone…',
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

  // ─── Chips de vigência (filtros da API) ──────────────────────────────────

  Widget _buildScopeChips(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final options = <(_BlacklistScope, String, IconData?, Color)>[
      (_BlacklistScope.all, 'Todos', null, mcmvAccentColor(context)),
      (_BlacklistScope.permanent, 'Permanentes', LucideIcons.lock, danger),
      (_BlacklistScope.temporary, 'Temporários', LucideIcons.timer, amber),
      (
        _BlacklistScope.expired,
        'Expirados',
        LucideIcons.calendarCheck,
        emerald
      ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: _kPagePadH),
      child: Row(
        children: [
          for (final (scope, label, icon, tone) in options) ...[
            McmvFilterChip(
              label: label,
              icon: icon,
              selected: _scope == scope,
              accent: tone,
              onTap: () => _selectScope(scope),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  // ─── Painel ──────────────────────────────────────────────────────────────

  Widget _buildPanel(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
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
      child = _appliedSearch.trim().isNotEmpty
          ? McmvEmptyState(
              icon: LucideIcons.searchX,
              title: 'Nada encontrado',
              body:
                  'Nenhuma entrada corresponde a "${_appliedSearch.trim()}".',
              tone: danger,
            )
          : McmvEmptyState(
              icon: LucideIcons.shieldCheck,
              title: 'Nenhuma entrada na blacklist',
              body: 'Quando houver contatos bloqueados, eles aparecerão aqui.',
              tone: danger,
            );
    } else {
      var animIndex = 0;
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in visible)
            _BlacklistItem(
              entry: entry,
              canManage: _canManage,
              removing: _removingId == entry.id,
              onRemove: () => _remove(entry),
            ).animate(key: ValueKey('bl-${entry.id}')).fadeIn(
                  delay:
                      Duration(milliseconds: 30 * (animIndex++).clamp(0, 12)),
                  duration: 220.ms,
                ),
        ],
      );
    }

    return Column(
      key: ValueKey('panel-${_scope.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        McmvPanelHeader(
          icon: LucideIcons.userMinus,
          eyebrow: 'BLOQUEIOS',
          title: _scope == _BlacklistScope.all
              ? 'Contatos bloqueados'
              : _scope == _BlacklistScope.permanent
                  ? 'Bloqueios permanentes'
                  : _scope == _BlacklistScope.temporary
                      ? 'Bloqueios temporários'
                      : 'Bloqueios expirados',
          hint:
              'Contatos nesta lista não recebem leads do programa MCMV.',
          tone: danger,
        ),
        const SizedBox(height: 14),
        child,
      ],
    ).animate(key: ValueKey('panel-${_scope.name}')).fadeIn(duration: 240.ms);
  }

  /// Skeleton fiel ao item da blacklist.
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
              const SkeletonBox(width: 44, height: 44, borderRadius: 13),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonText(width: 84, height: 18, borderRadius: 999),
                    SizedBox(height: 9),
                    SkeletonText(width: double.infinity, height: 15),
                    SizedBox(height: 6),
                    SkeletonText(width: 170, height: 12),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const SkeletonBox(width: 34, height: 34, borderRadius: 10),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Item da blacklist ───────────────────────────────────────────────────────

class _BlacklistItem extends StatelessWidget {
  final McmvBlacklistEntry entry;
  final bool canManage;
  final bool removing;
  final VoidCallback onRemove;

  const _BlacklistItem({
    required this.entry,
    required this.canManage,
    required this.removing,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;

    // Cor por significado: permanente = vermelho, temporário = âmbar,
    // expirado = verde (já liberado na prática).
    final tone = entry.isExpired
        ? emerald
        : entry.isPermanent
            ? danger
            : amber;

    final title = _title();
    final dateFmt = DateFormat('dd/MM/yyyy', 'pt_BR');

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              color: tone.withValues(alpha: isDark ? 0.16 : 0.1),
              border: Border.all(color: tone.withValues(alpha: 0.28)),
            ),
            child: Icon(LucideIcons.userMinus, color: tone, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    McmvStatusPill(
                      label: entry.isPermanent ? 'Permanente' : 'Temporário',
                      color: entry.isPermanent ? danger : amber,
                      icon: entry.isPermanent
                          ? LucideIcons.lock
                          : LucideIcons.timer,
                    ),
                    if (entry.isExpired)
                      McmvStatusPill(
                        label: 'Expirado',
                        color: emerald,
                        icon: LucideIcons.calendarCheck,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                    height: 1.2,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                ..._secondaryIdentifiers(context, title),
                if (entry.reason.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    entry.reason.trim(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: neutral,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (!entry.isPermanent && entry.expiresAt != null) ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(LucideIcons.calendar, size: 12, color: neutral),
                      const SizedBox(width: 4),
                      Text(
                        'Expira em ${dateFmt.format(entry.expiresAt!.toLocal())}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: neutral,
                          fontWeight: FontWeight.w700,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (canManage) ...[
            const SizedBox(width: 10),
            // Ação de remover no próprio item (não escondida em menu).
            removing
                ? Padding(
                    padding: const EdgeInsets.all(8),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: danger),
                    ),
                  )
                : InkResponse(
                    radius: 22,
                    onTap: onRemove,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: danger.withValues(alpha: isDark ? 0.14 : 0.08),
                        border: Border.all(
                            color: danger.withValues(alpha: 0.3)),
                      ),
                      child: Icon(LucideIcons.trash2, size: 16, color: danger),
                    ),
                  ),
          ],
        ],
      ),
    );
  }

  String _title() {
    if ((entry.cpf ?? '').trim().isNotEmpty) {
      return Masks.cpf(entry.cpf!.trim());
    }
    if ((entry.email ?? '').trim().isNotEmpty) return entry.email!.trim();
    if ((entry.phone ?? '').trim().isNotEmpty) {
      return Masks.phone(entry.phone!.trim());
    }
    return 'Sem identificador';
  }

  List<Widget> _secondaryIdentifiers(BuildContext context, String title) {
    final theme = Theme.of(context);
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final parts = <(IconData, String)>[];
    final email = (entry.email ?? '').trim();
    final phone = (entry.phone ?? '').trim();
    if (email.isNotEmpty && email != title) {
      parts.add((LucideIcons.mail, email));
    }
    if (phone.isNotEmpty && Masks.phone(phone) != title) {
      parts.add((LucideIcons.phone, Masks.phone(phone)));
    }
    if (parts.isEmpty) return const [];
    return [
      const SizedBox(height: 3),
      Wrap(
        spacing: 10,
        runSpacing: 3,
        children: [
          for (final (icon, text) in parts)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: neutral),
                const SizedBox(width: 4),
                Text(
                  text,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: neutral,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
        ],
      ),
    ];
  }
}
