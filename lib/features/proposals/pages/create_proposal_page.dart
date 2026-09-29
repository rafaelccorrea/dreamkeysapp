import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/cep_service.dart';
import '../../../shared/services/purchase_proposals_service.dart';
import '../../../shared/services/secure_storage_service.dart';
import '../../../shared/utils/input_formatters.dart';
import '../../../shared/utils/jwt_utils.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../utils/proposal_form_rules.dart';
import '../widgets/proposal_signatures_sheet.dart';

/// Cria ou edita uma ficha de proposta — paridade 1:1 com o
/// `CreatePurchaseProposalPage.tsx` (web = fonte da verdade):
///   - 3 etapas (Comprador, Proprietário, Corretor); 2 e 3 travadas até a
///     etapa anterior ser assinada (`maxEtapaLiberadaParaEnvio` do histórico);
///   - etapa 1 em 4 abas (Proposta, Proponente, Cônjuge, Imóvel);
///   - validação só da etapa atual, com as mesmas regras e mensagens;
///   - payload idêntico ao do web (ver `CreateProposalPayload`);
///   - etapa 3 = usuários que poderão ver a proposta (`addUsers`);
///   - editar etapa já assinada pede confirmação e reinicia o fluxo.
class CreateProposalPage extends StatefulWidget {
  const CreateProposalPage({super.key, this.proposalId});

  final String? proposalId;

  bool get isEditing => proposalId != null;

  @override
  State<CreateProposalPage> createState() => _CreateProposalPageState();
}

/// Abas internas da etapa 1 (web `TABS_ETAPA_1`).
const List<(String, IconData)> _kTabsEtapa1 = [
  ('Proposta', LucideIcons.handshake),
  ('Proponente', LucideIcons.user),
  ('Cônjuge', LucideIcons.heart),
  ('Imóvel', LucideIcons.house),
];

/// Campos de erro de cada aba da etapa 1 — decide para qual aba pular
/// quando a validação falha (mesma ordem do `validate()` do web).
const Set<String> _kTab0Keys = {
  'proposalDate', 'teamId', 'proposedPrice', 'validityDays',
  'downPaymentDays', 'deliveryDays', 'paymentConditions',
  'commissionPercentage',
};
const Set<String> _kTab1Keys = {
  'proponentName', 'proponentCpf', 'proponentBirthDate', 'proponentEmail',
  'proponentPhone', 'proponentZipCode',
};
const Set<String> _kTab2Keys = {
  'proponentSpouseCpf', 'proponentSpouseEmail', 'proponentSpousePhone',
};
const Set<String> _kTab3Keys = {
  'propertyAddress', 'propertyNeighborhood', 'propertyCity', 'propertyState',
};

const int _kMaxLinkedUsers = 10;

class _CreateProposalPageState extends State<CreateProposalPage> {
  final _scroll = ScrollController();

  int _etapa = 1;
  int _tab = 0;
  int _maxLiberada = 1;
  bool _loading = false;
  bool _saving = false;
  String _proposalNumber = '';
  ProposalStatus? _loadedStatus;
  bool _avisoFinalizada = false;
  Map<String, String>? _loadedSnap1;
  Map<String, String>? _loadedSnap2;
  Map<int, bool> _concluidas = {1: false, 2: false, 3: false};

  final Map<String, String> _errors = {};

  // Catálogos (mesmas fontes do web)
  List<ProposalOption> _teams = const [];
  bool _loadingTeams = true;
  List<ProposalOption> _units = const [];
  List<ProposalMember> _members = const [];
  bool _loadingMembers = true;
  String? _currentUserId;
  final List<String> _linkedUserIds = [];

  // ── Etapa 1 · Dados da proposta ─────────────────────────────────────────
  DateTime? _proposalDate;
  final _validityDays = TextEditingController(text: '5');
  final _proposedPrice = TextEditingController();
  final _commission = TextEditingController();
  final _downPayment = TextEditingController();
  final _downPaymentDays = TextEditingController();
  final _deliveryDays = TextEditingController(text: '30');
  final _monthlyPenalty = TextEditingController();
  final _paymentConditions = TextEditingController();
  String _teamId = '';
  String _saleUnit = '';
  String _captureUnit = '';

  /// O web não mostra "Observações" na tela: o valor só viaja no payload.
  String _observations = '';

  // ── Etapa 1 · Proponente ────────────────────────────────────────────────
  final _buyerName = TextEditingController();
  final _buyerCpf = TextEditingController();
  final _buyerRg = TextEditingController();
  DateTime? _buyerBirth;
  final _buyerNationality = TextEditingController(text: 'Brasileiro(a)');
  String _buyerMarital = '';
  String _buyerRegime = '';
  final _buyerProfession = TextEditingController();
  final _buyerEmail = TextEditingController();
  final _buyerPhone = TextEditingController();
  final _buyerZip = TextEditingController();
  final _buyerAddress = TextEditingController();
  final _buyerNeighborhood = TextEditingController();
  final _buyerCity = TextEditingController();
  String _buyerState = '';

  // ── Etapa 1 · Cônjuge do proponente ─────────────────────────────────────
  final _bsName = TextEditingController();
  final _bsCpf = TextEditingController();
  final _bsRg = TextEditingController();
  final _bsProfession = TextEditingController();
  final _bsPhone = TextEditingController();
  final _bsEmail = TextEditingController();

  // ── Etapa 1 · Imóvel ────────────────────────────────────────────────────
  final _propCode = TextEditingController();
  final _propRegistry = TextEditingController();
  final _propNotary = TextEditingController();
  final _propZip = TextEditingController();
  final _propAddress = TextEditingController();
  final _propNeighborhood = TextEditingController();
  final _propCity = TextEditingController();
  String _propState = '';

  // ── Etapa 2 · Proprietário ──────────────────────────────────────────────
  final _ownerName = TextEditingController();
  final _ownerCpf = TextEditingController();
  final _ownerRg = TextEditingController();
  DateTime? _ownerBirth;
  final _ownerNationality = TextEditingController(text: 'Brasileiro(a)');
  String _ownerMarital = '';
  String _ownerRegime = '';
  final _ownerProfession = TextEditingController();
  final _ownerEmail = TextEditingController();
  final _ownerPhone = TextEditingController();
  final _ownerZip = TextEditingController();
  final _ownerAddress = TextEditingController();
  final _ownerNeighborhood = TextEditingController();
  final _ownerCity = TextEditingController();
  String _ownerState = '';

  // ── Etapa 2 · Cônjuge do proprietário ───────────────────────────────────
  final _osName = TextEditingController();
  final _osCpf = TextEditingController();
  final _osProfession = TextEditingController();
  final _osEmail = TextEditingController();
  final _osPhone = TextEditingController();

  /// O web guarda `ownerSpouseRg` mas não tem campo na tela da etapa 2.
  String _osRg = '';

  bool _cepBuyer = false;
  bool _cepProp = false;
  bool _cepOwner = false;
  bool _searchingProperty = false;
  final Map<String, String> _lastAutoCep = {};

  List<TextEditingController> get _controllers => [
        _validityDays, _proposedPrice, _commission, _downPayment,
        _downPaymentDays, _deliveryDays, _monthlyPenalty, _paymentConditions,
        _buyerName, _buyerCpf, _buyerRg, _buyerNationality, _buyerProfession,
        _buyerEmail, _buyerPhone, _buyerZip, _buyerAddress, _buyerNeighborhood,
        _buyerCity, _bsName, _bsCpf, _bsRg, _bsProfession, _bsPhone, _bsEmail,
        _propCode, _propRegistry, _propNotary, _propZip, _propAddress,
        _propNeighborhood, _propCity, _ownerName, _ownerCpf, _ownerRg,
        _ownerNationality, _ownerProfession, _ownerEmail, _ownerPhone,
        _ownerZip, _ownerAddress, _ownerNeighborhood, _ownerCity, _osName,
        _osCpf, _osProfession, _osEmail, _osPhone,
      ];

  Color get _brand => Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;

  @override
  void initState() {
    super.initState();
    _loading = widget.isEditing;
    _loadCatalogs();
    if (widget.isEditing) _loadExisting();
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Carregamento ────────────────────────────────────────────────────────

  Future<void> _loadCatalogs() async {
    final svc = PurchaseProposalsService.instance;
    final teamsF = svc.listTeamsForProposal();
    final unitsF = svc.listSaleUnits();
    final membersF = svc.listCompanyMembers();
    final uidF = _readCurrentUserId();
    final teams = await teamsF;
    if (!mounted) return;
    setState(() {
      _teams = teams.data ?? const [];
      _loadingTeams = false;
    });
    final units = await unitsF;
    if (!mounted) return;
    setState(() => _units = units.data ?? const []);
    final members = await membersF;
    final uid = await uidF;
    if (!mounted) return;
    setState(() {
      _members = members.data ?? const [];
      _loadingMembers = false;
      _currentUserId = uid;
    });
  }

  Future<String?> _readCurrentUserId() async {
    try {
      final token = await SecureStorageService.instance.getAccessToken();
      if (token == null) return null;
      final claims = JwtUtils.decodeToken(token);
      final id = claims?['sub'] ?? claims?['userId'] ?? claims?['id'];
      return id?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadExisting() async {
    final svc = PurchaseProposalsService.instance;
    final pF = svc.getById(widget.proposalId!);
    final hF = svc.getHistorico(widget.proposalId!);
    final res = await pF;
    final hist = await hF;
    if (!mounted) return;
    if (!res.success || res.data == null) {
      _toast(res.message ?? 'Erro ao carregar proposta', error: true);
      Navigator.of(context).maybePop();
      return;
    }
    final p = res.data!;
    if (p.status == ProposalStatus.canceled) {
      _toast('Proposta cancelada não pode ser editada.');
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _hydrate(p);
      _loadedSnap1 = _snapshot1();
      _loadedSnap2 = _snapshot2();
      _loadedStatus = p.status;
      final h = hist.success ? hist.data : null;
      if (h != null) {
        _concluidas = {
          1: _etapaConcluida(h, 1),
          2: _etapaConcluida(h, 2),
          3: _etapaConcluida(h, 3),
        };
        final max = h.maxEtapaLiberadaParaEnvio ?? 1;
        _maxLiberada = max;
        _etapa = max.clamp(1, 3);
      } else {
        _concluidas = {1: false, 2: false, 3: false};
        _maxLiberada = 1;
        _etapa = 1;
      }
      _linkedUserIds
        ..clear()
        ..addAll(p.linkedUserIds);
      _proposalNumber =
          p.proposalNumber.isNotEmpty ? p.proposalNumber : widget.proposalId!;
      _avisoFinalizada = p.status == ProposalStatus.finalized;
      _loading = false;
    });
  }

  /// Anexo aprovado OU todas as assinaturas ativas da etapa assinadas
  /// (`etapaEstaConcluidaNoHistorico` do web).
  bool _etapaConcluida(ProposalHistorico h, int etapa) {
    final anexoOk =
        h.attachments.any((a) => a.etapa == etapa && a.status == 'approved');
    if (anexoOk) return true;
    final sigs = h.signatures
        .where((s) =>
            s.etapa == etapa && s.status.toLowerCase() != 'cancelled')
        .toList();
    if (sigs.isEmpty) return false;
    return sigs.every((s) => s.status.toLowerCase() == 'signed');
  }

  /// Web: data de nascimento igual a hoje nunca é exibida.
  DateTime? _sanitizeBirth(DateTime? d) {
    if (d == null) return null;
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return null;
    }
    return d;
  }

  void _hydrate(PurchaseProposal p) {
    String up(String? v) => (v ?? '').toUpperCase();
    _proposalDate = p.proposalDate;
    _validityDays.text = '${p.validityDays ?? 5}';
    _proposedPrice.text = ProposalRules.formatDecimal(p.proposedPrice);
    _paymentConditions.text = p.paymentConditions ?? '';
    _downPayment.text = ProposalRules.formatDecimal(p.downPayment);
    _downPaymentDays.text =
        p.downPaymentDays != null ? '${p.downPaymentDays}' : '';
    _commission.text = ProposalRules.formatDecimal(p.commissionPercentage);
    _deliveryDays.text = '${p.deliveryDays ?? 30}';
    _monthlyPenalty.text = ProposalRules.formatDecimal(p.monthlyPenalty);
    _teamId = p.teamId ?? '';
    _saleUnit = p.saleUnit ?? '';
    _captureUnit = p.captureUnit ?? '';
    _observations = p.observations ?? '';

    _buyerName.text = p.proponentName ?? '';
    _buyerCpf.text = ProposalRules.maskCpfOuCnpj(p.proponentCpf ?? '');
    _buyerRg.text = p.proponentRg ?? '';
    _buyerNationality.text = p.proponentNationality ?? 'Brasileiro(a)';
    _buyerMarital = p.proponentMaritalStatus ?? '';
    _buyerRegime = p.proponentMarriageRegime ?? '';
    _buyerBirth = _sanitizeBirth(p.proponentBirthDate);
    _buyerProfession.text = p.proponentProfession ?? '';
    _buyerEmail.text = p.proponentEmail ?? '';
    _buyerPhone.text = ProposalRules.maskPhone(p.proponentPhone ?? '');
    _buyerZip.text = ProposalRules.maskCep(p.proponentZipCode ?? '');
    _buyerAddress.text = p.proponentAddress ?? '';
    _buyerNeighborhood.text = p.proponentNeighborhood ?? '';
    _buyerCity.text = p.proponentCity ?? '';
    _buyerState = up(p.proponentState);

    _bsName.text = p.proponentSpouseName ?? '';
    _bsCpf.text = ProposalRules.maskCpf(p.proponentSpouseCpf ?? '');
    _bsRg.text = p.proponentSpouseRg ?? '';
    _bsProfession.text = p.proponentSpouseProfession ?? '';
    _bsEmail.text = p.proponentSpouseEmail ?? '';
    _bsPhone.text = ProposalRules.maskPhone(p.proponentSpousePhone ?? '');

    _propRegistry.text = p.propertyRegistry ?? '';
    _propNotary.text = p.propertyNotary ?? '';
    _propCode.text = p.propertyCode ?? '';
    _propZip.text = ProposalRules.maskCep(p.propertyZipCode ?? '');
    _propAddress.text = p.propertyAddress ?? '';
    _propNeighborhood.text = p.propertyNeighborhood ?? '';
    _propCity.text = p.propertyCity ?? '';
    _propState = up(p.propertyState);

    _ownerName.text = p.ownerName ?? '';
    _ownerRg.text = p.ownerRg ?? '';
    _ownerCpf.text = ProposalRules.maskCpfOuCnpj(p.ownerCpf ?? '');
    _ownerNationality.text = p.ownerNationality ?? 'Brasileiro(a)';
    _ownerMarital = p.ownerMaritalStatus ?? '';
    _ownerRegime = p.ownerMarriageRegime ?? '';
    _ownerBirth = _sanitizeBirth(p.ownerBirthDate);
    _ownerProfession.text = p.ownerProfession ?? '';
    _ownerEmail.text = p.ownerEmail ?? '';
    _ownerPhone.text = ProposalRules.maskPhone(p.ownerPhone ?? '');
    _ownerZip.text = ProposalRules.maskCep(p.ownerZipCode ?? '');
    _ownerAddress.text = p.ownerAddress ?? '';
    _ownerNeighborhood.text = p.ownerNeighborhood ?? '';
    _ownerCity.text = p.ownerCity ?? '';
    _ownerState = up(p.ownerState);

    _osName.text = p.ownerSpouseName ?? '';
    _osRg = p.ownerSpouseRg ?? '';
    _osCpf.text = ProposalRules.maskCpf(p.ownerSpouseCpf ?? '');
    _osProfession.text = p.ownerSpouseProfession ?? '';
    _osEmail.text = p.ownerSpouseEmail ?? '';
    _osPhone.text = ProposalRules.maskPhone(p.ownerSpousePhone ?? '');
  }

  // ── Snapshot (detecta edição em etapa já assinada) ──────────────────────

  static String _iso(DateTime? d) => d == null
      ? ''
      : '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

  static String _num(String v) =>
      (ProposalRules.parseDecimal(v) ?? 0).toString();

  static String _dig(String v) => ProposalRules.digits(v);

  Map<String, String> _snapshot1() => {
        'proposalDate': _iso(_proposalDate),
        'validityDays': _validityDays.text.trim(),
        'proposedPrice': _num(_proposedPrice.text),
        'paymentConditions': _paymentConditions.text.trim(),
        'downPayment': _num(_downPayment.text),
        'downPaymentDays': _downPaymentDays.text.trim(),
        'commissionPercentage': _num(_commission.text),
        'deliveryDays': _deliveryDays.text.trim(),
        'monthlyPenalty': _num(_monthlyPenalty.text),
        'teamId': _teamId.trim(),
        'saleUnit': _saleUnit.trim(),
        'captureUnit': _captureUnit.trim(),
        'observations': _observations.trim(),
        'proponentName': _buyerName.text.trim(),
        'proponentCpf': _dig(_buyerCpf.text),
        'proponentRg': _buyerRg.text.trim(),
        'proponentNationality': _buyerNationality.text.trim(),
        'proponentMaritalStatus': _buyerMarital.trim(),
        'proponentMarriageRegime': _buyerRegime.trim(),
        'proponentBirthDate': _iso(_buyerBirth),
        'proponentProfession': _buyerProfession.text.trim(),
        'proponentEmail': _buyerEmail.text.trim(),
        'proponentPhone': _dig(_buyerPhone.text),
        'proponentAddress': _buyerAddress.text.trim(),
        'proponentNeighborhood': _buyerNeighborhood.text.trim(),
        'proponentZipCode': _dig(_buyerZip.text),
        'proponentCity': _buyerCity.text.trim(),
        'proponentState': _buyerState.trim(),
        'proponentSpouseName': _bsName.text.trim(),
        'proponentSpouseCpf': _dig(_bsCpf.text),
        'proponentSpouseRg': _bsRg.text.trim(),
        'proponentSpouseProfession': _bsProfession.text.trim(),
        'proponentSpouseEmail': _bsEmail.text.trim(),
        'proponentSpousePhone': _dig(_bsPhone.text),
        'propertyRegistry': _propRegistry.text.trim(),
        'propertyNotary': _propNotary.text.trim(),
        'propertyCode': _propCode.text.trim(),
        'propertyZipCode': _dig(_propZip.text),
        'propertyAddress': _propAddress.text.trim(),
        'propertyNeighborhood': _propNeighborhood.text.trim(),
        'propertyCity': _propCity.text.trim(),
        'propertyState': _propState.trim(),
      };

  Map<String, String> _snapshot2() => {
        'ownerName': _ownerName.text.trim(),
        'ownerRg': _ownerRg.text.trim(),
        'ownerCpf': _dig(_ownerCpf.text),
        'ownerNationality': _ownerNationality.text.trim(),
        'ownerMaritalStatus': _ownerMarital.trim(),
        'ownerMarriageRegime': _ownerRegime.trim(),
        'ownerBirthDate': _iso(_ownerBirth),
        'ownerProfession': _ownerProfession.text.trim(),
        'ownerEmail': _ownerEmail.text.trim(),
        'ownerPhone': _dig(_ownerPhone.text),
        'ownerZipCode': _dig(_ownerZip.text),
        'ownerAddress': _ownerAddress.text.trim(),
        'ownerNeighborhood': _ownerNeighborhood.text.trim(),
        'ownerCity': _ownerCity.text.trim(),
        'ownerState': _ownerState.trim(),
        'ownerSpouseName': _osName.text.trim(),
        'ownerSpouseRg': _osRg.trim(),
        'ownerSpouseCpf': _dig(_osCpf.text),
        'ownerSpouseProfession': _osProfession.text.trim(),
        'ownerSpouseEmail': _osEmail.text.trim(),
        'ownerSpousePhone': _dig(_osPhone.text),
      };

  static bool _sameMap(Map<String, String> a, Map<String, String>? b) {
    if (b == null || a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  /// `getReinicioDecision` do web.
  ({bool needsReinicio, List<String> etapas}) _reinicioDecision() {
    final finalized = _loadedStatus == ProposalStatus.finalized;
    if (_loadedSnap1 == null) {
      return (
        needsReinicio: finalized,
        etapas: finalized ? const ['Proposta finalizada'] : const <String>[],
      );
    }
    final alterou1 = !_sameMap(_snapshot1(), _loadedSnap1);
    final alterou2 = !_sameMap(_snapshot2(), _loadedSnap2);
    final any = alterou1 || alterou2;
    final violou1 = alterou1 && (_concluidas[1] ?? false);
    final violou2 = alterou2 && (_concluidas[2] ?? false);
    final msgs = <String>[
      if (violou1) 'Etapa 1 (comprador, proposta e imóvel)',
      if (violou2) 'Etapa 2 (proprietário)',
    ];
    if (finalized && any && msgs.isEmpty) msgs.add('Proposta finalizada');
    return (
      needsReinicio: violou1 || violou2 || (finalized && any),
      etapas: msgs,
    );
  }

  // ── Validação (só a etapa atual, igual ao web) ──────────────────────────

  bool _validate() {
    final e = <String, String>{};
    String t(TextEditingController c) => c.text.trim();
    if (_etapa == 1) {
      if (_proposalDate == null) {
        e['proposalDate'] = 'Data da proposta é obrigatória';
      }
      if (!widget.isEditing && _teamId.trim().isEmpty) {
        e['teamId'] = 'Equipe da proposta é obrigatória';
      }
      if (_proposedPrice.text.isEmpty) {
        e['proposedPrice'] = 'Preço proposto é obrigatório';
      }
      if (t(_validityDays).isNotEmpty &&
          !ProposalRules.isValidDays(_validityDays.text)) {
        e['validityDays'] = 'Validade inválida (1–365 dias)';
      }
      if (t(_downPaymentDays).isNotEmpty &&
          !ProposalRules.isValidDays(_downPaymentDays.text)) {
        e['downPaymentDays'] = 'Prazo inválido (1–365 dias)';
      }
      if (t(_deliveryDays).isNotEmpty &&
          !ProposalRules.isValidDays(_deliveryDays.text)) {
        e['deliveryDays'] = 'Prazo inválido (1–365 dias)';
      }
      if (t(_paymentConditions).isEmpty) {
        e['paymentConditions'] = 'Condições de pagamento são obrigatórias';
      } else if (_paymentConditions.text.length > 2000) {
        e['paymentConditions'] = 'Máximo 2000 caracteres';
      }
      if (_commission.text.isEmpty) {
        e['commissionPercentage'] = 'Comissão é obrigatória';
      }
      if (t(_commission).isNotEmpty &&
          !ProposalRules.isValidPercentage(_commission.text)) {
        e['commissionPercentage'] = 'Percentual inválido (0–100)';
      }
      if (t(_buyerName).isEmpty) {
        e['proponentName'] = 'Nome do proponente é obrigatório';
      }
      if (t(_buyerCpf).isEmpty) {
        e['proponentCpf'] = 'CPF ou CNPJ do proponente é obrigatório';
      } else if (!ProposalRules.isValidCpfOuCnpj(_buyerCpf.text)) {
        e['proponentCpf'] = 'CPF ou CNPJ inválido';
      }
      if (t(_buyerPhone).isEmpty) {
        e['proponentPhone'] = 'Telefone do proponente é obrigatório';
      } else if (!ProposalRules.isValidPhone(_buyerPhone.text)) {
        e['proponentPhone'] = 'Telefone inválido';
      }
      final birth = _buyerBirth;
      if (birth != null) {
        final today = DateTime.now();
        if (birth.isAfter(today)) {
          e['proponentBirthDate'] = 'Data de nascimento não pode ser futura';
        } else if (ProposalRules.ageInYears(birth, today) < 18) {
          e['proponentBirthDate'] = 'Proponente deve ter pelo menos 18 anos';
        }
      }
      if (t(_buyerEmail).isNotEmpty &&
          !ProposalRules.isValidEmail(_buyerEmail.text)) {
        e['proponentEmail'] = 'E-mail inválido';
      }
      if (t(_buyerZip).isNotEmpty && !ProposalRules.isValidCep(_buyerZip.text)) {
        e['proponentZipCode'] = 'CEP inválido';
      }
      if (t(_bsCpf).isNotEmpty && !ProposalRules.isValidCpf(_bsCpf.text)) {
        e['proponentSpouseCpf'] = 'CPF inválido';
      }
      if (t(_bsEmail).isNotEmpty && !ProposalRules.isValidEmail(_bsEmail.text)) {
        e['proponentSpouseEmail'] = 'E-mail inválido';
      }
      if (t(_bsPhone).isNotEmpty && !ProposalRules.isValidPhone(_bsPhone.text)) {
        e['proponentSpousePhone'] = 'Telefone inválido';
      }
      if (t(_propAddress).isEmpty) {
        e['propertyAddress'] = 'Endereço do imóvel é obrigatório';
      }
      if (t(_propNeighborhood).isEmpty) {
        e['propertyNeighborhood'] = 'Bairro do imóvel é obrigatório';
      }
      if (t(_propCity).isEmpty) {
        e['propertyCity'] = 'Cidade do imóvel é obrigatória';
      }
      if (_propState.trim().isEmpty) {
        e['propertyState'] = 'Estado do imóvel é obrigatório';
      }
    }
    if (_etapa == 2) {
      if (t(_ownerName).isEmpty) {
        e['ownerName'] = 'Nome do proprietário é obrigatório';
      }
      if (t(_ownerCpf).isEmpty) {
        e['ownerCpf'] = 'CPF ou CNPJ do proprietário é obrigatório';
      } else if (!ProposalRules.isValidCpfOuCnpj(_ownerCpf.text)) {
        e['ownerCpf'] = 'CPF ou CNPJ inválido';
      }
      if (t(_ownerPhone).isEmpty) {
        e['ownerPhone'] = 'Telefone do proprietário é obrigatório';
      } else if (!ProposalRules.isValidPhone(_ownerPhone.text)) {
        e['ownerPhone'] = 'Telefone inválido';
      }
      if (t(_ownerEmail).isNotEmpty &&
          !ProposalRules.isValidEmail(_ownerEmail.text)) {
        e['ownerEmail'] = 'E-mail inválido';
      }
      if (t(_osCpf).isNotEmpty && !ProposalRules.isValidCpf(_osCpf.text)) {
        e['ownerSpouseCpf'] = 'CPF inválido';
      }
      if (t(_osEmail).isNotEmpty && !ProposalRules.isValidEmail(_osEmail.text)) {
        e['ownerSpouseEmail'] = 'E-mail inválido';
      }
      if (t(_osPhone).isNotEmpty && !ProposalRules.isValidPhone(_osPhone.text)) {
        e['ownerSpousePhone'] = 'Telefone inválido';
      }
    }
    setState(() {
      _errors
        ..clear()
        ..addAll(e);
      if (e.isNotEmpty && _etapa == 1) {
        final keys = e.keys.toSet();
        if (keys.intersection(_kTab0Keys).isNotEmpty) {
          _tab = 0;
        } else if (keys.intersection(_kTab1Keys).isNotEmpty) {
          _tab = 1;
        } else if (keys.intersection(_kTab2Keys).isNotEmpty) {
          _tab = 2;
        } else if (keys.intersection(_kTab3Keys).isNotEmpty) {
          _tab = 3;
        }
      }
    });
    if (e.isNotEmpty) _scrollTop();
    return e.isEmpty;
  }

  // ── Payload ─────────────────────────────────────────────────────────────

  CreateProposalPayload _buildPayload() {
    final money = ProposalRules.parseDecimal;
    return CreateProposalPayload()
      ..proposalDate = _proposalDate
      ..validityDays = _validityDays.text
      ..proposedPrice = money(_proposedPrice.text)
      ..paymentConditions = _paymentConditions.text
      ..downPayment =
          _downPayment.text.isEmpty ? null : money(_downPayment.text)
      ..downPaymentDays = _downPaymentDays.text
      ..commissionPercentage = money(_commission.text)
      ..deliveryDays = _deliveryDays.text
      ..monthlyPenalty =
          _monthlyPenalty.text.isEmpty ? null : money(_monthlyPenalty.text)
      ..teamId = _teamId
      ..saleUnit = _saleUnit
      ..captureUnit = _captureUnit
      ..observations = _observations
      ..buyerName = _buyerName.text
      ..buyerCpf = _buyerCpf.text
      ..buyerRg = _buyerRg.text
      ..buyerBirthDate = _buyerBirth
      ..buyerEmail = _buyerEmail.text
      ..buyerPhone = _buyerPhone.text
      ..buyerProfession = _buyerProfession.text
      ..buyerNationality = _buyerNationality.text
      ..buyerMaritalStatus = _buyerMarital
      ..buyerMarriageRegime = _buyerRegime
      ..buyerZipCode = _buyerZip.text
      ..buyerAddress = _buyerAddress.text
      ..buyerNeighborhood = _buyerNeighborhood.text
      ..buyerCity = _buyerCity.text
      ..buyerState = _buyerState
      ..buyerSpouseName = _bsName.text
      ..buyerSpouseCpf = _bsCpf.text
      ..buyerSpouseRg = _bsRg.text
      ..buyerSpouseEmail = _bsEmail.text
      ..buyerSpousePhone = _bsPhone.text
      ..buyerSpouseProfession = _bsProfession.text
      ..propertyRegistry = _propRegistry.text
      ..propertyNotary = _propNotary.text
      ..propertyCode = _propCode.text
      ..propertyZipCode = _propZip.text
      ..propertyAddress = _propAddress.text
      ..propertyNeighborhood = _propNeighborhood.text
      ..propertyCity = _propCity.text
      ..propertyState = _propState
      ..ownerName = _ownerName.text
      ..ownerCpf = _ownerCpf.text
      ..ownerRg = _ownerRg.text
      ..ownerBirthDate = _ownerBirth
      ..ownerEmail = _ownerEmail.text
      ..ownerPhone = _ownerPhone.text
      ..ownerProfession = _ownerProfession.text
      ..ownerNationality = _ownerNationality.text
      ..ownerMaritalStatus = _ownerMarital
      ..ownerMarriageRegime = _ownerRegime
      ..ownerZipCode = _ownerZip.text
      ..ownerAddress = _ownerAddress.text
      ..ownerNeighborhood = _ownerNeighborhood.text
      ..ownerCity = _ownerCity.text
      ..ownerState = _ownerState
      ..ownerSpouseName = _osName.text
      ..ownerSpouseCpf = _osCpf.text
      ..ownerSpouseRg = _osRg
      ..ownerSpouseEmail = _osEmail.text
      ..ownerSpousePhone = _osPhone.text
      ..ownerSpouseProfession = _osProfession.text;
  }

  // ── Salvar ──────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_saving) return;
    if (!_validate()) {
      _toast('Preencha os campos obrigatórios antes de continuar.',
          error: true);
      return;
    }
    if (widget.isEditing) {
      await _executeEditSave(false);
      return;
    }
    setState(() => _saving = true);
    final res =
        await PurchaseProposalsService.instance.create(_buildPayload());
    if (!mounted) return;
    if (!res.success || res.data == null) {
      setState(() => _saving = false);
      _toast(res.message ?? 'Erro ao salvar ficha de proposta', error: true);
      return;
    }
    final created = res.data!;
    if (created.id.isNotEmpty && _linkedUserIds.isNotEmpty) {
      await PurchaseProposalsService.instance
          .addUsers(created.id, List.of(_linkedUserIds));
    }
    if (!mounted) return;
    setState(() => _saving = false);
    _toast('Ficha de proposta criada com sucesso!');
    if (created.id.isNotEmpty) {
      await _openSignatures(
        id: created.id,
        number: created.proposalNumber.isNotEmpty
            ? created.proposalNumber
            : created.id,
        etapa: 1,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  /// `executeEditSave` do web.
  Future<void> _executeEditSave(bool confirmado) async {
    final id = widget.proposalId!;
    final decision = _reinicioDecision();
    if (decision.needsReinicio && !confirmado) {
      final ok = await _confirmReinicio(
        decision.etapas,
        _loadedStatus == ProposalStatus.finalized,
      );
      if (ok == true) await _executeEditSave(true);
      return;
    }
    setState(() => _saving = true);
    final svc = PurchaseProposalsService.instance;
    final res = await svc.update(id, _buildPayload());
    if (!mounted) return;
    if (!res.success) {
      setState(() => _saving = false);
      _toast(res.message ?? 'Erro ao atualizar ficha de proposta',
          error: true);
      return;
    }
    if (_linkedUserIds.isNotEmpty) {
      await svc.addUsers(id, List.of(_linkedUserIds));
    }
    if (!mounted) return;
    _toast('Ficha de proposta atualizada com sucesso!');
    var etapaModal = _etapa;
    if (decision.needsReinicio && confirmado) {
      final rein = await svc.reiniciarFluxoAssinaturas(id);
      if (!mounted) return;
      if (rein.success) {
        etapaModal = 1;
        _toast('Fluxo de assinaturas reiniciado. Envie novamente para as '
            'etapas 1, 2 e 3.');
      } else {
        _toast(
          rein.message ??
              'Erro ao reiniciar assinaturas. Tente pela listagem.',
          error: true,
        );
      }
    }
    setState(() => _saving = false);
    await _openSignatures(
      id: id,
      number: _proposalNumber.isNotEmpty ? _proposalNumber : id,
      etapa: etapaModal,
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<bool?> _confirmReinicio(List<String> etapas, bool finalizada) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ThemeHelpers.cardBackgroundColor(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Assinaturas serão invalidadas',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                finalizada
                    ? 'Há alterações em uma proposta finalizada. Ao continuar, '
                        'todas as assinaturas digitais (e anexos aprovados) '
                        'deixam de valer para esta ficha e será necessário '
                        'enviar novamente para as etapas 1, 2 e 3.'
                    : 'Você alterou dados de etapa(s) em que o fluxo já estava '
                        'concluído (assinatura digital ou anexo aprovado):',
                style: const TextStyle(height: 1.45),
              ),
              if (!finalizada && etapas.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final e in etapas)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 7, right: 8),
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: muted,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(e,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, height: 1.4)),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              Text(
                'Deseja salvar e reiniciar o fluxo de assinaturas?',
                style: TextStyle(color: muted, height: 1.4),
              ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(foregroundColor: muted),
            child: const Text('Cancelar',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: _brand,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Salvar e reiniciar assinaturas',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  List<ProposalSignerInput> _defaultSigners(int etapa) {
    ProposalSignerInput? signer(String name, String email, String phone) {
      if (name.trim().isEmpty || email.trim().isEmpty) return null;
      return ProposalSignerInput(
        email: email.trim(),
        name: name.trim(),
        phone: phone.trim().isEmpty ? null : phone,
      );
    }

    final s = etapa == 1
        ? signer(_buyerName.text, _buyerEmail.text, _buyerPhone.text)
        : etapa == 2
            ? signer(_ownerName.text, _ownerEmail.text, _ownerPhone.text)
            : null;
    return [?s];
  }

  Future<void> _openSignatures({
    required String id,
    required String number,
    required int etapa,
  }) {
    return showProposalSignaturesSheet(
      context,
      proposalId: id,
      proposalNumber: number,
      etapa: etapa,
      defaultSigners: _defaultSigners(etapa),
    );
  }

  /// Web: botão "Assinaturas (Comprador/Proprietário)" nas etapas já
  /// liberadas (1 e 2) da proposta em edição.
  bool get _canOpenSignatures =>
      widget.isEditing && _etapa <= _maxLiberada && _etapa < 3;

  Future<void> _openSignaturesFromHeader() async {
    await _openSignatures(
      id: widget.proposalId!,
      number: _proposalNumber.isNotEmpty ? _proposalNumber : widget.proposalId!,
      etapa: _etapa,
    );
    if (!mounted) return;
    final hist = await PurchaseProposalsService.instance
        .getHistorico(widget.proposalId!);
    if (!mounted || !hist.success || hist.data == null) return;
    setState(() => _maxLiberada = hist.data!.maxEtapaLiberadaParaEnvio ?? 1);
  }

  // ── CEP / busca de imóvel ───────────────────────────────────────────────

  Future<void> _buscarCep(
    String cep, {
    required void Function(bool) setLoading,
    required void Function(CepAddress) apply,
  }) async {
    final clean = ProposalRules.digits(cep);
    if (clean.length != 8) return;
    setState(() => setLoading(true));
    final addr = await CepService.instance.searchCep(clean);
    if (!mounted) return;
    setState(() => setLoading(false));
    if (addr == null) {
      _toast('CEP não encontrado.', error: true);
      return;
    }
    setState(() => apply(addr));
    _toast('Endereço preenchido pelo CEP.');
  }

  void _cepProponente() => _buscarCep(
        _buyerZip.text,
        setLoading: (v) => _cepBuyer = v,
        apply: (a) {
          _buyerAddress.text = a.street ?? '';
          _buyerNeighborhood.text = a.neighborhood ?? '';
          _buyerCity.text = a.city ?? '';
          _buyerState = (a.state ?? '').toUpperCase();
        },
      );

  void _cepImovel() => _buscarCep(
        _propZip.text,
        setLoading: (v) => _cepProp = v,
        apply: (a) {
          _propAddress.text = a.street ?? '';
          _propNeighborhood.text = a.neighborhood ?? '';
          _propCity.text = a.city ?? '';
          _propState = (a.state ?? '').toUpperCase();
          for (final k in const [
            'propertyAddress',
            'propertyNeighborhood',
            'propertyCity',
            'propertyState',
          ]) {
            _errors.remove(k);
          }
        },
      );

  void _cepProprietario() => _buscarCep(
        _ownerZip.text,
        setLoading: (v) => _cepOwner = v,
        apply: (a) {
          _ownerAddress.text = a.street ?? '';
          _ownerNeighborhood.text = a.neighborhood ?? '';
          _ownerCity.text = a.city ?? '';
          _ownerState = (a.state ?? '').toUpperCase();
        },
      );

  Future<void> _buscarImovelPorCodigo() async {
    final code = _propCode.text.trim();
    if (code.isEmpty) {
      _toast('Digite o código do imóvel para buscar.', error: true);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _searchingProperty = true);
    final res =
        await PurchaseProposalsService.instance.searchPropertiesByCode(code);
    if (!mounted) return;
    setState(() => _searchingProperty = false);
    if (!res.success) {
      _toast('Erro ao buscar imóveis. Tente novamente.', error: true);
      return;
    }
    final hits = res.data ?? const [];
    if (hits.isEmpty) {
      _toast('Nenhum imóvel encontrado com esse código.');
      return;
    }
    final picked = await showModalBottomSheet<ProposalPropertyHit>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PropertyHitsSheet(hits: hits, accent: _brand),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _propCode.text = picked.code;
      _propZip.text = ProposalRules.maskCep(picked.zipCode);
      _propAddress.text = picked.address;
      _propNeighborhood.text = picked.neighborhood;
      _propCity.text = picked.city;
      _propState = picked.state;
      for (final k in const [
        'propertyAddress',
        'propertyNeighborhood',
        'propertyCity',
        'propertyState',
      ]) {
        _errors.remove(k);
      }
    });
    _toast('Imóvel preenchido com os dados da propriedade.');
  }

  // ── Datas ───────────────────────────────────────────────────────────────

  Future<void> _pickDate(
    DateTime? current,
    ValueChanged<DateTime> onPick, {
    bool pastOnly = false,
  }) async {
    final now = DateTime.now();
    final last = pastOnly ? now : DateTime(now.year + 10);
    final initial = current ?? (pastOnly ? DateTime(now.year - 30) : now);
    final d = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(last) ? last : initial,
      firstDate: DateTime(1900),
      lastDate: last,
      helpText: 'Selecione a data',
      cancelText: 'Cancelar',
      confirmText: 'Confirmar',
    );
    if (d != null) onPick(d);
  }

  // ── Navegação ───────────────────────────────────────────────────────────

  void _scrollTop() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _goEtapa(int n) {
    if (n > _maxLiberada) {
      _toast('Liberada após assinatura da etapa anterior.');
      return;
    }
    setState(() => _etapa = n);
    _scrollTop();
  }

  void _goTab(int i) {
    setState(() => _tab = i);
    _scrollTop();
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            error ? AppColors.status.error : AppColors.status.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _clearError(String key) {
    if (_errors.containsKey(key)) setState(() => _errors.remove(key));
  }

  // ── Tema dos campos (mesma gramática da ficha de venda) ─────────────────

  ThemeData _formTheme(BuildContext context) {
    final base = Theme.of(context);
    final isDark = base.brightness == Brightness.dark;
    final fill = isDark
        ? Colors.white.withValues(alpha: 0.045)
        : Colors.black.withValues(alpha: 0.03);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final err = AppColors.status.error;
    OutlineInputBorder b(Color c, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: w == 0 ? BorderSide.none : BorderSide(color: c, width: w),
        );
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(primary: _brand, error: err),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: _brand,
        selectionColor: _brand.withValues(alpha: 0.18),
        selectionHandleColor: _brand,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fill,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        labelStyle: TextStyle(
            color: muted, fontWeight: FontWeight.w600, fontSize: 13.5),
        floatingLabelStyle: TextStyle(
            color: _brand, fontWeight: FontWeight.w700, fontSize: 13.5),
        hintStyle: TextStyle(
            color: muted.withValues(alpha: 0.7), fontWeight: FontWeight.w500),
        helperStyle: TextStyle(color: muted, fontSize: 11.5, height: 1.3),
        errorStyle: TextStyle(
            color: err, fontSize: 11.5, fontWeight: FontWeight.w600),
        errorMaxLines: 2,
        helperMaxLines: 3,
        prefixStyle: TextStyle(
            color: ThemeHelpers.textColor(context),
            fontWeight: FontWeight.w700),
        suffixStyle: TextStyle(
            color: muted, fontWeight: FontWeight.w600, fontSize: 12.5),
        border: b(Colors.transparent, 0),
        enabledBorder: b(Colors.transparent, 0),
        focusedBorder: b(_brand, 1.6),
        errorBorder: b(err, 1.2),
        focusedErrorBorder: b(err, 1.6),
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final title =
        widget.isEditing ? 'Editar ficha de proposta' : 'Nova ficha de proposta';
    return Scaffold(
      backgroundColor: ThemeHelpers.backgroundColor(context),
      appBar: AppBar(
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        elevation: 0,
        scrolledUnderElevation: 0.6,
        backgroundColor: ThemeHelpers.appBarBackgroundColor(context),
        actions: [
          if (!_loading && _canOpenSignatures)
            IconButton(
              tooltip: _etapa == 1
                  ? 'Assinaturas (Comprador)'
                  : 'Assinaturas (Proprietário)',
              onPressed: _saving ? null : _openSignaturesFromHeader,
              icon: const Icon(LucideIcons.signature, size: 20),
            ),
        ],
      ),
      body: _loading ? const _FormSkeleton() : _buildBody(),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        _StageRail(
          current: _etapa,
          maxLiberada: _maxLiberada,
          finalizada: (n) =>
              (n == 1 && _maxLiberada >= 2) ||
              (n == 2 && _maxLiberada >= 3) ||
              (n == 3 && _loadedStatus == ProposalStatus.finalized),
          accent: _brand,
          onTap: _goEtapa,
        ),
        if (_etapa == 1)
          _TabStrip(
            current: _tab,
            accent: _brand,
            hasError: (i) {
              final keys = switch (i) {
                0 => _kTab0Keys,
                1 => _kTab1Keys,
                2 => _kTab2Keys,
                _ => _kTab3Keys,
              };
              return _errors.keys.any(keys.contains);
            },
            onTap: _goTab,
          ),
        Expanded(
          child: Theme(
            data: _formTheme(context),
            child: ListView(
              controller: _scroll,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: [
                if (widget.isEditing && _avisoFinalizada) const _FinalizadaNote(),
                ..._content(),
              ],
            ),
          ),
        ),
        _navBar(),
      ],
    );
  }

  List<Widget> _content() {
    if (_etapa == 2) return _etapa2();
    if (_etapa == 3) return _etapa3();
    switch (_tab) {
      case 1:
        return _tabProponente();
      case 2:
        return _tabConjuge();
      case 3:
        return _tabImovel();
      default:
        return _tabProposta();
    }
  }

  String get _submitLabel {
    if (!widget.isEditing) {
      return _etapa == 1 ? 'Criar e enviar para assinatura' : 'Salvar';
    }
    switch (_etapa) {
      case 3:
        return 'Finalizar proposta';
      case 2:
        return 'Finalizar etapa';
      default:
        return 'Salvar alterações';
    }
  }

  Widget _navBar() {
    final showNext = _etapa == 1 && _tab < _kTabsEtapa1.length - 1;
    final VoidCallback? back = _etapa == 1
        ? (_tab > 0 ? () => _goTab(_tab - 1) : null)
        : () => _goEtapa(_etapa - 1);
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
          if (back != null) ...[
            OutlinedButton.icon(
              onPressed: _saving ? null : back,
              style: OutlinedButton.styleFrom(
                // Neutro — voltar não é ação de marca.
                foregroundColor: ThemeHelpers.textSecondaryColor(context),
                side: BorderSide(color: ThemeHelpers.borderColor(context)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(LucideIcons.arrowLeft, size: 16),
              label: const Text('Anterior',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: FilledButton(
              onPressed:
                  _saving ? null : (showNext ? () => _goTab(_tab + 1) : _submit),
              style: FilledButton.styleFrom(
                backgroundColor: _brand,
                disabledBackgroundColor: _brand.withValues(alpha: 0.55),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_saving)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    else
                      Icon(
                        showNext ? LucideIcons.arrowRight : LucideIcons.check,
                        size: 18,
                        color: Colors.white,
                      ),
                    const SizedBox(width: 8),
                    Text(
                      _saving
                          ? 'Salvando…'
                          : showNext
                              ? 'Próximo'
                              : _submitLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Builders de campo ───────────────────────────────────────────────────

  Widget _text(
    String key,
    String label,
    TextEditingController c, {
    bool required = false,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    int maxLines = 1,
    int? maxLength,
    String? prefix,
    String? suffixText,
    Widget? suffix,
    String? hint,
    String? helper,
    TextCapitalization caps = TextCapitalization.none,
    ValueChanged<String>? onChanged,
  }) {
    return _Field(
      label: required ? '$label *' : label,
      controller: c,
      error: _errors[key],
      keyboard: keyboard,
      formatters: formatters,
      maxLines: maxLines,
      maxLength: maxLength,
      prefix: prefix,
      suffixText: suffixText,
      suffix: suffix,
      hint: hint,
      helper: helper,
      caps: caps,
      onChanged: (v) {
        _clearError(key);
        onChanged?.call(v);
      },
    );
  }

  Widget _money(String key, String label, TextEditingController c,
          {bool required = false}) =>
      _text(key, label, c,
          required: required,
          keyboard: TextInputType.number,
          formatters: [CurrencyInputFormatter()],
          prefix: 'R\$ ');

  Widget _days(String key, String label, TextEditingController c) =>
      _text(key, label, c,
          keyboard: TextInputType.number,
          formatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(3),
          ],
          suffixText: 'dias úteis');

  Widget _select(
    String key,
    String label,
    String value,
    List<(String, String)> options,
    ValueChanged<String> onChanged, {
    bool required = false,
    String? hint,
    String? helper,
    String Function(String)? unknownLabel,
  }) {
    return _Select(
      label: required ? '$label *' : label,
      value: value,
      options: options,
      error: _errors[key],
      hint: hint,
      helper: helper,
      unknownLabel: unknownLabel,
      onChanged: (v) {
        _errors.remove(key);
        setState(() => onChanged(v));
      },
    );
  }

  Widget _uf(String key, String value, ValueChanged<String> onChanged,
          {bool required = false}) =>
      _select(key, 'UF', value, [for (final u in kProposalUfs) (u, u)],
          onChanged,
          required: required);

  Widget _cepField(
    String key,
    TextEditingController c, {
    required bool loading,
    required VoidCallback onSearch,
  }) {
    return _text(
      key,
      'CEP',
      c,
      keyboard: TextInputType.number,
      formatters: [ProposalMaskFormatter.cep],
      suffix: _InlineAction(
        icon: LucideIcons.search,
        loading: loading,
        tooltip: 'Buscar CEP',
        enabled: ProposalRules.digits(c.text).length == 8,
        onTap: onSearch,
      ),
      onChanged: (v) {
        setState(() {});
        // `useCepAutofill`: dispara sozinho ao completar 8 dígitos, sem
        // refazer a busca do mesmo CEP (a lupa força).
        final d = ProposalRules.digits(v);
        if (d.length == 8 && _lastAutoCep[key] != d) {
          _lastAutoCep[key] = d;
          onSearch();
        }
      },
    );
  }

  Widget _birth(String key, DateTime? value, ValueChanged<DateTime?> set) {
    return _DateField(
      label: 'Nascimento',
      value: value,
      error: _errors[key],
      onTap: () => _pickDate(value, (d) {
        _errors.remove(key);
        setState(() => set(d));
      }, pastOnly: true),
      onClear: value == null
          ? null
          : () {
              _errors.remove(key);
              setState(() => set(null));
            },
    );
  }

  // ── Etapa 1 · aba 0: Dados da proposta ──────────────────────────────────

  List<Widget> _tabProposta() {
    final teamOptions = [for (final t in _teams) (t.id, t.name)];
    final unitOptions = [for (final u in _units) (u.name, u.name)];
    return [
      const _Band('DADOS DA PROPOSTA', LucideIcons.handshake),
      _Row2(
        left: _DateField(
          label: 'Data da proposta *',
          value: _proposalDate,
          error: _errors['proposalDate'],
          onTap: () => _pickDate(_proposalDate, (d) {
            _errors.remove('proposalDate');
            setState(() => _proposalDate = d);
          }),
        ),
        right: _days('validityDays', 'Validade', _validityDays),
      ),
      _Row2(
        left: _money('proposedPrice', 'Preço proposto', _proposedPrice,
            required: true),
        right: _text(
          'commissionPercentage',
          'Comissão',
          _commission,
          required: true,
          keyboard: const TextInputType.numberWithOptions(decimal: true),
          formatters: [ProposalPercentFormatter()],
          suffixText: '%',
        ),
      ),
      _Row2(
        left: _money('downPayment', 'Sinal / arras', _downPayment),
        right: _days('downPaymentDays', 'Prazo do sinal', _downPaymentDays),
      ),
      _Row2(
        left: _days('deliveryDays', 'Prazo de entrega', _deliveryDays),
        right: _money('monthlyPenalty', 'Multa mensal', _monthlyPenalty),
      ),
      _select(
        'teamId',
        'Equipe',
        _teamId,
        teamOptions,
        (v) => _teamId = v,
        required: true,
        hint: _loadingTeams ? 'Carregando equipes…' : 'Selecione',
        helper: 'Equipe responsável por esta proposta no dashboard e nos '
            'rankings.',
        unknownLabel: (_) => 'Equipe indisponível',
      ),
      _Row2(
        left: _select('saleUnit', 'Unidade de venda', _saleUnit, unitOptions,
            (v) => _saleUnit = v,
            hint: 'Selecione', unknownLabel: (v) => '$v (indisponível)'),
        right: _select('captureUnit', 'Unidade de captação', _captureUnit,
            unitOptions, (v) => _captureUnit = v,
            hint: 'Selecione', unknownLabel: (v) => '$v (indisponível)'),
      ),
      _text(
        'paymentConditions',
        'Condições de pagamento',
        _paymentConditions,
        required: true,
        maxLines: 4,
        maxLength: 2000,
        caps: TextCapitalization.sentences,
        hint: 'Ex.: entrada de 30% e financiamento do restante em 120 meses',
        helper: 'Máximo 2000 caracteres. Inclua aqui todas as informações '
            'relevantes da proposta.',
      ),
    ];
  }

  // ── Etapa 1 · aba 1: Proponente ─────────────────────────────────────────

  List<Widget> _tabProponente() => [
        const _Band('PROPONENTE', LucideIcons.user),
        _text('proponentName', 'Nome completo', _buyerName,
            required: true, caps: TextCapitalization.words),
        _Row2(
          leftFlex: 3,
          rightFlex: 2,
          left: _text('proponentCpf', 'CPF / CNPJ', _buyerCpf,
              required: true,
              keyboard: TextInputType.number,
              formatters: [ProposalMaskFormatter.cpfOuCnpj]),
          right: _text('proponentRg', 'RG', _buyerRg,
              keyboard: TextInputType.number,
              formatters: [ProposalMaskFormatter.rg]),
        ),
        _Row2(
          left: _birth('proponentBirthDate', _buyerBirth,
              (d) => _buyerBirth = d),
          right: _text('proponentNationality', 'Nacionalidade',
              _buyerNationality,
              hint: 'Brasileiro(a)', caps: TextCapitalization.words),
        ),
        _Row2(
          left: _select('proponentMaritalStatus', 'Estado civil',
              _buyerMarital, kProposalMaritalStatus, (v) => _buyerMarital = v,
              hint: 'Selecione'),
          right: _select('proponentMarriageRegime', 'Regime de casamento',
              _buyerRegime, kProposalMarriageRegime, (v) => _buyerRegime = v,
              hint: 'Selecione'),
        ),
        _text('proponentProfession', 'Profissão', _buyerProfession,
            caps: TextCapitalization.sentences),
        _Row2(
          left: _text('proponentEmail', 'E-mail', _buyerEmail,
              keyboard: TextInputType.emailAddress,
              formatters: [ProposalEmailFormatter()]),
          right: _text('proponentPhone', 'Telefone', _buyerPhone,
              required: true,
              keyboard: TextInputType.phone,
              formatters: [ProposalMaskFormatter.phone]),
        ),
        const _Band('ENDEREÇO DO PROPONENTE', LucideIcons.mapPin),
        _Row2(
          left: _cepField('proponentZipCode', _buyerZip,
              loading: _cepBuyer, onSearch: _cepProponente),
          right: _text('proponentNeighborhood', 'Bairro', _buyerNeighborhood,
              caps: TextCapitalization.words),
        ),
        _text('proponentAddress', 'Endereço', _buyerAddress,
            hint: 'Rua, Av…', caps: TextCapitalization.words),
        _Row2(
          leftFlex: 3,
          rightFlex: 2,
          left: _text('proponentCity', 'Cidade', _buyerCity,
              caps: TextCapitalization.words),
          right: _uf('proponentState', _buyerState, (v) => _buyerState = v),
        ),
        const _Caption('O endereço é preenchido automaticamente ao digitar o '
            'CEP.'),
      ];

  // ── Etapa 1 · aba 2: Cônjuge do proponente ──────────────────────────────

  List<Widget> _tabConjuge() => [
        const _Band('CÔNJUGE / COMPANHEIRO(A) · OPCIONAL', LucideIcons.heart),
        _text('proponentSpouseName', 'Nome completo', _bsName,
            caps: TextCapitalization.words),
        _Row2(
          leftFlex: 3,
          rightFlex: 2,
          left: _text('proponentSpouseCpf', 'CPF', _bsCpf,
              keyboard: TextInputType.number,
              formatters: [ProposalMaskFormatter.cpf]),
          right: _text('proponentSpouseRg', 'RG', _bsRg,
              keyboard: TextInputType.number,
              formatters: [ProposalMaskFormatter.rg]),
        ),
        _Row2(
          left: _text('proponentSpouseProfession', 'Profissão', _bsProfession,
              caps: TextCapitalization.sentences),
          right: _text('proponentSpousePhone', 'Telefone', _bsPhone,
              keyboard: TextInputType.phone,
              formatters: [ProposalMaskFormatter.phone]),
        ),
        _text('proponentSpouseEmail', 'E-mail', _bsEmail,
            keyboard: TextInputType.emailAddress,
            formatters: [ProposalEmailFormatter()]),
      ];

  // ── Etapa 1 · aba 3: Imóvel ─────────────────────────────────────────────

  List<Widget> _tabImovel() => [
        const _Band('IMÓVEL', LucideIcons.house),
        _text(
          'propertyCode',
          'Código do imóvel',
          _propCode,
          hint: 'Código interno',
          caps: TextCapitalization.characters,
          helper: 'Digite o código e toque na lupa para preencher os dados do '
              'imóvel.',
          suffix: _InlineAction(
            icon: LucideIcons.search,
            loading: _searchingProperty,
            tooltip: 'Buscar imóvel',
            enabled: _propCode.text.trim().isNotEmpty,
            onTap: _buscarImovelPorCodigo,
          ),
          onChanged: (_) => setState(() {}),
        ),
        _Row2(
          left: _text('propertyRegistry', 'Cartório de Registro',
              _propRegistry,
              maxLength: 255, caps: TextCapitalization.words),
          right: _text('propertyNotary', 'Notário / Tabelião', _propNotary,
              maxLength: 255, caps: TextCapitalization.words),
        ),
        _Row2(
          left: _cepField('propertyZipCode', _propZip,
              loading: _cepProp, onSearch: _cepImovel),
          right: _text('propertyNeighborhood', 'Bairro', _propNeighborhood,
              required: true, caps: TextCapitalization.words),
        ),
        _text('propertyAddress', 'Endereço', _propAddress,
            required: true, hint: 'Rua, Av…', caps: TextCapitalization.words),
        _Row2(
          leftFlex: 3,
          rightFlex: 2,
          left: _text('propertyCity', 'Cidade', _propCity,
              required: true, caps: TextCapitalization.words),
          right: _uf('propertyState', _propState, (v) => _propState = v,
              required: true),
        ),
        const _Caption('O endereço é preenchido automaticamente ao digitar o '
            'CEP.'),
      ];

  // ── Etapa 2: Proprietário ───────────────────────────────────────────────

  List<Widget> _etapa2() => [
        const _Band('PROPRIETÁRIO', LucideIcons.userRound),
        _text('ownerName', 'Nome completo', _ownerName,
            required: true, caps: TextCapitalization.words),
        _Row2(
          leftFlex: 3,
          rightFlex: 2,
          left: _text('ownerCpf', 'CPF / CNPJ', _ownerCpf,
              required: true,
              keyboard: TextInputType.number,
              formatters: [ProposalMaskFormatter.cpfOuCnpj]),
          right: _text('ownerRg', 'RG', _ownerRg,
              keyboard: TextInputType.number,
              formatters: [ProposalMaskFormatter.rg]),
        ),
        _Row2(
          left: _birth('ownerBirthDate', _ownerBirth, (d) => _ownerBirth = d),
          right: _text('ownerNationality', 'Nacionalidade', _ownerNationality,
              hint: 'Brasileiro(a)', caps: TextCapitalization.words),
        ),
        _Row2(
          left: _select('ownerMaritalStatus', 'Estado civil', _ownerMarital,
              kProposalMaritalStatus, (v) => _ownerMarital = v,
              hint: 'Selecione'),
          right: _select('ownerMarriageRegime', 'Regime de casamento',
              _ownerRegime, kProposalMarriageRegime, (v) => _ownerRegime = v,
              hint: 'Selecione'),
        ),
        _text('ownerProfession', 'Profissão', _ownerProfession,
            caps: TextCapitalization.sentences),
        _Row2(
          left: _text('ownerEmail', 'E-mail', _ownerEmail,
              keyboard: TextInputType.emailAddress),
          right: _text('ownerPhone', 'Telefone', _ownerPhone,
              required: true,
              keyboard: TextInputType.phone,
              formatters: [ProposalMaskFormatter.phone]),
        ),
        const _Band('ENDEREÇO DO PROPRIETÁRIO', LucideIcons.mapPin),
        _Row2(
          left: _cepField('ownerZipCode', _ownerZip,
              loading: _cepOwner, onSearch: _cepProprietario),
          right: _text('ownerNeighborhood', 'Bairro', _ownerNeighborhood,
              caps: TextCapitalization.words),
        ),
        _text('ownerAddress', 'Endereço', _ownerAddress,
            hint: 'Rua, Av…', caps: TextCapitalization.words),
        _Row2(
          leftFlex: 3,
          rightFlex: 2,
          left: _text('ownerCity', 'Cidade', _ownerCity,
              caps: TextCapitalization.words),
          right: _uf('ownerState', _ownerState, (v) => _ownerState = v),
        ),
        const _Band('CÔNJUGE DO PROPRIETÁRIO · OPCIONAL', LucideIcons.heart),
        _text('ownerSpouseName', 'Nome', _osName,
            caps: TextCapitalization.words),
        _Row2(
          left: _text('ownerSpouseCpf', 'CPF', _osCpf,
              keyboard: TextInputType.number,
              formatters: [ProposalMaskFormatter.cpf]),
          right: _text('ownerSpouseProfession', 'Profissão', _osProfession,
              caps: TextCapitalization.sentences),
        ),
        _Row2(
          left: _text('ownerSpouseEmail', 'E-mail', _osEmail,
              keyboard: TextInputType.emailAddress),
          right: _text('ownerSpousePhone', 'Telefone', _osPhone,
              keyboard: TextInputType.phone,
              formatters: [ProposalMaskFormatter.phone]),
        ),
      ];

  // ── Etapa 3: usuários que poderão ver a proposta ────────────────────────

  List<Widget> _etapa3() {
    final byId = {for (final m in _members) m.id: m};
    final muted = ThemeHelpers.textSecondaryColor(context);
    final full = _linkedUserIds.length >= _kMaxLinkedUsers;
    return [
      const _Band('USUÁRIOS QUE PODERÃO VER ESTA PROPOSTA',
          LucideIcons.userPlus),
      Text(
        'Selecione os usuários que terão acesso a esta proposta. Você '
        '(criador) já está vinculado automaticamente.',
        style: TextStyle(color: muted, height: 1.4, fontSize: 13.5),
      ),
      const SizedBox(height: 14),
      if (_loadingMembers && _linkedUserIds.isNotEmpty)
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SkeletonBox(width: 120, height: 34, borderRadius: 999),
            SkeletonBox(width: 96, height: 34, borderRadius: 999),
          ],
        )
      else if (_linkedUserIds.isNotEmpty)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final id in _linkedUserIds)
              _UserChip(
                name: byId[id]?.name ?? 'Usuário',
                accent: _brand,
                onRemove: () => setState(() => _linkedUserIds.remove(id)),
              ),
          ],
        ),
      const SizedBox(height: 12),
      Row(
        children: [
          Flexible(
            child: OutlinedButton.icon(
              onPressed: full || _loadingMembers ? null : _pickLinkedUser,
              style: OutlinedButton.styleFrom(
                foregroundColor: _brand,
                side: BorderSide(color: _brand.withValues(alpha: 0.45)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('Adicionar usuário',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${_linkedUserIds.length}/$_kMaxLinkedUsers',
            style: TextStyle(
              color: muted,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    ];
  }

  Future<void> _pickLinkedUser() async {
    final exclude = {..._linkedUserIds, ?_currentUserId};
    final available =
        _members.where((m) => !exclude.contains(m.id)).toList();
    final picked = await showModalBottomSheet<ProposalMember>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MemberPickerSheet(members: available, accent: _brand),
    );
    if (picked == null || !mounted) return;
    if (_linkedUserIds.length >= _kMaxLinkedUsers) return;
    setState(() => _linkedUserIds.add(picked.id));
  }
}

// ─── Trilho de etapas (flush) ───────────────────────────────────────────────

class _StageRail extends StatelessWidget {
  const _StageRail({
    required this.current,
    required this.maxLiberada,
    required this.finalizada,
    required this.accent,
    required this.onTap,
  });

  final int current;
  final int maxLiberada;
  final bool Function(int) finalizada;
  final Color accent;
  final ValueChanged<int> onTap;

  static const _titles = ['Comprador', 'Proprietário', 'Corretor'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Row(
        children: [
          for (var n = 1; n <= 3; n++)
            Expanded(
              child: _StageTab(
                number: n,
                title: _titles[n - 1],
                selected: current == n,
                locked: n > maxLiberada,
                done: finalizada(n),
                accent: accent,
                onTap: () => onTap(n),
              ),
            ),
        ],
      ),
    );
  }
}

class _StageTab extends StatelessWidget {
  const _StageTab({
    required this.number,
    required this.title,
    required this.selected,
    required this.locked,
    required this.done,
    required this.accent,
    required this.onTap,
  });

  final int number;
  final String title;
  final bool selected;
  final bool locked;
  final bool done;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final text = ThemeHelpers.textColor(context);
    final IconData? mark = locked
        ? LucideIcons.lock
        : done
            ? LucideIcons.circleCheck
            : null;
    final markColor = done && !locked ? AppColors.status.success : muted;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Etapa $number, $title${locked ? ', bloqueada' : ''}',
      child: InkWell(
        onTap: onTap,
        child: Opacity(
          opacity: locked ? 0.55 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        'ETAPA $number',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: selected ? accent : muted,
                        ),
                      ),
                    ),
                    if (mark != null) ...[
                      const SizedBox(width: 4),
                      Icon(mark, size: 11, color: markColor),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                    color: selected ? text : muted,
                  ),
                ),
                const SizedBox(height: 9),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  height: 3,
                  decoration: BoxDecoration(
                    color: selected ? accent : Colors.transparent,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(3)),
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

// ─── Abas da etapa 1 ────────────────────────────────────────────────────────

class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.current,
    required this.accent,
    required this.hasError,
    required this.onTap,
  });

  final int current;
  final Color accent;
  final bool Function(int) hasError;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _kTabsEtapa1.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Material(
                  color: current == i
                      ? accent.withValues(alpha: 0.10)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => onTap(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              _kTabsEtapa1[i].$1,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: current == i
                                    ? FontWeight.w900
                                    : FontWeight.w700,
                                color: current == i ? accent : muted,
                              ),
                            ),
                          ),
                          if (hasError(i)) ...[
                            const SizedBox(width: 4),
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: AppColors.status.error,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Aviso de proposta finalizada ───────────────────────────────────────────

class _FinalizadaNote extends StatelessWidget {
  const _FinalizadaNote();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark
        ? AppColors.status.warningDarkMode
        : AppColors.status.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: c, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.triangleAlert, size: 16, color: c),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Esta proposta está finalizada. Se você alterar dados e salvar, '
              'será pedida confirmação e o fluxo de assinaturas será '
              'reiniciado (etapas 1, 2 e 3).',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: ThemeHelpers.textColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Peças do formulário ────────────────────────────────────────────────────

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
              maxLines: 2,
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
              color:
                  ThemeHelpers.borderLightColor(context).withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.info,
              size: 13, color: ThemeHelpers.textSecondaryColor(context)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
          ),
        ],
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

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.error,
    this.keyboard,
    this.formatters,
    this.maxLines = 1,
    this.maxLength,
    this.prefix,
    this.suffixText,
    this.suffix,
    this.hint,
    this.helper,
    this.caps = TextCapitalization.none,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String? error;
  final TextInputType? keyboard;
  final List<TextInputFormatter>? formatters;
  final int maxLines;
  final int? maxLength;
  final String? prefix;
  final String? suffixText;
  final Widget? suffix;
  final String? hint;
  final String? helper;
  final TextCapitalization caps;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    // Visual (filled, sem borda, foco na marca) herdado do _formTheme.
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: maxLines > 1 ? TextInputType.multiline : keyboard,
        inputFormatters: formatters,
        maxLines: maxLines,
        minLines: maxLines > 1 ? 3 : null,
        maxLength: maxLength,
        maxLengthEnforcement: MaxLengthEnforcement.enforced,
        textCapitalization: caps,
        onChanged: onChanged,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: ThemeHelpers.textColor(context),
            ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helper,
          errorText: error,
          prefixText: prefix,
          suffixText: suffix == null ? suffixText : null,
          suffixIcon: suffix,
          // Contador só no campo longo (condições de pagamento).
          counterText: maxLines > 1 ? null : '',
        ),
      ),
    );
  }
}

class _Select extends StatelessWidget {
  const _Select({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.error,
    this.hint,
    this.helper,
    this.unknownLabel,
  });

  final String label;
  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;
  final String? error;
  final String? hint;
  final String? helper;
  final String Function(String)? unknownLabel;

  @override
  Widget build(BuildContext context) {
    final items = <(String, String)>[...options];
    // Valor salvo fora da lista (legado, unidade desativada, equipe sem
    // acesso): mantém e mostra, como o web — nunca descarta o dado.
    if (value.isNotEmpty && !items.any((o) => o.$1 == value)) {
      items.add((value, unknownLabel?.call(value) ?? value));
    }
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        // A key força reconstruir quando o valor muda por fora (CEP, busca
        // de imóvel, hidratação) — `initialValue` só vale na montagem.
        key: ValueKey('$label|$value|${items.length}'),
        initialValue: value.isEmpty ? null : value,
        isExpanded: true,
        icon: Icon(LucideIcons.chevronDown, size: 18, color: muted),
        borderRadius: BorderRadius.circular(14),
        dropdownColor: ThemeHelpers.cardBackgroundColor(context),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: ThemeHelpers.textColor(context),
            ),
        hint: hint == null
            ? null
            : Text(hint!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: muted.withValues(alpha: 0.8))),
        items: [
          for (final o in items)
            DropdownMenuItem(
              value: o.$1,
              child: Text(o.$2, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
        decoration: InputDecoration(
          labelText: label,
          errorText: error,
          helperText: helper,
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
    this.error,
    this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final String? error;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final v = value;
    final text = v == null
        ? 'Selecionar'
        : '${v.day.toString().padLeft(2, '0')}/'
            '${v.month.toString().padLeft(2, '0')}/${v.year}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: InputDecorator(
          isEmpty: false,
          decoration: InputDecoration(labelText: label, errorText: error),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: v != null ? ThemeHelpers.textColor(context) : muted,
                  ),
                ),
              ),
              if (onClear != null)
                InkWell(
                  onTap: onClear,
                  customBorder: const CircleBorder(),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(LucideIcons.x, size: 16, color: muted),
                  ),
                )
              else
                Icon(LucideIcons.calendar, size: 16, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ação dentro do campo (lupa do CEP / do código do imóvel).
class _InlineAction extends StatelessWidget {
  const _InlineAction({
    required this.icon,
    required this.loading,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool loading;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final muted = ThemeHelpers.textSecondaryColor(context);
    if (loading) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: accent),
        ),
      );
    }
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 18, color: enabled ? accent : muted),
    );
  }
}

class _UserChip extends StatelessWidget {
  const _UserChip({
    required this.name,
    required this.accent,
    required this.onRemove,
  });

  final String name;
  final Color accent;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: accent.withValues(alpha: 0.16),
            child: Text(
              initial,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w900,
                fontSize: 11.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: ThemeHelpers.textColor(context),
              ),
            ),
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: 'Remover',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
            onPressed: onRemove,
            icon: Icon(LucideIcons.x,
                size: 15, color: ThemeHelpers.textSecondaryColor(context)),
          ),
        ],
      ),
    );
  }
}

// ─── Folhas (bottom sheets) ─────────────────────────────────────────────────

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: ThemeHelpers.borderColor(context),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
              IconButton(
                tooltip: 'Fechar',
                visualDensity: VisualDensity.compact,
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(LucideIcons.x,
                    size: 18, color: ThemeHelpers.textSecondaryColor(context)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Flexible(child: child),
        ],
      ),
    );
  }
}

class _MemberPickerSheet extends StatefulWidget {
  const _MemberPickerSheet({required this.members, required this.accent});
  final List<ProposalMember> members;
  final Color accent;

  @override
  State<_MemberPickerSheet> createState() => _MemberPickerSheetState();
}

class _MemberPickerSheetState extends State<_MemberPickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty
        ? widget.members
        : widget.members
            .where((m) =>
                m.name.toLowerCase().contains(q) ||
                (m.email ?? '').toLowerCase().contains(q))
            .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _SheetFrame(
        title: 'Adicionar usuário',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              autofocus: false,
              onChanged: (v) => setState(() => _q = v),
              cursorColor: widget.accent,
              decoration: InputDecoration(
                hintText: 'Buscar corretores…',
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                isDense: true,
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.045)
                    : Colors.black.withValues(alpha: 0.03),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        q.isEmpty
                            ? 'Nenhum usuário disponível'
                            : 'Nenhum usuário encontrado',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: muted),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final m = list[i];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor:
                                widget.accent.withValues(alpha: 0.14),
                            child: Text(
                              m.name.isNotEmpty
                                  ? m.name[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                color: widget.accent,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          title: Text(
                            m.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: (m.email ?? '').isEmpty
                              ? null
                              : Text(m.email!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                          onTap: () => Navigator.of(context).pop(m),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PropertyHitsSheet extends StatelessWidget {
  const _PropertyHitsSheet({required this.hits, required this.accent});
  final List<ProposalPropertyHit> hits;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return _SheetFrame(
      title: 'Imóveis encontrados',
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: hits.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          color: ThemeHelpers.borderLightColor(context),
        ),
        itemBuilder: (_, i) {
          final h = hits[i];
          final place = [
            if (h.address.isNotEmpty) h.address else 'Sem endereço',
            if (h.city.isNotEmpty) h.city,
          ].join(' · ');
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(LucideIcons.house, size: 18, color: accent),
            title: Text(
              h.code,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              place,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: muted),
            ),
            onTap: () => Navigator.of(context).pop(h),
          );
        },
      ),
    );
  }
}

// ─── Skeleton de carregamento ───────────────────────────────────────────────

class _FormSkeleton extends StatelessWidget {
  const _FormSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget row() => const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Expanded(child: SkeletonBox(height: 50, borderRadius: 14)),
              SizedBox(width: 12),
              Expanded(child: SkeletonBox(height: 50, borderRadius: 14)),
            ],
          ),
        );
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      children: [
        const Row(
          children: [
            Expanded(child: SkeletonBox(height: 40, borderRadius: 10)),
            SizedBox(width: 10),
            Expanded(child: SkeletonBox(height: 40, borderRadius: 10)),
            SizedBox(width: 10),
            Expanded(child: SkeletonBox(height: 40, borderRadius: 10)),
          ],
        ),
        const SizedBox(height: 22),
        const SkeletonBox(width: 140, height: 12, borderRadius: 6),
        const SizedBox(height: 14),
        const SkeletonBox(height: 50, borderRadius: 14),
        const SizedBox(height: 12),
        row(),
        row(),
        row(),
        row(),
        const SkeletonBox(height: 96, borderRadius: 14),
      ],
    );
  }
}
