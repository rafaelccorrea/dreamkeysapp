import 'dart:convert';
import 'dart:io' show Directory, File;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../services/proposals_dashboard_service.dart';
import '../widgets/dashboard/pd_common.dart';
import '../widgets/dashboard/pd_composition.dart';
import '../widgets/dashboard/pd_friction.dart';
import '../widgets/dashboard/pd_ranking_board.dart';
import '../widgets/dashboard/pd_series_chart.dart';
import '../widgets/dashboard/pd_sheets.dart';
import '../widgets/dashboard/pd_signature_journey.dart';

/// Dashboard de Fichas de Proposta — porta `/fichas-proposta/dashboard` do
/// web (`PurchaseProposalsDashboardPage.tsx`): KPIs, evolução por período,
/// funil de assinatura, composição, rankings, gargalos, contrapropostas e
/// score de fechamento, com período, filtros avançados e exportação
/// Excel/PDF gerada no servidor.
///
/// Personalidade própria: abertura com o valor fechado + traço do período, e
/// o corpo em capítulos numerados, cada um com a pergunta que responde.
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
  static const String _prefsKey =
      'dashboard:purchase-proposals:advanced-filters:v1';

  final ProposalsDashboardService _svc = ProposalsDashboardService.instance;

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
        limit: 15,
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

  Future<void> _export(PdExportKind kind) async {
    final label = kind == PdExportKind.excel ? 'Excel' : 'PDF';
    setState(() => _exporting = true);
    _snack('Gerando o $label…', short: true);
    // O web exporta sem `limit` (recorte completo).
    final filters = _filters().withoutLimit();
    final res = kind == PdExportKind.excel
        ? await _svc.exportExcel(filters)
        : await _svc.exportPdf(filters);
    if (!mounted) return;
    setState(() => _exporting = false);
    final file = res.data;
    if (!res.success || file == null) {
      _snack(res.message ?? 'Falha ao exportar o $label.');
      return;
    }
    try {
      final out = File('${Directory.systemTemp.path}/${file.fileName}');
      await out.writeAsBytes(file.bytes);
      final ok = await launchUrl(
        Uri.file(out.path),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) _snack('$label salvo em ${out.path}');
    } catch (e) {
      if (mounted) _snack('Erro ao abrir o $label: $e');
    }
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

  Widget _buildError() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        _periodBar(),
        Padding(
          padding: const EdgeInsets.fromLTRB(_padH, 48, _padH, 40),
          child: AppErrorState.fromApi(
            message: _error,
            statusCode: _errorStatus,
            onRetry: _load,
            dense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildSkeleton() {
    Widget ledger() => Row(
          children: const [
            Expanded(child: SkeletonBox(height: 40, borderRadius: 8)),
            SizedBox(width: 14),
            Expanded(child: SkeletonBox(height: 40, borderRadius: 8)),
            SizedBox(width: 14),
            Expanded(child: SkeletonBox(height: 40, borderRadius: 8)),
          ],
        );
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        _periodBar(),
        Padding(
          padding: const EdgeInsets.fromLTRB(_padH, 22, _padH, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBox(width: 120, height: 12, borderRadius: 4),
              const SizedBox(height: 10),
              const SkeletonBox(width: 190, height: 38, borderRadius: 8),
              const SizedBox(height: 10),
              const SkeletonBox(height: 44, borderRadius: 8),
              const SizedBox(height: 18),
              ledger(),
              const SizedBox(height: 26),
              const SkeletonBox(width: 160, height: 16, borderRadius: 4),
              const SizedBox(height: 14),
              const SkeletonBox(height: 150, borderRadius: 10),
              const SizedBox(height: 26),
              const SkeletonBox(width: 180, height: 16, borderRadius: 4),
              const SizedBox(height: 14),
              for (var i = 0; i < 4; i++) ...[
                const SkeletonBox(height: 22, borderRadius: 6),
                const SizedBox(height: 12),
              ],
            ],
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

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 40),
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
                _hero(d),
                _chapter(
                  number: 1,
                  title: 'Evolução',
                  question:
                      'Como as propostas e o valor fechado andaram no período?',
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
                      const SizedBox(height: 18),
                      _subhead('Assinaturas por etapa'),
                      const SizedBox(height: 10),
                      PdSignatureStages(signatures: d.signatures),
                    ],
                  ),
                ),
                _chapter(
                  number: 3,
                  title: 'Composição',
                  question: 'Em que estado estão as propostas e de onde vieram?',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PdRingBreakdown(
                        centerValue: pdInt.format(k.totalGeradas),
                        centerLabel: 'geradas',
                        slices: [
                          PdSlice('Finalizadas', k.finalizadas, t.green),
                          PdSlice('Em processamento', k.emProcessamento, t.blue),
                          PdSlice('Canceladas', k.canceladas, t.amber),
                          PdSlice('Excluídas', k.excluidas, t.red),
                        ],
                      ),
                      const SizedBox(height: 20),
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
                  number: 5,
                  title: 'Onde trava',
                  question:
                      'Quem está segurando assinatura e como andam as contrapropostas?',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PdBottleneckList(items: d.signatures.gargalos),
                      const SizedBox(height: 16),
                      _subhead(
                        'Contrapropostas',
                        hint:
                            '${pdInt.format(d.counterProposals.total)} no recorte',
                      ),
                      const SizedBox(height: 10),
                      PdCounterProposals(stats: d.counterProposals),
                    ],
                  ),
                ),
                _chapter(
                  number: 6,
                  title: 'Chance de fechamento',
                  question:
                      'Quais propostas em aberto têm mais chance de virar venda?',
                  child: PdScoreList(items: d.scoreFechamento),
                ),
              ],
            ),
          ),
        ),
      ],
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
                ),
                onPressed: _openAdvanced,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.slidersHorizontal, size: 16),
                    const SizedBox(width: 6),
                    const Text(
                      'Filtros',
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
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: t.dark
                                ? const Color(0xFF13131F)
                                : Colors.white,
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
                    maxLines: 1,
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

  Widget _hero(ProposalsDashboardData d) {
    final t = PdTones.of(context);
    final k = d.kpis;
    final linkedLow = k.propPropostasComFicha < 30;
    return Padding(
      padding: const EdgeInsets.fromLTRB(_padH, 20, _padH, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'FECHADO NO PERÍODO',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.3,
              color: t.accent,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              pdBrlCompact.format(k.valorFinalizado),
              maxLines: 1,
              style: TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.2,
                height: 1.05,
                color: t.text,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${pdBrlFull.format(k.valorFinalizado)} em '
            '${pdInt.format(k.finalizadas)} de '
            '${pdInt.format(k.totalGeradas)} propostas geradas',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.3,
              color: t.muted,
            ),
          ),
          if (d.timeseries.length > 1) ...[
            const SizedBox(height: 10),
            PdSparkline(
              values: [for (final p in d.timeseries) p.valorFinalizado],
              color: t.accent,
            ),
          ],
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _figure(
                    pdPercent(k.taxaConversao),
                    'conversão',
                    'finalizadas ÷ geradas',
                    t.green,
                  ),
                ),
                _vDivider(),
                Expanded(
                  child: _figure(
                    pdBrlCompact.format(k.ticketMedio),
                    'ticket médio',
                    pdBrlFull.format(k.ticketMedio),
                    t.text,
                  ),
                ),
                _vDivider(),
                Expanded(
                  child: _figure(
                    pdBrlCompact.format(k.valorPendente),
                    'pendente',
                    'em processamento',
                    t.amber,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const PdHairline(),
          const SizedBox(height: 14),
          // Vínculo proposta → ficha de venda (diagnóstico do web).
          Row(
            children: [
              Icon(LucideIcons.link, size: 15, color: t.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Vinculadas a ficha de venda',
                  maxLines: 1,
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
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: linkedLow ? t.red : t.green,
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
      ),
    );
  }

  Widget _vDivider() {
    final t = PdTones.of(context);
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: t.hairline,
    );
  }

  Widget _figure(String value, String label, String sub, Color tone) {
    final t = PdTones.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: tone,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: t.text,
          ),
        ),
        Text(
          sub,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            color: t.muted,
          ),
        ),
      ],
    );
  }

  // ─── Capítulos ─────────────────────────────────────────────────────────

  Widget _chapter({
    required int number,
    required String title,
    required String question,
    required Widget child,
  }) {
    return Column(
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
