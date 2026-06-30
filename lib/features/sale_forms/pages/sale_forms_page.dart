import 'package:flutter/material.dart';

import '../../../core/constants/app_permissions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/sale_forms_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../widgets/sale_form_card.dart';
import '../widgets/sale_form_type_modal.dart';
import 'create_sale_form_page.dart';
import 'sale_form_detail_page.dart';

const double _kPadH = 16;

Color _accent(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;
}

/// Listagem de fichas de venda — espelha `SaleFormsPage.tsx` (web) e o DNA da
/// tela de Fichas de Proposta do mobile. Fase 1: leitura + cancelar/excluir.
class SaleFormsPage extends StatefulWidget {
  const SaleFormsPage({super.key});

  @override
  State<SaleFormsPage> createState() => _SaleFormsPageState();
}

class _SaleFormsPageState extends State<SaleFormsPage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();

  SaleFormListResult? _data;
  SaleFormStats? _stats;
  SaleFormFilters _filters = const SaleFormFilters(limit: 20);
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
    if (_loadingMore || _loading || _data == null) return;
    if (_data!.page >= _data!.totalPages) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 280) {
      _loadMore();
    }
  }

  SaleFormFilters _withSearchAndDeleted(SaleFormFilters base) {
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
    final statsFut = SaleFormsService.instance.getStats(filters: f);
    final res = await SaleFormsService.instance.list(filters: f);
    final statsRes = await statsFut;
    if (!mounted) return;
    setState(() {
      _filters = f;
      _loading = false;
      if (res.success && res.data != null) {
        _data = res.data;
        _error = null;
      } else {
        _error = res.message ?? 'Não foi possível carregar as fichas de venda.';
      }
      if (statsRes.success && statsRes.data != null) {
        _stats = statsRes.data;
      }
    });
    if (mounted) FocusScope.of(context).unfocus();
  }

  Future<void> _loadMore() async {
    if (_data == null) return;
    setState(() => _loadingMore = true);
    final next = _filters.copyWith(page: _data!.page + 1);
    final res = await SaleFormsService.instance.list(
      filters: _withSearchAndDeleted(next),
    );
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (res.success && res.data != null) {
        _filters = next;
        _data = SaleFormListResult(
          items: [..._data!.items, ...res.data!.items],
          total: res.data!.total,
          page: res.data!.page,
          limit: res.data!.limit,
          totalPages: res.data!.totalPages,
        );
      }
    });
  }

  Future<void> _openDetail(SaleForm f) async {
    // Com permissão e ficha editável → abre em EDIÇÃO; senão, visualização.
    final canUpdate = ModuleAccessService.instance.hasPermission(
      AppPermissions.saleFormUpdate,
    );
    final editable =
        canUpdate &&
        f.deletedAt == null &&
        f.status != SaleFormStatus.finalized &&
        f.status != SaleFormStatus.canceled;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => editable
            ? CreateSaleFormPage(saleFormId: f.id)
            : SaleFormDetailPage(saleFormId: f.id),
      ),
    );
    if (changed == true && mounted) _load();
  }

  Future<void> _openCreate() async {
    final choice = await showSaleFormTypeModal(context);
    if (choice == null || !mounted) return;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CreateSaleFormPage(choice: choice)),
    );
    if (created == true && mounted) {
      _toast('Ficha de venda criada com sucesso.', ok: true);
      _load();
    }
  }

  Future<void> _confirmCancelar(SaleForm f) async {
    final reason = await _askReason(
      title: 'Cancelar ficha de venda',
      message:
          'A ficha nº ${f.formNumber} será cancelada e não poderá mais ser enviada para assinatura.',
      confirmLabel: 'Cancelar ficha',
    );
    if (reason == null || !mounted) return;
    final res = await SaleFormsService.instance.cancelar(f.id, reason);
    if (!mounted) return;
    _toast(
      res.success ? 'Ficha cancelada.' : (res.message ?? 'Falha ao cancelar.'),
      ok: res.success,
    );
    if (res.success) _load();
  }

  Future<void> _confirmExcluir(SaleForm f) async {
    final reason = await _askReason(
      title: 'Excluir ficha de venda',
      message:
          'Excluir a ficha nº ${f.formNumber}? Esta ação fica em auditoria.',
      confirmLabel: 'Excluir',
    );
    if (reason == null || !mounted) return;
    final res = await SaleFormsService.instance.excluir(f.id, reason);
    if (!mounted) return;
    _toast(
      res.success ? 'Ficha excluída.' : (res.message ?? 'Falha ao excluir.'),
      ok: res.success,
    );
    if (res.success) _load();
  }

  void _toast(String msg, {bool ok = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: ok ? AppColors.status.success : AppColors.status.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
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
      builder: (ctx) => AlertDialog(
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
              if (r.length < 5) return; // backend exige motivo (mín. 5)
              Navigator.of(ctx).pop(r);
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
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
            ModuleAccessService.instance.hasAnyPermission(
              AppPermissions.saleFormMenu,
            ) ||
            ModuleAccessService.instance.hasPermission(
              AppPermissions.saleFormView,
            );
        if (!canView) {
          return AppScaffold(
            title: 'Fichas de venda',
            currentBottomNavIndex: -1,
            showBottomNavigation: false,
            body: Center(
              child: Text(
                'Sem permissão para fichas de venda.',
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
    final canViewAll = ModuleAccessService.instance.hasPermission(
      AppPermissions.saleFormViewAll,
    );
    final canCreate = ModuleAccessService.instance.hasPermission(
      AppPermissions.saleFormCreate,
    );

    return AppScaffold(
      title: 'Fichas de venda',
      currentBottomNavIndex: -1,
      showBottomNavigation: false,
      body: Stack(
        children: [
          RefreshIndicator(
            color: accent,
            onRefresh: _load,
            child: CustomScrollView(
              controller: _scroll,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                        _Hero(
                          accent: accent,
                          stats: _stats,
                          filteredCount: _data?.total,
                          hasFilter:
                              _filters.status != null ||
                              _showDeletedOnly ||
                              _search.text.trim().isNotEmpty,
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
                          onChanged: (status) {
                            setState(
                              () =>
                                  _filters = _filters.copyWith(status: status),
                            );
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
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(_kPadH, 0, _kPadH, 96),
                    sliver: SliverList.separated(
                      itemCount: 6,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, _) => const SaleFormCardSkeleton(),
                    ),
                  )
                else if (_error != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: _kPadH),
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
                    padding: const EdgeInsets.fromLTRB(_kPadH, 0, _kPadH, 96),
                    sliver: SliverList.separated(
                      itemCount: _data!.items.length + (_loadingMore ? 1 : 0),
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        if (i >= _data!.items.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 18),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final f = _data!.items[i];
                        return SaleFormCard(
                          saleForm: f,
                          accent: accent,
                          onTap: () => _openDetail(f),
                          onCancelar: () => _confirmCancelar(f),
                          onExcluir: () => _confirmExcluir(f),
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
                'Nova ficha',
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

/// Hero editorial — eyebrow com dot + número grande + subtítulo.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.accent,
    this.stats,
    this.filteredCount,
    this.hasFilter = false,
    this.showingDeletedOnly = false,
  });

  final Color accent;
  final SaleFormStats? stats;
  final int? filteredCount;
  final bool hasFilter;
  final bool showingDeletedOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final emerald = isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
    final danger = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;

    final total = stats?.total ?? 0;
    final dotColor = showingDeletedOnly
        ? danger
        : (hasFilter ? accent : emerald);
    final subtitle = showingDeletedOnly
        ? 'Mostrando apenas fichas excluídas — em auditoria.'
        : hasFilter
        ? 'Filtro aplicado · ${filteredCount ?? '—'} no resultado.'
        : 'Acompanhe as vendas, status e envio para assinatura.';

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
                'FICHAS DE VENDA',
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
                  total == 1 ? 'ficha' : 'fichas',
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
            const SizedBox(height: 16),
            _StatsStrip(stats: stats!),
          ],
        ],
      ),
    );
  }
}

/// Faixa de KPIs por status (valores distintos — sem repetir o total do hero).
class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.stats});
  final SaleFormStats stats;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final divider = ThemeHelpers.borderColor(context).withValues(alpha: 0.45);
    final warn = isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
    final indigo = isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1);
    final green = isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);
    final blocks = <Widget>[
      _StatBlock(
        label: 'AGUARDANDO',
        value: stats.waitingForSignature,
        tone: warn,
      ),
      _StatBlock(label: 'EM ASSINAT.', value: stats.processing, tone: indigo),
      _StatBlock(label: 'FINALIZADAS', value: stats.finalized, tone: green),
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
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({
    required this.label,
    required this.value,
    required this.tone,
  });
  final String label;
  final int value;
  final Color tone;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: tone,
              letterSpacing: 1.0,
              height: 1.0,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            '$value',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: tone,
              letterSpacing: -0.6,
              height: 1.0,
              fontSize: 22,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'fichas',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: secondary,
              height: 1.0,
            ),
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
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      textInputAction: TextInputAction.search,
      onSubmitted: (_) {
        FocusScope.of(context).unfocus();
        onSubmitted();
      },
      decoration: InputDecoration(
        hintText: 'Buscar número, comprador, vendedor…',
        isDense: true,
        prefixIcon: Icon(Icons.search_rounded, color: accent, size: 22),
        suffixIcon: IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: onSubmitted,
          tooltip: 'Atualizar',
        ),
        filled: true,
        fillColor: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
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
    );
  }
}

class _StatusChips extends StatelessWidget {
  const _StatusChips({required this.current, required this.onChanged});
  final SaleFormStatus? current;
  final ValueChanged<SaleFormStatus?> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final items = <(SaleFormStatus?, String, Color)>[
      (null, 'Todas', Theme.of(context).colorScheme.primary),
      (
        SaleFormStatus.waitingForSignature,
        'Aguardando',
        dark ? AppColors.status.warningDarkMode : AppColors.status.warning,
      ),
      (
        SaleFormStatus.processing,
        'Em assinatura',
        dark ? AppColors.status.infoDarkMode : AppColors.status.info,
      ),
      (
        SaleFormStatus.finalized,
        'Finalizadas',
        dark ? AppColors.status.successDarkMode : AppColors.status.success,
      ),
      (
        SaleFormStatus.canceled,
        'Canceladas',
        dark ? AppColors.status.errorDarkMode : AppColors.status.error,
      ),
    ];
    // Grid de largura uniforme (2 colunas) — alinhado, sem scroll horizontal.
    // Item ímpar final ocupa a linha inteira para não deixar célula órfã.
    return LayoutBuilder(
      builder: (ctx, c) {
        const gap = 8.0;
        final half = (c.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < items.length; i++)
              SizedBox(
                width: (items.length.isOdd && i == items.length - 1)
                    ? c.maxWidth
                    : half,
                child: _StatusChip(
                  label: items[i].$2,
                  tone: items[i].$3,
                  selected: items[i].$1 == current,
                  onTap: () => onChanged(items[i].$1),
                ),
              ),
          ],
        );
      },
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
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Material(
      color: selected ? tone.withValues(alpha: 0.13) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? tone.withValues(alpha: 0.55)
                  : ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
              width: 1.4,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? tone : muted.withValues(alpha: 0.35),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: selected ? tone : muted,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
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
              color: value ? accent : ThemeHelpers.textSecondaryColor(context),
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
          Icon(Icons.description_outlined, size: 56, color: muted),
          const SizedBox(height: 12),
          Text(
            'Nenhuma ficha de venda encontrada',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Ajuste a busca ou os filtros para tentar novamente.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}
