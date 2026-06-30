import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/utils/input_formatters.dart';
import '../../../features/workspace/models/admin_user_model.dart';
import '../../../features/workspace/services/admin_users_service.dart';
import '../../../shared/services/sale_forms_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
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

enum _Funcao { corretor, captador, sdr, gerencia }

extension _FuncaoX on _Funcao {
  String get label => switch (this) {
        _Funcao.corretor => 'Corretor',
        _Funcao.captador => 'Captador',
        _Funcao.sdr => 'SDR',
        _Funcao.gerencia => 'Gerência',
      };
  String get api => switch (this) {
        _Funcao.corretor => 'corretor',
        _Funcao.captador => 'captador',
        _Funcao.sdr => 'sdr',
        _Funcao.gerencia => 'gerencia',
      };
}

class _Participant {
  String? userId;
  String userName = '';
  _Funcao funcao = _Funcao.corretor;
  final TextEditingController percent = TextEditingController();
  final TextEditingController valorFixo = TextEditingController();
  bool emitirNota = false;
  void dispose() {
    percent.dispose();
    valorFixo.dispose();
  }
}

/// Formulário de criação/edição de ficha de venda.
/// Criar: abra via [showSaleFormTypeModal] e passe [choice].
/// Editar: passe [saleFormId] (tipo/equipe vêm da ficha carregada).
class CreateSaleFormPage extends StatefulWidget {
  const CreateSaleFormPage({super.key, this.choice, this.saleFormId})
      : assert(choice != null || saleFormId != null,
            'Informe choice (criar) ou saleFormId (editar).');
  final SaleFormTypeChoice? choice;
  final String? saleFormId;

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
  // Geral
  DateTime? _saleDate;
  String? _mediaSource;
  final _saleUnit = TextEditingController();
  bool? _secretaryPresent;
  bool _generalGroup = false;
  final _managerName = TextEditingController();
  final _externalBrokerName = TextEditingController();
  final _description = TextEditingController();

  // Comprador
  final _buyerName = TextEditingController();
  final _buyerCpf = TextEditingController();
  final _buyerRg = TextEditingController();
  DateTime? _buyerBirth;
  final _buyerEmail = TextEditingController();
  final _buyerPhone = TextEditingController();
  final _buyerProfession = TextEditingController();
  final _buyerZip = TextEditingController();
  final _buyerStreet = TextEditingController();
  final _buyerNumber = TextEditingController();
  final _buyerComplement = TextEditingController();
  final _buyerNeighborhood = TextEditingController();
  final _buyerCity = TextEditingController();
  String? _buyerState;

  // Cônjuge comprador
  bool _hasBuyerSpouse = false;
  final _buyerSpouseName = TextEditingController();
  final _buyerSpouseCpf = TextEditingController();
  final _buyerSpouseRg = TextEditingController();
  final _buyerSpouseProfession = TextEditingController();
  final _buyerSpouseEmail = TextEditingController();
  final _buyerSpousePhone = TextEditingController();

  // Vendedor
  final _sellerName = TextEditingController();
  final _sellerCpf = TextEditingController();
  final _sellerRg = TextEditingController();
  DateTime? _sellerBirth;
  final _sellerEmail = TextEditingController();
  final _sellerPhone = TextEditingController();
  final _sellerProfession = TextEditingController();
  final _sellerZip = TextEditingController();
  final _sellerStreet = TextEditingController();
  final _sellerNumber = TextEditingController();
  final _sellerComplement = TextEditingController();
  final _sellerNeighborhood = TextEditingController();
  final _sellerCity = TextEditingController();
  String? _sellerState;

  // Cônjuge vendedor
  bool _hasSellerSpouse = false;
  final _sellerSpouseName = TextEditingController();
  final _sellerSpouseCpf = TextEditingController();
  final _sellerSpouseRg = TextEditingController();
  final _sellerSpouseProfession = TextEditingController();
  final _sellerSpouseEmail = TextEditingController();
  final _sellerSpousePhone = TextEditingController();

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
  DateTime? _empDataEntrada;

  // Financeiro
  final _saleValue = TextEditingController();
  final _totalCommission = TextEditingController();
  final _goalValue = TextEditingController();
  CommissionPaymentModel _commissionModel = CommissionPaymentModel.obrigatorio;
  final _commissionDesc = TextEditingController();

  // Comissões
  final List<_Participant> _participants = [];

  // Vincular usuários
  final List<AdminUser> _linkedUsers = [];

  bool _saving = false;
  final _scroll = ScrollController();

  bool get _isEmpreendimento => _type.isEmpreendimento;

  Color get _brand => Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;

  /// Cor de acento do passo = **vermelho da marca**, coerente com TODO o app
  /// (Documentos/Chaves/listagem usam `AppColors.primary`). Sem paleta por passo
  /// (arco-íris não tinha sentido): a identidade de cada etapa vem do ícone +
  /// "Passo X de N" + barra de progresso. Mantido como ponto único caso um dia
  /// se queira variar por etapa.
  Color _stepColor(int i) => _brand;

  Color get _accent => _brand;

  /// Tema local dos campos do formulário — visual filled, leve e fluido, com
  /// foco/cursor/seleção na cor do passo. Centraliza o estilo (inputs E selects
  /// ficam idênticos) e dá coerência de cor por etapa.
  ThemeData _formTheme(BuildContext context) {
    final base = Theme.of(context);
    final isDark = base.brightness == Brightness.dark;
    final fill = isDark
        ? Colors.white.withValues(alpha: 0.045)
        : Colors.black.withValues(alpha: 0.025);
    final muted = ThemeHelpers.textSecondaryColor(context);
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
        border: b(Colors.transparent, 0),
        enabledBorder: b(Colors.transparent, 0),
        focusedBorder: b(_accent, 1.6),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _type = widget.choice?.type ?? SaleFormType.terceiros;
    _teamId = widget.choice?.teamId ?? '';
    _teamName = widget.choice?.teamName ?? '';
    if (_isEdit) _loadExisting();
  }

  Future<void> _loadExisting() async {
    setState(() => _loadingExisting = true);
    final res = await SaleFormsService.instance.getById(widget.saleFormId!);
    if (!mounted) return;
    setState(() {
      _loadingExisting = false;
      if (res.success && res.data != null) {
        _prefill(res.data!);
      }
    });
  }

  void _prefill(SaleForm f) {
    final r = f.raw;
    String sv(String k) => (r[k] ?? '').toString();
    String moneyText(num? v) => CurrencyInputFormatter.format(v);

    _type = f.saleFormType;
    _teamId = f.teamId ?? '';
    _teamName = f.teamName ?? '';

    // Geral
    _saleDate = f.saleDate;
    final ms = f.mediaSource;
    if (ms != null && _kMediaSources.contains(ms)) _mediaSource = ms;
    _saleUnit.text = f.saleUnit ?? '';
    final sp = sv('secretaryPresent');
    if (sp.isNotEmpty) _secretaryPresent = sp.toLowerCase() == 'sim';
    _generalGroup = r['generalGroup'] == true;
    _managerName.text = sv('managerName');
    _externalBrokerName.text = sv('externalBrokerName');
    _description.text = f.description ?? '';

    // Comprador
    _buyerName.text = sv('buyerName');
    _buyerCpf.text = sv('buyerCpf');
    _buyerRg.text = sv('buyerRg');
    _buyerBirth = _parseD(r['buyerBirthDate']);
    _buyerEmail.text = sv('buyerEmail');
    _buyerPhone.text = sv('buyerPhone');
    _buyerProfession.text = sv('buyerProfession');
    _buyerZip.text = sv('buyerZipCode');
    _buyerStreet.text = sv('buyerStreet');
    _buyerNumber.text = sv('buyerNumber');
    _buyerComplement.text = sv('buyerComplement');
    _buyerNeighborhood.text = sv('buyerNeighborhood');
    _buyerCity.text = sv('buyerCity');
    if (_kUfs.contains(sv('buyerState'))) _buyerState = sv('buyerState');

    // Cônjuge comprador
    _buyerSpouseName.text = sv('buyerSpouseName');
    _buyerSpouseCpf.text = sv('buyerSpouseCpf');
    _buyerSpouseRg.text = sv('buyerSpouseRg');
    _buyerSpouseProfession.text = sv('buyerSpouseProfession');
    _buyerSpouseEmail.text = sv('buyerSpouseEmail');
    _buyerSpousePhone.text = sv('buyerSpousePhone');
    _hasBuyerSpouse = _buyerSpouseName.text.isNotEmpty;

    // Vendedor
    _sellerName.text = sv('sellerName');
    _sellerCpf.text = sv('sellerCpf');
    _sellerRg.text = sv('sellerRg');
    _sellerBirth = _parseD(r['sellerBirthDate']);
    _sellerEmail.text = sv('sellerEmail');
    _sellerPhone.text = sv('sellerPhone');
    _sellerProfession.text = sv('sellerProfession');
    _sellerZip.text = sv('sellerZipCode');
    _sellerStreet.text = sv('sellerStreet');
    _sellerNumber.text = sv('sellerNumber');
    _sellerComplement.text = sv('sellerComplement');
    _sellerNeighborhood.text = sv('sellerNeighborhood');
    _sellerCity.text = sv('sellerCity');
    if (_kUfs.contains(sv('sellerState'))) _sellerState = sv('sellerState');

    // Cônjuge vendedor
    _sellerSpouseName.text = sv('sellerSpouseName');
    _sellerSpouseCpf.text = sv('sellerSpouseCpf');
    _sellerSpouseRg.text = sv('sellerSpouseRg');
    _sellerSpouseProfession.text = sv('sellerSpouseProfession');
    _sellerSpouseEmail.text = sv('sellerSpouseEmail');
    _sellerSpousePhone.text = sv('sellerSpousePhone');
    _hasSellerSpouse = _sellerSpouseName.text.isNotEmpty;

    // Imóvel
    _propCode.text = f.propertyCode ?? '';
    _propZip.text = sv('propertyZipCode');
    _propAddress.text = sv('propertyAddress');
    _propNumber.text = sv('propertyNumber');
    _propComplement.text = sv('propertyComplement');
    _propNeighborhood.text = sv('propertyNeighborhood');
    _propCity.text = sv('propertyCity');
    if (_kUfs.contains(sv('propertyState'))) _propState = sv('propertyState');

    // Empreendimento
    final emp = f.empreendimentoData;
    if (emp != null) {
      _empIncorporadora.text = (emp['incorporadora'] ?? '').toString();
      _empNome.text = (emp['empreendimento'] ?? '').toString();
      _empUnidade.text = (emp['unidade'] ?? '').toString();
      _empFormaPagamento.text = (emp['formaPagamento'] ?? '').toString();
      _empDataEntrada = _parseD(emp['dataEntrada']);
      final ve = emp['valorEntrada'];
      _empValorEntrada.text = ve is num ? moneyText(ve) : '';
    }

    // Financeiro
    _saleValue.text = moneyText(f.saleValue);
    _totalCommission.text = moneyText(f.totalCommission);
    _goalValue.text = moneyText(f.goalValue);
    _commissionModel = f.commissionPaymentModel;
    _commissionDesc.text = sv('commissionPaymentModelDescription');

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
        if (p.funcao == _Funcao.sdr) {
          final vf = c['valorFixo'];
          p.valorFixo.text = vf is num ? moneyText(vf) : '';
        } else {
          final pc = c['porcentagem'];
          p.percent.text = pc is num ? pc.toString() : '';
        }
        _participants.add(p);
      }
      for (final g in (cd['gerencias'] as List? ?? const [])) {
        if (g is! Map) continue;
        final p = _Participant();
        p.funcao = _Funcao.gerencia;
        p.userName = (g['nome'] ?? 'Gerência').toString();
        final pc = g['porcentagem'];
        p.percent.text = pc is num ? pc.toString() : '';
        p.emitirNota = g['emitirNota'] == true;
        _participants.add(p);
      }
    }
  }

  static DateTime? _parseD(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  static _Funcao _parseFuncao(String? s) {
    switch ((s ?? '').toLowerCase()) {
      case 'captador':
        return _Funcao.captador;
      case 'sdr':
        return _Funcao.sdr;
      case 'gerencia':
        return _Funcao.gerencia;
      default:
        return _Funcao.corretor;
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    for (final c in [
      _saleUnit, _managerName, _externalBrokerName, _description,
      _buyerName, _buyerCpf, _buyerRg, _buyerEmail, _buyerPhone,
      _buyerProfession, _buyerZip, _buyerStreet, _buyerNumber,
      _buyerComplement, _buyerNeighborhood, _buyerCity,
      _buyerSpouseName, _buyerSpouseCpf, _buyerSpouseRg, _buyerSpouseProfession,
      _buyerSpouseEmail, _buyerSpousePhone,
      _sellerName, _sellerCpf, _sellerRg, _sellerEmail, _sellerPhone,
      _sellerProfession, _sellerZip, _sellerStreet, _sellerNumber,
      _sellerComplement, _sellerNeighborhood, _sellerCity,
      _sellerSpouseName, _sellerSpouseCpf, _sellerSpouseRg,
      _sellerSpouseProfession, _sellerSpouseEmail, _sellerSpousePhone,
      _propCode, _propZip, _propAddress, _propNumber, _propComplement,
      _propNeighborhood, _propCity,
      _empIncorporadora, _empNome, _empUnidade, _empValorEntrada,
      _empFormaPagamento,
      _saleValue, _totalCommission, _goalValue, _commissionDesc,
    ]) {
      c.dispose();
    }
    for (final p in _participants) {
      p.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  static double? _money(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    // pt-BR: remove milhar (.) e usa vírgula como decimal.
    final cleaned = t.replaceAll(RegExp(r'[^\d,.-]'), '');
    final normalized = cleaned.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  static String _onlyDigits(String s) => s.replaceAll(RegExp(r'\D'), '');

  String _dateIso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String? _t(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  // ── Validação + payload ─────────────────────────────────────────────────

  String? _validate() {
    if (_buyerName.text.trim().isEmpty) return 'Informe o nome do comprador.';
    if (_mediaSource == null) return 'Selecione a mídia de origem.';
    if (_saleUnit.text.trim().isEmpty) return 'Informe a unidade de venda.';
    if (_description.text.trim().isEmpty) return 'Informe a descrição da ficha.';
    if (_commissionModel == CommissionPaymentModel.obrigatorio &&
        _commissionDesc.text.trim().isEmpty) {
      return 'Descreva o modelo de pagamento da comissão.';
    }
    for (final p in _participants) {
      if (p.userId == null) {
        return 'Selecione o usuário de cada participante da comissão.';
      }
    }
    return null;
  }

  Map<String, dynamic> _buildPayload() {
    final body = <String, dynamic>{
      'saleFormType': _type.apiValue,
      'teamId': _teamId,
      'mediaSource': _mediaSource,
      'saleUnit': _saleUnit.text.trim(),
      'description': _description.text.trim(),
      'generalGroup': _generalGroup,
      'buyerName': _buyerName.text.trim(),
      'commissionPaymentModel': _commissionModel == CommissionPaymentModel.naoAplicavel
          ? 'nao_aplicavel'
          : 'obrigatorio',
    };

    void put(String key, String? value) {
      if (value != null && value.isNotEmpty) body[key] = value;
    }

    if (_saleDate != null) body['saleDate'] = _dateIso(_saleDate!);
    if (_secretaryPresent != null) {
      body['secretaryPresent'] = _secretaryPresent! ? 'Sim' : 'Não';
    }
    put('managerName', _t(_managerName));
    put('externalBrokerName', _t(_externalBrokerName));

    // Comprador
    put('buyerCpf', _onlyDigits(_buyerCpf.text).isEmpty ? null : _onlyDigits(_buyerCpf.text));
    put('buyerRg', _t(_buyerRg));
    if (_buyerBirth != null) body['buyerBirthDate'] = _dateIso(_buyerBirth!);
    put('buyerEmail', _t(_buyerEmail));
    put('buyerPhone', _t(_buyerPhone));
    put('buyerProfession', _t(_buyerProfession));
    put('buyerZipCode', _t(_buyerZip));
    put('buyerStreet', _t(_buyerStreet));
    put('buyerNumber', _t(_buyerNumber));
    put('buyerComplement', _t(_buyerComplement));
    put('buyerNeighborhood', _t(_buyerNeighborhood));
    put('buyerCity', _t(_buyerCity));
    put('buyerState', _buyerState);

    // Cônjuge comprador
    if (_hasBuyerSpouse) {
      put('buyerSpouseName', _t(_buyerSpouseName));
      put('buyerSpouseCpf',
          _onlyDigits(_buyerSpouseCpf.text).isEmpty ? null : _onlyDigits(_buyerSpouseCpf.text));
      put('buyerSpouseRg', _t(_buyerSpouseRg));
      put('buyerSpouseProfession', _t(_buyerSpouseProfession));
      put('buyerSpouseEmail', _t(_buyerSpouseEmail));
      put('buyerSpousePhone', _t(_buyerSpousePhone));
    }

    // Vendedor
    put('sellerName', _t(_sellerName));
    put('sellerCpf', _onlyDigits(_sellerCpf.text).isEmpty ? null : _onlyDigits(_sellerCpf.text));
    put('sellerRg', _t(_sellerRg));
    if (_sellerBirth != null) body['sellerBirthDate'] = _dateIso(_sellerBirth!);
    put('sellerEmail', _t(_sellerEmail));
    put('sellerPhone', _t(_sellerPhone));
    put('sellerProfession', _t(_sellerProfession));
    put('sellerZipCode', _t(_sellerZip));
    put('sellerStreet', _t(_sellerStreet));
    put('sellerNumber', _t(_sellerNumber));
    put('sellerComplement', _t(_sellerComplement));
    put('sellerNeighborhood', _t(_sellerNeighborhood));
    put('sellerCity', _t(_sellerCity));
    put('sellerState', _sellerState);

    // Cônjuge vendedor
    if (_hasSellerSpouse) {
      put('sellerSpouseName', _t(_sellerSpouseName));
      put('sellerSpouseCpf',
          _onlyDigits(_sellerSpouseCpf.text).isEmpty ? null : _onlyDigits(_sellerSpouseCpf.text));
      put('sellerSpouseRg', _t(_sellerSpouseRg));
      put('sellerSpouseProfession', _t(_sellerSpouseProfession));
      put('sellerSpouseEmail', _t(_sellerSpouseEmail));
      put('sellerSpousePhone', _t(_sellerSpousePhone));
    }

    // Imóvel ou Empreendimento
    if (_isEmpreendimento) {
      final emp = <String, dynamic>{};
      void ePut(String k, String? v) {
        if (v != null && v.isNotEmpty) emp[k] = v;
      }
      ePut('incorporadora', _t(_empIncorporadora));
      ePut('empreendimento', _t(_empNome));
      ePut('unidade', _t(_empUnidade));
      ePut('formaPagamento', _t(_empFormaPagamento));
      if (_empDataEntrada != null) emp['dataEntrada'] = _dateIso(_empDataEntrada!);
      final ve = _money(_empValorEntrada.text);
      if (ve != null) emp['valorEntrada'] = ve;
      if (emp.isNotEmpty) body['empreendimentoData'] = emp;
    } else {
      put('propertyCode', _t(_propCode));
      put('propertyZipCode', _t(_propZip));
      put('propertyAddress', _t(_propAddress));
      put('propertyNumber', _t(_propNumber));
      put('propertyComplement', _t(_propComplement));
      put('propertyNeighborhood', _t(_propNeighborhood));
      put('propertyCity', _t(_propCity));
      put('propertyState', _propState);
    }

    // Financeiro
    final sv = _money(_saleValue.text);
    if (sv != null) body['saleValue'] = sv;
    final tc = _money(_totalCommission.text);
    if (tc != null) body['totalCommission'] = tc;
    final gv = _money(_goalValue.text);
    if (gv != null) body['goalValue'] = gv;
    if (_commissionModel == CommissionPaymentModel.obrigatorio) {
      put('commissionPaymentModelDescription', _t(_commissionDesc));
    }

    // Comissões
    final corretores = <Map<String, dynamic>>[];
    final gerencias = <Map<String, dynamic>>[];
    var nivel = 0;
    for (final p in _participants) {
      if (p.funcao == _Funcao.gerencia) {
        nivel++;
        gerencias.add({
          'nivel': nivel,
          'porcentagem': _money(p.percent.text) ?? 0,
          'nome': p.userName,
          'emitirNota': p.emitirNota,
        });
      } else {
        final m = <String, dynamic>{
          'id': p.userId,
          'funcao': p.funcao.api,
          'emitirNota': p.emitirNota,
        };
        if (p.funcao == _Funcao.sdr) {
          m['valorFixo'] = _money(p.valorFixo.text) ?? 0;
          m['porcentagem'] = 0;
        } else {
          m['porcentagem'] = _money(p.percent.text) ?? 0;
        }
        corretores.add(m);
      }
    }
    if (corretores.isNotEmpty || gerencias.isNotEmpty) {
      body['commissionsData'] = {
        if (corretores.isNotEmpty) 'corretores': corretores,
        if (gerencias.isNotEmpty) 'gerencias': gerencias,
      };
    }

    return body;
  }

  Future<void> _submit() async {
    final err = _validate();
    if (err != null) {
      _toast(err, error: true);
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
    // Vincular usuários (opcional) — não bloqueia o sucesso.
    final ids = _linkedUsers.map((u) => u.id).toList();
    if (ids.isNotEmpty) {
      await SaleFormsService.instance.addUsers(res.data!.id, ids);
    }
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop(true);
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.status.error : AppColors.status.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pickDate(ValueChanged<DateTime> onPick, DateTime? initial) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year + 10),
    );
    if (d != null) onPick(d);
  }

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
    final steps = _buildSteps();
    final step = steps[_step];
    return AppScaffold(
      title: _isEdit ? 'Editar ficha de venda' : 'Nova ficha de venda',
      showBottomNavigation: false,
      body: Column(
        children: [
          _StepHeader(
            index: _step,
            total: steps.length,
            title: step.title,
            subtitle: step.subtitle,
            icon: step.icon,
            color: step.color,
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
                  for (final s in steps)
                    ListView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                      children: s.content,
                    ),
                ],
              ),
            ),
          ),
          _navBar(steps.length),
        ],
      ),
    );
  }

  List<
      ({
        String title,
        String subtitle,
        IconData icon,
        Color color,
        List<Widget> content
      })> _buildSteps() {
    return [
      (
        title: 'Dados gerais',
        subtitle: 'Venda, mídia e unidade',
        icon: LucideIcons.fileText,
        color: _stepColor(0),
        content: _sectionGeral(),
      ),
      (
        title: 'Comprador',
        subtitle: 'Dados pessoais e cônjuge',
        icon: LucideIcons.user,
        color: _stepColor(1),
        content: [
          ..._sectionPessoa(
            band: 'COMPRADOR',
            icon: LucideIcons.user,
            name: _buyerName,
            cpf: _buyerCpf,
            rg: _buyerRg,
            birth: _buyerBirth,
            onBirth: (d) => setState(() => _buyerBirth = d),
            email: _buyerEmail,
            phone: _buyerPhone,
            profession: _buyerProfession,
            zip: _buyerZip,
            street: _buyerStreet,
            number: _buyerNumber,
            complement: _buyerComplement,
            neighborhood: _buyerNeighborhood,
            city: _buyerCity,
            state: _buyerState,
            onState: (v) => setState(() => _buyerState = v),
            nameRequired: true,
          ),
          ..._sectionSpouse(
            band: 'CÔNJUGE DO COMPRADOR',
            has: _hasBuyerSpouse,
            onToggle: (v) => setState(() => _hasBuyerSpouse = v),
            name: _buyerSpouseName,
            cpf: _buyerSpouseCpf,
            rg: _buyerSpouseRg,
            profession: _buyerSpouseProfession,
            email: _buyerSpouseEmail,
            phone: _buyerSpousePhone,
          ),
        ],
      ),
      (
        title: 'Vendedor',
        subtitle: 'Dados pessoais e cônjuge',
        icon: LucideIcons.user,
        color: _stepColor(2),
        content: [
          ..._sectionPessoa(
            band: 'VENDEDOR',
            icon: LucideIcons.user,
            name: _sellerName,
            cpf: _sellerCpf,
            rg: _sellerRg,
            birth: _sellerBirth,
            onBirth: (d) => setState(() => _sellerBirth = d),
            email: _sellerEmail,
            phone: _sellerPhone,
            profession: _sellerProfession,
            zip: _sellerZip,
            street: _sellerStreet,
            number: _sellerNumber,
            complement: _sellerComplement,
            neighborhood: _sellerNeighborhood,
            city: _sellerCity,
            state: _sellerState,
            onState: (v) => setState(() => _sellerState = v),
            nameRequired: false,
          ),
          ..._sectionSpouse(
            band: 'CÔNJUGE DO VENDEDOR',
            has: _hasSellerSpouse,
            onToggle: (v) => setState(() => _hasSellerSpouse = v),
            name: _sellerSpouseName,
            cpf: _sellerSpouseCpf,
            rg: _sellerSpouseRg,
            profession: _sellerSpouseProfession,
            email: _sellerSpouseEmail,
            phone: _sellerSpousePhone,
          ),
        ],
      ),
      (
        title: _isEmpreendimento ? 'Empreendimento' : 'Imóvel',
        subtitle: 'Localização e dados',
        icon: _isEmpreendimento ? LucideIcons.building2 : LucideIcons.house,
        color: _stepColor(3),
        content: _isEmpreendimento ? _sectionEmpreendimento() : _sectionImovel(),
      ),
      (
        title: 'Financeiro & comissões',
        subtitle: 'Valores e participantes',
        icon: LucideIcons.dollarSign,
        color: _stepColor(4),
        content: [..._sectionFinanceiro(), ..._sectionComissoes()],
      ),
      (
        title: 'Usuários & revisão',
        subtitle: _isEdit ? 'Vincular e salvar' : 'Vincular e criar',
        icon: LucideIcons.userPlus,
        color: _stepColor(5),
        content: _sectionVincular(),
      ),
    ];
  }

  // ── Navegação dos passos ─────────────────────────────────────────────────

  String? _validateStep(int i) {
    switch (i) {
      case 0:
        if (_mediaSource == null) return 'Selecione a mídia de origem.';
        if (_saleUnit.text.trim().isEmpty) return 'Informe a unidade de venda.';
        if (_description.text.trim().isEmpty) {
          return 'Informe a descrição da ficha.';
        }
        return null;
      case 1:
        if (_buyerName.text.trim().isEmpty) {
          return 'Informe o nome do comprador.';
        }
        return null;
      case 4:
        if (_commissionModel == CommissionPaymentModel.obrigatorio &&
            _commissionDesc.text.trim().isEmpty) {
          return 'Descreva o modelo de pagamento da comissão.';
        }
        for (final p in _participants) {
          if (p.userId == null && p.funcao != _Funcao.gerencia) {
            return 'Selecione o usuário de cada participante da comissão.';
          }
        }
        return null;
      default:
        return null;
    }
  }

  void _next(int total) {
    final err = _validateStep(_step);
    if (err != null) {
      _toast(err, error: true);
      return;
    }
    if (_step < total - 1) {
      _pageCtrl.animateToPage(
        _step + 1,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _back() {
    if (_step > 0) {
      _pageCtrl.animateToPage(
        _step - 1,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
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
                backgroundColor: last ? _brand : _accent,
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
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Seções ──────────────────────────────────────────────────────────────

  List<Widget> _sectionGeral() => [
        _Band('DADOS GERAIS', LucideIcons.fileText),
        _Row2(
          left: _DateField(
            label: 'Data da venda',
            value: _saleDate,
            onTap: () =>
                _pickDate((d) => setState(() => _saleDate = d), _saleDate),
          ),
          right: _Field(
              label: 'Unidade de venda', controller: _saleUnit, required: true),
        ),
        _Dropdown(
          label: 'Mídia de origem',
          required: true,
          value: _mediaSource,
          options: _kMediaSources,
          onChanged: (v) => setState(() => _mediaSource = v),
        ),
        _Row2(
          left: _Field(label: 'Gerente', controller: _managerName),
          right:
              _Field(label: 'Corretor externo', controller: _externalBrokerName),
        ),
        _YesNo(
          label: 'Secretária presente?',
          value: _secretaryPresent,
          onChanged: (v) => setState(() => _secretaryPresent = v),
        ),
        _YesNo(
          label: 'Grupo geral?',
          value: _generalGroup,
          onChanged: (v) => setState(() => _generalGroup = v ?? false),
        ),
        _Field(label: 'Descrição', controller: _description, required: true, maxLines: 3),
        const SizedBox(height: 6),
      ];

  List<Widget> _sectionPessoa({
    required String band,
    required IconData icon,
    required TextEditingController name,
    required TextEditingController cpf,
    required TextEditingController rg,
    required DateTime? birth,
    required ValueChanged<DateTime> onBirth,
    required TextEditingController email,
    required TextEditingController phone,
    required TextEditingController profession,
    required TextEditingController zip,
    required TextEditingController street,
    required TextEditingController number,
    required TextEditingController complement,
    required TextEditingController neighborhood,
    required TextEditingController city,
    required String? state,
    required ValueChanged<String?> onState,
    required bool nameRequired,
  }) =>
      [
        _Band(band, icon),
        _Field(label: 'Nome', controller: name, required: nameRequired),
        _Row2(
          left: _Field(
              label: 'CPF/CNPJ', controller: cpf, keyboard: TextInputType.number),
          right: _Field(label: 'RG', controller: rg),
        ),
        _Row2(
          left: _Field(
              label: 'E-mail',
              controller: email,
              keyboard: TextInputType.emailAddress),
          right: _Field(
              label: 'Telefone', controller: phone, keyboard: TextInputType.phone),
        ),
        _Row2(
          left: _DateField(
            label: 'Nascimento',
            value: birth,
            onTap: () => _pickDate(onBirth, birth),
          ),
          right: _Field(label: 'Profissão', controller: profession),
        ),
        const SizedBox(height: 2),
        _MiniLabel('Endereço'),
        _Row2(
          leftFlex: 2,
          rightFlex: 3,
          left: _Field(label: 'CEP', controller: zip, keyboard: TextInputType.number),
          right: _Field(label: 'Bairro', controller: neighborhood),
        ),
        _Field(label: 'Logradouro', controller: street),
        _Row2(
          leftFlex: 2,
          rightFlex: 3,
          left: _Field(label: 'Número', controller: number, keyboard: TextInputType.number),
          right: _Field(label: 'Compl.', controller: complement),
        ),
        _Row2(
          leftFlex: 3,
          rightFlex: 2,
          left: _Field(label: 'Cidade', controller: city),
          right: _Dropdown(
            label: 'UF',
            value: state,
            options: _kUfs,
            onChanged: onState,
          ),
        ),
        const SizedBox(height: 6),
      ];

  List<Widget> _sectionSpouse({
    required String band,
    required bool has,
    required ValueChanged<bool> onToggle,
    required TextEditingController name,
    required TextEditingController cpf,
    required TextEditingController rg,
    required TextEditingController profession,
    required TextEditingController email,
    required TextEditingController phone,
  }) =>
      [
        _BandSwitch(band, LucideIcons.users, has, onToggle),
        if (has) ...[
          _Field(label: 'Nome', controller: name),
          _Row2(
            left: _Field(label: 'CPF', controller: cpf, keyboard: TextInputType.number),
            right: _Field(label: 'RG', controller: rg),
          ),
          _Row2(
            left: _Field(
                label: 'E-mail',
                controller: email,
                keyboard: TextInputType.emailAddress),
            right: _Field(
                label: 'Telefone', controller: phone, keyboard: TextInputType.phone),
          ),
          _Field(label: 'Profissão', controller: profession),
        ],
        const SizedBox(height: 6),
      ];

  List<Widget> _sectionImovel() => [
        _Band('IMÓVEL', LucideIcons.house),
        _Row2(
          leftFlex: 3,
          rightFlex: 2,
          left: _Field(label: 'Código do imóvel', controller: _propCode),
          right: _Field(
              label: 'CEP', controller: _propZip, keyboard: TextInputType.number),
        ),
        _Field(label: 'Endereço', controller: _propAddress),
        _Row2(
          leftFlex: 2,
          rightFlex: 3,
          left: _Field(label: 'Número', controller: _propNumber, keyboard: TextInputType.number),
          right: _Field(label: 'Compl.', controller: _propComplement),
        ),
        _Field(label: 'Bairro', controller: _propNeighborhood),
        _Row2(
          leftFlex: 3,
          rightFlex: 2,
          left: _Field(label: 'Cidade', controller: _propCity),
          right: _Dropdown(
            label: 'UF',
            value: _propState,
            options: _kUfs,
            onChanged: (v) => setState(() => _propState = v),
          ),
        ),
        const SizedBox(height: 6),
      ];

  List<Widget> _sectionEmpreendimento() => [
        _Band('EMPREENDIMENTO', LucideIcons.building2),
        _Row2(
          left: _Field(label: 'Incorporadora', controller: _empIncorporadora),
          right: _Field(label: 'Empreendimento', controller: _empNome),
        ),
        _Row2(
          left: _Field(label: 'Unidade', controller: _empUnidade),
          right: _DateField(
            label: 'Data de entrada',
            value: _empDataEntrada,
            onTap: () => _pickDate(
                (d) => setState(() => _empDataEntrada = d), _empDataEntrada),
          ),
        ),
        _Row2(
          left: _Field(
              label: 'Valor de entrada', controller: _empValorEntrada, money: true),
          right: _Field(
              label: 'Forma de pagamento', controller: _empFormaPagamento),
        ),
        const SizedBox(height: 6),
      ];

  List<Widget> _sectionFinanceiro() => [
        _Band('FINANCEIRO', LucideIcons.dollarSign),
        _Row2(
          left: _Field(label: 'Valor da venda', controller: _saleValue, money: true),
          right:
              _Field(label: 'Comissão total', controller: _totalCommission, money: true),
        ),
        _Field(label: 'Meta', controller: _goalValue, money: true),
        const SizedBox(height: 12),
        _MiniLabel('Modelo de comissão'),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: _Choice(
                label: 'Obrigatório',
                selected: _commissionModel == CommissionPaymentModel.obrigatorio,
                accent: _accent,
                onTap: () => setState(
                    () => _commissionModel = CommissionPaymentModel.obrigatorio),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Choice(
                label: 'Não aplicável',
                selected: _commissionModel == CommissionPaymentModel.naoAplicavel,
                accent: _accent,
                onTap: () => setState(
                    () => _commissionModel = CommissionPaymentModel.naoAplicavel),
              ),
            ),
          ],
        ),
        if (_commissionModel == CommissionPaymentModel.obrigatorio) ...[
          const SizedBox(height: 12),
          _Field(
            label: 'Descrição do modelo de comissão',
            controller: _commissionDesc,
            required: true,
            maxLines: 2,
          ),
        ],
        const SizedBox(height: 16),
      ];

  List<Widget> _sectionComissoes() => [
        _Band('COMISSÕES', LucideIcons.users),
        for (var i = 0; i < _participants.length; i++)
          _ParticipantCard(
            index: i,
            participant: _participants[i],
            accent: _accent,
            onPickUser: () => _pickParticipantUser(_participants[i]),
            onFuncao: (f) => setState(() => _participants[i].funcao = f),
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

  List<Widget> _sectionVincular() => [
        _Band('VINCULAR USUÁRIOS', LucideIcons.userPlus),
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
                    onRemove: () =>
                        setState(() => _linkedUsers.removeWhere((x) => x.id == u.id)),
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

  // ── User pickers ─────────────────────────────────────────────────────────

  Future<void> _pickParticipantUser(_Participant p) async {
    final u = await _showUserPicker();
    if (u != null) {
      setState(() {
        p.userId = u.id;
        p.userName = u.name;
      });
    }
  }

  Future<void> _pickLinkedUser() async {
    final u = await _showUserPicker();
    if (u != null && _linkedUsers.every((x) => x.id != u.id)) {
      setState(() => _linkedUsers.add(u));
    }
  }

  Future<AdminUser?> _showUserPicker() {
    return showModalBottomSheet<AdminUser>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UserPickerSheet(accent: _accent),
    );
  }

}

/// Cabeçalho do passo — ícone tonal na cor do passo + título + "Passo X de N"
/// + barra de progresso, e uma linha discreta de tipo/equipe. Dá orientação e
/// cor à tela (cada passo na sua cor; conforto via tom suave).
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
        // Flush: sem caixa tingida — só um sublinhado na cor do passo
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
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
              letterSpacing: 1.4,
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

class _BandSwitch extends StatelessWidget {
  const _BandSwitch(this.title, this.icon, this.value, this.onChanged);
  final String title;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: muted),
          const SizedBox(width: 7),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
              letterSpacing: 1.4,
            ),
          ),
          const Spacer(),
          Switch(value: value, onChanged: onChanged),
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

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.required = false,
    this.maxLines = 1,
    this.keyboard,
    this.money = false,
  });
  final String label;
  final TextEditingController controller;
  final bool required;
  final int maxLines;
  final TextInputType? keyboard;
  final bool money;

  @override
  Widget build(BuildContext context) {
    // Visual (filled, borda, foco) herdado do _formTheme — fica leve e coeso.
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: money ? TextInputType.number : keyboard,
        inputFormatters: money ? [CurrencyInputFormatter()] : null,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          prefixText: money ? 'R\$ ' : null,
        ),
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
  });
  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  final bool required;
  @override
  Widget build(BuildContext context) {
    // Mesmo visual filled dos campos (herda _formTheme) — selects coesos.
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        icon: Icon(LucideIcons.chevronDown,
            size: 18, color: ThemeHelpers.textSecondaryColor(context)),
        borderRadius: BorderRadius.circular(14),
        dropdownColor: ThemeHelpers.cardBackgroundColor(context),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: ThemeHelpers.textColor(context),
            ),
        items: options
            .map((o) => DropdownMenuItem(
                value: o,
                child: Text(o, overflow: TextOverflow.ellipsis)))
            .toList(),
        onChanged: onChanged,
        decoration: InputDecoration(labelText: required ? '$label *' : label),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.onTap});
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: InputDecorator(
          // Visual filled herdado do _formTheme (igual aos campos).
          decoration: InputDecoration(labelText: label),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value != null
                      ? DateFormat('dd/MM/yyyy', 'pt_BR').format(value!)
                      : 'Selecionar',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: value != null
                        ? ThemeHelpers.textColor(context)
                        : muted,
                  ),
                ),
              ),
              Icon(LucideIcons.calendar, size: 16, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _YesNo extends StatelessWidget {
  const _YesNo({required this.label, required this.value, required this.onChanged});
  final String label;
  final bool? value;
  final ValueChanged<bool?> onChanged;
  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w700, color: muted),
            ),
          ),
          _miniToggle(context, 'Sim', value == true, () => onChanged(true)),
          const SizedBox(width: 6),
          _miniToggle(context, 'Não', value == false, () => onChanged(false)),
        ],
      ),
    );
  }

  Widget _miniToggle(BuildContext c, String t, bool sel, VoidCallback onTap) {
    final accent = Theme.of(c).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? accent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: sel
                ? accent.withValues(alpha: 0.5)
                : ThemeHelpers.borderColor(c).withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          t,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
            color: sel ? accent : ThemeHelpers.textSecondaryColor(c),
          ),
        ),
      ),
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
        padding: const EdgeInsets.symmetric(vertical: 11),
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
        padding: const EdgeInsets.symmetric(vertical: 11),
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
            Text(
              label,
              style: TextStyle(
                  color: accent, fontWeight: FontWeight.w800, fontSize: 12.5),
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
          Text(
            name.split(' ').first,
            style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 12.5),
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
    required this.onPickUser,
    required this.onFuncao,
    required this.onEmitir,
    required this.onRemove,
  });
  final int index;
  final _Participant participant;
  final Color accent;
  final VoidCallback onPickUser;
  final ValueChanged<_Funcao> onFuncao;
  final ValueChanged<bool> onEmitir;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = participant;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final isSdr = p.funcao == _Funcao.sdr;
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
                child: Icon(LucideIcons.trash2, size: 16, color: muted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final f in _Funcao.values)
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
          const SizedBox(height: 10),
          TextField(
            controller: isSdr ? p.valorFixo : p.percent,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: isSdr
                ? [CurrencyInputFormatter()]
                : [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
            decoration: InputDecoration(
              labelText: isSdr ? 'Valor fixo' : 'Porcentagem (%)',
              prefixText: isSdr ? 'R\$ ' : null,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('Emitir nota',
                  style: TextStyle(fontWeight: FontWeight.w700, color: muted)),
              const Spacer(),
              Switch(value: p.emitirNota, onChanged: onEmitir),
            ],
          ),
        ],
      ),
    );
  }
}

/// Sheet de seleção de usuário (corretor/captador/etc. e vincular).
class _UserPickerSheet extends StatefulWidget {
  const _UserPickerSheet({required this.accent});
  final Color accent;
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
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          18, 10, 18, 14 + MediaQuery.paddingOf(context).bottom),
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
          TextField(
            controller: _searchCtrl,
            onSubmitted: (v) {
              _q = v.trim();
              _load();
            },
            decoration: InputDecoration(
              hintText: 'Buscar usuário…',
              prefixIcon: const Icon(LucideIcons.search, size: 18),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 10),
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
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: widget.accent.withValues(alpha: 0.15),
                              child: Text(
                                u.name.isNotEmpty ? u.name[0].toUpperCase() : '?',
                                style: TextStyle(
                                    color: widget.accent,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13),
                              ),
                            ),
                            title: Text(u.name,
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(u.email,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () => Navigator.of(context).pop(u),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
