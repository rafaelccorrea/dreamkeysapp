import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../core/finance_errors.dart';
import '../../core/finance_format.dart';
import '../../core/finance_route_names.dart';
import '../../meu_financeiro/models/meu_financeiro_models.dart';
import '../../meu_financeiro/pages/meu_financeiro_page.dart' show FinancePeriodo;
import '../../meu_financeiro/services/meu_financeiro_service.dart';
import '../../meu_financeiro/widgets/meu_financeiro_widgets.dart';
import '../../notificacoes/widgets/finance_bell_button.dart';
import '../models/request_models.dart';
import '../services/requests_service.dart';

/// Minhas solicitações (`/financeiro/solicitacoes`) — visão pessoal: lista
/// + resumo EM PARALELO, filtros de status, período e busca.
class SolicitacoesPage extends StatefulWidget {
  final RequestsService? service;
  const SolicitacoesPage({super.key, this.service});

  @override
  State<SolicitacoesPage> createState() => _SolicitacoesPageState();
}

class _SolicitacoesPageState extends State<SolicitacoesPage> {
  RequestsService get _svc => widget.service ?? RequestsService.instance;

  FinancePage<FinanceRequest>? _page;
  RequestsDashboard? _dash;
  FinanceError? _error;
  FinanceError? _dashError;
  bool _loading = true;
  bool _loadingMore = false;
  int _seq = 0;

  String? _status;
  FinancePeriodo? _periodo;
  DateTimeRange? _custom;
  String _search = '';
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  RequestsQuery _query({int page = 1}) {
    String? from;
    String? to;
    if (_custom != null) {
      from = financeQueryDate(_custom!.start);
      to = financeQueryDate(_custom!.end);
    } else if (_periodo != null) {
      (from, to) = _periodo!.range(DateTime.now());
    }
    return RequestsQuery(
      page: page,
      search: _search.trim().isEmpty ? null : _search.trim(),
      status: _status,
      from: from,
      to: to,
    );
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() => _loading = _page == null);
    final q = _query();
    final results = await Future.wait<Object>([
      _svc.list(q),
      _svc.dashboard(q),
    ]);
    if (!mounted || seq != _seq) return;
    final list = results[0] as Section<FinancePage<FinanceRequest>>;
    final dash = results[1] as Section<RequestsDashboard>;
    setState(() {
      _loading = false;
      _page = list.data;
      _error = list.error;
      _dash = dash.data ?? _dash;
      _dashError = dash.error;
    });
  }

  Future<void> _more() async {
    final cur = _page;
    if (cur == null || _loadingMore) return;
    final seq = _seq;
    setState(() => _loadingMore = true);
    final res = await _svc.list(_query(page: cur.page + 1));
    if (!mounted || seq != _seq) return;
    setState(() {
      _loadingMore = false;
      if (res.ok && res.data != null) _page = cur.append(res.data!);
    });
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted || v == _search) return;
      _search = v;
      _load();
    });
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _custom,
      locale: const Locale('pt', 'BR'),
      helpText: 'Período de criação',
    );
    if (r == null) return;
    setState(() {
      _custom = r;
      _periodo = null;
    });
    _load();
  }

  Future<void> _openNova() async {
    final created = await Navigator.of(
      context,
    ).pushNamed(FinanceRouteNames.novaSolicitacao);
    if (created != null && mounted) _load();
  }

  Future<void> _open(FinanceRequest r) async {
    await Navigator.of(context).pushNamed(FinanceRouteNames.solicitacao(r.id));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Solicitações',
      showDrawer: false,
      showBottomNavigation: false,
      actions: const [FinanceBellButton()],
      body: Stack(
        children: [
          RefreshIndicator(onRefresh: _load, child: _body(context)),
          Positioned(
            right: 16,
            bottom: 24,
            child: FloatingActionButton.extended(
              heroTag: 'fin-nova-solicitacao',
              backgroundColor: financeAccent(context),
              foregroundColor: Colors.white,
              onPressed: _openNova,
              icon: const Icon(LucideIcons.plus, size: 18),
              label: const Text(
                'Nova solicitação',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
      children: [
        Text(
          'Pagamento, reembolso ou adiantamento: tudo o que você pediu ao '
          'financeiro, com a etapa em que cada pedido está.',
          style: TextStyle(fontSize: 13, height: 1.35, color: secondary),
        ),
        const SizedBox(height: 14),
        _resumo(context),
        const SizedBox(height: 14),
        TextField(
          controller: _searchCtrl,
          onChanged: _onSearch,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Buscar por título, código ou valor…',
            prefixIcon: const Icon(LucideIcons.search, size: 18),
            filled: true,
            fillColor: ThemeHelpers.cardBackgroundColor(context),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: ThemeHelpers.borderLightColor(context),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: ThemeHelpers.borderLightColor(context),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              FinanceFilterChip(
                label: 'Qualquer data',
                selected: _periodo == null && _custom == null,
                onTap: () {
                  if (_periodo == null && _custom == null) return;
                  setState(() {
                    _periodo = null;
                    _custom = null;
                  });
                  _load();
                },
              ),
              for (final p in FinancePeriodo.values.where(
                (p) => p != FinancePeriodo.tudo,
              ))
                FinanceFilterChip(
                  label: p.label,
                  selected: _periodo == p,
                  onTap: () {
                    setState(() {
                      _periodo = _periodo == p ? null : p;
                      _custom = null;
                    });
                    _load();
                  },
                ),
              FinanceFilterChip(
                label: _custom == null
                    ? 'Personalizar'
                    : '${formatFinanceDateTime(_custom!.start.toIso8601String(), pattern: 'dd/MM')} – '
                          '${formatFinanceDateTime(_custom!.end.toIso8601String(), pattern: 'dd/MM/yy')}',
                selected: _custom != null,
                onTap: _pickCustom,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
          )
        else if (_error != null)
          FinanceInlineNotice(text: _error!.message, onRetry: _load)
        else if (_page == null || _page!.data.isEmpty)
          FinanceCard(
            child: FinanceEmpty(
              text: _status != null || _search.isNotEmpty || _periodo != null ||
                      _custom != null
                  ? 'Nenhuma solicitação no filtro aplicado.'
                  : 'Nada pedido ainda. Toque em "Nova solicitação" para começar.',
            ),
          )
        else
          FinanceCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(
              children: [
                for (final r in _page!.data) _row(context, r),
                if (_page!.hasMore)
                  TextButton.icon(
                    onPressed: _loadingMore ? null : _more,
                    icon: _loadingMore
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(LucideIcons.chevronDown, size: 16),
                    label: const Text('Ver mais'),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _row(BuildContext context, FinanceRequest r) {
    final etapa = r.status == 'PENDENTE'
        ? r.approvals.where((a) => a.status == 'PENDENTE').firstOrNull
        : null;
    return FinanceRow(
      onTap: () => _open(r),
      title: r.title.isEmpty ? (r.code ?? 'Solicitação') : r.title,
      subtitle: [
        ?r.code,
        requestTypeLabel(r.type),
        if (r.company != null) r.company!.name,
      ].join(' · '),
      meta: [
        formatFinanceDateTime(r.createdAt, pattern: 'dd/MM/yy'),
        if (etapa != null) 'aguardando ${approvalRoleLabel(etapa.role)}',
      ].join(' · '),
      value: formatBrl(r.amountApproved ?? r.amountRequested),
      pill: FinancePill(
        label: requestStatusLabel(r.status),
        color: FinanceTones.requestStatus(r.status),
      ),
    );
  }

  Widget _resumo(BuildContext context) {
    final d = _dash;
    final statuses = kRequestStatusLabels.keys.toList();
    if (d == null && _dashError != null) {
      return FinanceInlineNotice(
        text: 'Não deu para carregar o resumo: ${_dashError!.message}',
        onRetry: _load,
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _statusTile(context, null, 'Todas', d?.total),
          for (final s in statuses)
            _statusTile(context, s, kRequestStatusLabels[s]!, d?.byStatus[s]),
        ],
      ),
    );
  }

  Widget _statusTile(BuildContext context, String? s, String label, int? n) {
    final selected = _status == s;
    final tone = s == null ? financeAccent(context) : FinanceTones.requestStatus(s);
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Material(
        color: selected
            ? tone.withValues(alpha: 0.12)
            : ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            setState(() => _status = selected ? null : s);
            _load();
          },
          child: Container(
            width: 112,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? tone.withValues(alpha: 0.6)
                    : ThemeHelpers.borderLightColor(context),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  n == null ? '–' : '$n',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: tone,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ThemeHelpers.textSecondaryColor(context),
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
