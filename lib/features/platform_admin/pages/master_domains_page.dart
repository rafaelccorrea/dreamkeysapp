import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../models/pending_domain_model.dart';
import '../services/platform_admin_service.dart';
import '../widgets/platform_admin_ui.dart';

final DateFormat _dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

/// Aba da fila de domínios — por status pendente.
enum _DomainTab { all, dns, review }

/// **Domínios de sites** (Master · `/master/domains`) — paridade compacta com
/// a `PublicSiteDomainsAdminPage` do web: fila de domínios personalizados
/// aguardando DNS ou override manual, com aprovar/rejeitar no próprio card.
///
/// Cor por SIGNIFICADO: céu = fila/identidade da tela, âmbar = aguardando
/// DNS, violeta = revisão manual, esmeralda = aprovar, rosa = rejeitar.
class MasterDomainsPage extends StatefulWidget {
  const MasterDomainsPage({super.key});

  @override
  State<MasterDomainsPage> createState() => _MasterDomainsPageState();
}

class _MasterDomainsPageState extends State<MasterDomainsPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const double _kSectionGap = 12;

  List<PendingCustomDomain> _items = const [];
  bool _loading = true;
  bool _loaded = false;
  String? _error;
  String? _busyCompanyId;

  _DomainTab _tab = _DomainTab.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ─── Dados ───────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await PlatformAdminService.instance.listPendingDomains();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loaded = true;
      if (res.success && res.data != null) {
        _items = res.data!;
      } else {
        _error = res.message ?? 'Erro ao carregar domínios pendentes';
      }
    });
  }

  ({int total, int dns, int review}) get _stats {
    final dns = _items
        .where((i) => i.domainStatus == PublicSiteDomainStatus.pendingDns)
        .length;
    final review = _items
        .where((i) => i.domainStatus == PublicSiteDomainStatus.pendingReview)
        .length;
    return (total: _items.length, dns: dns, review: review);
  }

  List<PendingCustomDomain> get _visibleItems {
    switch (_tab) {
      case _DomainTab.all:
        return _items;
      case _DomainTab.dns:
        return _items
            .where((i) => i.domainStatus == PublicSiteDomainStatus.pendingDns)
            .toList();
      case _DomainTab.review:
        return _items
            .where(
                (i) => i.domainStatus == PublicSiteDomainStatus.pendingReview)
            .toList();
    }
  }

  Color _statusTone(BuildContext context, PublicSiteDomainStatus status) {
    switch (status) {
      case PublicSiteDomainStatus.pendingDns:
        return PlatformAdminUi.amber(context);
      case PublicSiteDomainStatus.pendingReview:
        return PlatformAdminUi.violet(context);
      case PublicSiteDomainStatus.active:
        return PlatformAdminUi.emerald(context);
      case PublicSiteDomainStatus.disabled:
      case PublicSiteDomainStatus.unknown:
        return PlatformAdminUi.slate(context);
    }
  }

  // ─── Ações ───────────────────────────────────────────────────────────────

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _approve(PendingCustomDomain item) async {
    setState(() => _busyCompanyId = item.companyId);
    final res =
        await PlatformAdminService.instance.approveDomain(item.companyId);
    if (!mounted) return;
    setState(() => _busyCompanyId = null);
    _toast(res.success
        ? 'Domínio aprovado'
        : (res.message ?? 'Erro na operação'));
    if (res.success) await _load();
  }

  Future<void> _reject(PendingCustomDomain item) async {
    final danger = PlatformAdminUi.rose(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Rejeitar domínio?',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        content: Text(
          'O domínio ${item.customDomain ?? '—'} de ${item.companyName} será '
          'rejeitado/desativado. A empresa continua com o subdomínio padrão. '
          'Deseja continuar?',
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
            child: const Text('Rejeitar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busyCompanyId = item.companyId);
    final res =
        await PlatformAdminService.instance.rejectDomain(item.companyId);
    if (!mounted) return;
    setState(() => _busyCompanyId = null);
    _toast(res.success
        ? 'Domínio rejeitado'
        : (res.message ?? 'Erro na operação'));
    if (res.success) await _load();
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!PlatformAdminUi.isMasterUser) {
      return const AppScaffold(
        title: 'Domínios de sites',
        showBottomNavigation: false,
        body: MasterDeniedView(),
      );
    }
    final accent = PlatformAdminUi.sky(context);
    return AppScaffold(
      title: 'Domínios de sites',
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
                        const SizedBox(height: 14),
                        _buildFlowNote(context),
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
    final stats = _stats;
    final amber = PlatformAdminUi.amber(context);
    final violet = PlatformAdminUi.violet(context);
    final emerald = PlatformAdminUi.emerald(context);
    final hasQueue = stats.total > 0;

    return MasterHero(
      eyebrow: 'MASTER · MEU SITE',
      accent: accent,
      dotColor: hasQueue ? amber : emerald,
      countText: '${stats.total}',
      unitText:
          stats.total == 1 ? 'domínio na fila' : 'domínios na fila',
      subtitle: !_loaded
          ? 'Carregando solicitações de domínios personalizados…'
          : hasQueue
              ? 'Solicitações aguardando propagação de DNS ou override manual.'
              : 'Tudo em dia — nenhum domínio aguardando aprovação.',
      loading: _loading && !_loaded,
      kpis: [
        MasterHeroKpi(
          icon: LucideIcons.globe,
          label: 'PENDENTES',
          value: '${stats.total}',
          sub: 'na fila agora',
          tone: accent,
        ),
        MasterHeroKpi(
          icon: LucideIcons.serverCog,
          label: 'DNS',
          value: '${stats.dns}',
          sub: 'aguardando CNAME',
          tone: amber,
        ),
        MasterHeroKpi(
          icon: LucideIcons.eye,
          label: 'REVISÃO',
          value: '${stats.review}',
          sub: 'override manual',
          tone: violet,
        ),
      ],
    );
  }

  /// Nota flush sobre o fluxo normal (paridade com o InfoBanner do web).
  Widget _buildFlowNote(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final accent = PlatformAdminUi.sky(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(LucideIcons.info, size: 14, color: accent),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Fluxo normal: ',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const TextSpan(
                  text:
                      'o cliente configura o CNAME no registrador; quando '
                      'propagar, o domínio ativa sozinho. Use aprovar/rejeitar '
                      'apenas quando precisar de override Master.',
                ),
              ],
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondary,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }

  // ─── Abas flush ──────────────────────────────────────────────────────────

  Color _tabTone(BuildContext context, _DomainTab tab) {
    switch (tab) {
      case _DomainTab.all:
        return PlatformAdminUi.sky(context);
      case _DomainTab.dns:
        return PlatformAdminUi.amber(context);
      case _DomainTab.review:
        return PlatformAdminUi.violet(context);
    }
  }

  IconData _tabIcon(_DomainTab tab) {
    switch (tab) {
      case _DomainTab.all:
        return LucideIcons.globe;
      case _DomainTab.dns:
        return LucideIcons.serverCog;
      case _DomainTab.review:
        return LucideIcons.eye;
    }
  }

  String _tabLabel(_DomainTab tab) {
    switch (tab) {
      case _DomainTab.all:
        return 'Todos';
      case _DomainTab.dns:
        return 'DNS';
      case _DomainTab.review:
        return 'Revisão';
    }
  }

  int _tabCount(_DomainTab tab) {
    final stats = _stats;
    switch (tab) {
      case _DomainTab.all:
        return stats.total;
      case _DomainTab.dns:
        return stats.dns;
      case _DomainTab.review:
        return stats.review;
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
          for (final tab in _DomainTab.values)
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
      _DomainTab tab) {
    switch (tab) {
      case _DomainTab.all:
        return (
          icon: LucideIcons.globe,
          eyebrow: 'FILA DE DOMÍNIOS',
          title: 'Domínios personalizados',
          hint:
              'Solicitações que ainda precisam de acompanhamento ou override.',
        );
      case _DomainTab.dns:
        return (
          icon: LucideIcons.serverCog,
          eyebrow: 'AGUARDANDO DNS',
          title: 'CNAME em propagação',
          hint:
              'Ativam sozinhos quando o DNS propagar — aprove só se necessário.',
        );
      case _DomainTab.review:
        return (
          icon: LucideIcons.eye,
          eyebrow: 'REVISÃO MANUAL',
          title: 'Aguardando decisão Master',
          hint: 'Casos que dependem de aprovação ou rejeição manual.',
        );
    }
  }

  Widget _buildActivePanel(BuildContext context) {
    final tone = _tabTone(context, _tab);
    final meta = _panelMeta(_tab);
    final visible = _visibleItems;

    Widget child;
    if (_loading && _items.isEmpty && !_loaded) {
      child = const MasterCardSkeleton(rows: 3, showAvatar: true);
    } else if (_error != null && _items.isEmpty) {
      child = MasterErrorState(message: _error!, onRetry: _load);
    } else if (visible.isEmpty) {
      child = MasterEmptyState(
        icon: LucideIcons.inbox,
        title: 'Tudo em dia',
        body: _tab == _DomainTab.all
            ? 'Não há domínios personalizados pendentes. Quando uma empresa solicitar um domínio, ele aparecerá aqui.'
            : 'Nenhum domínio neste estado no momento.',
        tone: PlatformAdminUi.emerald(context),
      );
    } else {
      var animIndex = 0;
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in visible)
            _DomainCard(
              key: ValueKey('domain-${item.companyId}'),
              item: item,
              busy: _busyCompanyId == item.companyId,
              tone: _statusTone(context, item.domainStatus),
              onApprove: () => _approve(item),
              onReject: () => _reject(item),
            ).animate(key: ValueKey('domain-anim-${item.companyId}')).fadeIn(
                  delay:
                      Duration(milliseconds: 30 * (animIndex++).clamp(0, 12)),
                  duration: 220.ms,
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
      ],
    ).animate(key: ValueKey('panel-${_tab.name}')).fadeIn(duration: 240.ms);
  }
}

// ─── Card de domínio (ações no próprio item) ─────────────────────────────────

class _DomainCard extends StatelessWidget {
  final PendingCustomDomain item;
  final bool busy;
  final Color tone;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _DomainCard({
    super.key,
    required this.item,
    required this.busy,
    required this.tone,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final emerald = PlatformAdminUi.emerald(context);
    final rose = PlatformAdminUi.rose(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(18),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: busy ? 0.55 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                  child: Icon(LucideIcons.globe, color: tone, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.customDomain?.trim().isNotEmpty == true
                            ? item.customDomain!.trim()
                            : '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: ThemeHelpers.textColor(context),
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(LucideIcons.building2,
                              size: 12, color: secondary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              item.companyName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: secondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                MasterMiniPill(
                  label: item.domainStatus.label,
                  color: tone,
                  icon: item.domainStatus == PublicSiteDomainStatus.pendingDns
                      ? LucideIcons.serverCog
                      : item.domainStatus ==
                              PublicSiteDomainStatus.pendingReview
                          ? LucideIcons.eye
                          : LucideIcons.circleCheck,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(LucideIcons.history, size: 12, color: secondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    item.updatedAt != null
                        ? 'Atualizado em ${_dateTimeFmt.format(item.updatedAt!.toLocal())}'
                        : 'Sem data de atualização',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 10.5,
                    ),
                  ),
                ),
                Text(
                  'ID ${item.companyId.length > 8 ? '${item.companyId.substring(0, 8)}…' : item.companyId}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secondary.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w600,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 1,
              color: ThemeHelpers.borderLightColor(context)
                  .withValues(alpha: 0.7),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: busy ? null : onApprove,
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          emerald.withValues(alpha: isDark ? 0.18 : 0.12),
                      foregroundColor: emerald,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                    icon: busy
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(LucideIcons.check, size: 16),
                    label: Text(
                      busy ? 'Processando…' : 'Aprovar',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: rose,
                      side: BorderSide(color: rose.withValues(alpha: 0.45)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                    icon: const Icon(LucideIcons.x, size: 16),
                    label: const Text(
                      'Rejeitar',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
