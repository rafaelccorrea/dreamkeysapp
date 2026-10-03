import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../core/finance_access.dart';
import '../core/finance_errors.dart';
import '../core/finance_format.dart';
import '../core/finance_me.dart';
import '../core/finance_route_names.dart';
import '../core/finance_visibility.dart';
import '../core/widgets/finance_form_widgets.dart';
import '../meu_financeiro/models/meu_financeiro_models.dart';
import '../meu_financeiro/services/meu_financeiro_service.dart';
import '../meu_financeiro/widgets/finance_sheet.dart';
import '../meu_financeiro/widgets/meu_financeiro_widgets.dart';
import '../notificacoes/widgets/finance_bell_button.dart';
import '../solicitacoes/models/request_models.dart';
import 'approvals_models.dart';
import 'approvals_service.dart';

/// "Para aprovar" — fila "Meu aval" da Central de Aprovações
/// (`/financeiro/aprovacoes`). Gestor/diretor/financeiro.
class ParaAprovarPage extends StatefulWidget {
  final ApprovalsService? service;
  const ParaAprovarPage({super.key, this.service});

  @override
  State<ParaAprovarPage> createState() => _ParaAprovarPageState();
}

class _ParaAprovarPageState extends State<ParaAprovarPage> {
  ApprovalsService get _svc => widget.service ?? ApprovalsService.instance;

  bool _loading = true;
  bool _busy = false;
  FinanceMe? _me;
  bool _meLoaded = false;
  FinancePage<ApprovalItem>? _page;
  FinanceError? _error;
  int? _count;
  final Set<String> _sel = {};
  final Map<String, String> _falhas = {};
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _search = '';
  int _seq = 0;

  bool get _cracha {
    final mas = ModuleAccessService.instance;
    return financeCrachaOk(
      crmRole: mas.userRole,
      hasFinancialAccess: mas.hasPermission('financial:access'),
    );
  }

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

  Future<void> _load() async {
    final seq = ++_seq;
    if (!_cracha) {
      setState(() => _loading = false);
      return;
    }
    final r = await Future.wait<Object>([
      FinanceMeService.instance.load(),
      _svc.meuAvalCount(),
      _svc.queue(search: _search),
    ]);
    if (!mounted || seq != _seq) return;
    final me = r[0] as ApiResponse<FinanceMe?>;
    final count = r[1] as Section<int>;
    final q = r[2] as Section<FinancePage<ApprovalItem>>;
    setState(() {
      _loading = false;
      _meLoaded = me.success;
      if (me.success) _me = me.data;
      _count = count.data ?? _count;
      _page = q.data;
      _error = q.error;
      _sel.removeWhere((k) => !(q.data?.data.any((i) => i.key == k) ?? false));
    });
  }

  Future<void> _more() async {
    final cur = _page;
    if (cur == null) return;
    final res = await _svc.queue(page: cur.page + 1, search: _search);
    if (!mounted || res.data == null) return;
    setState(() => _page = cur.append(res.data!));
  }

  bool get _podeDecidir => canDecideApprovals(_me);

  // ─── Decisões ───────────────────────────────────────────────────────────

  Future<void> _decidir(List<ApprovalItem> items, {required bool aprovar}) async {
    if (items.isEmpty || _busy) return;
    String? reason;
    var lote = items;
    if (aprovar) {
      final sep = separarParaAprovar(items);
      if (sep.adiantamentos.isNotEmpty && items.length > 1) {
        financeSnack(
          context,
          '${sep.adiantamentos.length} adiantamento(s) ficaram fora do lote: '
          'adiantamento é aprovado um a um, com a taxa.',
        );
      }
      if (items.length == 1 && items.first.source == 'ADVANCE') {
        await _aprovarAdiantamento(items.first);
        return;
      }
      lote = sep.lote;
      if (lote.isEmpty) return;
      final ok = await _confirm(
        'Aprovar ${lote.length == 1 ? 'este item' : '${lote.length} itens'}?',
        'Total ${formatBrl(lote.fold(0.0, (s, i) => s + i.amount))}',
        'Aprovar',
      );
      if (ok != true) return;
    } else {
      reason = await _pedirMotivo(lote.length);
      if (reason == null) return;
    }
    await _enviarLote(lote, aprovar: aprovar, reason: reason);
  }

  Future<void> _enviarLote(
    List<ApprovalItem> lote, {
    required bool aprovar,
    String? reason,
    Set<String> confirmados = const {},
  }) async {
    setState(() => _busy = true);
    final res = await _svc.bulk(
      approve: aprovar,
      reason: reason,
      items: [
        for (final i in lote)
          (
            source: i.source,
            id: i.id,
            confirmarDuplicidade: confirmados.contains(i.key),
          ),
      ],
    );
    if (!mounted) return;
    setState(() => _busy = false);
    // Lançamento em dobro: pergunta UMA vez por item retido.
    final duplicados = res.failed.where((f) => f.duplicidade).toList();
    final reenviar = <ApprovalItem>[];
    for (final f in duplicados) {
      final item = lote.where((i) => i.source == f.source && i.id == f.id).firstOrNull;
      if (item == null) continue;
      final ok = await _confirm(
        'Possível lançamento em dobro',
        '${item.code ?? item.title}: ${f.error}'
            '${f.suspeitos.isEmpty ? '' : '\nParecidos: ${f.suspeitos.join(', ')}'}',
        'Aprovar mesmo assim',
      );
      if (ok == true) {
        reenviar.add(item);
      } else {
        _falhas[item.key] =
            'Não aprovado: você conferiu o aviso de lançamento em dobro e '
            'escolheu não aprovar.';
      }
    }
    setState(() {
      for (final f in res.failed.where((f) => !f.duplicidade)) {
        _falhas['${f.source}:${f.id}'] = f.error;
      }
      _sel.clear();
    });
    if (reenviar.isNotEmpty && mounted) {
      await _enviarLote(
        reenviar,
        aprovar: true,
        confirmados: reenviar.map((i) => i.key).toSet(),
      );
      return;
    }
    if (!mounted) return;
    financeSnack(
      context,
      resumoDoLote(
        ok: res.succeeded.length,
        falhas: res.failed.where((f) => !f.duplicidade).length,
        aprovar: aprovar,
      ),
      error: res.succeeded.isEmpty && res.failed.isNotEmpty,
    );
    _load();
  }

  Future<bool?> _confirm(String title, String body, String action) =>
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(action),
            ),
          ],
        ),
      );

  Future<String?> _pedirMotivo(int n) async {
    final ctrl = TextEditingController();
    String? erro;
    final out = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(n == 1 ? 'Recusar item' : 'Recusar $n itens'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 4,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: 'Motivo da recusa',
              helperText: 'Mínimo de 5 caracteres. Quem pediu vai ler.',
              errorText: erro,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Voltar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: FinanceTones.rose),
              onPressed: () {
                final e = validarMotivoRecusa(ctrl.text);
                if (e != null) {
                  setD(() => erro = e);
                  return;
                }
                Navigator.pop(ctx, ctrl.text.trim());
              },
              child: const Text('Recusar'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    return out;
  }

  /// Adiantamento: taxa definida por quem aprova (`ModalAprovarAdiantamento`).
  Future<void> _aprovarAdiantamento(ApprovalItem item) async {
    if (!canApproveAdvance(_me)) {
      financeSnack(
        context,
        'Seu papel não aprova adiantamentos (falta "commission-advances:approve").',
        error: true,
      );
      return;
    }
    setState(() => _busy = true);
    final data = await _svc.advanceForApproval(item.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (data.advance == null) {
      financeSnack(context, data.error?.message ?? 'Adiantamento não encontrado.', error: true);
      return;
    }
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _AprovarAdiantamentoSheet(
        advance: data.advance!,
        balance: data.balance,
        onApprove: (fee, motivo) =>
            _svc.approveAdvance(item.id, feePercent: fee, capOverrideReason: motivo),
      ),
    );
    if (ok == true && mounted) {
      financeSnack(context, 'Adiantamento ${item.code ?? ''} aprovado.');
      _load();
    }
  }

  Future<void> _abrir(ApprovalItem item) async {
    await showFinanceSheet<void>(
      context,
      title: approvalSourceLabel(item.source),
      builder: (ctx, scroll) => FinanceAsyncBody<ApprovalItemDetail>(
        scroll: scroll,
        load: () => _svc.item(item.source, item.id),
        builder: (ctx, d) => _ItemDetail(
          item: item,
          detail: d,
          scroll: scroll,
          podeDecidir: _podeDecidir && item.canActByMe,
          onAprovar: () {
            Navigator.pop(ctx);
            _decidir([item], aprovar: true);
          },
          onRecusar: () {
            Navigator.pop(ctx);
            _decidir([item], aprovar: false);
          },
          onAbrirSolicitacao: item.source == 'REQUEST'
              ? () {
                  Navigator.pop(ctx);
                  Navigator.of(context).pushNamed(FinanceRouteNames.solicitacao(item.id));
                }
              : null,
        ),
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final selecionados = _page?.data.where((i) => _sel.contains(i.key)).toList() ?? [];
    return AppScaffold(
      title: 'Para aprovar',
      showDrawer: false,
      showBottomNavigation: false,
      actions: const [FinanceBellButton()],
      body: Column(
        children: [
          Expanded(child: _body(context)),
          if (selecionados.isNotEmpty) _barra(context, selecionados),
        ],
      ),
    );
  }

  Widget _locked(BuildContext context, String motivo) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        Icon(LucideIcons.lock, size: 40, color: financeAccent(context)),
        const SizedBox(height: 16),
        Text(
          'Você não aprova pelo Financeiro',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: ThemeHelpers.textColor(context),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          motivo,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.45,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pushReplacementNamed(
              FinanceRouteNames.meuDashboard,
            ),
            child: const Text('Ir para o Meu Financeiro'),
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    if (!_cracha) {
      return _locked(
        context,
        'A Central de Aprovações exige o acesso de gestão do Financeiro '
        '("financial:access") no CRM. Peça a quem administra os acessos.',
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (_meLoaded && !isFinanceTelaPermitida(_me, FinanceTela.aprovacoes)) {
      final papel = _me?.role ?? '';
      return _locked(
        context,
        'Seu papel no Financeiro (${papel.isEmpty ? 'sem papel' : financeRoleLabel(papel)}) '
        'não tem a tela de Aprovações. Quem aprova: Gestor, Diretor, '
        'Gerente financeiro, Diretor financeiro e Administrador.',
      );
    }
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final page = _page;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          FinanceCard(
            child: Row(
              children: [
                Text(
                  _count == null ? '–' : '$_count',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: financeAccent(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'aguardando o seu aval. Toque para ver e decidir; segure '
                    'para selecionar vários.',
                    style: TextStyle(fontSize: 13, height: 1.35, color: secondary),
                  ),
                ),
              ],
            ),
          ),
          if (!_podeDecidir) ...[
            const SizedBox(height: 12),
            const FinanceInlineNotice(
              color: FinanceTones.amber,
              icon: LucideIcons.eye,
              text: 'Você vê a fila, mas não decide por aqui.',
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400), () {
                _search = v;
                _load();
              });
            },
            decoration: financeInputDecoration(
              context,
              label: 'Buscar por código, título ou valor',
              prefix: const Icon(LucideIcons.search, size: 18),
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            FinanceInlineNotice(text: _error!.message, onRetry: _load)
          else if (page == null || page.data.isEmpty)
            const FinanceCard(
              child: FinanceEmpty(
                icon: LucideIcons.circleCheck,
                text: 'Nada aguardando o seu aval. Tudo em dia!',
              ),
            )
          else ...[
            for (final i in page.data) _tile(context, i),
            if (page.hasMore)
              Center(
                child: TextButton.icon(
                  onPressed: _more,
                  icon: const Icon(LucideIcons.chevronDown, size: 16),
                  label: const Text('Ver mais'),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, ApprovalItem i) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final selected = _sel.contains(i.key);
    final falha = _falhas[i.key];
    final selecionavel = _podeDecidir && i.canActByMe;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FinanceCard(
        borderColor: selected ? financeAccent(context) : null,
        onTap: () {
          if (_sel.isNotEmpty && selecionavel) {
            setState(() => selected ? _sel.remove(i.key) : _sel.add(i.key));
          } else {
            _abrir(i);
          }
        },
        padding: const EdgeInsets.all(14),
        child: GestureDetector(
          onLongPress: selecionavel
              ? () => setState(() => selected ? _sel.remove(i.key) : _sel.add(i.key))
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (_sel.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        selected ? LucideIcons.squareCheck : LucideIcons.square,
                        size: 18,
                        color: selecionavel
                            ? financeAccent(context)
                            : secondary.withValues(alpha: 0.4),
                      ),
                    ),
                  FinancePill(
                    label: approvalSourceLabel(i.source),
                    color: i.source == 'ADVANCE'
                        ? FinanceTones.violet
                        : i.source == 'REQUEST'
                        ? FinanceTones.sky
                        : FinanceTones.slate,
                  ),
                  if (i.priority == 'URGENTE' || i.priority == 'ALTA') ...[
                    const SizedBox(width: 6),
                    FinancePill(
                      label: requestPriorityLabel(i.priority),
                      color: FinanceTones.rose,
                    ),
                  ],
                  const Spacer(),
                  Text(
                    formatBrl(i.amount),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                [?i.code, i.title].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                [
                  ?i.counterparty,
                  ?i.companyName,
                  if (i.dueDate != null) 'vence ${formatFinanceDate(i.dueDate)}',
                  if (i.etapaAtual != null)
                    'etapa ${approvalRoleLabel(i.etapaAtual!.papel)}',
                ].join(' · '),
                style: TextStyle(fontSize: 12, color: secondary),
              ),
              if (i.possivelDuplicata.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Possível duplicata: ${i.possivelDuplicata.join(', ')}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: FinanceTones.amber,
                  ),
                ),
              ],
              if (!i.canActByMe) ...[
                const SizedBox(height: 6),
                Text(
                  i.blockedReason ?? 'Este item não está na sua mão agora.',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: secondary),
                ),
              ],
              if (falha != null) ...[
                const SizedBox(height: 6),
                Text(
                  falha,
                  style: const TextStyle(fontSize: 12, color: FinanceTones.rose),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _barra(BuildContext context, List<ApprovalItem> sel) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          border: Border(
            top: BorderSide(color: ThemeHelpers.borderLightColor(context)),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Limpar seleção',
              onPressed: () => setState(_sel.clear),
              icon: const Icon(LucideIcons.x, size: 18),
            ),
            Text('${sel.length}', style: const TextStyle(fontWeight: FontWeight.w800)),
            const Spacer(),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: FinanceTones.rose),
              onPressed: _busy ? null : () => _decidir(sel, aprovar: false),
              child: const Text('Recusar'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: FinanceTones.emerald),
              onPressed: _busy ? null : () => _decidir(sel, aprovar: true),
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Aprovar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemDetail extends StatelessWidget {
  final ApprovalItem item;
  final ApprovalItemDetail detail;
  final ScrollController scroll;
  final bool podeDecidir;
  final VoidCallback onAprovar;
  final VoidCallback onRecusar;
  final VoidCallback? onAbrirSolicitacao;

  const _ItemDetail({
    required this.item,
    required this.detail,
    required this.scroll,
    required this.podeDecidir,
    required this.onAprovar,
    required this.onRecusar,
    this.onAbrirSolicitacao,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        Text(
          [?item.code, item.title].join(' · '),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: ThemeHelpers.textColor(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          formatBrl(item.amount),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: financeAccent(context),
          ),
        ),
        const FinanceBlockTitle('Dados'),
        for (final c in detail.campos) FinanceField(c.$1, c.$2),
        if (detail.cadeia.isNotEmpty) ...[
          const FinanceBlockTitle('Cadeia'),
          for (final c in detail.cadeia)
            FinanceField(
              '${c.nivel}. ${approvalRoleLabel(c.papel)}',
              [
                approvalStepStatusLabel(c.status),
                ?c.aprovador,
                if (c.decididoEm != null)
                  formatFinanceDateTime(c.decididoEm, pattern: 'dd/MM/yy HH:mm'),
                if (c.comentario != null) '"${c.comentario}"',
              ].join(' · '),
            ),
        ],
        if (detail.anexos.isNotEmpty) ...[
          const FinanceBlockTitle('Anexos'),
          for (final a in detail.anexos)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(LucideIcons.paperclip, size: 15, color: secondary),
                  const SizedBox(width: 6),
                  Expanded(child: Text(a)),
                ],
              ),
            ),
          Text(
            'Para baixar os anexos, abra o item no Financeiro (web).',
            style: TextStyle(fontSize: 11.5, color: secondary),
          ),
        ],
        if (onAbrirSolicitacao != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onAbrirSolicitacao,
              icon: const Icon(LucideIcons.externalLink, size: 16),
              label: const Text('Abrir a solicitação'),
            ),
          ),
        const SizedBox(height: 18),
        if (!item.canActByMe)
          FinanceInlineNotice(
            color: FinanceTones.slate,
            icon: LucideIcons.info,
            text: item.blockedReason ?? 'Este item não está na sua mão agora.',
          )
        else if (podeDecidir)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: FinanceTones.rose,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: onRecusar,
                  icon: const Icon(LucideIcons.x, size: 16),
                  label: const Text('Recusar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: FinanceTones.emerald,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: onAprovar,
                  icon: const Icon(LucideIcons.check, size: 16),
                  label: Text(item.source == 'ADVANCE' ? 'Aprovar com taxa' : 'Aprovar'),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _AprovarAdiantamentoSheet extends StatefulWidget {
  final Map<String, dynamic> advance;
  final Map<String, dynamic>? balance;
  final Future<FinanceError?> Function(double fee, String? motivo) onApprove;

  const _AprovarAdiantamentoSheet({
    required this.advance,
    required this.balance,
    required this.onApprove,
  });

  @override
  State<_AprovarAdiantamentoSheet> createState() => _AprovarAdiantamentoSheetState();
}

class _AprovarAdiantamentoSheetState extends State<_AprovarAdiantamentoSheet> {
  late final TextEditingController _fee;
  final TextEditingController _motivo = TextEditingController();
  bool _saving = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    final f = financeNum(widget.advance['feePercent']);
    _fee = TextEditingController(text: brlInputText(f).replaceAll(',00', ''));
  }

  @override
  void dispose() {
    _fee.dispose();
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = financeNum(widget.advance['value']);
    final fee = (parseBrlInput(_fee.text) ?? 0).clamp(0, 100).toDouble();
    final cobrado = cobradoComTaxa(value, fee);
    final saldo = leSaldo(widget.balance);
    final temSaldo = widget.balance != null;
    final precisa = temSaldo &&
        precisaJustificarTeto(
          saldoLivre: saldo.saldoLivre,
          aReceber: saldo.aReceber,
          cobrado: cobrado,
        );
    final sobra = saldo.saldoLivre - cobrado;
    final corretor = (widget.advance['broker'] is Map
            ? widget.advance['broker']['name']
            : null)
        ?.toString() ?? 'O corretor';
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Aprovar adiantamento ${widget.advance['code'] ?? ''}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            FinanceTextField(
              controller: _fee,
              label: 'Taxa de antecipação (%)',
              helper: 'Definida por você agora — quem pediu não escolhe taxa. '
                  'Zero = sem taxa.',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: kMoneyInputFormatters,
              onChanged: (_) => setState(() {}),
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final f in [0, 5, 10, 20])
                  FinanceFilterChip(
                    label: f == 0 ? 'Sem taxa' : '$f%',
                    selected: fee == f,
                    onTap: () => setState(() => _fee.text = '$f'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            FinanceField('$corretor recebe', formatBrl(value), bold: true),
            FinanceField('Será descontado das comissões', formatBrl(cobrado), bold: true),
            if (temSaldo) ...[
              FinanceField('Saldo livre do corretor hoje', formatBrl(saldo.saldoLivre)),
              FinanceField(
                sobra >= 0 ? 'Sobra depois deste' : 'Falta',
                formatBrl(sobra.abs()),
                valueColor: sobra >= 0 ? FinanceTones.emerald : FinanceTones.rose,
              ),
            ] else
              const FinanceInlineNotice(
                color: FinanceTones.amber,
                icon: LucideIcons.info,
                text: 'Não foi possível carregar o saldo do corretor — o '
                    'financeiro confere o teto ao aprovar.',
              ),
            if (precisa) ...[
              const SizedBox(height: 10),
              FinanceTextField(
                controller: _motivo,
                label: 'Justificativa da aprovação acima do saldo *',
                maxLines: 3,
                maxLength: 400,
                onChanged: (_) => setState(() {}),
              ),
            ],
            if (_erro != null) ...[
              FinanceInlineNotice(text: _erro!),
              const SizedBox(height: 10),
            ],
            FinancePrimaryButton(
              label: precisa ? 'Aprovar acima do saldo' : 'Aprovar',
              color: precisa ? FinanceTones.rose : FinanceTones.emerald,
              loading: _saving,
              onPressed: precisa && _motivo.text.trim().isEmpty
                  ? null
                  : () async {
                      setState(() {
                        _saving = true;
                        _erro = null;
                      });
                      final e = await widget.onApprove(
                        fee,
                        precisa ? _motivo.text : null,
                      );
                      if (!context.mounted) return;
                      if (e == null) {
                        Navigator.of(context).pop(true);
                      } else {
                        setState(() {
                          _saving = false;
                          _erro = e.message;
                        });
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }
}
