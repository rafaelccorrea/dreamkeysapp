import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_permissions.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/sale_forms_service.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/file_delivery_sheet.dart';
import '../ficha_draft_store.dart';
import '../sale_form_list_display.dart';
import '../sale_forms_filters_storage.dart';
import '../sale_forms_relatorio_export.dart';
import '../widgets/fichas_filters_kit.dart';
import '../widgets/sale_form_card.dart';
import '../widgets/sale_form_report_row.dart';
import '../widgets/sale_form_row_actions.dart';
import '../widgets/sale_form_row_rules.dart';
import '../widgets/sale_form_signatures_sheet.dart';
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

  /// V-L4: "Lista operacional" × "Relatório fichas", como as abas da web.
  bool _modoRelatorio = false;
  FichaDraft? _rascunho;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _restaurarFiltrosECarregar();
    _lerRascunho();
  }

  /// Filtros guardados (web `loadSaleFormsFilters`): voltar à lista mantém
  /// busca, status, criadores, equipes, datas, ordenação e excluídas.
  Future<void> _restaurarFiltrosECarregar() async {
    final salvo = await SaleFormsFiltersStore.instance.ler(
      limit: _filters.limit,
    );
    if (!mounted) return;
    if (salvo != null) {
      _filters = salvo.filters;
      // Web: "Apenas excluídas" só vale com `sale_form:view_all` (o back
      // devolve 403 sem ela).
      _showDeletedOnly = salvo.showDeletedOnly && _podeVerExcluidas;
      _search.text = salvo.filters.search ?? '';
    }
    await _load();
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
      listDeletedOnly: _showDeletedOnly && _podeVerExcluidas ? true : null,
    );
  }

  bool get _podeVerExcluidas => ModuleAccessService.instance
      .hasPermission(AppPermissions.saleFormViewAll);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final f = _withSearchAndDeleted(_filters.copyWith(page: 1));
    // `persistListUi` do web: o recorte vale também na próxima visita.
    SaleFormsFiltersStore.instance.salvar(f, showDeletedOnly: _showDeletedOnly);
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

  /// "Itens por página" (web `PageSizePill`): recomeça da 1ª página com o
  /// novo tamanho — a rolagem infinita segue carregando de [n] em [n].
  void _mudarItensPorPagina(int n) {
    final limit = sanitizeSaleFormsPageSize(n);
    if (limit == _filters.limit) return;
    setState(() => _filters = _filters.copyWith(limit: limit));
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _load();
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

  /// Rascunho da ficha de venda guardado no aparelho (web: botão "Retomar
  /// rascunho (salvo …)" com X para descartar, ao lado de "Nova ficha").
  Future<void> _lerRascunho() async {
    final d = await FichaDraftStore.instance.ler('venda');
    if (mounted) setState(() => _rascunho = d);
  }

  Future<void> _descartarRascunho() async {
    await FichaDraftStore.instance.limpar('venda');
    if (!mounted) return;
    setState(() => _rascunho = null);
    _toast('Rascunho descartado', ok: true);
  }

  /// "Nova ficha" (web): vai direto ao modal de tipo; o rascunho tem botão
  /// próprio.
  Future<void> _openCreate() async {
    final choice = await showSaleFormTypeModal(context);
    if (choice == null || !mounted) return;
    await _abrirFormulario(choice: choice);
  }

  Future<void> _retomarRascunho() async {
    final draft = await FichaDraftStore.instance.ler('venda');
    if (!mounted) return;
    if (draft == null) {
      setState(() => _rascunho = null);
      return;
    }
    await _abrirFormulario(rascunho: draft.data);
  }

  Future<void> _abrirFormulario({
    SaleFormTypeChoice? choice,
    Map<String, dynamic>? rascunho,
  }) async {
    final created = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => CreateSaleFormPage(choice: choice, rascunho: rascunho),
      ),
    );
    if (mounted) _lerRascunho();
    if (!mounted || (created != true && created is! SaleFormCreatedResult)) {
      return;
    }
    _toast('Ficha de venda criada com sucesso.', ok: true);
    _load();
    // Web: `navigate('/fichas-venda', { state: { openSignaturesFormId } })`
    // — a lista abre as assinaturas da ficha nova.
    if (created is SaleFormCreatedResult) {
      await showSaleFormSignaturesSheet(
        context,
        saleFormId: created.id,
        formNumber: created.formNumber,
        onChanged: _load,
      );
    }
  }


  /// Relatório XLSX da lista — `ExportSaleFormsRelatorioModal` do web: busca
  /// todas as páginas do recorte atual (até 5000 fichas) com o último evento
  /// de auditoria e monta a planilha no aparelho; sai por Compartilhar ou
  /// Salvar no aparelho.
  Future<void> _exportarRelatorio() async {
    // Web: antes de exportar abre o modal para ajustar o recorte (parte do
    // recorte da lista); `userIds` só vai com `sale_form:view_all`.
    final escolha = await showSaleFormsExportSheet(
      context,
      initial: _filters,
      search: _search.text,
      deletedOnly: _showDeletedOnly,
      canViewAll: _podeVerExcluidas,
    );
    if (escolha == null || !mounted) return;
    final base = escolha.filters;
    var truncado = false;
    var quantas = 0;
    await showFileDeliverySheet(
      context,
      title: 'Relatório de fichas (Excel)',
      subtitle: 'Só entram fichas que você já pode ver no sistema.',
      paper: FileDeliveryPaper.spreadsheet,
      expectedType: 'XLSX',
      generatingTitle: 'Montando a planilha…',
      generatingHint: 'Busca todas as fichas do recorte, com o último evento '
          'de auditoria de cada uma.',
      readyTitle: 'Planilha pronta',
      readyNote: (_) => truncado
          ? 'Exportação limitada a $kSaleFormsExportMaxRows fichas. Refine '
              'período, status ou criadores para pegar o resto.'
          : '$quantas ficha(s) exportada(s). O arquivo respeita o mesmo '
              'acesso da listagem.',
      shareSubject: 'Relatório de fichas de venda',
      saveDialogTitle: 'Salvar relatório de fichas',
      load: () async {
        final res = await SaleFormsService.instance.listForExport(
          base,
          pageSize: kSaleFormsExportPageSize,
          maxRows: kSaleFormsExportMaxRows,
        );
        final data = res.data;
        if (!res.success || data == null) {
          return ApiResponse.error(
            message: res.message ?? 'Não foi possível buscar as fichas.',
            statusCode: res.statusCode,
          );
        }
        truncado = data.truncated;
        quantas = data.rows.length;
        // Web: sem fichas no recorte, não gera arquivo.
        if (quantas == 0) {
          return ApiResponse.error(
            message: 'Nenhuma ficha encontrada com estes filtros.',
            statusCode: 422,
          );
        }
        return ApiResponse.success(
          data: DeliverableFile(
            bytes: buildSaleFormsRelatorioXlsx(data.rows),
            fileName: saleFormsRelatorioFileName(DateTime.now()),
            mimeType: 'application/vnd.openxmlformats-officedocument.'
                'spreadsheetml.sheet',
          ),
          statusCode: 200,
        );
      },
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
        // Web (`fichas.routes.tsx`) e back (`GET /sistema/fichas-venda` com
        // `SALE_FORM_VIEW`) exigem `sale_form:view`; só `view_team`/`view_all`
        // abriria a tela para dar 403.
        final canView = ModuleAccessService.instance.hasPermission(
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
        // "Exportar XLSX" do web (aba Relatório fichas): mesmo recorte da
        // lista (busca, filtros e "Apenas excluídas").
        IconButton(
          tooltip: 'Exportar relatório (Excel)',
          icon: const Icon(LucideIcons.fileSpreadsheet, size: 19),
          onPressed: _loading ? null : _exportarRelatorio,
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
                padding: EdgeInsets.fromLTRB(padH, 14, padH, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Hero(
                      accent: accent,
                      stats: _stats,
                      canCreate: canCreate,
                      onCreate: _openCreate,
                      onPendentes: _openPendentes,
                      // Web: "Retomar rascunho" só com `sale_form:create`.
                      rascunhoSalvoEm: canCreate && _rascunho != null
                          ? fichaRascunhoSalvoEm(
                              _rascunho!.savedAt,
                              DateTime.now(),
                            )
                          : null,
                      onRetomar: _retomarRascunho,
                      onDescartar: _descartarRascunho,
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
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: false,
                          icon: Icon(LucideIcons.list, size: 16),
                          label: Text('Lista operacional'),
                        ),
                        ButtonSegment(
                          value: true,
                          icon: Icon(LucideIcons.clipboardCheck, size: 16),
                          label: Text('Relatório fichas'),
                        ),
                      ],
                      selected: {_modoRelatorio},
                      onSelectionChanged: (s) =>
                          setState(() => _modoRelatorio = s.first),
                    ),
                    const SizedBox(height: 10),
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
                padding: EdgeInsets.fromLTRB(padH, 0, padH, 8),
                sliver: SliverList.builder(
                  itemCount: itens.length + (_loadingMore ? 1 : 0),
                  itemBuilder: (_, i) {
                    // Próxima página chegando: esqueleto fiel à linha.
                    if (i >= itens.length) {
                      return const SaleFormCardSkeleton();
                    }
                    final f = itens[i];
                    if (_modoRelatorio) {
                      return SaleFormReportRow(
                        saleForm: f,
                        onTap: () => _openDetail(f),
                      );
                    }
                    return SaleFormCard(
                      saleForm: f,
                      accent: accent,
                      onTap: () => _openDetail(f),
                      onAction: (a) => _onAction(f, a),
                    );
                  },
                ),
              ),
            // V-L9: "página X de Y · N fichas" + itens por página (web).
            if (!_loading && _error == null && _data != null && itens.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(padH, 0, padH, 40),
                  child: _RodapePaginacao(
                    page: _data!.page,
                    totalPages: _data!.totalPages,
                    total: _data!.total,
                    limit: _filters.limit,
                    accent: accent,
                    onLimit: _mudarItensPorPagina,
                  ),
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
    required this.onRetomar,
    required this.onDescartar,
    this.rascunhoSalvoEm,
  });

  final Color accent;
  final SaleFormStats? stats;
  final bool canCreate;
  final VoidCallback onCreate;
  final VoidCallback onPendentes;
  final VoidCallback onRetomar;
  final VoidCallback onDescartar;

  /// "hoje às 10:12" etc.; `null` = sem rascunho (ou sem `create`).
  final String? rascunhoSalvoEm;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final st = stats;
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
            // Web: sem `sale_form:create` o botão não aparece.
            if (canCreate) ...[
              const SizedBox(width: 12),
              _NovaFicha(accent: accent, onTap: onCreate),
            ],
          ],
        ),
        if (rascunhoSalvoEm != null) ...[
          const SizedBox(height: 10),
          _RetomarRascunho(
            accent: accent,
            salvoEm: rascunhoSalvoEm!,
            onTap: onRetomar,
            onDescartar: onDescartar,
          ),
        ],
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
                  : saleFormsHeroResumo(st),
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

/// "Nova ficha" no canto do hero: compacto, na cor da marca. Só existe com
/// `sale_form:create` (o web esconde o botão sem a permissão).
class _NovaFicha extends StatelessWidget {
  const _NovaFicha({required this.accent, required this.onTap});
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 19, color: Colors.white),
              SizedBox(width: 6),
              Text(
                'Nova ficha',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Retomar rascunho · salvo …" com X para descartar (web `DraftWrap`).
class _RetomarRascunho extends StatelessWidget {
  const _RetomarRascunho({
    required this.accent,
    required this.salvoEm,
    required this.onTap,
    required this.onDescartar,
  });
  final Color accent;
  final String salvoEm;
  final VoidCallback onTap;
  final VoidCallback onDescartar;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final tom = SaleFormTom.aviso(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: tom.sinal.withValues(alpha: isDark ? 0.14 : 0.10),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          child: Row(
            children: [
              Icon(LucideIcons.fileClock, size: 18, color: tom.texto),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Retomar rascunho',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                    Text(
                      'salvo $salvoEm',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Descartar rascunho',
                onPressed: onDescartar,
                icon: Icon(Icons.close_rounded, size: 18, color: muted),
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
      // Mesmo rótulo curto do web (`saleFormStatusShortLabel`).
      (SaleFormStatus.processing, 'Em processo', SaleFormTom.info(context)),
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

/// Rodapé da lista (V-L9, paridade com `ListFooter` do web): onde a rolagem
/// está ("página X de Y · N fichas", o mesmo `total` do web) e o seletor
/// "Por página" 10/20/30/50 — pílulas de 40dp, alcançáveis com o polegar.
class _RodapePaginacao extends StatelessWidget {
  const _RodapePaginacao({
    required this.page,
    required this.totalPages,
    required this.total,
    required this.limit,
    required this.accent,
    required this.onLimit,
  });

  final int page;
  final int totalPages;
  final int total;
  final int limit;
  final Color accent;
  final ValueChanged<int> onLimit;

  @override
  Widget build(BuildContext context) {
    final tp = totalPages < 1 ? 1 : totalPages;
    final pg = page.clamp(1, tp);
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ThemeHelpers.borderLightColor(context)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 8,
        spacing: 12,
        children: [
          Text(
            'Página $pg de $tp · $total ${total == 1 ? 'ficha' : 'fichas'}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Por página',
                style: TextStyle(fontSize: 12, color: secundaria),
              ),
              const SizedBox(width: 6),
              for (final n in kSaleFormsPageSizes)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Semantics(
                    button: true,
                    selected: n == limit,
                    label: '$n itens por página',
                    child: Material(
                      color: n == limit
                          ? accent.withValues(alpha: 0.14)
                          : Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: n == limit
                              ? accent
                              : ThemeHelpers.borderColor(context),
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: n == limit ? null : () => onLimit(n),
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: Center(
                            child: Text(
                              '$n',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: n == limit
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: n == limit ? accent : secundaria,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}