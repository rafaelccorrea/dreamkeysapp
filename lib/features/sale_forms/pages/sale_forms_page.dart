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
                padding: EdgeInsets.fromLTRB(padH, 14, padH, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Hero(
                      accent: accent,
                      stats: _stats,
                      canCreate: canCreate,
                      onCreate: canCreate ? _openCreate : _createLocked,
                      onPendentes: _openPendentes,
                    ),
                    const SizedBox(height: 14),
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
                    const SizedBox(height: 14),
                    _PainelDeStatus(
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
                    const SizedBox(height: 12),
                    _LinhaDaLista(
                      total: _data?.total,
                      carregando: _loading,
                      excluidas: _showDeletedOnly,
                      sortBy: _filters.sortBy,
                      sortOrder: _filters.sortOrder,
                      mostrarExcluidas: canViewAll,
                      onExcluidas: () {
                        setState(() => _showDeletedOnly = !_showDeletedOnly);
                        _load();
                      },
                    ),
                  ],
                ),
              ),
            ),
            if (_loading)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(padH, 0, padH, 32),
                sliver: SliverList.builder(
                  itemCount: 7,
                  itemBuilder: (_, _) => const SaleFormCardSkeleton(),
                ),
              )
            else if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(padH, 12, padH, 0),
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
                  padding: EdgeInsets.fromLTRB(padH, 24, padH, 32),
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
                padding: EdgeInsets.fromLTRB(padH, 0, padH, 40),
                sliver: SliverList.builder(
                  itemCount: itens.length + (_loadingMore ? 1 : 0),
                  itemBuilder: (_, i) {
                    // Próxima página chegando: esqueleto fiel à linha.
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

/// Hero da lista (01/10/2026), no molde do de Imóveis: flush, título à
/// esquerda e a AÇÃO PRINCIPAL no canto superior direito. A linha de apoio
/// responde a pergunta de quem abre a tela ("quantas e quantas esperam
/// assinatura") e leva às assinaturas pendentes.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.accent,
    required this.stats,
    required this.canCreate,
    required this.onCreate,
    required this.onPendentes,
  });

  final Color accent;
  final SaleFormStats? stats;
  final bool canCreate;
  final VoidCallback onCreate;
  final VoidCallback onPendentes;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final st = stats;
    final esperando = st == null ? null : st.waitingForSignature + st.processing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                          color: accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          'VENDAS · FICHAS',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: accent,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w900,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Fichas de venda',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      height: 1.05,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _NovaFicha(accent: accent, canCreate: canCreate, onTap: onCreate),
          ],
        ),
        const SizedBox(height: 6),
        // Linha de apoio: a leitura do momento + atalho para o que espera
        // assinatura (antes era um botão grande só para isso).
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 2,
          children: [
            Text(
              st == null
                  ? 'Registre, assine e acompanhe cada venda.'
                  : '${st.total} ${st.total == 1 ? 'ficha' : 'fichas'}'
                        '${esperando != null && esperando > 0 ? ' · $esperando em assinatura' : ''}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
            InkWell(
              onTap: onPendentes,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.signature, size: 14, color: accent),
                    const SizedBox(width: 4),
                    Text(
                      'Minhas assinaturas pendentes',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// "Nova ficha" no canto do hero: compacto, na cor da marca. Sem permissão
/// continua à vista com cadeado e diz o porquê ao tocar.
class _NovaFicha extends StatelessWidget {
  const _NovaFicha({
    required this.accent,
    required this.canCreate,
    required this.onTap,
  });
  final Color accent;
  final bool canCreate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final cheio = canCreate;
    return Material(
      color: cheio ? accent : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: cheio
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ThemeHelpers.borderColor(context)),
                ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                cheio ? Icons.add_rounded : Icons.lock_outline_rounded,
                size: 19,
                color: cheio ? Colors.white : muted,
              ),
              const SizedBox(width: 6),
              Text(
                'Nova ficha',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: cheio ? Colors.white : muted,
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
            hintText: 'Nº, comprador, vendedor ou imóvel',
            isDense: true,
            prefixIcon: Icon(Icons.search_rounded, color: muted, size: 21),
            suffixIcon: sufixo,
            filled: true,
            fillColor: fill,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: borda(hair),
            enabledBorder: borda(hair),
            focusedBorder: borda(accent.withValues(alpha: 0.65), 1.4),
          ),
        );
      },
    );
  }
}

/// Painel de status — UMA faixa horizontal, sem pílulas: quatro células
/// iguais separadas por filete (número grande + rótulo), a marcada ganha o
/// traço de 3px na cor do status, como a aba ativa do app. Tocar filtra por
/// aquele status; tocar de novo volta a todas. A combinação de vários status
/// continua no modal Filtros.
///
/// Com um status marcado o back só conta esse status: as outras células
/// mostram "—" (estão fora do recorte, não são zero).
class _PainelDeStatus extends StatelessWidget {
  const _PainelDeStatus({
    required this.current,
    required this.onChanged,
    this.stats,
  });
  final Set<SaleFormStatus> current;
  final ValueChanged<Set<SaleFormStatus>> onChanged;
  final SaleFormStats? stats;

  int? _conta(SaleFormStatus s) {
    final st = stats;
    if (st == null) return null;
    if (current.isNotEmpty && !current.contains(s)) return null;
    switch (s) {
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
    final itens = <(SaleFormStatus, String, SaleFormTom)>[
      (SaleFormStatus.waitingForSignature, 'Aguardando',
          SaleFormTom.aviso(context)),
      (SaleFormStatus.processing, 'Assinando', SaleFormTom.info(context)),
      (SaleFormStatus.finalized, 'Finalizadas', SaleFormTom.sucesso(context)),
      (SaleFormStatus.canceled, 'Canceladas', SaleFormTom.erro(context)),
    ];
    final hair = ThemeHelpers.borderLightColor(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: hair), bottom: BorderSide(color: hair)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < itens.length; i++) ...[
              if (i > 0) VerticalDivider(width: 1, thickness: 1, color: hair),
              Expanded(
                child: _CelulaDeStatus(
                  rotulo: itens[i].$2,
                  tom: itens[i].$3,
                  n: _conta(itens[i].$1),
                  marcada: current.contains(itens[i].$1),
                  onTap: () {
                    final s = itens[i].$1;
                    onChanged(
                      current.length == 1 && current.contains(s)
                          ? <SaleFormStatus>{}
                          : {s},
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CelulaDeStatus extends StatelessWidget {
  const _CelulaDeStatus({
    required this.rotulo,
    required this.tom,
    required this.n,
    required this.marcada,
    required this.onTap,
  });
  final String rotulo;
  final SaleFormTom tom;
  final int? n;
  final bool marcada;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Semantics(
      button: true,
      selected: marcada,
      label: '$rotulo ${n ?? ''}',
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 10, 6, 9),
          decoration: BoxDecoration(
            color: marcada ? tom.sinal.withValues(alpha: 0.08) : null,
            border: Border(
              bottom: BorderSide(
                color: marcada ? tom.sinal : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  n == null ? '—' : '$n',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                    height: 1.05,
                    color: n == null ? muted : tom.texto,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  rotulo,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: marcada ? FontWeight.w900 : FontWeight.w700,
                    color: marcada ? ThemeHelpers.textColor(context) : muted,
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

/// Linha entre os controles e a lista: quantas fichas o recorte tem, em que
/// ordem, e (para quem vê tudo) o atalho de ver as excluídas.
class _LinhaDaLista extends StatelessWidget {
  const _LinhaDaLista({
    required this.total,
    required this.carregando,
    required this.excluidas,
    required this.sortBy,
    required this.sortOrder,
    required this.mostrarExcluidas,
    required this.onExcluidas,
  });

  final int? total;
  final bool carregando;
  final bool excluidas;
  final String sortBy;
  final String sortOrder;
  final bool mostrarExcluidas;
  final VoidCallback onExcluidas;

  static String _ordem(String by, String order) {
    final desc = order.toUpperCase() != 'ASC';
    String az(String campo) => desc ? '$campo Z→A' : '$campo A→Z';
    switch (by) {
      case 'createdAt':
        return desc ? 'mais recentes primeiro' : 'mais antigas primeiro';
      case 'formNumber':
        return desc ? 'nº maior primeiro' : 'nº menor primeiro';
      case 'buyerName':
        return az('comprador');
      case 'sellerName':
        return az('vendedor');
      case 'saleUnit':
        return az('unidade');
      case 'saleFormType':
        return az('tipo');
      case 'status':
        return az('status');
      case 'creatorName':
        return az('autor');
      default:
        return desc ? 'ordem decrescente' : 'ordem crescente';
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final erro = SaleFormTom.erro(context).texto;
    final n = total;
    final contagem = carregando || n == null
        ? 'Carregando'
        : excluidas
        ? '$n ${n == 1 ? 'excluída' : 'excluídas'}'
        : '$n ${n == 1 ? 'ficha' : 'fichas'}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: contagem.toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                      color: excluidas ? erro : ThemeHelpers.textColor(context),
                    ),
                  ),
                  TextSpan(text: '  ·  ${_ordem(sortBy, sortOrder)}'),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: muted),
            ),
          ),
          if (mostrarExcluidas)
            InkWell(
              onTap: onExcluidas,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      excluidas ? LucideIcons.arrowLeft : LucideIcons.trash2,
                      size: 14,
                      color: excluidas ? erro : muted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      excluidas ? 'Voltar às ativas' : 'Excluídas',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: excluidas ? erro : muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
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
