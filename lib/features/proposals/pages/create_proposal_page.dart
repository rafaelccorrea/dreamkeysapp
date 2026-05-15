import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/cep_service.dart';
import '../../../shared/services/purchase_proposals_service.dart';
import '../../../shared/utils/input_formatters.dart';
import '../../../shared/utils/masks.dart';
import '../widgets/proposal_signatures_sheet.dart';

const _kFieldRadius = 10.0;
const _kPagePad = 14.0;
const _kFieldGapH = 10.0;

/// Cria ou edita uma ficha de proposta. Espelha o
/// `CreatePurchaseProposalPage.tsx` do `imobx-front` (paridade de campos
/// e regras de validação obrigatórias do `CreateProposalAuthDto`).
///
/// Layout fluido: sem cards, sem encapsulamento — cada seção é uma faixa
/// edge-to-edge com cor temática própria + barra lateral acentuada.
class CreateProposalPage extends StatefulWidget {
  const CreateProposalPage({super.key, this.proposalId});

  final String? proposalId;

  bool get isEditing => proposalId != null;

  @override
  State<CreateProposalPage> createState() => _CreateProposalPageState();
}

class _CreateProposalPageState extends State<CreateProposalPage> {
  final _formKey = GlobalKey<FormState>();
  final _scroll = ScrollController();

  int _etapa = 1;
  bool _loading = false;
  bool _saving = false;
  PurchaseProposal? _existing;

  // Estado do formulário
  final _proposalDate = TextEditingController();
  final _validityDays = TextEditingController(text: '5');
  final _proposedPrice = TextEditingController();
  final _paymentConditions = TextEditingController();
  final _downPayment = TextEditingController();
  final _downPaymentDays = TextEditingController();
  final _commissionPercentage = TextEditingController();
  final _deliveryDays = TextEditingController(text: '30');
  final _monthlyPenalty = TextEditingController();
  final _saleUnit = TextEditingController();
  final _captureUnit = TextEditingController();
  final _observations = TextEditingController();

  // Comprador
  final _buyerName = TextEditingController();
  final _buyerCpf = TextEditingController();
  final _buyerRg = TextEditingController();
  final _buyerNationality = TextEditingController(text: 'Brasileiro(a)');
  final _buyerMaritalStatus = TextEditingController();
  final _buyerMarriageRegime = TextEditingController();
  DateTime? _buyerBirthDate;
  final _buyerProfession = TextEditingController();
  final _buyerEmail = TextEditingController();
  final _buyerPhone = TextEditingController();
  final _buyerZipCode = TextEditingController();
  final _buyerStreet = TextEditingController();
  final _buyerNumber = TextEditingController();
  final _buyerComplement = TextEditingController();
  final _buyerNeighborhood = TextEditingController();
  final _buyerCity = TextEditingController();
  final _buyerState = TextEditingController();

  bool _buyerHasSpouse = false;
  final _buyerSpouseName = TextEditingController();
  final _buyerSpouseCpf = TextEditingController();
  final _buyerSpouseRg = TextEditingController();
  final _buyerSpouseEmail = TextEditingController();
  final _buyerSpousePhone = TextEditingController();
  final _buyerSpouseProfession = TextEditingController();

  // Imóvel
  final _propertyCode = TextEditingController();
  final _propertyRegistry = TextEditingController();
  final _propertyNotary = TextEditingController();
  final _propertyCityRegistry = TextEditingController();
  final _propertyZipCode = TextEditingController();
  final _propertyStreet = TextEditingController();
  final _propertyNumber = TextEditingController();
  final _propertyComplement = TextEditingController();
  final _propertyNeighborhood = TextEditingController();
  final _propertyCity = TextEditingController();
  final _propertyState = TextEditingController();

  // Proprietário (Etapa 2)
  final _ownerName = TextEditingController();
  final _ownerCpf = TextEditingController();
  final _ownerRg = TextEditingController();
  final _ownerNationality = TextEditingController(text: 'Brasileiro(a)');
  final _ownerMaritalStatus = TextEditingController();
  final _ownerMarriageRegime = TextEditingController();
  DateTime? _ownerBirthDate;
  final _ownerProfession = TextEditingController();
  final _ownerEmail = TextEditingController();
  final _ownerPhone = TextEditingController();
  final _ownerZipCode = TextEditingController();
  final _ownerAddress = TextEditingController();
  final _ownerNeighborhood = TextEditingController();
  final _ownerCity = TextEditingController();
  final _ownerState = TextEditingController();

  bool _ownerHasSpouse = false;
  final _ownerSpouseName = TextEditingController();
  final _ownerSpouseCpf = TextEditingController();
  final _ownerSpouseRg = TextEditingController();
  final _ownerSpouseEmail = TextEditingController();
  final _ownerSpousePhone = TextEditingController();
  final _ownerSpouseProfession = TextEditingController();

  // Corretores / Captadores (Etapa 3)
  final List<_BrokerForm> _brokers = [_BrokerForm()];
  final List<_CaptadorForm> _captadores = [_CaptadorForm()];

  bool _cepBuyerLoading = false;
  bool _cepPropertyLoading = false;
  bool _cepOwnerLoading = false;

  // ────────── Paleta temática (coerente com app_colors.dart) ────────────

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Color get _accent =>
      _isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;

  Color get _hueRed =>
      _isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
  Color get _hueBlue =>
      _isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
  Color get _hueGreen =>
      _isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
  Color get _huePurple =>
      _isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
  Color get _hueYellow =>
      _isDark ? AppColors.status.yellowDarkMode : AppColors.status.yellow;
  Color get _hueVinho => _isDark
      ? AppColors.secondary.secondaryDarkMode
      : AppColors.secondary.secondary;

  @override
  void initState() {
    super.initState();
    if (widget.isEditing) {
      _loadExisting();
    } else {
      _proposalDate.text = _formatDate(DateTime.now());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final c in <TextEditingController>[
      _proposalDate, _validityDays, _proposedPrice, _paymentConditions,
      _downPayment, _downPaymentDays, _commissionPercentage, _deliveryDays,
      _monthlyPenalty, _saleUnit, _captureUnit, _observations,
      _buyerName, _buyerCpf, _buyerRg, _buyerNationality, _buyerMaritalStatus,
      _buyerMarriageRegime, _buyerProfession, _buyerEmail, _buyerPhone,
      _buyerZipCode, _buyerStreet, _buyerNumber, _buyerComplement,
      _buyerNeighborhood, _buyerCity, _buyerState,
      _buyerSpouseName, _buyerSpouseCpf, _buyerSpouseRg, _buyerSpouseEmail,
      _buyerSpousePhone, _buyerSpouseProfession,
      _propertyCode, _propertyRegistry, _propertyNotary, _propertyCityRegistry,
      _propertyZipCode, _propertyStreet, _propertyNumber, _propertyComplement,
      _propertyNeighborhood, _propertyCity, _propertyState,
      _ownerName, _ownerCpf, _ownerRg, _ownerNationality, _ownerMaritalStatus,
      _ownerMarriageRegime, _ownerProfession, _ownerEmail, _ownerPhone,
      _ownerZipCode, _ownerAddress, _ownerNeighborhood, _ownerCity, _ownerState,
      _ownerSpouseName, _ownerSpouseCpf, _ownerSpouseRg, _ownerSpouseEmail,
      _ownerSpousePhone, _ownerSpouseProfession,
    ]) {
      c.dispose();
    }
    for (final b in _brokers) {
      b.dispose();
    }
    for (final c in _captadores) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadExisting() async {
    setState(() => _loading = true);
    final res = await PurchaseProposalsService.instance.getById(
      widget.proposalId!,
    );
    if (!mounted) return;
    if (!res.success || res.data == null) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message ?? 'Erro ao carregar.')),
      );
      Navigator.of(context).maybePop();
      return;
    }
    final p = res.data!;
    setState(() {
      _existing = p;
      _loading = false;
      _hydrateFromProposal(p);
    });
  }

  void _hydrateFromProposal(PurchaseProposal p) {
    _proposalDate.text = _formatDate(p.proposalDate ?? DateTime.now());
    _validityDays.text = '${p.validityDays ?? 5}';
    _proposedPrice.text = _money(p.proposedPrice);
    _paymentConditions.text = p.paymentConditions ?? '';
    _downPayment.text = _money(p.downPayment);
    _downPaymentDays.text =
        p.downPaymentDays != null ? '${p.downPaymentDays}' : '';
    _commissionPercentage.text = p.commissionPercentage != null
        ? p.commissionPercentage!.toStringAsFixed(2).replaceAll('.', ',')
        : '';
    _deliveryDays.text = '${p.deliveryDays ?? 30}';
    _monthlyPenalty.text = _money(p.monthlyPenalty);
    _saleUnit.text = p.saleUnit ?? '';
    _captureUnit.text = p.captureUnit ?? '';

    _buyerName.text = p.proponentName ?? '';
    _buyerCpf.text = Masks.cpf(p.proponentCpf ?? '');
    _buyerRg.text = p.proponentRg ?? '';
    _buyerNationality.text = p.proponentNationality ?? 'Brasileiro(a)';
    _buyerMaritalStatus.text = p.proponentMaritalStatus ?? '';
    _buyerMarriageRegime.text = p.proponentMarriageRegime ?? '';
    _buyerBirthDate = p.proponentBirthDate;
    _buyerProfession.text = p.proponentProfession ?? '';
    _buyerEmail.text = p.proponentEmail ?? '';
    _buyerPhone.text = Masks.phone(p.proponentPhone ?? '');
    _buyerZipCode.text = Masks.cep(p.proponentZipCode ?? '');
    _buyerStreet.text = p.proponentAddress ?? '';
    _buyerNeighborhood.text = p.proponentNeighborhood ?? '';
    _buyerCity.text = p.proponentCity ?? '';
    _buyerState.text = p.proponentState ?? '';

    final hasSpouse = (p.proponentSpouseName?.trim().isNotEmpty ?? false) ||
        (p.proponentSpouseCpf?.trim().isNotEmpty ?? false);
    _buyerHasSpouse = hasSpouse;
    _buyerSpouseName.text = p.proponentSpouseName ?? '';
    _buyerSpouseCpf.text = Masks.cpf(p.proponentSpouseCpf ?? '');
    _buyerSpouseRg.text = p.proponentSpouseRg ?? '';
    _buyerSpouseEmail.text = p.proponentSpouseEmail ?? '';
    _buyerSpousePhone.text = Masks.phone(p.proponentSpousePhone ?? '');
    _buyerSpouseProfession.text = p.proponentSpouseProfession ?? '';

    _propertyCode.text = p.propertyCode ?? '';
    _propertyRegistry.text = p.propertyRegistry ?? '';
    _propertyNotary.text = p.propertyNotary ?? '';
    _propertyCityRegistry.text = p.propertyCityRegistry ?? '';
    _propertyZipCode.text = Masks.cep(p.propertyZipCode ?? '');
    _propertyStreet.text = p.propertyStreet ?? p.propertyAddress ?? '';
    _propertyNumber.text = p.propertyNumber ?? '';
    _propertyComplement.text = p.propertyComplement ?? '';
    _propertyNeighborhood.text = p.propertyNeighborhood ?? '';
    _propertyCity.text = p.propertyCity ?? '';
    _propertyState.text = p.propertyState ?? '';

    _ownerName.text = p.ownerName ?? '';
    _ownerCpf.text = Masks.cpf(p.ownerCpf ?? '');
    _ownerRg.text = p.ownerRg ?? '';
    _ownerNationality.text = p.ownerNationality ?? 'Brasileiro(a)';
    _ownerMaritalStatus.text = p.ownerMaritalStatus ?? '';
    _ownerMarriageRegime.text = p.ownerMarriageRegime ?? '';
    _ownerBirthDate = p.ownerBirthDate;
    _ownerProfession.text = p.ownerProfession ?? '';
    _ownerEmail.text = p.ownerEmail ?? '';
    _ownerPhone.text = Masks.phone(p.ownerPhone ?? '');
    _ownerZipCode.text = Masks.cep(p.ownerZipCode ?? '');
    _ownerAddress.text = p.ownerAddress ?? '';
    _ownerNeighborhood.text = p.ownerNeighborhood ?? '';
    _ownerCity.text = p.ownerCity ?? '';
    _ownerState.text = p.ownerState ?? '';

    final hasOwnerSpouse = (p.ownerSpouseName?.trim().isNotEmpty ?? false) ||
        (p.ownerSpouseCpf?.trim().isNotEmpty ?? false);
    _ownerHasSpouse = hasOwnerSpouse;
    _ownerSpouseName.text = p.ownerSpouseName ?? '';
    _ownerSpouseCpf.text = Masks.cpf(p.ownerSpouseCpf ?? '');
    _ownerSpouseRg.text = p.ownerSpouseRg ?? '';
    _ownerSpouseEmail.text = p.ownerSpouseEmail ?? '';
    _ownerSpousePhone.text = Masks.phone(p.ownerSpousePhone ?? '');
    _ownerSpouseProfession.text = p.ownerSpouseProfession ?? '';

    if (p.brokersData.isNotEmpty) {
      for (final b in _brokers) {
        b.dispose();
      }
      _brokers
        ..clear()
        ..addAll(p.brokersData.map(_BrokerForm.fromBroker));
    }
    if (p.captadoresData.isNotEmpty) {
      for (final c in _captadores) {
        c.dispose();
      }
      _captadores
        ..clear()
        ..addAll(p.captadoresData.map(_CaptadorForm.fromCaptador));
    }
  }

  String _money(double? v) {
    if (v == null) return '';
    final str = v.toStringAsFixed(2);
    return Masks.money(str.replaceAll('.', ''));
  }

  String _formatDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  DateTime? _parseDate(String s) {
    final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(s.trim());
    if (m == null) return null;
    final d = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final y = int.parse(m.group(3)!);
    try {
      return DateTime(y, mo, d);
    } catch (_) {
      return null;
    }
  }

  double? _parseMoney(String s) {
    if (s.trim().isEmpty) return null;
    final norm =
        s.replaceAll('.', '').replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(norm);
  }

  double? _parsePercent(String s) {
    if (s.trim().isEmpty) return null;
    final norm = s.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(norm);
  }

  Future<void> _pickDate(DateTime? current, ValueChanged<DateTime> setter,
      {bool allowFuture = true}) async {
    final initial = current ?? DateTime.now();
    final first = DateTime(1900);
    final last = allowFuture
        ? DateTime(DateTime.now().year + 5)
        : DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(last) ? last : initial,
      firstDate: first,
      lastDate: last,
      helpText: 'Selecione a data',
      cancelText: 'Cancelar',
      confirmText: 'Confirmar',
    );
    if (picked != null) setter(picked);
  }

  Future<void> _buscarCep({
    required String cep,
    required void Function(CepAddress) onResult,
    required void Function(bool) setLoading,
  }) async {
    final clean = cep.replaceAll(RegExp(r'\D'), '');
    if (clean.length != 8) return;
    setLoading(true);
    final addr = await CepService.instance.searchCep(clean);
    setLoading(false);
    if (addr == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CEP não encontrado.')),
      );
      return;
    }
    onResult(addr);
  }

  CreateProposalPayload _buildPayload() {
    final p = CreateProposalPayload()
      ..proposalDate = _parseDate(_proposalDate.text)
      ..validityDays = int.tryParse(_validityDays.text)
      ..proposedPrice = _parseMoney(_proposedPrice.text)
      ..paymentConditions = _paymentConditions.text
      ..downPayment = _parseMoney(_downPayment.text)
      ..downPaymentDays = int.tryParse(_downPaymentDays.text)
      ..commissionPercentage = _parsePercent(_commissionPercentage.text)
      ..deliveryDays = int.tryParse(_deliveryDays.text)
      ..monthlyPenalty = _parseMoney(_monthlyPenalty.text)
      ..saleUnit = _saleUnit.text
      ..captureUnit = _captureUnit.text
      ..observations = _observations.text
      ..buyerName = _buyerName.text
      ..buyerCpf = _buyerCpf.text
      ..buyerRg = _buyerRg.text
      ..buyerBirthDate = _buyerBirthDate
      ..buyerEmail = _buyerEmail.text
      ..buyerPhone = _buyerPhone.text
      ..buyerProfession = _buyerProfession.text
      ..buyerNationality = _buyerNationality.text
      ..buyerMaritalStatus = _buyerMaritalStatus.text
      ..buyerMarriageRegime = _buyerMarriageRegime.text
      ..buyerZipCode = _buyerZipCode.text
      ..buyerStreet = _buyerStreet.text
      ..buyerNumber = _buyerNumber.text
      ..buyerComplement = _buyerComplement.text
      ..buyerNeighborhood = _buyerNeighborhood.text
      ..buyerCity = _buyerCity.text
      ..buyerState = _buyerState.text
      ..propertyRegistry = _propertyRegistry.text
      ..propertyNotary = _propertyNotary.text
      ..propertyCityRegistry = _propertyCityRegistry.text
      ..propertyCode = _propertyCode.text
      ..propertyZipCode = _propertyZipCode.text
      ..propertyStreet = _propertyStreet.text
      ..propertyNumber = _propertyNumber.text
      ..propertyComplement = _propertyComplement.text
      ..propertyNeighborhood = _propertyNeighborhood.text
      ..propertyCity = _propertyCity.text
      ..propertyState = _propertyState.text
      ..ownerName = _ownerName.text
      ..ownerCpf = _ownerCpf.text
      ..ownerRg = _ownerRg.text
      ..ownerBirthDate = _ownerBirthDate
      ..ownerEmail = _ownerEmail.text
      ..ownerPhone = _ownerPhone.text
      ..ownerProfession = _ownerProfession.text
      ..ownerNationality = _ownerNationality.text
      ..ownerMaritalStatus = _ownerMaritalStatus.text
      ..ownerMarriageRegime = _ownerMarriageRegime.text
      ..ownerZipCode = _ownerZipCode.text
      ..ownerAddress = _ownerAddress.text
      ..ownerNeighborhood = _ownerNeighborhood.text
      ..ownerCity = _ownerCity.text
      ..ownerState = _ownerState.text
      ..brokersData =
          _brokers.where((b) => b.isFilled).map((b) => b.toBroker()).toList()
      ..captadoresData = _captadores
          .where((c) => c.isFilled)
          .map((c) => c.toCaptador())
          .toList();

    if (_buyerHasSpouse) {
      p.buyerSpouseName = _buyerSpouseName.text;
      p.buyerSpouseCpf = _buyerSpouseCpf.text;
      p.buyerSpouseRg = _buyerSpouseRg.text;
      p.buyerSpouseEmail = _buyerSpouseEmail.text;
      p.buyerSpousePhone = _buyerSpousePhone.text;
      p.buyerSpouseProfession = _buyerSpouseProfession.text;
    }
    if (_ownerHasSpouse) {
      p.ownerSpouseName = _ownerSpouseName.text;
      p.ownerSpouseCpf = _ownerSpouseCpf.text;
      p.ownerSpouseRg = _ownerSpouseRg.text;
      p.ownerSpouseEmail = _ownerSpouseEmail.text;
      p.ownerSpousePhone = _ownerSpousePhone.text;
      p.ownerSpouseProfession = _ownerSpouseProfession.text;
    }
    return p;
  }

  bool _validateEtapa1Quick() {
    final errors = <String>[];
    if (_parseDate(_proposalDate.text) == null) {
      errors.add('Data da proposta inválida');
    }
    if (_buyerName.text.trim().isEmpty) {
      errors.add('Nome do comprador é obrigatório');
    }
    final cpfDigits = _buyerCpf.text.replaceAll(RegExp(r'\D'), '');
    if (cpfDigits.length != 11 && cpfDigits.length != 14) {
      errors.add('CPF/CNPJ do comprador inválido');
    }
    final phoneDigits = _buyerPhone.text.replaceAll(RegExp(r'\D'), '');
    if (phoneDigits.length < 10) {
      errors.add('Telefone do comprador inválido');
    }
    if (_parseMoney(_proposedPrice.text) == null) {
      errors.add('Preço proposto é obrigatório');
    }
    if (_paymentConditions.text.trim().isEmpty) {
      errors.add('Condições de pagamento obrigatórias');
    }
    if (_parsePercent(_commissionPercentage.text) == null) {
      errors.add('Comissão é obrigatória');
    }
    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errors.first)),
      );
      return false;
    }
    return true;
  }

  Future<void> _save({bool enviarParaAssinatura = false}) async {
    if (!_validateEtapa1Quick()) return;
    setState(() => _saving = true);
    final payload = _buildPayload();
    final res = widget.isEditing
        ? await PurchaseProposalsService.instance
            .update(widget.proposalId!, payload)
        : await PurchaseProposalsService.instance.create(payload);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!res.success || res.data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message ?? 'Erro ao salvar.')),
      );
      return;
    }
    final saved = res.data!;
    if (enviarParaAssinatura) {
      await showProposalSignaturesSheet(
        context,
        proposalId: saved.id,
        proposalNumber: saved.proposalNumber,
        etapa: _etapa,
        defaultSigners: [
          if (saved.proponentEmail != null && saved.proponentName != null)
            ProposalSignerInput(
              email: saved.proponentEmail!,
              name: saved.proponentName!,
              phone: saved.proponentPhone,
            ),
        ],
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: ThemeHelpers.backgroundColor(context),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: ThemeHelpers.backgroundColor(context),
      appBar: AppBar(
        title: Text(
          widget.isEditing ? 'Editar ficha de proposta' : 'Nova ficha de proposta',
          style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.2),
        ),
        elevation: 0,
        scrolledUnderElevation: 0.6,
        backgroundColor: ThemeHelpers.appBarBackgroundColor(context),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _StepRail(
              accent: _accent,
              current: _etapa,
              maxLiberada: _existing?.maxEtapaLiberadaParaEnvio ?? 1,
              isEditing: widget.isEditing,
              onChanged: (n) {
                setState(() => _etapa = n);
                if (_scroll.hasClients) {
                  _scroll.animateTo(
                    0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                  );
                }
              },
            ),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.only(bottom: 36),
                  children: _buildEtapaFields(),
                ),
              ),
            ),
            _BottomBar(
              accent: _accent,
              saving: _saving,
              isEditing: widget.isEditing,
              etapa: _etapa,
              canSign: !widget.isEditing ||
                  _etapa <= (_existing?.maxEtapaLiberadaParaEnvio ?? 1),
              onSave: () => _save(),
              onSaveAndSign: () => _save(enviarParaAssinatura: true),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildEtapaFields() {
    switch (_etapa) {
      case 2:
        return _buildEtapa2();
      case 3:
        return _buildEtapa3();
      default:
        return _buildEtapa1();
    }
  }

  // ─── Etapa 1: Dados da proposta + Comprador + Cônjuge + Imóvel ─────────

  List<Widget> _buildEtapa1() {
    return [
      _Section(
        title: 'Dados da proposta',
        icon: Icons.handshake_outlined,
        accent: _hueRed,
        subtitle: 'Valores, prazos e condições principais da oferta',
        children: [
          _Row([
            _Field(
              label: 'Data da proposta *',
              controller: _proposalDate,
              keyboard: TextInputType.datetime,
              suffix: _SuffixAction(
                icon: Icons.event_outlined,
                onTap: () => _pickDate(
                  _parseDate(_proposalDate.text),
                  (d) => setState(() => _proposalDate.text = _formatDate(d)),
                ),
              ),
            ),
            _Field(
              label: 'Validade',
              controller: _validityDays,
              keyboard: TextInputType.number,
              formatters: [FilteringTextInputFormatter.digitsOnly],
              suffixText: 'dias',
            ),
          ], flex: const [3, 2]),
          _Row([
            _Field(
              label: 'Preço proposto *',
              controller: _proposedPrice,
              keyboard: TextInputType.number,
              formatters: [MoneyInputFormatter()],
              prefixText: 'R\$ ',
            ),
            _Field(
              label: 'Comissão *',
              controller: _commissionPercentage,
              keyboard: TextInputType.number,
              formatters: [PercentageInputFormatter()],
              suffixText: '%',
            ),
          ], flex: const [3, 2]),
          _Field(
            label: 'Condições de pagamento *',
            controller: _paymentConditions,
            maxLines: 3,
            hint: 'Ex.: 30% à vista, 70% em 24 parcelas de R\$ X.',
          ),
          _Row([
            _Field(
              label: 'Sinal (arras)',
              controller: _downPayment,
              keyboard: TextInputType.number,
              formatters: [MoneyInputFormatter()],
              prefixText: 'R\$ ',
            ),
            _Field(
              label: 'Prazo p/ sinal',
              controller: _downPaymentDays,
              keyboard: TextInputType.number,
              formatters: [FilteringTextInputFormatter.digitsOnly],
              suffixText: 'dias',
            ),
          ], flex: const [3, 2]),
          _Row([
            _Field(
              label: 'Prazo de entrega',
              controller: _deliveryDays,
              keyboard: TextInputType.number,
              formatters: [FilteringTextInputFormatter.digitsOnly],
              suffixText: 'dias',
            ),
            _Field(
              label: 'Multa mensal',
              controller: _monthlyPenalty,
              keyboard: TextInputType.number,
              formatters: [MoneyInputFormatter()],
              prefixText: 'R\$ ',
            ),
          ]),
          _Row([
            _Field(label: 'Unidade de venda', controller: _saleUnit),
            _Field(label: 'Unidade de captação', controller: _captureUnit),
          ]),
          _Field(
            label: 'Observações',
            controller: _observations,
            maxLines: 3,
            hint: 'Anotações adicionais sobre esta proposta',
          ),
        ],
      ),
      _Section(
        title: 'Proponente • Comprador',
        icon: Icons.person_outline_rounded,
        accent: _hueBlue,
        subtitle: 'Dados pessoais e contato de quem está propondo a compra',
        children: [
          _Field(
            label: 'Nome completo *',
            controller: _buyerName,
            textCapitalization: TextCapitalization.words,
          ),
          _Row([
            _Field(
              label: 'CPF / CNPJ *',
              controller: _buyerCpf,
              keyboard: TextInputType.number,
              formatters: [CpfInputFormatter()],
            ),
            _Field(label: 'RG', controller: _buyerRg),
          ], flex: const [3, 2]),
          _Row([
            _DateField(
              label: 'Data de nascimento',
              value: _buyerBirthDate,
              onPick: () => _pickDate(
                _buyerBirthDate,
                (d) => setState(() => _buyerBirthDate = d),
                allowFuture: false,
              ),
              onClear: _buyerBirthDate != null
                  ? () => setState(() => _buyerBirthDate = null)
                  : null,
            ),
            _Field(label: 'Nacionalidade', controller: _buyerNationality),
          ]),
          _Row([
            _Field(label: 'Estado civil', controller: _buyerMaritalStatus),
            _Field(
              label: 'Regime de bens',
              controller: _buyerMarriageRegime,
            ),
          ]),
          _Field(label: 'Profissão', controller: _buyerProfession),
          _Row([
            _Field(
              label: 'E-mail',
              controller: _buyerEmail,
              keyboard: TextInputType.emailAddress,
            ),
            _Field(
              label: 'Telefone *',
              controller: _buyerPhone,
              keyboard: TextInputType.phone,
              formatters: [PhoneInputFormatter()],
            ),
          ]),
        ],
      ),
      _Section(
        title: 'Endereço do comprador',
        icon: Icons.location_on_outlined,
        accent: _hueGreen,
        subtitle: 'Digite o CEP para preencher automaticamente',
        children: [
          _Row([
            _Field(
              label: 'CEP',
              controller: _buyerZipCode,
              keyboard: TextInputType.number,
              formatters: [CepInputFormatter()],
              onChanged: (v) {
                final clean = v.replaceAll(RegExp(r'\D'), '');
                if (clean.length == 8) {
                  _buscarCep(
                    cep: clean,
                    setLoading: (b) =>
                        setState(() => _cepBuyerLoading = b),
                    onResult: (addr) {
                      setState(() {
                        _buyerStreet.text = addr.street ?? '';
                        _buyerNeighborhood.text = addr.neighborhood ?? '';
                        _buyerCity.text = addr.city ?? '';
                        _buyerState.text = addr.state ?? '';
                      });
                    },
                  );
                }
              },
            ),
            _CepSearchButton(
              loading: _cepBuyerLoading,
              onTap: () => _buscarCep(
                cep: _buyerZipCode.text,
                setLoading: (b) => setState(() => _cepBuyerLoading = b),
                onResult: (addr) {
                  setState(() {
                    _buyerStreet.text = addr.street ?? '';
                    _buyerNeighborhood.text = addr.neighborhood ?? '';
                    _buyerCity.text = addr.city ?? '';
                    _buyerState.text = addr.state ?? '';
                  });
                },
              ),
            ),
          ], flex: const [2, 1]),
          _Field(label: 'Logradouro', controller: _buyerStreet),
          _Row([
            _Field(label: 'Número', controller: _buyerNumber),
            _Field(label: 'Complemento', controller: _buyerComplement),
          ], flex: const [2, 3]),
          _Field(label: 'Bairro', controller: _buyerNeighborhood),
          _Row([
            _Field(label: 'Cidade', controller: _buyerCity),
            _UfDropdown(
              value: _buyerState.text,
              onChanged: (v) =>
                  setState(() => _buyerState.text = v ?? ''),
            ),
          ], flex: const [3, 2]),
        ],
      ),
      _Section(
        title: 'Cônjuge • Companheiro(a)',
        icon: Icons.favorite_outline_rounded,
        accent: _huePurple,
        subtitle: 'Inclua dados do cônjuge ou companheiro(a) do comprador',
        trailing: _SectionSwitch(
          value: _buyerHasSpouse,
          onChanged: (v) => setState(() => _buyerHasSpouse = v),
        ),
        children: _buyerHasSpouse
            ? [
                _Field(
                  label: 'Nome do cônjuge',
                  controller: _buyerSpouseName,
                  textCapitalization: TextCapitalization.words,
                ),
                _Row([
                  _Field(
                    label: 'CPF',
                    controller: _buyerSpouseCpf,
                    keyboard: TextInputType.number,
                    formatters: [CpfInputFormatter()],
                  ),
                  _Field(label: 'RG', controller: _buyerSpouseRg),
                ], flex: const [3, 2]),
                _Row([
                  _Field(
                    label: 'E-mail',
                    controller: _buyerSpouseEmail,
                    keyboard: TextInputType.emailAddress,
                  ),
                  _Field(
                    label: 'Telefone',
                    controller: _buyerSpousePhone,
                    keyboard: TextInputType.phone,
                    formatters: [PhoneInputFormatter()],
                  ),
                ]),
                _Field(
                  label: 'Profissão',
                  controller: _buyerSpouseProfession,
                ),
              ]
            : const [
                _SectionEmpty(
                  message:
                      'Sem cônjuge / companheiro(a). Ative o switch acima para incluir.',
                ),
              ],
      ),
      _Section(
        title: 'Imóvel pretendido',
        icon: Icons.apartment_rounded,
        accent: _hueYellow,
        subtitle: 'Identificação cartorária e endereço completo do imóvel',
        children: [
          _Row([
            _Field(
              label: 'Código',
              controller: _propertyCode,
              textCapitalization: TextCapitalization.characters,
            ),
            _Field(label: 'Matrícula', controller: _propertyRegistry),
          ]),
          _Row([
            _Field(label: 'Cartório', controller: _propertyNotary),
            _Field(
              label: 'Cadastro municipal',
              controller: _propertyCityRegistry,
            ),
          ]),
          _Row([
            _Field(
              label: 'CEP',
              controller: _propertyZipCode,
              keyboard: TextInputType.number,
              formatters: [CepInputFormatter()],
              onChanged: (v) {
                final clean = v.replaceAll(RegExp(r'\D'), '');
                if (clean.length == 8) {
                  _buscarCep(
                    cep: clean,
                    setLoading: (b) =>
                        setState(() => _cepPropertyLoading = b),
                    onResult: (addr) {
                      setState(() {
                        _propertyStreet.text = addr.street ?? '';
                        _propertyNeighborhood.text = addr.neighborhood ?? '';
                        _propertyCity.text = addr.city ?? '';
                        _propertyState.text = addr.state ?? '';
                      });
                    },
                  );
                }
              },
            ),
            _CepSearchButton(
              loading: _cepPropertyLoading,
              onTap: () => _buscarCep(
                cep: _propertyZipCode.text,
                setLoading: (b) =>
                    setState(() => _cepPropertyLoading = b),
                onResult: (addr) {
                  setState(() {
                    _propertyStreet.text = addr.street ?? '';
                    _propertyNeighborhood.text = addr.neighborhood ?? '';
                    _propertyCity.text = addr.city ?? '';
                    _propertyState.text = addr.state ?? '';
                  });
                },
              ),
            ),
          ], flex: const [2, 1]),
          _Field(label: 'Logradouro', controller: _propertyStreet),
          _Row([
            _Field(label: 'Número', controller: _propertyNumber),
            _Field(label: 'Complemento', controller: _propertyComplement),
          ], flex: const [2, 3]),
          _Field(label: 'Bairro', controller: _propertyNeighborhood),
          _Row([
            _Field(label: 'Cidade', controller: _propertyCity),
            _UfDropdown(
              value: _propertyState.text,
              onChanged: (v) =>
                  setState(() => _propertyState.text = v ?? ''),
            ),
          ], flex: const [3, 2]),
        ],
      ),
    ];
  }

  // ─── Etapa 2: Proprietário ─────────────────────────────────────────────

  List<Widget> _buildEtapa2() {
    return [
      _Section(
        title: 'Proprietário',
        icon: Icons.account_circle_outlined,
        accent: _hueBlue,
        subtitle: 'Dados de quem é dono(a) do imóvel pretendido',
        children: [
          _Field(
            label: 'Nome completo *',
            controller: _ownerName,
            textCapitalization: TextCapitalization.words,
          ),
          _Row([
            _Field(
              label: 'CPF / CNPJ *',
              controller: _ownerCpf,
              keyboard: TextInputType.number,
              formatters: [CpfInputFormatter()],
            ),
            _Field(label: 'RG', controller: _ownerRg),
          ], flex: const [3, 2]),
          _Row([
            _DateField(
              label: 'Data de nascimento',
              value: _ownerBirthDate,
              onPick: () => _pickDate(
                _ownerBirthDate,
                (d) => setState(() => _ownerBirthDate = d),
                allowFuture: false,
              ),
              onClear: _ownerBirthDate != null
                  ? () => setState(() => _ownerBirthDate = null)
                  : null,
            ),
            _Field(label: 'Nacionalidade', controller: _ownerNationality),
          ]),
          _Row([
            _Field(label: 'Estado civil', controller: _ownerMaritalStatus),
            _Field(
              label: 'Regime de bens',
              controller: _ownerMarriageRegime,
            ),
          ]),
          _Field(label: 'Profissão', controller: _ownerProfession),
          _Row([
            _Field(
              label: 'E-mail',
              controller: _ownerEmail,
              keyboard: TextInputType.emailAddress,
            ),
            _Field(
              label: 'Telefone',
              controller: _ownerPhone,
              keyboard: TextInputType.phone,
              formatters: [PhoneInputFormatter()],
            ),
          ]),
        ],
      ),
      _Section(
        title: 'Endereço do proprietário',
        icon: Icons.location_on_outlined,
        accent: _hueGreen,
        subtitle: 'Digite o CEP para preencher automaticamente',
        children: [
          _Row([
            _Field(
              label: 'CEP',
              controller: _ownerZipCode,
              keyboard: TextInputType.number,
              formatters: [CepInputFormatter()],
              onChanged: (v) {
                final clean = v.replaceAll(RegExp(r'\D'), '');
                if (clean.length == 8) {
                  _buscarCep(
                    cep: clean,
                    setLoading: (b) =>
                        setState(() => _cepOwnerLoading = b),
                    onResult: (addr) {
                      setState(() {
                        _ownerAddress.text = addr.street ?? '';
                        _ownerNeighborhood.text = addr.neighborhood ?? '';
                        _ownerCity.text = addr.city ?? '';
                        _ownerState.text = addr.state ?? '';
                      });
                    },
                  );
                }
              },
            ),
            _CepSearchButton(
              loading: _cepOwnerLoading,
              onTap: () => _buscarCep(
                cep: _ownerZipCode.text,
                setLoading: (b) => setState(() => _cepOwnerLoading = b),
                onResult: (addr) {
                  setState(() {
                    _ownerAddress.text = addr.street ?? '';
                    _ownerNeighborhood.text = addr.neighborhood ?? '';
                    _ownerCity.text = addr.city ?? '';
                    _ownerState.text = addr.state ?? '';
                  });
                },
              ),
            ),
          ], flex: const [2, 1]),
          _Field(label: 'Logradouro', controller: _ownerAddress),
          _Field(label: 'Bairro', controller: _ownerNeighborhood),
          _Row([
            _Field(label: 'Cidade', controller: _ownerCity),
            _UfDropdown(
              value: _ownerState.text,
              onChanged: (v) =>
                  setState(() => _ownerState.text = v ?? ''),
            ),
          ], flex: const [3, 2]),
        ],
      ),
      _Section(
        title: 'Cônjuge do proprietário',
        icon: Icons.favorite_outline_rounded,
        accent: _huePurple,
        subtitle: 'Inclua dados do cônjuge ou companheiro(a) do proprietário',
        trailing: _SectionSwitch(
          value: _ownerHasSpouse,
          onChanged: (v) => setState(() => _ownerHasSpouse = v),
        ),
        children: _ownerHasSpouse
            ? [
                _Field(
                  label: 'Nome do cônjuge',
                  controller: _ownerSpouseName,
                  textCapitalization: TextCapitalization.words,
                ),
                _Row([
                  _Field(
                    label: 'CPF',
                    controller: _ownerSpouseCpf,
                    keyboard: TextInputType.number,
                    formatters: [CpfInputFormatter()],
                  ),
                  _Field(label: 'RG', controller: _ownerSpouseRg),
                ], flex: const [3, 2]),
                _Row([
                  _Field(
                    label: 'E-mail',
                    controller: _ownerSpouseEmail,
                    keyboard: TextInputType.emailAddress,
                  ),
                  _Field(
                    label: 'Telefone',
                    controller: _ownerSpousePhone,
                    keyboard: TextInputType.phone,
                    formatters: [PhoneInputFormatter()],
                  ),
                ]),
                _Field(
                  label: 'Profissão',
                  controller: _ownerSpouseProfession,
                ),
              ]
            : const [
                _SectionEmpty(
                  message:
                      'Sem cônjuge / companheiro(a). Ative o switch acima para incluir.',
                ),
              ],
      ),
    ];
  }

  // ─── Etapa 3: Corretores / Captadores ──────────────────────────────────

  List<Widget> _buildEtapa3() {
    return [
      _Section(
        title: 'Corretores de venda',
        icon: Icons.badge_outlined,
        accent: _hueRed,
        subtitle: 'Inclua até 3 corretores responsáveis pela venda',
        children: [
          for (var i = 0; i < _brokers.length; i++)
            _BrokerBlock(
              key: ValueKey(_brokers[i].id),
              index: i,
              form: _brokers[i],
              onRemove: _brokers.length > 1
                  ? () => setState(() {
                        _brokers[i].dispose();
                        _brokers.removeAt(i);
                      })
                  : null,
            ),
          if (_brokers.length < 3)
            Align(
              alignment: Alignment.centerLeft,
              child: _AddItemButton(
                label: 'Adicionar corretor',
                onPressed: () =>
                    setState(() => _brokers.add(_BrokerForm())),
              ),
            ),
          const SizedBox(height: 6),
        ],
      ),
      _Section(
        title: 'Captadores',
        icon: Icons.groups_outlined,
        accent: _hueVinho,
        subtitle: 'Inclua até 3 captadores e suas porcentagens',
        children: [
          for (var i = 0; i < _captadores.length; i++)
            _CaptadorBlock(
              key: ValueKey(_captadores[i].id),
              index: i,
              form: _captadores[i],
              onRemove: _captadores.length > 1
                  ? () => setState(() {
                        _captadores[i].dispose();
                        _captadores.removeAt(i);
                      })
                  : null,
            ),
          if (_captadores.length < 3)
            Align(
              alignment: Alignment.centerLeft,
              child: _AddItemButton(
                label: 'Adicionar captador',
                onPressed: () =>
                    setState(() => _captadores.add(_CaptadorForm())),
              ),
            ),
          const SizedBox(height: 6),
        ],
      ),
    ];
  }
}

// ─── Step rail (cabeçalho de etapas) ─────────────────────────────────────

class _StepRail extends StatelessWidget {
  const _StepRail({
    required this.accent,
    required this.current,
    required this.maxLiberada,
    required this.isEditing,
    required this.onChanged,
  });

  final Color accent;
  final int current;
  final int maxLiberada;
  final bool isEditing;
  final ValueChanged<int> onChanged;

  static const _labels = ['Comprador', 'Proprietário', 'Corretor'];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.025)
            : const Color(0xFFFAFAFC),
        border: Border(
          bottom: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
          ),
        ),
      ),
      child: Row(
        children: [
          for (var i = 1; i <= 3; i++) ...[
            _StepNode(
              index: i,
              label: _labels[i - 1],
              selected: current == i,
              completed: i < current,
              locked: isEditing && i > maxLiberada,
              accent: accent,
              onTap: () => onChanged(i),
            ),
            if (i < 3)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 22, left: 4, right: 4),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    height: 2.5,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: i < current
                            ? [accent, accent.withValues(alpha: 0.55)]
                            : [
                                ThemeHelpers.borderColor(context),
                                ThemeHelpers.borderColor(context),
                              ],
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _StepNode extends StatelessWidget {
  const _StepNode({
    required this.index,
    required this.label,
    required this.selected,
    required this.completed,
    required this.locked,
    required this.accent,
    required this.onTap,
  });

  final int index;
  final String label;
  final bool selected;
  final bool completed;
  final bool locked;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final filled = selected || completed;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(40),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? accent : Colors.transparent,
                    border: Border.all(
                      color: filled
                          ? accent
                          : ThemeHelpers.borderColor(context),
                      width: 1.6,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.38),
                              blurRadius: 14,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: completed
                      ? const Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: Colors.white,
                        )
                      : Text(
                          '$index',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            color: filled
                                ? Colors.white
                                : ThemeHelpers.textSecondaryColor(context),
                          ),
                        ),
                ),
                if (locked && !completed)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ThemeHelpers.textSecondaryColor(context),
                        border: Border.all(
                          color: ThemeHelpers.cardBackgroundColor(context),
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.lock,
                        size: 8,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                letterSpacing: 0.25,
                color: selected
                    ? accent
                    : ThemeHelpers.textSecondaryColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Bottom bar ──────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.accent,
    required this.saving,
    required this.isEditing,
    required this.etapa,
    required this.canSign,
    required this.onSave,
    required this.onSaveAndSign,
  });

  final Color accent;
  final bool saving;
  final bool isEditing;
  final int etapa;
  final bool canSign;
  final VoidCallback onSave;
  final VoidCallback onSaveAndSign;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          top: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: ThemeHelpers.shadowColor(context),
            blurRadius: 22,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: saving ? null : onSave,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: Text(isEditing ? 'Salvar' : 'Salvar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(
                    color: accent.withValues(alpha: 0.55),
                    width: 1.4,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent,
                      Color.lerp(accent, Colors.black, 0.18)!,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.40),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: FilledButton.icon(
                  onPressed: (saving || !canSign) ? null : onSaveAndSign,
                  icon: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          canSign ? Icons.draw_rounded : Icons.lock,
                          size: 18,
                        ),
                  label: Text(
                    canSign ? _signLabel(etapa) : 'Etapa bloqueada',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _signLabel(int etapa) {
    switch (etapa) {
      case 2:
        return 'Salvar e assinar etapa 2';
      case 3:
        return 'Salvar e assinar etapa 3';
      default:
        return 'Salvar e assinar';
    }
  }
}

// ─── Tema por seção (InheritedWidget) ────────────────────────────────────

class _SectionTheme extends InheritedWidget {
  const _SectionTheme({required this.accent, required super.child});

  final Color accent;

  static Color of(BuildContext context) {
    final t = context.dependOnInheritedWidgetOfExactType<_SectionTheme>();
    return t?.accent ?? Theme.of(context).colorScheme.primary;
  }

  @override
  bool updateShouldNotify(_SectionTheme oldWidget) =>
      oldWidget.accent != accent;
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.accent,
    required this.children,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final List<Widget> children;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return _SectionTheme(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionBand(
            title: title,
            icon: icon,
            accent: accent,
            subtitle: subtitle,
            trailing: trailing,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(_kPagePad, 14, _kPagePad, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionBand extends StatelessWidget {
  const _SectionBand({
    required this.title,
    required this.icon,
    required this.accent,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            accent.withValues(alpha: isDark ? 0.18 : 0.11),
            accent.withValues(alpha: 0.0),
          ],
        ),
        border: Border(
          left: BorderSide(color: accent, width: 4),
          top: BorderSide(
            color: accent.withValues(alpha: 0.22),
            width: 1,
          ),
          bottom: BorderSide(
            color: accent.withValues(alpha: 0.22),
            width: 1,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.28 : 0.18),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: accent.withValues(alpha: 0.4),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, size: 20, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                        color: accent,
                        height: 1.15,
                      ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                          letterSpacing: 0.1,
                          height: 1.25,
                        ),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _SectionSwitch extends StatelessWidget {
  const _SectionSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = _SectionTheme.of(context);
    return Switch.adaptive(
      value: value,
      onChanged: onChanged,
      activeThumbColor: accent,
      activeTrackColor: accent.withValues(alpha: 0.45),
    );
  }
}

class _SectionEmpty extends StatelessWidget {
  const _SectionEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final accent = _SectionTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: accent.withValues(alpha: 0.85),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontStyle: FontStyle.italic,
                    height: 1.3,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Row helper para layout horizontal ───────────────────────────────────

class _Row extends StatelessWidget {
  const _Row(this.children, {this.flex});

  final List<Widget> children;
  final List<int>? flex;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          Expanded(
            flex: flex != null && i < flex!.length ? flex![i] : 1,
            child: children[i],
          ),
          if (i < children.length - 1) const SizedBox(width: _kFieldGapH),
        ],
      ],
    );
  }
}

// ─── Fields ──────────────────────────────────────────────────────────────

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.keyboard,
    this.formatters,
    this.hint,
    this.maxLines = 1,
    this.textCapitalization = TextCapitalization.sentences,
    this.suffix,
    this.prefixText,
    this.suffixText,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboard;
  final List<TextInputFormatter>? formatters;
  final String? hint;
  final int maxLines;
  final TextCapitalization textCapitalization;
  final Widget? suffix;
  final String? prefixText;
  final String? suffixText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = _SectionTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : const Color(0xFFF4F6F9);
    final borderC = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE2E6EC);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        inputFormatters: formatters,
        maxLines: maxLines,
        textCapitalization: textCapitalization,
        onChanged: onChanged,
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          color: ThemeHelpers.textColor(context),
          letterSpacing: 0.1,
        ),
        cursorColor: accent,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          filled: true,
          fillColor: fill,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          labelStyle: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: ThemeHelpers.textSecondaryColor(context),
            letterSpacing: 0.15,
          ),
          floatingLabelStyle: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: accent,
            letterSpacing: 0.45,
          ),
          floatingLabelBehavior: FloatingLabelBehavior.auto,
          hintStyle: TextStyle(
            color: ThemeHelpers.textSecondaryColor(context)
                .withValues(alpha: 0.7),
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
          ),
          prefixText: prefixText,
          suffixText: suffixText,
          prefixStyle: TextStyle(
            fontWeight: FontWeight.w900,
            color: accent,
          ),
          suffixStyle: TextStyle(
            fontWeight: FontWeight.w900,
            color: accent,
          ),
          suffixIcon: suffix,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(_kFieldRadius),
            borderSide: BorderSide(color: borderC, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(_kFieldRadius),
            borderSide: BorderSide(color: accent, width: 1.6),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(_kFieldRadius),
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onPick,
    this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final accent = _SectionTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : const Color(0xFFF4F6F9);
    final borderC = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE2E6EC);
    final text = value == null
        ? ''
        : '${value!.day.toString().padLeft(2, '0')}/${value!.month.toString().padLeft(2, '0')}/${value!.year}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(_kFieldRadius),
        child: InputDecorator(
          isEmpty: text.isEmpty,
          decoration: InputDecoration(
            labelText: label,
            filled: true,
            fillColor: fill,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            labelStyle: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ThemeHelpers.textSecondaryColor(context),
              letterSpacing: 0.15,
            ),
            floatingLabelStyle: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: accent,
              letterSpacing: 0.45,
            ),
            floatingLabelBehavior: FloatingLabelBehavior.always,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(_kFieldRadius),
              borderSide: BorderSide(color: borderC, width: 1),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(_kFieldRadius),
            ),
            suffixIcon: onClear != null
                ? IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                    onPressed: onClear,
                    visualDensity: VisualDensity.compact,
                  )
                : Icon(Icons.event_outlined, color: accent),
          ),
          child: Text(
            text.isEmpty ? 'Selecione' : text,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: text.isEmpty
                  ? ThemeHelpers.textSecondaryColor(context)
                      .withValues(alpha: 0.7)
                  : ThemeHelpers.textColor(context),
            ),
          ),
        ),
      ),
    );
  }
}

class _UfDropdown extends StatelessWidget {
  const _UfDropdown({required this.value, required this.onChanged});

  static const _items = [
    'AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA','PB',
    'PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO',
  ];

  final String value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = _SectionTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : const Color(0xFFF4F6F9);
    final borderC = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE2E6EC);
    final v = _items.contains(value) ? value : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        initialValue: v,
        isDense: true,
        decoration: InputDecoration(
          labelText: 'UF',
          filled: true,
          fillColor: fill,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          labelStyle: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
          floatingLabelStyle: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: accent,
            letterSpacing: 0.45,
          ),
          floatingLabelBehavior: FloatingLabelBehavior.auto,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(_kFieldRadius),
            borderSide: BorderSide(color: borderC, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(_kFieldRadius),
            borderSide: BorderSide(color: accent, width: 1.6),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(_kFieldRadius),
          ),
        ),
        icon: Icon(Icons.keyboard_arrow_down_rounded, color: accent),
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w800,
          color: ThemeHelpers.textColor(context),
        ),
        dropdownColor: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(_kFieldRadius),
        items: _items
            .map(
              (u) => DropdownMenuItem(
                value: u,
                child: Text(u),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}

class _CepSearchButton extends StatelessWidget {
  const _CepSearchButton({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = _SectionTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        height: 52,
        child: Material(
          color: accent.withValues(alpha: isDark ? 0.22 : 0.13),
          borderRadius: BorderRadius.circular(_kFieldRadius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: loading ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (loading)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: accent,
                      ),
                    )
                  else
                    Icon(
                      Icons.travel_explore_rounded,
                      size: 18,
                      color: accent,
                    ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Buscar',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: accent,
                        letterSpacing: 0.4,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SuffixAction extends StatelessWidget {
  const _SuffixAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = _SectionTheme.of(context);
    return IconButton(
      icon: Icon(icon, color: accent, size: 20),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _AddItemButton extends StatelessWidget {
  const _AddItemButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = _SectionTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(Icons.add_rounded, size: 18, color: accent),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: accent,
          backgroundColor: accent.withValues(alpha: 0.08),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: accent.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 0.25,
          ),
        ),
      ),
    );
  }
}

// ─── Corretores / Captadores ─────────────────────────────────────────────

class _BrokerForm {
  _BrokerForm({String? id})
      : id = id ?? UniqueKey().toString(),
        nome = TextEditingController(),
        email = TextEditingController(),
        unidade = TextEditingController();

  _BrokerForm.fromBroker(ProposalBroker b)
      : id = b.id,
        nome = TextEditingController(text: b.nome),
        email = TextEditingController(text: b.email ?? ''),
        unidade = TextEditingController(text: b.unidade ?? '');

  final String id;
  final TextEditingController nome;
  final TextEditingController email;
  final TextEditingController unidade;

  bool get isFilled => nome.text.trim().isNotEmpty;

  ProposalBroker toBroker() => ProposalBroker(
        id: id,
        nome: nome.text.trim(),
        email: email.text.trim().isEmpty ? null : email.text.trim(),
        unidade: unidade.text.trim().isEmpty ? null : unidade.text.trim(),
      );

  void dispose() {
    nome.dispose();
    email.dispose();
    unidade.dispose();
  }
}

class _BrokerBlock extends StatelessWidget {
  const _BrokerBlock({
    super.key,
    required this.index,
    required this.form,
    this.onRemove,
  });

  final int index;
  final _BrokerForm form;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ItemHeader(
            index: index,
            title: 'Corretor',
            onRemove: onRemove,
          ),
          _Field(
            label: 'Nome *',
            controller: form.nome,
            textCapitalization: TextCapitalization.words,
          ),
          _Row([
            _Field(
              label: 'E-mail',
              controller: form.email,
              keyboard: TextInputType.emailAddress,
            ),
            _Field(label: 'Unidade', controller: form.unidade),
          ]),
        ],
      ),
    );
  }
}

class _CaptadorForm {
  _CaptadorForm({String? id})
      : id = id ?? UniqueKey().toString(),
        nome = TextEditingController(),
        unidade = TextEditingController(),
        porcentagem = TextEditingController();

  _CaptadorForm.fromCaptador(ProposalCaptador c)
      : id = c.id,
        nome = TextEditingController(text: c.nome),
        unidade = TextEditingController(text: c.unidade ?? ''),
        porcentagem = TextEditingController(
          text: c.porcentagem != null
              ? c.porcentagem!.toStringAsFixed(2).replaceAll('.', ',')
              : '',
        );

  final String id;
  final TextEditingController nome;
  final TextEditingController unidade;
  final TextEditingController porcentagem;

  bool get isFilled => nome.text.trim().isNotEmpty;

  ProposalCaptador toCaptador() {
    double? pct;
    final raw = porcentagem.text.trim();
    if (raw.isNotEmpty) {
      pct = double.tryParse(raw.replaceAll('.', '').replaceAll(',', '.'));
    }
    return ProposalCaptador(
      id: id,
      nome: nome.text.trim(),
      unidade: unidade.text.trim().isEmpty ? null : unidade.text.trim(),
      porcentagem: pct,
    );
  }

  void dispose() {
    nome.dispose();
    unidade.dispose();
    porcentagem.dispose();
  }
}

class _CaptadorBlock extends StatelessWidget {
  const _CaptadorBlock({
    super.key,
    required this.index,
    required this.form,
    this.onRemove,
  });

  final int index;
  final _CaptadorForm form;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ItemHeader(
            index: index,
            title: 'Captador',
            onRemove: onRemove,
          ),
          _Field(
            label: 'Nome *',
            controller: form.nome,
            textCapitalization: TextCapitalization.words,
          ),
          _Row([
            _Field(label: 'Unidade', controller: form.unidade),
            _Field(
              label: 'Porcentagem',
              controller: form.porcentagem,
              keyboard: TextInputType.number,
              formatters: [PercentageInputFormatter()],
              suffixText: '%',
            ),
          ]),
        ],
      ),
    );
  }
}

class _ItemHeader extends StatelessWidget {
  const _ItemHeader({
    required this.index,
    required this.title,
    this.onRemove,
  });

  final int index;
  final String title;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final accent = _SectionTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 10),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.16),
              border: Border.all(
                color: accent.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$title #${index + 1}',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: accent,
              letterSpacing: 0.4,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          if (onRemove != null)
            InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.delete_outline_rounded,
                      size: 16,
                      color: accent.withValues(alpha: 0.85),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Remover',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: accent.withValues(alpha: 0.85),
                        fontSize: 12,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
