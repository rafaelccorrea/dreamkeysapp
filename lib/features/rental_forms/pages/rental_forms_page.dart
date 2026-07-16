import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../models/rental_form_model.dart';
import '../services/rental_forms_service.dart';
import '../widgets/rental_form_card.dart';
import '../widgets/rental_share_link_sheet.dart';
import 'rental_form_editor_page.dart';

const double _kPadH = 16;

Color _accent(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;
}

/// Listagem de fichas de locação — espelha `FichasLocacaoPage.tsx` (web) com a
/// gramática flush do app: masthead documental (headline + fluxo de etapas
/// estilo razão) + busca + chips de status + cards com ações no próprio item.
class RentalFormsPage extends StatefulWidget {
  const RentalFormsPage({super.key});

  @override
  State<RentalFormsPage> createState() => _RentalFormsPageState();
}

class _RentalFormsPageState extends State<RentalFormsPage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();

  final List<RentalForm> _items = [];
  int _total = 0;
  int _page = 1;
  static const int _limit = 20;

  bool _loading = true;
  bool _loadingMore = false;
  bool _creating = false;
  String? _error;

  /// Filtro de status aplicado no cliente (a API só suporta `search`).
  RentalFormStatus? _statusFilter;

  bool get _hasMore => _items.length < _total;

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
    if (_loadingMore || _loading || !_hasMore) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 280) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await RentalFormsService.instance.list(
      page: 1,
      limit: _limit,
      search: _search.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _items
          ..clear()
          ..addAll(res.data!.items);
        _total = res.data!.total;
        _page = res.data!.page;
        _error = null;
      } else {
        _error =
            res.message ?? 'Não foi possível carregar as fichas de locação.';
      }
    });
    if (mounted) FocusScope.of(context).unfocus();
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    final res = await RentalFormsService.instance.list(
      page: _page + 1,
      limit: _limit,
      search: _search.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (res.success && res.data != null) {
        _page = res.data!.page;
        _total = res.data!.total;
        _items.addAll(res.data!.items);
      }
    });
  }

  List<RentalForm> get _visible => _statusFilter == null
      ? _items
      : _items.where((f) => f.status == _statusFilter).toList();

  // ── Ações ────────────────────────────────────────────────────────────────

  Future<void> _openEditor(String id) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => RentalFormEditorPage(formId: id)),
    );
    // O editor tem autosave — recarrega sempre ao voltar para refletir
    // título/status/link atualizados.
    if (mounted) _load();
  }

  /// "Nova ficha" — cria com título padrão (paridade web) e abre o editor.
  Future<void> _create() async {
    if (_creating) return;
    setState(() => _creating = true);
    final title =
        'Ficha ${DateFormat('dd/MM/yyyy', 'pt_BR').format(DateTime.now())}';
    final res = await RentalFormsService.instance.create(title: title);
    if (!mounted) return;
    setState(() => _creating = false);
    if (!res.success || res.data == null) {
      _toast(res.message ?? 'Erro ao criar ficha.', error: true);
      return;
    }
    _toast('Ficha criada.');
    await _openEditor(res.data!.id);
  }

  /// Reabrir para edição (finalizada/aguardando → pendente) e abrir o editor.
  Future<void> _reopen(RentalForm f) async {
    final res = await RentalFormsService.instance
        .update(f.id, status: RentalFormStatus.pending);
    if (!mounted) return;
    if (!res.success) {
      _toast(res.message ?? 'Não foi possível reabrir a ficha.', error: true);
      return;
    }
    _toast('Ficha reaberta para edição.');
    await _openEditor(f.id);
  }

  void _shareSignature(RentalForm f) {
    final url = f.signatureUrl;
    if (RentalFormsService.isInvalidSignatureUrl(url)) {
      _toast(
        'Link de assinatura inválido. Abra a ficha e gere novamente.',
        error: true,
      );
      return;
    }
    RentalShareLinkSheet.show(
      context,
      title: 'Link de assinatura',
      subtitle: f.title?.trim().isNotEmpty == true
          ? f.title!
          : 'Ficha de locação',
      url: url!,
      whatsappMessage:
          'Olá! Segue o link para assinatura da ficha de locação:\n$url',
      icon: LucideIcons.signature,
    );
  }

  Future<void> _confirmDelete(RentalForm f) async {
    final accent = _accent(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir ficha'),
        content: Text(
          'Excluir a ficha "${f.title?.trim().isNotEmpty == true ? f.title : '(sem título)'}"? '
          'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: accent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await RentalFormsService.instance.deleteForm(f.id);
    if (!mounted) return;
    _toast(
      res.success ? 'Ficha excluída.' : (res.message ?? 'Falha ao excluir.'),
      error: !res.success,
    );
    if (res.success) _load();
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            error ? AppColors.status.error : AppColors.status.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ModuleAccessService.instance,
      builder: (context, _) {
        final canView = ModuleAccessService.instance
                .hasAnyPermission(RentalFormPermissions.menu) ||
            ModuleAccessService.instance
                .hasPermission(RentalFormPermissions.view);
        if (!canView) {
          return AppScaffold(
            title: 'Fichas de locação',
            currentBottomNavIndex: -1,
            showBottomNavigation: false,
            body: Center(
              child: Text(
                'Sem permissão para fichas de locação.',
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
    // "Nova ficha" no web exige create OU update (retomar rascunho).
    final canCreate = ModuleAccessService.instance
            .hasPermission(RentalFormPermissions.create) ||
        ModuleAccessService.instance
            .hasPermission(RentalFormPermissions.update);
    final canUpdate = ModuleAccessService.instance
        .hasPermission(RentalFormPermissions.update);
    final canDelete = ModuleAccessService.instance
        .hasPermission(RentalFormPermissions.delete);

    final visible = _visible;

    return AppScaffold(
      title: 'Fichas de locação',
      currentBottomNavIndex: -1,
      showBottomNavigation: false,
      body: Stack(
        children: [
          RefreshIndicator(
            color: accent,
            onRefresh: _load,
            child: CustomScrollView(
              controller: _scroll,
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
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
                          total: _total,
                          loaded: _items,
                          loading: _loading,
                          hasFilter: _statusFilter != null ||
                              _search.text.trim().isNotEmpty,
                          filteredCount: visible.length,
                        ),
                        const SizedBox(height: 16),
                        _SearchBar(
                          controller: _search,
                          accent: accent,
                          onSubmitted: _load,
                        ),
                        const SizedBox(height: 12),
                        _StatusChips(
                          current: _statusFilter,
                          onChanged: (s) =>
                              setState(() => _statusFilter = s),
                        ),
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
                      itemBuilder: (_, _) => const RentalFormCardSkeleton(),
                    ),
                  )
                else if (_error != null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _ErrorState(message: _error!, onRetry: _load),
                  )
                else if (visible.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(hasFilter: _statusFilter != null),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(_kPadH, 0, _kPadH, 96),
                    sliver: SliverList.separated(
                      itemCount: visible.length + (_loadingMore ? 1 : 0),
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        if (i >= visible.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 18),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final f = visible[i];
                        final reopenable = canUpdate &&
                            (f.status == RentalFormStatus.finalized ||
                                f.status ==
                                    RentalFormStatus.awaitingSignature);
                        final signable = f.status ==
                                RentalFormStatus.awaitingSignature &&
                            !RentalFormsService.isInvalidSignatureUrl(
                                f.signatureUrl);
                        return RentalFormCard(
                          form: f,
                          accent: accent,
                          onTap: () => _openEditor(f.id),
                          onReopen: reopenable ? () => _reopen(f) : null,
                          onShareSignature:
                              signable ? () => _shareSignature(f) : null,
                          onDelete:
                              canDelete ? () => _confirmDelete(f) : null,
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
                child: _CreateFab(
                  accent: accent,
                  creating: _creating,
                  onTap: _create,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CreateFab extends StatelessWidget {
  const _CreateFab({
    required this.accent,
    required this.creating,
    required this.onTap,
  });
  final Color accent;
  final bool creating;
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
        onTap: creating ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (creating)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else
                const Icon(Icons.add_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Text(
                creating ? 'Criando…' : 'Nova ficha',
                style: const TextStyle(
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

/// Masthead documental — DNA da página de perfil: eyebrow tipográfico,
/// headline w900 e subtítulo editorial, seguido do **fluxo da ficha** em
/// linhas de razão (etapa → leader → contagem) com barra de distribuição.
/// Nada de número gigante nem fileira de KPIs sublinhados.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.accent,
    required this.total,
    required this.loaded,
    required this.loading,
    required this.hasFilter,
    required this.filteredCount,
  });

  final Color accent;
  final int total;
  final List<RentalForm> loaded;
  final bool loading;
  final bool hasFilter;
  final int filteredCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    final subtitle = hasFilter
        ? 'Filtro aplicado · $filteredCount no resultado.'
        : total == 0 && !loading
            ? 'Preencha pelo sistema ou envie o link para o cliente preencher.'
            : 'Sua carteira tem ${total == 1 ? '1 ficha' : '$total fichas'} — '
                'preencha pelo sistema ou envie o link para o cliente.';

    final pending =
        loaded.where((f) => f.status == RentalFormStatus.pending).length;
    final awaiting = loaded
        .where((f) => f.status == RentalFormStatus.awaitingSignature)
        .length;
    final finalized =
        loaded.where((f) => f.status == RentalFormStatus.finalized).length;
    final canceled =
        loaded.where((f) => f.status == RentalFormStatus.canceled).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'FICHAS DE LOCAÇÃO',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.2,
                  fontSize: 10,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'DOCUMENTOS',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: secondary.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.8,
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Fichas de locação',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
              color: textColor,
              height: 1.0,
              fontSize: 27,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: secondary,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          _StageLedger(
            loading: loading,
            pending: pending,
            awaiting: awaiting,
            finalized: finalized,
            canceled: canceled,
          ),
        ],
      ),
    );
  }
}

/// Fluxo da ficha em formato de razão documental: barra de distribuição por
/// etapa + linhas "etapa … contagem" com leader pontilhado por traços.
class _StageLedger extends StatelessWidget {
  const _StageLedger({
    required this.loading,
    required this.pending,
    required this.awaiting,
    required this.finalized,
    required this.canceled,
  });

  final bool loading;
  final int pending;
  final int awaiting;
  final int finalized;
  final int canceled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final info = isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    final warn =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final green =
        isDark ? AppColors.status.successDarkMode : AppColors.status.success;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

    final sum = pending + awaiting + finalized + canceled;
    final stages = <(IconData, String, int, Color)>[
      (LucideIcons.filePen, 'Em preenchimento', pending, info),
      (LucideIcons.signature, 'Aguardando assinatura', awaiting, warn),
      (LucideIcons.fileCheck2, 'Finalizadas', finalized, green),
      if (canceled > 0)
        (LucideIcons.fileX2, 'Canceladas', canceled, danger),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Barra de distribuição por etapa (trilho neutro quando vazio).
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 8,
            child: loading || sum == 0
                ? Container(
                    color:
                        ThemeHelpers.borderColor(context).withValues(alpha: 0.4),
                  )
                : Row(
                    children: [
                      for (final (_, _, count, tone) in stages)
                        if (count > 0)
                          Expanded(
                            flex: count,
                            child: Container(color: tone),
                          ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < stages.length; i++) ...[
          if (i > 0) const SizedBox(height: 9),
          _ledgerRow(
            context,
            icon: stages[i].$1,
            label: stages[i].$2,
            count: stages[i].$3,
            tone: stages[i].$4,
          ),
        ],
      ],
    );
  }

  Widget _ledgerRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required int count,
    required Color tone,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: tone.withValues(alpha: isDark ? 0.18 : 0.1),
          ),
          child: Icon(icon, size: 14, color: tone),
        ),
        const SizedBox(width: 9),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: ThemeHelpers.textColor(context),
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          loading ? '—' : '$count',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: count > 0 || loading
                ? tone
                : ThemeHelpers.textSecondaryColor(context)
                    .withValues(alpha: 0.7),
            letterSpacing: -0.3,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
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
      style: Theme.of(context)
          .textTheme
          .bodyMedium
          ?.copyWith(fontWeight: FontWeight.w600),
      textInputAction: TextInputAction.search,
      onSubmitted: (_) {
        FocusScope.of(context).unfocus();
        onSubmitted();
      },
      decoration: InputDecoration(
        hintText: 'Buscar pelo título da ficha…',
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
    );
  }
}

class _StatusChips extends StatelessWidget {
  const _StatusChips({required this.current, required this.onChanged});
  final RentalFormStatus? current;
  final ValueChanged<RentalFormStatus?> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final items = <(RentalFormStatus?, String, Color)>[
      (null, 'Todas', Theme.of(context).colorScheme.primary),
      (
        RentalFormStatus.pending,
        'Pendentes',
        dark ? AppColors.status.infoDarkMode : AppColors.status.info,
      ),
      (
        RentalFormStatus.awaitingSignature,
        'Aguardando',
        dark ? AppColors.status.warningDarkMode : AppColors.status.warning,
      ),
      (
        RentalFormStatus.finalized,
        'Finalizadas',
        dark ? AppColors.status.successDarkMode : AppColors.status.success,
      ),
      (
        RentalFormStatus.canceled,
        'Canceladas',
        dark ? AppColors.status.errorDarkMode : AppColors.status.error,
      ),
    ];
    // Grid alinhado em 2 colunas; item ímpar final ocupa a linha inteira.
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
                  : tone.withValues(alpha: 0.3),
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
                  color: selected ? tone : tone.withValues(alpha: 0.6),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasFilter});
  final bool hasFilter;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.clipboardList, size: 56, color: muted),
          const SizedBox(height: 12),
          Text(
            hasFilter
                ? 'Nenhuma ficha neste status'
                : 'Nenhuma ficha de locação ainda',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            hasFilter
                ? 'Ajuste o filtro ou a busca para tentar novamente.'
                : 'Toque em «Nova ficha» para criar a primeira.',
            textAlign: TextAlign.center,
            style:
                Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final accent = _accent(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.cloudOff, size: 52, color: muted),
          const SizedBox(height: 12),
          Text(
            'Não foi possível carregar',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style:
                Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              foregroundColor: accent,
              side: BorderSide(color: accent.withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text(
              'Tentar novamente',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
