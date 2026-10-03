import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/cep_service.dart';
import '../../../shared/services/purchase_proposals_service.dart';
import '../../../shared/services/secure_storage_service.dart';
import '../../../shared/utils/error_cause.dart';
import '../../../shared/utils/input_formatters.dart';
import '../../../shared/utils/jwt_utils.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/permission_route.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../../sale_forms/ficha_draft_store.dart';
import '../utils/proposal_draft.dart';
import '../utils/proposal_edit_rules.dart';
import '../utils/proposal_form_rules.dart';
import '../widgets/proposal_row_actions.dart' show showProposalPdfSheet;
import '../widgets/proposal_signatures_sheet.dart';

/// Cria ou edita uma ficha de proposta — paridade 1:1 com o
/// `CreatePurchaseProposalPage.tsx` (web = fonte da verdade):
///   - 3 etapas (Comprador, Proprietário, Corretor); 2 e 3 travadas até a
///     etapa anterior ser assinada (`maxEtapaLiberadaParaEnvio` do histórico);
///   - etapa 1 em 4 abas (Proposta, Proponente, Cônjuge, Imóvel);
///   - validação só da etapa atual, com as mesmas regras e mensagens;
///   - payload idêntico ao do web (ver `CreateProposalPayload`);
///   - etapa 3 = usuários que poderão ver a proposta (`addUsers`);
///   - editar etapa já assinada pede confirmação e reinicia o fluxo;
///   - proposta finalizada, cancelada ou excluída não abre o formulário (o
///     back recusa o `PATCH`): a tela diz o motivo e oferece histórico e PDF.
///
/// A guarda de acesso fica AQUI (não na rota): módulo `sale_forms` +
/// `proposal:update` para editar / `proposal:create` para criar — as mesmas
/// do `fichas.routes.tsx` do web. Assim lista, rota nomeada e deep link
/// passam todos por ela.
class CreateProposalPage extends StatelessWidget {
  const CreateProposalPage({super.key, this.proposalId, this.rascunho});

  final String? proposalId;

  /// Rascunho a retomar ("Retomar rascunho" da lista) — só na criação.
  final Map<String, dynamic>? rascunho;

  bool get isEditing => proposalId != null;

  @override
  Widget build(BuildContext context) {
    return PermissionRoute(
      module: 'sale_forms',
      permission: isEditing ? 'proposal:update' : 'proposal:create',
      child: _CreateProposalForm(proposalId: proposalId, rascunho: rascunho),
    );
  }
}

class _CreateProposalForm extends StatefulWidget {
  const _CreateProposalForm({this.proposalId, this.rascunho});

  final String? proposalId;
  final Map<String, dynamic>? rascunho;

  bool get isEditing => proposalId != null;

  @override
  State<_CreateProposalForm> createState() => _CreateProposalPageState();
}

/// Abas internas da etapa 1 (web `TABS_ETAPA_1`).
const List<(String, IconData)> _kTabsEtapa1 = [
  ('Dados da Proposta', LucideIcons.handshake),
  ('Proponente', LucideIcons.user),
  ('Cônjuge', LucideIcons.heart),
  ('Imóvel', LucideIcons.house),
];

/// Quem assina cada etapa (web: Comprador, Proprietário, Corretor).
const List<String> _kStageTitles = ['Comprador', 'Proprietário', 'Corretor'];

/// Coluna máxima do formulário em tela larga (tablet, landscape).
const double _kMaxContentWidth = 720;

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

class _CreateProposalPageState extends State<_CreateProposalForm>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();

  /// Trilho de etapas (rola junto): a altura dele diz onde as abas fixam.
  final _headerKey = GlobalKey();
  late final TabController _tabCtrl;

  int _etapa = 1;
  int _tabIndex = 0;
  int _maxLiberada = 1;
  bool _loading = false;
  bool _saving = false;
  String _proposalNumber = '';
  ProposalStatus? _loadedStatus;

  /// Edição recusada pelo back (finalizada/cancelada/excluída): a tela mostra
  /// o motivo no lugar do formulário.
  String? _bloqueio;
  bool _bloqueadaExcluida = false;
  int? _bloqueadaPdfEtapa;
  Map<String, String>? _loadedSnap1;
  Map<String, String>? _loadedSnap2;
  Map<int, bool> _concluidas = {1: false, 2: false, 3: false};

  final Map<String, String> _errors = {};

  // Catálogos (mesmas fontes do web)
  List<ProposalOption> _teams = const [];
  bool _loadingTeams = true;
  String? _teamsError;
  int _teamsStatus = 0;
  List<ProposalOption> _units = const [];
  List<ProposalMember> _members = const [];
  bool _loadingMembers = true;
  String? _membersError;
  int _membersStatus = 0;
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

  /// Gatilho do CEP automático por campo (`useCepAutofill` do web).
  final Map<String, ProposalCepGate> _cepGates = {};
  ProposalCepGate _cepGate(String key) =>
      _cepGates.putIfAbsent(key, ProposalCepGate.new);

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

  /// Aba atual da etapa 1. O TabBar acompanha toda troca (Próximo,
  /// Anterior e o salto para a aba com erro na validação).
  int get _tab => _tabIndex;
  set _tab(int v) {
    _tabIndex = v;
    if (_tabCtrl.index != v) _tabCtrl.animateTo(v);
  }

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _kTabsEtapa1.length, vsync: this);
    _loading = widget.isEditing;
    _loadCatalogs();
    if (widget.isEditing) _loadExisting();
    if (!widget.isEditing) {
      final r = widget.rascunho;
      if (r != null) {
        _aplicarRascunho(r);
        // Web: toast "Seu rascunho foi recuperado".
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _toast('Seu rascunho foi recuperado — você pode continuar de '
                'onde parou.', info: true);
          }
        });
      }
      // Autosave do rascunho (web: `useFormDraft`, `debounceMs: 700`, só na
      // criação). Confere a cada 700 ms e só grava quando algo mudou.
      _rascunhoTimer = Timer.periodic(
        const Duration(milliseconds: 700),
        (_) => _salvarRascunho(),
      );
    }
  }

  // ── Rascunho local ("Retomar rascunho", só na criação) ─────────────────

  Timer? _rascunhoTimer;
  String? _ultimoRascunho;
  bool _rascunhoGravado = false;

  /// Proposta criada: não regrava o rascunho (já foi apagado).
  bool _criada = false;

  /// Todo o formulário em texto (datas `yyyy-MM-dd`), com as mesmas chaves
  /// que [_aplicarRascunho] lê.
  Map<String, String> _camposRascunho() => {
        'proposalDate': _iso(_proposalDate),
        'validityDays': _validityDays.text,
        'proposedPrice': _proposedPrice.text,
        'commission': _commission.text,
        'downPayment': _downPayment.text,
        'downPaymentDays': _downPaymentDays.text,
        'deliveryDays': _deliveryDays.text,
        'monthlyPenalty': _monthlyPenalty.text,
        'paymentConditions': _paymentConditions.text,
        'teamId': _teamId,
        'saleUnit': _saleUnit,
        'captureUnit': _captureUnit,
        'observations': _observations,
        'buyerName': _buyerName.text,
        'buyerCpf': _buyerCpf.text,
        'buyerRg': _buyerRg.text,
        'buyerBirth': _iso(_buyerBirth),
        'buyerNationality': _buyerNationality.text,
        'buyerMarital': _buyerMarital,
        'buyerRegime': _buyerRegime,
        'buyerProfession': _buyerProfession.text,
        'buyerEmail': _buyerEmail.text,
        'buyerPhone': _buyerPhone.text,
        'buyerZip': _buyerZip.text,
        'buyerAddress': _buyerAddress.text,
        'buyerNeighborhood': _buyerNeighborhood.text,
        'buyerCity': _buyerCity.text,
        'buyerState': _buyerState,
        'bsName': _bsName.text,
        'bsCpf': _bsCpf.text,
        'bsRg': _bsRg.text,
        'bsProfession': _bsProfession.text,
        'bsPhone': _bsPhone.text,
        'bsEmail': _bsEmail.text,
        'propCode': _propCode.text,
        'propRegistry': _propRegistry.text,
        'propNotary': _propNotary.text,
        'propZip': _propZip.text,
        'propAddress': _propAddress.text,
        'propNeighborhood': _propNeighborhood.text,
        'propCity': _propCity.text,
        'propState': _propState,
        'ownerName': _ownerName.text,
        'ownerCpf': _ownerCpf.text,
        'ownerRg': _ownerRg.text,
        'ownerBirth': _iso(_ownerBirth),
        'ownerNationality': _ownerNationality.text,
        'ownerMarital': _ownerMarital,
        'ownerRegime': _ownerRegime,
        'ownerProfession': _ownerProfession.text,
        'ownerEmail': _ownerEmail.text,
        'ownerPhone': _ownerPhone.text,
        'ownerZip': _ownerZip.text,
        'ownerAddress': _ownerAddress.text,
        'ownerNeighborhood': _ownerNeighborhood.text,
        'ownerCity': _ownerCity.text,
        'ownerState': _ownerState,
        'osName': _osName.text,
        'osCpf': _osCpf.text,
        'osProfession': _osProfession.text,
        'osEmail': _osEmail.text,
        'osPhone': _osPhone.text,
        'osRg': _osRg,
      };

  Map<String, dynamic> _rascunhoData() => proposalDraftEncode(
        campos: _camposRascunho(),
        tab: _tabIndex,
        linkedUserIds: _linkedUserIds,
      );

  /// Devolve à tela o estado de [_rascunhoData] (chamado no `initState`).
  void _aplicarRascunho(Map<String, dynamic> raw) {
    final d = proposalDraftDecode(raw);
    String c(String k) => d.campo(k);
    _proposalDate = d.data('proposalDate');
    _validityDays.text = c('validityDays');
    _proposedPrice.text = c('proposedPrice');
    _commission.text = c('commission');
    _downPayment.text = c('downPayment');
    _downPaymentDays.text = c('downPaymentDays');
    _deliveryDays.text = c('deliveryDays');
    _monthlyPenalty.text = c('monthlyPenalty');
    _paymentConditions.text = c('paymentConditions');
    _teamId = c('teamId');
    _saleUnit = c('saleUnit');
    _captureUnit = c('captureUnit');
    _observations = c('observations');
    _buyerName.text = c('buyerName');
    _buyerCpf.text = c('buyerCpf');
    _buyerRg.text = c('buyerRg');
    _buyerBirth = d.nascimento('buyerBirth');
    _buyerNationality.text = c('buyerNationality');
    _buyerMarital = c('buyerMarital');
    _buyerRegime = c('buyerRegime');
    _buyerProfession.text = c('buyerProfession');
    _buyerEmail.text = c('buyerEmail');
    _buyerPhone.text = c('buyerPhone');
    _buyerZip.text = c('buyerZip');
    _buyerAddress.text = c('buyerAddress');
    _buyerNeighborhood.text = c('buyerNeighborhood');
    _buyerCity.text = c('buyerCity');
    _buyerState = c('buyerState');
    _bsName.text = c('bsName');
    _bsCpf.text = c('bsCpf');
    _bsRg.text = c('bsRg');
    _bsProfession.text = c('bsProfession');
    _bsPhone.text = c('bsPhone');
    _bsEmail.text = c('bsEmail');
    _propCode.text = c('propCode');
    _propRegistry.text = c('propRegistry');
    _propNotary.text = c('propNotary');
    _propZip.text = c('propZip');
    _propAddress.text = c('propAddress');
    _propNeighborhood.text = c('propNeighborhood');
    _propCity.text = c('propCity');
    _propState = c('propState');
    _ownerName.text = c('ownerName');
    _ownerCpf.text = c('ownerCpf');
    _ownerRg.text = c('ownerRg');
    _ownerBirth = d.nascimento('ownerBirth');
    _ownerNationality.text = c('ownerNationality');
    _ownerMarital = c('ownerMarital');
    _ownerRegime = c('ownerRegime');
    _ownerProfession.text = c('ownerProfession');
    _ownerEmail.text = c('ownerEmail');
    _ownerPhone.text = c('ownerPhone');
    _ownerZip.text = c('ownerZip');
    _ownerAddress.text = c('ownerAddress');
    _ownerNeighborhood.text = c('ownerNeighborhood');
    _ownerCity.text = c('ownerCity');
    _ownerState = c('ownerState');
    _osName.text = c('osName');
    _osCpf.text = c('osCpf');
    _osProfession.text = c('osProfession');
    _osEmail.text = c('osEmail');
    _osPhone.text = c('osPhone');
    _osRg = c('osRg');
    _linkedUserIds
      ..clear()
      ..addAll(d.linkedUserIds);
    if (d.tab != 0) {
      _tabIndex = d.tab;
      _tabCtrl.index = d.tab;
    }
    _ultimoRascunho = jsonEncode(_rascunhoData());
    _rascunhoGravado = true;
  }

  /// Grava se algo mudou; em branco não grava (e apaga o que havia). Um
  /// formulário novo em branco não apaga o rascunho anterior: ele só é
  /// substituído quando a proposta nova começa a ser preenchida (web).
  Future<void> _salvarRascunho() async {
    if (widget.isEditing || _criada || _saving) return;
    final data = _rascunhoData();
    final json = jsonEncode(data);
    if (json == _ultimoRascunho) return;
    _ultimoRascunho = json;
    if (proposalDraftIsBlank(
      _camposRascunho(),
      linkedUserIds: _linkedUserIds,
    )) {
      if (_rascunhoGravado) {
        _rascunhoGravado = false;
        await FichaDraftStore.instance.limpar(kProposalDraftTipo);
      }
      return;
    }
    _rascunhoGravado = true;
    await FichaDraftStore.instance.salvar(kProposalDraftTipo, data);
  }

  @override
  void dispose() {
    _rascunhoTimer?.cancel();
    // Saiu sem criar: guarda o último estado (o timer pode não ter rodado).
    if (!widget.isEditing && !_criada) _salvarRascunho();
    _scroll.dispose();
    _tabCtrl.dispose();
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
      _teamsError = teams.success ? null : (teams.message ?? '');
      _teamsStatus = teams.statusCode;
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
      _membersError = members.success ? null : (members.message ?? '');
      _membersStatus = members.statusCode;
      _loadingMembers = false;
      _currentUserId = uid;
    });
  }

  /// "Tentar de novo" das equipes (mesma chamada da abertura).
  Future<void> _reloadTeams() async {
    setState(() {
      _loadingTeams = true;
      _teamsError = null;
    });
    final res = await PurchaseProposalsService.instance.listTeamsForProposal();
    if (!mounted) return;
    setState(() {
      _teams = res.data ?? const [];
      _teamsError = res.success ? null : (res.message ?? '');
      _teamsStatus = res.statusCode;
      _loadingTeams = false;
    });
  }

  /// "Tentar de novo" dos usuários da etapa 3 (mesma chamada da abertura).
  Future<void> _reloadMembers() async {
    setState(() {
      _loadingMembers = true;
      _membersError = null;
    });
    final res = await PurchaseProposalsService.instance.listCompanyMembers();
    if (!mounted) return;
    setState(() {
      _members = res.data ?? const [];
      _membersError = res.success ? null : (res.message ?? '');
      _membersStatus = res.statusCode;
      _loadingMembers = false;
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
    // O back recusa o `PATCH` de excluída, finalizada e cancelada
    // (`purchase-proposals.service.ts`, `update`): não abre o formulário
    // (nem promete "reiniciar assinaturas" ao salvar).
    final bloqueio =
        proposalEdicaoBloqueada(status: p.status, deletedAt: p.deletedAt);
    if (bloqueio != null) {
      setState(() {
        _bloqueio = bloqueio;
        _bloqueadaExcluida = p.deletedAt != null;
        _bloqueadaPdfEtapa =
            p.status == ProposalStatus.finalized ? null : p.etapa.number;
        _loadedStatus = p.status;
        _proposalNumber =
            p.proposalNumber.isNotEmpty ? p.proposalNumber : widget.proposalId!;
        _loading = false;
      });
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

  /// `getReinicioDecision` do web (sem o ramo "proposta finalizada": a
  /// edição dela está bloqueada, ver [proposalEdicaoBloqueada]).
  ({bool needsReinicio, List<String> etapas}) _reinicioDecision() =>
      proposalReinicioDecision(
        atual1: _snapshot1(),
        carregado1: _loadedSnap1,
        atual2: _snapshot2(),
        carregado2: _loadedSnap2,
        concluidas: _concluidas,
      );

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
    // Web: `clearDraft()` depois de criar.
    _criada = true;
    _rascunhoTimer?.cancel();
    await FichaDraftStore.instance.limpar(kProposalDraftTipo);
    var falhaVinculo = false;
    if (created.id.isNotEmpty && _linkedUserIds.isNotEmpty) {
      final vinc = await PurchaseProposalsService.instance
          .addUsers(created.id, List.of(_linkedUserIds));
      falhaVinculo = !vinc.success;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    // O web engole a falha do vínculo (console.warn); aqui avisa, como a
    // ficha de venda do app (V15).
    _toast(falhaVinculo
        ? 'Ficha de proposta criada, mas não foi possível vincular os '
            'usuários. Tente de novo em "Usuários vinculados".'
        : 'Ficha de proposta criada com sucesso!');
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
      final ok = await _confirmReinicio(decision.etapas);
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
    var falhaVinculo = false;
    if (_linkedUserIds.isNotEmpty) {
      final vinc = await svc.addUsers(id, List.of(_linkedUserIds));
      falhaVinculo = !vinc.success;
    }
    if (!mounted) return;
    _toast(falhaVinculo
        ? 'Ficha de proposta atualizada, mas não foi possível vincular os '
            'usuários.'
        : 'Ficha de proposta atualizada com sucesso!');
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

  Future<bool?> _confirmReinicio(List<String> etapas) {
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
              const Text(
                'Você alterou dados de etapa(s) em que o fluxo já estava '
                'concluído (assinatura digital ou anexo aprovado):',
                style: TextStyle(height: 1.45),
              ),
              if (etapas.isNotEmpty) ...[
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
        actionsOverflowButtonSpacing: 8,
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
              // Invalida assinaturas: vermelho com texto branco (no escuro o
              // onPrimary padrão sairia preto).
              backgroundColor: _brand,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Salvar e reiniciar assinaturas',
                textAlign: TextAlign.center,
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

  String get _numeroOuId =>
      _proposalNumber.isNotEmpty ? _proposalNumber : widget.proposalId!;

  Future<void> _openSignaturesFromHeader([int? etapa]) async {
    await _openSignatures(
      id: widget.proposalId!,
      number: _numeroOuId,
      etapa: etapa ?? _etapa,
    );
    if (!mounted) return;
    final hist = await PurchaseProposalsService.instance
        .getHistorico(widget.proposalId!);
    if (!mounted || !hist.success || hist.data == null) return;
    setState(() => _maxLiberada = hist.data!.maxEtapaLiberadaParaEnvio ?? 1);
  }

  // ── CEP / busca de imóvel ───────────────────────────────────────────────

  /// `useCepAutofill` do web: [force] (a lupa) refaz o mesmo CEP; a busca
  /// automática não repete o CEP — salvo depois de o campo ficar incompleto
  /// ou de a busca falhar.
  Future<void> _buscarCep(
    String key,
    String cep, {
    required void Function(bool) setLoading,
    required void Function(CepAddress) apply,
    bool force = false,
  }) async {
    final gate = _cepGate(key);
    final clean = gate.gatilho(cep, force: force);
    if (clean == null) return;
    setState(() => setLoading(true));
    final addr = await CepService.instance.searchCep(clean);
    if (!mounted) return;
    setState(() => setLoading(false));
    if (addr == null) {
      gate.falhou();
      _toast(kProposalCepErro, error: true);
      return;
    }
    setState(() => apply(addr));
    _toast('Endereço preenchido pelo CEP.');
  }

  void _cepProponente({bool force = false}) => _buscarCep(
        'proponentZipCode',
        _buyerZip.text,
        force: force,
        setLoading: (v) => _cepBuyer = v,
        apply: (a) {
          _buyerAddress.text = a.street ?? '';
          _buyerNeighborhood.text = a.neighborhood ?? '';
          _buyerCity.text = a.city ?? '';
          _buyerState = (a.state ?? '').toUpperCase();
        },
      );

  void _cepImovel({bool force = false}) => _buscarCep(
        'propertyZipCode',
        _propZip.text,
        force: force,
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

  void _cepProprietario({bool force = false}) => _buscarCep(
        'ownerZipCode',
        _ownerZip.text,
        force: force,
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
      _toast('Nenhum imóvel encontrado com esse código.', info: true);
      return;
    }
    final picked = await showModalBottomSheet<ProposalPropertyHit>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _PropertyHitsSheet(hits: hits, code: code, accent: _brand),
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

  /// Volta ao começo do conteúdo. Na etapa 1 as abas ficam presas no topo,
  /// então o começo é logo abaixo delas — sem reabrir o trilho de etapas.
  void _scrollTop() {
    if (!_scroll.hasClients) return;
    final fixed = _etapa == 1 ? _headerExtent() : 0.0;
    _scrollTo(math.min(_scroll.offset, fixed));
  }

  void _scrollTo(double offset) {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      offset,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  double _headerExtent() {
    final box = _headerKey.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box.size.height : 0.0;
  }

  void _goEtapa(int n) {
    if (n > _maxLiberada) {
      _toast(
        n == 2
            ? 'A etapa 2 (proprietário) libera quando o comprador assinar.'
            : 'A etapa 3 (corretor) libera quando o proprietário assinar.',
        info: true,
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _etapa = n);
    _scrollTo(0);
  }

  void _goTab(int i) {
    FocusScope.of(context).unfocus();
    setState(() => _tab = i);
    _scrollTop();
  }

  void _toast(String msg, {bool error = false, bool info = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        // Verde só para o que deu certo e vermelho só para erro; aviso
        // (etapa travada, busca sem resultado) fica no tom neutro do app.
        backgroundColor: error
            ? AppColors.status.error
            : info
                ? null
                : AppColors.status.success,
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
    final err =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
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

  /// Margem lateral: 16 no celular; em tela larga o formulário vira uma
  /// coluna de até 720 centralizada (nada de campo esticado em 1000dp).
  static double _sidePad(double width) => width > _kMaxContentWidth + 32
      ? (width - _kMaxContentWidth) / 2
      : 16.0;

  /// Linha fina sob o título: em que etapa a pessoa está (e o número da
  /// proposta ao editar). Fica à vista mesmo com o trilho fora da tela.
  String get _appBarSubtitle {
    if (_loading) return 'Carregando proposta…';
    if (_bloqueio != null) return 'Somente leitura · nº $_numeroOuId';
    final hasNumber = widget.isEditing &&
        _proposalNumber.isNotEmpty &&
        _proposalNumber != widget.proposalId;
    return 'Etapa $_etapa de 3 · ${_kStageTitles[_etapa - 1]}'
        '${hasNumber ? ' · nº $_proposalNumber' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeHelpers.backgroundColor(context),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.isEditing ? 'Editar proposta' : 'Nova proposta',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 17,
                height: 1.15,
                color: ThemeHelpers.textColor(context),
              ),
            ),
            const SizedBox(height: 1),
            Text(
              _appBarSubtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.2,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
          ],
        ),
        elevation: 0,
        // Separação por filete (gramática flush), não por sombra ou tinta
        // ao rolar — as abas presas logo abaixo têm o próprio filete.
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
        backgroundColor: ThemeHelpers.appBarBackgroundColor(context),
        actions: [
          if (!_loading && _bloqueio == null && _canOpenSignatures)
            _signaturesAction(),
          if (!_loading && _bloqueio == null && widget.isEditing)
            _documentosMenu(),
        ],
      ),
      body: _loading
          ? const _FormSkeleton()
          : _bloqueio != null
              ? _EdicaoBloqueada(
                  motivo: _bloqueio!,
                  accent: _brand,
                  onHistorico: _abrirHistoricoBloqueada,
                  // Web: excluída não tem "Baixar PDF" no menu da linha.
                  onPdf: _bloqueadaExcluida ? null : _baixarPdfBloqueada,
                )
              : _buildBody(),
    );
  }

  /// Proposta que não edita: histórico (anexos + assinaturas) só leitura —
  /// o mesmo destino do toque na linha da lista.
  Future<void> _abrirHistoricoBloqueada() {
    return showProposalSignaturesSheet(
      context,
      proposalId: widget.proposalId!,
      proposalNumber: _numeroOuId,
      initialHistorico: true,
    );
  }

  /// O "Baixar PDF" do menu da linha: consolidado na finalizada, parcial da
  /// etapa atual nas demais.
  Future<void> _baixarPdfBloqueada() {
    return showProposalPdfSheet(
      context,
      proposalId: widget.proposalId!,
      numero: _numeroOuId,
      etapa: _bloqueadaPdfEtapa,
    );
  }

  /// Web (`CreatePurchaseProposalPage`, cabeçalho da edição): "Baixar PDF
  /// (Etapa N)" nas TRÊS etapas — inclusive a 3 e as ainda travadas — e
  /// "Assinaturas (Comprador/Proprietário)" nas etapas 1 e 2 já liberadas.
  Widget _documentosMenu() {
    return PopupMenuButton<String>(
      tooltip: 'PDF e assinaturas por etapa',
      icon: const Icon(LucideIcons.ellipsisVertical, size: 20),
      enabled: !_saving,
      onSelected: (v) {
        final n = int.parse(v.substring(1));
        if (v.startsWith('p')) {
          showProposalPdfSheet(
            context,
            proposalId: widget.proposalId!,
            numero: _numeroOuId,
            etapa: n,
          );
        } else {
          _openSignaturesFromHeader(n);
        }
      },
      itemBuilder: (_) => [
        for (final n in const [1, 2])
          if (n <= _maxLiberada)
            PopupMenuItem(
              value: 's$n',
              child: _MenuLinha(
                icon: LucideIcons.signature,
                text: n == 1
                    ? 'Assinaturas (Comprador)'
                    : 'Assinaturas (Proprietário)',
              ),
            ),
        if (_maxLiberada >= 1) const PopupMenuDivider(),
        for (final n in const [1, 2, 3])
          PopupMenuItem(
            value: 'p$n',
            child: _MenuLinha(
              icon: LucideIcons.fileDown,
              text: 'Baixar PDF (Etapa $n)',
            ),
          ),
      ],
    );
  }

  /// Assinaturas da etapa (edição): com rótulo quando cabe; só o ícone em
  /// tela estreita ou fonte grande.
  Widget _signaturesAction() {
    final tip = _etapa == 1
        ? 'Assinaturas do comprador'
        : 'Assinaturas do proprietário';
    final VoidCallback? onPressed =
        _saving ? null : _openSignaturesFromHeader;
    final wide = MediaQuery.sizeOf(context).width >=
        400 * MediaQuery.textScalerOf(context).scale(1);
    if (!wide) {
      return IconButton(
        tooltip: tip,
        onPressed: onPressed,
        icon: const Icon(LucideIcons.signature, size: 20),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: tip,
        child: TextButton.icon(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: ThemeHelpers.textColor(context),
          ),
          icon: const Icon(LucideIcons.signature, size: 18),
          label: const Text(
            'Assinaturas',
            maxLines: 1,
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return LayoutBuilder(
      builder: (context, c) {
        final pad = _sidePad(c.maxWidth);
        // Tela baixa com teclado aberto (landscape, aparelho pequeno): abas
        // e rodapé saem enquanto a pessoa digita, para o campo em foco não
        // ficar espremido, e voltam quando o teclado fecha. O formulário não
        // muda de lugar na árvore — o foco não se perde.
        final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
        final typingTight = keyboardOpen && c.maxHeight < 380;
        final showNav = c.maxHeight >= 140 && !typingTight;
        // Landscape/tela baixa: só o trilho (a etapa segue no título e o
        // motivo da trava aparece ao tocar na etapa travada).
        final compactHeader = c.maxHeight < 440;
        return Column(
          children: [
            Expanded(
              child: Theme(
                data: _formTheme(context),
                child: CustomScrollView(
                  controller: _scroll,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    // Trilho + resumo da etapa rolam com o formulário; na
                    // etapa 1 as abas ficam presas no topo.
                    SliverToBoxAdapter(
                      child: KeyedSubtree(
                        key: _headerKey,
                        child: _stageHeader(pad, compact: compactHeader),
                      ),
                    ),
                    if (_etapa == 1)
                      PinnedHeaderSliver(
                        child: typingTight
                            ? const SizedBox.shrink()
                            : _tabBar(pad),
                      ),
                    SliverPadding(
                      // Uma árvore por aba/etapa: campo de uma aba nunca
                      // herda foco ou estado do campo de outra.
                      key: ValueKey(
                          _etapa == 1 ? 'aba-$_tab' : 'etapa-$_etapa'),
                      padding: EdgeInsets.fromLTRB(pad, 16, pad, 28),
                      sliver: SliverList.list(
                        children: [
                          ..._errorSummary(),
                          ..._content(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (showNav) _navBar(pad) else const SizedBox.shrink(),
          ],
        );
      },
    );
  }

  /// Trilho das 3 etapas + o que acontece ao salvar esta e o que segue
  /// travado (e por quê).
  Widget _stageHeader(double pad, {bool compact = false}) {
    final done = [
      _maxLiberada >= 2,
      _maxLiberada >= 3,
      _loadedStatus == ProposalStatus.finalized,
    ];
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: pad, vertical: compact ? 8 : 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StageStepper(
            current: _etapa,
            maxLiberada: _maxLiberada,
            done: done,
            editing: widget.isEditing,
            accent: _brand,
            onTap: _goEtapa,
          ),
          if (!compact) ...[
            const SizedBox(height: 12),
            ..._stageBrief(),
          ],
        ],
      ),
    );
  }

  List<Widget> _stageBrief() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final next = switch (_etapa) {
      1 => widget.isEditing
          ? 'Ao salvar, abre o envio para o comprador assinar.'
          : 'Ao criar, abre o envio para o comprador assinar.',
      2 => 'Ao finalizar, abre o envio para o proprietário assinar.',
      _ => 'Ao finalizar, abre o envio para o corretor assinar.',
    };
    final String? lock = switch (_maxLiberada) {
      <= 1 => 'Etapas 2 e 3 liberam depois das assinaturas do comprador e '
          'do proprietário.',
      2 => 'A etapa 3 libera quando o proprietário assinar.',
      _ => null,
    };
    final concluded = widget.isEditing &&
        _etapa < 3 &&
        (_concluidas[_etapa] ?? false);
    return [
      _BriefLine(
        icon: LucideIcons.signature,
        iconColor: _brand,
        strong: true,
        text: next,
      ),
      if (concluded) ...[
        const SizedBox(height: 8),
        _BriefLine(
          icon: LucideIcons.triangleAlert,
          iconColor: isDark
              ? AppColors.message.warningTextDarkMode
              : AppColors.message.warningText,
          text: 'Esta etapa já foi concluída. Se alterar algum dado, será '
              'pedida confirmação e as assinaturas recomeçam.',
        ),
      ],
      if (lock != null) ...[
        const SizedBox(height: 8),
        _BriefLine(icon: LucideIcons.lock, text: lock),
      ],
    ];
  }

  /// Abas da etapa 1: TabBar com sublinhado (gramática do app), rolável
  /// para nunca cortar rótulo; o número vermelho diz quantos campos da aba
  /// precisam de revisão.
  Widget _tabBar(double pad) {
    // Material opaco (não Container): as abas ficam presas no topo com o
    // formulário passando por baixo, e o toque ainda mostra o ripple.
    return Material(
      color: ThemeHelpers.backgroundColor(context),
      shape: Border(
        bottom: BorderSide(color: ThemeHelpers.borderColor(context)),
      ),
      child: TabBar(
        controller: _tabCtrl,
        onTap: _goTab,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        padding: EdgeInsets.symmetric(horizontal: math.max(0.0, pad - 12)),
        labelPadding: const EdgeInsets.symmetric(horizontal: 12),
        labelColor: _brand,
        unselectedLabelColor: ThemeHelpers.textSecondaryColor(context),
        indicatorColor: _brand,
        dividerColor: Colors.transparent,
        labelStyle:
            const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
        unselectedLabelStyle:
            const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        tabs: [
          for (var i = 0; i < _kTabsEtapa1.length; i++)
            Tab(
              child: _TabLabel(
                text: _kTabsEtapa1[i].$1,
                errors: _tabErrorCount(i),
              ),
            ),
        ],
      ),
    );
  }

  int _tabErrorCount(int i) {
    final keys = switch (i) {
      0 => _kTab0Keys,
      1 => _kTab1Keys,
      2 => _kTab2Keys,
      _ => _kTab3Keys,
    };
    return _errors.keys.where(keys.contains).length;
  }

  /// "O que falta": depois de uma validação que falhou, o topo do conteúdo
  /// diz quantos campos revisar e em quais abas (cada uma vira atalho).
  List<Widget> _errorSummary() {
    if (_etapa == 3) return const [];
    var total = 0;
    var here = 0;
    final others = <(String, int, VoidCallback)>[];
    if (_etapa == 1) {
      for (var i = 0; i < _kTabsEtapa1.length; i++) {
        final n = _tabErrorCount(i);
        total += n;
        if (i == _tab) {
          here = n;
        } else if (n > 0) {
          others.add((_kTabsEtapa1[i].$1, n, () => _goTab(i)));
        }
      }
    } else {
      total = _errors.keys.where((k) => k.startsWith('owner')).length;
      here = total;
    }
    if (total == 0) return const [];
    return [_ErrorSummary(total: total, here: here, others: others)];
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

  /// Rótulo do CTA final: forma completa e forma curta (tela estreita).
  (String, String) get _submitLabels {
    if (!widget.isEditing) {
      return _etapa == 1
          ? ('Criar e enviar para assinatura', 'Criar e enviar')
          : ('Salvar', 'Salvar');
    }
    return switch (_etapa) {
      3 => ('Finalizar proposta', 'Finalizar'),
      2 => ('Finalizar etapa', 'Finalizar'),
      _ => ('Salvar alterações', 'Salvar'),
    };
  }

  static const _kCtaStyle =
      TextStyle(fontWeight: FontWeight.w900, fontSize: 15);
  static const _kBackStyle =
      TextStyle(fontWeight: FontWeight.w700, fontSize: 14);

  /// Escolhe o que cabe no rodapé medindo o texto real (com a escala de
  /// fonte do aparelho): os dois rótulos completos; senão o CTA na forma
  /// curta; só por último o "Anterior" vira apenas a seta.
  ({String label, bool iconBack}) _fitNav(
    double maxWidth,
    (String, String) labels, {
    required bool hasBack,
  }) {
    final scaler = MediaQuery.textScalerOf(context);
    final base = Theme.of(context).textTheme.labelLarge ?? const TextStyle();
    double measure(String text, TextStyle style) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: base.merge(style)),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final w = tp.width;
      tp.dispose();
      return w;
    }

    // Ícone 18 + vão 8 + padding 16×2, com folga de arredondamento.
    double cta(String text) => measure(text, _kCtaStyle) + 18 + 8 + 32 + 4;
    final backFull = measure('Anterior', _kBackStyle) + 16 + 8 + 28 + 4;
    const backIcon = 52.0;
    const gap = 10.0;
    for (final (label, iconBack) in [
      (labels.$1, false),
      (labels.$2, false),
      (labels.$1, true),
      (labels.$2, true),
    ]) {
      final back = hasBack ? (iconBack ? backIcon : backFull) + gap : 0.0;
      if (back + cta(label) <= maxWidth) {
        return (label: label, iconBack: hasBack && iconBack);
      }
    }
    return (label: labels.$2, iconBack: hasBack);
  }

  Widget _navBar(double pad) {
    final showNext = _etapa == 1 && _tab < _kTabsEtapa1.length - 1;
    final VoidCallback? back = _etapa == 1
        ? (_tab > 0 ? () => _goTab(_tab - 1) : null)
        : () => _goEtapa(_etapa - 1);
    final (String, String) labels = _saving
        ? ('Salvando…', 'Salvando…')
        : showNext
            // Diz para onde vai (quando cabe): "Próximo: Proponente".
            ? ('Próximo: ${_kTabsEtapa1[_tab + 1].$1}', 'Próximo')
            : _submitLabels;
    final backStyle = OutlinedButton.styleFrom(
      // Neutro — voltar não é ação de marca.
      foregroundColor: ThemeHelpers.textSecondaryColor(context),
      side: BorderSide(color: ThemeHelpers.borderColor(context)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      minimumSize: const Size(52, 50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          top: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
          pad, 10, pad, 10 + MediaQuery.paddingOf(context).bottom),
      child: LayoutBuilder(
        builder: (context, c) {
          final fit = _fitNav(c.maxWidth, labels, hasBack: back != null);
          return Row(
            children: [
              if (back != null) ...[
                if (fit.iconBack)
                  Tooltip(
                    message: 'Anterior',
                    child: OutlinedButton(
                      onPressed: _saving ? null : back,
                      style: backStyle.copyWith(
                        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                      ),
                      child: const Icon(LucideIcons.arrowLeft, size: 18),
                    ),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _saving ? null : back,
                    style: backStyle,
                    icon: const Icon(LucideIcons.arrowLeft, size: 16),
                    label: const Text(
                      'Anterior',
                      maxLines: 1,
                      softWrap: false,
                      style: _kBackStyle,
                    ),
                  ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: _saving
                      ? null
                      : (showNext ? () => _goTab(_tab + 1) : _submit),
                  style: FilledButton.styleFrom(
                    backgroundColor: _brand,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _brand.withValues(alpha: 0.55),
                    disabledForegroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    minimumSize: const Size(0, 50),
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
                            showNext
                                ? LucideIcons.arrowRight
                                : LucideIcons.check,
                            size: 18,
                            color: Colors.white,
                          ),
                        const SizedBox(width: 8),
                        Text(
                          fit.label,
                          maxLines: 1,
                          softWrap: false,
                          style: _kCtaStyle.copyWith(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
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
    TextInputAction? action,
    ValueChanged<String>? onSubmitted,
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
      action: action,
      onSubmitted: onSubmitted,
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
    required void Function({bool force}) onSearch,
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
        // A lupa força a busca mesmo com o mesmo CEP (web `force: true`).
        onTap: () => onSearch(force: true),
      ),
      onChanged: (v) {
        setState(() {});
        // `useCepAutofill`: dispara sozinho ao completar 8 dígitos; o
        // gatilho ([ProposalCepGate]) não repete o mesmo CEP, mas libera
        // depois de apagar/redigitar ou de uma falha.
        onSearch();
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
        // Web: o asterisco aparece sempre (`Label className='required'`),
        // embora a validação só cobre ao criar.
        required: true,
        hint: _loadingTeams
            ? 'Carregando equipes…'
            : _teams.isEmpty
                ? 'Nenhuma equipe disponível'
                : 'Selecione',
        helper: !_loadingTeams && _teams.isEmpty && _teamsError == null
            ? 'Nenhuma equipe está habilitada para fichas. Peça a um gestor '
                'para habilitar a sua.'
            : 'Equipe responsável por esta proposta no dashboard e nos '
                'rankings.',
        unknownLabel: (_) => 'Equipe indisponível',
      ),
      if (_teamsError != null && !_loadingTeams)
        _InlineError(
          what: 'as equipes',
          cause: ErrorCause.fromApi(
            message: _teamsError,
            statusCode: _teamsStatus,
          ),
          onRetry: _reloadTeams,
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
        helper: 'Descreva tudo o que foi combinado: entrada, financiamento, '
            'prazos. Até 2000 caracteres.',
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
          left: _text('proponentProfession', 'Profissão', _buyerProfession,
              caps: TextCapitalization.sentences),
          right: _select('proponentMaritalStatus', 'Estado civil',
              _buyerMarital, kProposalMaritalStatus, (v) => _buyerMarital = v,
              hint: 'Selecione'),
        ),
        // Largura inteira: o nome do regime é longo e precisa ser lido.
        _select('proponentMarriageRegime', 'Regime de casamento',
            _buyerRegime, kProposalMarriageRegime, (v) => _buyerRegime = v,
            hint: 'Selecione'),
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
        const _Caption('Preencha só se o proponente for casado(a) ou viver em '
            'união estável.'),
        const SizedBox(height: 6),
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
          // A tecla "buscar" do teclado faz o mesmo que a lupa.
          action: TextInputAction.search,
          onSubmitted: (_) => _buscarImovelPorCodigo(),
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
          left: _text('ownerProfession', 'Profissão', _ownerProfession,
              caps: TextCapitalization.sentences),
          right: _select('ownerMaritalStatus', 'Estado civil', _ownerMarital,
              kProposalMaritalStatus, (v) => _ownerMarital = v,
              hint: 'Selecione'),
        ),
        _select('ownerMarriageRegime', 'Regime de casamento', _ownerRegime,
            kProposalMarriageRegime, (v) => _ownerRegime = v,
            hint: 'Selecione'),
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
        const _Caption('Preencha só se o proprietário for casado(a) ou viver '
            'em união estável.'),
        const SizedBox(height: 6),
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
    final Widget people;
    if (_membersError != null && !_loadingMembers) {
      people = AppErrorState.fromApi(
        message: _membersError,
        statusCode: _membersStatus,
        onRetry: _reloadMembers,
        dense: true,
      );
    } else if (_loadingMembers && _linkedUserIds.isNotEmpty) {
      people = Column(
        children: [
          for (var i = 0; i < math.min(_linkedUserIds.length, 3); i++)
            const _LinkedUserSkeleton(),
        ],
      );
    } else if (_linkedUserIds.isEmpty) {
      people = _EmptyLinked(accent: _brand);
    } else {
      people = Column(
        children: [
          for (final id in _linkedUserIds)
            _LinkedUserRow(
              name: byId[id]?.name ?? 'Usuário',
              email: byId[id]?.email,
              accent: _brand,
              onRemove: () => setState(() => _linkedUserIds.remove(id)),
            ),
        ],
      );
    }
    return [
      const _Band('QUEM MAIS PODE VER ESTA PROPOSTA', LucideIcons.userPlus),
      Text(
        'Selecione os usuários que terão acesso a esta proposta. Você '
        '(criador) já está vinculado automaticamente.',
        style: TextStyle(color: muted, height: 1.4, fontSize: 13.5),
      ),
      const SizedBox(height: 16),
      _CapacityLine(
        used: _linkedUserIds.length,
        max: _kMaxLinkedUsers,
        accent: _brand,
      ),
      const SizedBox(height: 6),
      people,
      const SizedBox(height: 14),
      _AddUserButton(
        accent: _brand,
        full: full,
        enabled: !full && !_loadingMembers && _membersError == null,
        onTap: _pickLinkedUser,
      ),
      if (full) ...[
        const SizedBox(height: 10),
        const _BriefLine(
          icon: LucideIcons.lock,
          text: 'Limite de $_kMaxLinkedUsers usuários com acesso. Remova '
              'alguém para adicionar outra pessoa.',
        ),
      ],
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

// ─── Trilho de etapas ───────────────────────────────────────────────────────

/// As 3 etapas como fluxo (não como aba — as abas da etapa 1 vêm logo
/// abaixo, com sublinhado): nó numerado ligado por um fio que fica verde
/// quando a etapa da esquerda foi concluída, nome de quem assina e o estado
/// em palavras (Preenchendo, Em edição, Concluída, Liberada, Travada).
class _StageStepper extends StatelessWidget {
  const _StageStepper({
    required this.current,
    required this.maxLiberada,
    required this.done,
    required this.editing,
    required this.accent,
    required this.onTap,
  });

  final int current;
  final int maxLiberada;

  /// Etapas concluídas (índice 0 = etapa 1).
  final List<bool> done;
  final bool editing;
  final Color accent;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var n = 1; n <= 3; n++)
          Expanded(
            child: _StageNode(
              number: n,
              title: _kStageTitles[n - 1],
              selected: current == n,
              locked: n > maxLiberada,
              done: done[n - 1],
              editing: editing,
              lineBefore: n == 1 ? null : done[n - 2],
              lineAfter: n == 3 ? null : done[n - 1],
              accent: accent,
              onTap: () => onTap(n),
            ),
          ),
      ],
    );
  }
}

class _StageNode extends StatelessWidget {
  const _StageNode({
    required this.number,
    required this.title,
    required this.selected,
    required this.locked,
    required this.done,
    required this.editing,
    required this.lineBefore,
    required this.lineAfter,
    required this.accent,
    required this.onTap,
  });

  final int number;
  final String title;
  final bool selected;
  final bool locked;
  final bool done;
  final bool editing;

  /// Fio até o nó vizinho: null = não há; true = trecho já concluído.
  final bool? lineBefore;
  final bool? lineAfter;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final border = ThemeHelpers.borderColor(context);
    final ok = AppColors.status.success;

    final String state;
    final Color stateColor;
    if (done) {
      state = 'Concluída';
      stateColor = isDark
          ? AppColors.message.successTextDarkMode
          : AppColors.message.successText;
    } else if (locked) {
      state = 'Travada';
      stateColor = muted;
    } else if (selected) {
      state = editing ? 'Em edição' : 'Preenchendo';
      stateColor = accent;
    } else {
      state = 'Liberada';
      stateColor = muted;
    }

    // Marca = onde a pessoa está; verde = concluída; contorno na marca =
    // liberada; contorno neutro com cadeado = travada.
    final filled = selected || done;
    final fill = selected ? accent : (done ? ok : Colors.transparent);
    final ink = filled ? Colors.white : (locked ? muted : accent);
    final Widget glyph = done
        ? Icon(LucideIcons.check, size: 15, color: ink)
        : locked
            ? Icon(LucideIcons.lock, size: 13, color: ink)
            : Text(
                '$number',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  color: ink,
                ),
              );

    Widget line(bool? concluded, EdgeInsets gap) => Expanded(
          child: concluded == null
              ? const SizedBox.shrink()
              : Container(
                  height: 2,
                  margin: gap,
                  color: concluded ? ok.withValues(alpha: 0.8) : border,
                ),
        );

    Widget fitted(Widget child) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: FittedBox(fit: BoxFit.scaleDown, child: child),
        );

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: 'Etapa $number, $title, ${state.toLowerCase()}',
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 30,
                child: Row(
                  children: [
                    line(lineBefore, const EdgeInsets.only(right: 6)),
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: fill,
                        shape: BoxShape.circle,
                        border: filled
                            ? null
                            : Border.all(
                                color: locked ? border : accent,
                                width: 1.6,
                              ),
                      ),
                      child: glyph,
                    ),
                    line(lineAfter, const EdgeInsets.only(left: 6)),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              fitted(
                Text(
                  title,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                    color: selected ? ThemeHelpers.textColor(context) : muted,
                  ),
                ),
              ),
              const SizedBox(height: 1),
              fitted(
                Text(
                  state,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: stateColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Linha do resumo da etapa: ícone + frase curta.
class _BriefLine extends StatelessWidget {
  const _BriefLine({
    required this.icon,
    required this.text,
    this.iconColor,
    this.strong = false,
  });

  final IconData icon;
  final String text;
  final Color? iconColor;

  /// Frase principal (cor de texto); as demais ficam no tom secundário.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 14, color: iconColor ?? muted),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
              color: strong ? ThemeHelpers.textColor(context) : muted,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Abas da etapa 1 ────────────────────────────────────────────────────────

class _TabLabel extends StatelessWidget {
  const _TabLabel({required this.text, required this.errors});
  final String text;
  final int errors;

  @override
  Widget build(BuildContext context) {
    // TabBar rolável: largura livre, então nada de Flexible aqui.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, maxLines: 1, softWrap: false),
        if (errors > 0) ...[
          const SizedBox(width: 6),
          _CountBadge(count: errors),
        ],
      ],
    );
  }
}

/// Contagem estática (sem pulsar) de campos a revisar numa aba.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: count == 1 ? '1 campo para revisar' : '$count campos para revisar',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 18),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.status.error,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '$count',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

// ─── O que falta ────────────────────────────────────────────────────────────

/// Resumo no topo depois de uma validação que falhou: quantos campos, onde
/// estão, e um atalho para cada aba com problema.
class _ErrorSummary extends StatelessWidget {
  const _ErrorSummary({
    required this.total,
    required this.here,
    required this.others,
  });

  final int total;

  /// Campos com erro na aba (ou etapa) aberta.
  final int here;

  /// Outras abas com erro: (nome, quantidade, ir para a aba).
  final List<(String, int, VoidCallback)> others;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final String detail;
    if (here > 0 && others.isEmpty) {
      detail = 'Os campos com problema estão marcados em vermelho abaixo.';
    } else if (here > 0) {
      detail = 'Estão marcados em vermelho abaixo e também nas abas:';
    } else {
      detail = 'Esta aba está certa. Falta revisar:';
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: tone, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(LucideIcons.circleAlert, size: 16, color: tone),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  total == 1
                      ? 'Revise 1 campo para continuar'
                      : 'Revise $total campos para continuar',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 3),
            child: Text(
              detail,
              style: TextStyle(fontSize: 12.5, height: 1.35, color: muted),
            ),
          ),
          if (others.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in others)
                    _JumpChip(
                      label: '${o.$1} · ${o.$2}',
                      tone: tone,
                      onTap: o.$3,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _JumpChip extends StatelessWidget {
  const _JumpChip({
    required this.label,
    required this.tone,
    required this.onTap,
  });

  final String label;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: tone.withValues(alpha: isDark ? 0.16 : 0.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tone,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(LucideIcons.arrowRight, size: 13, color: tone),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Avisos ─────────────────────────────────────────────────────────────────

/// Proposta que o back não deixa editar (finalizada, cancelada, excluída):
/// no lugar do formulário, o motivo e o que dá para fazer — ver o histórico
/// e baixar o PDF. Vale para qualquer entrada (lista, rota, deep link).
class _EdicaoBloqueada extends StatelessWidget {
  const _EdicaoBloqueada({
    required this.motivo,
    required this.accent,
    required this.onHistorico,
    this.onPdf,
  });

  final String motivo;
  final Color accent;
  final VoidCallback onHistorico;
  final VoidCallback? onPdf;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: muted.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: muted.withValues(alpha: 0.22)),
                ),
                child: Icon(LucideIcons.fileLock, size: 25, color: muted),
              ),
              const SizedBox(height: 16),
              Text(
                motivo,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Os dados ficam como foram registrados. Você ainda pode ver '
                'o histórico das assinaturas e baixar o PDF.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, height: 1.45, color: muted),
              ),
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: onHistorico,
                    icon: const Icon(LucideIcons.history, size: 17),
                    label: const Text('Ver histórico'),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (onPdf != null)
                    OutlinedButton.icon(
                      onPressed: onPdf,
                      icon: const Icon(LucideIcons.fileDown, size: 17),
                      label: const Text('Baixar PDF'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: ThemeHelpers.textColor(context),
                        side: BorderSide(
                          color: ThemeHelpers.borderColor(context),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle:
                            const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Linha do menu "PDF e assinaturas por etapa" da edição.
class _MenuLinha extends StatelessWidget {
  const _MenuLinha({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: ThemeHelpers.textSecondaryColor(context)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// Falha ao carregar um catálogo da ficha (equipes): a causa real e o
/// "Tentar de novo" ali mesmo, sem tirar a pessoa do formulário.
class _InlineError extends StatelessWidget {
  const _InlineError({
    required this.what,
    required this.cause,
    required this.onRetry,
  });

  /// O que não carregou ("as equipes").
  final String what;
  final ErrorCause cause;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: cause.tone, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(cause.icon, size: 15, color: cause.tone),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Não foi possível carregar $what · ${cause.title}',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 23, top: 3),
            child: Text(
              cause.cause,
              style: TextStyle(fontSize: 12, height: 1.35, color: muted),
            ),
          ),
          if (cause.retryable)
            Padding(
              padding: const EdgeInsets.only(left: 11),
              child: TextButton.icon(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: cause.tone,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: const Size(0, 36),
                ),
                icon: const Icon(LucideIcons.rotateCw, size: 14),
                label: const Text(
                  'Tentar de novo',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
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

/// Duas colunas quando cabem (largura × escala de fonte do aparelho); em
/// tela estreita ou fonte grande empilha — CPF/CNPJ, telefone e valores em
/// R$ nunca ficam espremidos nem cortados dentro do campo.
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
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 320 * scale) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: leftFlex, child: left),
            const SizedBox(width: 12),
            Expanded(flex: rightFlex, child: right),
          ],
        );
      },
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
    this.action,
    this.onSubmitted,
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
  final TextInputAction? action;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    // Visual (filled, sem borda, foco na marca) herdado do _formTheme.
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: maxLines > 1 ? TextInputType.multiline : keyboard,
        // "Próximo" no teclado leva ao campo seguinte (menos toques).
        textInputAction: action ??
            (maxLines > 1 ? TextInputAction.newline : TextInputAction.next),
        onSubmitted: onSubmitted,
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
    // Uma opção por valor (duas unidades com o mesmo nome derrubariam o
    // DropdownButton, que exige exatamente um item com o valor atual).
    final seen = <String>{};
    final items = <(String, String)>[
      for (final o in options)
        if (seen.add(o.$1)) o,
    ];
    // Valor salvo fora da lista (legado, unidade desativada, equipe sem
    // acesso): mantém e mostra, como o web — nunca descarta o dado.
    if (value.isNotEmpty && !seen.contains(value)) {
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
        menuMaxHeight: 380,
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
        // No campo, uma linha com reticências; no menu, a opção longa
        // quebra em até 2 linhas (fonte grande, tela estreita) e é lida
        // inteira antes da escolha.
        selectedItemBuilder: (context) => [
          for (final o in items)
            Text(o.$2, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
        items: [
          for (final o in items)
            DropdownMenuItem(
              value: o.$1,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(o.$2,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
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

// ─── Etapa 3: quem pode ver a proposta ──────────────────────────────────────

/// Quantas pessoas já têm acesso: número em destaque + filete de lotação.
class _CapacityLine extends StatelessWidget {
  const _CapacityLine({
    required this.used,
    required this.max,
    required this.accent,
  });

  final int used;
  final int max;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final full = used >= max;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final warn = isDark
        ? AppColors.message.warningTextDarkMode
        : AppColors.message.warningText;
    final frac = max <= 0 ? 0.0 : math.min(1.0, used / max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$used',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                height: 1.1,
                color: full ? warn : ThemeHelpers.textColor(context),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                full
                    ? 'de $max · limite atingido'
                    : 'de $max usuários com acesso',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: muted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 4,
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(3),
          ),
          child: FractionallySizedBox(
            widthFactor: frac,
            child: Container(
              decoration: BoxDecoration(
                color: full ? warn : accent,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Linha de quem tem acesso: nome, e-mail (desfaz homônimos) e remover ali
/// mesmo. Linha flush com filete, como as listas do app.
class _LinkedUserRow extends StatelessWidget {
  const _LinkedUserRow({
    required this.name,
    required this.email,
    required this.accent,
    required this.onRemove,
  });

  final String name;
  final String? email;
  final Color accent;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final mail = (email ?? '').trim();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: accent.withValues(alpha: 0.12),
            child: Text(
              initial,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                if (mail.isNotEmpty)
                  Text(
                    mail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remover',
            onPressed: onRemove,
            icon: Icon(LucideIcons.x, size: 18, color: muted),
          ),
        ],
      ),
    );
  }
}

class _LinkedUserSkeleton extends StatelessWidget {
  const _LinkedUserSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: const Row(
        children: [
          SkeletonBox(width: 34, height: 34, borderRadius: 17),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 140, height: 12, borderRadius: 6),
                SizedBox(height: 6),
                SkeletonBox(width: 180, height: 10, borderRadius: 5),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Vazio que ensina: o que aparece aqui e como chegar lá.
class _EmptyLinked extends StatelessWidget {
  const _EmptyLinked({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.18 : 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(LucideIcons.users, size: 18, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nenhum usuário adicionado',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Adicione quem também precisa acompanhar esta proposta: '
                  'cada pessoa adicionada passa a ter acesso a ela.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Adicionar usuário" no desenho do botão de adicionar da ficha de venda;
/// no limite, travado com cadeado (o motivo vem logo abaixo).
class _AddUserButton extends StatelessWidget {
  const _AddUserButton({
    required this.accent,
    required this.enabled,
    required this.full,
    required this.onTap,
  });

  final Color accent;
  final bool enabled;
  final bool full;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = enabled ? accent : ThemeHelpers.textSecondaryColor(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: c.withValues(alpha: enabled ? 0.45 : 0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                full ? LucideIcons.lock : LucideIcons.userPlus,
                size: 16,
                color: c,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Adicionar usuário',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Folhas (bottom sheets) ─────────────────────────────────────────────────

/// Moldura das folhas: teto de 88% da altura, título à esquerda e fechar à
/// direita, sobe junto com o teclado, e o corpo rola — não estoura em
/// landscape nem em tela baixa.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.title,
    this.subtitle,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.88),
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
            16, 8, 8, 8 + (keyboard > 0 ? 0 : mq.padding.bottom)),
        // Material transparente: o toque nas linhas aparece por cima do
        // fundo da folha.
        child: Material(
          type: MaterialType.transparency,
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
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: ThemeHelpers.textColor(context),
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.35,
                                color: muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(LucideIcons.x, size: 18, color: muted),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: child,
                ),
              ),
            ],
          ),
        ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty
        ? widget.members
        : widget.members
            .where((m) =>
                m.name.toLowerCase().contains(q) ||
                (m.email ?? '').toLowerCase().contains(q))
            .toList();
    OutlineInputBorder border(Color? c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: c == null
              ? BorderSide.none
              : BorderSide(color: c, width: 1.6),
        );
    // A busca rola junto com a lista: em landscape com teclado aberto só o
    // título fica fixo, e a folha nunca estoura.
    final search = Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: TextField(
        onChanged: (v) => setState(() => _q = v),
        cursorColor: widget.accent,
        textInputAction: TextInputAction.search,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: ThemeHelpers.textColor(context),
        ),
        decoration: InputDecoration(
          hintText: 'Buscar por nome ou e-mail',
          prefixIcon: Icon(LucideIcons.search, size: 18, color: muted),
          isDense: true,
          filled: true,
          fillColor: isDark
              ? Colors.white.withValues(alpha: 0.045)
              : Colors.black.withValues(alpha: 0.03),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          border: border(null),
          enabledBorder: border(null),
          focusedBorder: border(widget.accent),
        ),
      ),
    );
    final total = widget.members.length;
    return _SheetFrame(
      title: 'Adicionar usuário',
      subtitle: total == 0
          ? null
          : total == 1
              ? '1 pessoa disponível'
              : '$total pessoas disponíveis',
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: 1 + (list.isEmpty ? 1 : list.length),
        itemBuilder: (context, i) {
          if (i == 0) return search;
          if (list.isEmpty) return _PickerEmpty(query: _q.trim());
          final m = list[i - 1];
          return _MemberTile(
            member: m,
            accent: widget.accent,
            onTap: () => Navigator.of(context).pop(m),
          );
        },
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.accent,
    required this.onTap,
  });

  final ProposalMember member;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final name = member.name.trim();
    final email = (member.email ?? '').trim();
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: accent.withValues(alpha: 0.12),
              child: Text(
                name.isEmpty ? '?' : name[0].toUpperCase(),
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  if (email.isNotEmpty)
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(LucideIcons.plus, size: 18, color: accent),
          ],
        ),
      ),
    );
  }
}

class _PickerEmpty extends StatelessWidget {
  const _PickerEmpty({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final searching = query.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 8),
      child: Column(
        children: [
          Icon(
            searching ? LucideIcons.searchX : LucideIcons.users,
            size: 22,
            color: muted,
          ),
          const SizedBox(height: 8),
          Text(
            searching
                ? 'Ninguém encontrado para “$query”'
                : 'Não há mais ninguém para adicionar',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            searching
                ? 'Confira a grafia ou busque pelo e-mail.'
                : 'Todos os usuários da empresa já têm acesso a esta proposta.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, height: 1.4, color: muted),
          ),
        ],
      ),
    );
  }
}

class _PropertyHitsSheet extends StatelessWidget {
  const _PropertyHitsSheet({
    required this.hits,
    required this.code,
    required this.accent,
  });

  final List<ProposalPropertyHit> hits;

  /// O código buscado (eco no cabeçalho).
  final String code;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final n = hits.length;
    return _SheetFrame(
      title: 'Imóveis encontrados',
      subtitle: n == 1
          ? '1 imóvel com o código “$code”. Toque para usar os dados dele.'
          : '$n imóveis com o código “$code”. Toque no certo para usar os '
              'dados dele.',
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: n,
        itemBuilder: (context, i) => _PropertyHitTile(
          hit: hits[i],
          accent: accent,
          onTap: () => Navigator.of(context).pop(hits[i]),
        ),
      ),
    );
  }
}

/// Um imóvel da busca: código, rua e bairro · cidade/UF · CEP — o bastante
/// para escolher o certo sem abrir nada.
class _PropertyHitTile extends StatelessWidget {
  const _PropertyHitTile({
    required this.hit,
    required this.accent,
    required this.onTap,
  });

  final ProposalPropertyHit hit;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final h = hit;
    final title =
        h.code.isEmpty || h.code == h.id ? 'Imóvel sem código' : h.code;
    final street =
        h.address.isNotEmpty ? h.address : 'Endereço não informado';
    final place = [
      if (h.neighborhood.isNotEmpty) h.neighborhood,
      if (h.city.isNotEmpty)
        h.state.isNotEmpty ? '${h.city}/${h.state}' : h.city,
      if (h.zipCode.isNotEmpty) 'CEP ${ProposalRules.maskCep(h.zipCode)}',
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: isDark ? 0.18 : 0.10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(LucideIcons.house, size: 18, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    street,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.3,
                      fontWeight: FontWeight.w500,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  if (place.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      place,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, height: 1.3, color: muted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Icon(LucideIcons.chevronRight, size: 18, color: muted),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Skeleton de carregamento ───────────────────────────────────────────────

/// Espelha a tela carregada: trilho das 3 etapas, resumo, abas e campos —
/// na mesma coluna (720 em tela larga) e sem o resumo em tela baixa.
class _FormSkeleton extends StatelessWidget {
  const _FormSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget node() => const Column(
          children: [
            SkeletonBox(width: 30, height: 30, borderRadius: 15),
            SizedBox(height: 8),
            SkeletonBox(width: 72, height: 11, borderRadius: 5),
            SizedBox(height: 5),
            SkeletonBox(width: 52, height: 9, borderRadius: 5),
          ],
        );
    Widget pair() => const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Expanded(child: SkeletonBox(height: 50, borderRadius: 14)),
              SizedBox(width: 12),
              Expanded(child: SkeletonBox(height: 50, borderRadius: 14)),
            ],
          ),
        );
    final hairline =
        Container(height: 1, color: ThemeHelpers.borderLightColor(context));
    return LayoutBuilder(
      builder: (context, c) {
        final pad = _CreateProposalPageState._sidePad(c.maxWidth);
        final compact = c.maxHeight < 440;
        return ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                  pad, compact ? 10 : 18, pad, compact ? 10 : 14),
              child: Row(
                children: [
                  Expanded(child: node()),
                  Expanded(child: node()),
                  Expanded(child: node()),
                ],
              ),
            ),
            if (!compact)
              Padding(
                padding: EdgeInsets.fromLTRB(pad, 0, pad, 14),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(height: 11, borderRadius: 5),
                    SizedBox(height: 7),
                    SkeletonBox(width: 200, height: 11, borderRadius: 5),
                  ],
                ),
              ),
            hairline,
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 16, pad, 14),
              child: const Row(
                children: [
                  Expanded(
                      flex: 4,
                      child: SkeletonBox(height: 12, borderRadius: 6)),
                  SizedBox(width: 22),
                  Expanded(
                      flex: 5,
                      child: SkeletonBox(height: 12, borderRadius: 6)),
                  SizedBox(width: 22),
                  Expanded(
                      flex: 4,
                      child: SkeletonBox(height: 12, borderRadius: 6)),
                  SizedBox(width: 22),
                  Expanded(
                      flex: 3,
                      child: SkeletonBox(height: 12, borderRadius: 6)),
                ],
              ),
            ),
            hairline,
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 20, pad, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonBox(width: 140, height: 12, borderRadius: 6),
                  const SizedBox(height: 16),
                  pair(),
                  pair(),
                  pair(),
                  pair(),
                  const SkeletonBox(height: 50, borderRadius: 14),
                  const SizedBox(height: 12),
                  const SkeletonBox(height: 96, borderRadius: 14),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
