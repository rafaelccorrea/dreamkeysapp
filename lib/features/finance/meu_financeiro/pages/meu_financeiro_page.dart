import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/module_access_service.dart';
import '../../../../shared/services/subscription_access_gate.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../aprovacoes/approvals_service.dart';
import '../../core/finance_access.dart';
import '../../core/finance_errors.dart';
import '../../core/finance_format.dart';
import '../../core/finance_pin_store.dart';
import '../../core/finance_route_names.dart';
import '../../core/finance_visibility.dart';
import '../../notificacoes/finance_notifications_controller.dart';
import '../../notificacoes/widgets/finance_bell_button.dart';
import '../models/drill_models.dart';
import '../models/meu_financeiro_models.dart';
import '../services/meu_financeiro_service.dart';
import '../widgets/drill_sheets.dart';
import '../widgets/meu_financeiro_widgets.dart';

/// Recorte de período da lista por visão (vale só para `/proximos`).
enum FinancePeriodo {
  tudo('Tudo'),
  esteMes('Este mês'),
  d30('30 dias'),
  d90('90 dias');

  const FinancePeriodo(this.label);
  final String label;

  /// `(from, to)` em `YYYY-MM-DD` (MeuFinanceiroPage.tsx:283,656).
  (String?, String?) range(DateTime today) {
    final d = DateTime(today.year, today.month, today.day);
    switch (this) {
      case FinancePeriodo.tudo:
        return (null, null);
      case FinancePeriodo.esteMes:
        final ini = DateTime(d.year, d.month, 1);
        final fim = DateTime(d.year, d.month + 1, 0);
        return (financeQueryDate(ini), financeQueryDate(fim));
      case FinancePeriodo.d30:
        return (
          financeQueryDate(d.subtract(const Duration(days: 29))),
          financeQueryDate(d),
        );
      case FinancePeriodo.d90:
        return (
          financeQueryDate(d.subtract(const Duration(days: 89))),
          financeQueryDate(d),
        );
    }
  }
}

/// Mensagem do topo (MeuFinanceiroPage.tsx:1258-1420): o primeiro caso que
/// casar vence. Pura (testável).
({String title, String text, String tone}) meuFinanceiroInsight(
  BrokerDashboardSummary s, {
  List<BrokerProximo> proximos = const [],
  bool hidden = false,
}) {
  String v(double x) => formatBrl(x, hidden: hidden);
  final ass = s.aguardandoAssinatura;
  if (ass.count > 0) {
    return (
      title: 'Ação sua · assinatura',
      text:
          '${ass.count} ${ass.count == 1 ? 'ficha aguarda' : 'fichas aguardam'} '
          'sua assinatura — ${v(ass.valor)} ficam travados até você assinar.',
      tone: 'amber',
    );
  }
  if (s.totals.saldoDevedor > 0) {
    return (
      title: 'Atenção · adiantamento',
      text:
          'Você tem ${v(s.totals.saldoDevedor)} de saldo devedor com a '
          'imobiliária. Ele é abatido dos próximos repasses.',
      tone: 'rose',
    );
  }
  if (proximos.any((p) => p.emAtraso)) {
    return (
      title: 'Atenção · previsão vencida',
      text:
          'Há repasses com a previsão de pagamento vencida. Se algo estiver '
          'errado, fale com o financeiro.',
      tone: 'rose',
    );
  }
  if (s.totals.aReceber > 0) {
    return (
      title: 'Próximos recebimentos',
      text: '${v(s.totals.aReceber)} de comissões a receber.',
      tone: 'sky',
    );
  }
  if (s.totals.recebido > 0) {
    return (
      title: 'Tudo em dia',
      text: 'Nenhuma pendência — ${v(s.totals.recebido)} já recebidos.',
      tone: 'emerald',
    );
  }
  return (
    title: 'Meu financeiro',
    text: 'Ainda não há comissões registradas para você.',
    tone: 'slate',
  );
}

/// Meu Financeiro do corretor — `/financeiro/meu-dashboard`. Sem
/// `financial:access` (é a visão pessoal); o portão do PIN fica na rota.
class MeuFinanceiroPage extends StatefulWidget {
  /// Serviço (fake nos testes).
  final MeuFinanceiroService? service;

  /// Venda a abrir na consulta ao entrar (deep link `?venda=`).
  final String? initialSaleId;

  const MeuFinanceiroPage({super.key, this.service, this.initialSaleId});

  @override
  State<MeuFinanceiroPage> createState() => _MeuFinanceiroPageState();
}

class _MeuFinanceiroPageState extends State<MeuFinanceiroPage> {
  static const String _hiddenPrefKey = 'meuFinanceiro:valoresOcultos';

  MeuFinanceiroService get _svc =>
      widget.service ?? MeuFinanceiroService.instance;

  MeuFinanceiroSnapshot? _snap;
  FinancePage<BrokerProximo>? _proximos;
  FinanceError? _proximosError;
  FinancePage<BrokerVenda>? _vendas;
  FinanceError? _vendasError;
  bool _loading = true;
  bool _refreshing = false;
  bool _loadingProx = false;
  bool _loadingVend = false;
  bool _loadingMoreProx = false;
  bool _loadingMoreVend = false;

  // Contadores de sequência: resposta atrasada é descartada.
  int _seq = 0;
  int _proxSeq = 0;
  int _vendSeq = 0;

  FinanceVisao _visao = FinanceVisao.aReceber;
  FinancePeriodo _periodo = FinancePeriodo.tudo;

  /// Recorte personalizado (substitui os atalhos de período).
  DateTimeRange? _customRange;

  /// Mês clicado no gráfico (`YYYY-MM`) — divide o filtro com o período.
  String? _mesSel;

  /// Status do rail (só na visão a-receber; seleção única).
  String? _status;

  /// "Para aprovar": contagem do Meu aval (só para quem tem o crachá).
  int? _meuAval;
  bool _initialSaleOpened = false;
  Timer? _pushDebounce;
  VendaSituacao _situacao = VendaSituacao.todas;
  String _search = '';
  String? _brokerId;
  bool _hidden = false;

  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  Timer? _auto;
  bool _wasUnlocked = true;

  final FinancePinStore _pins = FinancePinStore.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_loadHiddenPref());
    unawaited(_loadAll());
    _wasUnlocked = _pins.isUnlocked;
    _pins.addListener(_onPinChanged);
    // Atualização automática a cada 60 s com a tela visível e destravada.
    _auto = Timer.periodic(const Duration(seconds: 60), (_) => _autoRefresh());
    // Cada aviso do socket do Financeiro atualiza (debounce de 1,5 s).
    FinanceNotificationsController.instance.pushTick.addListener(_onPush);
  }

  void _onPush() {
    _pushDebounce?.cancel();
    _pushDebounce = Timer(const Duration(milliseconds: 1500), _autoRefresh);
  }

  @override
  void dispose() {
    FinanceNotificationsController.instance.pushTick.removeListener(_onPush);
    _pushDebounce?.cancel();
    _pins.removeListener(_onPinChanged);
    _auto?.cancel();
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onPinChanged() {
    final unlocked = _pins.isUnlocked;
    // Destravou de novo (voltou do segundo plano / venceu): dado fresco.
    if (unlocked && !_wasUnlocked) unawaited(_loadAll(silent: true));
    _wasUnlocked = unlocked;
  }

  void _autoRefresh() {
    if (!mounted || !_pins.isUnlocked || _refreshing) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    unawaited(_loadAll(silent: true));
  }

  Future<void> _loadHiddenPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool(_hiddenPrefKey) ?? false;
      if (mounted && v != _hidden) setState(() => _hidden = v);
    } catch (_) {}
  }

  Future<void> _toggleHidden() async {
    setState(() => _hidden = !_hidden);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_hiddenPrefKey, _hidden);
    } catch (_) {}
  }

  String? get _searchParam => _search.trim().isEmpty ? null : _search.trim();

  /// `(from, to)` do recorte: mês do gráfico > personalizado > atalho.
  (String?, String?) get _range {
    final now = DateTime.now();
    if (_mesSel != null) return mesDoGraficoRange(_mesSel!, now);
    final c = _customRange;
    if (c != null) {
      return (financeQueryDate(c.start), financeQueryDate(c.end));
    }
    return _periodo.range(now);
  }

  bool get _temRecorte =>
      _mesSel != null || _customRange != null || _periodo != FinancePeriodo.tudo;

  ProximosQuery _proxQuery({int page = 1}) {
    final (from, to) = _range;
    return ProximosQuery(
      visao: _visao,
      page: page,
      search: _searchParam,
      // O rail de status só vale na visão a-receber.
      status: _visao == FinanceVisao.aReceber ? _status : null,
      from: from,
      to: to,
      brokerId: _brokerId,
    );
  }

  bool get _cracha {
    final mas = ModuleAccessService.instance;
    return financeCrachaOk(
      crmRole: mas.userRole,
      hasFinancialAccess: mas.hasPermission('financial:access'),
    );
  }

  Future<void> _loadMeuAval() async {
    if (!_cracha) return;
    final r = await ApprovalsService.instance.meuAvalCount();
    if (mounted && r.ok) setState(() => _meuAval = r.data);
  }

  void _maybeOpenInitialSale() {
    final id = widget.initialSaleId;
    if (id == null || _initialSaleOpened) return;
    _initialSaleOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openVenda(id);
    });
  }

  void _openVenda(String saleId) => showVendaConsultaSheet(
    context,
    saleId: saleId,
    hidden: _hidden,
    service: _svc,
  );

  void _openOrigem(String repasseId) => showRepasseOrigemSheet(
    context,
    repasseId: repasseId,
    hidden: _hidden,
    service: _svc,
  );

  Future<void> _go(String route) async {
    final r = await Navigator.of(context).pushNamed(route);
    if (r != null && mounted) unawaited(_loadAll(silent: true));
  }

  VendasQuery _vendQuery({int page = 1}) => VendasQuery(
    page: page,
    search: _searchParam,
    situacao: _situacao,
    brokerId: _brokerId,
  );

  Future<void> _loadAll({bool silent = false}) async {
    final seq = ++_seq;
    if (!silent && _snap == null && !_loading) setState(() => _loading = true);
    _refreshing = true;
    // "Meu aval" corre junto (não espera o lote).
    unawaited(_loadMeuAval());
    final snap = await _svc.loadAll(
      proximosQuery: _proxQuery(),
      vendasQuery: _vendQuery(),
      brokerId: _brokerId,
    );
    _refreshing = false;
    _maybeOpenInitialSale();
    if (!mounted || seq != _seq) return;
    setState(() {
      _snap = snap;
      _loading = false;
      // As listas também vieram no lote; descartam pedidos de lista
      // anteriores que ainda estejam em voo.
      _proxSeq++;
      _vendSeq++;
      _proximos = snap.proximos.data;
      _proximosError = snap.proximos.error;
      _vendas = snap.vendas.data;
      _vendasError = snap.vendas.error;
      _loadingProx = false;
      _loadingVend = false;
    });
  }

  Future<void> _reloadProximos({bool more = false}) async {
    final seq = ++_proxSeq;
    final page = more ? (_proximos?.page ?? 0) + 1 : 1;
    setState(() {
      if (more) {
        _loadingMoreProx = true;
      } else {
        _loadingProx = true;
      }
    });
    final res = await _svc.proximos(_proxQuery(page: page));
    if (!mounted || seq != _proxSeq) return;
    setState(() {
      _loadingProx = false;
      _loadingMoreProx = false;
      if (res.ok) {
        _proximos = more && _proximos != null
            ? _proximos!.append(res.data!)
            : res.data;
        _proximosError = null;
      } else {
        _proximosError = res.error;
      }
    });
  }

  Future<void> _reloadVendas({bool more = false}) async {
    final seq = ++_vendSeq;
    final page = more ? (_vendas?.page ?? 0) + 1 : 1;
    setState(() {
      if (more) {
        _loadingMoreVend = true;
      } else {
        _loadingVend = true;
      }
    });
    final res = await _svc.vendas(_vendQuery(page: page));
    if (!mounted || seq != _vendSeq) return;
    setState(() {
      _loadingVend = false;
      _loadingMoreVend = false;
      if (res.ok) {
        _vendas = more && _vendas != null
            ? _vendas!.append(res.data!)
            : res.data;
        _vendasError = null;
      } else {
        _vendasError = res.error;
      }
    });
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted || v == _search) return;
      _search = v;
      unawaited(_reloadProximos());
      unawaited(_reloadVendas());
    });
  }

  void _selectVisao(FinanceVisao v, {VendaSituacao? situacao}) {
    // Segundo toque no cartão ativo desfaz (volta ao padrão).
    final same = _visao == v && v != FinanceVisao.aReceber;
    setState(() {
      _visao = same ? FinanceVisao.aReceber : v;
      // Trocar de visão limpa o status (só existe na a-receber).
      if (_visao != FinanceVisao.aReceber) _status = null;
      if (situacao != null) {
        _situacao = same ? VendaSituacao.todas : situacao;
      }
    });
    unawaited(_reloadProximos());
    if (situacao != null) unawaited(_reloadVendas());
  }

  void _selectBroker(String? id) {
    if (id == _brokerId) return;
    setState(() => _brokerId = id);
    unawaited(_loadAll());
  }

  /// Rail de status: seleção única; tocar no mesmo desfaz.
  void _toggleStatus(String s) {
    setState(() => _status = _status == s ? null : s);
    unawaited(_reloadProximos());
  }

  /// Clique no mês do gráfico: filtra a lista da visão ativa (não troca a
  /// visão); clicar de novo desfaz. Divide o filtro com o período.
  void _selecionarMes(String ym) {
    setState(() {
      _mesSel = _mesSel == ym ? null : ym;
      _customRange = null;
      _periodo = FinancePeriodo.tudo;
    });
    unawaited(_reloadProximos());
  }

  void _setPeriodo(FinancePeriodo p) {
    setState(() {
      // Segundo toque no atalho ativo volta para "Tudo".
      _periodo = _periodo == p && _customRange == null && _mesSel == null
          ? FinancePeriodo.tudo
          : p;
      _customRange = null;
      _mesSel = null;
    });
    unawaited(_reloadProximos());
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 3, 12, 31),
      initialDateRange: _customRange,
      locale: const Locale('pt', 'BR'),
      helpText: _visao.dateLabel,
    );
    if (r == null || !mounted) return;
    setState(() {
      _customRange = r;
      _mesSel = null;
      _periodo = FinancePeriodo.tudo;
    });
    unawaited(_reloadProximos());
  }

  void _limparRecorte() {
    setState(() {
      _customRange = null;
      _mesSel = null;
      _periodo = FinancePeriodo.tudo;
      _status = null;
    });
    unawaited(_reloadProximos());
  }

  bool get _financeOnly =>
      SubscriptionAccessGate.instance.decision ==
      AccessGateDecision.financeOnly;

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Meu Financeiro',
      showBottomNavigation: !_financeOnly,
      actions: [
        const FinanceBellButton(),
        IconButton(
          tooltip: _hidden ? 'Mostrar valores' : 'Ocultar valores',
          onPressed: _toggleHidden,
          icon: Icon(
            _hidden ? LucideIcons.eyeOff : LucideIcons.eye,
            size: 20,
            color: ThemeHelpers.textColor(context),
          ),
        ),
      ],
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final snap = _snap;
    if (_loading && snap == null) return const _Skeleton();
    if (snap == null) return const SizedBox.shrink();

    final summaryErr = snap.summary.error;
    // Empresa sem Financeiro / sem acesso: estado próprio, nunca "sem permissão".
    if (summaryErr != null &&
        (summaryErr.kind == FinanceErrorKind.companyNotProvisioned ||
            summaryErr.kind == FinanceErrorKind.companyNoAccess)) {
      return _CompanyUnavailable(error: summaryErr, onRetry: _loadAll);
    }

    final summary = snap.summary.data;
    final me = snap.me.data;
    final podeSolicitacoes =
        snap.me.ok && isFinanceTelaPermitida(me, FinanceTela.solicitacoes);
    final podeAprovar =
        snap.me.ok &&
        canSeeParaAprovar(
          crmRole: ModuleAccessService.instance.userRole,
          hasFinancialAccess: ModuleAccessService.instance.hasPermission(
            'financial:access',
          ),
          me: me,
        );
    final assinaturas = snap.assinaturas.data;

    return RefreshIndicator(
      onRefresh: () => _loadAll(silent: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _header(context, summary, snap),
          const SizedBox(height: 14),
          if (summaryErr != null) ...[
            FinanceInlineNotice(text: summaryErr.message, onRetry: _loadAll),
            const SizedBox(height: 14),
          ],
          if (podeAprovar) ...[
            _paraAprovarCard(context),
            const SizedBox(height: 14),
          ],
          if (summary != null) ...[
            _insight(context, summary),
            const SizedBox(height: 14),
            _kpis(context, summary),
            const SizedBox(height: 14),
            FinanceCard(
              child: FinanceCompositionBar(
                totals: summary.totals,
                hidden: _hidden,
              ),
            ),
            const SizedBox(height: 18),
          ],
          if (summary != null &&
              summary.aguardandoAssinatura.count > 0 &&
              assinaturas != null &&
              assinaturas.data.isNotEmpty) ...[
            _assinaturasSection(context, summary, assinaturas),
            const SizedBox(height: 18),
          ],
          _searchField(context),
          const SizedBox(height: 14),
          _visaoSection(context),
          const SizedBox(height: 18),
          if (summary != null) ...[
            FinanceCard(
              child: Column(
                children: [
                  FinanceSectionHeader(
                    title: 'Linha do tempo das comissões',
                    icon: LucideIcons.chartColumn,
                    subtitle: _mesSel == null
                        ? 'Toque num mês para filtrar a lista acima'
                        : 'Filtrando ${_mesLabel(_mesSel!)} · toque de novo para desfazer',
                  ),
                  FinanceMonthlyChart(
                    mensal: summary.mensal,
                    hidden: _hidden,
                    selectedMonth: _mesSel,
                    onMonthTap: _selecionarMes,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
          if (podeSolicitacoes && snap.requests.ok) ...[
            _requestsSection(context, snap.requests.data),
            const SizedBox(height: 18),
          ],
          _advancesSection(context, snap.advances),
          _vendasSection(context, summary),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Atualizado às ${_hhmm(snap.loadedAt)} · renova sozinho a cada 60 s',
              style: TextStyle(
                fontSize: 11.5,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Widget _header(
    BuildContext context,
    BrokerDashboardSummary? summary,
    MeuFinanceiroSnapshot snap,
  ) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final brokers = summary?.brokers ?? const <BrokerOption>[];
    final n = summary?.vendasComRepasse ?? 0;
    final sub = brokers.length > 1
        ? '$n ${n == 1 ? 'venda' : 'vendas'} com repasse · ${brokers.length} corretores no seu escopo'
        : '$n ${n == 1 ? 'venda' : 'vendas'} com repasse · o que entrou, o que foi retido e o que ainda vem';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FINANCEIRO · MEU PAINEL',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w800,
            color: financeAccent(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Suas comissões',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
            color: ThemeHelpers.textColor(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          sub,
          style: TextStyle(fontSize: 13, height: 1.35, color: secondary),
        ),
        if (brokers.length > 1 || _brokerId != null) ...[
          const SizedBox(height: 12),
          _brokerSelector(context, brokers),
        ],
      ],
    );
  }

  Widget _brokerSelector(BuildContext context, List<BrokerOption> brokers) {
    return FinanceCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          isExpanded: true,
          value: _brokerId,
          icon: const Icon(LucideIcons.chevronDown, size: 18),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Meus dados'),
            ),
            for (final b in brokers)
              DropdownMenuItem<String?>(
                value: b.brokerId,
                child: Text(
                  b.brokerName ?? 'Sem nome',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _selectBroker,
        ),
      ),
    );
  }

  Widget _insight(BuildContext context, BrokerDashboardSummary s) {
    final i = meuFinanceiroInsight(
      s,
      proximos: _proximos?.data ?? const [],
      hidden: _hidden,
    );
    final tone = switch (i.tone) {
      'amber' => FinanceTones.amber,
      'rose' => FinanceTones.rose,
      'sky' => FinanceTones.sky,
      'emerald' => FinanceTones.emerald,
      _ => FinanceTones.slate,
    };
    final icon = switch (i.tone) {
      'amber' => LucideIcons.signature,
      'rose' => LucideIcons.triangleAlert,
      'emerald' => LucideIcons.circleCheck,
      _ => LucideIcons.info,
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tone.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: tone),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  i.title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: tone,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  i.text,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpis(BuildContext context, BrokerDashboardSummary s) {
    final t = s.totals;
    final adiant = s.adiantamentoAprovado;
    final liquido = adiant == null || adiant.valor <= 0
        ? null
        : 'líquido de adiantamento ${formatBrl(t.aReceber - adiant.valor, hidden: _hidden)}';
    final travado = s.aguardandoAssinatura.count > 0
        ? '+ ${formatBrl(t.travado ?? s.aguardandoAssinatura.valor, hidden: _hidden)} travado · sem assinatura'
        : null;
    final mesAtual = _mesAtual(s.mensal);
    String esteMes(double? v) => v == null || v == 0
        ? ''
        : ' · este mês ${formatBrl(v, hidden: _hidden)}';

    return Column(
      children: [
        FinanceHeroCard(
          label: 'A receber',
          value: t.aReceber,
          hidden: _hidden,
          liquido:
              liquido ??
              (t.travado != null
                  ? 'comissões por vir · só fichas assinadas'
                  : null),
          tag: travado,
          selected: _visao == FinanceVisao.aReceber,
          onTap: () => _selectVisao(
            FinanceVisao.aReceber,
            situacao: VendaSituacao.aReceber,
          ),
        ),
        const SizedBox(height: 12),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // Altura fixa (não proporção): em celular estreito a proporção
          // espremia o cartão e o texto de apoio estourava.
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent:
                150 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4),
          ),
          children: [
            FinanceKpiTile(
              label: 'Recebido',
              value: formatBrl(t.recebido, hidden: _hidden),
              hint: 'já pago a você${esteMes(mesAtual?.recebido)}',
              icon: LucideIcons.circleCheck,
              tone: FinanceTones.emerald,
              selected: _visao == FinanceVisao.recebido,
              onTap: () => _selectVisao(
                FinanceVisao.recebido,
                situacao: VendaSituacao.quitadas,
              ),
            ),
            FinanceKpiTile(
              label: 'Retido',
              value: formatBrl(t.retido, hidden: _hidden),
              hint: 'abatido de adiantamentos${esteMes(mesAtual?.retido)}',
              icon: LucideIcons.hourglass,
              tone: FinanceTones.amber,
              selected: _visao == FinanceVisao.retido,
              onTap: () => _selectVisao(
                FinanceVisao.retido,
                situacao: VendaSituacao.retencao,
              ),
            ),
            FinanceKpiTile(
              label: 'Adiantamentos aprovados',
              value: adiant == null
                  ? '–'
                  : formatBrl(adiant.valor, hidden: _hidden),
              hint: adiant == null
                  ? 'a descontar dos próximos repasses'
                  : '${adiant.count} ${adiant.count == 1 ? 'adiantamento' : 'adiantamentos'} · a descontar',
              icon: LucideIcons.handCoins,
              tone: FinanceTones.violet,
              selected: _visao == FinanceVisao.adiantamentoAprovado,
              onTap: () => _selectVisao(FinanceVisao.adiantamentoAprovado),
            ),
            FinanceKpiTile(
              label: 'Saldo devedor',
              value: formatBrl(t.saldoDevedor, hidden: _hidden),
              hint: 'dívida com a imobiliária',
              icon: LucideIcons.landmark,
              tone: FinanceTones.rose,
              selected: _visao == FinanceVisao.saldoDevedor,
              onTap: () => _selectVisao(FinanceVisao.saldoDevedor),
            ),
          ],
        ),
      ],
    );
  }

  static MonthlyEarning? _mesAtual(List<MonthlyEarning> mensal) {
    final now = DateTime.now();
    final key = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    for (final m in mensal) {
      if (m.month == key) return m;
    }
    return null;
  }

  Widget _searchField(BuildContext context) {
    return TextField(
      controller: _searchCtrl,
      onChanged: _onSearchChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Buscar venda, imóvel ou corretor…',
        prefixIcon: const Icon(LucideIcons.search, size: 18),
        suffixIcon: _searchCtrl.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(LucideIcons.x, size: 18),
                onPressed: () {
                  _searchCtrl.clear();
                  _onSearchChanged('');
                  setState(() {});
                },
              ),
        filled: true,
        fillColor: ThemeHelpers.cardBackgroundColor(context),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
    );
  }

  Widget _visaoSection(BuildContext context) {
    final page = _proximos;
    final filtered = _temRecorte || _status != null || _searchParam != null;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final custom = _customRange;
    final comOrigem = _visao == FinanceVisao.aReceber ||
        _visao == FinanceVisao.recebido ||
        _visao == FinanceVisao.retido;
    return FinanceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FinanceSectionHeader(
            title: _visao.title,
            icon: LucideIcons.calendarClock,
            subtitle: page == null
                ? null
                : '${page.total} no total${_mesSel == null ? '' : ' em ${_mesLabel(_mesSel!)}'}',
            trailing: _loadingProx
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final p in FinancePeriodo.values)
                  FinanceFilterChip(
                    label: p.label,
                    selected:
                        _periodo == p && custom == null && _mesSel == null,
                    onTap: () => _setPeriodo(p),
                  ),
                FinanceFilterChip(
                  label: custom == null
                      ? 'Personalizar'
                      : '${_dm(custom.start)} – ${_dm(custom.end, ano: true)}',
                  selected: custom != null,
                  onTap: _pickCustomRange,
                ),
              ],
            ),
          ),
          if (_visao == FinanceVisao.aReceber) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      'Status',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: secondary,
                      ),
                    ),
                  ),
                  for (final s in kProximosStatusRail)
                    FinanceFilterChip(
                      label: s.$2,
                      selected: _status == s.$1,
                      onTap: () => _toggleStatus(s.$1),
                    ),
                ],
              ),
            ),
          ],
          if (_mesSel != null || custom != null || _status != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _limparRecorte,
                icon: const Icon(LucideIcons.x, size: 14),
                label: Text(
                  [
                    if (_mesSel != null)
                      'Mês: ${_mesLabel(_mesSel!)}${_ehMesAtual(_mesSel!) ? ' · inclui atrasados' : ''}',
                    if (custom != null)
                      '${_visao.dateLabel}: ${_dm(custom.start)} – ${_dm(custom.end, ano: true)}',
                    if (_status != null) 'Status: ${proximoStatusLabel(_status!)}',
                    'limpar recorte',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          const SizedBox(height: 6),
          if (_proximosError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FinanceInlineNotice(
                text: _proximosError!.message,
                onRetry: _reloadProximos,
              ),
            )
          else if (page == null || page.data.isEmpty)
            FinanceEmpty(text: filtered ? _visao.emptyFiltered : _visao.empty)
          else ...[
            for (final p in page.data)
              FinanceRow(
                title: p.title,
                subtitle: p.subtitle,
                meta:
                    '${_visao.dateLabel} ${formatFinanceDate(p.previstoPara)}',
                value: formatBrl(p.valor, hidden: _hidden),
                // Tocar abre a consulta da venda (sem venda = título avulso).
                onTap: p.saleId == null ? null : () => _openVenda(p.saleId!),
                pill: FinancePill(
                  label: proximoStatusLabel(p.status, emAtraso: p.emAtraso),
                  color: FinanceTones.proximoStatus(
                    p.status,
                    emAtraso: p.emAtraso,
                  ),
                ),
                action: comOrigem && p.repasseId.isNotEmpty
                    ? IconButton(
                        tooltip: 'De onde vem este repasse',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _openOrigem(p.repasseId),
                        icon: Icon(
                          LucideIcons.info,
                          size: 17,
                          color: secondary,
                        ),
                      )
                    : null,
              ),
            if (page.hasMore)
              _moreButton(_loadingMoreProx, () => _reloadProximos(more: true)),
          ],
        ],
      ),
    );
  }

  Widget _moreButton(bool loading, VoidCallback onTap) {
    return Center(
      child: TextButton.icon(
        onPressed: loading ? null : onTap,
        icon: loading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(LucideIcons.chevronDown, size: 16),
        label: const Text('Ver mais'),
      ),
    );
  }

  Widget _requestsSection(
    BuildContext context,
    FinancePage<RequestSummary>? page,
  ) {
    final rows = page?.data ?? const <RequestSummary>[];
    return FinanceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FinanceSectionHeader(
            title: 'Minhas solicitações',
            icon: LucideIcons.fileText,
            subtitle: rows.isEmpty
                ? 'Nada pedido ainda. Pagamento, reembolso ou adiantamento: tudo começa por aqui.'
                : '${page!.total} ${page.total == 1 ? 'pedido que envolve' : 'pedidos que envolvem'} você',
            trailing: rows.isEmpty
                ? null
                : TextButton(
                    onPressed: () => _go(FinanceRouteNames.solicitacoes),
                    child: const Text('Ver todas'),
                  ),
          ),
          if (rows.isEmpty)
            const FinanceEmpty(text: 'Nenhuma solicitação.')
          else
            for (final r in rows)
              FinanceRow(
                onTap: () => _go(FinanceRouteNames.solicitacao(r.id)),
                title: r.code ?? r.title,
                subtitle: r.code == null ? null : r.title,
                meta: formatFinanceDateTime(r.createdAt),
                value: formatBrl(
                  r.amountApproved ?? r.amountRequested,
                  hidden: _hidden,
                ),
                pill: FinancePill(
                  label: requestStatusLabel(r.status),
                  color: FinanceTones.requestStatus(r.status),
                ),
              ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _go(FinanceRouteNames.novaSolicitacao),
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('Nova solicitação'),
            ),
          ),
        ],
      ),
    );
  }

  static String _dm(DateTime d, {bool ano = false}) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}'
      '${ano ? '/${(d.year % 100).toString().padLeft(2, '0')}' : ''}';

  static bool _ehMesAtual(String ym) {
    final n = DateTime.now();
    return ym == '${n.year}-${n.month.toString().padLeft(2, '0')}';
  }

  static String _mesLabel(String ym) {
    const m = [
      'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
      'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez',
    ];
    final d = DateTime.tryParse('$ym-01');
    if (d == null) return ym;
    return '${m[d.month - 1]}/${(d.year % 100).toString().padLeft(2, '0')}';
  }

  Widget _paraAprovarCard(BuildContext context) {
    final n = _meuAval;
    return FinanceCard(
      onTap: () => _go(FinanceRouteNames.aprovacoes),
      padding: const EdgeInsets.all(14),
      borderColor: (n ?? 0) > 0
          ? FinanceTones.amber.withValues(alpha: 0.6)
          : null,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: FinanceTones.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              LucideIcons.stamp,
              size: 18,
              color: FinanceTones.amber,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Para aprovar',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                Text(
                  n == null
                      ? 'Pedidos aguardando o seu aval'
                      : n == 0
                      ? 'Nada aguardando o seu aval'
                      : '$n ${n == 1 ? 'item aguarda' : 'itens aguardam'} o seu aval',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
              ],
            ),
          ),
          if ((n ?? 0) > 0)
            Badge(
              label: Text('$n'),
              backgroundColor: FinanceTones.amber,
            ),
          const SizedBox(width: 6),
          const Icon(LucideIcons.chevronRight, size: 18),
        ],
      ),
    );
  }

  Widget _assinaturasSection(
    BuildContext context,
    BrokerDashboardSummary s,
    FinancePage<AssinaturaFicha> page,
  ) {
    final multi = s.brokers.length > 1;
    return FinanceCard(
      borderColor: FinanceTones.amber.withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FinanceSectionHeader(
            title: 'Fichas aguardando sua assinatura',
            icon: LucideIcons.signature,
            subtitle:
                '${page.total} ${page.total == 1 ? 'ficha' : 'fichas'} · '
                '${formatBrl(s.aguardandoAssinatura.valor, hidden: _hidden)} em comissão travada',
          ),
          Text(
            'Esse valor ainda não conta no seu "A receber". Assinou, ele entra '
            'na conta sozinho. Toque na ficha para ver a venda.',
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
          for (final f in page.data)
            FinanceRow(
              onTap: () => _openVenda(f.saleId),
              title: f.title,
              subtitle: [
                if (f.subtitle.isNotEmpty) f.subtitle,
                if (multi && f.brokerName != null) f.brokerName!,
              ].join(' · '),
              meta:
                  '${f.parcelas} ${f.parcelas == 1 ? 'parcela travada' : 'parcelas travadas'}',
              value: formatBrl(f.valor, hidden: _hidden),
              pill: const FinancePill(
                label: 'Aguardando assinatura',
                color: FinanceTones.amber,
              ),
            ),
          if (page.hasMore)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${page.total} fichas neste recorte — as 5 de maior valor acima.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _advancesSection(
    BuildContext context,
    Section<FinancePage<CommissionAdvance>> sec,
  ) {
    final err = sec.error;
    // Um 403 de papel bloqueia só esta seção; COMPANY_* e outros erros a
    // escondem (o resto da tela segue).
    if (err != null) {
      if (err.kind != FinanceErrorKind.forbidden) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: FinanceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FinanceSectionHeader(
                title: 'Adiantamentos de comissão',
                icon: LucideIcons.handCoins,
              ),
              FinanceInlineNotice(
                text: err.message,
                color: FinanceTones.violet,
                icon: LucideIcons.lock,
              ),
            ],
          ),
        ),
      );
    }
    final page = sec.data;
    final rows = page?.data ?? const <CommissionAdvance>[];
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: FinanceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FinanceSectionHeader(
              title: 'Adiantamentos de comissão',
              icon: LucideIcons.handCoins,
              subtitle: (page?.total ?? 0) == 0
                  ? 'Precisa de parte da comissão antes? Peça um adiantamento.'
                  : '${page!.total} no total',
            ),
            if (rows.isEmpty)
              const FinanceEmpty(text: 'Nenhum adiantamento pedido.'),
            for (final a in rows)
              FinanceRow(
                title: a.code.isEmpty ? 'Adiantamento' : a.code,
                subtitle: [
                  if (a.saleLabel != null) a.saleLabel!,
                  'Recebido ${formatBrl(a.value, hidden: _hidden)}',
                  if (a.feeValue > 0)
                    'taxa ${formatBrl(a.feeValue, hidden: _hidden)} (${a.feePercent.toStringAsFixed(a.feePercent.truncateToDouble() == a.feePercent ? 0 : 2).replaceAll('.', ',')}%)',
                ].join(' · '),
                meta: a.saldoRestante == null
                    ? null
                    : 'Saldo restante ${formatBrl(a.saldoRestante!, hidden: _hidden)}',
                value: formatBrl(a.chargedValue, hidden: _hidden),
                pill: FinancePill(
                  label: advanceStatusLabel(a.status),
                  color: FinanceTones.advanceStatus(a.status),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _go(FinanceRouteNames.pedirAdiantamento),
                icon: const Icon(LucideIcons.handCoins, size: 16),
                label: const Text('Solicitar adiantamento'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vendasSection(BuildContext context, BrokerDashboardSummary? summary) {
    final page = _vendas;
    final temTravado = (summary?.totals.travado ?? 0) > 0;
    final filtered = _situacao != VendaSituacao.todas || _searchParam != null;
    return FinanceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FinanceSectionHeader(
            title: 'Minhas vendas',
            icon: LucideIcons.receipt,
            subtitle: page == null ? null : '${page.total} com comissão',
            trailing: _loadingVend
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final s in VendaSituacao.values)
                  if (s != VendaSituacao.semAssinatura || temTravado)
                    FinanceFilterChip(
                      label: s.label,
                      selected: _situacao == s,
                      onTap: () {
                        if (_situacao == s) return;
                        setState(() => _situacao = s);
                        unawaited(_reloadVendas());
                      },
                    ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (_vendasError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FinanceInlineNotice(
                text: _vendasError!.message,
                onRetry: _reloadVendas,
              ),
            )
          else if (page == null || page.data.isEmpty)
            FinanceEmpty(
              text: filtered
                  ? 'Nenhuma venda no filtro aplicado.'
                  : 'Nenhuma venda com comissão registrada.',
            )
          else ...[
            for (final v in page.data) _vendaTile(context, v, summary),
            if (page.hasMore)
              _moreButton(_loadingMoreVend, () => _reloadVendas(more: true)),
          ],
        ],
      ),
    );
  }

  Widget _vendaTile(
    BuildContext context,
    BrokerVenda v,
    BrokerDashboardSummary? summary,
  ) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final multi = (summary?.brokers.length ?? 0) > 1;
    final sub = [
      if (v.fichaVenda != null && (v.propertyName != null || v.unit != null))
        'Ficha ${v.fichaVenda}',
      if (v.clientName != null) v.clientName!,
      if (multi && v.brokerName != null) v.brokerName!,
    ].join(' · ');
    Widget cell(String label, double value, Color? tone) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: secondary)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatBrl(value, hidden: _hidden),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: tone ?? ThemeHelpers.textColor(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: v.saleId.isEmpty ? null : () => _openVenda(v.saleId),
      child: Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ThemeHelpers.borderLightColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            v.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: secondary),
            ),
          ],
          if (v.papeisLabel.isNotEmpty || v.parcelas > 0) ...[
            const SizedBox(height: 4),
            Text(
              [
                if (v.papeisLabel.isNotEmpty) v.papeisLabel,
                if (v.parcelas > 0)
                  '${v.parcelas} ${v.parcelas == 1 ? 'parcela' : 'parcelas'}',
              ].join(' · '),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: secondary,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              cell('Devido', v.totals.devido, null),
              cell('Recebido', v.totals.recebido, FinanceTones.emerald),
              cell('Retido', v.totals.retido, FinanceTones.amber),
              cell('A receber', v.totals.aReceber, FinanceTones.sky),
            ],
          ),
          if ((v.totals.travado ?? 0) > 0) ...[
            const SizedBox(height: 6),
            Text(
              '+ ${formatBrl(v.totals.travado!, hidden: _hidden)} travado · sem assinatura',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: FinanceTones.amber,
              ),
            ),
          ],
        ],
      ),
    ),
    );
  }
}

/// Empresa sem Financeiro / sem acesso (`EmpresaIndisponivelState.tsx:33`).
class _CompanyUnavailable extends StatelessWidget {
  final FinanceError error;
  final Future<void> Function({bool silent}) onRetry;

  const _CompanyUnavailable({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final semModulo = error.kind == FinanceErrorKind.companyNotProvisioned;
    final title = semModulo
        ? 'Esta empresa ainda não tem o módulo financeiro habilitado'
        : 'Você não tem acesso ao financeiro desta empresa';
    final body = semModulo
        ? 'A empresa existe no CRM, mas ainda não foi provisionada no '
              'financeiro. Fale com o suporte para habilitar o módulo nesta empresa.'
        : 'A empresa tem movimentação, mas o seu usuário não está vinculado a '
              'ela — os números não aparecem por falta de acesso, não porque '
              'estejam zerados. Peça a um administrador para vincular seu '
              'usuário, ou troque de empresa no seu perfil.';
    final accent = financeAccent(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              semModulo ? LucideIcons.landmark : LucideIcons.lock,
              color: accent,
              size: 32,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: ThemeHelpers.textColor(context),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          body,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.45,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
        ),
        const SizedBox(height: 22),
        Center(
          child: OutlinedButton.icon(
            onPressed: () => onRetry(),
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Verificar de novo'),
          ),
        ),
      ],
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final base = ThemeHelpers.borderLightColor(context).withValues(alpha: 0.6);
    Widget box(double h, {double r = 18}) => Container(
      height: h,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(r),
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        box(18, r: 6),
        box(28, r: 8),
        const SizedBox(height: 6),
        box(70),
        box(150, r: 24),
        Row(
          children: [
            Expanded(child: box(120)),
            const SizedBox(width: 12),
            Expanded(child: box(120)),
          ],
        ),
        box(220),
      ],
    );
  }
}
