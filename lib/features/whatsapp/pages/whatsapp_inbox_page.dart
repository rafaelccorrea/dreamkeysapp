import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/profile_service.dart';
import '../../../shared/services/secure_storage_service.dart';
import '../../../shared/utils/jwt_utils.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/whatsapp_models.dart';
import '../services/whatsapp_service.dart';
import '../widgets/whatsapp_conversation_card.dart';
import '../widgets/whatsapp_filters_drawer.dart';

/// Estado de uma aba de atendimento (lista paginada independente).
class _TabState {
  List<WhatsAppConversation> items = const [];
  bool loading = false;
  bool loadingMore = false;
  bool loaded = false;
  String? error;
  int total = 0;
  bool get hasMore => items.length < total;
}

/// Tela **WhatsApp** (`/whatsapp`) — inbox de conversas do atendimento.
///
/// Paridade com o `WhatsAppPage.tsx` do painel: abas de atendimento
/// (Todas / Aguardando / Em atendimento / Minhas / Finalizadas), busca por
/// nome/telefone/conteúdo, filtros (não lidas, negociação, tipo, período),
/// badges de não lidas e indicação do canal (API oficial × QR Code).
/// Mesmo DNA visual de Comissões/Aprovações: hero editorial com KPIs, busca
/// flush, abas com sublinhado e painel com eyebrow + título + hint.
class WhatsAppInboxPage extends StatefulWidget {
  const WhatsAppInboxPage({super.key});

  @override
  State<WhatsAppInboxPage> createState() => _WhatsAppInboxPageState();
}

class _WhatsAppInboxPageState extends State<WhatsAppInboxPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const double _kSectionGap = 12;
  static const int _pageSize = 20;

  static const _tabs = WhatsAppAttendanceTab.values;

  WhatsAppAttendanceTab _activeTab = WhatsAppAttendanceTab.all;
  final Map<WhatsAppAttendanceTab, _TabState> _state = {
    for (final t in WhatsAppAttendanceTab.values) t: _TabState(),
  };
  final Map<WhatsAppAttendanceTab, int?> _counts = {
    for (final t in WhatsAppAttendanceTab.values) t: null,
  };

  int? _unreadCount;
  WhatsAppIntegrationStatus? _integrationStatus;
  bool _headerLoading = true;
  String? _currentUserId;

  WhatsAppInboxFilters _filters = const WhatsAppInboxFilters();
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _appliedSearch = '';
  bool _searchFocused = false;

  // Paridade com a rota web `/whatsapp`: PermissionRoute com
  // [whatsapp:view, whatsapp:view_messages] (qualquer uma libera).
  bool get _canView => ModuleAccessService.instance.hasAnyPermission(
        const ['whatsapp:view', 'whatsapp:view_messages'],
      );

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _resolveCurrentUser();
    if (!mounted) return;
    unawaited(_loadHeader());
    unawaited(_loadCounts());
    unawaited(_loadTab(_activeTab));
  }

  /// Resolve o id do usuário logado (aba "Minhas") — perfil com fallback no
  /// token, mesmo caminho do chat interno.
  Future<void> _resolveCurrentUser() async {
    try {
      final profile = await ProfileService.instance.getProfile();
      if (profile.success && profile.data != null) {
        _currentUserId = profile.data!.id;
        return;
      }
      final token = await SecureStorageService.instance.getAccessToken();
      if (token != null) {
        final payload = JwtUtils.decodeToken(token);
        _currentUserId =
            payload?['sub']?.toString() ?? payload?['userId']?.toString();
      }
    } catch (e) {
      debugPrint('❌ [WHATSAPP] _resolveCurrentUser: $e');
    }
  }

  // ─── Cores ───────────────────────────────────────────────────────────────

  Color _accentColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
  }

  /// Tom semântico de cada aba: marca = visão geral; âmbar = aguardando
  /// (atenção); azul = em atendimento (atividade); verde = minhas (ok/seu
  /// campo); neutro = finalizadas (arquivo).
  Color _tabColor(BuildContext context, WhatsAppAttendanceTab tab) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (tab) {
      case WhatsAppAttendanceTab.all:
        return _accentColor(context);
      case WhatsAppAttendanceTab.waiting:
        return isDark
            ? AppColors.status.warningDarkMode
            : AppColors.status.warning;
      case WhatsAppAttendanceTab.inProgress:
        return isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
      case WhatsAppAttendanceTab.mine:
        return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
      case WhatsAppAttendanceTab.finalized:
        return ThemeHelpers.textSecondaryColor(context);
    }
  }

  IconData _tabIcon(WhatsAppAttendanceTab tab) {
    switch (tab) {
      case WhatsAppAttendanceTab.all:
        return LucideIcons.inbox;
      case WhatsAppAttendanceTab.waiting:
        return LucideIcons.hourglass;
      case WhatsAppAttendanceTab.inProgress:
        return LucideIcons.headset;
      case WhatsAppAttendanceTab.mine:
        return LucideIcons.circleUserRound;
      case WhatsAppAttendanceTab.finalized:
        return LucideIcons.circleCheckBig;
    }
  }

  // ─── Dados ───────────────────────────────────────────────────────────────

  Future<void> _loadHeader() async {
    setState(() => _headerLoading = true);
    final results = await Future.wait<dynamic>([
      WhatsAppService.instance.getUnreadCount(),
      WhatsAppService.instance.getIntegrationStatus(),
    ]);
    if (!mounted) return;
    setState(() {
      _headerLoading = false;
      _unreadCount = results[0] as int?;
      _integrationStatus = results[1] as WhatsAppIntegrationStatus?;
    });
  }

  /// Contagem real (contatos distintos) por aba — badges do rail.
  Future<void> _loadCounts() async {
    final futures = _tabs.map((tab) async {
      final count = await WhatsAppService.instance.getConversationsCount(
        tab: tab,
        search: _appliedSearch,
        filters: _filters,
        currentUserId: _currentUserId,
      );
      if (!mounted) return;
      setState(() => _counts[tab] = count);
    });
    await Future.wait(futures);
  }

  Future<void> _loadTab(WhatsAppAttendanceTab tab,
      {bool refresh = false}) async {
    final st = _state[tab]!;
    setState(() {
      st.loading = true;
      if (refresh) st.error = null;
    });
    final res = await WhatsAppService.instance.getConversations(
      tab: tab,
      search: _appliedSearch,
      filters: _filters,
      currentUserId: _currentUserId,
      limit: _pageSize,
      offset: 0,
    );
    if (!mounted) return;
    setState(() {
      st.loading = false;
      st.loaded = true;
      if (res.success && res.data != null) {
        st.items = res.data!.conversations;
        st.total = res.data!.total;
        st.error = null;
      } else {
        st.error = res.message ?? 'Erro ao carregar conversas';
      }
    });
  }

  Future<void> _loadMore(WhatsAppAttendanceTab tab) async {
    final st = _state[tab]!;
    if (st.loadingMore || !st.hasMore) return;
    setState(() => st.loadingMore = true);
    final res = await WhatsAppService.instance.getConversations(
      tab: tab,
      search: _appliedSearch,
      filters: _filters,
      currentUserId: _currentUserId,
      limit: _pageSize,
      offset: st.items.length,
    );
    if (!mounted) return;
    setState(() {
      st.loadingMore = false;
      if (res.success && res.data != null) {
        final seen = st.items.map((c) => c.phoneNumber).toSet();
        st.items = [
          ...st.items,
          ...res.data!.conversations.where((c) => seen.add(c.phoneNumber)),
        ];
        st.total = res.data!.total;
      }
    });
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _loadHeader(),
      _loadCounts(),
      _loadTab(_activeTab, refresh: true),
    ]);
  }

  void _selectTab(WhatsAppAttendanceTab tab) {
    if (tab == _activeTab) return;
    setState(() => _activeTab = tab);
    final st = _state[tab]!;
    if (!st.loaded && !st.loading) _loadTab(tab);
  }

  void _resetAndReload() {
    setState(() {
      for (final s in _state.values) {
        s.items = const [];
        s.loaded = false;
        s.total = 0;
        s.error = null;
      }
      for (final t in _tabs) {
        _counts[t] = null;
      }
    });
    unawaited(_loadCounts());
    unawaited(_loadTab(_activeTab, refresh: true));
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final v = value.trim();
      if (v == _appliedSearch) return;
      _appliedSearch = v;
      _resetAndReload();
    });
  }

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => WhatsAppFiltersDrawer(
        initialFilters: _filters,
        onApply: (f) {
          _filters = f;
          _resetAndReload();
        },
        onClear: () {
          _filters = const WhatsAppInboxFilters();
          _resetAndReload();
        },
      ),
    );
  }

  Future<void> _openConversation(WhatsAppConversation conversation) async {
    // Rota registrada centralmente em app_routes: /whatsapp/:phoneNumber.
    await Navigator.of(context).pushNamed(
      '/whatsapp/${Uri.encodeComponent(conversation.phoneNumber)}',
      arguments: conversation,
    );
    if (!mounted) return;
    // Ao voltar da thread, ressincroniza badges e a aba ativa.
    unawaited(_loadHeader());
    unawaited(_loadCounts());
    unawaited(_loadTab(_activeTab, refresh: true));
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canView) {
      return const AppScaffold(
        title: 'WhatsApp',
        showBottomNavigation: false,
        body: _DeniedView(),
      );
    }
    return AppScaffold(
      title: 'WhatsApp',
      showBottomNavigation: false,
      body: RefreshIndicator(
        color: _accentColor(context),
        onRefresh: _refreshAll,
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

  // ─── Hero editorial ──────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accentColor(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final blue = isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;

    final total = _counts[WhatsAppAttendanceTab.all];
    final unread = _unreadCount ?? 0;
    // Sem `whatsapp:view` o status vem nulo (403) — não acusamos desconexão.
    final disconnected =
        _integrationStatus != null && !_integrationStatus!.hasAnyChannel;
    final dot = !_headerLoading && disconnected ? amber : green;

    final String subtitle;
    if (_headerLoading && total == null) {
      subtitle = 'Sincronizando seu atendimento…';
    } else if (disconnected) {
      subtitle = 'Nenhum canal conectado — configure o WhatsApp no painel.';
    } else if (unread > 0) {
      subtitle =
          '$unread mensagem${unread == 1 ? '' : 's'} não lida${unread == 1 ? '' : 's'} aguardando resposta.';
    } else {
      subtitle = 'Caixa em dia — nenhuma mensagem pendente.';
    }

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
                'ATENDIMENTO WHATSAPP',
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
                total == null ? '—' : '$total',
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
                  total == 1 ? 'conversa' : 'conversas',
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
          _buildKpiStrip(context, green, amber, blue),
        ],
      ),
    );
  }

  Widget _buildKpiStrip(
      BuildContext context, Color green, Color amber, Color blue) {
    final divider = ThemeHelpers.borderColor(context).withValues(alpha: 0.45);
    final waiting = _counts[WhatsAppAttendanceTab.waiting];
    final unread = _unreadCount;
    final status = _integrationStatus;

    final String channelValue;
    final String channelSub;
    if (status == null) {
      channelValue = '—';
      channelSub = 'verificando';
    } else if (!status.hasAnyChannel) {
      channelValue = 'Off';
      channelSub = 'desconectado';
    } else if (status.activeProvider == 'both') {
      channelValue = 'Duplo';
      channelSub = 'oficial + QR';
    } else {
      channelValue = status.usesUnofficialChat ? 'QR Code' : 'Oficial';
      channelSub = status.usesUnofficialChat ? 'Baileys' : 'Meta Cloud';
    }

    final blocks = <Widget>[
      _heroKpiBlock(
        context,
        LucideIcons.mailCheck,
        'NÃO LIDAS',
        unread == null ? '—' : '$unread',
        unread == null
            ? 'aguardando'
            : unread == 0
                ? 'tudo lido'
                : 'para responder',
        green,
      ),
      _heroKpiBlock(
        context,
        LucideIcons.hourglass,
        'AGUARDANDO',
        waiting == null ? '—' : '$waiting',
        'sem atendente',
        amber,
      ),
      _heroKpiBlock(
        context,
        status?.usesUnofficialChat == true
            ? LucideIcons.qrCode
            : LucideIcons.badgeCheck,
        'CANAL',
        channelValue,
        channelSub,
        blue,
      ),
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

  // ─── Busca flush + botão de filtros ──────────────────────────────────────

  Widget _buildSearchRow(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: _buildSearchField(context)),
        const SizedBox(width: 10),
        _buildFilterButton(context),
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
                  hintText: 'Buscar contato, telefone, mensagem…',
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

  Widget _buildFilterButton(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accentColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final cardColor = ThemeHelpers.cardBackgroundColor(context);
    final active = _filters.activeCount > 0;
    final borderColor = active
        ? accent.withValues(alpha: isDark ? 0.5 : 0.42)
        : (isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.06));

    return InkWell(
      onTap: _openFilters,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: active
              ? accent.withValues(alpha: isDark ? 0.16 : 0.08)
              : cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: active ? 1.4 : 1),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              LucideIcons.listFilter,
              size: 20,
              color: active ? accent : secondary,
            ),
            if (active)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  constraints: const BoxConstraints(minWidth: 14),
                  child: Text(
                    '${_filters.activeCount}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Abas flush (rail rolável — 5 abas) ──────────────────────────────────

  Widget _buildTabsRail(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: _kPagePadH - 8),
        child: Row(
          children: [
            for (final tab in _tabs)
              _FlushTab(
                icon: _tabIcon(tab),
                label: tab.label,
                count: _counts[tab] ?? 0,
                tone: _tabColor(context, tab),
                selected: _activeTab == tab,
                onTap: () => _selectTab(tab),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Painel ativo ────────────────────────────────────────────────────────

  Widget _buildActivePanel(BuildContext context) {
    final st = _state[_activeTab]!;
    Widget child;
    if (st.loading && st.items.isEmpty) {
      child = _buildSkeleton();
    } else if (st.error != null && st.items.isEmpty) {
      child = _buildError(context, _activeTab, st.error!);
    } else if (st.items.isEmpty) {
      child = _buildEmpty(context, _activeTab);
    } else {
      child = _buildTabBody(context, _activeTab, st);
    }

    return Column(
      key: ValueKey('panel-${_activeTab.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPanelHeader(context, _activeTab),
        const SizedBox(height: 6),
        child,
      ],
    ).animate(key: ValueKey('panel-${_activeTab.name}')).fadeIn(
          duration: 240.ms,
        );
  }

  ({IconData icon, String eyebrow, String title, String hint}) _panelMeta(
      WhatsAppAttendanceTab tab) {
    switch (tab) {
      case WhatsAppAttendanceTab.all:
        return (
          icon: LucideIcons.inbox,
          eyebrow: 'TODAS',
          title: 'Caixa de entrada',
          hint: 'Todas as conversas da empresa, da mais recente à mais antiga.',
        );
      case WhatsAppAttendanceTab.waiting:
        return (
          icon: LucideIcons.hourglass,
          eyebrow: 'AGUARDANDO',
          title: 'Sem atendente',
          hint: 'Contatos esperando alguém assumir o atendimento.',
        );
      case WhatsAppAttendanceTab.inProgress:
        return (
          icon: LucideIcons.headset,
          eyebrow: 'EM ATENDIMENTO',
          title: 'Com atendente',
          hint: 'Conversas que já têm um responsável cuidando.',
        );
      case WhatsAppAttendanceTab.mine:
        return (
          icon: LucideIcons.circleUserRound,
          eyebrow: 'MINHAS',
          title: 'Meus atendimentos',
          hint: 'Conversas atribuídas a você.',
        );
      case WhatsAppAttendanceTab.finalized:
        return (
          icon: LucideIcons.circleCheckBig,
          eyebrow: 'FINALIZADAS',
          title: 'Atendimentos encerrados',
          hint: 'Uma nova mensagem do contato reabre a conversa.',
        );
    }
  }

  Widget _buildPanelHeader(BuildContext context, WhatsAppAttendanceTab tab) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = _tabColor(context, tab);
    final meta = _panelMeta(tab);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
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
      ),
    );
  }

  Widget _buildTabBody(
      BuildContext context, WhatsAppAttendanceTab tab, _TabState st) {
    var animIndex = 0;
    final nodes = <Widget>[
      for (final c in st.items)
        WhatsAppConversationCard(
          conversation: c,
          onTap: () => _openConversation(c),
        )
            .animate(key: ValueKey('wa-${c.phoneNumber}'))
            .fadeIn(
              delay: Duration(milliseconds: 25 * (animIndex++).clamp(0, 12)),
              duration: 220.ms,
            ),
    ];

    if (st.hasMore) nodes.add(_buildLoadMore(context, tab, st));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: nodes,
    );
  }

  Widget _buildLoadMore(
      BuildContext context, WhatsAppAttendanceTab tab, _TabState st) {
    final accent = _accentColor(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Center(
        child: st.loadingMore
            ? SizedBox(
                width: 22,
                height: 22,
                child:
                    CircularProgressIndicator(strokeWidth: 2.2, color: accent),
              )
            : OutlinedButton.icon(
                onPressed: () => _loadMore(tab),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  side: BorderSide(color: accent.withValues(alpha: 0.45)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(LucideIcons.chevronDown, size: 16),
                label: const Text('Carregar mais'),
              ),
      ),
    );
  }

  // ─── Estados ─────────────────────────────────────────────────────────────

  /// Skeleton fiel à linha de conversa: avatar redondo + nome/hora +
  /// preview + chips.
  Widget _buildSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(
        6,
        (_) => Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBox(width: 48, height: 48, borderRadius: 999),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Row(
                      children: [
                        Expanded(
                          child: SkeletonText(
                              width: 140, height: 15, borderRadius: 999),
                        ),
                        SizedBox(width: 8),
                        SkeletonText(width: 38, height: 11),
                      ],
                    ),
                    SizedBox(height: 8),
                    SkeletonText(width: double.infinity, height: 13),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        SkeletonText(width: 72, height: 18, borderRadius: 999),
                        SizedBox(width: 6),
                        SkeletonText(width: 56, height: 18, borderRadius: 999),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, WhatsAppAttendanceTab tab) {
    final theme = Theme.of(context);
    final tone = _tabColor(context, tab);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hasSearch = _appliedSearch.trim().isNotEmpty;
    final hasFilters = _filters.activeCount > 0;
    final (icon, title, body) = hasSearch
        ? (
            LucideIcons.searchX,
            'Nada encontrado',
            'Nenhuma conversa corresponde a "${_appliedSearch.trim()}".',
          )
        : hasFilters
            ? (
                LucideIcons.filterX,
                'Nenhum resultado',
                'Nenhuma conversa passa nos filtros ativos. Ajuste ou limpe os filtros.',
              )
            : switch (tab) {
                WhatsAppAttendanceTab.all => (
                    LucideIcons.inbox,
                    'Caixa vazia',
                    'Quando um contato mandar mensagem no WhatsApp da empresa, a conversa aparece aqui.',
                  ),
                WhatsAppAttendanceTab.waiting => (
                    LucideIcons.partyPopper,
                    'Ninguém esperando',
                    'Todos os contatos já estão sendo atendidos.',
                  ),
                WhatsAppAttendanceTab.inProgress => (
                    LucideIcons.headset,
                    'Nada em atendimento',
                    'Nenhuma conversa com atendente responsável no momento.',
                  ),
                WhatsAppAttendanceTab.mine => (
                    LucideIcons.circleUserRound,
                    'Nada atribuído a você',
                    'Quando uma conversa for atribuída a você, ela aparece aqui.',
                  ),
                WhatsAppAttendanceTab.finalized => (
                    LucideIcons.circleCheckBig,
                    'Nenhuma finalizada',
                    'Conversas encerradas ficam guardadas aqui.',
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

  Widget _buildError(
      BuildContext context, WhatsAppAttendanceTab tab, String message) {
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
            onPressed: () => _loadTab(tab, refresh: true),
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
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 13),
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
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
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
              'Você não tem acesso ao atendimento do WhatsApp.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Solicite ao administrador a permissão de visualizar mensagens do WhatsApp.',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
