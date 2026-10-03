import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../core/finance_api_client.dart';
import '../core/finance_cadastros.dart';
import '../core/finance_format.dart';
import '../core/finance_me.dart';
import '../core/widgets/finance_form_widgets.dart';
import '../meu_financeiro/widgets/finance_sheet.dart';
import '../meu_financeiro/widgets/meu_financeiro_widgets.dart';
import '../solicitacoes/models/request_models.dart';
import 'adiantamento_rules.dart';

/// Pedir adiantamento de comissão (`DrawerAdiantamentoForm.tsx`, modo
/// "minha visão": o corretor pede para si). O saldo livre NÃO é mostrado:
/// `broker-balance` exige `view-staff`, que o corretor não tem — o teto é
/// conferido pelo back no envio (400 com o máximo).
class PedirAdiantamentoPage extends StatefulWidget {
  const PedirAdiantamentoPage({super.key});

  @override
  State<PedirAdiantamentoPage> createState() => _PedirAdiantamentoPageState();
}

class _PedirAdiantamentoPageState extends State<PedirAdiantamentoPage> {
  final FinanceApiClient _client = FinanceApiClient.instance;

  bool _loading = true;
  bool _saving = false;
  String? _vendasErro;
  String? _loadErro;
  List<FinanceRef> _companies = const [];
  List<VendaOpcao> _vendas = const [];
  FinanceMe? _me;

  String? _companyId;
  final Set<String> _saleIds = {};
  final _desc = TextEditingController();
  final _value = TextEditingController();
  final _notes = TextEditingController();
  Map<String, String> _errors = {};
  String? _serverError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _desc.dispose();
    _value.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Empresas e (me → repasses) correm em paralelo; com o /auth/me em
    // cache, os repasses saem junto, sem cascata.
    final companiesF = FinanceCadastros.instance.companies();
    final vendasF = () async {
      final meRes = await FinanceMeService.instance.load();
      final me = meRes.success ? meRes.data : null;
      _me = me;
      final id = me?.userId;
      final res = await _client.get<dynamic>(
        '/repasses',
        query: {'brokerId': ?id},
      );
      return (res, id);
    }();
    final comp = await companiesF;
    final (rep, brokerId) = await vendasF;
    if (!mounted) return;
    setState(() {
      _loading = false;
      _companies = comp.data ?? const [];
      if (_companies.length == 1) _companyId = _companies.first.id;
      if (!comp.ok) _loadErro = 'Não foi possível carregar as empresas.';
      if (brokerId == null) {
        _loadErro =
            'Seu usuário não está vinculado ao Financeiro desta empresa — '
            'peça a um administrador para vincular antes de pedir adiantamento.';
      }
      if (rep.success) {
        final raw = rep.data;
        final list = raw is List
            ? raw
            : (raw is Map && raw['data'] is List ? raw['data'] as List : const []);
        _vendas = vendasParaAdiantamento(
          list
              .whereType<Map>()
              .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
              .toList(),
        );
      } else {
        _vendasErro = rep.financeError?.message;
      }
    });
  }

  double get _aReceberTotal => _vendas.fold(0, (s, v) => s + v.aReceber);

  Future<void> _submit() async {
    final value = parseBrlInput(_value.text);
    final errors = validarAdiantamento(
      companyId: _companyId,
      description: _desc.text,
      value: value,
    );
    setState(() {
      _errors = errors;
      _serverError = null;
    });
    if (errors.isNotEmpty) return;
    final brokerId = _me?.userId;
    if (brokerId == null) {
      financeSnack(context, _loadErro ?? 'Usuário sem vínculo.', error: true);
      return;
    }
    setState(() => _saving = true);
    final saleIds = _vendas
        .map((v) => v.saleId)
        .where(_saleIds.contains)
        .toList();
    var body = buildAdiantamentoBody(
      companyId: _companyId!,
      brokerId: brokerId,
      saleIds: saleIds,
      description: _desc.text,
      value: value!,
      notes: _notes.text,
    );
    ApiResponse<dynamic> res = await _client.post<dynamic>(
      '/commission-advances',
      body: body,
    );
    String? aviso;
    if (!res.success && deveReenviarSemSaleIds(body, res.message)) {
      body = Map.of(body)..remove('saleIds');
      res = await _client.post<dynamic>('/commission-advances', body: body);
      if (res.success) {
        aviso =
            'Só a primeira venda ficou vinculada: o servidor ainda não aceita '
            'múltiplas vendas.';
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (!res.success) {
      // 400 do teto já traz "Saldo livre R$X … Máximo com taxa de F%: R$M".
      setState(() => _serverError = res.financeError?.message ?? res.message);
      return;
    }
    final code = res.data is Map ? (res.data as Map)['code']?.toString() : null;
    financeSnack(
      context,
      aviso ?? 'Adiantamento ${code ?? ''} solicitado.'.replaceAll('  ', ' '),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Pedir adiantamento',
      showDrawer: false,
      showBottomNavigation: false,
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
          : _form(context),
    );
  }

  Widget _form(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final value = parseBrlInput(_value.text) ?? 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
      children: [
        Text(
          'Receba agora parte da comissão que ainda vai entrar. O valor é '
          'descontado dos seus próximos repasses, mais a taxa definida por '
          'quem aprova, se houver.',
          style: TextStyle(fontSize: 13, height: 1.4, color: secondary),
        ),
        const SizedBox(height: 14),
        if (_loadErro != null) ...[
          FinanceInlineNotice(text: _loadErro!, onRetry: _load),
          const SizedBox(height: 12),
        ],
        FinanceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FinanceSectionHeader(
                title: 'Seu limite',
                icon: LucideIcons.gauge,
              ),
              FinanceField(
                'A receber nas vendas',
                formatBrl(_aReceberTotal),
                valueColor: FinanceTones.sky,
                bold: true,
              ),
              const SizedBox(height: 6),
              Text(
                'O saldo livre (a receber − adiantamentos e estornos em aberto '
                '− pedidos em andamento) é conferido pelo financeiro no envio. '
                'Se passar do saldo, o pedido volta com o valor máximo.',
                style: TextStyle(fontSize: 12, height: 1.4, color: secondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FinanceDropdown<String>(
          label: 'Empresa pagadora *',
          value: _companyId,
          error: _errors['companyId'],
          items: [for (final c in _companies) (c.id, c.name)],
          onChanged: (v) => setState(() => _companyId = v),
        ),
        FinanceTextField(
          controller: _desc,
          label: 'Descrição *',
          hint: 'Ex.: adiantamento da comissão da venda do apto 302',
          maxLines: 2,
          error: _errors['description'],
        ),
        FinanceTextField(
          controller: _value,
          label: 'Valor adiantado (R\$) *',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: kMoneyInputFormatters,
          error: _errors['value'],
          onChanged: (_) => setState(() {}),
        ),
        FinanceCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: _box(context, 'Você recebe', formatBrl(value)),
              ),
              Expanded(
                child: _box(
                  context,
                  'Será descontado',
                  formatBrl(value),
                  hint: 'mais a taxa definida na aprovação, se houver',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Vendas do adiantamento (opcional)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: ThemeHelpers.textColor(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _vendasErro != null
              ? '$_vendasErro Tente reabrir a tela — a lista não foi carregada, '
                    'você pode ter vendas.'
              : _vendas.isEmpty
              ? 'Nenhuma venda com repasse encontrada para você.'
              : 'Vendas a que o adiantamento se refere — pode marcar mais de uma.',
          style: TextStyle(fontSize: 12.5, color: secondary),
        ),
        const SizedBox(height: 6),
        for (final v in _vendas)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _saleIds.contains(v.saleId),
            onChanged: _saleIds.length >= 30 && !_saleIds.contains(v.saleId)
                ? null
                : (on) => setState(() {
                    if (on == true) {
                      _saleIds.add(v.saleId);
                    } else {
                      _saleIds.remove(v.saleId);
                    }
                  }),
            title: Text(v.detalhe, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: v.aReceber > 0
                ? Text('a receber ${formatBrl(v.aReceber)}')
                : null,
          ),
        const SizedBox(height: 8),
        FinanceTextField(
          controller: _notes,
          label: 'Observações',
          maxLines: 3,
        ),
        if (_serverError != null) ...[
          FinanceInlineNotice(text: _serverError!),
          const SizedBox(height: 12),
        ],
        FinancePrimaryButton(
          label: 'Solicitar adiantamento',
          icon: LucideIcons.handCoins,
          loading: _saving,
          onPressed: _me?.userId == null ? null : _submit,
        ),
      ],
    );
  }

  Widget _box(BuildContext context, String label, String v, {String? hint}) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: secondary)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            v,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
            ),
          ),
        ),
        if (hint != null)
          Text(hint, style: TextStyle(fontSize: 11, color: secondary)),
      ],
    );
  }
}
