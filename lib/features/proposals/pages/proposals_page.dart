import 'package:flutter/material.dart';

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
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(_kPadH, 8, _kPadH, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ProposalsHero(
                          accent: accent,
                          stats: _stats,
                          filteredCount: _data?.total,
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

}

/// Hero **editorial flush** (sem banner/card) — mesmo DNA das telas de
/// Usuários e Aprovações: eyebrow com dot semântico, número grande + rótulo,
/// subtítulo contextual e faixa de KPIs.
class _ProposalsHero extends StatelessWidget {
  const _ProposalsHero({
    required this.accent,
    this.stats,
    this.filteredCount,
    this.hasFilter = false,
    this.showingDeletedOnly = false,
  });

  final Color accent;
  final ProposalStats? stats;
  final int? filteredCount;
  final bool hasFilter;
  final bool showingDeletedOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final wine = isDark
        ? AppColors.secondary.secondaryDarkMode
        : AppColors.secondary.secondary;
    final emerald =
        isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

    final total = stats?.total ?? 0;
    final dotColor =
        showingDeletedOnly ? danger : (hasFilter ? accent : emerald);
    final subtitle = showingDeletedOnly
        ? 'Mostrando apenas fichas excluídas — em auditoria.'
        : hasFilter
            ? 'Filtro aplicado · ${filteredCount ?? '—'} no resultado.'
            : 'Crie, edite, acompanhe etapas e envie para assinatura.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
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
                  color: dotColor,
                  boxShadow: [
                    BoxShadow(
                      color: dotColor.withValues(alpha: 0.55),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              Text(
                'FICHAS DE PROPOSTA',
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
                  color: textColor,
                  height: 1.0,
                  letterSpacing: -1.0,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  total == 1 ? 'proposta' : 'propostas',
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
          if (stats != null) ...[
            const SizedBox(height: 18),
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
