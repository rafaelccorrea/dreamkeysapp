import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/purchase_proposals_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../widgets/proposal_card.dart';
import '../widgets/proposal_signatures_sheet.dart';
import 'create_proposal_page.dart';

const double _kPadH = 16;
const double _kFabBottom = 96;

Color _accent(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;
}

/// Listagem de fichas de proposta — espelha `PurchaseProposalsPage.tsx` do
/// imobx-front (mobile view).
class ProposalsPage extends StatefulWidget {
  const ProposalsPage({super.key});

  @override
  State<ProposalsPage> createState() => _ProposalsPageState();
}

class _ProposalsPageState extends State<ProposalsPage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();

  ProposalListResult? _data;
  ProposalStats? _stats;
  ProposalFilters _filters = const ProposalFilters(limit: 20);
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  bool _showDeletedOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || _loading) return;
    if (_data == null) return;
    if (_data!.page >= _data!.totalPages) return;
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 280) {
      _loadMore();
    }
  }

  ProposalFilters _withSearchAndDeleted(ProposalFilters base) {
    final s = _search.text.trim();
    return base.copyWith(
      search: s.isEmpty ? null : s,
      listDeletedOnly: _showDeletedOnly ? true : null,
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final f = _withSearchAndDeleted(_filters.copyWith(page: 1));
    final statsFut = PurchaseProposalsService.instance.getStats();
    final res = await PurchaseProposalsService.instance.list(filters: f);
    final statsRes = await statsFut;
    if (!mounted) return;
    setState(() {
      _filters = f;
      _loading = false;
      if (res.success && res.data != null) {
        _data = res.data;
        _error = null;
      } else {
        _error = res.message ?? 'Não foi possível carregar as propostas.';
      }
      if (statsRes.success && statsRes.data != null) {
        _stats = statsRes.data;
      }
    });
  }

  Future<void> _loadMore() async {
    if (_data == null) return;
    setState(() => _loadingMore = true);
    final next = _filters.copyWith(page: _data!.page + 1);
    final res = await PurchaseProposalsService.instance
        .list(filters: _withSearchAndDeleted(next));
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (res.success && res.data != null) {
        _filters = next;
        _data = ProposalListResult(
          items: [..._data!.items, ...res.data!.items],
          total: res.data!.total,
          page: res.data!.page,
          limit: res.data!.limit,
          totalPages: res.data!.totalPages,
        );
      }
    });
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const CreateProposalPage(),
      ),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Proposta criada com sucesso.')),
      );
      _load();
    }
  }

  Future<void> _openDetail(PurchaseProposal p) async {
    final canUpdate =
        ModuleAccessService.instance.hasPermission('proposal:update');
    final isOpen = p.status == ProposalStatus.processing &&
        p.deletedAt == null &&
        canUpdate;
    if (!isOpen) {
      _openSignatures(p, showHistorico: true);
      return;
    }
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateProposalPage(proposalId: p.id),
      ),
    );
    if (updated == true && mounted) {
      _load();
    }
  }

  void _openSignatures(
    PurchaseProposal p, {
    bool showHistorico = false,
    int? etapaOverride,
  }) {
    final etapa = etapaOverride ?? p.etapa.number;
    showProposalSignaturesSheet(
      context,
      proposalId: p.id,
      proposalNumber: p.proposalNumber,
      etapa: etapa,
      initialHistorico: showHistorico,
      defaultSigners: [
        if (p.proponentName != null && p.proponentEmail != null)
          ProposalSignerInput(
            email: p.proponentEmail!,
            name: p.proponentName!,
            phone: p.proponentPhone,
          ),
        if (etapa >= 2 && p.ownerName != null && p.ownerEmail != null)
          ProposalSignerInput(
            email: p.ownerEmail!,
            name: p.ownerName!,
            phone: p.ownerPhone,
          ),
      ],
      onChanged: _load,
    );
  }

  Future<void> _confirmCancelar(PurchaseProposal p) async {
    final reason = await _askReason(
      title: 'Cancelar proposta',
      message:
          'A proposta nº ${p.proposalNumber} não poderá mais ser enviada para assinatura.',
      confirmLabel: 'Cancelar proposta',
    );
    if (reason == null || !mounted) return;
    final res =
        await PurchaseProposalsService.instance.cancelar(p.id, reason);
    if (!mounted) return;
    if (res.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Proposta cancelada.')),
      );
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message ?? 'Falha ao cancelar.')),
      );
    }
  }

  Future<void> _confirmExcluir(PurchaseProposal p) async {
    final reason = await _askReason(
      title: 'Excluir proposta',
      message: 'Excluir a ficha nº ${p.proposalNumber}? Esta ação fica em auditoria.',
      confirmLabel: 'Excluir',
    );
    if (reason == null || !mounted) return;
    final res = await PurchaseProposalsService.instance.excluir(p.id, reason);
    if (!mounted) return;
    if (res.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Proposta excluída.')),
      );
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message ?? 'Falha ao excluir.')),
      );
    }
  }

  Future<String?> _askReason({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final controller = TextEditingController();
    final accent = _accent(context);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Motivo *',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Voltar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: accent),
              onPressed: () {
                final r = controller.text.trim();
                if (r.isEmpty) return;
                Navigator.of(ctx).pop(r);
              },
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return res;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ModuleAccessService.instance,
      builder: (context, _) {
        final canView =
            ModuleAccessService.instance.hasPermission('proposal:view');
        if (!canView) {
          return AppScaffold(
            title: 'Fichas de proposta',
            currentBottomNavIndex: -1,
            showBottomNavigation: false,
            body: Center(
              child: Text(
                'Sem permissão para fichas de proposta.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          );
        }
        return _buildBody(context);
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    final accent = _accent(context);
    final canCreate =
        ModuleAccessService.instance.hasPermission('proposal:create');
    final canViewAll =
        ModuleAccessService.instance.hasPermission('proposal:view_all');

    return AppScaffold(
      title: 'Fichas de proposta',
      currentBottomNavIndex: -1,
      showBottomNavigation: false,
      body: Stack(
        children: [
          RefreshIndicator(
            color: accent,
            onRefresh: _load,
            child: CustomScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ..._heroAmbientGlows(context, accent),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(_kPadH, 8, _kPadH, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _ProposalsHero(
                              accent: accent,
                              stats: _stats,
                              filteredCount: _data?.total,
                              statusFilter: _filters.status,
                              hasFilter: _filters.status != null ||
                                  _showDeletedOnly ||
                                  (_search.text.trim().isNotEmpty),
                              showingDeletedOnly: _showDeletedOnly,
                            ),
                            const SizedBox(height: 16),
                        _SearchBar(
                          controller: _search,
                          accent: accent,
                          onSubmitted: _load,
                        ),
                        const SizedBox(height: 12),
                        _StatusChips(
                          current: _filters.status,
                          accent: accent,
                          onChanged: (status) {
                            setState(() {
                              _filters = _filters.copyWith(status: status);
                            });
                            _load();
                          },
                        ),
                        if (canViewAll) ...[
                          const SizedBox(height: 10),
                          _DeletedToggle(
                            value: _showDeletedOnly,
                            accent: accent,
                            onChanged: (v) {
                              setState(() => _showDeletedOnly = v);
                              _load();
                            },
                          ),
                        ],
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: _kPadH),
                      child: Text(
                        _error!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: ThemeHelpers.textSecondaryColor(context),
                            ),
                      ),
                    ),
                  )
                else if (_data == null || _data!.items.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                        _kPadH, 0, _kPadH, _kFabBottom),
                    sliver: SliverList.separated(
                      itemCount: _data!.items.length + (_loadingMore ? 1 : 0),
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        if (i >= _data!.items.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 18),
                            child: Center(
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }
                        final p = _data!.items[i];
                        return ProposalCard(
                          proposal: p,
                          accent: accent,
                          onTap: () => _openDetail(p),
                          onContinue: () => _openSignatures(p),
                          onShowHistorico: () =>
                              _openSignatures(p, showHistorico: true),
                          onCancelar: () => _confirmCancelar(p),
                          onExcluir: () => _confirmExcluir(p),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (canCreate)
            Positioned(
              right: _kPadH,
              bottom: 22,
              child: SafeArea(
                child: _CreateFab(accent: accent, onTap: _openCreate),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _heroAmbientGlows(BuildContext context, Color accent) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final wine = isDark
        ? AppColors.secondary.secondaryDarkMode
        : AppColors.secondary.secondary;
    return [
      Positioned(
        top: -72,
        right: -48,
        child: IgnorePointer(
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  accent.withValues(alpha: isDark ? 0.22 : 0.12),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
      Positioned(
        top: 24,
        left: -56,
        child: IgnorePointer(
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  wine.withValues(alpha: isDark ? 0.16 : 0.08),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }
}

class _ProposalsHero extends StatelessWidget {
  const _ProposalsHero({
    required this.accent,
    this.stats,
    this.filteredCount,
    this.statusFilter,
    this.hasFilter = false,
    this.showingDeletedOnly = false,
  });

  final Color accent;
  final ProposalStats? stats;
  final int? filteredCount;
  final ProposalStatus? statusFilter;
  final bool hasFilter;
  final bool showingDeletedOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final isDark = theme.brightness == Brightness.dark;
    final now = DateTime.now();
    final wine = isDark
        ? AppColors.secondary.secondaryDarkMode
        : AppColors.secondary.secondary;
    final surface = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : Colors.white.withValues(alpha: 0.72);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.28 : 0.14),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            surface,
            accent.withValues(alpha: isDark ? 0.06 : 0.04),
            wine.withValues(alpha: isDark ? 0.05 : 0.03),
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: isDark ? 0.12 : 0.06),
            blurRadius: 24,
            offset: const Offset(0, 10),
            spreadRadius: -8,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Textura diagonal sutil
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _HeroMeshPainter(
                  accent: accent.withValues(alpha: isDark ? 0.07 : 0.05),
                ),
              ),
            ),
          ),
          // Barra accent superior
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accent,
                    Color.lerp(accent, wine, 0.5) ?? accent,
                    wine.withValues(alpha: 0.4),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HeroIcon(accent: accent, wine: wine),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _HeroModulePill(accent: accent),
                              _HeroMetaPill(
                                icon: Icons.calendar_today_rounded,
                                label: DateFormat('d MMM', 'pt_BR')
                                    .format(now)
                                    .toUpperCase(),
                              ),
                              _HeroMetaPill(
                                icon: Icons.schedule_rounded,
                                label: DateFormat('HH:mm', 'pt_BR').format(now),
                                mono: true,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Propostas de compra',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                              height: 1.05,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                width: 28,
                                height: 3,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(2),
                                  gradient: LinearGradient(
                                    colors: [accent, wine],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Container(
                                  height: 1,
                                  color: ThemeHelpers.borderLightColor(context)
                                      .withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Crie, edite, acompanhe etapas e envie para assinatura.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: muted,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                          if (hasFilter) ...[
                            const SizedBox(height: 10),
                            _HeroContextChips(
                              accent: accent,
                              showingDeletedOnly: showingDeletedOnly,
                              statusFilter: statusFilter,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (stats != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    height: 1,
                    color: ThemeHelpers.borderLightColor(context)
                        .withValues(alpha: 0.65),
                  ),
                  const SizedBox(height: 4),
                  _HeroKpiStrip(
                    accent: accent,
                    wine: wine,
                    total: stats!.total,
                    filteredCount: filteredCount,
                    hasFilter: hasFilter,
                    showingDeletedOnly: showingDeletedOnly,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Linhas diagonais discretas no fundo do painel hero.
class _HeroMeshPainter extends CustomPainter {
  _HeroMeshPainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = accent
      ..strokeWidth = 0.6;
    const step = 22.0;
    for (var x = -size.height; x < size.width + size.height; x += step) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HeroMeshPainter old) => old.accent != accent;
}

class _HeroModulePill extends StatelessWidget {
  const _HeroModulePill({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Text(
        'FICHAS DE PROPOSTA',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
              fontSize: 9.5,
            ),
      ),
    );
  }
}

class _HeroMetaPill extends StatelessWidget {
  const _HeroMetaPill({
    required this.icon,
    required this.label,
    this.mono = false,
  });

  final IconData icon;
  final String label;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: muted),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w800,
                  letterSpacing: mono ? 0.2 : 0.8,
                  fontFeatures: mono
                      ? const [FontFeature.tabularFigures()]
                      : null,
                  fontSize: 9.5,
                ),
          ),
        ],
      ),
    );
  }
}

class _HeroContextChips extends StatelessWidget {
  const _HeroContextChips({
    required this.accent,
    required this.showingDeletedOnly,
    this.statusFilter,
  });

  final Color accent;
  final bool showingDeletedOnly;
  final ProposalStatus? statusFilter;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    if (showingDeletedOnly) {
      chips.add(_HeroContextChip(
        label: 'Apenas excluídas',
        icon: Icons.delete_outline_rounded,
        tone: const Color(0xFFDC2626),
      ));
    }
    if (statusFilter != null) {
      final (label, tone) = switch (statusFilter!) {
        ProposalStatus.processing => ('Em andamento', const Color(0xFF6366F1)),
        ProposalStatus.finalized => ('Finalizadas', const Color(0xFF16A34A)),
        ProposalStatus.canceled => ('Canceladas', const Color(0xFFDC2626)),
      };
      chips.add(_HeroContextChip(
        label: label,
        icon: Icons.filter_alt_rounded,
        tone: tone,
      ));
    }
    if (chips.isEmpty) {
      chips.add(_HeroContextChip(
        label: 'Filtro ativo',
        icon: Icons.tune_rounded,
        tone: accent,
      ));
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: chips,
    );
  }
}

class _HeroContextChip extends StatelessWidget {
  const _HeroContextChip({
    required this.label,
    required this.icon,
    required this.tone,
  });

  final String label;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tone.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: tone),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
          ),
        ],
      ),
    );
  }
}

class _HeroIcon extends StatelessWidget {
  const _HeroIcon({required this.accent, required this.wine});

  final Color accent;
  final Color wine;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(17),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent,
            Color.lerp(accent, wine, 0.65) ?? accent,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: isDark ? 0.38 : 0.26),
            blurRadius: 18,
            offset: const Offset(0, 8),
            spreadRadius: -3,
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.22),
          width: 1.2,
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -3,
            right: -3,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.9),
                border: Border.all(color: accent, width: 2),
              ),
            ),
          ),
          Positioned(
            bottom: 7,
            left: 7,
            child: Icon(
              Icons.draw_rounded,
              size: 11,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
          const Center(
            child: Icon(
              Icons.request_page_rounded,
              color: Colors.white,
              size: 27,
            ),
          ),
        ],
      ),
    );
  }
}

/// Faixa KPI unificada — mesmo idioma visual das Anotações.
class _HeroKpiStrip extends StatelessWidget {
  const _HeroKpiStrip({
    required this.accent,
    required this.wine,
    required this.total,
    this.filteredCount,
    this.hasFilter = false,
    this.showingDeletedOnly = false,
  });

  final Color accent;
  final Color wine;
  final int total;
  final int? filteredCount;
  final bool hasFilter;
  final bool showingDeletedOnly;

  @override
  Widget build(BuildContext context) {
    final div = ThemeHelpers.borderLightColor(context).withValues(alpha: 0.7);
    final items = <_HeroKpiItem>[
      _HeroKpiItem(
        accent: accent,
        label: 'No total',
        value: '$total',
        icon: Icons.request_page_rounded,
      ),
    ];

    if (showingDeletedOnly) {
      items.add(
        _HeroKpiItem(
          accent: const Color(0xFFDC2626),
          label: 'Excluídas',
          value: filteredCount == null ? '—' : '${filteredCount!}',
          icon: Icons.delete_outline_rounded,
        ),
      );
    } else if (hasFilter) {
      items.add(
        _HeroKpiItem(
          accent: wine,
          label: 'No filtro',
          value: filteredCount == null ? '—' : '${filteredCount!}',
          icon: Icons.filter_alt_outlined,
        ),
      );
    }

    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) Container(width: 1, height: 42, color: div),
          Expanded(child: items[i]),
        ],
      ],
    );
  }
}

class _HeroKpiItem extends StatelessWidget {
  const _HeroKpiItem({
    required this.accent,
    required this.label,
    required this.value,
    required this.icon,
  });

  final Color accent;
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: accent.withValues(alpha: 0.75)),
              const SizedBox(width: 5),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: accent,
                      letterSpacing: -0.8,
                      height: 1,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: ThemeHelpers.textSecondaryColor(context),
              letterSpacing: 1.3,
              fontSize: 9.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 7),
          Container(
            height: 2.5,
            width: 22,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: LinearGradient(
                colors: [
                  accent,
                  accent.withValues(alpha: 0.35),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.accent,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final Color accent;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final border = ThemeHelpers.borderColor(context);
    return TextField(
      controller: controller,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
      decoration: InputDecoration(
        hintText: 'Buscar número, proponente, ficha…',
        isDense: true,
        prefixIcon: Icon(Icons.search_rounded, color: accent, size: 22),
        suffixIcon: IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: onSubmitted,
          tooltip: 'Atualizar',
        ),
        filled: true,
        fillColor: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.35),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border.withValues(alpha: 0.4)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border.withValues(alpha: 0.35)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent.withValues(alpha: 0.65)),
        ),
      ),
      onSubmitted: (_) => onSubmitted(),
    );
  }
}

class _StatusChips extends StatelessWidget {
  const _StatusChips({
    required this.current,
    required this.accent,
    required this.onChanged,
  });

  final ProposalStatus? current;
  final Color accent;
  final ValueChanged<ProposalStatus?> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = <(ProposalStatus?, String, Color)>[
      (null, 'Todas', accent),
      (
        ProposalStatus.processing,
        'Em andamento',
        const Color(0xFF6366F1),
      ),
      (ProposalStatus.finalized, 'Finalizadas', const Color(0xFF16A34A)),
      (ProposalStatus.canceled, 'Canceladas', const Color(0xFFDC2626)),
    ];

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (s, label, tone) = items[i];
          final selected = s == current;
          return _StatusChip(
            label: label,
            tone: tone,
            selected: selected,
            onTap: () => onChanged(s),
          );
        },
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.tone,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color tone;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? tone.withValues(alpha: 0.15)
          : Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? tone.withValues(alpha: 0.6)
                  : Colors.transparent,
              width: 1.4,
            ),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: selected
                      ? tone
                      : ThemeHelpers.textSecondaryColor(context),
                  letterSpacing: 0.2,
                ),
          ),
        ),
      ),
    );
  }
}

class _DeletedToggle extends StatelessWidget {
  const _DeletedToggle({
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value
                ? accent.withValues(alpha: 0.55)
                : ThemeHelpers.borderColor(context),
          ),
          color: value ? accent.withValues(alpha: 0.06) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? Icons.toggle_on_rounded : Icons.toggle_off_outlined,
              size: 22,
              color:
                  value ? accent : ThemeHelpers.textSecondaryColor(context),
            ),
            const SizedBox(width: 8),
            Text(
              'Apenas excluídas',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: value
                        ? accent
                        : ThemeHelpers.textSecondaryColor(context),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.request_page_outlined, size: 56, color: muted),
          const SizedBox(height: 12),
          Text(
            'Nenhuma proposta encontrada',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Toque em "Nova proposta" para registrar a primeira.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: muted,
                ),
          ),
        ],
      ),
    );
  }
}

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
                'Nova proposta',
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
