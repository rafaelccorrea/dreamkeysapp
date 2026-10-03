import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/api_service.dart';
import '../../../../shared/services/module_access_service.dart';
import '../../../../shared/services/secure_storage_service.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../core/finance_access.dart';
import '../../core/finance_cadastros.dart';
import '../../core/finance_format.dart';
import '../../core/finance_me.dart';
import '../../core/finance_route_names.dart';
import '../../core/widgets/finance_form_widgets.dart';
import '../../meu_financeiro/services/meu_financeiro_service.dart';
import '../../meu_financeiro/widgets/finance_sheet.dart';
import '../../meu_financeiro/widgets/meu_financeiro_widgets.dart';
import '../models/request_models.dart';
import '../models/request_rules.dart';
import '../services/requests_service.dart';
import '../widgets/anexo_picker.dart';

/// Nova solicitação (tipo → campos → anexos) ou edição/correção
/// (`NovaSolicitacao.tsx` + `DrawerSolicitacaoForm.tsx`).
class SolicitacaoFormPage extends StatefulWidget {
  /// Preenchido = edição (PENDENTE) ou correção (REPROVADO).
  final String? editId;
  final RequestsService? service;

  const SolicitacaoFormPage({super.key, this.editId, this.service});

  @override
  State<SolicitacaoFormPage> createState() => _SolicitacaoFormPageState();
}

class _SolicitacaoFormPageState extends State<SolicitacaoFormPage> {
  RequestsService get _svc => widget.service ?? RequestsService.instance;
  final FinanceCadastros _cad = FinanceCadastros.instance;

  bool get _edicao => widget.editId != null;

  bool _loading = true;
  bool _saving = false;
  bool _escolhendoTipo = false;
  String? _loadError;
  final List<String> _faltaram = [];

  RequestTiposCatalog? _catalog;
  List<FinanceRef> _companies = const [];
  List<FinanceRef> _categories = const [];
  List<FinanceRef> _costCenters = const [];
  List<FinanceRef> _suppliers = const [];
  List<FinanceRef> _cards = const [];
  bool _loadingCards = false;
  FinanceMe? _me;
  FinanceRequest? _original;

  final SolicitacaoForm _f = SolicitacaoForm();
  Map<String, String> _errors = {};
  final List<AnexoLocal> _anexos = [];

  final _title = TextEditingController();
  final _just = TextEditingController();
  final _amount = TextEditingController();
  final _dept = TextEditingController();
  final _notes = TextEditingController();
  final _outros = TextEditingController();
  final _mensagem = TextEditingController();
  final Map<String, TextEditingController> _campoCtrls = {};
  final List<(TextEditingController, String?)> _rateioRows = [];

  Timer? _draftTimer;
  String? _draftKey;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    for (final c in [_title, _just, _amount, _dept, _notes, _outros, _mensagem]) {
      c.dispose();
    }
    for (final c in _campoCtrls.values) {
      c.dispose();
    }
    for (final r in _rateioRows) {
      r.$1.dispose();
    }
    super.dispose();
  }

  // ─── Carga (tudo em paralelo; uma lista que falha vira aviso) ───────────

  Future<void> _init() async {
    final futures = <Future<Object?>>[
      _cad.tipos(),
      _cad.companies(),
      _cad.categories(),
      _cad.costCenters(),
      _cad.suppliers(),
      FinanceMeService.instance.load(),
      if (_edicao) _svc.detail(widget.editId!),
    ];
    final r = await Future.wait(futures);
    if (!mounted) return;
    final tipos = r[0] as Section<RequestTiposCatalog>;
    final comp = r[1] as Section<List<FinanceRef>>;
    final cat = r[2] as Section<List<FinanceRef>>;
    final cc = r[3] as Section<List<FinanceRef>>;
    final sup = r[4] as Section<List<FinanceRef>>;
    final me = r[5] as ApiResponse<FinanceMe?>;
    _catalog = tipos.data;
    _companies = comp.data ?? const [];
    _categories = cat.data ?? const [];
    _costCenters = cc.data ?? const [];
    _suppliers = sup.data ?? const [];
    _me = me.success ? me.data : null;
    if (!comp.ok) _faltaram.add('empresas');
    if (!cat.ok) _faltaram.add('categorias');
    // Centro de custo e fornecedor exigem chaves do time financeiro: para o
    // corretor o 403 é esperado — o campo some, sem alarme.
    if (!cc.ok && cc.error?.statusCode != 403) _faltaram.add('centros de custo');
    if (!sup.ok && sup.error?.statusCode != 403) _faltaram.add('fornecedores');

    if (_edicao) {
      final det = r[6] as Section<FinanceRequest>;
      if (det.data == null) {
        setState(() {
          _loading = false;
          _loadError = det.error?.message ?? 'Solicitação não encontrada.';
        });
        return;
      }
      _prefill(det.data!);
    } else {
      if (_companies.length == 1) _f.companyId = _companies.first.id;
      _escolhendoTipo = (_catalog?.tipos.isNotEmpty ?? false);
      if (!_escolhendoTipo) await _restoreDraft();
    }
    setState(() => _loading = false);
    if (_f.ehCartao) _loadCards();
  }

  void _prefill(FinanceRequest o) {
    _original = o;
    final tipo = _catalog?.tipos.where((t) => t.id == o.tipoId).firstOrNull;
    final notas = separarNotas(o.notes);
    _f
      ..tipo = tipo
      ..companyId = o.company?.id
      ..naturezaId = o.naturezaId
      ..type = o.type
      ..title = o.title
      ..justification = o.justification
      ..amount = o.amountRequested
      ..priority = o.priority
      ..categoryId = o.category?.id
      ..costCenterId = o.costCenter?.id
      ..supplierId = o.supplier?.id
      ..department = o.department ?? ''
      ..paymentMethod = o.paymentMethod
      ..notes = notas.notes
      ..outrosDescricao = notas.outros
      ..camposExtras = Map.of(o.camposExtras)
      ..creditCardId = o.creditCardId
      ..purchaseDate = o.purchaseDate == null
          ? null
          : DateTime.tryParse(o.purchaseDate!)?.toUtc()
      ..cartaoParcelado = (o.installments ?? 1) > 1
      ..installments = (o.installments ?? 2) > 1 ? o.installments! : 2;
    if (o.beneficiaries.isNotEmpty) {
      _f.rateio = true;
      for (final b in o.beneficiaries) {
        _rateioRows.add((
          TextEditingController(text: brlInputText(financeNum(b['amount']))),
          b['companyId']?.toString(),
        ));
      }
    }
    _syncControllers();
  }

  void _syncControllers() {
    _title.text = _f.title;
    _just.text = _f.justification;
    _amount.text = brlInputText(_f.amount);
    _dept.text = _f.department;
    _notes.text = _f.notes;
    _outros.text = _f.outrosDescricao;
    for (final c in _f.tipo?.campos ?? const <TipoCampo>[]) {
      if (c.kind == 'SIM_NAO' || c.kind == 'LISTA' || c.kind == 'DATA') continue;
      final v = _f.camposExtras[c.chave];
      _ctrl(c.chave).text = v == null
          ? ''
          : (c.kind == 'MOEDA' && v is num ? brlInputText(v.toDouble()) : '$v');
    }
  }

  TextEditingController _ctrl(String chave) =>
      _campoCtrls.putIfAbsent(chave, TextEditingController.new);

  Future<void> _loadCards() async {
    final company = _f.companyId;
    if (company == null) return;
    setState(() => _loadingCards = true);
    final r = await _cad.creditCards(company);
    if (!mounted) return;
    setState(() {
      _loadingCards = false;
      _cards = r.data ?? const [];
      if (!r.ok && !_faltaram.contains('cartões')) _faltaram.add('cartões');
    });
  }

  // ─── Rascunho local (só na criação) ─────────────────────────────────────

  Future<String> _key() async {
    final company = await SecureStorageService.instance.getCompanyId();
    return rascunhoKey(
      tipoId: _f.tipo?.id,
      userId: ModuleAccessService.instance.userId ?? _me?.userId,
      companyId: company,
    );
  }

  Future<void> _restoreDraft() async {
    if (_edicao) return;
    _draftKey = await _key();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftKey!);
      if (raw == null) return;
      final d = jsonDecode(raw);
      if (d is! Map) return;
      _f.applyDraft(Map<String, dynamic>.from(d));
      _syncControllers();
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Rascunho recuperado.'),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(label: 'Descartar', onPressed: _discardDraft),
            ),
          );
        });
      }
    } catch (_) {}
  }

  void _scheduleDraft() {
    if (_edicao || _draftKey == null) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (_f.isEmpty) {
          await prefs.remove(_draftKey!);
        } else {
          await prefs.setString(_draftKey!, jsonEncode(_f.toDraft()));
        }
      } catch (_) {}
    });
  }

  Future<void> _clearDraft() async {
    _draftTimer?.cancel();
    if (_draftKey == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey!);
    } catch (_) {}
  }

  void _discardDraft() {
    _clearDraft();
    setState(() {
      final company = _f.companyId;
      final tipo = _f.tipo;
      _f
        ..applyDraft(const {})
        ..companyId = company
        ..tipo = tipo;
      _syncControllers();
    });
  }

  void _changed(VoidCallback fn) {
    setState(fn);
    if (_errors.isNotEmpty) _errors = {};
    _scheduleDraft();
  }

  // ─── Tipo ───────────────────────────────────────────────────────────────

  Future<void> _escolherTipo(RequestTipo? t) async {
    if (t != null && t.ehAdiantamento) {
      // O motor ADIANTAMENTO_COMISSAO desvia para "Pedir adiantamento".
      Navigator.of(context).pushReplacementNamed(FinanceRouteNames.pedirAdiantamento);
      return;
    }
    setState(() {
      _f.tipo = t;
      _escolhendoTipo = false;
    });
    await _restoreDraft();
    if (mounted) setState(() {});
  }

  // ─── Envio ──────────────────────────────────────────────────────────────

  void _collect() {
    _f
      ..title = _title.text
      ..justification = _just.text
      ..amount = parseBrlInput(_amount.text)
      ..department = _dept.text
      ..notes = _notes.text
      ..outrosDescricao = _outros.text
      ..qtdAnexos = _anexos.length;
    for (final c in _f.tipo?.campos ?? const <TipoCampo>[]) {
      final ctrl = _campoCtrls[c.chave];
      if (ctrl == null) continue;
      if (c.kind == 'NUMERO' || c.kind == 'MOEDA') {
        _f.camposExtras[c.chave] = parseBrlInput(ctrl.text);
      } else {
        _f.camposExtras[c.chave] = ctrl.text.trim();
      }
    }
    _f.beneficiaries = [
      for (final r in _rateioRows)
        (companyId: r.$2, amount: parseBrlInput(r.$1.text)),
    ];
  }

  Future<void> _submit() async {
    _collect();
    final errors = validarSolicitacao(_f, edicao: _edicao);
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      financeSnack(context, 'Revise os campos destacados.', error: true);
      return;
    }
    setState(() => _saving = true);
    if (_edicao) {
      await _submitEdit();
    } else {
      await _submitNew();
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _submitEdit() async {
    final reprovada = _original?.status == 'REPROVADO';
    final body = buildRequestBody(
      _f,
      edicao: true,
      corrigindoReprovada: reprovada,
      mensagem: _mensagem.text,
    );
    final res = await _svc.update(widget.editId!, body);
    if (!mounted) return;
    if (!res.success) {
      financeSnack(context, res.message ?? 'Não foi possível salvar.', error: true);
      return;
    }
    financeSnack(
      context,
      reprovada
          ? 'Solicitação corrigida e reenviada para aprovação!'
          : 'Solicitação atualizada!',
    );
    Navigator.of(context).pop(true);
  }

  Future<void> _submitNew() async {
    final body = buildRequestBody(_f);
    final res = await _svc.create(body);
    if (!mounted) return;
    switch (res) {
      case CriacaoFalhou(:final error):
        financeSnack(context, error.message, error: true);
        return;
      case CriacaoOk(:final request, :final avisoLancamento, :final reconciliada):
        await _clearDraft();
        // Anexos UM DE CADA VEZ (o back aceita 3 simultâneos no total).
        final avisos = <String>[];
        final multipart = usaUploadMultipart(_me);
        for (final a in _anexos) {
          final erro = await _svc.uploadAttachment(
            request.id,
            filename: a.name,
            bytes: a.bytes,
            mimeType: a.mime,
            multipart: multipart,
          );
          if (erro != null) {
            avisos.add(
              'Este anexo pode não ter entrado: "${a.name}" ($erro). Confira '
              'no detalhe da solicitação e anexe o que faltar.',
            );
          }
        }
        if (!mounted) return;
        if (avisoLancamento != null || avisos.isNotEmpty || reconciliada) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text('Solicitação ${request.code ?? ''} criada'.trim()),
              content: SingleChildScrollView(
                child: Text(
                  [
                    if (reconciliada)
                      'O servidor demorou mais do que o app esperou, mas o '
                          'pedido ENTROU — conferimos antes de avisar. NÃO '
                          'envie de novo.',
                    ?avisoLancamento,
                    ...avisos,
                  ].join('\n\n'),
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Entendi'),
                ),
              ],
            ),
          );
        } else {
          financeSnack(context, 'Solicitação criada com sucesso!');
        }
        if (!mounted) return;
        Navigator.of(
          context,
        ).pushReplacementNamed(FinanceRouteNames.solicitacao(request.id), result: true);
    }
  }

  Future<void> _addAnexo() async {
    final a = await pickAnexo(context, limiteBytes: limiteAnexoBytes(_me));
    if (a == null || !mounted) return;
    _changed(() => _anexos.add(a));
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final titulo = _edicao
        ? (_original?.status == 'REPROVADO'
              ? 'Corrigir solicitação'
              : 'Editar solicitação')
        : 'Nova solicitação';
    return AppScaffold(
      title: titulo,
      showDrawer: false,
      showBottomNavigation: false,
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
          : _loadError != null
          ? ListView(
              padding: const EdgeInsets.all(20),
              children: [FinanceInlineNotice(text: _loadError!)],
            )
          : _escolhendoTipo
          ? _tipoPicker(context)
          : _form(context),
    );
  }

  Widget _tipoPicker(BuildContext context) {
    final tipos = _catalog!.tipos;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        Text(
          'O que você precisa pedir?',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: ThemeHelpers.textColor(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Escolha o tipo: os campos do pedido seguem o que o financeiro '
          'configurou para ele.',
          style: TextStyle(fontSize: 13, color: secondary),
        ),
        const SizedBox(height: 16),
        for (final t in tipos)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: FinanceCard(
              onTap: () => _escolherTipo(t),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: financeAccent(context).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      t.ehAdiantamento
                          ? LucideIcons.handCoins
                          : t.ehReembolso
                          ? LucideIcons.receipt
                          : LucideIcons.banknote,
                      size: 19,
                      color: financeAccent(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.nome,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: ThemeHelpers.textColor(context),
                          ),
                        ),
                        if (t.descricao != null)
                          Text(
                            t.descricao!,
                            style: TextStyle(fontSize: 12.5, color: secondary),
                          ),
                      ],
                    ),
                  ),
                  Icon(LucideIcons.chevronRight, size: 18, color: secondary),
                ],
              ),
            ),
          ),
      ],
    );
  }

  bool _visivel(String campo) => _f.tipo == null || _f.tipo!.base(campo).visivel;
  bool _obrig(String campo) => _f.tipo != null && _f.tipo!.base(campo).obrigatorio;
  String _lbl(String l, String campo) => _obrig(campo) ? '$l *' : l;

  Widget _form(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final tipo = _f.tipo;
    final reprovada = _original?.status == 'REPROVADO';
    final valorTravado = _original?.valorTravado ?? false;
    final podeTrocarEmpresa = !_edicao || reprovada;
    final podeRateio =
        _visivel('rateio') && !(tipo?.ehReembolso ?? false) && (!_edicao || reprovada);
    final naturezas = tipo == null
        ? const <RequestNatureza>[]
        : _catalog!.naturezasDo(tipo);
    final custosDaEmpresa = _costCenters.where((c) {
      final cid = c.raw['companyId']?.toString();
      return cid == null || cid.isEmpty || cid == _f.companyId;
    }).toList();
    final hoje = DateTime.now();
    final compraPassada = _f.purchaseDate != null &&
        DateTime(_f.purchaseDate!.year, _f.purchaseDate!.month, _f.purchaseDate!.day)
            .isBefore(DateTime(hoje.year, hoje.month, hoje.day));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
      children: [
        if (tipo != null)
          FinanceCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(LucideIcons.tag, size: 16, color: financeAccent(context)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tipo.nome,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (!_edicao)
                  TextButton(
                    onPressed: () => setState(() => _escolhendoTipo = true),
                    child: const Text('Trocar'),
                  ),
              ],
            ),
          ),
        if (_faltaram.isNotEmpty) ...[
          const SizedBox(height: 10),
          FinanceInlineNotice(
            color: FinanceTones.amber,
            icon: LucideIcons.info,
            text: 'Não foi possível carregar: ${_faltaram.join(', ')}.',
          ),
        ],
        if (reprovada) ...[
          const SizedBox(height: 10),
          const FinanceInlineNotice(
            color: FinanceTones.amber,
            icon: LucideIcons.rotateCcw,
            text:
                'Ao salvar, a solicitação é reenviada e passa de novo pela '
                'cadeia de aprovação.',
          ),
        ],
        const SizedBox(height: 14),
        if (podeTrocarEmpresa)
          FinanceDropdown<String>(
            label: 'Empresa *',
            value: _f.companyId,
            error: _errors['companyId'],
            items: [for (final c in _companies) (c.id, c.name)],
            onChanged: (v) {
              _changed(() {
                _f.companyId = v;
                _f.costCenterId = null;
                _f.creditCardId = null;
                _cards = const [];
              });
              if (_f.ehCartao) _loadCards();
            },
          )
        else
          FinanceField('Empresa', _original?.company?.name ?? '—'),
        if (tipo == null)
          FinanceDropdown<String>(
            label: 'Tipo *',
            value: _f.type,
            error: _errors['type'],
            items: [for (final t in kRequestTypesNovos) (t, requestTypeLabel(t))],
            onChanged: (v) => _changed(() => _f.type = v),
          )
        else if (_visivel('natureza'))
          FinanceDropdown<String>(
            label: _lbl('Natureza', 'natureza'),
            value: _f.naturezaId,
            error: _errors['naturezaId'],
            allowClear: !_obrig('natureza'),
            items: [for (final n in naturezas) (n.id, n.nome)],
            onChanged: (v) => _changed(() {
              _f.naturezaId = v;
              _f.type = naturezas.where((n) => n.id == v).firstOrNull?.grupo;
            }),
          ),
        if (_f.exigeDescricaoOutros)
          FinanceTextField(
            controller: _outros,
            label: 'O que é esse "Outros"? *',
            error: _errors['outrosDescricao'],
            onChanged: (_) => _changed(() => _f.outrosDescricao = _outros.text),
          ),
        FinanceTextField(
          controller: _title,
          label: 'Título *',
          maxLength: 200,
          error: _errors['title'],
          onChanged: (_) => _changed(() => _f.title = _title.text),
        ),
        FinanceTextField(
          controller: _just,
          label: 'Justificativa *',
          maxLines: 5,
          error: _errors['justification'],
          onChanged: (_) => _changed(() => _f.justification = _just.text),
        ),
        FinanceTextField(
          controller: _amount,
          label: 'Valor solicitado (R\$) *',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: kMoneyInputFormatters,
          enabled: !valorTravado,
          error: _errors['amount'],
          helper: valorTravado
              ? 'Uma etapa já aprovou: o valor só muda reprovando e reenviando.'
              : 'Não há teto: o valor só define a alçada de aprovação.',
          onChanged: (_) => _changed(() => _f.amount = parseBrlInput(_amount.text)),
        ),
        if (_visivel('prioridade'))
          FinanceDropdown<String>(
            label: 'Prioridade',
            value: _f.priority,
            items: [
              for (final e in kRequestPriorityLabels.entries) (e.key, e.value),
            ],
            onChanged: (v) => _changed(() => _f.priority = v ?? 'MEDIA'),
          ),
        if (_categories.isNotEmpty)
          FinanceDropdown<String>(
            label: 'Categoria',
            value: _f.categoryId,
            allowClear: true,
            items: [for (final c in _categories) (c.id, c.name)],
            onChanged: (v) => _changed(() => _f.categoryId = v),
          ),
        if (_visivel('centroDeCusto') && custosDaEmpresa.isNotEmpty)
          FinanceDropdown<String>(
            label: _lbl('Centro de custo', 'centroDeCusto'),
            value: _f.costCenterId,
            allowClear: true,
            error: _errors['costCenterId'],
            items: [for (final c in custosDaEmpresa) (c.id, c.name)],
            onChanged: (v) => _changed(() => _f.costCenterId = v),
          ),
        if (_visivel('fornecedor') &&
            !(tipo?.ehReembolso ?? false) &&
            _suppliers.isNotEmpty)
          FinanceDropdown<String>(
            label: _lbl('Fornecedor', 'fornecedor'),
            value: _f.supplierId,
            allowClear: true,
            error: _errors['supplierId'],
            items: [for (final s in _suppliers) (s.id, s.name)],
            onChanged: (v) => _changed(() => _f.supplierId = v),
          ),
        if (_visivel('departamento'))
          FinanceTextField(
            controller: _dept,
            label: _lbl('Departamento', 'departamento'),
            error: _errors['department'],
            onChanged: (_) => _changed(() => _f.department = _dept.text),
          ),
        if (_visivel('formaDePagamento') && !(tipo?.ehReembolso ?? false))
          FinanceDropdown<String>(
            label: _lbl('Forma de pagamento', 'formaDePagamento'),
            value: _f.paymentMethod,
            allowClear: true,
            error: _errors['paymentMethod'],
            items: [
              for (final e in kPaymentMethodLabels.entries) (e.key, e.value),
            ],
            onChanged: (v) {
              _changed(() => _f.paymentMethod = v);
              if (v == 'CARTAO_CREDITO') _loadCards();
            },
          ),
        if (_f.ehCartao) ..._cartao(context, compraPassada),
        for (final c in tipo?.campos ?? const <TipoCampo>[]) _campo(context, c),
        if (_visivel('observacoes'))
          FinanceTextField(
            controller: _notes,
            label: _lbl('Observações', 'observacoes'),
            maxLines: 3,
            error: _errors['notes'],
            onChanged: (_) => _changed(() => _f.notes = _notes.text),
          ),
        if (podeRateio && !_f.ehCartao) ..._rateio(context),
        if (reprovada)
          FinanceTextField(
            controller: _mensagem,
            label: 'Mensagem para quem aprova (opcional)',
            maxLines: 3,
            maxLength: 1000,
          ),
        if (!_edicao) _anexosBlock(context),
        const SizedBox(height: 18),
        FinancePrimaryButton(
          label: _edicao
              ? (reprovada ? 'Corrigir e reenviar' : 'Salvar alterações')
              : 'Enviar solicitação',
          icon: LucideIcons.send,
          loading: _saving,
          onPressed: _submit,
        ),
        const SizedBox(height: 10),
        Text(
          _edicao
              ? 'As alterações ficam registradas no histórico do pedido.'
              : 'O rascunho fica salvo neste aparelho até você enviar.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: secondary),
        ),
      ],
    );
  }

  List<Widget> _cartao(BuildContext context, bool compraPassada) {
    return [
      if (_loadingCards)
        const Padding(
          padding: EdgeInsets.only(bottom: 14),
          child: LinearProgressIndicator(minHeight: 2),
        )
      else
        FinanceDropdown<String>(
          label: 'Cartão de crédito *',
          value: _f.creditCardId,
          error: _errors['creditCardId'],
          helper: _cards.isEmpty ? 'Nenhum cartão disponível para esta empresa.' : null,
          items: [for (final c in _cards) (c.id, c.name)],
          onChanged: (v) => _changed(() => _f.creditCardId = v),
        ),
      FinanceDateField(
        label: 'Data da compra *',
        value: _f.purchaseDate,
        error: _errors['purchaseDate'],
        helper: compraPassada
            ? 'Compra já realizada: vai direto para a fatura do cartão, sem '
                  'aprovação prévia.'
            : null,
        onChanged: (d) => _changed(() => _f.purchaseDate = d),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('À vista')),
            ButtonSegment(value: true, label: Text('Parcelado')),
          ],
          selected: {_f.cartaoParcelado},
          onSelectionChanged: (s) => _changed(() => _f.cartaoParcelado = s.first),
        ),
      ),
      if (_f.cartaoParcelado)
        FinanceDropdown<int>(
          label: 'Parcelas *',
          value: _f.installments,
          error: _errors['installments'],
          items: [for (var i = 2; i <= 24; i++) (i, '${i}x')],
          onChanged: (v) => _changed(() => _f.installments = v ?? 2),
        ),
    ];
  }

  Widget _campo(BuildContext context, TipoCampo c) {
    final label = c.obrigatorio && c.kind != 'SIM_NAO' ? '${c.rotulo} *' : c.rotulo;
    final err = _errors['campo:${c.chave}'];
    switch (c.kind) {
      case 'SIM_NAO':
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(c.rotulo),
          subtitle: c.ajuda == null ? null : Text(c.ajuda!),
          value: _f.camposExtras[c.chave] == true,
          onChanged: (v) => _changed(() => _f.camposExtras[c.chave] = v),
        );
      case 'LISTA':
        return FinanceDropdown<String>(
          label: label,
          value: _f.camposExtras[c.chave]?.toString(),
          error: err,
          helper: c.ajuda,
          allowClear: !c.obrigatorio,
          items: [for (final o in c.opcoes) (o, o)],
          onChanged: (v) => _changed(() => _f.camposExtras[c.chave] = v),
        );
      case 'DATA':
        final raw = _f.camposExtras[c.chave]?.toString();
        return FinanceDateField(
          label: label,
          value: raw == null ? null : DateTime.tryParse(raw),
          error: err,
          helper: c.ajuda,
          onChanged: (d) => _changed(
            () => _f.camposExtras[c.chave] = d == null ? null : financeQueryDate(d),
          ),
        );
      default:
        final numeric = c.kind == 'NUMERO' || c.kind == 'MOEDA';
        return FinanceTextField(
          controller: _ctrl(c.chave),
          label: c.kind == 'MOEDA' ? '$label (R\$)' : label,
          error: err,
          helper: c.ajuda,
          maxLines: c.kind == 'TEXTO_LONGO' ? 4 : 1,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : null,
          inputFormatters: numeric ? kMoneyInputFormatters : null,
          onChanged: (v) => _changed(
            () => _f.camposExtras[c.chave] = numeric ? parseBrlInput(v) : v,
          ),
        );
    }
  }

  List<Widget> _rateio(BuildContext context) {
    final soma = _rateioRows.fold<double>(
      0,
      (s, r) => s + (parseBrlInput(r.$1.text) ?? 0),
    );
    return [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Ratear entre empresas'),
        subtitle: const Text('Divide o valor entre empresas do grupo.'),
        value: _f.rateio,
        onChanged: (v) => _changed(() {
          _f.rateio = v;
          if (v && _rateioRows.isEmpty) {
            _rateioRows.add((TextEditingController(), _f.companyId));
          }
        }),
      ),
      if (_f.rateio) ...[
        for (var i = 0; i < _rateioRows.length; i++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: FinanceDropdown<String>(
                  label: 'Empresa',
                  value: _rateioRows[i].$2,
                  items: [for (final c in _companies) (c.id, c.name)],
                  onChanged: (v) => _changed(
                    () => _rateioRows[i] = (_rateioRows[i].$1, v),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FinanceTextField(
                  controller: _rateioRows[i].$1,
                  label: 'Valor',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: kMoneyInputFormatters,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              IconButton(
                onPressed: () => _changed(() {
                  _rateioRows.removeAt(i).$1.dispose();
                }),
                icon: const Icon(LucideIcons.x, size: 18),
              ),
            ],
          ),
        Row(
          children: [
            TextButton.icon(
              onPressed: () => _changed(
                () => _rateioRows.add((TextEditingController(), null)),
              ),
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('Adicionar empresa'),
            ),
            const Spacer(),
            Text(
              'Soma ${formatBrl(soma)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        if (_errors['rateio'] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              _errors['rateio']!,
              style: const TextStyle(color: FinanceTones.rose, fontSize: 12.5),
            ),
          ),
      ],
    ];
  }

  Widget _anexosBlock(BuildContext context) {
    final limite = limiteAnexoBytes(_me) ~/ (1024 * 1024);
    final comprovante = _obrig('comprovante');
    return FinanceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FinanceSectionHeader(
            title: comprovante ? 'Comprovante *' : 'Anexos',
            icon: LucideIcons.paperclip,
            subtitle: 'PDF, JPG, PNG ou WebP · até $limite MB cada · enviados '
                'depois que o pedido for criado',
            trailing: IconButton(
              tooltip: 'Anexar',
              onPressed: _addAnexo,
              icon: Icon(LucideIcons.plus, color: financeAccent(context)),
            ),
          ),
          if (_anexos.isEmpty)
            FinanceEmpty(
              text: comprovante
                  ? 'Anexe o comprovante do gasto.'
                  : 'Nenhum anexo (opcional).',
            )
          else
            for (var i = 0; i < _anexos.length; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _anexos[i].mime == 'application/pdf'
                      ? LucideIcons.fileText
                      : LucideIcons.image,
                  size: 20,
                ),
                title: Text(_anexos[i].name, overflow: TextOverflow.ellipsis),
                subtitle: Text(_anexos[i].sizeLabel),
                trailing: IconButton(
                  icon: const Icon(LucideIcons.x, size: 18),
                  onPressed: () => _changed(() => _anexos.removeAt(i)),
                ),
              ),
          if (_errors['anexos'] != null)
            Text(
              _errors['anexos']!,
              style: const TextStyle(color: FinanceTones.rose, fontSize: 12.5),
            ),
        ],
      ),
    );
  }
}

