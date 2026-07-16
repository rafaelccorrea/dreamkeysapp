import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/presence_model.dart';
import '../services/platform_admin_service.dart';
import '../widgets/platform_admin_ui.dart';

final DateFormat _timeFmt = DateFormat('HH:mm', 'pt_BR');
final DateFormat _dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

/// Aba da lista de conectados — régua de atividade do MonitoringPage web.
enum _PresenceTab { all, active, idle, away }

/// **Monitoria online** (Master · `/master/monitoring`) — paridade compacta
/// com a `MonitoringPage` do web: quem está conectado AGORA, com atividade
/// (ativo/ocioso/ausente), empresa, dispositivo, sessões e ação de
/// desconectar no próprio item. Atualiza sozinha a cada 30s enquanto aberta.
///
/// Cor por SIGNIFICADO: esmeralda = presença/ativo, âmbar = ocioso,
/// cinza = ausente, céu = conexões, violeta = pico.
class MasterMonitoringPage extends StatefulWidget {
  const MasterMonitoringPage({super.key});

  @override
  State<MasterMonitoringPage> createState() => _MasterMonitoringPageState();
}

class _MasterMonitoringPageState extends State<MasterMonitoringPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const double _kSectionGap = 12;
  static const Duration _kAutoRefresh = Duration(seconds: 30);

  PresenceOverview _overview = PresenceOverview.zero;
  List<OnlineUser> _users = const [];
  bool _loading = true;
  bool _loaded = false;
  String? _error;
  DateTime? _lastUpdated;
  String? _busyUserId;

  _PresenceTab _tab = _PresenceTab.all;

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  Timer? _autoRefresh;
  String _appliedSearch = '';

  @override
  void initState() {
    super.initState();
    _load();
    // Polling silencioso — mesma ideia do auto-refresh do MonitoringPage web.
    _autoRefresh = Timer.periodic(_kAutoRefresh, (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    _autoRefresh?.cancel();
    super.dispose();
  }

  // ─── Dados ───────────────────────────────────────────────────────────────

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final results = await Future.wait([
      PlatformAdminService.instance.getPresenceOverview(),
      PlatformAdminService.instance.getOnlineUsers(limit: 500),
    ]);
    if (!mounted) return;
    final ovRes = results[0];
    final usersRes = results[1];
    setState(() {
      _loading = false;
      _loaded = true;
      if (ovRes.success && ovRes.data is PresenceOverview) {
        _overview = ovRes.data as PresenceOverview;
      }
      if (usersRes.success && usersRes.data is OnlineUsersResult) {
        _users = (usersRes.data as OnlineUsersResult).users;
        _lastUpdated = DateTime.now();
        _error = null;
      } else if (!silent && _users.isEmpty) {
        _error = usersRes.message ?? 'Erro ao carregar a monitoria';
      }
    });
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

  // ─── Derivados ───────────────────────────────────────────────────────────

  ({int active, int idle, int away}) get _statusCounts {
    var active = 0, idle = 0, away = 0;
    for (final u in _users) {
      switch (u.activity) {
        case PresenceActivity.active:
          active++;
          break;
        case PresenceActivity.idle:
          idle++;
          break;
        case PresenceActivity.away:
          away++;
          break;
      }
    }
    return (active: active, idle: idle, away: away);
  }

  List<OnlineUser> get _visibleUsers {
    final term = _appliedSearch.toLowerCase();
    return _users.where((u) {
      switch (_tab) {
        case _PresenceTab.all:
          break;
        case _PresenceTab.active:
          if (u.activity != PresenceActivity.active) return false;
          break;
        case _PresenceTab.idle:
          if (u.activity != PresenceActivity.idle) return false;
          break;
        case _PresenceTab.away:
          if (u.activity != PresenceActivity.away) return false;
          break;
      }
      if (term.isEmpty) return true;
      final haystack =
          '${u.name} ${u.email} ${u.companyName ?? ''}'.toLowerCase();
      return haystack.contains(term);
    }).toList();
  }

  Color _activityColor(BuildContext context, PresenceActivity a) {
    switch (a) {
      case PresenceActivity.active:
        return PlatformAdminUi.emerald(context);
      case PresenceActivity.idle:
        return PlatformAdminUi.amber(context);
      case PresenceActivity.away:
        return PlatformAdminUi.slate(context);
    }
  }

  Color _roleColor(BuildContext context, String role) {
    switch (role.trim().toLowerCase()) {
      case 'master':
        return PlatformAdminUi.violet(context);
      case 'admin':
        return PlatformAdminUi.sky(context);
      case 'manager':
        return PlatformAdminUi.amber(context);
      default:
        return PlatformAdminUi.slate(context);
    }
  }

  // ─── Ações ───────────────────────────────────────────────────────────────

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _forceLogout(OnlineUser user) async {
    final danger = PlatformAdminUi.rose(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Forçar logout',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        content: Text(
          'Deseja desconectar ${user.name}? Todas as sessões ativas serão '
          'encerradas.',
          style: const TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: danger),
            child: const Text('Forçar logout'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busyUserId = user.userId);
    final res = await PlatformAdminService.instance.forceLogout(user.userId);
    if (!mounted) return;
    setState(() => _busyUserId = null);
    _toast(res.success
        ? 'Logout forçado: ${res.data?.disconnectedSockets ?? 0} conexão(ões) encerrada(s).'
        : (res.message ?? 'Não foi possível forçar o logout.'));
    if (res.success) await _load(silent: true);
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!PlatformAdminUi.isMasterUser) {
      return const AppScaffold(
        title: 'Monitoria online',
        showBottomNavigation: false,
        body: MasterDeniedView(),
      );
    }
    final accent = PlatformAdminUi.emerald(context);
    return AppScaffold(
      title: 'Monitoria online',
      showBottomNavigation: false,
      body: RefreshIndicator(
        color: accent,
        onRefresh: _load,
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
                        _buildHero(context, accent),
                        const SizedBox(height: _kSectionGap),
                        MasterSearchField(
                          controller: _searchController,
                          hint: 'Buscar nome, e-mail ou empresa…',
                          accent: accent,
                          onChanged: _onSearchChanged,
                        ),
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

  Widget _buildHero(BuildContext context, Color accent) {
    final sky = PlatformAdminUi.sky(context);
    final violet = PlatformAdminUi.violet(context);
    final amber = PlatformAdminUi.amber(context);
    final total = _overview.totalOnline;
    final subtitle = !_loaded
        ? 'Sincronizando presença em tempo real…'
        : total == 0
            ? 'Ninguém conectado no momento — a lista atualiza sozinha a cada 30s.'
            : 'Atualizado às ${_lastUpdated != null ? _timeFmt.format(_lastUpdated!) : '—'} · '
                'atualização automática a cada 30s.';

    return MasterHero(
      eyebrow: 'MASTER · MONITORIA',
      accent: accent,
      dotColor: total > 0 ? accent : PlatformAdminUi.slate(context),
      countText: '$total',
      unitText: total == 1 ? 'usuário online agora' : 'usuários online agora',
      subtitle: subtitle,
      loading: _loading && !_loaded,
      kpis: [
        MasterHeroKpi(
          icon: LucideIcons.cable,
          label: 'CONEXÕES',
          value: '${_overview.totalConnections}',
          sub: '${_overview.usersWithMultipleSessions} multi-sessão',
          tone: sky,
        ),
        MasterHeroKpi(
          icon: LucideIcons.trendingUp,
          label: 'PICO HOJE',
          value: '${_overview.peakToday}',
          sub: _overview.peakTodayAt != null
              ? 'às ${_timeFmt.format(_overview.peakTodayAt!.toLocal())}'
              : 'sem registros',
          tone: violet,
        ),
        MasterHeroKpi(
          icon: LucideIcons.building2,
          label: 'EMPRESAS',
          value: '${_overview.activeCompanies}',
          sub: 'ativas agora',
          tone: amber,
        ),
      ],
    );
  }

  // ─── Abas flush ──────────────────────────────────────────────────────────

  Color _tabTone(BuildContext context, _PresenceTab tab) {
    switch (tab) {
      case _PresenceTab.all:
        return PlatformAdminUi.sky(context);
      case _PresenceTab.active:
        return PlatformAdminUi.emerald(context);
      case _PresenceTab.idle:
        return PlatformAdminUi.amber(context);
      case _PresenceTab.away:
        return PlatformAdminUi.slate(context);
    }
  }

  IconData _tabIcon(_PresenceTab tab) {
    switch (tab) {
      case _PresenceTab.all:
        return LucideIcons.users;
      case _PresenceTab.active:
        return LucideIcons.activity;
      case _PresenceTab.idle:
        return LucideIcons.clock3;
      case _PresenceTab.away:
        return LucideIcons.moon;
    }
  }

  String _tabLabel(_PresenceTab tab) {
    switch (tab) {
      case _PresenceTab.all:
        return 'Todos';
      case _PresenceTab.active:
        return 'Ativos';
      case _PresenceTab.idle:
        return 'Ociosos';
      case _PresenceTab.away:
        return 'Ausentes';
    }
  }

  int _tabCount(_PresenceTab tab) {
    final counts = _statusCounts;
    switch (tab) {
      case _PresenceTab.all:
        return _users.length;
      case _PresenceTab.active:
        return counts.active;
      case _PresenceTab.idle:
        return counts.idle;
      case _PresenceTab.away:
        return counts.away;
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
          for (final tab in _PresenceTab.values)
            Expanded(
              child: MasterFlushTab(
                icon: _tabIcon(tab),
                label: _tabLabel(tab),
                count: _tabCount(tab),
                tone: _tabTone(context, tab),
                selected: _tab == tab,
                onTap: () => setState(() => _tab = tab),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Painel ativo ────────────────────────────────────────────────────────

  ({IconData icon, String eyebrow, String title, String hint}) _panelMeta(
      _PresenceTab tab) {
    switch (tab) {
      case _PresenceTab.all:
        return (
          icon: LucideIcons.radar,
          eyebrow: 'EQUIPE CONECTADA',
          title: 'Todos os usuários online',
          hint: 'Quem está usando o ecossistema agora, em todas as empresas.',
        );
      case _PresenceTab.active:
        return (
          icon: LucideIcons.activity,
          eyebrow: 'ATIVOS',
          title: 'Atividade nos últimos 2 minutos',
          hint: 'Interagindo com o sistema neste exato momento.',
        );
      case _PresenceTab.idle:
        return (
          icon: LucideIcons.clock3,
          eyebrow: 'OCIOSOS',
          title: 'Sem atividade há 2–15 minutos',
          hint: 'Conectados, mas parados — podem ter deixado a aba aberta.',
        );
      case _PresenceTab.away:
        return (
          icon: LucideIcons.moon,
          eyebrow: 'AUSENTES',
          title: 'Sem atividade há mais de 15 minutos',
          hint: 'Sessões abertas sem uso — candidatas a desconexão.',
        );
    }
  }

  Widget _buildActivePanel(BuildContext context) {
    final tone = _tabTone(context, _tab);
    final meta = _panelMeta(_tab);
    final visible = _visibleUsers;

    Widget child;
    if (_loading && _users.isEmpty && !_loaded) {
      child = _buildSkeleton();
    } else if (_error != null && _users.isEmpty) {
      child = MasterErrorState(message: _error!, onRetry: _load);
    } else if (visible.isEmpty) {
      final hasSearch = _appliedSearch.isNotEmpty;
      child = MasterEmptyState(
        icon: hasSearch ? LucideIcons.searchX : LucideIcons.wifiOff,
        title: hasSearch ? 'Nada encontrado' : 'Ninguém por aqui',
        body: hasSearch
            ? 'Nenhum usuário online corresponde a "$_appliedSearch".'
            : _tab == _PresenceTab.all
                ? 'Nenhum usuário conectado no momento.'
                : 'Nenhum usuário neste estado de atividade agora.',
        tone: tone,
      );
    } else {
      // Empresas com mais gente online primeiro dão contexto; a lista em si
      // segue a ordem do backend (mais recente atividade primeiro).
      var animIndex = 0;
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final user in visible)
            _OnlineUserTile(
              key: ValueKey('online-${user.userId}'),
              user: user,
              busy: _busyUserId == user.userId,
              activityColor: _activityColor(context, user.activity),
              roleColor: _roleColor(context, user.role),
              onDisconnect: () => _forceLogout(user),
            ).animate(key: ValueKey('online-anim-${user.userId}')).fadeIn(
                  delay:
                      Duration(milliseconds: 25 * (animIndex++).clamp(0, 12)),
                  duration: 200.ms,
                ),
        ],
      );
    }

    return Column(
      key: ValueKey('panel-${_tab.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MasterPanelHeader(
          icon: meta.icon,
          eyebrow: meta.eyebrow,
          title: meta.title,
          hint: meta.hint,
          tone: tone,
        ),
        const SizedBox(height: 14),
        child,
        if (visible.isNotEmpty && _overview.perCompany.isNotEmpty) ...[
          const SizedBox(height: 20),
          _buildTopCompanies(context),
        ],
      ],
    ).animate(key: ValueKey('panel-${_tab.name}')).fadeIn(duration: 240.ms);
  }

  /// Skeleton fiel à linha de usuário online (avatar + identidade + ação).
  Widget _buildSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(
        6,
        (_) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBox(width: 44, height: 44, borderRadius: 13),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonText(width: 130, height: 15),
                    SizedBox(height: 7),
                    SkeletonText(width: double.infinity, height: 12),
                    SizedBox(height: 6),
                    SkeletonText(width: 170, height: 11),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const SkeletonBox(width: 34, height: 34, borderRadius: 12),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Top empresas online ─────────────────────────────────────────────────

  Widget _buildTopCompanies(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final accent = PlatformAdminUi.emerald(context);
    final top = _overview.perCompany.take(5).toList();
    final maxOnline =
        top.fold<int>(1, (m, c) => c.online > m ? c.online : m);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.building2, size: 14, color: secondary),
            const SizedBox(width: 6),
            Text(
              'TOP EMPRESAS ONLINE',
              style: theme.textTheme.labelSmall?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Container(
                  height: 1,
                  color: ThemeHelpers.borderLightColor(context)
                      .withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < top.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: i == 0 ? 0.2 : 0.1),
                  ),
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: Text(
                    top[i].companyName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: top[i].online / maxOnline,
                      minHeight: 5,
                      backgroundColor:
                          ThemeHelpers.borderLightColor(context)
                              .withValues(alpha: 0.6),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        accent.withValues(alpha: i == 0 ? 1 : 0.55),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${top[i].online}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─── Linha de usuário online (flush, ação no próprio item) ───────────────────

class _OnlineUserTile extends StatelessWidget {
  final OnlineUser user;
  final bool busy;
  final Color activityColor;
  final Color roleColor;
  final VoidCallback onDisconnect;

  const _OnlineUserTile({
    super.key,
    required this.user,
    required this.busy,
    required this.activityColor,
    required this.roleColor,
    required this.onDisconnect,
  });

  IconData get _deviceIcon {
    switch (user.deviceKind) {
      case PresenceDeviceKind.mobile:
        return LucideIcons.smartphone;
      case PresenceDeviceKind.tablet:
        return LucideIcons.tablet;
      case PresenceDeviceKind.desktop:
        return LucideIcons.monitor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final danger = PlatformAdminUi.rose(context);

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MasterInitialsAvatar(
            initials: user.initials,
            tone: roleColor,
            statusDot: activityColor,
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
                        user.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: ThemeHelpers.textColor(context),
                          height: 1.2,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    MasterMiniPill(
                      label: user.activity.label,
                      color: activityColor,
                    ),
                    if (user.connections > 1) ...[
                      const SizedBox(width: 6),
                      MasterMiniPill(
                        label: '${user.connections}×',
                        color: PlatformAdminUi.amber(context),
                        icon: LucideIcons.cable,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  user.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 10,
                  runSpacing: 3,
                  children: [
                    _metaBit(
                      context,
                      LucideIcons.building2,
                      user.companyName ?? 'Sem empresa',
                      secondary,
                    ),
                    _metaBit(
                      context,
                      _deviceIcon,
                      [
                        if ((user.device ?? '').isNotEmpty) user.device!,
                        if ((user.browser ?? '').isNotEmpty) user.browser!,
                      ].join(' · ').ifEmptyDash(),
                      secondary,
                    ),
                    _metaBit(
                      context,
                      LucideIcons.userRound,
                      user.roleLabel,
                      roleColor,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Tooltip(
                  message: user.lastSeen != null
                      ? 'Última atividade em ${_dateTimeFmt.format(user.lastSeen!.toLocal())}'
                      : 'Sem registro de atividade',
                  child: Text(
                    'Online há ${user.onlineFor} · visto ${user.lastSeenAgo}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: secondary.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w600,
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Ação no próprio item: desconectar (com confirmação no handler).
          busy
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Tooltip(
                  message: 'Desconectar ${user.name}',
                  child: InkResponse(
                    radius: 22,
                    onTap: onDisconnect,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color:
                            danger.withValues(alpha: isDark ? 0.14 : 0.08),
                        border: Border.all(
                          color: danger.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Icon(LucideIcons.logOut,
                          size: 16, color: danger),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _metaBit(
      BuildContext context, IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: color,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

extension on String {
  String ifEmptyDash() => trim().isEmpty ? '—' : this;
}
