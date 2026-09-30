import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/utils/error_cause.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/minimal_body_chrome.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../../kanban/models/kanban_models.dart';
import '../models/sdr_dashboard_filters.dart';
import '../models/sdr_extra_models.dart';
import '../models/sdr_metrics_model.dart';
import '../models/sdr_settings_model.dart';
import '../services/sdr_service.dart';
import '../widgets/sdr_config_sheet.dart';
import '../widgets/sdr_dash_detalhe_sheet.dart';
import '../widgets/sdr_dash_pecas.dart';
import '../widgets/sdr_dashboard_filters_drawer.dart';

/// Rota das configurações (fiação central em `AppRoutes.sdrSettings`).
const String _kSdrSettingsRoute = '/sdr/settings';

/// Dash SDR — o funil do pré-atendimento, na estrutura e na ordem do web
/// (`SDRDashboardPage.tsx`; lá só a aba "Funil" é visível, então a tela é
/// uma página corrida). Redesenho de 30/09/2026:
///   1. topo: o que a tela mostra, atualizar e o período (atalhos do web +
///      régua dos últimos 30 dias);
///   2. estações do funil: entradas (a base) e os três destinos — em
///      qualificação, transferidos, perdidos — com a participação sobre as
///      entradas, o sinal de saúde e o detalhe ao toque;
///   3. leituras: conversão, resposta no WhatsApp, maior origem, leads/dia;
///   4. leads & duplicados (a peneira);
///   5. funil de conversão (passagem entre etapas);
///   6. funil por etapa (colunas do funil SDR).
/// A "Distribuição por estado" do web repete as estações (mesmos números,
/// mesmo toque) — no celular ela mora nelas.
///
/// Eixo da tela = petróleo (`status.teal`); sinais: âmbar = em qualificação
/// ou atenção, verde = transferido ou bom, vermelho = perdido ou crítico.
///
/// Gating (sdr-01, igual ao web): módulo `kanban_management` + permissão
/// `kanban:view_all_teams`. O agente de IA do WhatsApp (`whatsapp_ai` +
/// `whatsapp:manage_config`) fica num ícone da barra: ele não dá nome à tela
/// (no web ele nem aparece aqui).
class SdrDashboardPage extends StatefulWidget {
  const SdrDashboardPage({super.key});

  @override
  State<SdrDashboardPage> createState() => _SdrDashboardPageState();
}

class _SdrDashboardPageState extends State<SdrDashboardPage> {
  static const double _kPadH = 16;
  static const double _kPadTop = 14;
  static const double _kPadBottom = 88;
  static const double _kSecaoGap = 30;

  /// Coluna máxima em tablet/paisagem: o funil e as linhas não esticam de
  /// ponta a ponta (o recuo extra entra no padding da lista).
  static const double _kMaxContentWidth = 760;

  /// Etapas do "Funil por etapa" antes do "Mostrar todas" (o web pagina de
  /// 10 em 10).
  static const int _kEtapasIniciais = 10;

  double _sideGutter(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return math.max(0, (width - _kMaxContentWidth - 2 * _kPadH) / 2);
  }

  bool _isLoading = true;
  bool _recarregando = false;
  bool _temDados = false;
  String? _errorMessage;
  int _errorStatus = 0;

  /// Ordem dos pedidos: resposta de um recorte antigo não sobrescreve a do
  /// recorte novo (troca rápida de período).
  int _pedido = 0;
  DateTime? _atualizadoEm;
  SdrMetrics _metrics = SdrMetrics.empty;
  SdrDashboardFilters _filters = SdrDashboardFilters.initial;
  List<SdrTeamOption> _teams = const [];
  bool _etapasTodas = false;

  /// Funis ativos das equipes visíveis — traduzem equipe em `projectId` no
  /// recorte (`SdrQueryContext`) e dão os nomes da linha "Vendo".
  List<SdrProjectOption> _projects = const [];

  /// Funis SDR ("sdr"/"pré-aten" no nome): o recorte com que a tela abre e
  /// para onde "Voltar ao padrão" volta — igual ao web.
  List<String> _funisSdr = const [];

  /// Configurações do agente — só o estado (ativo/pausado) no ícone da barra.
  SdrSettings? _agentSettings;

  /// Listas completas do recorte (detalhe das estações): pedidas no primeiro
  /// toque e reaproveitadas entre as estações até o recorte mudar.
  Future<ApiResponse<SdrLeadLists>>? _listas;

  bool get _hasAccess =>
      ModuleAccessService.instance.hasCompanyModule('kanban_management') &&
      ModuleAccessService.instance.hasPermission('kanban:view_all_teams');

  /// Configurações do agente de IA: só com o WhatsApp-IA.
  bool get _hasAgent =>
      ModuleAccessService.instance.hasCompanyModule('whatsapp_ai') &&
      ModuleAccessService.instance.hasPermission('whatsapp:manage_config');

  @override
  void initState() {
    super.initState();
    unawaited(_inicializar());
    unawaited(_loadAgentStatus());
  }

  // ─── Dados ─────────────────────────────────────────────────────────────────

  /// Recorte das consultas: equipes + funis (sem eles, a equipe iria como
  /// `teamId` cru e o funil escolhido seria descartado).
  SdrQueryContext get _contexto =>
      SdrQueryContext(teams: _teams, projects: _projects);

  /// Recorte padrão do web: 30 dias nos funis SDR (sem funil SDR na empresa,
  /// sem recorte de funil).
  SdrDashboardFilters get _filtrosPadrao => SdrDashboardFilters.initial
      .copyWith(projectIds: Set<String>.from(_funisSdr));

  /// O recorte atual é o padrão (funis SDR, sem equipe)?
  bool get _ehPadrao =>
      _filters.teamIds.isEmpty &&
      _filters.projectIds.length == _funisSdr.length &&
      _filters.projectIds.containsAll(_funisSdr);

  /// Abertura na ordem do web: equipes → funis → recorte padrão (funis SDR) →
  /// métricas. Pedir as métricas antes mostraria a soma de todos os funis e
  /// "Transferidos" inchado até o recorte chegar.
  Future<void> _inicializar() async {
    if (!_hasAccess) return;
    await _loadTeams();
    await _loadProjects();
    if (!mounted) return;
    if (_funisSdr.isNotEmpty &&
        _filters.projectIds.isEmpty &&
        _filters.teamIds.isEmpty) {
      setState(() => _filters = _filtrosPadrao);
    }
    await _loadMetrics();
  }

  Future<void> _loadProjects() async {
    final res = await SdrService.instance
        .getProjects(_teams.map((t) => t.id).toList(growable: false));
    if (!mounted || !res.success || res.data == null) return;
    setState(() {
      _projects = res.data!;
      _funisSdr = defaultSdrProjectIds(_projects);
    });
  }

  Future<void> _loadMetrics() async {
    if (!_hasAccess) return;
    final pedido = ++_pedido;
    setState(() {
      if (_temDados) {
        _recarregando = true;
      } else {
        _isLoading = true;
      }
      _listas = null;
    });
    final res = await SdrService.instance
        .getMetrics(filters: _filters, context: _contexto);
    if (!mounted || pedido != _pedido) return;
    setState(() {
      _isLoading = false;
      _recarregando = false;
      if (res.success && res.data != null) {
        _metrics = res.data!;
        _temDados = true;
        _errorMessage = null;
        _errorStatus = 0;
        _atualizadoEm = DateTime.now();
        _etapasTodas = false;
      } else {
        _errorMessage = res.message ?? 'Erro ao carregar métricas do SDR';
        _errorStatus = res.statusCode;
      }
    });
  }

  Future<void> _loadTeams() async {
    if (!_hasAccess) return;
    final res = await SdrService.instance.getTeams();
    if (!mounted || !res.success || res.data == null) return;
    setState(() => _teams = res.data!);
  }

  Future<void> _loadAgentStatus() async {
    if (!_hasAccess || !_hasAgent) return;
    final res = await SdrService.instance.getSettings();
    if (!mounted || !res.success || res.data == null) return;
    setState(() => _agentSettings = res.data);
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadMetrics(), _loadAgentStatus()]);
  }

  /// Listas do detalhe (`lists=full`, mesmo recorte das métricas). Falha não
  /// fica guardada: o próximo toque tenta de novo.
  Future<ApiResponse<SdrLeadLists>> _carregarListas({bool forcar = false}) {
    final guardada = _listas;
    if (!forcar && guardada != null) return guardada;
    final futuro = SdrService.instance
        .getLeadLists(filters: _filters, context: _contexto);
    _listas = futuro;
    unawaited(futuro.then((r) {
      if (!r.success && identical(_listas, futuro)) _listas = null;
    }));
    return futuro;
  }

  void _abrirDetalhe(SdrDetalheTipo tipo) {
    mostrarSdrDetalhe(
      context,
      tipo: tipo,
      metricas: _metrics,
      carregar: _carregarListas,
    );
  }

  void _aplicarPreset(SdrPeriodPreset p) {
    if (_filters.preset == p) return;
    setState(() => _filters = _filters.copyWith(preset: p));
    _loadMetrics();
  }

  /// Volta ao recorte padrão (funis SDR, sem equipe), mantendo o período.
  void _voltarAoPadrao() {
    setState(() => _filters = _filters.copyWith(
          teamIds: const <String>{},
          projectIds: Set<String>.from(_funisSdr),
        ));
    _loadMetrics();
  }

  static bool _mesmoConjunto(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  void _openFilters() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black54,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SdrDashboardFiltersDrawer(
        initialFilters: _filters,
        teams: _teams,
        onApply: (f) {
          // Funil explícito manda no recorte (regra do web), e o app não tem
          // seletor de funil: escolher equipe troca os funis SDR pelos funis
          // da equipe; tirar todas as equipes volta aos funis SDR.
          var novo = f;
          if (!_mesmoConjunto(f.teamIds, _filters.teamIds)) {
            novo = f.copyWith(
              projectIds: f.teamIds.isNotEmpty
                  ? const <String>{}
                  : Set<String>.from(_funisSdr),
            );
          }
          setState(() => _filters = novo);
          _loadMetrics();
        },
        onClear: () {
          setState(() => _filters = _filtrosPadrao);
          _loadMetrics();
        },
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).pushNamed(_kSdrSettingsRoute);
  }

  /// Ajustes rápidos do agente de IA (ícone da barra). Salvar atualiza o
  /// estado do ícone na hora; "Todas as opções" leva à página completa.
  void _openConfigSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black54,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SdrConfigSheet(
        initial: _agentSettings,
        onSaved: (s) {
          if (!mounted) return;
          setState(() => _agentSettings = s);
        },
        onOpenFullSettings: _openSettings,
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_hasAccess) {
      return const AppScaffold(
        title: 'Dash SDR',
        showBottomNavigation: false,
        body: _DeniedView(),
      );
    }

    return AppScaffold(
      title: 'Dash SDR',
      showBottomNavigation: false,
      actions: [
        if (_hasAgent) _acaoAgente(context),
        _BadgedToolbarAction(
          count: _filters.activeCount,
          child: ChromeToolbarIconButton(
            icon: LucideIcons.slidersHorizontal,
            tooltip: 'Filtros',
            onPressed: _openFilters,
          ),
        ),
      ],
      body: _corpo(context),
    );
  }

  /// O ícone do agente diz o estado sem texto (robô / robô desligado).
  Widget _acaoAgente(BuildContext context) {
    final ativo = _agentSettings?.enabled;
    final estado = ativo == null ? '' : (ativo ? ' · ativo' : ' · pausado');
    return ChromeToolbarIconButton(
      icon: ativo == false ? LucideIcons.botOff : LucideIcons.bot,
      tooltip: 'Agente de IA do WhatsApp$estado',
      onPressed: _openConfigSheet,
    );
  }

  Widget _corpo(BuildContext context) {
    if (_isLoading && !_temDados) return _buildSkeleton(context);
    if (!_temDados && _errorMessage != null) return _buildError(context);

    final gutter = _sideGutter(context);
    final s = _metrics.summary;
    final vazio = s.totalEntries == 0 &&
        s.totalLeads == 0 &&
        s.transferred == 0 &&
        s.lost == 0 &&
        s.transferredByEntry == 0;

    return Stack(
      children: [
        RefreshIndicator(
          color: SdrTom.eixo(context),
          onRefresh: _refreshAll,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              _kPadH + gutter,
              _kPadTop,
              _kPadH + gutter,
              _kPadBottom,
            ),
            children: [
              _topo(context),
              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                _faixaErro(context),
              ],
              const SizedBox(height: 22),
              if (vazio)
                _vazio(context)
              else ...[
                _estacoes(context),
                const SizedBox(height: 22),
                _leituras(context),
                const SizedBox(height: _kSecaoGap),
                _peneira(context),
                if (s.totalEntries > 0) ...[
                  const SizedBox(height: _kSecaoGap),
                  _funilConversao(context),
                ],
                if (_metrics.byColumn.isNotEmpty) ...[
                  const SizedBox(height: _kSecaoGap),
                  _funilPorEtapa(context),
                ],
              ],
            ],
          ),
        ),
        if (_recarregando)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              minHeight: 2,
              color: SdrTom.eixo(context),
              backgroundColor: Colors.transparent,
            ),
          ),
      ],
    );
  }

  // ─── 1. Topo ───────────────────────────────────────────────────────────────

  Widget _topo(BuildContext context) {
    final theme = Theme.of(context);
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    final range = _filters.resolvedRange();
    final hora = _atualizadoEm;
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
                  Text(
                    'Funil em tempo real',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: ThemeHelpers.textColor(context),
                      letterSpacing: -0.5,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Qualificação, conversão e transferências para corretores.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secundaria,
                      height: 1.35,
                    ),
                  ),
                  if (hora != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(LucideIcons.clock3, size: 12, color: secundaria),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Atualizado às ${_hhmm(hora)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: secundaria,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            _BotaoAtualizar(
              ocupado: _recarregando,
              onTap: _refreshAll,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _atalhosPeriodo(context),
        const SizedBox(height: 12),
        SdrReguaPeriodo(inicio: range.start, fim: range.end),
        const SizedBox(height: 7),
        _legendaRegua(context, range),
        if (_filters.teamIds.isNotEmpty ||
            _filters.projectIds.isNotEmpty) ...[
          const SizedBox(height: 10),
          _linhaVendo(context),
        ],
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(LucideIcons.info, size: 13, color: secundaria),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Entradas contam pela data de criação do card; transferidos e perdidos, pela data do evento.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: secundaria,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Atalhos do período do web ("Hoje · Ontem · 7 dias · 30 dias") como abas
  /// com sublinhado; o calendário abre os filtros para as outras janelas.
  Widget _atalhosPeriodo(BuildContext context) {
    const atalhos = [
      SdrPeriodPreset.today,
      SdrPeriodPreset.yesterday,
      SdrPeriodPreset.last7,
      SdrPeriodPreset.last30,
    ];
    final tinta = SdrTom.texto(context, SdrTom.eixo(context));
    final outra = !atalhos.contains(_filters.preset);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: SdrTom.trilho(context))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final p in atalhos)
            Expanded(
              child: _AbaSublinhada(
                ativa: _filters.preset == p,
                tom: tinta,
                onTap: () => _aplicarPreset(p),
                child: Text(
                  p.label,
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
            ),
          SizedBox(
            width: 52,
            child: Tooltip(
              message: 'Outro período',
              child: _AbaSublinhada(
                ativa: outra,
                tom: tinta,
                onTap: _openFilters,
                child: Icon(
                  LucideIcons.calendarDays,
                  size: 18,
                  color: outra
                      ? tinta
                      : ThemeHelpers.textSecondaryColor(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendaRegua(
    BuildContext context,
    ({DateTime start, DateTime end}) r,
  ) {
    final theme = Theme.of(context);
    final estilo = theme.textTheme.labelSmall?.copyWith(
      color: ThemeHelpers.textSecondaryColor(context),
      fontWeight: FontWeight.w600,
      fontSize: 11,
    );
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final fim = DateTime(r.end.year, r.end.month, r.end.day);
    final inicio = DateTime(r.start.year, r.start.month, r.start.day);
    final dias = fim.difference(inicio).inDays + 1;
    final antesDaRegua = inicio
        .isBefore(hoje.subtract(const Duration(days: SdrReguaPeriodo.dias - 1)));
    final quantos = dias == 1 ? '1 dia' : '$dias dias';
    final centro = _filters.preset == SdrPeriodPreset.thisMonth
        ? 'Este mês · $quantos'
        : quantos;
    return Row(
      children: [
        Expanded(
          child: Text(
            '${antesDaRegua ? '‹ ' : ''}${sdrDiaMes(inicio)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: estilo,
          ),
        ),
        Text(
          centro,
          maxLines: 1,
          style: estilo?.copyWith(
            color: ThemeHelpers.textColor(context),
            fontWeight: FontWeight.w900,
          ),
        ),
        Expanded(
          child: Text(
            fim == hoje ? '${sdrDiaMes(fim)} · hoje' : sdrDiaMes(fim),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: estilo,
          ),
        ),
      ],
    );
  }

  /// "Vendo" do web: o recorte de funil/equipe que está valendo. No padrão
  /// (funis SDR) diz que é o padrão; fora dele, oferece voltar.
  Widget _linhaVendo(BuildContext context) {
    final theme = Theme.of(context);
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    final forte = TextStyle(
      color: ThemeHelpers.textColor(context),
      fontWeight: FontWeight.w800,
    );

    String nomes(Iterable<String> ids, Map<String, String> catalogo) {
      final conhecidos =
          ids.map((id) => catalogo[id]).whereType<String>().toList();
      final faltam = ids.length - conhecidos.length;
      return [
        ...conhecidos,
        if (faltam > 0) '+$faltam',
      ].join(', ');
    }

    final partes = <InlineSpan>[const TextSpan(text: 'Vendo ')];
    if (_filters.teamIds.isNotEmpty) {
      final catalogo = {for (final t in _teams) t.id: t.name};
      final varias = _filters.teamIds.length > 1;
      partes
        ..add(TextSpan(text: varias ? 'as equipes ' : 'a equipe '))
        ..add(TextSpan(text: nomes(_filters.teamIds, catalogo), style: forte));
    } else {
      final catalogo = {for (final p in _projects) p.id: p.name};
      final varios = _filters.projectIds.length > 1;
      partes
        ..add(TextSpan(
          text: _ehPadrao
              ? (varios ? 'os funis SDR ' : 'o funil SDR ')
              : (varios ? 'os funis ' : 'o funil '),
        ))
        ..add(TextSpan(
          text: nomes(_filters.projectIds, catalogo),
          style: forte,
        ));
    }
    if (_ehPadrao) partes.add(const TextSpan(text: ' · recorte padrão'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                _filters.teamIds.isNotEmpty
                    ? LucideIcons.users
                    : LucideIcons.funnel,
                size: 14,
                color: secundaria,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text.rich(
                TextSpan(children: partes),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: secundaria,
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
        if (!_ehPadrao)
          TextButton.icon(
            onPressed: _voltarAoPadrao,
            style: TextButton.styleFrom(
              foregroundColor: ThemeHelpers.textColor(context),
              padding: const EdgeInsets.symmetric(horizontal: 0),
              minimumSize: const Size(0, 36),
            ),
            icon: const Icon(LucideIcons.rotateCcw, size: 14),
            label: Text(
              _funisSdr.isEmpty ? 'Ver todos os funis' : 'Voltar ao padrão',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
      ],
    );
  }

  /// A recarga falhou com dado na tela: diz a causa, avisa que os números
  /// são do último carregamento e oferece tentar de novo.
  Widget _faixaErro(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final causa = ErrorCause.fromApi(
      message: _errorMessage,
      statusCode: _errorStatus,
    );
    final vermelho = SdrTom.perdido(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      decoration: BoxDecoration(
        color: vermelho.withValues(alpha: isDark ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: vermelho.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              causa.icon,
              size: 16,
              color: SdrTom.texto(context, vermelho),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Não deu para atualizar',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${causa.cause} Os números abaixo são do último carregamento.',
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    height: 1.35,
                  ),
                ),
                TextButton.icon(
                  onPressed: _loadMetrics,
                  style: TextButton.styleFrom(
                    foregroundColor: ThemeHelpers.textColor(context),
                    padding: const EdgeInsets.symmetric(horizontal: 0),
                  ),
                  icon: const Icon(LucideIcons.refreshCw, size: 14),
                  label: const Text(
                    'Tentar de novo',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Sem nenhuma entrada no recorte: diz o que aparece aqui e o caminho.
  Widget _vazio(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final eixo = SdrTom.eixo(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: eixo.withValues(alpha: isDark ? 0.16 : 0.10),
            ),
            child: Icon(
              LucideIcons.inbox,
              size: 26,
              color: SdrTom.texto(context, eixo),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Nenhuma entrada no período',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Aqui aparecem os leads que entram no funil SDR: quantos seguem em '
            'qualificação, quantos foram para corretores e quantos se perderam. '
            'Troque o período acima ou a equipe nos filtros.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _openFilters,
            icon: const Icon(LucideIcons.slidersHorizontal, size: 16),
            label: const Text(
              'Ajustar filtros',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: ThemeHelpers.textColor(context),
              side: BorderSide(color: ThemeHelpers.borderColor(context)),
              minimumSize: const Size(0, 42),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 2. Estações do funil ─────────────────────────────────────────────────

  Widget _estacoes(BuildContext context) {
    final s = _metrics.summary;
    final e = s.totalEntries;
    double sobreEntradas(int v) => e > 0 ? v / e : 0.0;
    final perdaPct = e > 0 ? s.lostByEntry * 100 / e : 0.0;
    final destinos = _metrics.transferAggregates.byDestinationTeam;
    final motivos = [..._metrics.lossReasons]
      ..sort((a, b) => b.count.compareTo(a.count));
    final motivo = motivos.isEmpty ? null : motivos.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _estacaoEntradas(context),
        const SizedBox(height: 4),
        _Estacao(
          icone: LucideIcons.hourglass,
          rotulo: 'Em qualificação',
          valor: s.inQualification,
          fracao: sobreEntradas(s.inQualification),
          tom: SdrTom.qualificacao(context),
          detalhe: e > 0
              ? '${sdrPct(sobreEntradas(s.inQualification) * 100)} do funil ainda em triagem'
              : 'Leads abertos no SDR agora',
          nota: s.inQualification > 0 ? 'Situação atual do funil SDR' : null,
          notaIcone: LucideIcons.radar,
          ultimo: false,
          onTap: () => _abrirDetalhe(SdrDetalheTipo.qualificacao),
        ),
        _Estacao(
          icone: LucideIcons.arrowRightLeft,
          rotulo: 'Transferidos',
          valor: s.transferredByEntry,
          fracao: sobreEntradas(s.transferredByEntry),
          tom: SdrTom.transferido(context),
          detalhe:
              '${sdrInt(s.transferred)} no período (evento) · ${sdrPct(s.conversaoCoorte)} de conversão',
          nota: destinos.isNotEmpty
              ? 'Principal destino: ${destinos.first.label}'
              : 'Passagem para corretores e funil comercial',
          notaIcone: LucideIcons.arrowUpRight,
          ultimo: false,
          onTap: () => _abrirDetalhe(SdrDetalheTipo.transferidos),
        ),
        _Estacao(
          icone: LucideIcons.circleX,
          rotulo: 'Perdidos',
          valor: s.lostByEntry,
          fracao: sobreEntradas(s.lostByEntry),
          tom: SdrTom.perdido(context),
          sinal: e > 0 ? sdrSinalPerda(perdaPct) : null,
          sinalDica: 'taxa de perda',
          detalhe: '${sdrInt(s.lost)} marcados no período (evento)',
          nota: motivo == null
              ? null
              : 'Motivo principal: ${KanbanLossReason.tryParse(motivo.reason)?.label ?? motivo.reason} (${sdrInt(motivo.count)})',
          notaIcone: LucideIcons.flag,
          ultimo: true,
          onTap: () => _abrirDetalhe(SdrDetalheTipo.perdidos),
        ),
      ],
    );
  }

  /// A base do funil: o número grande da tela, com a evolução dos últimos
  /// meses ao lado. Toque abre a lista de quem entrou.
  Widget _estacaoEntradas(BuildContext context) {
    final theme = Theme.of(context);
    final s = _metrics.summary;
    final e = s.totalEntries;
    final eixo = SdrTom.eixo(context);
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    final absorvidos = s.duplicateInbound ?? 0;
    final brutos = s.grossEntries ?? e;
    final detalhe = absorvidos > 0
        ? '${sdrInt(brutos)} brutos (${sdrInt(absorvidos)} repetidos absorvidos pelo dedupe) · ${sdrInt(s.coorte)} na coorte'
        : s.totalMovements != null
            ? '${sdrInt(s.coorte)} na coorte · ${sdrInt(s.totalMovements!)} movimentações no período'
            : '${sdrInt(s.coorte)} na coorte';
    final meses = _metrics.byMonth.length > 6
        ? _metrics.byMonth.sublist(_metrics.byMonth.length - 6)
        : _metrics.byMonth;
    final tendencia = meses.map((m) => m.totalLeads).toList(growable: false);

    return InkWell(
      onTap: () => _abrirDetalhe(SdrDetalheTipo.entradas),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        LucideIcons.logIn,
                        size: 14,
                        color: SdrTom.texto(context, eixo),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'ENTRADAS NO PERÍODO',
                          maxLines: 2,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: secundaria,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      sdrInt(e),
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -1.4,
                        height: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    detalhe,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: secundaria,
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            if (tendencia.length > 1) ...[
              const SizedBox(width: 14),
              SizedBox(
                width: 92,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SdrMiniGrafico(valores: tendencia, cor: eixo, altura: 34),
                    const SizedBox(height: 5),
                    Text(
                      'últimos ${tendencia.length} meses',
                      maxLines: 2,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: secundaria,
                        fontSize: 10.5,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(width: 2),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Icon(
                LucideIcons.chevronRight,
                size: 18,
                color: secundaria.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 3. Leituras ──────────────────────────────────────────────────────────

  /// Quatro leituras numa grade de fios (sem chapa de card): 2 colunas no
  /// celular, 1 em tela muito estreita ou fonte grande, 4 no tablet.
  Widget _leituras(BuildContext context) {
    final itens = _itensLeitura(context);
    final fio = SdrTom.trilho(context);
    return LayoutBuilder(
      builder: (context, c) {
        final escala = MediaQuery.textScalerOf(context).scale(14) / 14;
        final w = c.maxWidth;
        final colunas = w >= 640
            ? 4
            : (w < 300 || (w < 380 && escala > 1.25))
                ? 1
                : 2;
        final linhas = <Widget>[];
        for (var i = 0; i < itens.length; i += colunas) {
          final fatia = itens.sublist(i, math.min(i + colunas, itens.length));
          linhas.add(
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: fio)),
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = 0; j < colunas; j++) ...[
                      if (j > 0) Container(width: 1, color: fio),
                      Expanded(
                        child: j < fatia.length
                            ? Padding(
                                padding: EdgeInsets.only(
                                  left: j == 0 ? 0 : 12,
                                  right: j == colunas - 1 ? 0 : 12,
                                  top: 14,
                                  bottom: 14,
                                ),
                                child: fatia[j],
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }
        linhas.add(Container(height: 1, color: fio));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: linhas,
        );
      },
    );
  }

  List<Widget> _itensLeitura(BuildContext context) {
    final s = _metrics.summary;
    final eixo = SdrTom.eixo(context);
    final conv = s.conversaoCoorte;

    final w = _metrics.whatsapp;
    final media = sdrMinutos(w?.avgFirstResponseMinutes);
    final mediana = sdrMinutos(w?.medianFirstResponseMinutes);
    final aguardando = w?.awaitingReplyCount ?? 0;
    final amostra = w?.firstResponseSampleSize ?? 0;

    final fontes = [..._metrics.bySource]
      ..sort((a, b) => b.totalLeads.compareTo(a.totalLeads));
    final top = fontes.isEmpty ? null : fontes.first;
    final fatiaTop = (top != null && s.totalLeads > 0)
        ? top.totalLeads / s.totalLeads
        : null;

    // Leads por dia = média dos últimos 7 dias de cards criados
    // (`dailyCreatedByDate`, janela de 30), como no web.
    final diario = _metrics.dailyCreatedByDate;
    final ult30 =
        diario.length > 30 ? diario.sublist(diario.length - 30) : diario;
    final ult7 = ult30.length > 7 ? ult30.sublist(ult30.length - 7) : ult30;
    final soma7 = ult7.fold<int>(0, (a, d) => a + d.created);
    final media7 = ult7.isEmpty ? null : (soma7 / ult7.length).round();
    final pico7 =
        ult7.isEmpty ? 0 : ult7.map((d) => d.created).reduce(math.max);

    return [
      _Leitura(
        icone: LucideIcons.percent,
        rotulo: 'Conversão',
        valor: sdrPct(conv),
        sinal: sdrSinalConversao(conv),
        detalhe:
            '${sdrInt(s.transferredByEntry)} transferidos de ${sdrInt(s.coorte)} que entraram',
        nota: 'Coorte por data de entrada',
        pe: SdrTrilho(
          fracao: conv / 100,
          cor: SdrTom.transferido(context),
          altura: 5,
        ),
      ),
      _Leitura(
        icone: LucideIcons.messageCircle,
        rotulo: 'Resp. WhatsApp',
        valor: media ?? 'Sem amostra',
        valorNome: media == null,
        detalhe: mediana != null
            ? 'Mediana $mediana · média ${media ?? '—'}'
            : 'Tempo da primeira resposta no período',
        nota: aguardando > 0
            ? '${sdrInt(aguardando)} ${aguardando == 1 ? 'conversa aguardando' : 'conversas aguardando'} retorno'
            : amostra > 0
                ? 'Base de ${sdrInt(amostra)} conversas analisadas'
                : null,
        notaIcone: aguardando > 0 ? LucideIcons.clock3 : null,
        notaTom: aguardando > 0 ? SdrTom.qualificacao(context) : null,
        pe: const SdrPontilhado(),
      ),
      _Leitura(
        icone: LucideIcons.megaphone,
        rotulo: 'Maior origem',
        valor: top?.source ?? 'Sem origem dominante',
        valorNome: true,
        detalhe: top != null
            ? '${sdrInt(top.totalLeads)} leads · ${sdrPct(top.conversionRate)} de conversão'
            : 'Nenhuma origem com volume no recorte',
        nota: fatiaTop != null ? '${sdrPct(fatiaTop * 100)} do volume total' : null,
        pe: fatiaTop != null
            ? SdrTrilho(fracao: fatiaTop, cor: eixo, altura: 5)
            : const SdrPontilhado(),
      ),
      _Leitura(
        icone: LucideIcons.chartColumn,
        rotulo: 'Leads por dia',
        valor: media7 != null ? sdrInt(media7) : 'Sem dado',
        valorNome: media7 == null,
        detalhe: media7 != null
            ? '${sdrInt(soma7)} leads nos últimos 7 dias'
            : 'Média de cards criados por dia',
        nota: media7 != null ? 'Pico de ${sdrInt(pico7)} leads em um dia' : null,
        pe: ult7.length > 1
            ? SdrMiniGrafico(
                valores: ult7.map((d) => d.created).toList(growable: false),
                cor: eixo,
                altura: 24,
              )
            : const SdrPontilhado(),
      ),
    ];
  }

  // ─── 4. Leads & duplicados (a peneira) ────────────────────────────────────

  Widget _peneira(BuildContext context) {
    final theme = Theme.of(context);
    final s = _metrics.summary;
    final eixo = SdrTom.eixo(context);
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    final fio = SdrTom.trilho(context);

    // Bruto = cards criados + repetidos que o dedupe absorveu (sem card).
    final cards = s.totalEntries;
    final absorvidos = s.duplicateInbound ?? 0;
    final total = s.grossEntries ?? cards + absorvidos;
    final novos = s.uniqueLeads;
    final ecoCards = s.duplicateCards ?? math.max(0, cards - novos);
    final eco = s.duplicateLeads;
    final ecoPct = total > 0 ? (eco * 100 / total).round() : 0;
    final novosPct = total > 0 ? 100 - ecoPct : 0;
    final dias = _metrics.leadsByDay.where((d) => d.date != null).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SdrSecaoCabecalho(
          icone: LucideIcons.copy,
          titulo: 'Leads & duplicados',
          dica:
              'Portais reenviam o mesmo lead. A peneira separa gente nova de eco: repetição não vira atendimento.',
        ),
        const SizedBox(height: 16),
        Text(
          '${sdrInt(total)} leads entrantes (brutos) no período',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: ThemeHelpers.textColor(context),
          ),
        ),
        const SizedBox(height: 8),
        SdrBarraPeneira(novos: novos, eco: eco),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _placarPeneira(
                  context,
                  amostra: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: eixo,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  rotulo: 'Gente nova',
                  valor: novos,
                  sub: '$novosPct% do que entrou',
                  subTom: SdrTom.texto(context, eixo),
                  ),
                ),
              ),
              Container(width: 1, color: fio),
              const SizedBox(width: 12),
              Expanded(
                child: _placarPeneira(
                  context,
                  amostra: const SdrHachura(largura: 10, altura: 10),
                  rotulo: 'Eco',
                  valor: eco,
                  sub: '$ecoPct% chegou repetido',
                  subTom: ThemeHelpers.textColor(context),
                  sub2: (ecoCards > 0 || absorvidos > 0)
                      ? '${sdrInt(ecoCards)} viraram card · ${sdrInt(absorvidos)} absorvidos pelo dedupe'
                      : null,
                ),
              ),
            ],
          ),
        ),
        if (dias.length > 1) ...[
          const SizedBox(height: 18),
          _colunasDias(context, dias),
        ],
        ..._frasesPeneira(context, dias, total: total, eco: eco, ecoPct: ecoPct)
            .expand((f) => [const SizedBox(height: 10), f]),
        if (dias.isEmpty && total == 0) ...[
          const SizedBox(height: 10),
          Text(
            'Sem leads no período selecionado.',
            style: theme.textTheme.bodySmall?.copyWith(color: secundaria),
          ),
        ],
      ],
    );
  }

  Widget _placarPeneira(
    BuildContext context, {
    required Widget amostra,
    required String rotulo,
    required int valor,
    required String sub,
    required Color subTom,
    String? sub2,
  }) {
    final theme = Theme.of(context);
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            amostra,
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                rotulo.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: secundaria,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            sdrInt(valor),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
              letterSpacing: -0.6,
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          sub,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: subTom,
            fontWeight: FontWeight.w800,
            fontSize: 11.5,
          ),
        ),
        if (sub2 != null) ...[
          const SizedBox(height: 3),
          Text(
            sub2,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: secundaria,
              fontSize: 11,
              height: 1.3,
            ),
          ),
        ],
      ],
    );
  }

  /// Colunas por dia: sólido = gente nova, hachura = eco. Toque segura a
  /// dica com o dia e os números.
  Widget _colunasDias(BuildContext context, List<SdrDayPoint> dias) {
    final theme = Theme.of(context);
    final data = dias.length > 31 ? dias.sublist(dias.length - 31) : dias;
    final maior = data.fold<int>(0, (m, d) => math.max(m, d.total));
    if (maior <= 0) return const SizedBox.shrink();
    const alturaMax = 64.0;
    final eixo = SdrTom.eixo(context);
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    // A altura do DIA sai do total; eco e gente nova dividem essa altura
    // (o piso de 2dp vale para o dia inteiro — somar pisos por parte
    // passaria dos 64 e estouraria a coluna).
    ({double eco, double novos}) alturas(SdrDayPoint d) {
      if (d.total <= 0) return (eco: 0.0, novos: 0.0);
      final dia = math.max(2.0, alturaMax * d.total / maior);
      final fatiaEco = (d.duplicates / d.total).clamp(0.0, 1.0).toDouble();
      return (eco: dia * fatiaEco, novos: dia * (1 - fatiaEco));
    }

    String dm(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    final estilo = theme.textTheme.labelSmall?.copyWith(
      color: secundaria,
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: alturaMax,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < data.length; i++) ...[
                if (i > 0) SizedBox(width: data.length > 20 ? 1.5 : 3),
                Expanded(
                  child: Tooltip(
                    message:
                        '${dm(data[i].date!)} · ${sdrInt(data[i].total)} entradas · ${sdrInt(data[i].duplicates)} eco',
                    child: Builder(builder: (context) {
                      final a = alturas(data[i]);
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (a.eco > 0)
                            SizedBox(
                              height: a.eco,
                              width: double.infinity,
                              child: CustomPaint(
                                painter: SdrHachuraPainter(
                                  traco: secundaria.withValues(alpha: 0.55),
                                  fundo: SdrTom.trilho(context),
                                ),
                              ),
                            ),
                          if (a.novos > 0)
                            Container(
                              height: a.novos,
                              width: double.infinity,
                              color: eixo,
                            ),
                        ],
                      );
                    }),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(dm(data.first.date!), style: estilo),
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 8, height: 8, color: eixo),
                      const SizedBox(width: 4),
                      Text('gente nova', style: estilo),
                      const SizedBox(width: 10),
                      const SdrHachura(largura: 8, altura: 8, raio: 1),
                      const SizedBox(width: 4),
                      Text('eco', style: estilo),
                    ],
                  ),
                ),
              ),
            ),
            Text(dm(data.last.date!), style: estilo),
          ],
        ),
      ],
    );
  }

  /// As leituras da peneira — os mesmos números, em frases curtas.
  List<Widget> _frasesPeneira(
    BuildContext context,
    List<SdrDayPoint> dias, {
    required int total,
    required int eco,
    required int ecoPct,
  }) {
    final negrito = TextStyle(
      fontWeight: FontWeight.w900,
      color: ThemeHelpers.textColor(context),
    );
    final frases = <Widget>[];
    final razao = eco > 0 ? math.max(2, (total / eco).round()) : 0;
    if (eco > 0 && razao >= 2) {
      frases.add(_Frase(
        icone: LucideIcons.funnel,
        tom: SdrTom.eixo(context),
        texto: [
          const TextSpan(text: 'A cada '),
          TextSpan(text: '${sdrInt(razao)} entradas', style: negrito),
          const TextSpan(text: ', 1 chega repetida: foram '),
          TextSpan(text: sdrInt(eco), style: negrito),
          const TextSpan(text: ' atendimentos que a peneira poupou.'),
        ],
      ));
    } else if (total > 0) {
      frases.add(_Frase(
        icone: LucideIcons.circleCheck,
        tom: SdrTom.transferido(context),
        texto: [
          TextSpan(text: 'Nenhum eco', style: negrito),
          const TextSpan(text: ' no período: tudo que entrou é gente nova.'),
        ],
      ));
    }

    SdrDayPoint? pico;
    for (final d in dias) {
      if (pico == null || d.duplicates > pico.duplicates) pico = d;
    }
    if (pico != null && pico.duplicates > 0 && pico.date != null) {
      final d = pico.date!;
      frases.add(_Frase(
        icone: LucideIcons.triangleAlert,
        tom: SdrTom.qualificacao(context),
        texto: [
          const TextSpan(text: 'O dia mais ruidoso foi '),
          TextSpan(text: sdrDiaMes(d), style: negrito),
          TextSpan(
            text:
                ': ${sdrInt(pico.duplicates)} ecos em ${sdrInt(pico.total)} entradas.',
          ),
        ],
      ));
    }

    if (dias.length > 7) {
      final ult7 = dias.sublist(dias.length - 7);
      final tot7 = ult7.fold<int>(0, (a, d) => a + d.total);
      final dup7 = ult7.fold<int>(0, (a, d) => a + d.duplicates);
      if (tot7 > 0) {
        final recente = (dup7 * 100 / tot7).round();
        final tendencia = recente - ecoPct;
        if (tendencia.abs() > 2) {
          final subindo = tendencia > 0;
          frases.add(_Frase(
            icone: subindo ? LucideIcons.trendingUp : LucideIcons.trendingDown,
            tom: subindo
                ? SdrTom.qualificacao(context)
                : SdrTom.transferido(context),
            texto: [
              const TextSpan(text: 'O eco está '),
              TextSpan(text: subindo ? 'subindo' : 'caindo', style: negrito),
              TextSpan(
                text:
                    ': $recente% nos últimos 7 dias, contra $ecoPct% no período todo.',
              ),
            ],
          ));
        }
      }
    }
    return frases;
  }

  // ─── 5. Funil de conversão ────────────────────────────────────────────────

  Widget _funilConversao(BuildContext context) {
    final theme = Theme.of(context);
    final s = _metrics.summary;
    final e = s.totalEntries;
    final perdidos = s.lostByEntry;
    // "Contatados" = entradas − perdidos (a conta do web: quem avançou).
    final contatados = math.max(0, e - perdidos);
    final eixo = SdrTom.eixo(context);
    final etapas = <({String rotulo, int valor, Color tom})>[
      (rotulo: 'Entradas', valor: e, tom: eixo),
      (rotulo: 'Contatados', valor: contatados, tom: eixo.withValues(alpha: 0.62)),
      (
        rotulo: 'Em qualificação',
        valor: s.inQualification,
        tom: SdrTom.qualificacao(context),
      ),
      (rotulo: 'Perdidos', valor: perdidos, tom: SdrTom.perdido(context)),
    ];
    final maior = math.max(1, etapas.map((x) => x.valor).reduce(math.max));
    // Largura pela raiz (como o web): etapa pequena continua visível.
    double largura(int v) => math.max(0.16, math.sqrt(v / maior));
    final secundaria = ThemeHelpers.textSecondaryColor(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SdrSecaoCabecalho(
          icone: LucideIcons.funnel,
          titulo: 'Funil de conversão SDR',
          dica:
              '${sdrInt(e)} entradas (CRM) · ${sdrInt(s.transferredByEntry)} transferidos da coorte · ${sdrPct(s.conversaoCoorte)} de conversão',
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, c) {
            final larguraFunil =
                (c.maxWidth * 0.42).clamp(104.0, 240.0).toDouble();
            return Column(
              children: [
                for (var i = 0; i < etapas.length; i++) ...[
                  if (i > 0) const SizedBox(height: 3),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: larguraFunil,
                          child: CustomPaint(
                            painter: SdrCamadaFunilPainter(
                              topo: largura(etapas[i].valor),
                              base: i + 1 < etapas.length
                                  ? largura(etapas[i + 1].valor)
                                  : largura(etapas[i].valor) * 0.82,
                              cor: etapas[i].tom,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            child: _rotuloEtapaFunil(
                              context,
                              i: i,
                              rotulo: etapas[i].rotulo,
                              valor: etapas[i].valor,
                              anterior: i > 0 ? etapas[i - 1].valor : null,
                              base: e,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Text(
          'Passagem = quanto cada etapa tem em relação à anterior. Os '
          'transferidos saem do funil e entram só na conversão.',
          style: theme.textTheme.labelSmall?.copyWith(
            color: secundaria,
            fontSize: 11,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _rotuloEtapaFunil(
    BuildContext context, {
    required int i,
    required String rotulo,
    required int valor,
    required int? anterior,
    required int base,
  }) {
    final theme = Theme.of(context);
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    final ehPerda = rotulo == 'Perdidos';
    final passagem =
        (anterior != null && anterior > 0) ? valor * 100 / anterior : null;
    // Passagem colorida só nas etapas de avanço (verde ≥ 50, âmbar ≥ 25,
    // vermelho abaixo, como o web). Na perda, "passar mais" não é bom —
    // fica neutra.
    final tomPassagem = passagem == null || ehPerda
        ? secundaria
        : SdrTom.texto(
            context,
            passagem >= 50
                ? SdrTom.transferido(context)
                : passagem >= 25
                    ? SdrTom.qualificacao(context)
                    : SdrTom.perdido(context),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          rotulo,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            color: ThemeHelpers.textColor(context),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: sdrInt(valor),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: -0.3,
                ),
              ),
              TextSpan(
                text: i == 0
                    ? '  topo do funil'
                    : '  ${sdrPct(base > 0 ? valor * 100 / base : 0)} do total',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: secundaria,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (passagem != null) ...[
          const SizedBox(height: 2),
          Text(
            '${sdrPct(passagem)} de passagem',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: tomPassagem,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ],
    );
  }

  // ─── 6. Funil por etapa ───────────────────────────────────────────────────

  Widget _funilPorEtapa(BuildContext context) {
    final theme = Theme.of(context);
    final colunas = _metrics.byColumn;
    final maior = colunas.fold<int>(0, (m, c) => math.max(m, c.totalLeads));
    final visiveis = _etapasTodas
        ? colunas
        : colunas.take(_kEtapasIniciais).toList(growable: false);
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SdrSecaoCabecalho(
          icone: LucideIcons.columns3,
          titulo: 'Funil por etapa',
          dica: 'Leads em cada coluna do funil SDR, na ordem do quadro.',
          trailing: Text(
            colunas.length == 1 ? '1 etapa' : '${colunas.length} etapas',
            style: theme.textTheme.labelSmall?.copyWith(
              color: secundaria,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < visiveis.length; i++)
          _linhaEtapa(
            context,
            indice: i,
            coluna: visiveis[i],
            anterior: i > 0 ? visiveis[i - 1].totalLeads : null,
            maior: maior,
            ultima: i == visiveis.length - 1,
          ),
        if (colunas.length > _kEtapasIniciais)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _etapasTodas = !_etapasTodas),
              style: TextButton.styleFrom(
                foregroundColor: secundaria,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              ),
              icon: Icon(
                _etapasTodas ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                size: 16,
              ),
              label: Text(
                _etapasTodas
                    ? 'Mostrar menos'
                    : 'Mostrar as ${colunas.length} etapas',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
    );
  }

  Widget _linhaEtapa(
    BuildContext context, {
    required int indice,
    required SdrColumnMetric coluna,
    required int? anterior,
    required int maior,
    required bool ultima,
  }) {
    final theme = Theme.of(context);
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    final eixo = SdrTom.eixo(context);
    final totalLeads = _metrics.summary.totalLeads;
    final doTotal = totalLeads > 0 ? coluna.totalLeads * 100 / totalLeads : 0.0;
    final passo = (anterior != null && anterior > 0)
        ? coluna.totalLeads * 100 / anterior
        : null;
    final estilo = theme.textTheme.labelSmall?.copyWith(
      color: secundaria,
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: ultima
            ? null
            : Border(bottom: BorderSide(color: SdrTom.trilho(context))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 30,
            child: Text(
              (indice + 1).toString().padLeft(2, '0'),
              style: theme.textTheme.labelMedium?.copyWith(
                color: SdrTom.texto(context, eixo),
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        coluna.columnTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ThemeHelpers.textColor(context),
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      sdrInt(coluna.totalLeads),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: ThemeHelpers.textColor(context),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SdrTrilho(
                  fracao: maior > 0 ? coluna.totalLeads / maior : 0,
                  cor: eixo,
                  altura: 5,
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${sdrPct(doTotal)} do total',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: estilo,
                      ),
                    ),
                    if (passo != null)
                      Text('passo ${sdrPct(passo)}', maxLines: 1, style: estilo),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Estados ───────────────────────────────────────────────────────────────

  Widget _buildError(BuildContext context) {
    return AppErrorState.fromApi(
      message: _errorMessage,
      statusCode: _errorStatus,
      onRetry: _loadMetrics,
    );
  }

  /// Esqueleto fiel à tela: topo (título, atalhos do período, régua), a base
  /// do funil, as três estações com o ramal, a grade de leituras e a peneira.
  Widget _buildSkeleton(BuildContext context) {
    final gutter = _sideGutter(context);
    final fio = SdrTom.trilho(context);
    Widget linhaFio() => Container(height: 1, color: fio);

    Widget estacao() => Padding(
          padding: const EdgeInsets.fromLTRB(28, 14, 0, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [
              Row(
                children: [
                  SkeletonBox(width: 16, height: 16, borderRadius: 5),
                  SizedBox(width: 8),
                  Expanded(child: SkeletonText(width: 130, height: 13)),
                  SizedBox(width: 12),
                  SkeletonText(width: 46, height: 20),
                ],
              ),
              SizedBox(height: 10),
              SkeletonBox(height: 6, borderRadius: 99),
              SizedBox(height: 8),
              SkeletonText(width: 210, height: 10),
            ],
          ),
        );

    Widget leitura() => const Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonText(width: 90, height: 10),
              SizedBox(height: 10),
              SkeletonText(width: 70, height: 22),
              SizedBox(height: 8),
              SkeletonText(width: 120, height: 10),
              SizedBox(height: 12),
              SkeletonBox(height: 5, borderRadius: 99),
            ],
          ),
        );

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        _kPadH + gutter,
        _kPadTop,
        _kPadH + gutter,
        _kPadBottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonText(width: 190, height: 20),
                    SizedBox(height: 8),
                    SkeletonText(width: 250, height: 11),
                    SizedBox(height: 8),
                    SkeletonText(width: 110, height: 10),
                  ],
                ),
              ),
              SizedBox(width: 12),
              SkeletonBox(width: 40, height: 40, borderRadius: 12),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              for (var i = 0; i < 4; i++)
                const Expanded(
                  child: Center(child: SkeletonText(width: 44, height: 12)),
                ),
              const SizedBox(
                width: 52,
                child: Center(
                  child: SkeletonBox(width: 18, height: 18, borderRadius: 5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          linhaFio(),
          const SizedBox(height: 12),
          const SkeletonBox(height: 8, borderRadius: 3),
          const SizedBox(height: 8),
          const Row(
            children: [
              SkeletonText(width: 40, height: 10),
              Spacer(),
              SkeletonText(width: 50, height: 10),
              Spacer(),
              SkeletonText(width: 64, height: 10),
            ],
          ),
          const SizedBox(height: 14),
          const SkeletonText(width: 260, height: 10),
          const SizedBox(height: 26),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonText(width: 140, height: 10),
                    SizedBox(height: 10),
                    SkeletonText(width: 130, height: 38),
                    SizedBox(height: 10),
                    SkeletonText(width: 220, height: 10),
                  ],
                ),
              ),
              SizedBox(width: 14),
              SkeletonBox(width: 92, height: 34, borderRadius: 8),
            ],
          ),
          const SizedBox(height: 6),
          estacao(),
          estacao(),
          estacao(),
          const SizedBox(height: 16),
          linhaFio(),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: leitura()),
                Container(width: 1, color: fio),
                const SizedBox(width: 12),
                Expanded(child: leitura()),
              ],
            ),
          ),
          linhaFio(),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: leitura()),
                Container(width: 1, color: fio),
                const SizedBox(width: 12),
                Expanded(child: leitura()),
              ],
            ),
          ),
          linhaFio(),
          const SizedBox(height: 30),
          const Row(
            children: [
              SkeletonBox(width: 30, height: 30, borderRadius: 9),
              SizedBox(width: 10),
              SkeletonText(width: 160, height: 15),
            ],
          ),
          const SizedBox(height: 16),
          const SkeletonBox(height: 12, borderRadius: 99),
        ],
      ),
    );
  }
}

// ─── Estação do funil ────────────────────────────────────────────────────────

/// Um destino das entradas: rótulo e número, trilho da participação sobre as
/// entradas (com o sinal de saúde quando há), o detalhe e a nota. O ramal à
/// esquerda liga a estação à base. Toque abre a lista.
class _Estacao extends StatelessWidget {
  const _Estacao({
    required this.icone,
    required this.rotulo,
    required this.valor,
    required this.fracao,
    required this.tom,
    required this.detalhe,
    required this.ultimo,
    required this.onTap,
    this.nota,
    this.notaIcone,
    this.sinal,
    this.sinalDica,
  });

  final IconData icone;
  final String rotulo;
  final int valor;
  final double fracao;
  final Color tom;
  final String detalhe;
  final String? nota;
  final IconData? notaIcone;
  final SdrSinal? sinal;

  /// O que o sinal mede ("taxa de perda") — vai na dica do ícone.
  final String? sinalDica;
  final bool ultimo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tinta = SdrTom.texto(context, tom);
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    final escala = MediaQuery.textScalerOf(context).scale(16) / 16;
    final s = sinal;
    final tintaSinal = s == null ? null : SdrTom.texto(context, s.tom(context));

    return InkWell(
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 22,
              child: CustomPaint(
                painter: SdrRamalPainter(
                  cor: ThemeHelpers.borderColor(context),
                  ultimo: ultimo,
                  meio: 13 + 11 * escala,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 0, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(icone, size: 16, color: tinta),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            rotulo,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: ThemeHelpers.textColor(context),
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          sdrInt(valor),
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: ThemeHelpers.textColor(context),
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          LucideIcons.chevronRight,
                          size: 16,
                          color: secundaria.withValues(alpha: 0.7),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Expanded(child: SdrTrilho(fracao: fracao, cor: tom)),
                        const SizedBox(width: 10),
                        Text(
                          sdrPct(fracao * 100),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: tinta,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (s != null && tintaSinal != null) ...[
                          const SizedBox(width: 8),
                          Tooltip(
                            message: sinalDica == null
                                ? s.palavra
                                : '${sinalDica!}: ${s.palavra}',
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(s.icone, size: 13, color: tintaSinal),
                                const SizedBox(width: 3),
                                Text(
                                  s.palavra,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: tintaSinal,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      detalhe,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: secundaria,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                    if (nota != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Icon(
                              notaIcone ?? LucideIcons.info,
                              size: 12,
                              color: secundaria,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              nota!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: ThemeHelpers.textColor(context),
                                fontWeight: FontWeight.w700,
                                fontSize: 11.5,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Leitura (célula da grade) ───────────────────────────────────────────────

/// Célula de leitura: rótulo, valor, sinal (quando há), detalhe, nota e um
/// pé visual (trilho, minigráfico ou pontilhado). Leitura não é status: a
/// marca do rótulo é neutra.
class _Leitura extends StatelessWidget {
  const _Leitura({
    required this.icone,
    required this.rotulo,
    required this.valor,
    required this.detalhe,
    required this.pe,
    this.valorNome = false,
    this.sinal,
    this.nota,
    this.notaIcone,
    this.notaTom,
  });

  final IconData icone;
  final String rotulo;
  final String valor;

  /// Valor que é um nome ("Facebook") ou uma frase curta: tipografia de nome,
  /// em até 2 linhas, em vez do número grande.
  final bool valorNome;
  final SdrSinal? sinal;
  final String detalhe;
  final String? nota;
  final IconData? notaIcone;
  final Color? notaTom;
  final Widget pe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    final s = sinal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icone, size: 13, color: secundaria),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                rotulo.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: secundaria,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.9,
                  fontSize: 10.5,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (valorNome)
          Text(
            valor,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
              height: 1.2,
            ),
          )
        else
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valor,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w900,
                letterSpacing: -0.8,
                height: 1.05,
              ),
            ),
          ),
        if (s != null) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                s.icone,
                size: 12,
                color: SdrTom.texto(context, s.tom(context)),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  s.palavra,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: SdrTom.texto(context, s.tom(context)),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 6),
        Text(
          detalhe,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: secundaria,
            fontSize: 11,
            height: 1.35,
          ),
        ),
        if (nota != null) ...[
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (notaIcone != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    notaIcone,
                    size: 12,
                    color: notaTom == null
                        ? secundaria
                        : SdrTom.texto(context, notaTom!),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  nota!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],
        const Spacer(),
        const SizedBox(height: 10),
        pe,
      ],
    );
  }
}

// ─── Frase de leitura (peneira) ──────────────────────────────────────────────

class _Frase extends StatelessWidget {
  const _Frase({required this.icone, required this.tom, required this.texto});

  final IconData icone;
  final Color tom;
  final List<InlineSpan> texto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: tom.withValues(alpha: isDark ? 0.18 : 0.10),
          ),
          child: Icon(icone, size: 14, color: SdrTom.texto(context, tom)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text.rich(
              TextSpan(children: texto),
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
                height: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Atalho do período (aba com sublinhado) ──────────────────────────────────

class _AbaSublinhada extends StatelessWidget {
  const _AbaSublinhada({
    required this.ativa,
    required this.tom,
    required this.onTap,
    required this.child,
  });

  final bool ativa;
  final Color tom;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: DefaultTextStyle.merge(
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: ativa
                        ? tom
                        : ThemeHelpers.textSecondaryColor(context),
                    fontWeight: ativa ? FontWeight.w900 : FontWeight.w600,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 2.5,
            decoration: BoxDecoration(
              color: ativa ? tom : Colors.transparent,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Botão de atualizar (canto do topo) ──────────────────────────────────────

class _BotaoAtualizar extends StatelessWidget {
  const _BotaoAtualizar({required this.ocupado, required this.onTap});

  final bool ocupado;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: ocupado ? 'Atualizando' : 'Atualizar',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: ocupado ? null : () => onTap(),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ThemeHelpers.borderColor(context)),
            ),
            child: ocupado
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: SdrTom.eixo(context),
                    ),
                  )
                : Icon(
                    LucideIcons.refreshCw,
                    size: 17,
                    color: ThemeHelpers.textColor(context),
                  ),
          ),
        ),
      ),
    );
  }
}

// ─── Ação da appbar com badge de filtros ativos ──────────────────────────────

/// Envolve um [ChromeToolbarIconButton] com um selo no canto — quantos
/// filtros fogem do padrão. Some quando `count == 0`.
class _BadgedToolbarAction extends StatelessWidget {
  const _BadgedToolbarAction({required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Selo na tinta legível do eixo; o número usa o `onPrimaryColor` do tema
    // (branco no claro, grafite no escuro — o petróleo claro do escuro não
    // segura texto branco).
    final tom = SdrTom.texto(context, SdrTom.eixo(context));
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (count > 0)
          Positioned(
            top: 5,
            right: 4,
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(minWidth: 15),
                height: 15,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: tom,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: ThemeHelpers.backgroundColor(context)
                        .withValues(alpha: 0.9),
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: ThemeHelpers.onPrimaryColor(context),
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Acesso negado ───────────────────────────────────────────────────────────

class _DeniedView extends StatelessWidget {
  const _DeniedView();

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    // Texto da cerca de verdade (sdr-01): o Dash SDR lê o CRM — módulo
    // `kanban_management` + `kanban:view_all_teams`. Rola em paisagem com
    // fonte grande em vez de estourar.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.lock, size: 38, color: secondary),
              const SizedBox(height: 12),
              Text(
                'Você não tem acesso ao Dash SDR',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'O painel mostra os leads do funil SDR no CRM. Peça ao '
                'administrador o módulo CRM e a permissão de ver todas as '
                'equipes.',
                textAlign: TextAlign.center,
                style: TextStyle(color: secondary, fontSize: 12.5, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
