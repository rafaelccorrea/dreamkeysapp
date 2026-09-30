import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/purchase_proposals_service.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../sale_forms/widgets/fichas_filters_kit.dart';
import '../../sale_forms/widgets/sale_form_tones.dart';
import '../widgets/proposal_card.dart';
import '../widgets/proposal_row_actions.dart';
import '../widgets/proposal_signatures_sheet.dart';
import '../widgets/proposals_filters_sheet.dart';
import 'proposals_dashboard_page.dart';
import 'create_proposal_page.dart';

const double _kPadH = 16;

/// Largura máxima do conteúdo em tablet/tela larga: a lista não estica uma
/// linha em 1000dp — fica centralizada e as margens crescem.
const double _kMaxConteudo = 720;

final NumberFormat _inteiro = NumberFormat.decimalPattern('pt_BR');

Color _accent(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;
}

/// Contagem da base (`GET /fichas-proposta/stats`): o back devolve o total e
/// o total de cada status (o web mostra os quatro). O `ProposalStats`
/// compartilhado só lê o total, então a lista lê o mesmo JSON aqui — uma
/// chamada só, como antes.
class _Contagem {
  const _Contagem({
    required this.total,
    required this.processing,
    required this.finalized,
    required this.canceled,
  });

  final int total;
  final int? processing;
  final int? finalized;
  final int? canceled;

  static int? _n(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}');
  }

  factory _Contagem.fromJson(Map<String, dynamic> j) => _Contagem(
    total: _n(j['total']) ?? 0,
    processing: _n(j['processing']),
    finalized: _n(j['finalized']),
    canceled: _n(j['canceled']),
  );

  int? doStatus(ProposalStatus s) {
    switch (s) {
      case ProposalStatus.processing:
        return processing;
      case ProposalStatus.finalized:
        return finalized;
      case ProposalStatus.canceled:
        return canceled;
    }
  }
}

Future<_Contagem?> _carregarContagem() async {
  try {
    final res = await ApiService.instance.get<Map<String, dynamic>>(
      ApiConstants.purchaseProposalsStats,
    );
    if (!res.success || res.data == null) return null;
    return _Contagem.fromJson(res.data!);
  } catch (_) {
    return null;
  }
}

/// Listagem de fichas de proposta — espelha `PurchaseProposalsPage.tsx` do
/// imobx-front e segue o molde da lista de fichas de venda (01/10/2026): no
/// topo o hero com a ação principal no canto, depois busca + filtros, o
/// painel de status com a contagem de cada um e a linha da lista (quantas e
/// em que ordem); cada proposta é uma linha flush com a etapa da assinatura
/// e a ação da etapa ali mesmo.
class ProposalsPage extends StatefulWidget {
  const ProposalsPage({super.key});

  @override
  State<ProposalsPage> createState() => _ProposalsPageState();
}

class _ProposalsPageState extends State<ProposalsPage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();

  ProposalListResult? _data;
  _Contagem? _stats;
  ProposalFilters _filters = const ProposalFilters(limit: 20);
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
    final statsFut = _carregarContagem();
    final res = await PurchaseProposalsService.instance.list(filters: f);
    final stats = await statsFut;
    if (!mounted) return;
    setState(() {
      _filters = f;
      _loading = false;
      if (res.success && res.data != null) {
        _data = res.data;
        _error = null;
        _errorStatus = 0;
      } else {
        _error = res.message ?? 'Não foi possível carregar as propostas.';
        _errorStatus = res.statusCode;
      }
      if (stats != null) _stats = stats;
    });
    if (mounted) FocusScope.of(context).unfocus();
  }

  Future<void> _loadMore() async {
    if (_data == null) return;
    setState(() => _loadingMore = true);
    final next = _filters.copyWith(page: _data!.page + 1);
    final res = await PurchaseProposalsService.instance.list(
      filters: _withSearchAndDeleted(next),
    );
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

  /// Modal "Filtros" (paridade com o drawer do web). Limpar também desliga
  /// "Apenas excluídas", como o `clearDrawerFilters` do web.
  Future<void> _openFilters(bool canViewAll) async {
    final out = await showProposalsFiltersSheet(
      context,
      initial: _filters,
      canViewAll: canViewAll,
    );
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

  // ─── Navegação ───────────────────────────────────────────────────────────

  Future<void> _openCreate() async {
    final created = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const CreateProposalPage()));
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Proposta criada com sucesso.')),
      );
      _load();
    }
  }

  /// "Nova proposta" travada: aparece com cadeado e diz o porquê (não some).
  void _createLocked() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Criar fichas de proposta depende de permissão. Peça ao '
          'administrador da empresa.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openDetail(PurchaseProposal p) async {
    final canUpdate = ModuleAccessService.instance.hasPermission(
      'proposal:update',
    );
    final isOpen =
        p.status == ProposalStatus.processing &&
        p.deletedAt == null &&
        canUpdate;
    if (!isOpen) {
      _openSignatures(p, showHistorico: true);
      return;
    }
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CreateProposalPage(proposalId: p.id)),
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

  /// Folha de ações da linha (espelho do menu do web). Navegação fica aqui;
  /// o resto no despachante compartilhado.
  Future<void> _onAction(PurchaseProposal p, ProposalRowAction a) async {
    switch (a) {
      case ProposalRowAction.assinaturas:
        _openSignatures(p);
        return;
      case ProposalRowAction.historico:
        _openSignatures(p, showHistorico: true);
        return;
      case ProposalRowAction.editar:
        final updated = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => CreateProposalPage(proposalId: p.id),
          ),
        );
        if (updated == true && mounted) _load();
        return;
      default:
        if (await runProposalRowAction(context, p, a) && mounted) _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ModuleAccessService.instance,
      builder: (context, _) {
        final canView = ModuleAccessService.instance.hasPermission(
          'proposal:view',
        );
        if (!canView) {
          return const AppScaffold(
            title: 'Fichas de proposta',
            currentBottomNavIndex: -1,
            showBottomNavigation: false,
            body: _LockedState(),
          );
        }
        return _buildBody(context);
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    final accent = _accent(context);
    final canCreate = ModuleAccessService.instance.hasPermission(
      'proposal:create',
    );
    final canViewAll = ModuleAccessService.instance.hasPermission(
      'proposal:view_all',
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
    final itens = _data?.items ?? const <PurchaseProposal>[];

    return AppScaffold(
      title: 'Fichas de proposta',
      currentBottomNavIndex: -1,
      showBottomNavigation: false,
      actions: [
        // Painel de propostas (web: /fichas-proposta/dashboard).
        if (ProposalsDashboardPage.canOpen())
          IconButton(
            tooltip: 'Dashboard de propostas',
            icon: const Icon(LucideIcons.chartColumn, size: 19),
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.proposalsDashboard),
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
                          onTap: () => _openFilters(canViewAll),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _PainelDeStatus(
                      current: _filters.status,
                      // A contagem do back é das ATIVAS: no modo "excluídas"
                      // as células ficam em "—" (fora do recorte, não zero).
                      stats: _showDeletedOnly ? null : _stats,
                      onChanged: (status) {
                        setState(
                          () => _filters = _filters.copyWith(status: status),
                        );
                        _load();
                      },
                    ),
                    const SizedBox(height: 12),
                    _LinhaDaLista(
                      total: _data?.total,
                      base: _stats?.total,
                      recorte: temRecorte,
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
                  itemBuilder: (_, _) => const ProposalCardSkeleton(),
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
                      return const ProposalCardSkeleton();
                    }
                    final p = itens[i];
                    return ProposalCard(
                      proposal: p,
                      accent: accent,
                      onTap: () => _openDetail(p),
                      onContinue: () => _openSignatures(p),
                      onShowHistorico: () =>
                          _openSignatures(p, showHistorico: true),
                      onAction: (a) => _onAction(p, a),
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

/// Hero da lista (01/10/2026), no molde do de fichas de venda: flush, título
/// à esquerda e a AÇÃO PRINCIPAL no canto superior direito. A linha de apoio
/// responde a pergunta de quem abre a tela ("quantas e quantas ainda estão
/// em assinatura").
class _Hero extends StatelessWidget {
  const _Hero({
    required this.accent,
    required this.stats,
    required this.canCreate,
    required this.onCreate,
  });

  final Color accent;
  final _Contagem? stats;
  final bool canCreate;
  final VoidCallback onCreate;

  static const String _titulo = 'Fichas de proposta';
  static const TextStyle _estiloTitulo = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w900,
    letterSpacing: -0.5,
    height: 1.05,
  );

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final st = stats;
    final andamento = st?.processing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            // "Nova proposta" inteiro só quando cabe AO LADO do título numa
            // linha (320dp, texto a 130%, deitado); senão vira "Nova" — o
            // título nunca é cortado pelo botão.
            final base = DefaultTextStyle.of(context).style;
            final scaler = MediaQuery.textScalerOf(context);
            double medir(String s, TextStyle estilo) {
              final tp = TextPainter(
                text: TextSpan(text: s, style: base.merge(estilo)),
                maxLines: 1,
                textDirection: Directionality.of(context),
                textScaler: scaler,
              )..layout();
              final w = tp.width;
              tp.dispose();
              return w;
            }

            final wTitulo = medir(_titulo, _estiloTitulo);
            final wBotao =
                medir('Nova proposta', _NovaProposta.estiloRotulo) + 28 + 25;
            final inteiro = wTitulo + 12 + wBotao <= c.maxWidth;
            return Row(
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
                              'VENDAS · PROPOSTAS',
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
                        _titulo,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _estiloTitulo.copyWith(
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _NovaProposta(
                  accent: accent,
                  canCreate: canCreate,
                  rotulo: inteiro ? 'Nova proposta' : 'Nova',
                  onTap: onCreate,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        // Linha de apoio: a leitura do momento (antes um número gigante
        // solto no topo, sem título nem ação).
        Text(
          st == null
              ? 'Registre a proposta e colha as assinaturas em três etapas.'
              : '${_inteiro.format(st.total)} '
                    '${st.total == 1 ? 'proposta' : 'propostas'}'
                    '${andamento != null && andamento > 0 ? ' · ${_inteiro.format(andamento)} em andamento' : ''}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: muted,
          ),
        ),
      ],
    );
  }
}

/// "Nova proposta" no canto do hero: compacto, na cor da marca. Sem
/// permissão continua à vista com cadeado e diz o porquê ao tocar.
class _NovaProposta extends StatelessWidget {
  const _NovaProposta({
    required this.accent,
    required this.canCreate,
    required this.rotulo,
    required this.onTap,
  });
  final Color accent;
  final bool canCreate;
  final String rotulo;
  final VoidCallback onTap;

  static const TextStyle estiloRotulo = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w800,
  );

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final cheio = canCreate;
    return Semantics(
      button: true,
      label: cheio ? 'Nova proposta' : 'Nova proposta (sem permissão)',
      excludeSemantics: true,
      child: Material(
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
                    border: Border.all(
                      color: ThemeHelpers.borderColor(context),
                    ),
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
                  rotulo,
                  maxLines: 1,
                  softWrap: false,
                  style: estiloRotulo.copyWith(
                    color: cheio ? Colors.white : muted,
                  ),
                ),
              ],
            ),
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
            hintText: 'Nº da proposta ou comprador',
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

/// Painel de status — UMA faixa horizontal, sem pílulas: três células
/// iguais separadas por filete (número grande + rótulo), a marcada ganha o
/// traço de 3px na cor do status, como a aba ativa do app. Tocar filtra por
/// aquele status; tocar de novo volta a todas (o status também está no modal
/// Filtros).
///
/// A contagem é da base (`/stats`, como no web): não muda com a busca nem
/// com os filtros — o recorte está na linha da lista logo abaixo.
class _PainelDeStatus extends StatelessWidget {
  const _PainelDeStatus({
    required this.current,
    required this.onChanged,
    this.stats,
  });
  final ProposalStatus? current;
  final ValueChanged<ProposalStatus?> onChanged;
  final _Contagem? stats;

  @override
  Widget build(BuildContext context) {
    final itens = <(ProposalStatus, String)>[
      (ProposalStatus.processing, 'Em andamento'),
      (ProposalStatus.finalized, 'Finalizadas'),
      (ProposalStatus.canceled, 'Canceladas'),
    ];
    final hair = ThemeHelpers.borderLightColor(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: hair),
          bottom: BorderSide(color: hair),
        ),
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
                  tom: proposalStatusTom(context, itens[i].$1),
                  n: stats?.doStatus(itens[i].$1),
                  marcada: current == itens[i].$1,
                  onTap: () {
                    final s = itens[i].$1;
                    onChanged(current == s ? null : s);
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
                  n == null ? '—' : _inteiro.format(n),
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

/// Linha entre os controles e a lista: quantas propostas o recorte tem (e de
/// quantas na base), em que ordem, e (para quem vê tudo) o atalho de ver as
/// excluídas.
class _LinhaDaLista extends StatelessWidget {
  const _LinhaDaLista({
    required this.total,
    required this.base,
    required this.recorte,
    required this.carregando,
    required this.excluidas,
    required this.sortBy,
    required this.sortOrder,
    required this.mostrarExcluidas,
    required this.onExcluidas,
  });

  /// Resultado do recorte atual (`total` da listagem).
  final int? total;

  /// Base inteira (`/stats`).
  final int? base;
  final bool recorte;
  final bool carregando;
  final bool excluidas;
  final String sortBy;
  final String sortOrder;
  final bool mostrarExcluidas;
  final VoidCallback onExcluidas;

  static String _ordem(String by, String order) {
    final desc = order.toUpperCase() != 'ASC';
    switch (by) {
      case 'proposalNumber':
        return desc ? 'nº maior primeiro' : 'nº menor primeiro';
      case 'status':
        return 'por status';
      case 'proponentName':
        return desc ? 'comprador Z→A' : 'comprador A→Z';
      case 'proposedPrice':
        return desc ? 'maior valor primeiro' : 'menor valor primeiro';
      case 'validityDays':
        return desc ? 'maior validade primeiro' : 'menor validade primeiro';
      case 'creatorName':
        return desc ? 'autor Z→A' : 'autor A→Z';
      default:
        return desc ? 'mais recentes primeiro' : 'mais antigas primeiro';
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final erro = SaleFormTom.erro(context).texto;
    final n = total;
    final b = base;
    final contagem = carregando || n == null
        ? 'Carregando'
        : excluidas
        ? '${_inteiro.format(n)} ${n == 1 ? 'excluída' : 'excluídas'}'
        : '${_inteiro.format(n)} ${n == 1 ? 'proposta' : 'propostas'}';
    // Num recorte, "de quantas" na base — a mesma leitura do cabeçalho de
    // antes ("no recorte, de N no total"), agora numa linha só.
    final deBase =
        !carregando &&
            !excluidas &&
            recorte &&
            n != null &&
            b != null &&
            b != n
        ? '  ·  de ${_inteiro.format(b)}'
        : '';
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
                  TextSpan(text: '$deBase  ·  ${_ordem(sortBy, sortOrder)}'),
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
            LucideIcons.archive,
            'Nenhuma proposta excluída neste recorte',
            'Propostas excluídas saem da lista normal e ficam aqui para '
                'auditoria, com o motivo registrado. Toque em "Voltar às '
                'ativas" para ver as outras.',
          )
        : recorte
        ? (
            LucideIcons.searchX,
            'Nenhuma proposta neste recorte',
            'A busca ou os filtros não encontraram propostas. Amplie os '
                'critérios ou limpe tudo para ver a lista completa.',
          )
        : (
            LucideIcons.fileSignature,
            'Nenhuma proposta ainda',
            canCreate
                ? 'Aqui ficam as fichas de proposta de compra. Registre a '
                      'primeira em "Nova proposta": o comprador assina '
                      'primeiro, depois o proprietário e, por fim, o '
                      'corretor.'
                : 'Aqui ficam as fichas de proposta de compra que você pode '
                      'ver. Quando alguém registrar uma proposta com você, '
                      'ela aparece nesta lista.',
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
              child: Icon(icone, size: 24, color: muted),
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
                icon: const Icon(LucideIcons.filterX, size: 17),
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
                label: const Text('Nova proposta'),
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

/// Sem `proposal:view`: a tela diz o motivo e quem resolve (não some).
class _LockedState extends StatelessWidget {
  const _LockedState();

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
                child: Icon(LucideIcons.lock, size: 25, color: muted),
              ),
              const SizedBox(height: 16),
              Text(
                'Sem acesso às fichas de proposta',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sua conta não tem a permissão de ver propostas. Peça ao '
                'administrador da empresa para liberar o acesso.',
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
