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
import '../models/collection_models.dart';
import '../services/collection_service.dart';
import '../widgets/collection_filters_sheet.dart';
import '../widgets/collection_message_card.dart';

/// Tela **Régua de Cobrança** (`/collection`) — paridade com a
/// `CollectionPage.tsx` do imobx-front, no DNA do app: a própria régua como
/// hero (linha do tempo Enviada → Entregue → Lida, com desvio de Falhas),
/// medidor de taxa de sucesso, distribuição por canal, busca + filtros flush,
/// abas com sublinhado por situação da mensagem e ações do gestor no próprio
/// fluxo (processar cobranças / configurar réguas).
class CollectionPage extends StatefulWidget {
  const CollectionPage({super.key});

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const double _kSectionGap = 12;

  static const _tabs = [
    CollectionMessageTab.all,
    CollectionMessageTab.delivered,
    CollectionMessageTab.waiting,
    CollectionMessageTab.failed,
  ];

  CollectionMessageTab _activeTab = CollectionMessageTab.all;

  List<CollectionMessage> _messages = const [];
  CollectionStatistics _stats = CollectionStatistics.zero;
  bool _loading = true;
  bool _statsLoading = true;
  String? _error;

  bool _processing = false;

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _appliedSearch = '';
  bool _searchFocused = false;
  CollectionMessageFilters _filters = CollectionMessageFilters.empty;

  bool get _canView =>
      ModuleAccessService.instance.hasPermission(CollectionAccess.view);
  bool get _canManage =>
      ModuleAccessService.instance.hasPermission(CollectionAccess.manage);

  @override
  void initState() {
    super.initState();
    _loadAll();
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

  /// Tom semântico de cada aba — vermelho da marca = visão principal,
  /// verde = chegou, âmbar = aguardando, vermelho de erro = falhou.
  Color _tabColor(BuildContext context, CollectionMessageTab tab) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (tab) {
      case CollectionMessageTab.all:
        return _accentColor(context);
      case CollectionMessageTab.delivered:
        return isDark
            ? AppColors.status.greenDarkMode
            : AppColors.status.green;
      case CollectionMessageTab.waiting:
        return isDark
            ? AppColors.status.warningDarkMode
            : AppColors.status.warning;
      case CollectionMessageTab.failed:
        return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    }
  }

  // ─── Dados ───────────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    await Future.wait([_loadMessages(), _loadStats()]);
  }

  Future<void> _loadMessages() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await CollectionService.instance.getMessages();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _messages = res.data!;
      } else {
        _error = res.message ?? 'Erro ao carregar a régua de cobrança';
      }
    });
  }

  Future<void> _loadStats() async {
    setState(() => _statsLoading = true);
    final res = await CollectionService.instance.getStatistics();
    if (!mounted) return;
    setState(() {
      _statsLoading = false;
      if (res.success && res.data != null) _stats = res.data!;
    });
  }

  /// Base após busca + filtros do modal (as abas fatiam esta lista).
  List<CollectionMessage> get _baseList {
    final q = _appliedSearch.trim().toLowerCase();
    return _messages.where((m) {
      if (!_filters.matches(m)) return false;
      if (q.isEmpty) return true;
      bool has(String? s) => (s ?? '').toLowerCase().contains(q);
      return has(m.recipientName) ||
          has(m.recipientEmail) ||
          has(m.recipientPhone) ||
          has(m.subject) ||
          has(m.message);
    }).toList();
  }

  List<CollectionMessage> _listFor(CollectionMessageTab tab) {
    final base = _baseList;
    switch (tab) {
      case CollectionMessageTab.all:
        return base;
      case CollectionMessageTab.delivered:
        return base.where((m) => m.status.isSuccess).toList();
      case CollectionMessageTab.waiting:
        return base.where((m) => m.status.isWaiting).toList();
      case CollectionMessageTab.failed:
        return base.where((m) => m.status.isFailure).toList();
    }
  }

  int _tabCount(CollectionMessageTab tab) => _listFor(tab).length;

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final v = value.trim();
      if (v == _appliedSearch) return;
      setState(() => _appliedSearch = v);
    });
  }

  // ─── Ações ───────────────────────────────────────────────────────────────

  void _openRules() {
    Navigator.of(context).pushNamed('/collection/rules').then((_) {
      if (mounted) _loadAll();
    });
  }

  Future<void> _confirmProcess() async {
    final accent = _accentColor(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: ThemeHelpers.cardBackgroundColor(ctx),
        title: Text(
          'Processar cobranças',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
            color: ThemeHelpers.textColor(ctx),
          ),
        ),
        content: Text(
          'Deseja processar as cobranças manualmente? Isso enviará mensagens '
          'para todos os pagamentos pendentes.',
          style: TextStyle(
            color: ThemeHelpers.textSecondaryColor(ctx),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: ThemeHelpers.textSecondaryColor(ctx),
            ),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(LucideIcons.send, size: 16),
            label: const Text('Processar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _processing = true);
    final res = await CollectionService.instance.processCollections();
    if (!mounted) return;
    setState(() => _processing = false);
    final messenger = ScaffoldMessenger.of(context);
    if (res.success) {
      messenger.showSnackBar(
        SnackBar(
          content:
              Text(res.data ?? 'Processamento de cobranças iniciado'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadAll();
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(res.message ?? 'Erro ao processar cobranças'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openFilters() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => CollectionFiltersSheet(
        initialFilters: _filters,
        onApply: (f) => setState(() => _filters = f),
        onClear: () =>
            setState(() => _filters = CollectionMessageFilters.empty),
      ),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canView) {
      return const AppScaffold(
        title: 'Régua de Cobrança',
        showBottomNavigation: false,
        body: _DeniedView(),
      );
    }
    return AppScaffold(
      title: 'Régua de Cobrança',
      showBottomNavigation: false,
      body: RefreshIndicator(
        color: _accentColor(context),
        onRefresh: _loadAll,
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
                        if (_canManage) ...[
                          const SizedBox(height: 16),
                          _buildManageActions(context),
                        ],
                        const SizedBox(height: _kSectionGap),
                        _buildSearchRow(context),
                        const SizedBox(height: _kSectionGap),
                      ],
                    ),
                  ),
                  _buildTabsRail(context),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        _kPagePadH, _kSectionGap, _kPagePadH, _kPagePadBottom),
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

  // ─── Hero: a régua como linha do tempo ───────────────────────────────────
  //
  // A identidade desta tela é a própria régua: estações Enviada → Entregue →
  // Lida conectadas por um trilho, com o desvio de Falhas ao final, e um
  // medidor de taxa de sucesso logo abaixo. Sem número gigante nem fileira
  // de KPIs sublinhados.

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accentColor(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

    final total = _stats.total;
    final hasFailures = _stats.failed > 0;
    final subtitle = total == 0
        ? 'As cobranças enviadas pela régua aparecem aqui.'
        : hasFailures
            ? '${_stats.failed} falha${_stats.failed == 1 ? '' : 's'} de envio para revisar.'
            : 'Todos os envios da régua saíram sem problemas.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Régua de cobrança',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: textColor,
                        letterSpacing: -0.5,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: hasFailures && !_statsLoading
                            ? danger
                            : secondary,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: accent.withValues(alpha: isDark ? 0.16 : 0.08),
                  border: Border.all(color: accent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.send, size: 12, color: accent),
                    const SizedBox(width: 5),
                    Text(
                      _statsLoading
                          ? '—'
                          : '$total envio${total == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w900,
                        fontSize: 11.5,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildJourney(context),
          const SizedBox(height: 16),
          _buildSuccessMeter(context),
          const SizedBox(height: 14),
          _buildChannelStrip(context),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(LucideIcons.clock3, size: 12, color: secondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Envio automático todos os dias às 8h — ou processe agora.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmtPct(double pct) {
    final s = pct
        .toStringAsFixed(pct % 1 == 0 ? 0 : 1)
        .replaceAll('.', ',');
    return '$s%';
  }

  /// Linha do tempo da régua — estações conectadas por um trilho, com o
  /// desvio de Falhas separado por um divisor vertical.
  Widget _buildJourney(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final blue = isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final purple =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

    // Trilho entre estações — alinhado ao centro do círculo (38px / 2).
    Widget rail(Color from, Color to) => Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: LinearGradient(
                  colors: [
                    from.withValues(alpha: 0.5),
                    to.withValues(alpha: 0.5),
                  ],
                ),
              ),
            ),
          ),
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _JourneyStation(
          icon: LucideIcons.send,
          label: 'ENVIADAS',
          count: _statsLoading ? null : _stats.sent,
          tone: blue,
        ),
        rail(blue, emerald),
        _JourneyStation(
          icon: LucideIcons.mailCheck,
          label: 'ENTREGUES',
          count: _statsLoading ? null : _stats.delivered,
          tone: emerald,
        ),
        rail(emerald, purple),
        _JourneyStation(
          icon: LucideIcons.mailOpen,
          label: 'LIDAS',
          count: _statsLoading ? null : _stats.read,
          tone: purple,
        ),
        Container(
          width: 1,
          height: 52,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
        ),
        _JourneyStation(
          icon: LucideIcons.circleAlert,
          label: 'FALHAS',
          count: _statsLoading ? null : _stats.failed,
          tone: danger,
          dimWhenZero: true,
        ),
      ],
    );
  }

  /// Medidor da taxa de sucesso da régua — rótulo, barra fina e percentual.
  Widget _buildSuccessMeter(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final frac =
        _statsLoading ? 0.0 : _stats.successRate.clamp(0.0, 1.0).toDouble();
    final pct = (_stats.successRate * 100).clamp(0, 100).toDouble();

    return Row(
      children: [
        Text(
          'TAXA DE SUCESSO',
          style: theme.textTheme.labelSmall?.copyWith(
            color: secondary,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
            fontSize: 9.5,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 6,
              child: LayoutBuilder(
                builder: (context, c) => Stack(
                  children: [
                    Container(
                      color: ThemeHelpers.borderColor(context)
                          .withValues(alpha: 0.4),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutCubic,
                      width: c.maxWidth * frac,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        gradient: LinearGradient(
                          colors: [
                            emerald.withValues(alpha: 0.7),
                            emerald,
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          _statsLoading ? '—' : _fmtPct(pct),
          style: theme.textTheme.labelSmall?.copyWith(
            color: emerald,
            fontWeight: FontWeight.w900,
            fontSize: 12,
            letterSpacing: -0.2,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  /// Distribuição por canal — chips tonais compactos (email/WhatsApp/SMS).
  Widget _buildChannelStrip(BuildContext context) {
    final entries = [
      (CollectionChannel.email, _stats.byEmail),
      (CollectionChannel.whatsapp, _stats.byWhatsapp),
      (CollectionChannel.sms, _stats.bySms),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (channel, count) in entries)
          _ChannelChip(
            channel: channel,
            count: _statsLoading ? null : count,
          ),
      ],
    );
  }

  // ─── Ações do gestor ─────────────────────────────────────────────────────

  Widget _buildManageActions(BuildContext context) {
    final accent = _accentColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _openRules,
            icon: const Icon(LucideIcons.settings2, size: 16),
            label: const Text(
              'Regras da régua',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: ThemeHelpers.textColor(context),
              side: BorderSide(color: secondary.withValues(alpha: 0.35)),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: _processing ? null : _confirmProcess,
            icon: _processing
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(LucideIcons.send, size: 16),
            label: Text(
              _processing ? 'Processando…' : 'Processar cobranças',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
              ),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }

  // ─── Busca + filtros flush ───────────────────────────────────────────────

  Widget _buildSearchRow(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accentColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final cardColor = ThemeHelpers.cardBackgroundColor(context);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final filterCount = _filters.activeCount;
    final filterActive = filterCount > 0;

    return Row(
      children: [
        Expanded(child: _buildSearchField(context)),
        const SizedBox(width: 10),
        // Botão de filtros — mesmo shell do campo de busca, badge com contagem.
        InkWell(
          onTap: _openFilters,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: filterActive
                  ? accent.withValues(alpha: isDark ? 0.16 : 0.08)
                  : cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: filterActive
                    ? accent.withValues(alpha: isDark ? 0.5 : 0.42)
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
                      width: 15,
                      height: 15,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$filterCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
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
                  hintText: 'Buscar destinatário, contato…',
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
                count: _tabCount(tab),
                tone: _tabColor(context, tab),
                selected: _activeTab == tab,
                onTap: () => setState(() => _activeTab = tab),
              ),
            ),
        ],
      ),
    );
  }

  IconData _tabIcon(CollectionMessageTab tab) {
    switch (tab) {
      case CollectionMessageTab.all:
        return LucideIcons.inbox;
      case CollectionMessageTab.delivered:
        return LucideIcons.checkCheck;
      case CollectionMessageTab.waiting:
        return LucideIcons.hourglass;
      case CollectionMessageTab.failed:
        return LucideIcons.circleAlert;
    }
  }

  String _tabLabel(CollectionMessageTab tab) {
    switch (tab) {
      case CollectionMessageTab.all:
        return 'Todas';
      case CollectionMessageTab.delivered:
        return 'Enviadas';
      case CollectionMessageTab.waiting:
        return 'Pendentes';
      case CollectionMessageTab.failed:
        return 'Falhas';
    }
  }

  // ─── Painel ativo ────────────────────────────────────────────────────────

  Widget _buildActivePanel(BuildContext context) {
    final list = _listFor(_activeTab);
    Widget child;
    if (_loading && _messages.isEmpty) {
      child = _buildSkeleton();
    } else if (_error != null && _messages.isEmpty) {
      child = _buildError(context, _error!);
    } else if (list.isEmpty) {
      child = _buildEmpty(context, _activeTab);
    } else {
      child = _buildList(context, list);
    }

    return Column(
      key: ValueKey('panel-${_activeTab.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPanelHeader(context, _activeTab),
        const SizedBox(height: 14),
        child,
      ],
    ).animate(key: ValueKey('panel-${_activeTab.name}')).fadeIn(
          duration: 240.ms,
        );
  }

  ({IconData icon, String eyebrow, String title, String hint}) _panelMeta(
      CollectionMessageTab tab) {
    switch (tab) {
      case CollectionMessageTab.all:
        return (
          icon: LucideIcons.inbox,
          eyebrow: 'HISTÓRICO',
          title: 'Todas as cobranças',
          hint: 'Tudo que a régua disparou, do mais recente ao mais antigo.',
        );
      case CollectionMessageTab.delivered:
        return (
          icon: LucideIcons.checkCheck,
          eyebrow: 'ENVIADAS',
          title: 'Cobranças que saíram',
          hint: 'Mensagens enviadas, entregues ou lidas pelo destinatário.',
        );
      case CollectionMessageTab.waiting:
        return (
          icon: LucideIcons.hourglass,
          eyebrow: 'PENDENTES',
          title: 'Aguardando envio',
          hint: 'Na fila ou aguardando o próximo processamento da régua.',
        );
      case CollectionMessageTab.failed:
        return (
          icon: LucideIcons.circleAlert,
          eyebrow: 'FALHAS',
          title: 'Envios com problema',
          hint: 'Falhas e devoluções — revise o contato do destinatário.',
        );
    }
  }

  Widget _buildPanelHeader(BuildContext context, CollectionMessageTab tab) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = _tabColor(context, tab);
    final meta = _panelMeta(tab);

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

  Widget _buildList(BuildContext context, List<CollectionMessage> list) {
    final nodes = <Widget>[];
    var animIndex = 0;

    for (final group in _groupByMonth(list)) {
      if (nodes.isNotEmpty) nodes.add(const SizedBox(height: 14));
      nodes.add(_PanelSubsectionHeader(
        label: group.label,
        icon: LucideIcons.calendarDays,
        count: group.items.length,
      ));
      nodes.add(const SizedBox(height: 8));
      for (final m in group.items) {
        nodes.add(
          CollectionMessageCard(
            message: m,
            onTap: () => _showDetail(context, m),
          ).animate(key: ValueKey('m-${m.id}')).fadeIn(
                delay: Duration(milliseconds: 30 * (animIndex++).clamp(0, 12)),
                duration: 220.ms,
              ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: nodes,
    );
  }

  /// Agrupa por mês preservando a ordem (a API devolve desc por criação).
  List<({String label, List<CollectionMessage> items})> _groupByMonth(
      List<CollectionMessage> list) {
    final fmt = DateFormat('MMMM yyyy', 'pt_BR');
    final map = <String, List<CollectionMessage>>{};
    for (final m in list) {
      final d = m.bestDate?.toLocal();
      final key = d == null ? 'Sem data' : fmt.format(d);
      map.putIfAbsent(key, () => []).add(m);
    }
    return map.entries
        .map((e) => (label: e.key, items: e.value))
        .toList(growable: false);
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
                    SkeletonText(width: 170, height: 12),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const SkeletonText(width: 52, height: 14),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, CollectionMessageTab tab) {
    final theme = Theme.of(context);
    final tone = _tabColor(context, tab);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hasQuery = _appliedSearch.trim().isNotEmpty || _filters.activeCount > 0;
    final (icon, title, body) = hasQuery
        ? (
            LucideIcons.searchX,
            'Nada encontrado',
            'Nenhuma cobrança corresponde à busca ou aos filtros aplicados.',
          )
        : switch (tab) {
            CollectionMessageTab.all => (
                LucideIcons.send,
                'Nenhuma cobrança ainda',
                'Configure as regras da régua e as mensagens aparecem aqui.',
              ),
            CollectionMessageTab.delivered => (
                LucideIcons.mailCheck,
                'Nenhuma enviada',
                'Quando uma cobrança sair, ela aparece aqui.',
              ),
            CollectionMessageTab.waiting => (
                LucideIcons.partyPopper,
                'Fila vazia',
                'Nenhuma cobrança aguardando envio no momento.',
              ),
            CollectionMessageTab.failed => (
                LucideIcons.circleCheckBig,
                'Nenhuma falha',
                'Todos os envios da régua saíram sem problemas.',
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
            onPressed: _loadAll,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }

  // ─── Detalhe ─────────────────────────────────────────────────────────────

  void _showDetail(BuildContext context, CollectionMessage m) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => _MessageDetailSheet(message: m),
    );
  }
}

// ─── Estação da linha do tempo (hero) ────────────────────────────────────────

/// Uma estação da régua: círculo tonal com ícone, contagem tabular e rótulo.
/// `count == null` indica carregamento (“—”). Com [dimWhenZero], a estação
/// fica discreta quando não há ocorrências (ex.: nenhuma falha).
class _JourneyStation extends StatelessWidget {
  final IconData icon;
  final String label;
  final int? count;
  final Color tone;
  final bool dimWhenZero;

  const _JourneyStation({
    required this.icon,
    required this.label,
    required this.count,
    required this.tone,
    this.dimWhenZero = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dim = dimWhenZero && count == 0;
    final fg = dim ? tone.withValues(alpha: 0.45) : tone;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: fg.withValues(alpha: isDark ? 0.16 : 0.1),
            border: Border.all(color: fg.withValues(alpha: 0.35)),
          ),
          child: Icon(icon, size: 16, color: fg),
        ),
        const SizedBox(height: 7),
        Text(
          count == null ? '—' : '$count',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: dim ? ThemeHelpers.textSecondaryColor(context) : fg,
            letterSpacing: -0.4,
            height: 1.0,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 8.5,
            fontWeight: FontWeight.w900,
            color: dim
                ? ThemeHelpers.textSecondaryColor(context)
                    .withValues(alpha: 0.7)
                : fg,
            letterSpacing: 1.1,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}

// ─── Chip de canal (hero) ────────────────────────────────────────────────────

class _ChannelChip extends StatelessWidget {
  final CollectionChannel channel;
  final int? count;

  const _ChannelChip({required this.channel, this.count});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone = collectionChannelColor(context, channel);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.13 : 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(collectionChannelIcon(channel), size: 13, color: tone),
          const SizedBox(width: 6),
          Text(
            channel.label,
            style: TextStyle(
              color: tone,
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            count == null ? '—' : '$count',
            style: TextStyle(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
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

// ─── Cabeçalho de sub-seção (mês) ────────────────────────────────────────────

class _PanelSubsectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  final int count;

  const _PanelSubsectionHeader({
    required this.label,
    required this.icon,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Row(
      children: [
        Icon(icon, size: 14, color: secondary),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: secondary,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
        if (count > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color:
                  ThemeHelpers.borderLightColor(context).withValues(alpha: 0.7),
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
        ],
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

// ─── Bottom sheet de detalhe da mensagem ─────────────────────────────────────

class _MessageDetailSheet extends StatelessWidget {
  const _MessageDetailSheet({required this.message});
  final CollectionMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final channelTone = collectionChannelColor(context, message.channel);
    final statusTone = collectionStatusColor(context, message.status);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final fmt = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

    final name = message.recipientName.trim().isNotEmpty
        ? message.recipientName.trim()
        : 'Destinatário';

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: channelTone.withValues(alpha: isDark ? 0.22 : 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.16),
            blurRadius: 28,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: secondary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        color:
                            channelTone.withValues(alpha: isDark ? 0.18 : 0.1),
                        border: Border.all(
                            color: channelTone.withValues(alpha: 0.3)),
                      ),
                      child: Icon(collectionChannelIcon(message.channel),
                          color: channelTone, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: ThemeHelpers.textColor(context),
                              letterSpacing: -0.3,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _miniPill(
                                  message.status.label, statusTone, isDark),
                              _miniPill(
                                  message.channel.label, channelTone, isDark),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                // Corpo da mensagem em destaque tonal (cor do canal).
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: channelTone.withValues(alpha: isDark ? 0.12 : 0.07),
                    border:
                        Border.all(color: channelTone.withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MENSAGEM ENVIADA',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: channelTone,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                          fontSize: 10,
                        ),
                      ),
                      if (message.subject?.trim().isNotEmpty ?? false) ...[
                        const SizedBox(height: 6),
                        Text(
                          message.subject!.trim(),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: ThemeHelpers.textColor(context),
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        message.message.trim().isNotEmpty
                            ? message.message.trim()
                            : '—',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: ThemeHelpers.textColor(context),
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (message.contact != null && message.contact!.isNotEmpty)
                  _row(
                    context,
                    message.channel == CollectionChannel.email
                        ? 'Email'
                        : 'Telefone',
                    message.contact!,
                    icon: message.channel == CollectionChannel.email
                        ? LucideIcons.atSign
                        : LucideIcons.phone,
                  ),
                if (message.ruleName?.trim().isNotEmpty ?? false)
                  _row(context, 'Régua', message.ruleName!.trim(),
                      icon: LucideIcons.settings2),
                const _Divider(),
                if (message.createdAt != null)
                  _row(context, 'Criada em',
                      fmt.format(message.createdAt!.toLocal())),
                if (message.sentAt != null)
                  _row(context, 'Enviada em',
                      fmt.format(message.sentAt!.toLocal())),
                if (message.deliveredAt != null)
                  _row(context, 'Entregue em',
                      fmt.format(message.deliveredAt!.toLocal())),
                if (message.readAt != null)
                  _row(context, 'Lida em',
                      fmt.format(message.readAt!.toLocal())),
                if (message.failedAt != null)
                  _row(context, 'Falhou em',
                      fmt.format(message.failedAt!.toLocal())),
                if (message.errorMessage?.trim().isNotEmpty ?? false) ...[
                  const SizedBox(height: 14),
                  Text(
                    'ERRO REPORTADO',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusTone,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    message.errorMessage!.trim(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniPill(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: isDark ? 0.4 : 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontWeight: FontWeight.w800, fontSize: 11),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value,
      {IconData? icon}) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: secondary),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        height: 1,
        color: ThemeHelpers.borderLightColor(context),
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
              'Você não tem acesso à régua de cobrança.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Solicite ao administrador a permissão de visualizar cobranças.',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
