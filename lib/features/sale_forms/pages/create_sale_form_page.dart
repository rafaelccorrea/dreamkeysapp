import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/utils/input_formatters.dart';
import '../../../features/organization/models/unit_model.dart';
import '../../../features/organization/services/unit_service.dart';
import '../../../features/workspace/models/admin_user_model.dart';
import '../../../features/workspace/services/admin_users_service.dart';
import '../../../shared/services/cep_service.dart';
import '../../../shared/services/purchase_proposals_service.dart'
    show PurchaseProposal;
import '../../../shared/services/sale_forms_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../sale_form_rules.dart';
import '../services/sale_form_lookup_service.dart';
import '../services/sale_form_proposal_link_service.dart';
import '../widgets/proposal_picker_sheet.dart';
import '../widgets/sale_form_type_modal.dart';

/// Mídias de origem oficiais (espelha `midiasOrigemFichaVenda.ts` do web).
const List<String> _kMediaSources = [
  'REMARKETING',
  'PAP',
  'RELACIONAMENTO',
  'ANUNCIO PAGO',
  'INDICAÇÃO',
  'PLANTAO EXTERNO/INTERNO',
  'CHAVES NA MAO',
  'SITE',
  'GRUPO ZAP',
  'FEIRAS E EVENTOS',
  'LISTA FRIA',
  'ANUNCIO PAGO (CAMPANHA PESSOAL)',
  'ANUNCIO PAGO (CAMPANHA DE CONVERSA)',
  'INSTAGRAM PESSOAL',
  'CHATPRO - LEAD ORGANICO',
  'TELEFONE IMOBILIARIA',
  'DISPAROS',
  'PLACA',
  'INSTAGRAM ORGANICO',
  'GOOGLE ADS',
];

const List<String> _kUfs = [
  'AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MT', 'MS',
  'MG', 'PA', 'PB', 'PR', 'PE', 'PI', 'RJ', 'RN', 'RS', 'RO', 'RR', 'SC',
  'SP', 'SE', 'TO',
];

/// Valor fixo (R$) da comissão SDR por venda — igual ao web
/// (`VALOR_FIXO_COMISSAO_SDR_REAIS`): definido pela empresa, não editável.
const double _kSdrValorFixo = 300;

/// Diretor e Gestor SDR são da família da gerência (viajam em
/// `commissionsData.gerencias` com `papel`), como na web; aparecem só quando
/// as regras de comissão da empresa os habilitam. "Outros" fica fora das
/// travas (sem limite), como no web.
enum _Funcao { corretor, captador, sdr, gerencia, diretor, gestorSdr, outros }

extension _FuncaoX on _Funcao {
  String get label => switch (this) {
        _Funcao.corretor => 'Corretor',
        _Funcao.captador => 'Captador',
        _Funcao.sdr => 'SDR',
        _Funcao.gerencia => 'Gerência',
        _Funcao.diretor => 'Diretor',
        _Funcao.gestorSdr => 'Gestor SDR',
        _Funcao.outros => 'Outros',
      };
  String get api => switch (this) {
        _Funcao.corretor => 'corretor',
        _Funcao.captador => 'captador',
        _Funcao.sdr => 'sdr',
        _Funcao.gerencia => 'gerencia',
        _Funcao.diretor => 'diretor',
        _Funcao.gestorSdr => 'gestor_sdr',
        _Funcao.outros => 'outros',
      };

  /// Linhas que vão em `gerencias` (gestor comum, diretor, gestor SDR).
  bool get ehGerencia =>
      this == _Funcao.gerencia ||
      this == _Funcao.diretor ||
      this == _Funcao.gestorSdr;

  /// Corretor, captador e outros escolhem entre percentual e valor fixo.
  bool get escolheModo =>
      this == _Funcao.corretor ||
      this == _Funcao.captador ||
      this == _Funcao.outros;

  /// `papel` da linha de gerência no back; gestor comum não leva papel.
  String? get papel => switch (this) {
        _Funcao.diretor => 'diretor',
        _Funcao.gestorSdr => 'gestor_sdr',
        _ => null,
      };
}

class _Participant {
  String? userId;
  String userName = '';
  _Funcao funcao = _Funcao.corretor;
  final TextEditingController percent = TextEditingController();
  final TextEditingController valorFixo = TextEditingController();

  /// Corretor/captador/outros pagos em valor fixo (R$) em vez de %.
  bool fixo = false;
  bool emitirNota = false;
  void dispose() {
    percent.dispose();
    valorFixo.dispose();
  }
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Data só (sem fuso): "2026-09-20T00:00:00.000Z" → 20/09/2026.
DateTime? _parseD(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  if (m != null) {
    return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }
  final d = DateTime.tryParse(s);
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

/// Campo de data que aceita "Não aplicável".
class _DateSlot {
  DateTime? value;
  bool na = false;

  /// Formato do web: ISO, "Não aplicável" ou vazio.
  String get snapshot => na ? kSaleFormNa : (value == null ? '' : _iso(value!));

  /// `payloadOptionalDate`: N/A ou vazio não vai.
  String? get payload => na || value == null ? null : _iso(value!);

  void prefill(dynamic raw) {
    na = isSaleFormNa(raw?.toString());
    value = na ? null : _parseD(raw);
  }

  void clear() {
    value = null;
    na = false;
  }
}

// ── Payload (mesmas funções do web) ────────────────────────────────────────

/// `payloadRequiredText`: preserva "Não aplicável".
String _reqText(String v) {
  final t = v.trim();
  return isSaleFormNa(t) ? kSaleFormNa : t;
}

/// `payloadOptionalText`: valor, "Não aplicável" ou nada.
String? _optText(String v) {
  final t = v.trim();
  if (t.isEmpty) return null;
  return isSaleFormNa(t) ? kSaleFormNa : t;
}

/// `payloadOptionalFormat` (e-mail, telefone, CEP): N/A não vai.
String? _optFmt(String v) {
  final t = v.trim();
  if (t.isEmpty || isSaleFormNa(t)) return null;
  return t;
}

/// `payloadCpf`: só dígitos; N/A não vai.
String? _cpfPayload(String v) {
  if (isSaleFormNa(v)) return null;
  final d = saleFormDigits(v);
  return d.isEmpty ? null : d;
}

/// `payloadOptionalMoney`: N/A não vai; só o valor da venda exige > 0.
double? _optMoney(String v, {bool allowZero = false}) {
  if (isSaleFormNa(v) || v.trim().isEmpty) return null;
  final n = saleFormNumeric(v);
  if (n < 0) return null;
  if (!allowZero && n <= 0) return null;
  return n;
}

/// `mergeDescriptionForSave`: Observações entram na descrição.
String _mergeDescription(String description, String notes) {
  final d = description.trim();
  final n = notes.trim();
  if (d.isNotEmpty && n.isNotEmpty) return '$d\n\n$n';
  return d.isNotEmpty ? d : n;
}

/// Comprador, vendedor e cônjuges — mesmas chaves do web com prefixo
/// (`buyer`, `buyerSpouse`, `seller`, `sellerSpouse`).
class _Pessoa {
  _Pessoa(this.p);
  final String p;
  final name = TextEditingController();
  final cpf = TextEditingController();
  final rg = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  final profession = TextEditingController();
  final zip = TextEditingController();
  final street = TextEditingController();
  final number = TextEditingController();
  final complement = TextEditingController();
  final neighborhood = TextEditingController();
  final city = TextEditingController();
  String? state;
  final birth = _DateSlot();

  List<TextEditingController> get _ctrls => [
        name, cpf, rg, email, phone, profession, zip, street, number,
        complement, neighborhood, city,
      ];

  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
  }

  void clear() {
    for (final c in _ctrls) {
      c.clear();
    }
    state = null;
    birth.clear();
  }

  /// `inferHas*SpouseFromForm`: vazio ou "Não aplicável" não conta como dado.
  bool get temDado => [
        ..._ctrls.map((c) => c.text),
        state ?? '',
        birth.value == null ? '' : 'data',
      ].any((t) => t.trim().isNotEmpty && !isSaleFormNa(t));

  void prefill(Map<String, dynamic> r, SaleFormMask docMask) {
    String sv(String k) {
      final s = (r['$p$k'] ?? '').toString().trim();
      return isSaleFormNa(s) ? kSaleFormNa : s;
    }

    name.text = sv('Name');
    final doc = sv('Cpf');
    cpf.text = doc.isEmpty || doc == kSaleFormNa
        ? doc
        : saleFormApplyMask(docMask, doc);
    rg.text = sv('Rg');
    birth.prefill(r['${p}BirthDate']);
    email.text = sv('Email');
    phone.text = sv('Phone');
    profession.text = sv('Profession');
    zip.text = sv('ZipCode');
    street.text = sv('Street');
    number.text = sv('Number');
    complement.text = sv('Complement');
    neighborhood.text = sv('Neighborhood');
    city.text = sv('City');
    final uf = sv('State').toUpperCase();
    state = uf == kSaleFormNa.toUpperCase()
        ? kSaleFormNa
        : (_kUfs.contains(uf) ? uf : null);
  }

  /// Estado no formato do web (para as regras).
  void snapshot(Map<String, String> fd) {
    fd['${p}Name'] = name.text;
    fd['${p}Cpf'] = cpf.text;
    fd['${p}Rg'] = rg.text;
    fd['${p}BirthDate'] = birth.snapshot;
    fd['${p}Profession'] = profession.text;
    fd['${p}Email'] = email.text;
    fd['${p}Phone'] = phone.text;
    fd['${p}ZipCode'] = zip.text;
    fd['${p}Street'] = street.text;
    fd['${p}Number'] = number.text;
    fd['${p}Neighborhood'] = neighborhood.text;
    fd['${p}City'] = city.text;
    fd['${p}State'] = state ?? '';
  }

  void payload(Map<String, dynamic> body, {bool nameRequired = false}) {
    void put(String k, dynamic v) {
      if (v != null) body['$p$k'] = v;
    }

    put('Name', nameRequired ? _reqText(name.text) : _optText(name.text));
    put('Cpf', _cpfPayload(cpf.text));
    put('Rg', _optText(rg.text));
    put('BirthDate', birth.payload);
    put('Email', _optFmt(email.text));
    put('Phone', _optFmt(phone.text));
    put('Profession', _optText(profession.text));
    put('ZipCode', _optFmt(zip.text));
    put('Street', _optText(street.text));
    put('Number', _optText(number.text));
    put('Complement', _optText(complement.text));
    put('Neighborhood', _optText(neighborhood.text));
    put('City', _optText(city.text));
    put('State', _optText(state ?? ''));
  }
}

/// Formulário de criação/edição de ficha de venda — mesmas abas, campos e
/// regras do web (`CreateSaleFormPage.tsx`). Quase tudo é "obrigatório ou
/// Não aplicável" (chip N/A no campo; opção "― Não aplicável ―" nos selects).
/// Criar: abra via [showSaleFormTypeModal] e passe [choice].
/// Editar: passe [saleFormId] (tipo/equipe vêm da ficha carregada).
/// Criar a partir de uma proposta: passe também [prefillProposalId] (o
/// `?propostaId=` do web, usado pelo aviso "proposta finalizada").
class CreateSaleFormPage extends StatefulWidget {
  const CreateSaleFormPage({
    super.key,
    this.choice,
    this.saleFormId,
    this.prefillProposalId,
  }) : assert(choice != null || saleFormId != null,
            'Informe choice (criar) ou saleFormId (editar).');
  final SaleFormTypeChoice? choice;
  final String? saleFormId;
  final String? prefillProposalId;

  @override
  State<CreateSaleFormPage> createState() => _CreateSaleFormPageState();
}

class _CreateSaleFormPageState extends State<CreateSaleFormPage> {
  // Tipo/equipe — de `choice` (criar) ou da ficha carregada (editar).
  late SaleFormType _type;
  String _teamId = '';
  String _teamName = '';

  // Stepper.
  final PageController _pageCtrl = PageController();
  int _step = 0;

  bool get _isEdit => widget.saleFormId != null;
  bool _loadingExisting = false;

  // Dados gerais
  final _saleDate = _DateSlot();
  String? _mediaSource;
  final _saleUnit = TextEditingController();

  /// 'Sim' | 'Não' | "Não aplicável" (select do web).
  String? _secretaryPresent;
  bool _generalGroup = false;

  /// Nome do gerente (select de gestores do web) ou "Não aplicável".
  String _managerName = '';
  final _externalBrokerName = TextEditingController();
  final _description = TextEditingController();

  // Unidades (filiais): dona da ficha + compartilhadas.
  List<OrgUnit> _units = const [];
  final List<String> _sharedUnitIds = [];

  /// Edição: só envia `sharedUnitIds` depois de ler o que está gravado.
  bool _sharedUnitsReady = true;

  // Pessoas
  final _buyer = _Pessoa('buyer');
  final _buyerSpouse = _Pessoa('buyerSpouse');
  final _seller = _Pessoa('seller');
  final _sellerSpouse = _Pessoa('sellerSpouse');
  bool _hasBuyerSpouse = false;
  bool _hasSellerSpouse = false;

  // Imóvel
  final _propCode = TextEditingController();
  final _propZip = TextEditingController();
  final _propAddress = TextEditingController();
  final _propNumber = TextEditingController();
  final _propComplement = TextEditingController();
  final _propNeighborhood = TextEditingController();
  final _propCity = TextEditingController();
  String? _propState;

  // Empreendimento
  final _empIncorporadora = TextEditingController();
  final _empNome = TextEditingController();
  final _empUnidade = TextEditingController();
  final _empValorEntrada = TextEditingController();
  final _empFormaPagamento = TextEditingController();
  final _empDataEntrada = _DateSlot();

  // Financeiro
  final _saleValue = TextEditingController();
  final _totalCommission = TextEditingController();
  final _goalValue = TextEditingController();
  final _debtConfessionValue = TextEditingController();
  /// null = ainda não respondido
  bool? _debtConfession;
  bool? _fullFinancing;
  /// Ficha criada antes dos campos novos (sem resposta gravada): não cobra.
  bool _fichaAnteriorAosCamposNovos = false;
  CommissionPaymentModel _commissionModel = CommissionPaymentModel.obrigatorio;
  final _commissionDesc = TextEditingController();

  // Parcelamento da comissão
  bool _parcelado = false;
  final _parcelasQtd = TextEditingController();
  bool _parcelasIguais = true;
  final List<TextEditingController> _parcelas = [];

  // Colaboradores (nome do usuário ou "Não aplicável").
  String _preAtendimento = '';
  String _centralCaptacao = '';

  // Observações (vão juntas na descrição, como no web).
  final _notes = TextEditingController();

  // Comissões
  final List<_Participant> _participants = [];
  // Travas de comissão da empresa: decidem quais funções aparecem (Diretor,
  // Gestor SDR), a % fixa do diretor e as somas máximas de cada grupo.
  SaleFormCommissionRules _rules = SaleFormCommissionRules.padrao;

  List<_Funcao> get _funcoesDisponiveis => [
        _Funcao.corretor,
        _Funcao.captador,
        _Funcao.sdr,
        _Funcao.gerencia,
        if (_rules.usaDiretor) _Funcao.diretor,
        if (_rules.usaGestorSdr) _Funcao.gestorSdr,
        _Funcao.outros,
      ];

  // Vincular usuários (máx. 10, como no web).
  final List<SaleFormPessoa> _linkedUsers = [];
  static const int _kMaxVinculados = 10;

  // Proposta de origem ("Preencher a partir de uma proposta", só ao criar):
  // pré-preenche a ficha e, criada a ficha, é vinculada a ela
  // (`PATCH /sistema/fichas-proposta/:id/vincular-ficha-venda`).
  PurchaseProposal? _proposta;
  bool _carregandoProposta = false;

  late final Future<List<SaleFormPessoa>> _gestoresFuture;

  /// Erros por campo (chaves do web) — mostrados no próprio campo.
  final Map<String, String> _errors = {};

  /// Último CEP consultado por grupo (evita buscar de novo o mesmo CEP).
  final Map<String, String> _lastCep = {};

  bool _saving = false;

  bool get _isEmpreendimento => _type.isEmpreendimento;

  /// Abas do web: Lançamento/MCMV não têm Vendedor nem Cônjuge Vendedor.
  List<int> get _tabIds =>
      _isEmpreendimento ? kSaleFormTabsLancamento : kSaleFormTabsTodas;

  Color get _brand => Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;

  /// Cor de acento do passo = **vermelho da marca**, coerente com TODO o app
  /// (Documentos/Chaves/listagem usam `AppColors.primary`). Sem paleta por passo
  /// (arco-íris não tinha sentido): a identidade de cada etapa vem do ícone +
  /// "Passo X de N" + barra de progresso.
  Color get _accent => _brand;

  /// Tema local dos campos do formulário — visual filled, leve e fluido, com
  /// foco/cursor/seleção na cor da marca. Centraliza o estilo (inputs E selects
  /// ficam idênticos), inclusive o estado de erro.
  ThemeData _formTheme(BuildContext context) {
    final base = Theme.of(context);
    final isDark = base.brightness == Brightness.dark;
    final fill = isDark
        ? Colors.white.withValues(alpha: 0.045)
        : Colors.black.withValues(alpha: 0.025);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final error = AppColors.status.error;
    OutlineInputBorder b(Color c, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: w == 0 ? BorderSide.none : BorderSide(color: c, width: w),
        );
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(primary: _accent),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: _accent,
        selectionColor: _accent.withValues(alpha: 0.18),
        selectionHandleColor: _accent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fill,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        labelStyle:
            TextStyle(color: muted, fontWeight: FontWeight.w600, fontSize: 13.5),
        floatingLabelStyle: TextStyle(
            color: _accent, fontWeight: FontWeight.w700, fontSize: 13.5),
        hintStyle: TextStyle(
            color: muted.withValues(alpha: 0.7), fontWeight: FontWeight.w500),
        prefixStyle: TextStyle(
            color: ThemeHelpers.textColor(context), fontWeight: FontWeight.w700),
        errorStyle: TextStyle(
            color: error, fontWeight: FontWeight.w600, fontSize: 11.5),
        errorMaxLines: 3,
        border: b(Colors.transparent, 0),
        enabledBorder: b(Colors.transparent, 0),
        focusedBorder: b(_accent, 1.6),
        errorBorder: b(error.withValues(alpha: 0.75), 1.2),
        focusedErrorBorder: b(error, 1.6),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _type = widget.choice?.type ?? SaleFormType.terceiros;
    _teamId = widget.choice?.teamId ?? '';
    _teamName = widget.choice?.teamName ?? '';
    _gestoresFuture = SaleFormLookupService.instance.gestores();
    _loadRules();
    _loadUnits();
    if (_isEdit) _loadExisting();
    final pid = widget.prefillProposalId?.trim() ?? '';
    if (!_isEdit && pid.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _aplicarProposta(pid);
      });
    }
  }

  Future<void> _loadRules() async {
    final res = await SaleFormsService.instance.getCommissionRules();
    if (!mounted || !res.success || res.data == null) return;
    setState(() {
      _rules = res.data!;
      // Diretor já escolhido (edição hidratada antes das regras): a % é fixa.
      for (final p in _participants) {
        if (p.funcao == _Funcao.diretor) _aplicarPercentFixo(p);
      }
    });
  }

  /// Unidades (filiais) ativas — select "Unidade responsável" e
  /// "Compartilhar com outras unidades" (mesma fonte do web).
  Future<void> _loadUnits() async {
    final res = await UnitService.instance.list(activeOnly: true);
    if (!mounted || !res.success || res.data == null) return;
    setState(() => _units = res.data!);
  }

  /// Diretor tem percentual fixo pelas regras da empresa — o campo só reflete.
  void _aplicarPercentFixo(_Participant p) {
    final fixo = _rules.diretorPercent;
    if (fixo == null) return;
    p.percent.text = _pctText(fixo);
  }

  /// % em pt-BR ("2,5"): o `_money` trata ponto como milhar, então o texto
  /// do campo precisa ir com vírgula para voltar como o mesmo número.
  static String _pctText(num v) {
    final s = v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
    return s.replaceFirst('.', ',');
  }

  Future<void> _loadExisting() async {
    setState(() {
      _loadingExisting = true;
      _sharedUnitsReady = false;
    });
    final res = await SaleFormsService.instance.getById(widget.saleFormId!);
    if (!mounted) return;
    setState(() {
      _loadingExisting = false;
      if (res.success && res.data != null) {
        _prefill(res.data!);
      }
    });
    final shared = await SaleFormLookupService.instance
        .unidadesCompartilhadas(widget.saleFormId!);
    if (!mounted || shared == null) return;
    setState(() {
      _sharedUnitIds
        ..clear()
        ..addAll(shared);
      _sharedUnitsReady = true;
    });
  }

  void _prefill(SaleForm f) {
    final r = f.raw;
    String sv(String k) {
      final s = (r[k] ?? '').toString().trim();
      return isSaleFormNa(s) ? kSaleFormNa : s;
    }

    String moneyText(dynamic v) {
      final n = v is num ? v : num.tryParse((v ?? '').toString());
      return CurrencyInputFormatter.format(n);
    }

    _type = f.saleFormType;
    _teamId = f.teamId ?? '';
    _teamName = f.teamName ?? '';

    // Dados gerais
    _saleDate.prefill(r['saleDate']);
    final ms = f.mediaSource;
    if (ms != null && _kMediaSources.contains(ms)) _mediaSource = ms;
    _saleUnit.text = sv('saleUnit');
    final sp = sv('secretaryPresent');
    if (sp == kSaleFormNa) {
      _secretaryPresent = kSaleFormNa;
    } else if (sp.isNotEmpty) {
      _secretaryPresent = sp.toLowerCase() == 'sim' ? 'Sim' : 'Não';
    }
    _generalGroup = r['generalGroup'] == true;
    _managerName = sv('managerName');
    _externalBrokerName.text = sv('externalBrokerName');
    // Web: descrição e observações são gravadas juntas ("\n\n" separa).
    final rawDesc = (r['description'] ?? '').toString().trim();
    final sep = rawDesc.indexOf('\n\n');
    _description.text = sep >= 0 ? rawDesc.substring(0, sep).trim() : rawDesc;
    _notes.text = sep >= 0 ? rawDesc.substring(sep + 2).trim() : '';

    // Pessoas
    _buyer.prefill(r, SaleFormMask.cpfOuCnpj);
    _buyerSpouse.prefill(r, SaleFormMask.cpf);
    _seller.prefill(r, SaleFormMask.cpfOuCnpj);
    _sellerSpouse.prefill(r, SaleFormMask.cpf);
    _hasBuyerSpouse = _buyerSpouse.temDado;
    _hasSellerSpouse = _sellerSpouse.temDado;

    // Imóvel
    _propCode.text = sv('propertyCode');
    _propZip.text = sv('propertyZipCode');
    _propAddress.text = sv('propertyAddress');
    _propNumber.text = sv('propertyNumber');
    _propComplement.text = sv('propertyComplement');
    _propNeighborhood.text = sv('propertyNeighborhood');
    _propCity.text = sv('propertyCity');
    final pUf = sv('propertyState').toUpperCase();
    _propState = pUf == kSaleFormNa.toUpperCase()
        ? kSaleFormNa
        : (_kUfs.contains(pUf) ? pUf : null);

    // Empreendimento
    final emp = f.empreendimentoData;
    if (emp != null) {
      String ev(String k) {
        final s = (emp[k] ?? '').toString().trim();
        return isSaleFormNa(s) ? kSaleFormNa : s;
      }

      _empIncorporadora.text = ev('incorporadora');
      _empNome.text = ev('empreendimento');
      _empUnidade.text = ev('unidade');
      _empFormaPagamento.text = ev('formaPagamento');
      _empDataEntrada.prefill(emp['dataEntrada']);
      final ve = emp['valorEntrada'];
      _empValorEntrada.text = ve == null ? '' : moneyText(ve);
    }

    // Financeiro
    _saleValue.text = f.saleValue == null ? '' : moneyText(f.saleValue);
    _totalCommission.text =
        f.totalCommission == null ? '' : moneyText(f.totalCommission);
    _goalValue.text = f.goalValue == null ? '' : moneyText(f.goalValue);
    _debtConfession =
        r['debtConfession'] is bool ? r['debtConfession'] as bool : null;
    _fullFinancing =
        r['fullFinancing'] is bool ? r['fullFinancing'] as bool : null;
    _fichaAnteriorAosCamposNovos =
        _debtConfession == null && _fullFinancing == null;
    final dcv = r['debtConfessionValue'];
    _debtConfessionValue.text = dcv == null ? '' : moneyText(dcv);
    _commissionModel = f.commissionPaymentModel;
    _commissionDesc.text = _commissionModel == CommissionPaymentModel.naoAplicavel
        ? ''
        : (r['commissionPaymentModelDescription'] ?? '').toString();

    // Parcelamento
    final inst = r['commissionInstallmentsData'];
    if (inst is Map) {
      _parcelado = inst['parcelado'] == true;
      final q = inst['quantidadeParcelas'];
      _parcelasQtd.text = q == null ? '' : '$q';
      _parcelasIguais = inst['parcelasIguais'] != false;
      final vals = inst['valoresParcelas'];
      if (vals is List) {
        for (final v in vals) {
          _parcelas.add(TextEditingController(text: moneyText(v)));
        }
      }
      _syncParcelas();
    }

    // Colaboradores
    final col = r['collaboratorsData'];
    if (col is Map) {
      String cv(String k) {
        final s = (col[k] ?? '').toString().trim();
        return isSaleFormNa(s) ? kSaleFormNa : s;
      }

      _preAtendimento = cv('preAtendimento');
      _centralCaptacao = cv('centralCaptacao');
    }

    // Usuários vinculados (mesma leitura do web: userId + user.name).
    final linked = r['linkedUsers'];
    if (linked is List) {
      for (final row in linked.whereType<Map>()) {
        final uid = (row['userId'] ?? row['user_id'] ?? '').toString().trim();
        if (uid.isEmpty || _linkedUsers.any((u) => u.id == uid)) continue;
        final u = row['user'] ?? row['User'];
        final nome = u is Map ? (u['name'] ?? u['email'] ?? '').toString() : '';
        _linkedUsers.add(SaleFormPessoa(
          id: uid,
          name: nome.trim().isNotEmpty ? nome.trim() : 'Usuário',
          email: u is Map ? (u['email'] ?? '').toString() : '',
        ));
      }
    }

    // Comissões
    final cd = f.commissionsData;
    if (cd != null) {
      for (final c in (cd['corretores'] as List? ?? const [])) {
        if (c is! Map) continue;
        final p = _Participant();
        p.userId = c['id']?.toString();
        p.userName = (c['nome'] ?? c['name'] ?? 'Participante').toString();
        p.funcao = _parseFuncao(c['funcao']?.toString());
        p.emitirNota = c['emitirNota'] == true;
        final vf = c['valorFixo'];
        final pc = c['porcentagem'];
        if (p.funcao == _Funcao.sdr) {
          p.valorFixo.text = moneyText(vf is num ? vf : _kSdrValorFixo);
        } else if (vf is num && vf > 0) {
          p.fixo = true;
          p.valorFixo.text = moneyText(vf);
        } else {
          p.percent.text = pc is num ? _pctText(pc) : '';
        }
        _participants.add(p);
      }
      for (final g in (cd['gerencias'] as List? ?? const [])) {
        if (g is! Map) continue;
        final p = _Participant();
        p.funcao = switch (g['papel']?.toString()) {
          'diretor' => _Funcao.diretor,
          'gestor_sdr' => _Funcao.gestorSdr,
          _ => _Funcao.gerencia,
        };
        p.userId = g['gestorId']?.toString();
        p.userName = (g['nome'] ?? p.funcao.label).toString();
        final pc = g['porcentagem'];
        p.percent.text = pc is num ? _pctText(pc) : '';
        p.emitirNota = g['emitirNota'] == true;
        _participants.add(p);
      }
    }
  }

  static _Funcao _parseFuncao(String? s) {
    switch ((s ?? '').toLowerCase()) {
      case 'captador':
        return _Funcao.captador;
      case 'sdr':
        return _Funcao.sdr;
      case 'gerencia':
        return _Funcao.gerencia;
      case 'diretor':
        return _Funcao.diretor;
      case 'gestor_sdr':
        return _Funcao.gestorSdr;
      case 'outros':
        return _Funcao.outros;
      default:
        return _Funcao.corretor;
    }
  }

  // ── Proposta de origem ──────────────────────────────────────────────────

  Future<void> _escolherProposta() async {
    if (_carregandoProposta) return;
    FocusScope.of(context).unfocus();
    final escolhida = await showSaleFormProposalPicker(
      context,
      accent: _accent,
      selectedId: _proposta?.id,
    );
    if (escolhida == null || !mounted) return;
    await _aplicarProposta(escolhida.id);
  }

  /// `handleSelecionarProposta` do web: carrega o detalhe e pré-preenche.
  Future<void> _aplicarProposta(String id) async {
    setState(() => _carregandoProposta = true);
    final res = await SaleFormProposalLinkService.instance.carregar(id);
    if (!mounted) return;
    if (!res.success || res.data == null) {
      setState(() => _carregandoProposta = false);
      _toast(res.message ?? 'Erro ao carregar proposta.', error: true);
      return;
    }
    setState(() {
      _carregandoProposta = false;
      _proposta = res.data;
      _preencherComProposta(res.data!);
    });
    _toast('Ficha de venda preenchida com os dados da proposta. '
        'Revise e complete os campos que faltarem.');
  }

  /// Remove só o vínculo (web: `setPropostaSelecionadaId('')`); o que foi
  /// preenchido fica.
  void _removerProposta() => setState(() => _proposta = null);

  /// `mapPurchaseProposalToFormData` + merge do web: Proponente → Comprador,
  /// Proprietário → Vendedor, imóvel, data, unidade, valor e comissão. Só
  /// entra valor com conteúdo — vazio não apaga o que já foi digitado — e
  /// "Não aplicável" nunca vem da proposta (N/A é decisão de quem preenche).
  /// Chamar dentro de `setState`.
  void _preencherComProposta(PurchaseProposal p) {
    final r = p.raw;
    String? txt(dynamic v) {
      final s = (v ?? '').toString().trim();
      return s.isEmpty || isSaleFormNa(s) ? null : s;
    }

    // `pickFirst` do web.
    dynamic primeiro(List<dynamic> vs) =>
        vs.firstWhere((v) => txt(v) != null, orElse: () => null);

    void texto(TextEditingController c, String key, dynamic v,
        {SaleFormMask mask = SaleFormMask.none}) {
      final s = txt(v);
      if (s == null) return;
      final out = mask == SaleFormMask.none
          ? s
          : saleFormApplyMask(mask, saleFormDigits(s)).trim();
      if (out.isEmpty) return;
      c.text = out;
      _errors.remove(key);
    }

    void data(_DateSlot slot, String key, dynamic v) {
      if (txt(v) == null) return;
      final d = _parseD(v);
      if (d == null) return;
      slot
        ..value = d
        ..na = false;
      _errors.remove(key);
    }

    void dinheiro(TextEditingController c, String key, num? v) {
      if (v == null || v <= 0) return;
      c.text = CurrencyInputFormatter.format(v);
      _errors.remove(key);
    }

    String? uf(dynamic v) {
      final s = txt(v)?.toUpperCase();
      return s != null && _kUfs.contains(s) ? s : null;
    }

    void pessoa(
      _Pessoa pe,
      SaleFormMask docMask, {
      dynamic name,
      dynamic cpf,
      dynamic rg,
      dynamic birth,
      dynamic email,
      dynamic phone,
      dynamic profession,
      dynamic zip,
      dynamic street,
      dynamic neighborhood,
      dynamic city,
      dynamic state,
    }) {
      String k(String s) => '${pe.p}$s';
      texto(pe.name, k('Name'), name);
      texto(pe.cpf, k('Cpf'), cpf, mask: docMask);
      texto(pe.rg, k('Rg'), rg);
      data(pe.birth, k('BirthDate'), birth);
      texto(pe.email, k('Email'), email);
      texto(pe.phone, k('Phone'), phone, mask: SaleFormMask.phone);
      texto(pe.profession, k('Profession'), profession);
      texto(pe.zip, k('ZipCode'), zip, mask: SaleFormMask.cep);
      texto(pe.street, k('Street'), street);
      texto(pe.neighborhood, k('Neighborhood'), neighborhood);
      texto(pe.city, k('City'), city);
      final u = uf(state);
      if (u != null) {
        pe.state = u;
        _errors.remove(k('State'));
      }
    }

    // Dados gerais
    data(_saleDate, 'saleDate', r['proposalDate']);
    final unidade = txt(p.saleUnit);
    if (unidade != null) {
      _saleUnit.text = unidade;
      _errors.remove('saleUnit');
      // A unidade dona nunca é "compartilhada".
      final dona = _ownerUnit?.id;
      if (dona != null) _sharedUnitIds.remove(dona);
    }

    // Financeiro: valor proposto; comissão = valor × % da proposta.
    final preco = p.proposedPrice;
    final pct = p.commissionPercentage;
    dinheiro(_saleValue, 'saleValue', preco);
    if (preco != null && pct != null) {
      dinheiro(_totalCommission, 'totalCommission', preco * (pct / 100));
    }

    // Comprador ← Proponente
    pessoa(
      _buyer,
      SaleFormMask.cpfOuCnpj,
      name: p.proponentName,
      cpf: p.proponentCpf,
      rg: p.proponentRg,
      birth: r['proponentBirthDate'],
      email: p.proponentEmail,
      phone: p.proponentPhone,
      profession: p.proponentProfession,
      zip: p.proponentZipCode,
      street: p.proponentAddress,
      neighborhood: p.proponentNeighborhood,
      city: p.proponentCity,
      state: p.proponentState,
    );
    pessoa(
      _buyerSpouse,
      SaleFormMask.cpf,
      name: p.proponentSpouseName,
      cpf: p.proponentSpouseCpf,
      rg: p.proponentSpouseRg,
      birth: primeiro([
        r['buyerSpouseBirthDate'],
        r['proponentSpouseBirthDate'],
        r['proponentSpouseBirthdate'],
      ]),
      email: p.proponentSpouseEmail,
      phone: p.proponentSpousePhone,
      profession: p.proponentSpouseProfession,
    );

    // Vendedor ← Proprietário (web não copia CEP, cidade nem UF dele).
    pessoa(
      _seller,
      SaleFormMask.cpfOuCnpj,
      name: p.ownerName,
      cpf: p.ownerCpf,
      rg: p.ownerRg,
      birth: r['ownerBirthDate'],
      email: p.ownerEmail,
      phone: p.ownerPhone,
      profession: p.ownerProfession,
      street: p.ownerAddress,
      neighborhood: p.ownerNeighborhood,
    );
    final pd = r['propertyData'];
    pessoa(
      _sellerSpouse,
      SaleFormMask.cpf,
      name: p.ownerSpouseName,
      cpf: p.ownerSpouseCpf,
      rg: p.ownerSpouseRg,
      birth: primeiro([
        r['sellerSpouseBirthDate'],
        r['ownerSpouseBirthDate'],
        r['ownerSpouseBirthdate'],
        if (pd is Map) pd['ownerSpouseBirthDate'],
        if (pd is Map) pd['sellerSpouseBirthDate'],
      ]),
      email: p.ownerSpouseEmail,
      phone: p.ownerSpousePhone,
      profession: p.ownerSpouseProfession,
    );

    // Imóvel (web não copia o CEP do imóvel).
    texto(_propAddress, 'propertyAddress',
        primeiro([p.propertyAddress, p.propertyStreet]));
    texto(_propNumber, 'propertyNumber', p.propertyNumber);
    texto(_propComplement, '', p.propertyComplement);
    texto(_propNeighborhood, 'propertyNeighborhood', p.propertyNeighborhood);
    texto(_propCity, 'propertyCity', p.propertyCity);
    final pUf = uf(p.propertyState);
    if (pUf != null) {
      _propState = pUf;
      _errors.remove('propertyState');
    }
    texto(_propCode, 'propertyCode',
        primeiro([p.propertyCode, p.propertyRegistry]));

    // `inferHas*SpouseFromForm`: o interruptor segue o que ficou preenchido.
    _hasBuyerSpouse = _buyerSpouse.temDado;
    _hasSellerSpouse = _sellerSpouse.temDado;
    if (!_hasBuyerSpouse) {
      _errors.removeWhere((k, _) => kSaleFormTabFieldKeys[2]!.contains(k));
    }
    if (!_hasSellerSpouse) {
      _errors.removeWhere((k, _) => kSaleFormTabFieldKeys[4]!.contains(k));
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    for (final c in [
      _saleUnit, _externalBrokerName, _description, _notes,
      _propCode, _propZip, _propAddress, _propNumber, _propComplement,
      _propNeighborhood, _propCity,
      _empIncorporadora, _empNome, _empUnidade, _empValorEntrada,
      _empFormaPagamento,
      _saleValue, _totalCommission, _goalValue, _debtConfessionValue,
      _commissionDesc, _parcelasQtd,
      ..._parcelas,
    ]) {
      c.dispose();
    }
    for (final pe in [_buyer, _buyerSpouse, _seller, _sellerSpouse]) {
      pe.dispose();
    }
    for (final p in _participants) {
      p.dispose();
    }
    super.dispose();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  static double? _money(String s) {
    final t = s.trim();
    if (t.isEmpty || isSaleFormNa(t)) return null;
    // pt-BR: remove milhar (.) e usa vírgula como decimal.
    final cleaned = t.replaceAll(RegExp(r'[^\d,.-]'), '');
    final normalized = cleaned.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  static String _brl(double v) => 'R\$ ${CurrencyInputFormatter.format(v)}';

  void _clearErr(String key) {
    if (key.isEmpty || !_errors.containsKey(key)) return;
    setState(() => _errors.remove(key));
  }

  /// Unidade (filial) cujo nome é a "Unidade responsável" escolhida.
  OrgUnit? get _ownerUnit {
    final nome = _saleUnit.text.trim();
    if (nome.isEmpty) return null;
    for (final u in _units) {
      if (u.name == nome) return u;
    }
    return null;
  }

  int get _qtdParcelas => int.tryParse(_parcelasQtd.text.trim()) ?? 0;

  /// Garante um campo por parcela (mantém o que já foi digitado).
  void _syncParcelas() {
    final q = _qtdParcelas.clamp(0, kSaleFormMaxParcelas);
    while (_parcelas.length < q) {
      _parcelas.add(TextEditingController());
    }
  }

  // ── Validação (regras do web) ───────────────────────────────────────────

  SaleFormRulesInput _rulesInput() {
    final fd = <String, String>{
      'teamId': _teamId,
      'saleDate': _saleDate.snapshot,
      'secretaryPresent': _secretaryPresent ?? '',
      'managerName': _managerName,
      'mediaSource': _mediaSource ?? '',
      'saleUnit': _saleUnit.text,
      'description': _description.text,
      'incorporadora': _empIncorporadora.text,
      'empreendimento': _empNome.text,
      'unidade': _empUnidade.text,
      'dataEntrada': _empDataEntrada.snapshot,
      'valorEntrada': _empValorEntrada.text,
      'formaPagamento': _empFormaPagamento.text,
      'propertyCode': _propCode.text,
      'propertyZipCode': _propZip.text,
      'propertyAddress': _propAddress.text,
      'propertyNumber': _propNumber.text,
      'propertyNeighborhood': _propNeighborhood.text,
      'propertyCity': _propCity.text,
      'propertyState': _propState ?? '',
      'saleValue': _saleValue.text,
      'totalCommission': _totalCommission.text,
      'goalValue': _goalValue.text,
      'commissionPaymentModelDescription': _commissionDesc.text,
      'commissionInstallmentsCount': _parcelasQtd.text,
      'debtConfession':
          _debtConfession == null ? '' : (_debtConfession! ? 'sim' : 'nao'),
      'debtConfessionValue': _debtConfessionValue.text,
      'fullFinancing':
          _fullFinancing == null ? '' : (_fullFinancing! ? 'sim' : 'nao'),
      'preAtendimento': _preAtendimento,
      'centralCaptacao': _centralCaptacao,
    };
    for (final pe in [_buyer, _buyerSpouse, _seller, _sellerSpouse]) {
      pe.snapshot(fd);
    }
    return SaleFormRulesInput(
      fd: fd,
      hasBuyerSpouse: _hasBuyerSpouse,
      hasSellerSpouse: _hasSellerSpouse,
      generalGroup: _generalGroup,
      isLancamentoOuMcmv: _isEmpreendimento,
      commissionModelNaoAplicavel:
          _commissionModel == CommissionPaymentModel.naoAplicavel,
      installmentsEnabled: _parcelado,
      installmentsEqual: _parcelasIguais,
      installmentValues: [for (final c in _parcelas) c.text],
      fichaAnteriorAosCamposNovos: _fichaAnteriorAosCamposNovos,
    );
  }

  /// `hasValidCommissions` do web: com modelo ≠ Não aplicável, ao menos uma
  /// linha de comissão válida (% > 0, valor fixo > 0 ou SDR).
  bool _hasValidCommissions() {
    for (final p in _participants) {
      if (p.userId == null) continue;
      if (p.funcao == _Funcao.sdr) {
        if ((_money(p.valorFixo.text) ?? _kSdrValorFixo) > 0) return true;
      } else if (p.funcao == _Funcao.diretor) {
        if ((_rules.diretorPercent ?? _money(p.percent.text) ?? 0) > 0) {
          return true;
        }
      } else if (p.funcao.escolheModo && p.fixo) {
        if ((_money(p.valorFixo.text) ?? 0) > 0) return true;
      } else if ((_money(p.percent.text) ?? 0) > 0) {
        return true;
      }
    }
    return false;
  }

  /// Aba Comissões: usuário em cada linha, uma função por família e por
  /// pessoa (como o web impede), comissão válida e travas da empresa.
  String? _commissionError() {
    for (final p in _participants) {
      if (p.userId == null) {
        return 'Selecione o usuário de cada participante da comissão.';
      }
    }
    final corretores = <String>{};
    final gerencias = <String>{};
    for (final p in _participants) {
      final grupo = p.funcao.ehGerencia ? gerencias : corretores;
      if (!grupo.add(p.userId!)) {
        return p.funcao.ehGerencia
            ? '${p.userName} já tem uma função de gerência nesta ficha.'
            : '${p.userName} já tem uma função de corretor/captador/SDR nesta ficha.';
      }
    }
    if (_commissionModel == CommissionPaymentModel.naoAplicavel) return null;
    if (!_hasValidCommissions()) {
      return 'Defina a comissão de cada usuário vinculado (percentual ou valor fixo, conforme a função). SDR usa valor fixo da empresa.';
    }
    return _validarTravasDeComissao();
  }

  /// Mesmas travas da web (`validateSaleFormCommissionRules`): as somas valem
  /// para a ficha, não por pessoa. SDR (valor fixo), outros e linhas em valor
  /// fixo ficam fora das somas.
  String? _validarTravasDeComissao() {
    const tol = 0.001;
    double corretores = 0, gerencia = 0, gestorSdr = 0;
    for (final p in _participants) {
      final v = p.fixo ? 0.0 : (_money(p.percent.text) ?? 0);
      switch (p.funcao) {
        case _Funcao.corretor:
        case _Funcao.captador:
          corretores += v;
        case _Funcao.gerencia:
          gerencia += v;
        case _Funcao.gestorSdr:
          gestorSdr += v;
        case _Funcao.diretor:
          if (!_rules.usaDiretor) {
            return 'Comissão de diretor não está habilitada nas regras de comissão da empresa.';
          }
        case _Funcao.sdr:
        case _Funcao.outros:
          break;
      }
    }
    final maxC = _rules.corretoresTotalMax;
    if (maxC != null && corretores > maxC + tol) {
      return 'Corretores e captadores somam no máximo ${_pctText(maxC)}% na ficha. Atual: ${_pctText(corretores)}%';
    }
    final maxG = _rules.gerenciaTotalMax;
    if (maxG != null && gerencia > maxG + tol) {
      return 'Gestores/gerentes somam no máximo ${_pctText(maxG)}% na ficha (divida entre eles). Atual: ${_pctText(gerencia)}%';
    }
    final maxS = _rules.gestorSdrMax;
    if (maxS != null && gestorSdr > maxS + tol) {
      return 'Gestores SDR somam no máximo ${_pctText(maxS)}% na ficha. Atual: ${_pctText(gestorSdr)}%';
    }
    return null;
  }

  // ── Payload (mesmo do web) ──────────────────────────────────────────────

  Map<String, dynamic> _buildPayload() {
    final body = <String, dynamic>{
      'saleFormType': _type.apiValue,
      'teamId': _teamId,
      'mediaSource': _reqText(_mediaSource ?? ''),
      'saleUnit': _reqText(_saleUnit.text),
      'description': _mergeDescription(_description.text, _notes.text),
      'generalGroup': _generalGroup,
      'commissionPaymentModel':
          _commissionModel == CommissionPaymentModel.naoAplicavel
              ? 'nao_aplicavel'
              : 'obrigatorio',
    };

    void put(String key, dynamic value) {
      if (value != null) body[key] = value;
    }

    final unitId = _ownerUnit?.id;
    put('unitId', unitId);
    if (!_isEdit || _sharedUnitsReady) {
      body['sharedUnitIds'] =
          _sharedUnitIds.where((id) => id != unitId).toList();
    }
    put('saleDate', _saleDate.payload);
    put('secretaryPresent', _optText(_secretaryPresent ?? ''));
    put('managerName', _optText(_managerName));
    put('externalBrokerName', _optText(_externalBrokerName.text));

    _buyer.payload(body, nameRequired: true);
    if (_hasBuyerSpouse) _buyerSpouse.payload(body);
    // Lançamento/MCMV não têm Vendedor nem Cônjuge Vendedor (abas ocultas).
    if (!_isEmpreendimento) {
      _seller.payload(body);
      if (_hasSellerSpouse) _sellerSpouse.payload(body);
    }

    if (_isEmpreendimento) {
      final algum = [
        _empIncorporadora.text, _empNome.text, _empUnidade.text,
        _empDataEntrada.snapshot, _empValorEntrada.text,
        _empFormaPagamento.text,
      ].any((t) => t.isNotEmpty);
      if (algum) {
        final emp = <String, dynamic>{};
        void ePut(String k, dynamic v) {
          if (v != null) emp[k] = v;
        }

        ePut('incorporadora', _optText(_empIncorporadora.text));
        ePut('empreendimento', _optText(_empNome.text));
        ePut('unidade', _optText(_empUnidade.text));
        ePut('dataEntrada', _empDataEntrada.payload);
        ePut('valorEntrada', _optMoney(_empValorEntrada.text, allowZero: true));
        ePut('formaPagamento', _optText(_empFormaPagamento.text));
        body['empreendimentoData'] = emp;
      }
    } else {
      put('propertyCode', _optText(_propCode.text));
      put('propertyZipCode', _optFmt(_propZip.text));
      put('propertyAddress', _optText(_propAddress.text));
      put('propertyNumber', _optText(_propNumber.text));
      put('propertyComplement', _optText(_propComplement.text));
      put('propertyNeighborhood', _optText(_propNeighborhood.text));
      put('propertyCity', _optText(_propCity.text));
      put('propertyState', _optText(_propState ?? ''));
    }

    // Financeiro
    put('saleValue', _optMoney(_saleValue.text));
    put('totalCommission', _optMoney(_totalCommission.text, allowZero: true));
    put('goalValue', _optMoney(_goalValue.text, allowZero: true));
    if (_debtConfession != null) {
      body['debtConfession'] = _debtConfession;
      // "Não" apaga o valor gravado; sem resposta não manda nada.
      body['debtConfessionValue'] = _debtConfession!
          ? saleFormNumeric(_debtConfessionValue.text)
          : null;
    }
    if (_fullFinancing != null) body['fullFinancing'] = _fullFinancing;
    final naoAplicavel = _commissionModel == CommissionPaymentModel.naoAplicavel;
    if (!naoAplicavel) {
      final desc = _commissionDesc.text.trim();
      if (desc.isNotEmpty) body['commissionPaymentModelDescription'] = desc;
    }
    if (naoAplicavel || !_parcelado) {
      body['commissionInstallments'] = {'parcelado': false};
    } else {
      final q = _qtdParcelas;
      body['commissionInstallments'] = {
        'parcelado': true,
        'quantidadeParcelas': q,
        'parcelasIguais': _parcelasIguais,
        if (!_parcelasIguais)
          'valoresParcelas': [
            for (var i = 0; i < q; i++)
              saleFormNumeric(i < _parcelas.length ? _parcelas[i].text : ''),
          ],
      };
    }
    if (_preAtendimento.isNotEmpty || _centralCaptacao.isNotEmpty) {
      body['collaboratorsData'] = {
        if (_preAtendimento.isNotEmpty) 'preAtendimento': _preAtendimento,
        if (_centralCaptacao.isNotEmpty) 'centralCaptacao': _centralCaptacao,
      };
    }

    // Comissões — corretores sem usuário e gerências sem % não vão (web).
    final corretores = <Map<String, dynamic>>[];
    final gerencias = <Map<String, dynamic>>[];
    var nivel = 0;
    for (final p in _participants) {
      if (p.funcao.ehGerencia) {
        final pct = p.funcao == _Funcao.diretor
            ? (_rules.diretorPercent ?? _money(p.percent.text) ?? 0)
            : (_money(p.percent.text) ?? 0);
        if (pct <= 0) continue;
        nivel++;
        gerencias.add({
          'nivel': nivel,
          'porcentagem': pct,
          'nome': p.userName,
          if (p.userId != null) 'gestorId': p.userId,
          if (p.funcao.papel != null) 'papel': p.funcao.papel,
          'emitirNota': p.emitirNota,
        });
      } else {
        if (p.userId == null) continue;
        final m = <String, dynamic>{
          'id': p.userId,
          'funcao': p.funcao.api,
          'emitirNota': p.emitirNota,
        };
        if (p.funcao == _Funcao.sdr) {
          m['porcentagem'] = 0;
          m['valorFixo'] = _money(p.valorFixo.text) ?? _kSdrValorFixo;
        } else if (p.fixo) {
          m['porcentagem'] = 0;
          final vf = _money(p.valorFixo.text) ?? 0;
          if (vf > 0) m['valorFixo'] = vf;
        } else {
          m['porcentagem'] = _money(p.percent.text) ?? 0;
        }
        corretores.add(m);
      }
    }
    if (_participants.isNotEmpty) {
      body['commissionsData'] = {
        'corretores': corretores,
        'gerencias': gerencias,
      };
    }

    return body;
  }

  Future<void> _submit() async {
    // Todas as abas visíveis (menos Vincular e Comissões), como o `validate`.
    final input = _rulesInput();
    final merged = <String, String>{};
    int? primeira;
    var msg = '';
    for (var idx = 0; idx < _tabIds.length; idx++) {
      final tid = _tabIds[idx];
      if (tid == 6 || tid == 7) continue;
      final te = computeSaleFormErrorsForTab(tid, input);
      if (te.isEmpty) continue;
      merged.addAll(te);
      if (primeira == null) {
        primeira = idx;
        msg = te.values.first;
      }
    }
    setState(() {
      _errors
        ..clear()
        ..addAll(merged);
    });
    if (primeira != null) {
      _goTo(primeira);
      _toast(msg, error: true);
      return;
    }
    final ce = _commissionError();
    if (ce != null) {
      _goTo(_tabIds.indexOf(7));
      _toast(ce, error: true);
      return;
    }

    setState(() => _saving = true);
    final payload = _buildPayload();
    final res = _isEdit
        ? await SaleFormsService.instance.update(widget.saleFormId!, payload)
        : await SaleFormsService.instance.create(payload);
    if (!mounted) return;
    if (!res.success || res.data == null) {
      setState(() => _saving = false);
      _toast(
        res.message ??
            (_isEdit ? 'Falha ao salvar ficha.' : 'Falha ao criar ficha de venda.'),
        error: true,
      );
      return;
    }
    // Vincular usuários — no web quem entra nas comissões já é vinculado,
    // então os participantes vão junto. Não bloqueia o sucesso.
    final ids = <String>{
      ..._linkedUsers.map((u) => u.id),
      for (final p in _participants)
        if (p.userId != null) p.userId!,
    }.toList();
    if (ids.isNotEmpty) {
      await SaleFormsService.instance.addUsers(res.data!.id, ids);
    }
    // Web: criada a partir de uma proposta → vincula a proposta à ficha nova
    // (depois dos usuários). Não bloqueia o sucesso; o web só loga a falha,
    // aqui o usuário é avisado.
    final proposta = _proposta;
    final novaId = res.data!.id;
    if (!_isEdit && proposta != null && novaId.isNotEmpty) {
      final v = await SaleFormProposalLinkService.instance
          .vincularFichaVenda(proposta.id, novaId);
      if (!mounted) return;
      if (!v.success) {
        _toast(
          'A ficha foi criada, mas não foi possível vinculá-la à proposta '
          '${propostaNumeroLabel(proposta)}.',
          error: true,
        );
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop(true);
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor:
              error ? AppColors.status.error : AppColors.status.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _pickDate(ValueChanged<DateTime> onPick, DateTime? initial,
      {DateTime? first}) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: first ?? DateTime(now.year - 100),
      lastDate: DateTime(now.year + 10),
    );
    if (d != null) onPick(d);
  }

  /// Busca o endereço no ViaCEP ao completar 8 dígitos (como o web).
  Future<void> _autoCep(
    String grupo,
    String raw, {
    required TextEditingController street,
    required TextEditingController neighborhood,
    required TextEditingController city,
    required ValueChanged<String> onUf,
    required List<String> keys,
  }) async {
    final d = saleFormDigits(raw);
    if (d.length != 8) {
      if (d.length < 8) _lastCep[grupo] = '';
      return;
    }
    if (_lastCep[grupo] == d) return;
    _lastCep[grupo] = d;
    final a = await CepService.instance.searchCep(d);
    if (!mounted) return;
    if (a == null) {
      _toast('CEP não encontrado ou inválido', error: true);
      return;
    }
    setState(() {
      if ((a.street ?? '').trim().isNotEmpty) street.text = a.street!.trim();
      if ((a.neighborhood ?? '').trim().isNotEmpty) {
        neighborhood.text = a.neighborhood!.trim();
      }
      if ((a.city ?? '').trim().isNotEmpty) city.text = a.city!.trim();
      final uf = (a.state ?? '').trim().toUpperCase();
      if (_kUfs.contains(uf)) onUf(uf);
      for (final k in keys) {
        _errors.remove(k);
      }
    });
  }

  void _autoCepPessoa(_Pessoa pe, String raw) => _autoCep(
        pe.p,
        raw,
        street: pe.street,
        neighborhood: pe.neighborhood,
        city: pe.city,
        onUf: (uf) => pe.state = uf,
        keys: [
          '${pe.p}Street', '${pe.p}Neighborhood', '${pe.p}City',
          '${pe.p}State',
        ],
      );

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loadingExisting) {
      return AppScaffold(
        title: 'Editar ficha de venda',
        showBottomNavigation: false,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final ids = _tabIds;
    if (_step >= ids.length) _step = ids.length - 1;
    final meta = _tabMeta(ids[_step]);
    return AppScaffold(
      title: _isEdit ? 'Editar ficha de venda' : 'Nova ficha de venda',
      showBottomNavigation: false,
      body: Column(
        children: [
          _StepHeader(
            index: _step,
            total: ids.length,
            title: meta.title,
            subtitle: meta.subtitle,
            icon: meta.icon,
            color: _accent,
            typeLabel: _type.label,
            teamName: _teamName,
          ),
          Expanded(
            child: Theme(
              data: _formTheme(context),
              child: PageView(
                controller: _pageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _step = i),
                children: [
                  for (final tid in ids)
                    ListView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                      children: _tabContent(tid),
                    ),
                ],
              ),
            ),
          ),
          _navBar(ids.length),
        ],
      ),
    );
  }

  /// Rótulos das abas do web (TABS).
  ({String title, String subtitle, IconData icon}) _tabMeta(int tid) =>
      switch (tid) {
        0 => (
            title: 'Dados gerais',
            subtitle: 'Venda, unidade e mídia',
            icon: LucideIcons.fileText,
          ),
        1 => (
            title: 'Comprador',
            subtitle: 'Dados pessoais e endereço',
            icon: LucideIcons.user,
          ),
        2 => (
            title: 'Cônjuge do comprador',
            subtitle: 'Cônjuge ou sócio',
            icon: LucideIcons.users,
          ),
        3 => (
            title: 'Vendedor',
            subtitle: 'Dados pessoais e endereço',
            icon: LucideIcons.user,
          ),
        4 => (
            title: 'Cônjuge do vendedor',
            subtitle: 'Cônjuge ou sócio',
            icon: LucideIcons.users,
          ),
        5 => (
            title: _isEmpreendimento
                ? 'Empreendimento / financeiro'
                : 'Imóvel / financeiro',
            subtitle: 'Valores, comissão e colaboradores',
            icon: _isEmpreendimento ? LucideIcons.building2 : LucideIcons.house,
          ),
        6 => (
            title: 'Vincular usuários',
            subtitle: 'Quem pode ver a ficha',
            icon: LucideIcons.userPlus,
          ),
        7 => (
            title: 'Comissões',
            subtitle: 'Participantes e valores',
            icon: LucideIcons.dollarSign,
          ),
        _ => (
            title: 'Observações',
            subtitle: _isEdit ? 'Revisar e salvar' : 'Revisar e criar',
            icon: LucideIcons.notebookPen,
          ),
      };

  List<Widget> _tabContent(int tid) => switch (tid) {
        0 => _sectionGeral(),
        1 => _sectionPessoa(
            _buyer,
            band: 'COMPRADOR',
            docLabel: 'CPF/CNPJ',
            docMask: SaleFormMask.cpfOuCnpj,
          ),
        2 => _sectionConjuge(
            _buyerSpouse,
            band: 'CÔNJUGE DO COMPRADOR',
            pergunta: 'Há cônjuge ou sócio do comprador nesta venda?',
            has: _hasBuyerSpouse,
            onToggle: (v) => setState(() {
              _hasBuyerSpouse = v;
              if (!v) {
                _buyerSpouse.clear();
                _errors.removeWhere(
                    (k, _) => kSaleFormTabFieldKeys[2]!.contains(k));
              }
            }),
          ),
        3 => _sectionPessoa(
            _seller,
            band: 'VENDEDOR',
            docLabel: 'CPF/CNPJ',
            docMask: SaleFormMask.cpfOuCnpj,
          ),
        4 => _sectionConjuge(
            _sellerSpouse,
            band: 'CÔNJUGE DO VENDEDOR',
            pergunta: 'Há cônjuge ou sócio do vendedor nesta venda?',
            has: _hasSellerSpouse,
            onToggle: (v) => setState(() {
              _hasSellerSpouse = v;
              if (!v) {
                _sellerSpouse.clear();
                _errors.removeWhere(
                    (k, _) => kSaleFormTabFieldKeys[4]!.contains(k));
              }
            }),
          ),
        5 => [
            ...(_isEmpreendimento
                ? _sectionEmpreendimento()
                : _sectionImovel()),
            ..._sectionFinanceiro(),
            ..._sectionColaboradores(),
          ],
        6 => _sectionVincular(),
        7 => _sectionComissoes(),
        _ => _sectionObservacoes(),
      };

  // ── Navegação dos passos ─────────────────────────────────────────────────

  /// `tryGoToTab` do web: valida a aba atual antes de avançar.
  void _next(int total) {
    final tid = _tabIds[_step];
    final errs = computeSaleFormErrorsForTab(tid, _rulesInput());
    setState(() {
      _errors.removeWhere(
          (k, _) => (kSaleFormTabFieldKeys[tid] ?? const []).contains(k));
      _errors.addAll(errs);
    });
    if (errs.isNotEmpty) {
      _toast(errs.values.first, error: true);
      return;
    }
    if (tid == 7) {
      final ce = _commissionError();
      if (ce != null) {
        _toast(ce, error: true);
        return;
      }
    }
    FocusScope.of(context).unfocus();
    if (_step < total - 1) _goTo(_step + 1);
  }

  void _back() {
    FocusScope.of(context).unfocus();
    if (_step > 0) _goTo(_step - 1);
  }

  void _goTo(int index) {
    if (index < 0 || !_pageCtrl.hasClients) return;
    _pageCtrl.animateToPage(
      index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _navBar(int total) {
    final last = _step == total - 1;
    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          top: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
      child: Row(
        children: [
          if (_step > 0) ...[
            OutlinedButton.icon(
              onPressed: _saving ? null : _back,
              style: OutlinedButton.styleFrom(
                // Neutro — voltar não é ação de marca; coerência de cor.
                foregroundColor: ThemeHelpers.textSecondaryColor(context),
                side: BorderSide(color: ThemeHelpers.borderColor(context)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(LucideIcons.arrowLeft, size: 16),
              label: const Text('Voltar',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: FilledButton.icon(
              onPressed:
                  _saving ? null : (last ? _submit : () => _next(total)),
              style: FilledButton.styleFrom(
                backgroundColor: _brand,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(last ? LucideIcons.check : LucideIcons.arrowRight,
                      size: 18),
              label: Text(
                _saving
                    ? 'Salvando…'
                    : last
                        ? (_isEdit ? 'Salvar alterações' : 'Criar ficha de venda')
                        : 'Próximo',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Fábricas de campo (erro no campo + N/A) ─────────────────────────────

  /// Campo de texto. [key] = chave do web (erro); [na] = aceita N/A.
  Widget _tf(
    String key,
    String label,
    TextEditingController c, {
    bool req = true,
    bool na = true,
    SaleFormMask mask = SaleFormMask.none,
    TextInputType? keyboard,
    bool money = false,
    int maxLines = 1,
    int? maxLength,
    String? hint,
    String? helper,
    ValueChanged<String>? onChanged,
  }) =>
      _Field(
        label: label,
        controller: c,
        required: req,
        allowNa: na,
        mask: mask,
        keyboard: keyboard,
        money: money,
        maxLines: maxLines,
        maxLength: maxLength,
        hint: hint,
        helper: helper,
        errorText: key.isEmpty ? null : _errors[key],
        onChanged: (v) {
          _clearErr(key);
          onChanged?.call(v);
        },
      );

  Widget _dateField(String key, String label, _DateSlot slot,
          {DateTime? first}) =>
      _DateField(
        label: label,
        required: true,
        value: slot.value,
        na: slot.na,
        errorText: _errors[key],
        onTap: () => _pickDate(
          (d) => setState(() {
            slot.value = d;
            slot.na = false;
            _errors.remove(key);
          }),
          slot.value,
          first: first,
        ),
        onNa: () => setState(() {
          slot.na = !slot.na;
          if (slot.na) slot.value = null;
          _errors.remove(key);
        }),
      );

  Widget _ufField(String key, String? value, ValueChanged<String?> onChanged) =>
      _Dropdown(
        label: 'UF',
        required: true,
        allowNa: true,
        value: value,
        options: _kUfs,
        errorText: _errors[key],
        onChanged: (v) => setState(() {
          onChanged(v);
          _errors.remove(key);
        }),
      );

  /// Pergunta de escolha única (pílulas lado a lado, sem estourar a linha).
  List<Widget> _pergunta(
    String label, {
    required List<(String, String)> opcoes,
    required String? value,
    required ValueChanged<String> onChanged,
    bool required = true,
    String? errorKey,
    String? helper,
  }) {
    final err = errorKey == null ? null : _errors[errorKey];
    return [
      _MiniLabel(required ? '$label *' : label),
      Row(
        children: [
          for (var i = 0; i < opcoes.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: _Choice(
                label: opcoes[i].$2,
                selected: value == opcoes[i].$1,
                accent: _accent,
                onTap: () {
                  onChanged(opcoes[i].$1);
                  if (errorKey != null) _errors.remove(errorKey);
                },
              ),
            ),
          ],
        ],
      ),
      if (err != null) _ErrorLine(err),
      if (helper != null && err == null) _Helper(helper),
      const SizedBox(height: 14),
    ];
  }

  // ── Seções ──────────────────────────────────────────────────────────────

  String? _displayNa(String v) =>
      v.trim().isEmpty ? null : (isSaleFormNa(v) ? kSaleFormNa : v);

  Widget _unidadeField() {
    // Sem unidades cadastradas (ou sem acesso): texto livre, como era.
    if (_units.isEmpty) {
      return _tf('saleUnit', 'Unidade responsável', _saleUnit);
    }
    final atual = _saleUnit.text.trim();
    final nomes = _units.map((u) => u.name).toList();
    final labels = <String, String>{};
    if (atual.isNotEmpty && !isSaleFormNa(atual) && !nomes.contains(atual)) {
      nomes.add(atual);
      labels[atual] = '$atual (indisponível)';
    }
    return _Dropdown(
      label: 'Unidade responsável',
      required: true,
      allowNa: true,
      value: atual.isEmpty ? null : (isSaleFormNa(atual) ? kSaleFormNa : atual),
      options: nomes,
      labels: labels,
      errorText: _errors['saleUnit'],
      onChanged: (v) => setState(() {
        _saleUnit.text = v ?? '';
        _errors.remove('saleUnit');
        // A unidade dona nunca é "compartilhada".
        final dona = _ownerUnit?.id;
        if (dona != null) _sharedUnitIds.remove(dona);
      }),
    );
  }

  List<Widget> _sectionGeral() {
    final dona = _ownerUnit?.id;
    final compartilhaveis = _units.where((u) => u.id != dona).toList();
    final nomesCompartilhados = [
      for (final u in compartilhaveis)
        if (_sharedUnitIds.contains(u.id)) u.name,
    ];
    return [
      // Web: "Preencher a partir de uma proposta" (só ao criar).
      if (!_isEdit)
        SaleFormProposalPrefillBar(
          accent: _accent,
          proposta: _proposta,
          carregando: _carregandoProposta,
          onEscolher: _escolherProposta,
          onRemover: _removerProposta,
        ),
      _Band('DADOS GERAIS', LucideIcons.fileText),
      _Row2(
        left: _dateField('saleDate', 'Data da venda', _saleDate,
            first: DateTime(2000)),
        right: _unidadeField(),
      ),
      if (_units.length > 1)
        _PickerField(
          label: 'Compartilhar com outras unidades',
          value: nomesCompartilhados.isEmpty
              ? null
              : nomesCompartilhados.join(', '),
          placeholder: 'Nenhuma — só a unidade responsável',
          onTap: () => _pickSharedUnits(compartilhaveis),
        ),
      _PickerField(
        label: 'Nome do gerente',
        required: true,
        value: _displayNa(_managerName),
        errorText: _errors['managerName'],
        onTap: _pickGestor,
      ),
      _Dropdown(
        label: 'Mídia de origem',
        required: true,
        value: _mediaSource,
        options: _kMediaSources,
        errorText: _errors['mediaSource'],
        onChanged: (v) => setState(() {
          _mediaSource = v;
          _errors.remove('mediaSource');
        }),
      ),
      ..._pergunta(
        'Secretária presente',
        opcoes: const [('Sim', 'Sim'), ('Não', 'Não'), (kSaleFormNa, 'N/A')],
        value: _secretaryPresent,
        errorKey: 'secretaryPresent',
        onChanged: (v) => setState(() => _secretaryPresent = v),
      ),
      ..._pergunta(
        'Grupo geral (unidade compartilhada)',
        required: false,
        opcoes: const [('false', 'Não'), ('true', 'Sim')],
        value: _generalGroup ? 'true' : 'false',
        helper: 'Quando Sim, a ficha é de unidade compartilhada entre equipes.',
        onChanged: (v) => setState(() => _generalGroup = v == 'true'),
      ),
      _tf(
        'description',
        _generalGroup
            ? 'Descrição da forma de comissionamento'
            : 'Descrição / observações da ficha',
        _description,
        maxLines: 4,
        helper: _generalGroup
            ? 'Obrigatório quando a ficha é de unidade compartilhada.'
            : 'Obrigatório: detalhes relevantes da operação.',
      ),
      const SizedBox(height: 6),
    ];
  }

  List<Widget> _camposPessoa(_Pessoa pe,
      {required String docLabel, required SaleFormMask docMask}) {
    String k(String s) => '${pe.p}$s';
    return [
      _tf(k('Name'), 'Nome completo', pe.name, keyboard: TextInputType.name),
      _Row2(
        left: _tf(k('Cpf'), docLabel, pe.cpf,
            mask: docMask, keyboard: TextInputType.number),
        right: _tf(k('Rg'), 'RG', pe.rg),
      ),
      _Row2(
        left: _dateField(k('BirthDate'), 'Nascimento', pe.birth),
        right: _tf(k('Profession'), 'Profissão', pe.profession),
      ),
      _Row2(
        left: _tf(k('Email'), 'E-mail', pe.email,
            mask: SaleFormMask.email, keyboard: TextInputType.emailAddress),
        right: _tf(k('Phone'), 'Celular', pe.phone,
            mask: SaleFormMask.phone, keyboard: TextInputType.phone),
      ),
      const SizedBox(height: 2),
      _MiniLabel('Endereço'),
      _Row2(
        left: _tf(k('ZipCode'), 'CEP', pe.zip,
            mask: SaleFormMask.cep,
            keyboard: TextInputType.number,
            onChanged: (v) => _autoCepPessoa(pe, v)),
        right: _tf(k('Neighborhood'), 'Bairro', pe.neighborhood),
      ),
      _tf(k('Street'), 'Rua', pe.street),
      _Row2(
        leftFlex: 2,
        rightFlex: 3,
        left: _tf(k('Number'), 'Número', pe.number),
        right: _tf('', 'Complemento', pe.complement, req: false, na: false),
      ),
      _Row2(
        leftFlex: 3,
        rightFlex: 2,
        left: _tf(k('City'), 'Cidade', pe.city),
        right: _ufField(k('State'), pe.state, (v) => pe.state = v),
      ),
      const SizedBox(height: 6),
    ];
  }

  List<Widget> _sectionPessoa(
    _Pessoa pe, {
    required String band,
    required String docLabel,
    required SaleFormMask docMask,
  }) =>
      [
        _Band(band, LucideIcons.user),
        ..._camposPessoa(pe, docLabel: docLabel, docMask: docMask),
      ];

  List<Widget> _sectionConjuge(
    _Pessoa pe, {
    required String band,
    required String pergunta,
    required bool has,
    required ValueChanged<bool> onToggle,
  }) =>
      [
        _Band(band, LucideIcons.users),
        _SwitchRow(
          title: pergunta,
          hint: has
              ? 'Ligado — os campos abaixo são obrigatórios.'
              : 'Desligado — avance; nada aqui é obrigatório.',
          value: has,
          onChanged: onToggle,
        ),
        const SizedBox(height: 12),
        if (has) ..._camposPessoa(pe, docLabel: 'CPF', docMask: SaleFormMask.cpf),
      ];

  List<Widget> _sectionImovel() => [
        _Band('IMÓVEL', LucideIcons.house),
        _Row2(
          left: _tf('propertyCode', 'Código do imóvel', _propCode),
          right: _tf('propertyZipCode', 'CEP', _propZip,
              mask: SaleFormMask.cep,
              keyboard: TextInputType.number,
              onChanged: (v) => _autoCep(
                    'property',
                    v,
                    street: _propAddress,
                    neighborhood: _propNeighborhood,
                    city: _propCity,
                    onUf: (uf) => _propState = uf,
                    keys: const [
                      'propertyAddress', 'propertyNeighborhood',
                      'propertyCity', 'propertyState',
                    ],
                  )),
        ),
        _tf('propertyAddress', 'Endereço', _propAddress),
        _Row2(
          leftFlex: 2,
          rightFlex: 3,
          left: _tf('propertyNumber', 'Número', _propNumber),
          right: _tf('', 'Complemento', _propComplement, req: false, na: false),
        ),
        _tf('propertyNeighborhood', 'Bairro', _propNeighborhood),
        _Row2(
          leftFlex: 3,
          rightFlex: 2,
          left: _tf('propertyCity', 'Cidade', _propCity),
          right: _ufField('propertyState', _propState, (v) => _propState = v),
        ),
        const SizedBox(height: 6),
      ];

  List<Widget> _sectionEmpreendimento() => [
        _Band('EMPREENDIMENTO', LucideIcons.building2),
        _Row2(
          left: _tf('incorporadora', 'Incorporadora', _empIncorporadora),
          right: _tf('empreendimento', 'Empreendimento', _empNome),
        ),
        _Row2(
          left: _tf('unidade', 'Unidade', _empUnidade,
              hint: 'Ex: Bloco 1, Apto 101'),
          right: _dateField('dataEntrada', 'Data da entrada', _empDataEntrada),
        ),
        _Row2(
          left: _tf('valorEntrada', 'Valor entrada', _empValorEntrada,
              money: true),
          right: _tf('formaPagamento', 'Forma de pagamento', _empFormaPagamento),
        ),
        const SizedBox(height: 6),
      ];

  List<Widget> _sectionFinanceiro() {
    final naoAplicavel = _commissionModel == CommissionPaymentModel.naoAplicavel;
    return [
      _Band('VALORES FINANCEIROS', LucideIcons.dollarSign),
      ..._pergunta(
        'Modelo de pagamento da comissão',
        required: !naoAplicavel,
        opcoes: const [('obrigatorio', 'Obrigatório'), ('nao', 'Não aplicável')],
        value: naoAplicavel ? 'nao' : 'obrigatorio',
        onChanged: (v) => setState(() {
          _commissionModel = v == 'nao'
              ? CommissionPaymentModel.naoAplicavel
              : CommissionPaymentModel.obrigatorio;
          if (v == 'nao') {
            // Web: "Não aplicável" desliga o parcelamento.
            _parcelado = false;
            _parcelasQtd.clear();
            _parcelasIguais = true;
            for (final c in _parcelas) {
              c.clear();
            }
            for (final k in const [
              'commissionPaymentModelDescription', 'totalCommission',
              'goalValue', 'commissionInstallmentsCount',
              'commissionInstallmentValues',
            ]) {
              _errors.remove(k);
            }
          }
        }),
      ),
      if (!naoAplicavel)
        _tf(
          'commissionPaymentModelDescription',
          'Descrição do modelo de pagamento',
          _commissionDesc,
          na: false,
          maxLines: 3,
          hint: 'Parcelamento, regras acordadas com incorporadora, etc.',
        ),
      _tf('saleValue', 'Valor da venda', _saleValue, money: true),
      _Row2(
        left: _tf('totalCommission', 'Comissão total', _totalCommission,
            req: !naoAplicavel,
            money: true,
            onChanged: (_) => setState(() {})),
        right: _tf('goalValue', 'Valor da meta', _goalValue,
            req: !naoAplicavel, money: true),
      ),
      const SizedBox(height: 4),
      ..._pergunta(
        'A imobiliária paga a confissão de dívida?',
        opcoes: const [('sim', 'Sim'), ('nao', 'Não')],
        value: _debtConfession == null ? null : (_debtConfession! ? 'sim' : 'nao'),
        errorKey: 'debtConfession',
        onChanged: (v) => setState(() {
          _debtConfession = v == 'sim';
          if (v != 'sim') {
            _debtConfessionValue.clear();
            _errors.remove('debtConfessionValue');
          }
        }),
      ),
      if (_debtConfession == true)
        _tf('debtConfessionValue', 'Valor da confissão de dívida',
            _debtConfessionValue,
            na: false, money: true),
      ..._pergunta(
        'Financiamento é 100%?',
        opcoes: const [('sim', 'Sim'), ('nao', 'Não')],
        value: _fullFinancing == null ? null : (_fullFinancing! ? 'sim' : 'nao'),
        errorKey: 'fullFinancing',
        onChanged: (v) => setState(() => _fullFinancing = v == 'sim'),
      ),
      if (!naoAplicavel) ..._secaoParcelamento(),
      const SizedBox(height: 6),
    ];
  }

  List<Widget> _secaoParcelamento() {
    final q = _qtdParcelas;
    final total = saleFormNumeric(_totalCommission.text);
    final valido = q >= 2 && q <= kSaleFormMaxParcelas;
    final errValores = _errors['commissionInstallmentValues'];
    return [
      _SwitchRow(
        title: 'Comissão parcelada',
        hint:
            'Se a comissão for paga em parcelas, marque e informe a quantidade. A soma das parcelas deve bater com a Comissão Total.',
        value: _parcelado,
        onChanged: (on) => setState(() {
          _parcelado = on;
          if (!on) {
            _parcelasQtd.clear();
            _parcelasIguais = true;
            for (final c in _parcelas) {
              c.clear();
            }
          }
          _errors.remove('commissionInstallmentsCount');
          _errors.remove('commissionInstallmentValues');
        }),
      ),
      if (_parcelado) ...[
        const SizedBox(height: 12),
        _Field(
          label: 'Quantidade de parcelas',
          controller: _parcelasQtd,
          required: true,
          keyboard: TextInputType.number,
          digitsOnly: true,
          maxLength: 3,
          hint: 'Ex.: 3',
          errorText: _errors['commissionInstallmentsCount'],
          onChanged: (_) => setState(() {
            _syncParcelas();
            _errors.remove('commissionInstallmentsCount');
            _errors.remove('commissionInstallmentValues');
          }),
        ),
        _SwitchRow(
          title: 'Todas as parcelas com o mesmo valor',
          hint: _parcelasIguais && valido && total > 0
              ? '${q}x de ${_brl(total / q)} (calculado da Comissão Total)'
              : null,
          value: _parcelasIguais,
          onChanged: (v) => setState(() {
            _parcelasIguais = v;
            if (!v) _syncParcelas();
            _errors.remove('commissionInstallmentValues');
          }),
        ),
        if (!_parcelasIguais && valido) ...[
          const SizedBox(height: 12),
          for (var i = 0; i < q; i += 2)
            _Row2(
              left: _parcelaField(i),
              right: i + 1 < q ? _parcelaField(i + 1) : const SizedBox.shrink(),
            ),
          Builder(builder: (_) {
            final vals = [for (var i = 0; i < q; i++) _parcelas[i].text];
            final vivo = saleFormInstallmentValuesError(
                vals, q, _totalCommission.text);
            if (vivo != null || errValores != null) {
              return _ErrorLine(vivo ?? errValores!);
            }
            final soma =
                vals.fold<double>(0, (a, b) => a + saleFormNumeric(b));
            return _Helper(
                'Soma das parcelas: ${_brl(soma)} = Comissão Total: ${_brl(total)}');
          }),
        ],
      ],
      const SizedBox(height: 8),
    ];
  }

  Widget _parcelaField(int i) => _Field(
        label: 'Parcela ${i + 1}',
        controller: _parcelas[i],
        required: true,
        money: true,
        onChanged: (_) => setState(() {
          _errors.remove('commissionInstallmentValues');
        }),
      );

  List<Widget> _sectionColaboradores() => [
        _Band('COLABORADORES', LucideIcons.users),
        _Row2(
          left: _PickerField(
            label: 'Pré-atendimento',
            required: true,
            value: _displayNa(_preAtendimento),
            errorText: _errors['preAtendimento'],
            onTap: () => _pickColaborador(
                'preAtendimento', (v) => _preAtendimento = v),
          ),
          right: _PickerField(
            label: 'Central de captação',
            required: true,
            value: _displayNa(_centralCaptacao),
            errorText: _errors['centralCaptacao'],
            onTap: () => _pickColaborador(
                'centralCaptacao', (v) => _centralCaptacao = v),
          ),
        ),
        const SizedBox(height: 6),
      ];

  List<Widget> _sectionVincular() => [
        _Band('VINCULAR USUÁRIOS', LucideIcons.userPlus),
        _Helper(
            'Selecione os usuários que terão acesso a esta ficha. Você (criador) já está vinculado automaticamente.'),
        const SizedBox(height: 12),
        if (_linkedUsers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final u in _linkedUsers)
                  _UserChip(
                    name: u.name,
                    accent: _accent,
                    onRemove: () => setState(
                        () => _linkedUsers.removeWhere((x) => x.id == u.id)),
                  ),
              ],
            ),
          ),
        _AddButton(
          label: 'Adicionar usuário',
          accent: _accent,
          onTap: _pickLinkedUser,
        ),
        const SizedBox(height: 6),
      ];

  List<Widget> _sectionComissoes() => [
        _Band('COMISSÕES', LucideIcons.dollarSign),
        _Helper(
            'Registre cada participante. A mesma pessoa pode ter uma função de corretor/captador/SDR e uma de gerência.'),
        const SizedBox(height: 12),
        _tf('', 'Externo', _externalBrokerName,
            req: false,
            na: false,
            maxLength: 255,
            hint: 'Corretor não cadastrado no sistema'),
        for (var i = 0; i < _participants.length; i++)
          _ParticipantCard(
            index: i,
            participant: _participants[i],
            accent: _accent,
            funcoes: _funcoesDisponiveis,
            diretorPercent: _rules.diretorPercent,
            onPickUser: () => _pickParticipantUser(_participants[i]),
            onFuncao: (f) => setState(() {
              final p = _participants[i];
              final eraSdr = p.funcao == _Funcao.sdr;
              p.funcao = f;
              if (f == _Funcao.diretor) _aplicarPercentFixo(p);
              if (f == _Funcao.sdr) {
                p.fixo = false;
                p.valorFixo.text =
                    CurrencyInputFormatter.format(_kSdrValorFixo);
              } else if (eraSdr) {
                p.valorFixo.clear();
              }
              if (!f.escolheModo) p.fixo = false;
            }),
            onModo: (fixo) => setState(() => _participants[i].fixo = fixo),
            onEmitir: (v) => setState(() => _participants[i].emitirNota = v),
            onRemove: () => setState(() {
              _participants[i].dispose();
              _participants.removeAt(i);
            }),
          ),
        const SizedBox(height: 8),
        _AddButton(
          label: 'Adicionar participante',
          accent: _accent,
          onTap: () => setState(() => _participants.add(_Participant())),
        ),
        const SizedBox(height: 6),
      ];

  List<Widget> _sectionObservacoes() => [
        _Band('OBSERVAÇÕES', LucideIcons.notebookPen),
        _tf('', 'Observações gerais', _notes,
            req: false,
            na: false,
            maxLines: 8,
            hint: 'Informações adicionais, condições especiais…'),
        _Helper('Opcional. Entra na ficha junto com a descrição.'),
        const SizedBox(height: 6),
      ];

  // ── Pickers ─────────────────────────────────────────────────────────────

  Future<void> _pickParticipantUser(_Participant p) async {
    final u = await _showUserPicker();
    if (u is AdminUser) {
      setState(() {
        p.userId = u.id;
        p.userName = u.name;
      });
    }
  }

  Future<void> _pickLinkedUser() async {
    if (_linkedUsers.length >= _kMaxVinculados) {
      _toast('Máximo de $_kMaxVinculados usuários vinculados.', error: true);
      return;
    }
    final u = await _showUserPicker();
    if (u is AdminUser && _linkedUsers.every((x) => x.id != u.id)) {
      setState(() => _linkedUsers
          .add(SaleFormPessoa(id: u.id, name: u.name, email: u.email)));
    }
  }

  Future<void> _pickColaborador(String key, ValueChanged<String> set) async {
    final r = await _showUserPicker(allowNa: true);
    if (r == null) return;
    setState(() {
      set(r is AdminUser ? r.name : kSaleFormNa);
      _errors.remove(key);
    });
  }

  Future<void> _pickGestor() async {
    final r = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PessoaPickerSheet(
        accent: _accent,
        titulo: 'Nome do gerente',
        future: _gestoresFuture,
        atual: _managerName,
      ),
    );
    if (r == null) return;
    setState(() {
      _managerName = r is SaleFormPessoa ? r.name : kSaleFormNa;
      _errors.remove('managerName');
    });
  }

  Future<void> _pickSharedUnits(List<OrgUnit> opcoes) async {
    final r = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UnidadesSheet(
        accent: _accent,
        unidades: opcoes,
        selecionadas: _sharedUnitIds.toSet(),
      ),
    );
    if (r == null) return;
    setState(() {
      _sharedUnitIds
        ..clear()
        ..addAll(r);
    });
  }

  /// Devolve [AdminUser] ou [kSaleFormNa] (quando [allowNa]).
  Future<Object?> _showUserPicker({bool allowNa = false}) {
    return showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UserPickerSheet(accent: _accent, allowNa: allowNa),
    );
  }
}

/// Cabeçalho do passo — ícone tonal na cor da marca + título + "Passo X de N"
/// + barra de progresso, e uma linha discreta de tipo/equipe.
class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.index,
    required this.total,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.typeLabel,
    required this.teamName,
  });
  final int index;
  final int total;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String typeLabel;
  final String teamName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final frac = (index + 1) / total;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        // Flush: sem caixa tingida — só um sublinhado na cor da marca
        // (ecoa o indicador de TabBar do app). Ver dreamkeysapp-flush-design.
        color: Colors.transparent,
        border: Border(
          bottom: BorderSide(color: color.withValues(alpha: 0.7), width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.22 : 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.3,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Passo ${index + 1} de $total · $subtitle',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 4,
              backgroundColor:
                  ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(LucideIcons.handshake, size: 12, color: muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$typeLabel · $teamName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
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

// ─── Widgets de formulário ──────────────────────────────────────────────────

class _Band extends StatelessWidget {
  const _Band(this.title, this.icon);
  final String title;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 14, color: muted),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: ThemeHelpers.textColor(context),
                letterSpacing: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniLabel extends StatelessWidget {
  const _MiniLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
          color: ThemeHelpers.textSecondaryColor(context),
        ),
      ),
    );
  }
}

/// Texto de apoio discreto (mesma voz do `HelperText` do web).
class _Helper extends StatelessWidget {
  const _Helper(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          height: 1.35,
          fontWeight: FontWeight.w500,
          color: ThemeHelpers.textSecondaryColor(context),
        ),
      ),
    );
  }
}

/// Erro fora de um input (perguntas sim/não, soma das parcelas).
class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: AppColors.status.error,
        ),
      ),
    );
  }
}

/// Chip "N/A" no canto do campo: marca "Não aplicável" (o campo trava e
/// mostra o texto); tocar de novo desmarca. Só aparece com o campo vazio ou
/// já marcado — digitou um valor, ele sai do caminho.
class _NaChip extends StatelessWidget {
  const _NaChip({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Tooltip(
      message: active ? 'Desmarcar Não aplicável' : 'Marcar como Não aplicável',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 8, 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: active ? accent.withValues(alpha: 0.14) : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: active
                    ? accent.withValues(alpha: 0.55)
                    : ThemeHelpers.borderColor(context).withValues(alpha: 0.8),
              ),
            ),
            child: Text(
              'N/A',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: active ? accent : muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.required = false,
    this.allowNa = false,
    this.maxLines = 1,
    this.keyboard,
    this.money = false,
    this.digitsOnly = false,
    this.mask = SaleFormMask.none,
    this.maxLength,
    this.hint,
    this.helper,
    this.errorText,
    this.onChanged,
  });
  final String label;
  final TextEditingController controller;
  final bool required;
  final bool allowNa;
  final int maxLines;
  final TextInputType? keyboard;
  final bool money;
  final bool digitsOnly;
  final SaleFormMask mask;
  final int? maxLength;
  final String? hint;
  final String? helper;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    // Visual (filled, borda, foco, erro) herdado do _formTheme.
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final isNa = isSaleFormNa(value.text);
          final muted = ThemeHelpers.textSecondaryColor(context);
          final showChip = allowNa && (value.text.isEmpty || isNa);
          return TextField(
            controller: controller,
            readOnly: isNa && allowNa,
            minLines: 1,
            maxLines: maxLines,
            maxLength: maxLength,
            keyboardType: money || digitsOnly ? TextInputType.number : keyboard,
            inputFormatters: money
                ? [CurrencyInputFormatter()]
                : digitsOnly
                    ? [FilteringTextInputFormatter.digitsOnly]
                    : [SaleFormFieldFormatter(mask)],
            onChanged: onChanged,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isNa ? muted : null,
                  fontStyle: isNa ? FontStyle.italic : null,
                ),
            decoration: InputDecoration(
              labelText: required ? '$label *' : label,
              hintText: hint,
              helperText: helper,
              helperMaxLines: 3,
              errorText: errorText,
              counterText: maxLength != null ? '' : null,
              prefixText: money && !isNa ? 'R\$ ' : null,
              suffixIcon: showChip
                  ? _NaChip(
                      active: isNa,
                      onTap: () {
                        controller.text = isNa ? '' : kSaleFormNa;
                        onChanged?.call(controller.text);
                      },
                    )
                  : null,
              suffixIconConstraints:
                  const BoxConstraints(minWidth: 0, minHeight: 0),
            ),
          );
        },
      ),
    );
  }
}

class _Row2 extends StatelessWidget {
  const _Row2({
    required this.left,
    required this.right,
    this.leftFlex = 1,
    this.rightFlex = 1,
  });
  final Widget left;
  final Widget right;
  final int leftFlex;
  final int rightFlex;
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: leftFlex, child: left),
        const SizedBox(width: 12),
        Expanded(flex: rightFlex, child: right),
      ],
    );
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.required = false,
    this.allowNa = false,
    this.labels = const {},
    this.errorText,
  });
  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  final bool required;

  /// Opção "― Não aplicável ―" no topo (valor "Não aplicável").
  final bool allowNa;

  /// Rótulo de exibição por valor (ex.: "(indisponível)").
  final Map<String, String> labels;
  final String? errorText;
  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final items = <DropdownMenuItem<String>>[
      if (allowNa)
        DropdownMenuItem(
          value: kSaleFormNa,
          child: Text(
            kSaleFormNaSelectLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: muted, fontStyle: FontStyle.italic),
          ),
        ),
      for (final o in options)
        DropdownMenuItem(
          value: o,
          child: Text(labels[o] ?? o,
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
    ];
    final v = value != null && items.any((i) => i.value == value) ? value : null;
    // Mesmo visual filled dos campos (herda _formTheme) — selects coesos.
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        // A chave força recriar quando o valor muda por fora (ex.: CEP).
        key: ValueKey('$label|$v'),
        initialValue: v,
        isExpanded: true,
        icon: Icon(LucideIcons.chevronDown, size: 18, color: muted),
        borderRadius: BorderRadius.circular(14),
        dropdownColor: ThemeHelpers.cardBackgroundColor(context),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: ThemeHelpers.textColor(context),
            ),
        items: items,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          errorText: errorText,
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    this.required = false,
    this.na = false,
    this.onNa,
    this.errorText,
  });
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final bool required;
  final bool na;

  /// Alterna "Não aplicável" (null = campo não aceita N/A).
  final VoidCallback? onNa;
  final String? errorText;
  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: na ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: InputDecorator(
          // Visual filled herdado do _formTheme (igual aos campos).
          decoration: InputDecoration(
            labelText: required ? '$label *' : label,
            errorText: errorText,
            suffixIcon: onNa != null && (na || value == null)
                ? _NaChip(active: na, onTap: onNa!)
                : Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(LucideIcons.calendar, size: 16, color: muted),
                  ),
            suffixIconConstraints:
                const BoxConstraints(minWidth: 0, minHeight: 0),
          ),
          child: Text(
            na
                ? kSaleFormNa
                : value != null
                    ? DateFormat('dd/MM/yyyy', 'pt_BR').format(value!)
                    : 'Selecionar',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontStyle: na ? FontStyle.italic : null,
              color: value != null && !na
                  ? ThemeHelpers.textColor(context)
                  : muted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Campo que abre um seletor (gerente, colaboradores, unidades) — mesmo
/// visual dos inputs; "― Não aplicável ―" é opção dentro do seletor.
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.onTap,
    this.required = false,
    this.placeholder = 'Selecionar',
    this.errorText,
  });
  final String label;
  final String? value;
  final VoidCallback onTap;
  final bool required;
  final String placeholder;
  final String? errorText;
  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final isNa = isSaleFormNa(value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: required ? '$label *' : label,
            errorText: errorText,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value ?? placeholder,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontStyle: isNa ? FontStyle.italic : null,
                    color: value != null && !isNa
                        ? ThemeHelpers.textColor(context)
                        : muted,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(LucideIcons.chevronDown, size: 16, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Linha com interruptor (cônjuge/sócio, parcelamento, contrato).
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.hint,
  });
  final String title;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              if (hint != null) ...[
                const SizedBox(height: 2),
                Text(
                  hint!,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                    color: muted,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.5)
                : ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: selected ? accent : ThemeHelpers.textSecondaryColor(context),
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.label, required this.accent, required this.onTap});
  final String label;
  final Color accent;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.plus, size: 15, color: accent),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: accent, fontWeight: FontWeight.w800, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserChip extends StatelessWidget {
  const _UserChip(
      {required this.name, required this.accent, required this.onRemove});
  final String name;
  final Color accent;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              name.split(' ').first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: accent, fontWeight: FontWeight.w800, fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 5),
          GestureDetector(
            onTap: onRemove,
            child: Icon(LucideIcons.x, size: 14, color: accent),
          ),
        ],
      ),
    );
  }
}

class _ParticipantCard extends StatelessWidget {
  const _ParticipantCard({
    required this.index,
    required this.participant,
    required this.accent,
    required this.funcoes,
    required this.diretorPercent,
    required this.onPickUser,
    required this.onFuncao,
    required this.onModo,
    required this.onEmitir,
    required this.onRemove,
  });
  final int index;
  final _Participant participant;
  final Color accent;

  /// Funções habilitadas pelas regras da empresa (a atual entra mesmo que
  /// a empresa tenha desligado a função depois — ficha antiga continua legível).
  final List<_Funcao> funcoes;

  /// % fixa do diretor (regras da empresa); `null` = empresa não usa diretor.
  final double? diretorPercent;
  final VoidCallback onPickUser;
  final ValueChanged<_Funcao> onFuncao;

  /// Corretor/captador/outros: `true` = valor fixo (R$), `false` = %.
  final ValueChanged<bool> onModo;
  final ValueChanged<bool> onEmitir;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = participant;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final isSdr = p.funcao == _Funcao.sdr;
    final isDiretor = p.funcao == _Funcao.diretor;
    final emReais = isSdr || (p.funcao.escolheModo && p.fixo);
    final opcoes = [
      ...funcoes,
      if (!funcoes.contains(p.funcao)) p.funcao,
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onPickUser,
                  child: Row(
                    children: [
                      Icon(LucideIcons.userPlus, size: 16, color: accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          p.userId == null ? 'Selecionar usuário *' : p.userName,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: p.userId == null
                                ? muted
                                : ThemeHelpers.textColor(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              GestureDetector(
                onTap: onRemove,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(LucideIcons.trash2, size: 16, color: muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final f in opcoes)
                GestureDetector(
                  onTap: () => onFuncao(f),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      color: p.funcao == f
                          ? accent.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: p.funcao == f
                            ? accent.withValues(alpha: 0.5)
                            : ThemeHelpers.borderColor(context)
                                .withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      f.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: p.funcao == f ? accent : muted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (p.funcao.escolheModo) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _Choice(
                    label: 'Percentual',
                    selected: !p.fixo,
                    accent: accent,
                    onTap: () => onModo(false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Choice(
                    label: 'Valor fixo',
                    selected: p.fixo,
                    accent: accent,
                    onTap: () => onModo(true),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            key: ValueKey('${p.funcao.api}-$emReais'),
            controller: emReais ? p.valorFixo : p.percent,
            // SDR (valor da empresa) e diretor (% da empresa): só mostram.
            readOnly: isDiretor || isSdr,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: emReais
                ? [CurrencyInputFormatter()]
                : [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDiretor || isSdr ? muted : null,
                ),
            decoration: InputDecoration(
              labelText: isSdr
                  ? 'Valor fixo'
                  : emReais
                      ? 'Valor fixo (R\$)'
                      : isDiretor
                          ? 'Porcentagem fixa (%)'
                          : 'Porcentagem (%)',
              prefixText: emReais ? 'R\$ ' : null,
              helperText: isSdr
                  ? 'Valor fixo pela empresa.'
                  : isDiretor
                      ? (diretorPercent != null
                          ? 'Definida nas regras de comissão da empresa.'
                          : 'A empresa não usa comissão de diretor.')
                      : null,
              suffixIcon: isDiretor || isSdr
                  ? Icon(LucideIcons.lock, size: 16, color: muted)
                  : null,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Contrato de intermediação?',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, color: muted),
                ),
              ),
              Switch(value: p.emitirNota, onChanged: onEmitir),
            ],
          ),
        ],
      ),
    );
  }
}

/// Moldura comum das folhas de seleção: altura máxima, alça, teclado.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.8),
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(18, 10, 18, 14 + mq.padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: ThemeHelpers.borderColor(context),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Linha "― Não aplicável ―" das folhas de seleção.
class _NaTile extends StatelessWidget {
  const _NaTile({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: ThemeHelpers.borderColor(context).withValues(alpha: 0.4),
        child: Icon(LucideIcons.ban, size: 15, color: muted),
      ),
      title: Text(
        kSaleFormNaSelectLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontWeight: FontWeight.w700, fontStyle: FontStyle.italic, color: muted),
      ),
      subtitle: const Text('Sem informação no cadastro',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}

Widget _avatar(Color accent, String name) => CircleAvatar(
      radius: 16,
      backgroundColor: accent.withValues(alpha: 0.15),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
            color: accent, fontWeight: FontWeight.w900, fontSize: 13),
      ),
    );

/// Sheet de seleção de usuário (participantes, colaboradores e vincular).
/// Devolve [AdminUser] ou [kSaleFormNa] (quando [allowNa]).
class _UserPickerSheet extends StatefulWidget {
  const _UserPickerSheet({required this.accent, this.allowNa = false});
  final Color accent;
  final bool allowNa;
  @override
  State<_UserPickerSheet> createState() => _UserPickerSheetState();
}

class _UserPickerSheetState extends State<_UserPickerSheet> {
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  List<AdminUser> _users = [];
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await AdminUsersService.instance.listUsers(
      limit: 100,
      search: _q.isEmpty ? null : _q,
      compact: true,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _users = res.data!.users;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return _SheetFrame(
      children: [
        TextField(
          controller: _searchCtrl,
          textInputAction: TextInputAction.search,
          onSubmitted: (v) {
            _q = v.trim();
            _load();
          },
          decoration: InputDecoration(
            hintText: 'Buscar colaborador por nome ou e-mail…',
            prefixIcon: const Icon(LucideIcons.search, size: 18),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 10),
        if (widget.allowNa)
          _NaTile(onTap: () => Navigator.of(context).pop(kSaleFormNa)),
        Flexible(
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _users.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text('Nenhum usuário encontrado.',
                          style: TextStyle(color: secondary)),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _users.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 4),
                      itemBuilder: (_, i) {
                        final u = _users[i];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: _avatar(widget.accent, u.name),
                          title: Text(u.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(u.email,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => Navigator.of(context).pop(u),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

/// Seleção de gestor ("Nome do Gerente" do web): gestores da empresa +
/// "― Não aplicável ―". Devolve [SaleFormPessoa] ou [kSaleFormNa].
class _PessoaPickerSheet extends StatefulWidget {
  const _PessoaPickerSheet({
    required this.accent,
    required this.titulo,
    required this.future,
    required this.atual,
  });
  final Color accent;
  final String titulo;
  final Future<List<SaleFormPessoa>> future;

  /// Valor atual (ficha antiga com nome fora da lista continua escolhível).
  final String atual;
  @override
  State<_PessoaPickerSheet> createState() => _PessoaPickerSheetState();
}

class _PessoaPickerSheetState extends State<_PessoaPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return _SheetFrame(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            widget.titulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: ThemeHelpers.textColor(context),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
          decoration: InputDecoration(
            hintText: 'Buscar gestor…',
            prefixIcon: const Icon(LucideIcons.search, size: 18),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 10),
        _NaTile(onTap: () => Navigator.of(context).pop(kSaleFormNa)),
        Flexible(
          child: FutureBuilder<List<SaleFormPessoa>>(
            future: widget.future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final todos = [...(snap.data ?? const <SaleFormPessoa>[])];
              final atual = widget.atual.trim();
              if (atual.isNotEmpty &&
                  !isSaleFormNa(atual) &&
                  todos.every((g) => g.name != atual)) {
                todos.insert(0, SaleFormPessoa(id: '', name: atual));
              }
              final lista = _q.isEmpty
                  ? todos
                  : todos
                      .where((g) =>
                          g.name.toLowerCase().contains(_q) ||
                          g.email.toLowerCase().contains(_q))
                      .toList();
              if (lista.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text('Nenhum gestor encontrado.',
                      style: TextStyle(color: secondary)),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                itemCount: lista.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (_, i) {
                  final g = lista[i];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: _avatar(widget.accent, g.name),
                    title: Text(g.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: g.email.isEmpty
                        ? null
                        : Text(g.email,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: g.name == atual
                        ? Icon(LucideIcons.check, size: 16, color: widget.accent)
                        : null,
                    onTap: () => Navigator.of(context).pop(g),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// "Compartilhar com outras unidades" (várias). Devolve os ids marcados.
class _UnidadesSheet extends StatefulWidget {
  const _UnidadesSheet({
    required this.accent,
    required this.unidades,
    required this.selecionadas,
  });
  final Color accent;
  final List<OrgUnit> unidades;
  final Set<String> selecionadas;
  @override
  State<_UnidadesSheet> createState() => _UnidadesSheetState();
}

class _UnidadesSheetState extends State<_UnidadesSheet> {
  late final Set<String> _sel = {...widget.selecionadas};

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return _SheetFrame(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Compartilhar com outras unidades',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: ThemeHelpers.textColor(context),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Opcional. Os gestores dessas unidades também poderão ver a ficha.',
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final u in widget.unidades)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: widget.accent,
                  value: _sel.contains(u.id),
                  title: Text(u.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _sel.add(u.id);
                    } else {
                      _sel.remove(u.id);
                    }
                  }),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(_sel.toList()),
            style: FilledButton.styleFrom(
              backgroundColor: widget.accent,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Concluir',
                style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ),
      ],
    );
  }
}
