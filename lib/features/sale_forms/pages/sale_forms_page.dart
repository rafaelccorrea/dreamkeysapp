import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_permissions.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/sale_forms_service.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../widgets/fichas_filters_kit.dart';
import '../widgets/sale_form_card.dart';
import '../widgets/sale_form_row_actions.dart';
import '../widgets/sale_form_row_rules.dart';
import '../widgets/sale_form_tones.dart';
import '../widgets/sale_form_type_modal.dart';
import '../widgets/sale_forms_filters_sheet.dart';
import 'create_sale_form_page.dart';

const double _kPadH = 16;

/// Largura máxima do conteúdo em tablet/tela larga: a lista não estica um
/// card em 1000dp — fica centralizada e as margens crescem.
const double _kMaxConteudo = 720;

Color _accent(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;
}

/// Listagem de fichas de venda — espelha `SaleFormsPage.tsx` (web) e segue a
/// lista de Imóveis (superfície de trabalho do dia a dia): no topo o que dá
/// para fazer agora (nova ficha, assinaturas pendentes), depois busca +
/// filtros, atalhos de status com a contagem de cada um e a linha da lista
/// (quantas e em que ordem).
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
  // Guardado junto da mensagem: sem o código HTTP não dá para distinguir
  // "sem permissão" de "servidor fora do ar".
  int _errorStatus = 0;
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
        _errorStatus = 0;
      } else {
        _error = res.message;
        _errorStatus = res.statusCode;
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

  /// Tocar na linha abre a ficha em LEITURA (igual ao web); editar é uma
  /// ação do menu, bloqueada com motivo quando a ficha não pode mudar.
  Future<void> _openDetail(SaleForm f) async {
    if (await runSaleFormRowAction(context, f, SaleFormRowAction.ver) &&
        mounted) {
      _load();
    }
  }

  Future<void> _onAction(SaleForm f, SaleFormRowAction a) async {
    if (await runSaleFormRowAction(context, f, a) && mounted) _load();
  }

  /// Modal "Filtros" (paridade com `SaleFormsFiltersDrawer` do web). Limpar
  /// também desliga "Apenas excluídas", como o `handleClearFilters` do web.
  Future<void> _openFilters() async {
    final out = await showSaleFormsFiltersSheet(context, initial: _filters);
    if (out == null || !mounted) return;
    setState(() {
      _filters = out.filters;
      if (out.cleared) _showDeletedOnly = false;
    });
    _load();
  }

  /// Estado vazio de um recorte: limpa busca, filtros e "Apenas excluídas"
  /// de uma vez (o mesmo "Limpar" do modal de filtros).
  void _limparRecorte() {
    _search.clear();
    setState(() {
      _filters = _filters.withoutListFilters();
      _showDeletedOnly = false;
    });
    _load();
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

  /// "Nova ficha" travada: aparece com cadeado e diz o porquê (não some).
  void _createLocked() {
    _toast(
      'Criar fichas de venda depende de permissão. Peça ao administrador '
      'da empresa.',
    );
  }

  void _openPendentes() {
    Navigator.of(context).pushNamed(AppRoutes.saleFormsPendingSignatures);
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
          return const AppScaffold(
            title: 'Fichas de venda',
            currentBottomNavIndex: -1,
            showBottomNavigation: false,
            body: _SemAcesso(),
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
    final largura = MediaQuery.sizeOf(context).width;
    final padH = largura > _kMaxConteudo + 2 * _kPadH
        ? (largura - _kMaxConteudo) / 2
        : _kPadH;
    final buscaAplicada = _filters.search?.trim() ?? '';
    final temRecorte =
        _filters.drawerFilterCount > 0 ||
        _showDeletedOnly ||
        buscaAplicada.isNotEmpty;
    final itens = _data?.items ?? const <SaleForm>[];

    return AppScaffold(
      title: 'Fichas de venda',
      currentBottomNavIndex: -1,
      showBottomNavigation: false,
      actions: [
        // Assinaturas pendentes (web: link no topo da lista de fichas).
        IconButton(
          tooltip: 'Assinaturas pendentes',
          icon: const Icon(LucideIcons.penLine, size: 19),
          onPressed: _openPendentes,
        ),
        // Painel de fichas (paridade com "Dash Fichas Venda" do web —
        // permissão sale_form:view_dashboard; backend valida o escopo).
        if (ModuleAccessService.instance
            .hasPermission('sale_form:view_dashboard'))
          IconButton(
            tooltip: 'Dashboard de fichas',
            icon: const Icon(LucideIcons.chartColumn, size: 19),
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.saleFormsDashboard),
          ),
      ],
      body: RefreshIndicator(
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
                padding: EdgeInsets.fromLTRB(padH, 12, padH, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AcoesDoTopo(
                      accent: accent,
                      canCreate: canCreate,
                      onCreate: canCreate ? _openCreate : _createLocked,
                      onPendentes: _openPendentes,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _SearchBar(
                            controller: _search,
                            accent: accent,
                            aplicada: buscaAplicada,
                            onSubmitted: _load,
                            onClear: () {
                              _search.clear();
                              _load();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        FichasFiltersButton(
                          count: _filters.drawerFilterCount,
                          onTap: _openFilters,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _StatusChips(
                      current: _filters.effectiveStatuses.toSet(),
                      stats: _stats,
                      onChanged: (selected) {
                        setState(
                          () => _filters = _filters.copyWith(
                            status: null,
                            statuses: [
                              for (final s in SaleFormStatus.values)
                                if (selected.contains(s)) s,
                            ],
                          ),
                        );
                        _load();
                      },
                    ),
                    if (canViewAll) ...[
                      const SizedBox(height: 8),
                      _ExcluidasToggle(
                        value: _showDeletedOnly,
                        onChanged: (v) {
                          setState(() => _showDeletedOnly = v);
                          _load();
                        },
                      ),
                    ],
                    const SizedBox(height: 14),
                    _CabecalhoDaLista(
                      total: _data?.total,
                      carregando: _loading,
                      excluidas: _showDeletedOnly,
                      sortBy: _filters.sortBy,
                      sortOrder: _filters.sortOrder,
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
            if (_loading)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(padH, 0, padH, 32),
                sliver: SliverList.separated(
                  itemCount: 6,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, _) => const SaleFormCardSkeleton(),
                ),
              )
            else if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: padH),
                  child: AppErrorState.fromApi(
                    message: _error,
                    statusCode: _errorStatus,
                    onRetry: _load,
                    dense: true,
                  ),
                ),
              )
            else if (itens.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(padH, 8, padH, 32),
                  child: _EmptyState(
                    recorte: temRecorte,
                    excluidas: _showDeletedOnly,
                    canCreate: canCreate,
                    onCreate: _openCreate,
                    onLimpar: _limparRecorte,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(padH, 0, padH, 32),
                sliver: SliverList.separated(
                  itemCount: itens.length + (_loadingMore ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    // Próxima página chegando: esqueleto fiel ao card.
                    if (i >= itens.length) {
                      return const SaleFormCardSkeleton();
                    }
                    final f = itens[i];
                    return SaleFormCard(
                      saleForm: f,
                      accent: accent,
                      onTap: () => _openDetail(f),
                      onAction: (a) => _onAction(f, a),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// O que dá para fazer agora: criar uma ficha (CTA da marca — com cadeado e
/// motivo para quem não pode criar) e ver o que espera assinatura. Lado a
/// lado quando cabe; empilhado em tela estreita ou fonte grande.
class _AcoesDoTopo extends StatelessWidget {
  const _AcoesDoTopo({
    required this.accent,
    required this.canCreate,
    required this.onCreate,
    required this.onPendentes,
  });

  final Color accent;
  final bool canCreate;
  final VoidCallback onCreate;
  final VoidCallback onPendentes;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return LayoutBuilder(
      builder: (context, c) {
        // "Assinaturas pendentes" é longo: lado a lado só com folga (tablet
        // ou paisagem); no celular, um embaixo do outro, sem espremer.
        final escala = MediaQuery.textScalerOf(context).scale(1);
        final empilhar = c.maxWidth < 420 || escala > 1.25;
        final criar = _BotaoTopo(
          icon: canCreate ? Icons.add_rounded : Icons.lock_outline_rounded,
          label: 'Nova ficha',
          cor: canCreate ? accent : muted,
          cheio: canCreate,
          bloqueado: !canCreate,
          onTap: onCreate,
        );
        final pendentes = _BotaoTopo(
          icon: LucideIcons.penLine,
          label: 'Assinaturas pendentes',
          cor: SaleFormTom.sucesso(context).texto,
          cheio: false,
          onTap: onPendentes,
        );
        if (empilhar) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [criar, const SizedBox(height: 8), pendentes],
          );
        }
        return Row(
          children: [
            Expanded(child: criar),
            const SizedBox(width: 10),
            Expanded(child: pendentes),
          ],
        );
      },
    );
  }
}

class _BotaoTopo extends StatelessWidget {
  const _BotaoTopo({
    required this.icon,
    required this.label,
    required this.cor,
    required this.cheio,
    required this.onTap,
    this.bloqueado = false,
  });

  final IconData icon;
  final String label;
  final Color cor;
  final bool cheio;
  final bool bloqueado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = bloqueado
        ? ThemeHelpers.textSecondaryColor(context)
        : ThemeHelpers.textColor(context);
    final fg = cheio ? Colors.white : text;
    return Material(
      color: cheio ? cor : Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: cheio
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: ThemeHelpers.borderColor(context)),
                ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: cheio ? Colors.white : cor),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.1,
                      color: fg,
                    ),
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

/// Busca da lista: o termo só vale ao buscar (teclado ou seta). A ponta
/// direita diz o estado — seta quando há termo novo, "x" quando há busca
/// valendo (limpa e recarrega).
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.accent,
    required this.aplicada,
    required this.onSubmitted,
    required this.onClear,
  });
  final TextEditingController controller;
  final Color accent;

  /// Termo que está valendo na lista agora.
  final String aplicada;
  final VoidCallback onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final hair = ThemeHelpers.borderLightColor(context);
    final fill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    OutlineInputBorder borda(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: c, width: w),
    );
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, v, _) {
        final digitado = v.text.trim();
        Widget? sufixo;
        if (digitado.isNotEmpty && digitado != aplicada) {
          sufixo = IconButton(
            tooltip: 'Buscar',
            icon: Icon(Icons.arrow_forward_rounded, color: accent, size: 21),
            onPressed: () {
              FocusScope.of(context).unfocus();
              onSubmitted();
            },
          );
        } else if (digitado.isNotEmpty || aplicada.isNotEmpty) {
          sufixo = IconButton(
            tooltip: 'Limpar busca',
            icon: Icon(Icons.close_rounded, color: muted, size: 20),
            onPressed: onClear,
          );
        }
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
            hintText: 'Buscar nº, comprador, vendedor ou imóvel',
            isDense: true,
            prefixIcon: Icon(Icons.search_rounded, color: accent, size: 22),
            suffixIcon: sufixo,
            filled: true,
            fillColor: fill,
            contentPadding: const EdgeInsets.symmetric(vertical: 13),
            border: borda(hair),
            enabledBorder: borda(hair),
            focusedBorder: borda(accent.withValues(alpha: 0.65), 1.4),
          ),
        );
      },
    );
  }
}

/// Atalhos de status — MULTI, como o drawer do web (`statuses[]`): cada chip
/// liga/desliga o seu status; "Todas" limpa. Mesmo estado do modal Filtros.
///
/// Cada chip carrega a contagem do recorte atual. Com um status marcado o
/// back só conta esse status, então só o marcado mostra número — os outros
/// não são zero, estão fora do recorte.
class _StatusChips extends StatelessWidget {
  const _StatusChips({
    required this.current,
    required this.onChanged,
    this.stats,
  });
  final Set<SaleFormStatus> current;
  final ValueChanged<Set<SaleFormStatus>> onChanged;
  final SaleFormStats? stats;

  void _tap(SaleFormStatus? s) {
    if (s == null) {
      onChanged(<SaleFormStatus>{});
      return;
    }
    final next = {...current};
    if (!next.remove(s)) next.add(s);
    onChanged(next);
  }

  int? _conta(SaleFormStatus? s) {
    final st = stats;
    if (st == null) return null;
    final dentro = s == null
        ? current.isEmpty
        : (current.isEmpty || current.contains(s));
    if (!dentro) return null;
    switch (s) {
      case null:
        return st.total;
      case SaleFormStatus.waitingForSignature:
        return st.waitingForSignature;
      case SaleFormStatus.processing:
        return st.processing;
      case SaleFormStatus.finalized:
        return st.finalized;
      case SaleFormStatus.canceled:
        return st.canceled;
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = Theme.of(context).colorScheme.primary;
    final items = <(SaleFormStatus?, String, SaleFormTom)>[
      (null, 'Todas', SaleFormTom(brand, brand)),
      (
        SaleFormStatus.waitingForSignature,
        SaleFormStatus.waitingForSignature.shortLabel,
        SaleFormTom.aviso(context),
      ),
      (
        SaleFormStatus.processing,
        SaleFormStatus.processing.shortLabel,
        SaleFormTom.info(context),
      ),
      (
        SaleFormStatus.finalized,
        SaleFormStatus.finalized.shortLabel,
        SaleFormTom.sucesso(context),
      ),
      (
        SaleFormStatus.canceled,
        SaleFormStatus.canceled.shortLabel,
        SaleFormTom.erro(context),
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
                  tom: items[i].$3,
                  count: _conta(items[i].$1),
                  selected: items[i].$1 == null
                      ? current.isEmpty
                      : current.contains(items[i].$1),
                  onTap: () => _tap(items[i].$1),
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
    required this.tom,
    required this.selected,
    required this.onTap,
    this.count,
  });
  final String label;
  final SaleFormTom tom;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final tone = tom.sinal;
    final style = Theme.of(context).textTheme.labelMedium;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? tone.withValues(alpha: 0.13) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            // Altura mínima igual em todas as células: a grade fica alinhada
            // mesmo quando uma encolhe o conteúdo.
            constraints: const BoxConstraints(minHeight: 40),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? tone.withValues(alpha: 0.55)
                    : tone.withValues(alpha: 0.3),
                width: 1.4,
              ),
            ),
            // Rótulo + contagem nunca cortam: em 320dp encolhem juntos.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
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
                  Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: style?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: selected ? tom.texto : muted,
                      letterSpacing: 0.1,
                    ),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '$count',
                      maxLines: 1,
                      softWrap: false,
                      style: style?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: selected
                            ? tom.texto
                            : ThemeHelpers.textColor(context),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Apenas excluídas" (só quem vê tudo) — linha flush com interruptor, como
/// os atalhos de Imóveis: rótulo + o que acontece ao ligar.
class _ExcluidasToggle extends StatelessWidget {
  const _ExcluidasToggle({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tom = SaleFormTom.erro(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Semantics(
      button: true,
      toggled: value,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onChanged(!value),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(
                  value ? Icons.delete_rounded : Icons.delete_outline_rounded,
                  size: 19,
                  color: value ? tom.texto : muted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Apenas excluídas',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          height: 1.1,
                          color: value
                              ? tom.texto
                              : ThemeHelpers.textColor(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        value
                            ? 'Mostrando só as fichas excluídas (auditoria).'
                            : 'Ver as fichas excluídas, guardadas para '
                                  'auditoria.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                          fontSize: 11.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _Interruptor(ligado: value, tom: tom.sinal),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Interruptor chapado (sem degradê nem brilho) — só a trilha na cor.
class _Interruptor extends StatelessWidget {
  const _Interruptor({required this.ligado, required this.tom});
  final bool ligado;
  final Color tom;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: 44,
      height: 26,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: ligado
            ? tom
            : ThemeHelpers.borderColor(context).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        alignment: ligado ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Linha entre os controles e a lista (como a "LISTAGEM" de Imóveis):
/// quantas fichas o recorte tem e em que ordem elas estão.
class _CabecalhoDaLista extends StatelessWidget {
  const _CabecalhoDaLista({
    required this.total,
    required this.carregando,
    required this.excluidas,
    required this.sortBy,
    required this.sortOrder,
  });

  final int? total;
  final bool carregando;
  final bool excluidas;
  final String sortBy;
  final String sortOrder;

  static String _ordem(String by, String order) {
    final desc = order.toUpperCase() != 'ASC';
    String az(String campo) => desc ? '$campo: Z → A' : '$campo: A → Z';
    switch (by) {
      case 'createdAt':
        return desc ? 'Mais recentes primeiro' : 'Mais antigas primeiro';
      case 'formNumber':
        return desc ? 'Número: maior primeiro' : 'Número: menor primeiro';
      case 'buyerName':
        return az('Comprador');
      case 'sellerName':
        return az('Vendedor');
      case 'saleUnit':
        return az('Unidade');
      case 'saleFormType':
        return az('Tipo');
      case 'status':
        return az('Status');
      case 'creatorName':
        return az('Criado por');
      default:
        return desc ? 'Ordem decrescente' : 'Ordem crescente';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tom = excluidas ? SaleFormTom.erro(context).texto : _accent(context);
    final n = total;
    final contagem = carregando || n == null
        ? 'Carregando'
        : excluidas
        ? '$n ${n == 1 ? 'ficha excluída' : 'fichas excluídas'}'
        : '$n ${n == 1 ? 'ficha' : 'fichas'}';
    return Row(
      children: [
        Icon(
          excluidas ? Icons.delete_outline_rounded : Icons.view_list_rounded,
          size: 14,
          color: tom,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            contagem.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: tom,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              fontSize: 10.5,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _ordem(sortBy, sortOrder),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}

/// Vazio que ensina: o que aparece aqui e como chegar lá — e, num recorte,
/// o caminho de volta (limpar busca e filtros).
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.recorte,
    required this.excluidas,
    required this.canCreate,
    required this.onCreate,
    required this.onLimpar,
  });

  final bool recorte;
  final bool excluidas;
  final bool canCreate;
  final VoidCallback onCreate;
  final VoidCallback onLimpar;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final accent = _accent(context);
    final (icone, titulo, texto) = excluidas
        ? (
            Icons.delete_outline_rounded,
            'Nenhuma ficha excluída neste recorte',
            'As fichas excluídas ficam guardadas para auditoria e aparecem '
                'aqui. Desligue "Apenas excluídas" para voltar às fichas '
                'ativas.',
          )
        : recorte
        ? (
            LucideIcons.searchX,
            'Nenhuma ficha neste recorte',
            'A busca ou os filtros não encontraram fichas. Amplie os critérios '
                'ou limpe tudo para ver a lista completa.',
          )
        : (
            Icons.description_outlined,
            'Nenhuma ficha de venda ainda',
            canCreate
                ? 'Cada venda registrada vira uma ficha aqui, com status, '
                      'valor e o andamento das assinaturas. Toque em "Nova '
                      'ficha" para registrar a primeira.'
                : 'Cada venda registrada vira uma ficha aqui, com status, '
                      'valor e o andamento das assinaturas.',
          );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: muted.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: muted.withValues(alpha: 0.22)),
              ),
              child: Icon(icone, size: 26, color: muted),
            ),
            const SizedBox(height: 14),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: ThemeHelpers.textColor(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              texto,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: muted, height: 1.45),
            ),
            if (recorte) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onLimpar,
                icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                label: const Text('Limpar busca e filtros'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ThemeHelpers.textColor(context),
                  side: BorderSide(color: ThemeHelpers.borderColor(context)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ] else if (canCreate) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded, size: 19),
                label: const Text('Nova ficha'),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sem a permissão de ver fichas: cadeado + o que fazer (não é erro de
/// rede — tentar de novo não resolve).
class _SemAcesso extends StatelessWidget {
  const _SemAcesso();

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: muted.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: muted.withValues(alpha: 0.22)),
                ),
                child: Icon(Icons.lock_outline_rounded, size: 26, color: muted),
              ),
              const SizedBox(height: 16),
              Text(
                'Sem acesso às fichas de venda',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Seu perfil não tem a permissão de ver fichas de venda. Peça '
                'ao administrador da empresa para liberar o acesso.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, height: 1.45, color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
