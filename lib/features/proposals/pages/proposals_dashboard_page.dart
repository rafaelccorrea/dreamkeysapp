import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/services/api_service.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/file_delivery_sheet.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../services/proposals_dashboard_service.dart';
import '../widgets/dashboard/pd_common.dart';
import '../widgets/dashboard/pd_composition.dart';
import '../widgets/dashboard/pd_friction.dart';
import '../widgets/dashboard/pd_ranking_board.dart';
import '../widgets/dashboard/pd_series_chart.dart';
import '../widgets/dashboard/pd_sheets.dart';
import '../widgets/dashboard/pd_signature_journey.dart';
import '../widgets/proposal_signatures_sheet.dart';

/// Dashboard de Fichas de Proposta — porta `/fichas-proposta/dashboard` do
/// web (`PurchaseProposalsDashboardPage.tsx`): KPIs, evolução por período,
/// funil de assinatura, composição, rankings, gargalos, contrapropostas e
/// score de fechamento, com período, filtros avançados e exportação
/// Excel/PDF gerada no servidor.
///
/// Personalidade própria: abre como um boletim — o valor fechado em
/// manchete, o traço do período e a faixa "Agora" (o que pede ação, cada
/// linha leva ao capítulo que explica); o corpo segue em capítulos
/// numerados, cada um com a pergunta que responde. Assinatura parada e
/// proposta com chance alta abrem as assinaturas da própria proposta.
class ProposalsDashboardPage extends StatefulWidget {
  const ProposalsDashboardPage({super.key});

  static const String permission = 'proposal:view_dashboard';
  static const String exportPermission = 'proposal:export';

  /// Web: `ModuleRoute sale_forms` + `PermissionRoute proposal:view_dashboard`
  /// com `noRoleBypass` — admin/master passam pelo bypass do próprio
  /// `hasPermission` (igual ao hook do web), mas gestor precisa da permissão
  /// real.
  static bool canOpen() {
    final m = ModuleAccessService.instance;
    if (!m.hasCompanyModule('sale_forms')) return false;
    return _hasStrict(permission);
  }

  static bool _hasStrict(String perm) {
    final m = ModuleAccessService.instance;
    if ((m.userRole ?? '').toLowerCase() == 'manager') {
      return m.userPermissionNames.contains(perm);
    }
    return m.hasPermission(perm);
  }

  @override
  State<ProposalsDashboardPage> createState() => _ProposalsDashboardPageState();
}

class _ProposalsDashboardPageState extends State<ProposalsDashboardPage> {
  static const double _padH = 16;

  /// Coluna de leitura em tela larga (tablet/paisagem).
  static const double _maxW = 720;

  /// Mesmo `limit` enviado ao back — listas com esse tamanho podem estar
  /// cortadas, então a contagem vira "15+".
  static const int _listLimit = 15;

  static const String _prefsKey =
      'dashboard:purchase-proposals:advanced-filters:v1';

  final ProposalsDashboardService _svc = ProposalsDashboardService.instance;

  final GlobalKey _chapterTrava = GlobalKey();
  final GlobalKey _chapterChance = GlobalKey();

  ProposalsDashboardData? _data;
  bool _loading = true;
  bool _exporting = false;
  String? _error;
  int _errorStatus = 0;
  int _seq = 0;

  PdPeriod _period = PdPeriod.initial();
  PdAdvancedFilters _advanced = const PdAdvancedFilters();

  List<ProposalsPickOption> _users = const [];
  List<ProposalsPickOption> _teams = const [];
  bool _optionsLoading = true;
  ProposalsUnitScope? _scope;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  // ─── Dados ─────────────────────────────────────────────────────────────

  Future<void> _bootstrap() async {
    await _restoreAdvanced();
    if (!mounted) return;
    _loadOptions();
    await _load();
  }

  Future<void> _restoreAdvanced() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _advanced =
            PdAdvancedFilters.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      // Sem storage o painel segue com o padrão.
    }
  }

  Future<void> _persistAdvanced() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_advanced.toJson()));
    } catch (_) {
      // Silencioso, como no web.
    }
  }

  ProposalsDashboardFilters _filters() => ProposalsDashboardFilters(
        dateFrom: _period.dateFrom,
        dateTo: _period.dateTo,
        granularity: _period.granularity,
        excludeUserIds: _advanced.excludeUserIds,
        excludeTeamIds: _advanced.excludeTeamIds,
        excludeNonCommercialTeams: _advanced.excludeNonCommercialTeams,
        limit: _listLimit,
      );

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() => _loading = true);
    final res = await _svc.getDashboard(_filters());
    if (!mounted || seq != _seq) return;
    final ok = res.success && res.data != null;
    setState(() {
      _loading = false;
      if (ok) {
        _data = res.data;
        _error = null;
        _errorStatus = 0;
      } else {
        _error = res.message ?? 'Erro ao carregar o painel de propostas';
        _errorStatus = res.statusCode;
      }
    });
    if (!ok && _data != null) {
      _snack('Não foi possível atualizar: ${_error ?? 'erro desconhecido'}');
    }
  }

  Future<void> _loadOptions() async {
    final results = await Future.wait([
      _svc.getAvailableUsers(limit: 200),
      _svc.getAvailableTeams(),
    ]);
    final scopeRes = await _svc.getMyUnitScope();
    if (!mounted) return;
    setState(() {
      _optionsLoading = false;
      if (results[0].success) _users = results[0].data ?? const [];
      if (results[1].success) _teams = results[1].data ?? const [];
      if (scopeRes.success) _scope = scopeRes.data;
    });
  }

  // ─── Ações ─────────────────────────────────────────────────────────────

  Future<void> _openPeriod() async {
    final picked = await showPdPeriodSheet(context, _period);
    if (picked == null || !mounted) return;
    setState(() => _period = picked);
    _load();
  }

  Future<void> _openAdvanced() async {
    final picked = await showPdAdvancedSheet(
      context,
      current: _advanced,
      users: _users,
      teams: _teams,
      loading: _optionsLoading,
    );
    if (picked == null || !mounted) return;
    setState(() => _advanced = picked);
    _persistAdvanced();
    _load();
  }

  Future<void> _openExport() async {
    final canExport =
        ProposalsDashboardPage._hasStrict(ProposalsDashboardPage.exportPermission);
    final kind = await showPdExportSheet(
      context,
      canExport: canExport,
      scopeLine:
          '${_period.rangeLabel}, ${_period.granularityLabel}'
          '${_advanced.count > 0 ? ', ${_advanced.count} filtro(s) avançado(s)' : ''}',
    );
    if (kind == null || !mounted) return;
    await _export(kind);
  }

  /// Exporta o recorte e entrega pela folha de arquivo do app
  /// (Compartilhar / Salvar no aparelho) — `Uri.file` não abre no Android
  /// nem no iOS.
  Future<void> _export(PdExportKind kind) async {
    final excel = kind == PdExportKind.excel;
    final label = excel ? 'Excel' : 'PDF';
    // O web exporta sem `limit` (recorte completo).
    final filters = _filters().withoutLimit();
    setState(() => _exporting = true);
    await showFileDeliverySheet(
      context,
      title: 'Painel de propostas em $label',
      subtitle: '${_period.rangeLabel}, ${_period.granularityLabel}'
          '${_advanced.count > 0 ? ', ${_advanced.count} filtro(s) avançado(s)' : ''}',
      paper:
          excel ? FileDeliveryPaper.spreadsheet : FileDeliveryPaper.document,
      expectedType: excel ? 'XLSX' : 'PDF',
      generatingTitle: 'Gerando o $label…',
      readyTitle: '$label pronto',
      shareSubject: 'Painel de propostas',
      saveDialogTitle: 'Salvar $label',
      load: () async {
        final res = excel
            ? await _svc.exportExcel(filters)
            : await _svc.exportPdf(filters);
        final file = res.data;
        if (!res.success || file == null) {
          return ApiResponse.error(
            message: res.message ?? '',
            statusCode: res.statusCode,
            data: res.error,
          );
        }
        return ApiResponse.success(
          data: DeliverableFile(bytes: file.bytes, fileName: file.fileName),
          statusCode: res.statusCode,
        );
      },
    );
    if (mounted) setState(() => _exporting = false);
  }

  /// Abrir a proposta a partir do painel exige poder ver propostas; sem a
  /// permissão, as linhas continuam legíveis, só não abrem.
  bool get _canOpenProposals =>
      ModuleAccessService.instance.hasPermission('proposal:view');

  void _openProposal(String id, String number, int etapa) {
    if (id.isEmpty) return;
    showProposalSignaturesSheet(
      context,
      proposalId: id,
      proposalNumber: number,
      etapa: etapa < 1 ? 1 : (etapa > 3 ? 3 : etapa),
      onChanged: _load,
    );
  }

  void _goTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: 0.02,
    );
  }

  void _snack(String message, {bool short = false}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: short ? 2 : 4),
        ),
      );
  }

  // ─── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = PdTones.of(context);
    return AppScaffold(
      title: 'Painel de Propostas',
      showBottomNavigation: false,
      actions: [
        IconButton(
          tooltip: 'Exportar',
          onPressed: _exporting || _data == null ? null : _openExport,
          icon: const Icon(LucideIcons.fileDown, size: 19),
        ),
        IconButton(
          tooltip: 'Atualizar',
          onPressed: _loading ? null : _load,
          icon: const Icon(LucideIcons.refreshCw, size: 18),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: _load,
        color: t.accent,
        child: _data == null
            ? (_error != null && !_loading ? _buildError() : _buildSkeleton())
            : _buildContent(_data!),
      ),
    );
  }

  /// Tela larga: coluna de leitura centrada — nada de gráfico esticado em
  /// 1000dp.
  Widget _capped(Widget child) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxW),
          child: child,
        ),
      );

  Widget _buildError() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        _capped(_periodBar()),
        _capped(
          Padding(
            padding: const EdgeInsets.fromLTRB(_padH, 48, _padH, 40),
            child: AppErrorState.fromApi(
              message: _error,
              statusCode: _errorStatus,
              onRetry: _load,
              dense: true,
            ),
          ),
        ),
      ],
    );
  }

  /// Esqueleto fiel à abertura: manchete, traço, três figuras, faixa
  /// "Agora" e o primeiro gráfico.
  Widget _buildSkeleton() {
    Widget ledger() => Row(
          children: const [
            Expanded(child: SkeletonBox(height: 54, borderRadius: 8)),
            SizedBox(width: 25),
            Expanded(child: SkeletonBox(height: 54, borderRadius: 8)),
            SizedBox(width: 25),
            Expanded(child: SkeletonBox(height: 54, borderRadius: 8)),
          ],
        );
    Widget nowRow() => const Padding(
          padding: EdgeInsets.symmetric(vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 18, height: 18, borderRadius: 5),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonText(height: 13),
                    SizedBox(height: 6),
                    SkeletonText(width: 170, height: 10),
                  ],
                ),
              ),
            ],
          ),
        );
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        _capped(_periodBar()),
        _capped(
          Padding(
            padding: const EdgeInsets.fromLTRB(_padH, 20, _padH, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonBox(width: 190, height: 40, borderRadius: 8),
                const SizedBox(height: 10),
                const SkeletonText(width: 250, height: 12),
                const SizedBox(height: 14),
                const SkeletonBox(height: 44, borderRadius: 8),
                const SizedBox(height: 18),
                ledger(),
                const SizedBox(height: 22),
                const SkeletonText(width: 56, height: 10),
                nowRow(),
                nowRow(),
                const SizedBox(height: 22),
                const SkeletonBox(width: 160, height: 16, borderRadius: 4),
                const SizedBox(height: 14),
                const SkeletonBox(height: 200, borderRadius: 10),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(ProposalsDashboardData d) {
    final t = PdTones.of(context);
    final k = d.kpis;
    final rankingTabs = <PdRankingTab>[
      PdRankingTab('Corretores', d.rankingCorretores, showAvatar: true),
      PdRankingTab('Equipes', d.rankingEquipes),
      PdRankingTab('Unidades', d.rankingImobiliarias),
      PdRankingTab('Regiões', d.rankingRegioes),
      if (d.rankingEmpreendimentos.isNotEmpty)
        PdRankingTab('Empreendimentos', d.rankingEmpreendimentos),
    ];
    final canOpen = _canOpenProposals;

    // Coluna inteira montada (não lazy): a faixa "Agora" rola até o
    // capítulo certo, e ele precisa existir para isso.
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 40),
      child: _capped(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _periodBar(),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: _loading ? 0.45 : 1,
              child: IgnorePointer(
                ignoring: _loading,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _opening(d),
                    _chapter(
                      number: 1,
                      title: 'Evolução',
                      question: 'Como as propostas e o valor fechado andaram '
                          'no período?',
                      child: PdSeriesChart(
                        points: d.timeseries,
                        granularity: _period.granularity,
                      ),
                    ),
                    _chapter(
                      number: 2,
                      title: 'Jornada da assinatura',
                      question: 'Até onde as propostas chegam antes de fechar?',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          PdSignatureRail(funnel: d.funnel),
                          const SizedBox(height: 20),
                          _subhead('Assinaturas por etapa'),
                          const SizedBox(height: 12),
                          PdSignatureStages(signatures: d.signatures),
                        ],
                      ),
                    ),
                    _chapter(
                      number: 3,
                      title: 'Composição',
                      question:
                          'Em que estado estão as propostas e de onde vieram?',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          PdRingBreakdown(
                            centerValue: pdInt.format(k.totalGeradas),
                            centerLabel: 'geradas',
                            slices: [
                              PdSlice('Finalizadas', k.finalizadas, t.green),
                              PdSlice('Em andamento', k.emProcessamento, t.blue),
                              PdSlice('Canceladas', k.canceladas, t.amber),
                              PdSlice('Excluídas', k.excluidas, t.red),
                            ],
                          ),
                          const SizedBox(height: 22),
                          _subhead(
                            'Mídia / origem',
                            hint: 'via ficha de venda vinculada',
                          ),
                          const SizedBox(height: 6),
                          PdOriginBars(items: d.rankingMidias),
                        ],
                      ),
                    ),
                    _chapter(
                      number: 4,
                      title: 'Quem fecha',
                      question: 'Quem converte mais valor no recorte?',
                      child: PdRankingBoard(tabs: rankingTabs),
                    ),
                    _chapter(
                      key: _chapterTrava,
                      number: 5,
                      title: 'Onde trava',
                      question: 'Quem está segurando assinatura e como andam '
                          'as contrapropostas?',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (canOpen && d.signatures.gargalos.isNotEmpty) ...[
                            _tapHint('Toque numa linha para reenviar ou copiar '
                                'o link da assinatura.'),
                            const SizedBox(height: 4),
                          ],
                          PdBottleneckList(
                            items: d.signatures.gargalos,
                            onOpen: canOpen
                                ? (g) => _openProposal(
                                      g.proposalId,
                                      g.proposalNumber,
                                      g.etapa,
                                    )
                                : null,
                          ),
                          const SizedBox(height: 18),
                          _subhead(
                            'Contrapropostas',
                            hint: '${pdInt.format(d.counterProposals.total)} '
                                'no recorte',
                          ),
                          const SizedBox(height: 12),
                          PdCounterProposals(stats: d.counterProposals),
                        ],
                      ),
                    ),
                    _chapter(
                      key: _chapterChance,
                      number: 6,
                      title: 'Chance de fechamento',
                      question: 'Quais propostas em aberto têm mais chance de '
                          'virar venda?',
                      child: PdScoreList(
                        items: d.scoreFechamento,
                        onOpen: canOpen
                            ? (s) => _openProposal(
                                  s.proposalId,
                                  s.proposalNumber,
                                  s.etapaAtual,
                                )
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Barra de período ──────────────────────────────────────────────────

  Widget _periodBar() {
    final t = PdTones.of(context);
    final scope = _scope;
    final count = _advanced.count;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(_padH, 6, 6, 6),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _openPeriod,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(LucideIcons.calendar, size: 18, color: t.accent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      _period.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.2,
                                        color: t.text,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    LucideIcons.chevronDown,
                                    size: 15,
                                    color: t.muted,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 1),
                              Text(
                                '${_period.rangeLabel} · ${_period.granularityLabel}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: t.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: t.text,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(48, 44),
                ),
                onPressed: _openAdvanced,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.slidersHorizontal, size: 16),
                    const SizedBox(width: 6),
                    const Text(
                      'Filtros',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: t.text,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          '$count',
                          textAlign: TextAlign.center,
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: t.surface,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (scope != null && scope.isRestricted)
          Padding(
            padding: const EdgeInsets.fromLTRB(_padH, 0, _padH, 8),
            child: Row(
              children: [
                Icon(LucideIcons.building2, size: 13, color: t.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    scope.resolvedLabels.length == 1
                        ? 'Seu escopo: apenas ${scope.resolvedLabels.first}'
                        : scope.resolvedLabels.isEmpty
                            ? 'Seu escopo: unidades restritas'
                            : 'Seu escopo: ${scope.resolvedLabels.length} unidades '
                                '(${scope.resolvedLabels.join(', ')})',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: t.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const PdHairline(),
      ],
    );
  }

  // ─── Abertura ──────────────────────────────────────────────────────────

  /// Boletim do período: a manchete é o dinheiro fechado (o rótulo vem
  /// depois do número, como frase — sem eyebrow), o traço mostra o ritmo,
  /// três figuras dão a proporção e a faixa "Agora" diz o que pede ação.
  Widget _opening(ProposalsDashboardData d) {
    final t = PdTones.of(context);
    final k = d.kpis;
    return Padding(
      padding: const EdgeInsets.fromLTRB(_padH, 20, _padH, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              pdBrlCompact.format(k.valorFinalizado),
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.2,
                height: 1.05,
                color: t.text,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'fechados no período',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: t.text,
                  ),
                ),
                TextSpan(
                  text: ' · ${pdBrlFull.format(k.valorFinalizado)} em '
                      '${pdPlural(k.finalizadas, 'proposta finalizada', 'propostas finalizadas')}'
                      ' de ${pdInt.format(k.totalGeradas)} geradas',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: t.muted,
                  ),
                ),
              ],
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(height: 1.35),
          ),
          if (d.timeseries.length > 1) ...[
            const SizedBox(height: 12),
            PdSparkline(
              values: [for (final p in d.timeseries) p.valorFinalizado],
              color: t.accent,
            ),
          ],
          const SizedBox(height: 18),
          PdLedger(
            children: [
              PdFigure(
                value: pdPercent(k.taxaConversao),
                label: 'conversão',
                sub: 'finalizadas ÷ geradas',
                tone: t.green,
              ),
              PdFigure(
                value: pdBrlCompact.format(k.ticketMedio),
                label: 'ticket médio',
                sub: pdBrlFull.format(k.ticketMedio),
              ),
              PdFigure(
                value: pdBrlCompact.format(k.valorPendente),
                label: 'em andamento',
                sub: pdPlural(k.emProcessamento, 'proposta aberta',
                    'propostas abertas'),
                tone: t.amber,
              ),
            ],
          ),
          const SizedBox(height: 22),
          _nowBlock(d),
          const SizedBox(height: 16),
          const PdHairline(),
          const SizedBox(height: 14),
          _linkBlock(k),
        ],
      ),
    );
  }

  /// Faixa "Agora": o que pede ação no recorte, em frases. Cada linha leva
  /// ao capítulo que detalha (rastreio = navegação). Sem nada travado, uma
  /// linha calma diz isso — o vazio também informa.
  Widget _nowBlock(ProposalsDashboardData d) {
    final t = PdTones.of(context);
    final gargalos = d.signatures.gargalos;
    final lentas = gargalos.where((g) => g.pendingDays >= 3).toList();
    ProposalsSignatureBottleneck? pior;
    for (final g in lentas) {
      if (pior == null || g.pendingDays > pior.pendingDays) pior = g;
    }
    final cortada =
        gargalos.length >= _listLimit && lentas.length == gargalos.length;
    final contras = d.counterProposals.pendente;
    final altas = d.scoreFechamento.where((s) => s.score >= 70).toList();

    final rows = <Widget>[];
    if (pior != null) {
      final n = lentas.length;
      final qtd = cortada ? '$n+' : pdInt.format(n);
      final quem = pior.signerName.isEmpty ? 'signatário sem nome' : pior.signerName;
      rows.add(
        _nowRow(
          icon: LucideIcons.clockAlert,
          tone: pior.pendingDays >= 7 ? t.red : t.amberText,
          title: n == 1
              ? '1 assinatura esperando há 3 dias ou mais'
              : '$qtd assinaturas esperando há 3 dias ou mais',
          detail: 'A mais antiga: ${pdDays(pior.pendingDays)} · $quem'
              '${pior.proposalNumber.isEmpty ? '' : ' · Nº ${pior.proposalNumber}'}',
          onTap: () => _goTo(_chapterTrava),
        ),
      );
    }
    if (contras > 0) {
      rows.add(
        _nowRow(
          icon: LucideIcons.handshake,
          tone: t.amberText,
          title: '${pdPlural(contras, 'contraproposta esperando', 'contrapropostas esperando')} '
              'resposta',
          detail: 'O placar de aprovadas e recusadas está em "Onde trava".',
          onTap: () => _goTo(_chapterTrava),
        ),
      );
    }
    if (rows.isEmpty) {
      rows.add(
        _nowRow(
          icon: LucideIcons.circleCheck,
          tone: t.green,
          title: 'Nada travado no recorte',
          detail: 'Nenhuma assinatura esperando há 3 dias ou mais e nenhuma '
              'contraproposta sem resposta.',
        ),
      );
    }
    if (altas.isNotEmpty) {
      final melhor = altas.first;
      final nome = melhor.proponentName.isEmpty
          ? 'proponente não informado'
          : melhor.proponentName;
      rows.add(
        _nowRow(
          icon: LucideIcons.trendingUp,
          tone: t.green,
          title: altas.length == 1
              ? '1 proposta com chance alta de fechar'
              : '${pdInt.format(altas.length)} propostas com chance alta de '
                  'fechar',
          detail: 'Nota ${melhor.score}: $nome · '
              '${pdBrlCompact.format(melhor.proposedPrice)}',
          onTap: () => _goTo(_chapterChance),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _subhead('Agora'),
        const SizedBox(height: 2),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const PdHairline(indent: 30),
          rows[i],
        ],
      ],
    );
  }

  Widget _nowRow({
    required IconData icon,
    required Color tone,
    required String title,
    String? detail,
    VoidCallback? onTap,
  }) {
    final t = PdTones.of(context);
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: tone),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                    color: t.text,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                      color: t.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(LucideIcons.chevronRight, size: 16, color: t.muted),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
  }

  /// Vínculo proposta → ficha de venda (diagnóstico do web). O número fica
  /// em tinta de texto; a régua carrega o alerta.
  Widget _linkBlock(ProposalsKpis k) {
    final t = PdTones.of(context);
    final linkedLow = k.propPropostasComFicha < 30;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(LucideIcons.link, size: 15, color: t.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Vinculadas a ficha de venda',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: t.text,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              pdPercent(k.propPropostasComFicha),
              maxLines: 1,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: t.text,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        PdMeter(
          fraction: k.propPropostasComFicha / 100,
          color: linkedLow ? t.red : t.green,
          height: 5,
        ),
        if (k.propPropostasComFicha < 100) ...[
          const SizedBox(height: 7),
          Text(
            'Quando a proposta finaliza e gera a ficha de venda, o vínculo '
            'deveria ser preenchido sozinho. Abaixo de 100%, a conversão '
            'proposta → venda aparece menor do que é.',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              height: 1.35,
              color: t.muted,
            ),
          ),
        ],
      ],
    );
  }

  // ─── Capítulos ─────────────────────────────────────────────────────────

  Widget _chapter({
    Key? key,
    required int number,
    required String title,
    required String question,
    required Widget child,
  }) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PdHairline(),
        Padding(
          padding: const EdgeInsets.fromLTRB(_padH, 20, _padH, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PdChapterHeader(
                number: number,
                title: title,
                question: question,
              ),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ],
    );
  }

  Widget _tapHint(String text) {
    final t = PdTones.of(context);
    return Row(
      children: [
        Icon(LucideIcons.pointer, size: 13, color: t.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: t.muted,
            ),
          ),
        ),
      ],
    );
  }

  Widget _subhead(String text, {String? hint}) {
    final t = PdTones.of(context);
    return Row(
      children: [
        Flexible(
          child: Text(
            text.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: t.muted,
            ),
          ),
        ),
        if (hint != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: t.muted,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
